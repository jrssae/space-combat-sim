// The big hulls' surfaces (M7-T06): nearest points, the segment sweep and the drum's skin velocity.
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::{Basis, Vector3};

use super::*;
use crate::rows::{ROLE_SURFACE, Rows, Surface};

// A box of half extents `half` at `centre`, axis-aligned, packed as `set_surface` takes it.
fn packed_box(centre: [f64; 3], half: [f64; 3]) -> Vec<f64> {
    vec![
        0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, centre[0], centre[1], centre[2], half[0],
        half[1], half[2],
    ]
}

// A capsule along y: half segment `h`, radius `r`, at `centre`.
fn packed_capsule(centre: [f64; 3], h: f64, r: f64) -> Vec<f64> {
    vec![
        1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, centre[0], centre[1], centre[2], h, r,
        0.0,
    ]
}

// A tunnel 94 m wide and 34 m tall along z, walls 10 m thick, 200 m long: the docking bay's shape, roughly.
fn tunnel() -> Surface {
    let mut p = Vec::new();
    p.extend(packed_box([0.0, 22.0, 0.0], [57.0, 5.0, 100.0])); // roof
    p.extend(packed_box([0.0, -22.0, 0.0], [57.0, 5.0, 100.0])); // floor
    p.extend(packed_box([52.0, 0.0, 0.0], [5.0, 17.0, 100.0])); // starboard wall
    p.extend(packed_box([-52.0, 0.0, 0.0], [5.0, 17.0, 100.0])); // port wall
    from_packed(&p, 0.0)
}

// One row holding `surface`, at `at` turned by `basis`.
fn row_with(surface: Surface, at: Vector3, basis: Basis) -> Rows {
    let mut map = HashMap::new();
    map.insert(7_i64, Arc::new(surface));
    Rows {
        body_ids: vec![7],
        ids: vec![7],
        positions: vec![at],
        velocities: vec![Vector3::ZERO],
        bases: vec![basis],
        radii: vec![150.0],
        rigid: vec![false],
        is_static: vec![false],
        faction_ix: vec![0],
        roles: vec![ROLE_SURFACE],
        surfaces: Some(Arc::new(map)),
        ..Rows::default()
    }
}

#[test]
fn a_packed_surface_keeps_its_volumes_and_drops_broken_ones() {
    let mut p = packed_box([0.0, 0.0, 0.0], [1.0, 2.0, 2.0]);
    p.extend(packed_capsule([0.0, 10.0, 0.0], 3.0, 1.0));
    let mut broken = packed_box([0.0, 0.0, 0.0], [1.0, 1.0, 1.0]);
    broken[12] = f64::NAN;
    p.extend(broken);
    p.extend([1.0, 2.0]); // a short tail
    let s = from_packed(&p, 0.148);
    assert_eq!(s.volumes.len(), 2);
    assert!(!s.volumes[0].capsule && s.volumes[1].capsule);
    assert!((s.volumes[0].reach - 3.0).abs() < 1e-12);
    assert!((s.volumes[1].reach - 4.0).abs() < 1e-12);
    assert_eq!(s.spin_rad_s, 0.148);
}

#[test]
fn the_nearest_point_is_on_the_nearest_volume() {
    let s = tunnel();
    // In the middle of the tunnel the floor and roof are 17 m off, the walls 47 m.
    let (d, p, k) = nearest(&s, [0.0, 0.0, 0.0]).unwrap();
    assert!((d - 17.0).abs() < 1e-9, "{d}");
    assert!(k == 0 || k == 1);
    assert!((p[1].abs() - 17.0).abs() < 1e-9);
    // Near the starboard wall it is the wall.
    let (d, p, k) = nearest(&s, [40.0, 0.0, 10.0]).unwrap();
    assert_eq!(k, 2);
    assert!((d - 7.0).abs() < 1e-9);
    assert_eq!(p, [47.0, 0.0, 10.0]);
    // Inside a wall: 0.
    assert_eq!(nearest(&s, [52.0, 0.0, 0.0]).unwrap().0, 0.0);
    // A capsule's surface: radius off its axis.
    let c = from_packed(&packed_capsule([0.0, 0.0, 0.0], 5.0, 2.0), 0.0);
    let (d, p, _) = nearest(&c, [10.0, 3.0, 0.0]).unwrap();
    assert!((d - 8.0).abs() < 1e-9 && (p[0] - 2.0).abs() < 1e-9 && (p[1] - 3.0).abs() < 1e-9);
    let (d, _, _) = nearest(&c, [0.0, 9.0, 0.0]).unwrap();
    assert!((d - 2.0).abs() < 1e-9, "past the end cap: {d}");
    assert!(nearest(&Surface::default(), [0.0, 0.0, 0.0]).is_none());
}

#[test]
fn a_bolt_down_the_tunnel_hits_nothing_and_one_across_it_hits_the_wall() {
    let s = tunnel();
    assert!(
        sweep(&s, [0.0, 0.0, -300.0], [0.0, 0.0, 300.0], 0.5).is_none(),
        "the tunnel is open"
    );
    let (t, k) = sweep(&s, [0.0, 0.0, 0.0], [100.0, 0.0, 0.0], 0.5).unwrap();
    assert_eq!(k, 2);
    assert!(
        (t - 0.465).abs() < 1e-9,
        "enters the starboard wall grown by 0.5 m at 46.5 m: {t}"
    );
    // Starting inside a wall: at once.
    assert_eq!(
        sweep(&s, [52.0, 0.0, 0.0], [60.0, 0.0, 0.0], 0.0)
            .unwrap()
            .0,
        0.0
    );
    // The earliest of two volumes along the path.
    let (_, k) = sweep(&s, [0.0, -100.0, 0.0], [0.0, 100.0, 0.0], 0.0).unwrap();
    assert_eq!(k, 1, "the floor first, going up");
    // A capsule: its side, and an end cap.
    let c = from_packed(&packed_capsule([0.0, 0.0, 0.0], 5.0, 2.0), 0.0);
    let (t, _) = sweep(&c, [-10.0, 0.0, 0.0], [10.0, 0.0, 0.0], 0.0).unwrap();
    assert!((t - 0.4).abs() < 1e-9, "{t}");
    let (t, _) = sweep(&c, [0.0, 20.0, 0.0], [0.0, 0.0, 0.0], 1.0).unwrap();
    assert!((t - 0.6).abs() < 1e-9, "the cap grown by 1 m at y 8: {t}");
    assert!(
        sweep(&c, [-10.0, 0.0, 4.0], [10.0, 0.0, 4.0], 1.0).is_none(),
        "4 m off the axis passes a 3 m capsule"
    );
}

#[test]
fn the_row_helpers_follow_the_body_pose() {
    // The tunnel's body 1 km along x, turned a quarter about y: the tunnel now runs along x.
    let basis = Basis::from_axis_angle(Vector3::UP, std::f32::consts::FRAC_PI_2);
    let rows = row_with(tunnel(), Vector3::new(1000.0, 0.0, 0.0), basis);
    let (p, d) = nearest_of_row(&rows, 0, Vector3::new(1000.0, 0.0, 0.0)).unwrap();
    assert!((d - 17.0).abs() < 1e-3);
    assert!((p.y.abs() - 17.0).abs() < 1e-3);
    assert!(
        !segment_enters(
            &rows,
            0,
            Vector3::new(700.0, 0.0, 0.0),
            Vector3::new(1300.0, 0.0, 0.0),
            0.5
        ),
        "along the tunnel"
    );
    assert!(
        segment_enters(
            &rows,
            0,
            Vector3::new(1000.0, 0.0, -100.0),
            Vector3::new(1000.0, 0.0, 100.0),
            0.5
        ),
        "across it"
    );
    let mut near = 0;
    near_volumes(&rows, 0, Vector3::new(1000.0, 0.0, 0.0), 20.0, |_, d| {
        assert!(d <= 20.0);
        near += 1;
    });
    assert_eq!(near, 2, "the roof and the floor, not the walls 47 m off");
    // A row that is not a big hull has no surface.
    let mut plain = rows.clone();
    plain.roles = vec![0];
    assert!(nearest_of_row(&plain, 0, Vector3::ZERO).is_none());
    assert!(!segment_enters(
        &plain,
        0,
        Vector3::new(1000.0, 0.0, -100.0),
        Vector3::new(1000.0, 0.0, 100.0),
        0.5
    ));
}

#[test]
fn the_drums_skin_moves_at_its_spin_times_its_radius() {
    let basis = Basis::from_axis_angle(Vector3::BACK, 0.3);
    let origin = Vector3::new(10.0, 20.0, -1000.0);
    let v = surface_velocity(
        &basis,
        origin,
        0.148,
        origin + Vector3::new(417.0, 0.0, 55.0),
    );
    assert!((v.length() - 0.148 * 417.0).abs() < 1e-3, "{}", v.length());
    assert!(
        v.y > 61.0 && v.x.abs() < 1e-3,
        "counter-clockwise about +z: {v:?}"
    );
    assert_eq!(
        surface_velocity(&basis, origin, 0.0, origin + Vector3::RIGHT * 400.0),
        Vector3::ZERO
    );
}

// A fighter as avoidance sees it.
fn fighter(at: Vector3, v: Vector3) -> crate::kernels::pilot::Ship {
    crate::kernels::pilot::Ship {
        position: at,
        velocity: v,
        radius: 8.0,
        a_retro: 30.0,
        rate_max_x: 1.5,
        rate_max_y: 1.5,
        a_rcs_x: 20.0,
        a_rcs_y: 20.0,
        tie_hash: 12345,
    }
}

#[test]
fn avoidance_goes_round_the_skin_not_the_bounding_sphere() {
    use crate::kernels::pilot::avoid;
    let rows = row_with(tunnel(), Vector3::ZERO, Basis::IDENTITY);
    // 300 m out beside the tunnel, well inside its 150 m... the row's 150 m bounding radius is not what counts: flying
    // past 120 m off the side wall is no threat, though inside the sphere.
    let wish = Vector3::new(0.0, 0.0, 100.0);
    let out = avoid(
        &rows,
        &fighter(Vector3::new(180.0, 0.0, -100.0), wish),
        &[0],
        &[],
        0,
        wish,
    );
    assert_eq!(out.v_des, wish, "nothing to dodge 120 m clear of the wall");
    // Straight at the starboard wall from outside: a dodge.
    let at_wall = Vector3::new(-100.0, 0.0, 0.0);
    let out = avoid(
        &rows,
        &fighter(Vector3::new(200.0, 0.0, 0.0), at_wall),
        &[0],
        &[],
        0,
        at_wall,
    );
    assert_ne!(out.v_des, at_wall, "the wall ahead is dodged");
    // Down the middle of the tunnel: roof and floor 17 m off push equally, so the course holds up and down.
    let down = Vector3::new(0.0, 0.0, 60.0);
    let out = avoid(
        &rows,
        &fighter(Vector3::new(0.0, 0.0, -50.0), down),
        &[0],
        &[],
        0,
        down,
    );
    assert!(
        out.v_des.y.abs() < 1e-3,
        "roof and floor balance: {:?}",
        out.v_des
    );
    // Off-centre, nearer the roof: pushed down.
    let out = avoid(
        &rows,
        &fighter(Vector3::new(0.0, 8.0, -50.0), down),
        &[0],
        &[],
        0,
        down,
    );
    assert!(
        out.v_des.y < 0.0,
        "away from the nearer roof: {:?}",
        out.v_des
    );
}

#[test]
fn the_fire_lane_is_blocked_by_a_friendly_big_hulls_volumes_only() {
    use crate::kernels::pilot::{FRIENDLY, fire_lane};
    let rows = row_with(tunnel(), Vector3::ZERO, Basis::IDENTITY);
    let relations = [FRIENDLY];
    // Down the tunnel: clear.
    assert!(fire_lane(
        &rows,
        &relations,
        0,
        &[0],
        Vector3::new(0.0, 0.0, -300.0),
        Vector3::BACK,
        2000.0,
        99,
        false
    ));
    // Across it: the wall is in the way.
    assert!(!fire_lane(
        &rows,
        &relations,
        0,
        &[0],
        Vector3::new(-300.0, 0.0, 0.0),
        Vector3::RIGHT,
        2000.0,
        99,
        false
    ));
    // Past it, 30 m clear of the roof's top, though through the bounding sphere: clear.
    assert!(fire_lane(
        &rows,
        &relations,
        0,
        &[0],
        Vector3::new(-300.0, 57.0, 0.0),
        Vector3::RIGHT,
        2000.0,
        99,
        false
    ));
}

// The eight corners of a box of half extents `h` at the origin, flattened.
fn corners(h: [f64; 3]) -> Vec<f64> {
    let mut out = Vec::new();
    for sx in [-1.0, 1.0] {
        for sy in [-1.0, 1.0] {
            for sz in [-1.0, 1.0] {
                out.extend([sx * h[0], sy * h[1], sz * h[2]]);
            }
        }
    }
    out
}

#[test]
fn a_hulls_planes_are_its_faces() {
    let flat = corners([1.0, 2.0, 3.0]);
    let points: Vec<[f64; 3]> = flat.chunks_exact(3).map(|p| [p[0], p[1], p[2]]).collect();
    let planes = hull_planes(&points);
    assert_eq!(planes.len(), 6, "a box's six faces: {planes:?}");
    // A wedge: a box cut on a slope; its sloped face is one plane.
    let wedge: Vec<[f64; 3]> = vec![
        [0.0, 0.0, 0.0],
        [10.0, 0.0, 0.0],
        [0.0, 0.0, 10.0],
        [10.0, 0.0, 10.0],
        [0.0, 2.0, 0.0],
        [10.0, 2.0, 0.0],
        [0.0, 8.0, 10.0],
        [10.0, 8.0, 10.0],
    ];
    assert_eq!(hull_planes(&wedge).len(), 6);
}

#[test]
fn a_bolt_stops_on_the_hull_not_on_its_box() {
    // A wedge 10 m across, its top sloping from 2 m to 8 m; its box is 8 m tall everywhere.
    let wedge: Vec<f64> = vec![
        0.0, 0.0, 0.0, 10.0, 0.0, 0.0, 0.0, 0.0, 10.0, 10.0, 0.0, 10.0, 0.0, 2.0, 0.0, 10.0, 2.0,
        0.0, 0.0, 8.0, 10.0, 10.0, 8.0, 10.0,
    ];
    let mut s = from_packed(&packed_box([5.0, 4.0, 5.0], [5.0, 4.0, 5.0]), 0.0);
    let (t_box, _) = sweep(&s, [5.0, 20.0, 1.0], [5.0, -20.0, 1.0], 0.0).unwrap();
    assert!(
        (20.0 - 40.0 * t_box - 8.0).abs() < 1e-9,
        "the box's top at 8 m"
    );
    let mut flat = vec![0.0, 8.0];
    flat.extend(wedge);
    add_hulls(&mut s, &flat);
    let (t, k) = sweep(&s, [5.0, 20.0, 1.0], [5.0, -20.0, 1.0], 0.0).unwrap();
    assert_eq!(k, 0);
    assert!(
        (20.0 - 40.0 * t - 2.6).abs() < 1e-9,
        "the slope at z 1 is 2.6 m up: {}",
        20.0 - 40.0 * t
    );
    // Grown by a bolt's radius, a little sooner; past the slope's high end, nothing.
    let (t_grown, _) = sweep(&s, [5.0, 20.0, 1.0], [5.0, -20.0, 1.0], 0.25).unwrap();
    assert!(t_grown < t);
    assert!(sweep(&s, [5.0, 20.0, 12.0], [5.0, -20.0, 12.0], 0.0).is_none());
    // Broken input is skipped, not trusted.
    let mut t2 = from_packed(&packed_box([0.0, 0.0, 0.0], [1.0, 1.0, 1.0]), 0.0);
    add_hulls(&mut t2, &[5.0, 8.0, 1.0, 2.0]);
    assert!(t2.hulls.iter().all(|h| h.is_empty()));
}

#[test]
fn a_wish_into_the_skin_is_turned_along_it_not_cancelled() {
    use crate::kernels::pilot::avoid;
    let rows = row_with(tunnel(), Vector3::ZERO, Basis::IDENTITY);
    // 20 m off the starboard wall's outside (x = 57), inside the keep-off distance (8 m hull + 15 m), wanting to go
    // through it at 60 m/s and somewhat aft: the wish comes out along the wall at speed, not to a stand.
    let wish = Vector3::new(-60.0, 0.0, 30.0);
    let ship = fighter(Vector3::new(77.0, 0.0, 0.0), Vector3::ZERO);
    let out = avoid(&rows, &ship, &[0], &[], 0, wish);
    assert!(out.v_des.x >= -1.0, "no longer into the wall: {:?}", out.v_des);
    assert!(out.v_des.z > 40.0, "along the wall, the way it leaned: {:?}", out.v_des);
    // Dead on, the ship's seeded side picks a way along the wall.
    let wish = Vector3::new(-60.0, 0.0, 0.0);
    let out = avoid(&rows, &ship, &[0], &[], 0, wish);
    let along = (out.v_des.y * out.v_des.y + out.v_des.z * out.v_des.z).sqrt();
    assert!(along > 40.0, "a way round is chosen: {:?}", out.v_des);
    // Farther out than the band the wish stands until the ordinary dodge sees the wall.
    let far = fighter(Vector3::new(57.0 + 23.0 + 61.0, 0.0, 0.0), Vector3::ZERO);
    let slow = Vector3::new(-4.0, 0.0, 0.0);
    assert_eq!(avoid(&rows, &far, &[0], &[], 0, slow).v_des, slow);
    // Going away from the wall, or along it, nothing is turned.
    let off = Vector3::new(50.0, 0.0, 0.0);
    assert_eq!(avoid(&rows, &ship, &[0], &[], 0, off).v_des.z, 0.0);
}

#[test]
fn a_turning_hulls_arm_coming_round_is_dodged_by_a_ship_at_rest() {
    use crate::kernels::pilot::avoid;
    // An arm from the axis out to 300 m along +x, 20 m thick, turning at 0.148 rad/s about +z: at 250 m out its face
    // moves at 37 m/s toward +y. A ship holding still 60 m ahead of it is 1.6 s from being hit.
    let arm = from_packed(&packed_box([150.0, 0.0, 0.0], [150.0, 10.0, 10.0]), 0.148);
    let rows = row_with(arm, Vector3::ZERO, Basis::IDENTITY);
    let ship = fighter(Vector3::new(250.0, 70.0, 0.0), Vector3::ZERO);
    let out = avoid(&rows, &ship, &[0], &[], 0, Vector3::ZERO);
    assert!(f64::from(crate::v3::length(out.v_des)) > 5.0, "it moves out of the arm's way: {:?}", out.v_des);
    // The same arm at rest is no threat to a ship at rest.
    let still = from_packed(&packed_box([150.0, 0.0, 0.0], [150.0, 10.0, 10.0]), 0.0);
    let rows = row_with(still, Vector3::ZERO, Basis::IDENTITY);
    assert_eq!(avoid(&rows, &ship, &[0], &[], 0, Vector3::ZERO).v_des, Vector3::ZERO);
}

#[test]
fn a_ship_falling_at_the_skin_too_fast_for_its_side_thrusters_pulls_out() {
    use crate::kernels::pilot::avoid;
    let rows = row_with(tunnel(), Vector3::ZERO, Basis::IDENTITY);
    // 180 m off the starboard wall, falling at it at 60 m/s while wanting to go along it: a quarter turn and the retros
    // need more room than is left, so it pulls out now, and its wish has no way in.
    let along = Vector3::new(0.0, 0.0, 80.0);
    let falling = fighter(Vector3::new(57.0 + 180.0, 0.0, 0.0), Vector3::new(-60.0, 0.0, 0.0));
    let out = avoid(&rows, &falling, &[0], &[], 0, along);
    assert!(out.pull_out && out.urgent, "it must burn now");
    assert!(out.v_des.x >= 0.0, "no way in is asked for: {:?}", out.v_des);
    // Wanting to go in as well, the way in is dropped at once, far outside the slide's band, and the wish's way along the
    // wall kept (M7-T38: the stop comes first, so it is not turned along at the wish's whole speed).
    let inward = Vector3::new(-60.0, 0.0, 40.0);
    let out = avoid(&rows, &falling, &[0], &[], 0, inward);
    assert!(out.pull_out && out.v_des.x >= -1.0 && (out.v_des.z - 40.0).abs() < 1e-3, "along the wall: {:?}", out.v_des);
    // The same fall from 600 m out leaves room: no pull-out yet. Nor for a ship moving along the wall or away.
    let high = fighter(Vector3::new(57.0 + 600.0, 0.0, 0.0), Vector3::new(-60.0, 0.0, 0.0));
    assert!(!avoid(&rows, &high, &[0], &[], 0, along).pull_out);
    let level = fighter(Vector3::new(57.0 + 60.0, 0.0, 0.0), along);
    assert!(!avoid(&rows, &level, &[0], &[], 0, along).pull_out);
}

#[test]
fn a_turning_hull_is_kept_off_where_its_parts_sweep() {
    // The arm (to 300 m out along +x, 20 m thick) sweeps a disc; a wall of the tunnel a ring with the tunnel clear inside.
    let arm = from_packed(&packed_box([150.0, 0.0, 0.0], [150.0, 10.0, 10.0]), 0.148);
    let ring = arm.volumes[0].swept;
    assert!(ring[0] == 0.0 && (ring[1] - 300.17).abs() < 0.01, "from the axis to its far corners: {ring:?}");
    assert_eq!((ring[2], ring[3]), (-10.0, 10.0));
    let roof = tunnel().volumes[0].swept;
    assert!((roof[0] - 17.0).abs() < 1e-9, "the roof's ring starts at the tunnel's half height: {roof:?}");
    let capsule = from_packed(&packed_capsule([100.0, 0.0, 5.0], 30.0, 4.0), 0.148).volumes[0].swept;
    assert!((capsule[0] - 96.0).abs() < 1e-9 && (capsule[1] - (100.0_f64.hypot(30.0) + 4.0)).abs() < 1e-9, "{capsule:?}");
    // Opposite the arm (at -x, where it is not this tick) the swept disc is as near as beside it.
    let rows = row_with(arm, Vector3::ZERO, Basis::IDENTITY);
    let (at, d) = nearest_to_avoid(&rows, 0, Vector3::new(-200.0, 0.0, 60.0), 0.0).unwrap();
    assert!((d - 50.0).abs() < 1e-3 && (at.z - 10.0).abs() < 1e-3 && (at.x + 200.0).abs() < 1e-3, "{at:?} {d}");
    // Past the tip: the rim.
    let (at, d) = nearest_to_avoid(&rows, 0, Vector3::new(0.0, -400.0, 0.0), 0.0).unwrap();
    assert!((d - 99.83).abs() < 0.01 && at.y < -300.0, "{at:?} {d}");
}


// The drum's waist as the Cobra arms make it (M7-T38): a core out to 189.5 m and four arms standing on it from 196 to 246.5 m
// out, 300 m long, turning at 0.148 rad/s.
fn waist() -> Surface {
    let mut p = packed_box([0.0, 0.0, 0.0], [134.0, 134.0, 150.0]);
    for k in 0..4 {
        let (s, c) = (std::f64::consts::FRAC_PI_2 * f64::from(k)).sin_cos();
        p.extend([0.0, c, s, 0.0, -s, c, 0.0, 0.0, 0.0, 1.0, 219.0 * c, 219.0 * s, 0.0, 23.0, 47.0, 150.0]);
    }
    from_packed(&p, 0.148)
}

#[test]
fn among_the_cobra_arms_a_ship_is_pushed_out_past_their_tips_never_in_toward_the_drum() {
    use crate::kernels::pilot::avoid;
    use crate::v3::dot;
    let rows = row_with(waist(), Vector3::ZERO, Basis::IDENTITY);
    let radial = Vector3::new(0.7071, 0.7071, 0.0);
    // Between two arms at every depth of their ring (nearer its floor than its tips too), and in the 6.5 m between the core
    // and the arms' floor where no ship fits: wanting in, at rest or along the axis, the way given is out.
    for r in [193.0_f32, 200.0, 215.0, 235.0] {
        let ship = fighter(radial * r, radial * -20.0);
        for wish in [radial * -60.0, Vector3::ZERO, Vector3::new(0.0, 0.0, 100.0)] {
            let out = avoid(&rows, &ship, &[0], &[], 0, wish);
            assert!(dot(out.v_des, radial) > 5.0, "{r} m out wanting {wish:?}: {:?}", out.v_des);
        }
    }
    // One point, out past the tips, whatever ring the ship is in.
    let (at, d) = nearest_to_avoid(&rows, 0, radial * 205.0, 2.0 * 23.0).unwrap();
    assert!(d == 0.0 && dot(sub(radial * 205.0, at), radial) > 0.0, "{at:?} {d}");
}

#[test]
fn a_hole_round_the_axis_wide_enough_to_fly_is_still_a_way_out() {
    // The tunnel turning with the drum: a ship in a wall's ring near the hole is led into the tunnel when that is nearer;
    // where the hole is narrower than a ship needs it is no way out, and nothing leads across the axis.
    let mut tunnel = tunnel();
    tunnel.spin_rad_s = 0.148;
    let rows = row_with(tunnel, Vector3::ZERO, Basis::IDENTITY);
    let p = Vector3::new(0.0, 19.0, 0.0); // in the roof, 2 m above its underside
    let (at, d) = nearest_to_avoid(&rows, 0, p, 2.0).unwrap();
    assert!(d == 0.0 && at.y > p.y, "down into the tunnel: {at:?}");
    let (at, _) = nearest_to_avoid(&rows, 0, p, 40.0).unwrap();
    assert!(at.y < p.y || (at.z - p.z).abs() > 0.1, "a 34 m tunnel is too narrow for a 40 m ship: not down: {at:?}");
}

#[test]
fn a_ship_sliding_along_one_face_is_stopped_short_of_a_part_it_falls_at_beyond_it() {
    use crate::kernels::pilot::avoid;
    // A long low deck along z at 0..20 m up and a tower beyond it to +x: the ship skims the deck 60 m up while flying at the
    // tower at 80 m/s. The deck is nearer, but the tower is where it would strike: it pulls out from the tower.
    let mut p = packed_box([0.0, 10.0, 0.0], [600.0, 10.0, 600.0]);
    p.extend(packed_box([300.0, 200.0, 0.0], [20.0, 200.0, 600.0]));
    let rows = row_with(from_packed(&p, 0.0), Vector3::ZERO, Basis::IDENTITY);
    let ship = fighter(Vector3::new(100.0, 80.0, 0.0), Vector3::new(80.0, 0.0, 0.0));
    let out = avoid(&rows, &ship, &[0], &[], 0, Vector3::new(80.0, 0.0, 0.0));
    assert!(out.pull_out, "it must stop short of the tower");
    assert!(out.v_des.x <= 0.0, "no more way toward it: {:?}", out.v_des);
    // Flying along the tower instead, the nearer deck makes no pull-out.
    let wide = fighter(Vector3::new(100.0, 80.0, 0.0), Vector3::new(0.0, 0.0, 80.0));
    assert!(!avoid(&rows, &wide, &[0], &[], 0, Vector3::new(0.0, 0.0, 80.0)).pull_out, "along the tower, not at it");
}

#[test]
fn a_ship_passing_wide_of_a_corner_is_not_falling_at_it() {
    use crate::kernels::pilot::avoid;
    // A step in the turning drum: a body 200 m across, then from z = 0 a band 300 m across (its corners 424 m out). A ship
    // 75 m outside the band's swept ring flies along the axis at 120 m/s toward the step: its way passes over the corner,
    // so no pull-out.
    let mut p = packed_box([0.0, 0.0, 300.0], [300.0, 300.0, 300.0]);
    p.extend(packed_box([0.0, 0.0, -300.0], [200.0, 200.0, 300.0]));
    let rows = row_with(from_packed(&p, 0.148), Vector3::ZERO, Basis::IDENTITY);
    let ship = fighter(Vector3::new(500.0, 0.0, -400.0), Vector3::new(0.0, 0.0, 120.0));
    let wish = Vector3::new(0.0, 0.0, 120.0);
    let out = avoid(&rows, &ship, &[0], &[], 0, wish);
    assert!(!out.pull_out, "passing 75 m over the corner is no fall");
    // Flying at the step's face itself, inside the band's ring, is.
    let at_face = fighter(Vector3::new(300.0, 0.0, -400.0), Vector3::new(0.0, 0.0, 120.0));
    assert!(avoid(&rows, &at_face, &[0], &[], 0, wish).pull_out, "straight at the step's face");
}

#[test]
fn pulling_out_the_wish_along_the_skin_changes_the_way_by_no_more_than_the_fall() {
    use crate::kernels::pilot::avoid;
    // Falling at the tunnel's wall at 60 m/s while the wish asks for 150 m/s along it: the stop comes first, so the wish
    // keeps the ship's way along the wall and adds no more than 60 m/s to it.
    let rows = row_with(tunnel(), Vector3::ZERO, Basis::IDENTITY);
    let falling = fighter(Vector3::new(57.0 + 180.0, 0.0, 0.0), Vector3::new(-60.0, 0.0, 10.0));
    let out = avoid(&rows, &falling, &[0], &[], 0, Vector3::new(0.0, 0.0, 150.0));
    assert!(out.pull_out);
    assert!(out.v_des.x >= -1e-3 && out.v_des.z <= 10.0 + 60.0 + 1e-3 && out.v_des.z > 10.0, "{:?}", out.v_des);
}


// A fin: a plate 4 m thick across x, 3 km tall and 250 m along z, at x = -535 (M7-T38).
fn fin() -> Surface {
    from_packed(&packed_box([-535.0, 0.0, 365.0], [2.0, 1500.0, 125.0]), 0.0)
}

#[test]
fn a_way_that_meets_a_thin_plates_face_is_found_though_its_nearest_point_is_an_edge() {
    use crate::v3::dot;
    let rows = row_with(fin(), Vector3::ZERO, Basis::IDENTITY);
    // 330 m out, 30 m past the plate's edge in z, flying at it at 150 m/s with a little drift onto it: its nearest point
    // is the edge, which its way passes wide of, but the way meets the face 2 s on.
    let p = Vector3::new(-865.0, 700.0, 520.0);
    let v = Vector3::new(150.0, 0.0, -20.0);
    let (t, n) = path_entry(&rows, 0, p, v, 8.0, 25.0).expect("the face is met");
    assert!((t - (330.0 - 2.0 - 25.0) / 150.0).abs() < 0.05, "{t}");
    assert!(dot(n, Vector3::new(-1.0, 0.0, 0.0)) > 0.99, "the face's normal: {n:?}");
    // Through the gap beside it, or too slow to get there in the time given, nothing.
    assert!(path_entry(&rows, 0, Vector3::new(-865.0, 700.0, 585.0), Vector3::new(150.0, 0.0, 0.0), 8.0, 25.0).is_none());
    assert!(path_entry(&rows, 0, p, v, 1.0, 25.0).is_none());
}

#[test]
fn a_way_through_a_turning_hulls_ring_meets_its_rim_its_end_or_its_holes_wall() {
    use crate::v3::dot;
    let rows = row_with(waist(), Vector3::ZERO, Basis::IDENTITY);
    // Falling at the arms' ring from 400 m out: its rim, 400 - 246.5 - 25 m on.
    let (t, n) = path_entry(&rows, 0, Vector3::new(400.0, 0.0, 0.0), Vector3::new(-100.0, 0.0, 0.0), 5.0, 25.0).unwrap();
    assert!((t - (400.0 - 246.5 - 25.0) / 100.0).abs() < 0.01 && n.x > 0.99, "{t} {n:?}");
    // Along the axis at 220 m out, from 300 m fore of it: its fore end.
    let (t, n) = path_entry(&rows, 0, Vector3::new(220.0, 0.0, -450.0), Vector3::new(0.0, 0.0, 100.0), 5.0, 25.0).unwrap();
    assert!((t - (450.0 - 150.0 - 25.0) / 100.0).abs() < 0.01 && dot(n, Vector3::new(0.0, 0.0, -1.0)) > 0.99, "{t} {n:?}");
    // A chord 300 m from the axis passes outside it all.
    assert!(path_entry(&rows, 0, Vector3::new(300.0, -500.0, 0.0), Vector3::new(0.0, 100.0, 0.0), 10.0, 25.0).is_none());
}

#[test]
fn a_ship_falling_at_a_thin_plates_face_pulls_out_and_one_passing_its_edge_does_not() {
    use crate::kernels::pilot::avoid;
    let rows = row_with(fin(), Vector3::ZERO, Basis::IDENTITY);
    // At the face from 330 m at 150 m/s: a quarter turn and the retros need more, so it pulls out, wanting no way in.
    let falling = fighter(Vector3::new(-865.0, 700.0, 520.0), Vector3::new(150.0, 0.0, -20.0));
    let out = avoid(&rows, &falling, &[0], &[], 0, Vector3::new(150.0, 0.0, 0.0));
    assert!(out.pull_out, "it must stop short of the face");
    assert!(out.v_des.x <= 150.0 - 1.0, "less way toward it than it has: {:?}", out.v_des);
    // Through the gap beside the plate, 60 m clear of its edge: its way passes wide, so it keeps its wish.
    let through = fighter(Vector3::new(-865.0, 700.0, 550.0), Vector3::new(150.0, 0.0, 0.0));
    let out = avoid(&rows, &through, &[0], &[], 0, Vector3::new(150.0, 0.0, 0.0));
    assert!(!out.pull_out && out.v_des == Vector3::new(150.0, 0.0, 0.0), "{:?}", out.v_des);
}

#[test]
fn a_wish_at_a_face_it_could_not_stop_short_of_is_turned_off_it_early() {
    use crate::kernels::pilot::avoid;
    let rows = row_with(fin(), Vector3::ZERO, Basis::IDENTITY);
    // Flying along the plate 300 m out, the wish swings straight at its face at 150 m/s: too late to stop for once the ship
    // turns, so the wish loses its way at the face now, though the ship is not yet falling at it.
    let ship = fighter(Vector3::new(-835.0, 700.0, 365.0), Vector3::new(0.0, 0.0, 120.0));
    let out = avoid(&rows, &ship, &[0], &[], 0, Vector3::new(150.0, 0.0, 0.0));
    assert!(out.v_des.x <= 1e-3, "no way at the face: {:?}", out.v_des);
    // The same wish from 2 km out has room: it stands.
    let far = fighter(Vector3::new(-2535.0, 700.0, 365.0), Vector3::new(0.0, 0.0, 120.0));
    assert_eq!(avoid(&rows, &far, &[0], &[], 0, Vector3::new(150.0, 0.0, 0.0)).v_des, Vector3::new(150.0, 0.0, 0.0));
}

// A capital's sections overlap a little at their cuts (M10-T05); its hit lands on the section the bolt meets first (M10-T08).
#[test]
fn a_bolt_across_two_sections_meeting_at_a_cut_names_the_one_it_meets_first() {
    let mut p = Vec::new();
    p.extend(packed_box([0.0, 0.0, -51.0], [20.0, 20.0, 52.0])); // the bow, z -103 to 1
    p.extend(packed_box([0.0, 0.0, 51.0], [20.0, 20.0, 52.0])); // the stern, z -1 to 103
    let s = from_packed(&p, 0.0);
    let (_, k) = sweep(&s, [0.0, 0.0, 300.0], [0.0, 0.0, -300.0], 0.5).unwrap();
    assert_eq!(k, 1, "from astern, the stern first though it is listed second");
    let (_, k) = sweep(&s, [0.0, 0.0, -300.0], [0.0, 0.0, 300.0], 0.5).unwrap();
    assert_eq!(k, 0, "from ahead, the bow");
    let (_, k) = sweep(&s, [100.0, 0.0, 0.5], [-100.0, 0.0, 0.5], 0.0).unwrap();
    assert_eq!(k, 0, "square on the cut, where both start at once: the earlier listed");
    let (_, k) = sweep(&s, [100.0, 0.0, 30.0], [-100.0, 0.0, 30.0], 0.0).unwrap();
    assert_eq!(k, 1, "across the stern alone");
}
