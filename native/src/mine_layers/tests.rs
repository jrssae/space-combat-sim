// The battle's mine layers (M10-T15, Q20), beside the kernel and outside its engine-free guard (test builds only).
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::Basis;

use super::*;
use crate::rows::{FLAG_RIGID, ROLE_COMBAT, ROLE_SURFACE};
use crate::surface::from_packed;

const LIVE: u32 = FLAG_RIGID | FLAG_HULL_ACTIVE;
const US: u32 = 0;
const THEM: u32 = 1;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

fn specs() -> [Spec; KINDS] {
    let mut s = [Spec::NONE; KINDS];
    s[ENERGY as usize] = Spec { speed_mps: 900.0, capitals_only: true, ..Spec::NONE };
    s[GUIDED as usize] = Spec { speed_mps: 150.0, dormant_s: 60.0, ..Spec::NONE };
    s
}

fn rows_of(bodies: &[(i64, u32, Vector3, f64)]) -> Rows {
    let mut rows = Rows::default();
    for &(body, faction, at, radius) in bodies {
        rows.body_ids.push(body);
        rows.ids.push(body);
        rows.faction_ix.push(faction);
        rows.positions.push(at);
        rows.velocities.push(Vector3::ZERO);
        rows.bases.push(Basis::IDENTITY);
        rows.angular.push(Vector3::ZERO);
        rows.radii.push(radius);
        rows.kinds.push(if radius > 100.0 { 1 } else { 0 });
        rows.flags.push(LIVE);
        rows.hull_ids.push(body + 1000);
        rows.handles.push(body);
        rows.rigid.push(true);
        rows.is_static.push(false);
        rows.is_mine.push(false);
        rows.hull_fraction.push(1.0);
        rows.target_ids.push(-1);
        rows.reach.push(0.0);
        rows.name_ids.push(0);
        rows.roles.push(if radius > 100.0 { ROLE_SURFACE } else { ROLE_COMBAT });
    }
    rows.node_count = bodies.len();
    rows
}

fn layer(kind: u8) -> Layer {
    let guided = kind == GUIDED;
    Layer {
        owner: 1,
        local: Vector3::ZERO,
        forward: v(0.0, 0.0, if guided { 1.0 } else { -1.0 }),
        kind,
        works: true,
        range_min_m: if guided { 0.0 } else { 4000.0 },
        range_m: if guided { 3000.0 } else { 12000.0 },
        cycle_s: if guided { 30.0 } else { 20.0 },
        count: if guided { 4 } else { 1 },
        max_in_play: 12,
        cone_cos: 60.0_f64.to_radians().cos(),
        drop_mps: 20.0,
        clearance_m: 10.0,
        next_at: 0.0,
        search_at: 0.0,
    }
}

fn lay(layers: &mut [Layer], mines: &Mines, rows: &Rows, now_s: f64) -> Vec<Lay> {
    let hostile = vec![false, true, true, false];
    let order: Vec<u32> = (0..rows.positions.len() as u32).collect();
    let owners: Vec<i32> = layers.iter().map(|l| rows.body_ids.iter().position(|&b| b == l.owner).map_or(-1, |r| r as i32)).collect();
    let view = View { rows, hull_rows: &order, owner_rows: &owners, hostile: &hostile, factions: 2, frame_velocity: Vector3::ZERO, now_s };
    let mut out = Vec::new();
    decide(layers, mines, &specs(), &view, &mut out);
    out
}

#[test]
fn an_energy_launcher_sends_a_mine_at_a_hostile_capital_in_range_aimed_ahead_of_it() {
    // The G'Quan (body 1, row 0) at the origin, a hostile capital 6 km ahead drifting across at 100 m/s, a fighter nearer.
    let mut rows = rows_of(&[(1, US, Vector3::ZERO, 200.0), (2, THEM, v(0.0, 0.0, -6000.0), 300.0), (3, THEM, v(0.0, 0.0, -2000.0), 8.0)]);
    rows.velocities[1] = v(100.0, 0.0, 0.0);
    let mut layers = [layer(ENERGY)];
    let out = lay(&mut layers, &Mines::default(), &rows, 1.0);
    assert_eq!(out.len(), 1, "one mine at the capital, none at the fighter");
    let l = out[0];
    assert_eq!(l.kind, ENERGY);
    assert!(l.dest.x > 600.0 && l.dest.x < 800.0, "aimed ahead of a target that crosses 100 m/s for the flight's {} s: {:?}", 6.7, l.dest);
    assert!((f64::from(crate::v3::length(l.vel)) - 900.0).abs() < 1e-2);
    assert!(l.vel.z < 0.0 && l.vel.x > 0.0);
    // It waits out its cycle, then lays again.
    assert!(lay(&mut layers, &Mines::default(), &rows, 10.0).is_empty());
    assert_eq!(lay(&mut layers, &Mines::default(), &rows, 21.5).len(), 1);
}

#[test]
fn an_energy_launcher_leaves_a_capital_outside_its_range_or_cone_alone() {
    let rows = rows_of(&[(1, US, Vector3::ZERO, 200.0), (2, THEM, v(0.0, 0.0, -3000.0), 300.0), (3, THEM, v(0.0, 0.0, 8000.0), 300.0)]);
    let mut layers = [layer(ENERGY)];
    assert!(lay(&mut layers, &Mines::default(), &rows, 1.0).is_empty(), "3 km is too near and the one astern is outside the fore cone");
    let rows = rows_of(&[(1, US, Vector3::ZERO, 200.0), (2, US, v(0.0, 0.0, -6000.0), 300.0)]);
    let mut layers = [layer(ENERGY)];
    assert!(lay(&mut layers, &Mines::default(), &rows, 1.0).is_empty(), "never at a friend");
}

#[test]
fn a_guided_layer_drops_mines_astern_while_a_hostile_is_on_its_tail_up_to_its_cap() {
    let rows = rows_of(&[(1, US, Vector3::ZERO, 100.0), (2, THEM, v(0.0, 0.0, 2000.0), 20.0)]);
    let mut layers = [layer(GUIDED)];
    layers[0].local = v(0.0, 0.0, 90.0);
    let out = lay(&mut layers, &Mines::default(), &rows, 1.0);
    assert_eq!(out.len(), 4, "four a drop");
    assert!(out.iter().all(|l| l.kind == GUIDED && l.vel.z > 0.0 && l.from.z > 99.0));
    let xs: Vec<f32> = out.iter().map(|l| l.from.x).collect();
    assert!(xs.windows(2).all(|w| w[0] < w[1]), "dropped side by side: {xs:?}");
    // A hostile ahead of it does not draw a drop, and the cap holds the count in play.
    let rows_ahead = rows_of(&[(1, US, Vector3::ZERO, 100.0), (2, THEM, v(0.0, 0.0, -2000.0), 20.0)]);
    let mut layers = [layer(GUIDED)];
    assert!(lay(&mut layers, &Mines::default(), &rows_ahead, 1.0).is_empty());
    let mut mines = Mines::default();
    for _ in 0..10 {
        mines.lay(None, GUIDED, US, Vector3::ZERO, v(0.0, 0.0, 20.0), crate::mine_kernels::DORMANT, 0.0, &specs()[GUIDED as usize], 1);
    }
    let mut layers = [layer(GUIDED)];
    assert_eq!(lay(&mut layers, &mines, &rows, 1.0).len(), 2, "12 in play at most: ten there, two more");
}

#[test]
fn a_disabled_ship_or_a_lost_mount_lays_nothing() {
    let mut rows = rows_of(&[(1, US, Vector3::ZERO, 100.0), (2, THEM, v(0.0, 0.0, 2000.0), 20.0)]);
    rows.flags[0] |= FLAG_DISABLED;
    let mut layers = [layer(GUIDED)];
    assert!(lay(&mut layers, &Mines::default(), &rows, 1.0).is_empty());
    rows.flags[0] = LIVE;
    layers[0].works = false;
    assert!(lay(&mut layers, &Mines::default(), &rows, 1.0).is_empty());
}

#[test]
fn an_energy_mine_stops_a_stand_off_short_of_the_capitals_surface_not_at_its_centre() {
    // A box hull (half extents 20 x 10 x 200) 6 km dead ahead of the G'Quan, at rest: its bow face is at z = -5 800.
    let mut rows = rows_of(&[(1, US, Vector3::ZERO, 200.0), (2, THEM, v(0.0, 0.0, -6000.0), 260.0)]);
    let hull = from_packed(&[0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0, 10.0, 200.0], 0.0);
    let mut map = HashMap::new();
    map.insert(2_i64, Arc::new(hull));
    rows.surfaces = Some(Arc::new(map));
    let mut layers = [layer(ENERGY)];
    let out = lay(&mut layers, &Mines::default(), &rows, 1.0);
    assert_eq!(out.len(), 1);
    let stop = out[0].dest.z;
    assert!((f64::from(stop) + 5700.0).abs() < 15.0, "it stops 100 m off the bow face, not at the centre: z = {stop}");
}
