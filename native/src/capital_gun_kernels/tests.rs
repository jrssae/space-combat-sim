// The capital turrets and launchers (M10-T14), beside the kernel and outside its engine-free guard (test builds only).
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::Basis;

use super::*;
use crate::rows::{FLAG_DISABLED, FLAG_DISGUISE_SHIFT, FLAG_RIGID, ROLE_COMBAT, ROLE_SURFACE, Surface};
use crate::surface::from_packed;

const LIVE: u32 = FLAG_RIGID | FLAG_HULL_ACTIVE;
const DT: f64 = 1.0 / 60.0;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

// One row per (body, position, radius, kind, faction, flags); body 1 (the shooter) holds `surface` when one is given.
fn rows_of(bodies: &[(i64, Vector3, f64, u8, u32, u32)], surface: Option<Surface>) -> Rows {
    let mut rows = Rows::default();
    for &(body, at, radius, kind, faction, flags) in bodies {
        rows.body_ids.push(body);
        rows.ids.push(body + 5000); // the target marker's id
        rows.faction_ix.push(faction);
        rows.positions.push(at);
        rows.velocities.push(Vector3::ZERO);
        rows.bases.push(Basis::IDENTITY);
        rows.angular.push(Vector3::ZERO);
        rows.radii.push(radius);
        rows.kinds.push(kind);
        rows.flags.push(flags);
        rows.hull_ids.push(body + 1000);
        rows.handles.push(body);
        rows.rigid.push(flags & FLAG_RIGID != 0);
        rows.is_static.push(false);
        rows.is_mine.push(false);
        rows.hull_fraction.push(1.0);
        rows.target_ids.push(-1);
        rows.reach.push(0.0);
        rows.name_ids.push(0);
        rows.roles.push(if body == 1 && surface.is_some() { ROLE_SURFACE } else { ROLE_COMBAT });
    }
    rows.node_count = bodies.len();
    if let Some(s) = surface {
        let mut map = HashMap::new();
        map.insert(1_i64, Arc::new(s));
        rows.surfaces = Some(Arc::new(map));
    }
    rows
}

// The shooter's hull: a long box along z (half extents 20 x 10 x 200) round its centre.
fn hull() -> Surface {
    from_packed(&[0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0, 10.0, 200.0], 0.0)
}

fn gun(role: u8) -> GunSpec {
    GunSpec {
        launcher: false,
        role,
        damage: 12.0,
        barrels: 1,
        burst_shots: 1,
        burst_spacing_s: 0.0,
        cycle_s: 2.0,
        speed_mps: 1800.0,
        range_m: 4000.0,
        lifetime_s: 2.5,
        hit_radius_m: 1.0,
        spread_rad: 0.0,
        traverse_rad_s: 360f64.to_radians(),
        elevation_rad_s: 360f64.to_radians(),
        nav_gain: 0.0,
        turn_rad_s: 0.0,
        warhead: WARHEAD_NONE,
        color: [1.0; 4],
        look: 0,
    }
}

fn launcher(role: u8) -> GunSpec {
    GunSpec {
        launcher: true,
        speed_mps: 350.0,
        range_m: 6000.0,
        lifetime_s: 20.0,
        cycle_s: 12.0,
        damage: 40.0,
        nav_gain: 4.0,
        turn_rad_s: 0.6,
        warhead: WARHEAD_MISSILE,
        ..gun(role)
    }
}

// Factions 0 and 1 hostile to each other, 2 friendly to everyone.
fn table() -> Vec<bool> {
    vec![false, true, false, true, false, false, false, false, false]
}

struct Run {
    rows: Rows,
    mounts: Vec<Mount>,
    owners: Vec<Owner>,
    owner_of: Vec<u32>,
    hostile: Vec<bool>,
    now_s: f64,
    tick: i64,
}

impl Run {
    // A shooter at the origin (body 1, faction 0) with one turret on its top (20 m up), its base facing up, the usual
    // 200 deg cone (elevation down to -10 deg).
    fn new(rows: Rows, spec: GunSpec) -> Run {
        let mount = Mount::new(1, 1, v(0.0, 10.0, 0.0), v(0.0, 1.0, 0.0), v(0.0, 0.0, -1.0), 100f64.to_radians(), false, 5.0, spec);
        Run::with(rows, mount)
    }

    fn with(rows: Rows, mount: Mount) -> Run {
        Run {
            rows,
            mounts: vec![mount],
            owners: vec![Owner { body: 1, bodies: vec![1], order: 0 }],
            owner_of: vec![0],
            hostile: table(),
            now_s: 0.0,
            tick: 0,
        }
    }

    fn tick(&mut self) -> (Vec<Shot>, Tally) {
        let rows = &self.rows;
        let owner_rows: Vec<i32> = self
            .owners
            .iter()
            .map(|o| rows.body_ids.iter().position(|&b| b == o.body).map_or(-1, |r| r as i32))
            .collect();
        let hull_rows: Vec<u32> = (0..rows.body_ids.len() as u32).collect();
        let world = GunWorld {
            rows,
            hull_rows: &hull_rows,
            owner_rows: &owner_rows,
            hostile: &self.hostile,
            factions: 3,
            row_of: |id: i64| rows.body_ids.iter().position(|&b| b == id),
            rest: Vector3::ZERO,
        };
        let mut shots = Vec::new();
        let mut tally = Tally::default();
        let mut scratch = Scratch::default();
        step(&mut self.mounts, &self.owners, &self.owner_of, &world, self.now_s, DT, self.tick, &mut shots, &mut scratch, &mut tally);
        self.now_s += DT;
        self.tick += 1;
        (shots, tally)
    }

    // Ticks until the first shot (at most `limit` ticks): the shots and the tick they came on.
    fn first_shots(&mut self, limit: usize) -> Option<(Vec<Shot>, usize)> {
        for t in 0..limit {
            let (shots, _) = self.tick();
            if !shots.is_empty() {
                return Some((shots, t));
            }
        }
        None
    }
}

#[test]
fn a_turret_leads_a_hostile_and_fires_on_its_cycle() {
    let rows = rows_of(&[(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, 400.0, -2000.0), 8.0, 0, 1, LIVE)], None);
    let mut run = Run::new(rows, gun(ROLE_DUAL));
    let (shots, _) = run.first_shots(60).expect("it fires at a hostile in range and arc");
    assert_eq!(shots.len(), 1);
    assert_eq!(run.mounts[0].target, 2);
    let dir = normalized(shots[0].velocity);
    let want = normalized(sub(v(0.0, 400.0, -2000.0), shots[0].start));
    assert!(f64::from(dot(dir, want)) > 0.9999, "it fires along the line to a still target");
    // Not again until its cycle has passed.
    let mut again = 0;
    for _ in 0..119 {
        again += run.tick().0.len();
    }
    assert_eq!(again, 0, "silent for the rest of its 2 s cycle");
    assert!(run.first_shots(3).is_some(), "and fires again once it has");
}

#[test]
fn a_friend_or_a_target_out_of_range_is_never_picked() {
    let rows = rows_of(
        &[(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, 300.0, -1000.0), 8.0, 0, 2, LIVE), (3, v(0.0, 300.0, -6000.0), 8.0, 0, 1, LIVE)],
        None,
    );
    let mut run = Run::new(rows, gun(ROLE_DUAL));
    assert!(run.first_shots(120).is_none());
    assert_eq!(run.mounts[0].target, 0);
}

#[test]
fn a_target_below_the_base_is_outside_the_arc() {
    // 30 deg below the base plane: past the cone's -10 deg edge.
    let rows = rows_of(&[(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, -1145.0, -2000.0), 8.0, 0, 1, LIVE)], None);
    let mut run = Run::new(rows, gun(ROLE_DUAL));
    assert!(run.first_shots(120).is_none());
    // Moved up into the arc, it is taken.
    run.rows.positions[1] = v(0.0, 200.0, -2000.0);
    assert!(run.first_shots(60).is_some());
}

#[test]
fn an_anti_fighter_gun_takes_fighters_first_and_an_anti_capital_gun_capitals_first() {
    let bodies = [
        (1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE),
        (2, v(0.0, 500.0, -1500.0), 300.0, 1, 1, LIVE), // a capital, nearer
        (3, v(0.0, 500.0, 2500.0), 8.0, 0, 1, LIVE),    // a fighter, further
    ];
    let mut af = Run::new(rows_of(&bodies, None), gun(ROLE_AF));
    af.tick();
    assert_eq!(af.mounts[0].target, 3);
    let mut ac = Run::new(rows_of(&bodies, None), gun(ROLE_AC));
    ac.tick();
    assert_eq!(ac.mounts[0].target, 2);
    let mut dual = Run::new(rows_of(&bodies, None), gun(ROLE_DUAL));
    dual.tick();
    assert_eq!(dual.mounts[0].target, 2, "a dual gun takes the nearer");
}

#[test]
fn the_ships_order_comes_first_for_its_heavy_guns_but_not_its_anti_fighter_guns() {
    let bodies = [
        (1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE),
        (2, v(0.0, 500.0, -1000.0), 8.0, 0, 1, LIVE),
        (3, v(0.0, 500.0, -3000.0), 8.0, 0, 1, LIVE),
    ];
    let mut run = Run::new(rows_of(&bodies, None), gun(ROLE_AC));
    run.owners[0].order = 3;
    run.tick();
    assert_eq!(run.mounts[0].target, 3);
    let mut af = Run::new(rows_of(&bodies, None), gun(ROLE_AF));
    af.owners[0].order = 3;
    af.tick();
    assert_eq!(af.mounts[0].target, 2);
}

#[test]
fn a_lost_mount_or_no_rate_of_fire_holds_fire() {
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, 400.0, -2000.0), 8.0, 0, 1, LIVE)];
    let mut run = Run::new(rows_of(&bodies, None), gun(ROLE_DUAL));
    run.mounts[0].works = false;
    assert!(run.first_shots(120).is_none());
    run.mounts[0].works = true;
    run.mounts[0].rate = 0.0;
    assert!(run.first_shots(120).is_none());
}

#[test]
fn half_the_rate_of_fire_doubles_the_cycle() {
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, 400.0, -2000.0), 8.0, 0, 1, LIVE)];
    let mut run = Run::new(rows_of(&bodies, None), gun(ROLE_DUAL));
    run.mounts[0].rate = 0.5;
    let (_, t0) = run.first_shots(60).unwrap();
    let mut gap = 0;
    while run.tick().0.is_empty() {
        gap += 1;
        assert!(gap < 400);
    }
    let _ = t0;
    assert!((gap as f64 * DT - 4.0).abs() < 0.05, "4 s between shots at half rate, got {}", gap as f64 * DT);
}

#[test]
fn a_disguised_hostile_is_left_alone_until_it_is_revealed() {
    // Body 2 is faction 1 broadcasting faction 2 (friendly): flags carry 2 + 1.
    let disguised = LIVE | (3 << FLAG_DISGUISE_SHIFT);
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, 400.0, -2000.0), 8.0, 0, 1, disguised)];
    let mut run = Run::new(rows_of(&bodies, None), gun(ROLE_DUAL));
    assert!(run.first_shots(120).is_none());
    run.rows.flags[1] = LIVE;
    assert!(run.first_shots(60).is_some());
}

#[test]
fn its_own_hull_hides_a_target_behind_it() {
    // A turret on the hull's top; the target below the hull, inside the cone's lower edge but the box in the way.
    let bodies = [(1, v(0.0, 0.0, 0.0), 200.0, 1, 0, LIVE), (2, v(0.0, -60.0, -3000.0), 8.0, 0, 1, LIVE)];
    let mut run = Run::new(rows_of(&bodies, Some(hull())), gun(ROLE_DUAL));
    run.mounts[0].local_at = v(0.0, 10.0, 150.0); // aft on the top: the line runs down past the bow
    assert!(run.first_shots(120).is_none(), "the hull hides it");
    run.rows.positions[1] = v(0.0, 300.0, -3000.0);
    assert!(run.first_shots(60).is_some());
}

#[test]
fn a_fixed_gun_holds_its_gimbal_and_a_burst_fires_its_shots_then_waits() {
    let mut spec = gun(ROLE_AC);
    spec.burst_shots = 3;
    spec.burst_spacing_s = 0.35;
    spec.cycle_s = 10.0;
    spec.elevation_rad_s = 6f64.to_radians();
    // On the bow, axis forward, 8 deg each way, resting on the axis.
    let mount = Mount::new(1, 1, v(0.0, 0.0, -200.0), v(0.0, 0.0, -1.0), v(0.0, 1.0, 0.0), 8f64.to_radians(), true, 10.0, spec);
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(1500.0, 0.0, -3000.0), 400.0, 1, 1, LIVE)];
    let mut run = Run::with(rows_of(&bodies, None), mount);
    assert!(run.first_shots(120).is_none(), "26 deg off the bow: outside its gimbal");
    run.rows.positions[1] = v(200.0, 0.0, -3000.0);
    let mut times = Vec::new();
    for t in 0..800 {
        if !run.tick().0.is_empty() {
            times.push(t);
        }
    }
    assert!(times.len() >= 4, "a burst of three and the next burst's first: {times:?}");
    let s = |k: usize| (times[k] - times[0]) as f64 * DT;
    assert!((s(1) - 0.35).abs() < 0.03 && (s(2) - 0.7).abs() < 0.03, "{times:?}");
    assert!((s(3) - 10.0).abs() < 0.03, "the next burst a cycle after the first began: {times:?}");
}

#[test]
fn a_burst_cut_short_by_a_lost_target_recharges_from_its_start() {
    // Q76's pulse cannon: three shots half a second apart, the next burst 3 s after one began.
    let mut spec = gun(ROLE_DUAL);
    spec.burst_shots = 3;
    spec.burst_spacing_s = 0.5;
    spec.cycle_s = 3.0;
    let near = v(0.0, 400.0, -2000.0);
    let rows = rows_of(&[(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, near, 8.0, 0, 1, LIVE)], None);
    let mut run = Run::new(rows, spec);
    let (_, first) = run.first_shots(60).expect("it opens fire");
    // Out of reach before the second shot: the burst ends.
    run.rows.positions[1] = v(0.0, 400.0, -9000.0);
    for _ in 0..20 {
        assert!(run.tick().0.is_empty());
    }
    assert_eq!(run.mounts[0].burst_fired, 0, "the burst is over");
    run.rows.positions[1] = near;
    let (_, next) = run.first_shots(400).expect("it fires again once recharged");
    let _ = first;
    let gap = (21 + next) as f64 * DT;
    assert!((gap - 3.0).abs() < 0.05, "the next burst a cycle after the cut one began, not its second shot: {gap}");
    // A whole burst on a target that stays: three shots, then the recharge.
    let mut times = vec![0usize];
    for t in 1..400 {
        if !run.tick().0.is_empty() {
            times.push(t);
        }
    }
    let s = |k: usize| (times[k] - times[0]) as f64 * DT;
    assert!(times.len() >= 4, "{times:?}");
    assert!((s(1) - 0.5).abs() < 0.03 && (s(2) - 1.0).abs() < 0.03 && (s(3) - 3.0).abs() < 0.03, "{times:?}");
}

#[test]
fn twin_barrels_fire_together_with_their_own_spread() {
    let mut spec = gun(ROLE_DUAL);
    spec.barrels = 2;
    spec.spread_rad = 0.5f64.to_radians();
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, 400.0, -2000.0), 30.0, 0, 1, LIVE)];
    let mut run = Run::new(rows_of(&bodies, None), spec);
    let (shots, _) = run.first_shots(60).unwrap();
    assert_eq!(shots.len(), 2);
    assert_ne!(shots[0].velocity, shots[1].velocity);
}

#[test]
fn a_launcher_fires_a_salvo_at_its_target_between_its_cell_and_the_target() {
    let mut spec = launcher(ROLE_AF);
    spec.barrels = 2;
    // Cells facing up on the top, a hemisphere.
    let mount = Mount::new(1, 1, v(0.0, 10.0, 0.0), v(0.0, 1.0, 0.0), v(0.0, 0.0, -1.0), 90f64.to_radians(), true, 0.0, spec);
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, 10.0, -5000.0), 8.0, 0, 1, LIVE)];
    let mut run = Run::with(rows_of(&bodies, None), mount);
    let (shots, _) = run.first_shots(30).expect("it launches");
    assert_eq!(shots.len(), 2);
    for s in &shots {
        assert_eq!(s.target, 2);
        let d = normalized(s.velocity);
        assert!(d.y > 0.5 && d.z < -0.5, "between straight up and the target: {d:?}");
        assert!((f64::from(length(s.velocity)) - 350.0).abs() < 0.01);
    }
    assert!(run.first_shots(600).is_none(), "reloading for 12 s");
}

#[test]
fn a_torpedo_takes_capitals_only() {
    let mut spec = launcher(ROLE_AC);
    spec.warhead = WARHEAD_TORPEDO;
    let mount = Mount::new(1, 1, v(0.0, 0.0, -200.0), v(0.0, 0.0, -1.0), v(0.0, 1.0, 0.0), 45f64.to_radians(), true, 0.0, spec);
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, 0.0, -2000.0), 8.0, 0, 1, LIVE)];
    let mut run = Run::with(rows_of(&bodies, None), mount);
    assert!(run.first_shots(60).is_none());
    run.rows.radii[1] = 400.0;
    run.rows.kinds[1] = 1;
    assert!(run.first_shots(60).is_some());
}

#[test]
fn a_missile_turns_toward_its_target_and_leaves_the_list_once_its_bolt_is_gone() {
    let rows = rows_of(&[(2, v(1000.0, 0.0, -3000.0), 8.0, 0, 1, LIVE)], None);
    let mut bolts = Bolts::default();
    bolts.insert_owned(-1, v(0.0, 0.0, 0.0), v(0.0, 0.0, -350.0), 0, 1, 3, 2.0, 40.0, [1.0; 4], 0, 20.0, 0);
    let mut missiles = vec![Missile { bolt: -1, target: 2, mount: 0, nav_gain: 4.0, turn_rad_s: 0.6, warhead: WARHEAD_MISSILE }];
    let hull_rows = [0_u32];
    let hostile = table();
    let world = GunWorld {
        rows: &rows,
        hull_rows: &hull_rows,
        owner_rows: &[],
        hostile: &hostile,
        factions: 3,
        row_of: |id: i64| rows.body_ids.iter().position(|&b| b == id),
        rest: Vector3::ZERO,
    };
    // A still target off to the side: PN alone turns a missile flying straight at the line's start, so move the target.
    let mut moving = rows.clone();
    moving.velocities[0] = v(-100.0, 0.0, 0.0);
    moving.rigid[0] = true;
    let world_moving = GunWorld { rows: &moving, ..world };
    let mut out = Vec::new();
    steer_missiles(&mut missiles, &bolts, &world_moving, DT, &mut out);
    assert_eq!(out.len(), 1);
    let (i, vel) = out[0];
    assert_eq!(i, 0);
    assert!((f64::from(length(vel)) - 350.0).abs() < 1e-3, "same speed");
    assert_ne!(vel, v(0.0, 0.0, -350.0), "turned");
    bolts.spent[0] = true;
    out.clear();
    steer_missiles(&mut missiles, &bolts, &world_moving, DT, &mut out);
    assert!(missiles.is_empty());
}

#[test]
fn a_ship_out_of_the_rows_holds_its_state_and_two_runs_fire_alike() {
    let bodies = [
        (1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE),
        (2, v(300.0, 400.0, -2000.0), 8.0, 0, 1, LIVE),
        (3, v(-300.0, 600.0, -1500.0), 8.0, 0, 1, LIVE),
    ];
    let mut spec = gun(ROLE_DUAL);
    spec.spread_rad = 0.3f64.to_radians();
    let mut a = Run::new(rows_of(&bodies, None), spec);
    let mut b = Run::new(rows_of(&bodies, None), spec);
    let mut shots_a = Vec::new();
    let mut shots_b = Vec::new();
    for _ in 0..400 {
        shots_a.extend(a.tick().0);
        shots_b.extend(b.tick().0);
    }
    assert!(!shots_a.is_empty());
    assert_eq!(shots_a, shots_b);
    assert_eq!(a.mounts, b.mounts);
    // Out of the rows: nothing moves.
    let mut parked = Run::new(rows_of(&bodies[1..], None), spec);
    let before = parked.mounts.clone();
    assert!(parked.first_shots(60).is_none());
    assert_eq!(parked.mounts, before);
}

// Q71: a fixed gun with no gimbal holds a target its wide pick cone sees, but fires only once the line along its axis meets it.
#[test]
fn a_fixed_gun_with_no_gimbal_fires_only_when_its_line_meets_the_target() {
    let spec = gun(ROLE_DUAL);
    let mount = Mount::new(1, 1, v(0.0, 0.0, -200.0), v(0.0, 0.0, -1.0), v(0.0, 1.0, 0.0), 0.0, true, 10.0, spec)
        .with_pick_cone(30f64.to_radians());
    assert!(mount.fixed);
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(600.0, 0.0, -2000.0), 8.0, 0, 1, LIVE)];
    let mut run = Run::with(rows_of(&bodies, None), mount);
    assert!(run.first_shots(60).is_none(), "17 deg off its line: held, not fired");
    assert_eq!(run.mounts[0].target, 2, "the wide cone holds it for the helm");
    run.rows.positions[1] = v(5.0, 0.0, -2000.0);
    let (shots, _) = run.first_shots(5).expect("on its line it fires");
    let d = normalized(shots[0].velocity);
    assert!(d.z < -0.9999, "straight along the axis: {d:?}");
}

// A fixed gun at a big hull fires when its line crosses the hull's surface, though the hull's centre is well off the line.
#[test]
fn a_fixed_gun_fires_when_its_line_crosses_a_big_hulls_surface() {
    let spec = gun(ROLE_AC);
    let mount = Mount::new(1, 1, v(0.0, 0.0, -200.0), v(0.0, 0.0, -1.0), v(0.0, 1.0, 0.0), 0.0, true, 10.0, spec)
        .with_pick_cone(30f64.to_radians());
    // A long hull lying across the line 3 km ahead, its centre 150 m to the side: its box reaches 200 m along x.
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(150.0, 0.0, -3000.0), 210.0, 1, 1, LIVE)];
    let mut rows = rows_of(&bodies, None);
    rows.roles[1] = ROLE_SURFACE;
    let across = from_packed(&[0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 200.0, 10.0, 20.0], 0.0);
    let mut map = HashMap::new();
    map.insert(2_i64, Arc::new(across));
    rows.surfaces = Some(Arc::new(map));
    let mut run = Run::with(rows, mount);
    assert!(run.first_shots(5).is_some(), "the line meets the hull's near end");
    run.rows.positions[1] = v(260.0, 0.0, -3000.0);
    run.mounts[0].ready_at = f64::NEG_INFINITY;
    assert!(run.first_shots(5).is_none(), "moved 110 m on, the hull's end is past the line");
}

// A big hull whose centre its own hull hides is aimed at on a surface volume that shows past it; one wholly hidden waits longer.
#[test]
fn a_gun_aims_at_the_part_of_a_big_hull_its_own_hull_does_not_hide() {
    let bodies = [(1, v(0.0, 0.0, 0.0), 210.0, 1, 0, LIVE), (2, v(0.0, -60.0, -1500.0), 120.0, 1, 1, LIVE)];
    let mut rows = rows_of(&bodies, Some(hull()));
    rows.roles[1] = ROLE_SURFACE;
    // Its hull low below the shooter's deck line, a tower rising above it.
    let target = from_packed(
        &[
            0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 30.0, 20.0, 100.0, //
            0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 80.0, 0.0, 10.0, 20.0, 10.0,
        ],
        0.0,
    );
    if let Some(map) = rows.surfaces.as_mut() {
        Arc::make_mut(map).insert(2, Arc::new(target));
    }
    let mut run = Run::new(rows, gun(ROLE_AC));
    run.tick();
    assert_eq!(run.mounts[0].target, 2, "picked on the part that shows");
    assert_eq!(run.mounts[0].aim_local, v(0.0, 80.0, 0.0), "the tower, not the hidden centre");
    // Lower the tower out of sight: wholly hidden, it is passed over and looked for again only after `HIDDEN_WAIT`.
    let mut hidden = run.rows.clone();
    hidden.positions[1] = v(0.0, -200.0, -1500.0);
    let mut low = Run::new(hidden, gun(ROLE_AC));
    let (_, tally) = low.tick();
    assert_eq!(low.mounts[0].target, 0);
    assert!(tally.hidden > 0);
    assert_eq!(low.mounts[0].pick_wait, HIDDEN_WAIT - 1);
}

// A fixed gun's own pod, lying in front of its pivot round the barrel, never hides its target: its line starts at the muzzle.
#[test]
fn a_fixed_guns_pod_round_its_barrel_does_not_hide_the_target() {
    let spec = gun(ROLE_DUAL);
    // The hull, and a fairing 10 to 30 m ahead of the gun's pivot; the 40 m barrel reaches past it.
    let hull_and_pod = from_packed(
        &[
            0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0, 10.0, 200.0, //
            0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 30.0, 0.0, -215.0, 5.0, 5.0, 10.0,
        ],
        0.0,
    );
    let mount = Mount::new(1, 1, v(30.0, 0.0, -195.0), v(0.0, 0.0, -1.0), v(1.0, 0.0, 0.0), 0.0, true, 40.0, spec)
        .with_pick_cone(30f64.to_radians());
    let bodies = [(1, v(0.0, 0.0, 0.0), 210.0, 1, 0, LIVE), (2, v(30.0, 0.0, -3000.0), 8.0, 0, 1, LIVE)];
    let mut run = Run::with(rows_of(&bodies, Some(hull_and_pod)), mount);
    let (shots, _) = run.first_shots(10).expect("it fires past its pod");
    assert!(shots[0].start.z < -230.0, "from its muzzle: {:?}", shots[0].start);
}

// A fixed gun whose line meets only a big hull's rotating section fires: the sweep lands bolts there as on the hull.
#[test]
fn a_fixed_gun_fires_when_its_line_meets_the_targets_rotating_section() {
    let spec = gun(ROLE_AC);
    let mount = Mount::new(1, 1, v(0.0, 0.0, -200.0), v(0.0, 0.0, -1.0), v(0.0, 1.0, 0.0), 0.0, true, 10.0, spec)
        .with_pick_cone(30f64.to_radians());
    // The hull 3 km ahead, 300 m off the line; its drum (body 3) lies on the line.
    let bodies = [
        (1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE),
        (2, v(300.0, 0.0, -3000.0), 320.0, 1, 1, LIVE),
        (3, v(0.0, 0.0, -3000.0), 40.0, 1, 1, LIVE),
    ];
    let mut rows = rows_of(&bodies, None);
    rows.roles[1] = ROLE_SURFACE;
    rows.roles[2] = ROLE_SURFACE;
    rows.ids[2] = rows.body_ids[2]; // no marker of its own: not a target in itself
    let box_of = |half: f64| from_packed(&[0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, half, 20.0, 20.0], 0.0);
    let mut drum = box_of(30.0);
    drum.named_by = 2;
    let mut map = HashMap::new();
    map.insert(2_i64, Arc::new(box_of(100.0)));
    map.insert(3_i64, Arc::new(drum));
    rows.surfaces = Some(Arc::new(map));
    let mut run = Run::with(rows.clone(), mount.clone());
    let (shots, _) = run.first_shots(5).expect("the drum is on its line");
    assert_eq!(shots[0].target, 2, "fired at the hull the drum belongs to");
    // Without the drum the line meets nothing: held.
    if let Some(map) = rows.surfaces.as_mut() {
        Arc::make_mut(map).remove(&3);
    }
    let mut bare = Run::with(rows, mount);
    assert!(bare.first_shots(5).is_none());
}

// Review round: a held target is weighed again on the pick beat, so a role's preference holds after the pick too.
#[test]
fn an_anti_fighter_gun_holding_a_capital_turns_to_a_fighter_that_comes_in() {
    let bodies = [
        (1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE),
        (2, v(0.0, 500.0, -1500.0), 300.0, 1, 1, LIVE), // a capital
        (3, v(0.0, 500.0, 9000.0), 8.0, 0, 1, LIVE),    // a fighter, out of reach for now
    ];
    let mut run = Run::new(rows_of(&bodies, None), gun(ROLE_AF));
    run.tick();
    assert_eq!(run.mounts[0].target, 2, "nothing better: it takes the capital");
    run.rows.positions[2] = v(0.0, 500.0, 2500.0);
    for _ in 0..PICK_EVERY {
        run.tick();
    }
    assert_eq!(run.mounts[0].target, 3, "a fighter in reach: the capital is dropped by the next beat");
    // A nearer fighter does not take it off the one it holds.
    run.rows.positions[1] = v(0.0, 500.0, -800.0);
    run.rows.radii[1] = 8.0;
    run.rows.kinds[1] = 0;
    for _ in 0..3 * PICK_EVERY {
        run.tick();
    }
    assert_eq!(run.mounts[0].target, 3);
}

#[test]
fn an_order_given_while_a_heavy_gun_holds_a_target_is_taken_on_the_next_beat() {
    let bodies = [
        (1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE),
        (2, v(0.0, 500.0, -1000.0), 300.0, 1, 1, LIVE),
        (3, v(0.0, 500.0, -3000.0), 300.0, 1, 1, LIVE),
    ];
    let mut run = Run::new(rows_of(&bodies, None), gun(ROLE_AC));
    run.tick();
    assert_eq!(run.mounts[0].target, 2);
    run.owners[0].order = 3;
    for _ in 0..PICK_EVERY {
        run.tick();
    }
    assert_eq!(run.mounts[0].target, 3);
}

// Review round: a disabled capital is engaged last, only when nothing live is in reach.
#[test]
fn a_disabled_capital_is_taken_only_when_no_live_hostile_is_in_reach() {
    let bodies = [
        (1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE),
        (2, v(0.0, 500.0, -1000.0), 300.0, 1, 1, LIVE | FLAG_DISABLED), // disabled, nearer
        (3, v(0.0, 500.0, -3000.0), 300.0, 1, 1, LIVE),
        (4, v(0.0, 500.0, 2000.0), 8.0, 0, 1, LIVE), // a live fighter
    ];
    let mut ac = Run::new(rows_of(&bodies, None), gun(ROLE_AC));
    ac.tick();
    assert_eq!(ac.mounts[0].target, 3, "the live capital first");
    let mut only_fighter = Run::new(rows_of(&[bodies[0], bodies[1], bodies[3]], None), gun(ROLE_AC));
    only_fighter.tick();
    assert_eq!(only_fighter.mounts[0].target, 4, "a live fighter before a disabled capital, even for a heavy gun");
    let mut alone = Run::new(rows_of(&bodies[..2], None), gun(ROLE_AC));
    alone.tick();
    assert_eq!(alone.mounts[0].target, 2, "nothing live: the hulk is fair game");
    // Holding the disabled hull, it turns to a live one that comes into reach.
    alone.rows = rows_of(&bodies[..3], None);
    for _ in 0..PICK_EVERY {
        alone.tick();
    }
    assert_eq!(alone.mounts[0].target, 3);
}

// Review round: a launcher fires only at what its rounds reach with time to spare (a torpedo's range was its whole flight).
#[test]
fn a_torpedo_is_launched_only_within_nine_tenths_of_its_flight() {
    let mut spec = launcher(ROLE_AC);
    spec.warhead = WARHEAD_TORPEDO;
    spec.speed_mps = 250.0;
    spec.lifetime_s = 40.0;
    spec.range_m = 10_000.0;
    assert!((spec.reach_m() - 9000.0).abs() < 1e-9);
    let mount = Mount::new(1, 1, v(0.0, 0.0, -200.0), v(0.0, 0.0, -1.0), v(0.0, 1.0, 0.0), 45f64.to_radians(), true, 0.0, spec);
    // Its near side 9 500 m from the tube: in range, out of the torpedo's reach.
    let bodies = [(1, v(0.0, 0.0, 0.0), 60.0, 1, 0, LIVE), (2, v(0.0, 0.0, -10_100.0), 400.0, 1, 1, LIVE)];
    let mut run = Run::with(rows_of(&bodies, None), mount);
    assert!(run.first_shots(120).is_none());
    run.rows.positions[1] = v(0.0, 0.0, -9_100.0);
    assert!(run.first_shots(60).is_some(), "8 500 m off: launched");
    assert_eq!(gun(ROLE_AC).reach_m(), 4000.0, "a gun's reach is its range");
}

// Review round: a ship leaving takes its mounts; missiles in flight keep naming their own mount, the gone ship's none.
#[test]
fn a_ship_leaving_keeps_every_other_missile_on_its_own_mount() {
    let spec = launcher(ROLE_DUAL);
    let at = v(0.0, 0.0, 0.0);
    let up = v(0.0, 1.0, 0.0);
    let fwd = v(0.0, 0.0, -1.0);
    let mut mounts = vec![
        Mount::new(10, 1, at, up, fwd, 1.0, true, 0.0, spec),
        Mount::new(20, 2, at, up, fwd, 1.0, true, 0.0, spec),
        Mount::new(10, 3, at, up, fwd, 1.0, true, 0.0, spec),
        Mount::new(30, 4, at, up, fwd, 1.0, true, 0.0, spec),
    ];
    let mut owners = vec![
        Owner { body: 10, bodies: vec![10], order: 0 },
        Owner { body: 20, bodies: vec![20], order: 0 },
        Owner { body: 30, bodies: vec![30], order: 0 },
    ];
    let mut owner_of = vec![0, 1, 0, 2];
    let missile = |mount: u32| Missile { bolt: -1, target: 0, mount, nav_gain: 4.0, turn_rad_s: 0.6, warhead: WARHEAD_MISSILE };
    let mut missiles = vec![missile(0), missile(1), missile(2), missile(3)];
    remove_owner(&mut mounts, &mut owners, &mut owner_of, &mut missiles, 10);
    assert_eq!(mounts.iter().map(|m| m.id).collect::<Vec<_>>(), vec![2, 4]);
    assert_eq!(owner_of, vec![0, 1]);
    let named: Vec<u32> = missiles.iter().map(|m| m.mount).collect();
    assert_eq!(named, vec![NO_MOUNT, 0, NO_MOUNT, 1], "ship 20's on its mount, ship 30's on its own, ship 10's on none");
    remove_owner(&mut mounts, &mut owners, &mut owner_of, &mut missiles, 99);
    assert_eq!(mounts.len(), 2, "an unknown ship changes nothing");
}

// Review round: a pick reuses its buffers, and a re-weigh on the beat stays deterministic.
#[test]
fn picks_on_the_beat_with_reused_buffers_fire_alike_on_two_runs() {
    let bodies = [
        (1, v(0.0, 0.0, 0.0), 200.0, 1, 0, LIVE),
        (2, v(0.0, 300.0, -3000.0), 300.0, 1, 1, LIVE | FLAG_DISABLED),
        (3, v(200.0, 400.0, -2000.0), 8.0, 0, 1, LIVE),
        (4, v(-300.0, 600.0, 1500.0), 8.0, 0, 1, LIVE),
    ];
    let mut spec = gun(ROLE_AF);
    spec.spread_rad = 0.3f64.to_radians();
    let mut a = Run::new(rows_of(&bodies, Some(hull())), spec);
    let mut b = Run::new(rows_of(&bodies, Some(hull())), spec);
    let (mut sa, mut sb) = (Vec::new(), Vec::new());
    for t in 0..600 {
        if t == 200 {
            a.rows.positions[2] = v(200.0, 400.0, -9000.0);
            b.rows.positions[2] = v(200.0, 400.0, -9000.0);
        }
        sa.extend(a.tick().0);
        sb.extend(b.tick().0);
    }
    assert!(!sa.is_empty());
    assert_eq!(sa, sb);
    assert_eq!(a.mounts, b.mounts);
}
