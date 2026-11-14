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
    // Wanting to go in as well, the wish is turned along the skin at once, far outside the slide's band.
    let inward = Vector3::new(-60.0, 0.0, 40.0);
    let out = avoid(&rows, &falling, &[0], &[], 0, inward);
    assert!(out.pull_out && out.v_des.x >= -1.0 && out.v_des.z > 50.0, "turned along the wall: {:?}", out.v_des);
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
    let (at, d) = nearest_to_avoid(&rows, 0, Vector3::new(-200.0, 0.0, 60.0)).unwrap();
    assert!((d - 50.0).abs() < 1e-3 && (at.z - 10.0).abs() < 1e-3 && (at.x + 200.0).abs() < 1e-3, "{at:?} {d}");
    // Past the tip: the rim.
    let (at, d) = nearest_to_avoid(&rows, 0, Vector3::new(0.0, -400.0, 0.0)).unwrap();
    assert!((d - 99.83).abs() < 0.01 && at.y < -300.0, "{at:?} {d}");
}
