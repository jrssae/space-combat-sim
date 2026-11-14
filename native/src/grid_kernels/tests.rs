// The station grid's kernels (M7-T07, D75): each gun kind's pick, the latch, the interceptor's choice and reach, beams
// immune, the station's hull blocking its guns, the drum's skin speed in a shot.
use std::collections::HashMap;
use std::sync::Arc;

use super::*;
use crate::kernels::contact::sorted_cells_into;
use crate::rows::{FLAG_HULL_ACTIVE, FLAG_RIGID, ROLE_SURFACE, Surface};
use crate::turret_kernels::{PICK_REACH, REL_NEUTRAL};

const STATION: i64 = 100;
const KIND_BEAM: u8 = 8;
// Factions: 0 the station's people, 1 raiders (hostile), 2 a second hostile people, 3 neutral.
const STRIDE: usize = 4;

fn table() -> Vec<u8> {
    let (f, n, h) = (REL_FRIENDLY, REL_NEUTRAL, REL_HOSTILE);
    vec![
        f, h, h, n, //
        h, f, h, h, //
        h, h, f, h, //
        n, h, h, f,
    ]
}

// The station: one box 100 m across and 1 000 m long about its origin, spinning at `spin` about +z.
fn station_surface(spin: f64) -> Surface {
    let p = vec![0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 50.0, 50.0, 500.0];
    surface::from_packed(&p, spin)
}

// Row 0 the station (a big hull, no rigid body), then a ship per `(body, faction, at, capital)`.
fn rows_with(ships: &[(i64, u32, Vector3, bool)], spin: f64) -> Rows {
    let mut map = HashMap::new();
    map.insert(STATION, Arc::new(station_surface(spin)));
    let mut rows = Rows {
        body_ids: vec![STATION],
        ids: vec![STATION],
        positions: vec![Vector3::ZERO],
        velocities: vec![Vector3::ZERO],
        bases: vec![Basis::IDENTITY],
        radii: vec![510.0],
        rigid: vec![false],
        is_static: vec![false],
        is_mine: vec![false],
        reach: vec![0.0],
        faction_ix: vec![0],
        flags: vec![FLAG_HULL_ACTIVE],
        kinds: vec![6],
        roles: vec![ROLE_SURFACE],
        surfaces: Some(Arc::new(map)),
        ..Rows::default()
    };
    for &(body, faction, at, capital) in ships {
        rows.body_ids.push(body);
        rows.ids.push(body);
        rows.positions.push(at);
        rows.velocities.push(Vector3::ZERO);
        rows.bases.push(Basis::IDENTITY);
        rows.radii.push(if capital { 200.0 } else { 8.0 });
        rows.rigid.push(true);
        rows.is_static.push(false);
        rows.is_mine.push(false);
        rows.reach.push(0.0);
        rows.faction_ix.push(faction);
        rows.flags.push(FLAG_RIGID | FLAG_HULL_ACTIVE);
        rows.kinds.push(if capital { KIND_CAPITAL } else { 0 });
        rows.roles.push(0);
    }
    rows
}

fn finder(rows: &Rows) -> impl Fn(i64) -> i64 + '_ {
    move |b| rows.body_ids.iter().position(|&x| x == b).map_or(-1, |r| r as i64)
}

// A gun on top of the station, its base facing up.
fn gun(kind: u8, range_m: f64) -> PickMount {
    PickMount {
        slot: 0,
        stamp: 1,
        body: STATION,
        faction_ix: 0,
        local: Vector3::new(0.0, 52.0, 0.0),
        up: Vector3::new(0.0, 1.0, 0.0),
        min_elevation: (-10_f64).to_radians(),
        reach_m: range_m * PICK_REACH,
        kind,
    }
}

fn grid_of(rows: &Rows) -> Grid {
    let mut grid = Grid { cell_m: 5000.0, ..Grid::default() };
    sorted_cells_into(&rows.positions, grid.cell_m, &mut grid.cells);
    grid
}

fn pick_with(rows: &Rows, m: &PickMount, latch: &Latch) -> i64 {
    let grid = grid_of(rows);
    let (mut query, mut found) = (Query::default(), Vec::new());
    let surface_rows = vec![0_usize];
    let relations = table();
    let mut ctx = PickCtx {
        relations: &relations,
        stride: STRIDE,
        latch,
        surface_rows: &surface_rows,
        grid: &grid,
        query: &mut query,
        found: &mut found,
    };
    pick(rows, &finder(rows), m, &mut ctx)
}

fn free_against(sides: &[u32]) -> Latch {
    let mut latch = Latch::default();
    for &s in sides {
        latch.set(0, s);
    }
    latch
}

#[test]
fn the_guns_hold_fire_until_the_latch_frees_them() {
    let rows = rows_with(&[(1, 1, Vector3::new(0.0, 900.0, 0.0), false)], 0.0);
    assert_eq!(pick_with(&rows, &gun(MOUNT_LIGHT, 3000.0), &Latch::default()), 0, "never first");
    assert_eq!(pick_with(&rows, &gun(MOUNT_LIGHT, 3000.0), &free_against(&[1])), 1);
    assert_eq!(pick_with(&rows, &gun(MOUNT_LIGHT, 3000.0), &free_against(&[2])), 0, "free against another side only");
}

#[test]
fn a_light_turret_takes_the_nearest_fighter_first_and_a_capital_when_none_is_in_reach() {
    let rows = rows_with(
        &[
            (1, 1, Vector3::new(0.0, 300.0, 0.0), true),
            (2, 1, Vector3::new(0.0, 1500.0, 0.0), false),
            (3, 1, Vector3::new(0.0, 900.0, 0.0), false),
            (4, 1, Vector3::new(0.0, 5000.0, 0.0), false),
        ],
        0.0,
    );
    assert_eq!(pick_with(&rows, &gun(MOUNT_LIGHT, 3000.0), &free_against(&[1])), 3, "the nearest fighter, not the nearer capital");
    let rows = rows_with(&[(1, 1, Vector3::new(0.0, 300.0, 0.0), true), (4, 1, Vector3::new(0.0, 5000.0, 0.0), false)], 0.0);
    assert_eq!(pick_with(&rows, &gun(MOUNT_LIGHT, 3000.0), &free_against(&[1])), 1, "the capital when no fighter is in reach");
}

#[test]
fn a_knocked_out_mount_is_left_out_of_the_pick_and_shows_as_a_dead_point() {
    let rows = rows_with(&[(1, 1, Vector3::new(0.0, 900.0, 0.0), false)], 0.0);
    let mut m = tk::Mounts::default();
    let gun_spec = tk::Gun { range_m: 3000.0, ..tk::Gun::default() };
    for (id, kind) in [(1, MOUNT_LIGHT), (2, MOUNT_HEAVY), (3, MOUNT_INTERCEPTOR)] {
        let slot = m.add(id, 1, STATION, 0, Vector3::new(0.0, 52.0, 0.0), Vector3::new(0.0, 1.0, 0.0), 200.0, 3.0, gun_spec);
        m.kind[slot] = kind;
    }
    m.out[1] = true;
    let mut job = tk::PickJob::default();
    job.take_from(&m, &tk::Memory::default(), &table(), STRIDE, &tk::Hulls::default(), &free_against(&[1]), &[STATION]);
    let slots: Vec<u32> = job.mounts.iter().map(|p| p.slot).collect();
    assert_eq!(slots, vec![0], "the knocked-out heavy and the interceptor (main thread) are not picked for");
    let mut points = Vec::new();
    mount_points(&rows, &finder(&rows), &m, &mut points);
    assert_eq!(points.iter().map(|p| (p.slot, p.alive)).collect::<Vec<_>>(), vec![(0, true), (1, false), (2, true)]);
    assert!((points[0].at - Vector3::new(0.0, 52.0, 0.0)).length() < 1e-4, "at the mount's pivot on its body");
}

#[test]
fn a_heavy_cannon_takes_capitals_first_and_fighters_when_none_is_in_reach() {
    let near_fighter = (1, 1, Vector3::new(0.0, 400.0, 0.0), false);
    let far_capital = (2, 1, Vector3::new(0.0, 5000.0, 0.0), true);
    let rows = rows_with(&[near_fighter, far_capital], 0.0);
    assert_eq!(pick_with(&rows, &gun(MOUNT_HEAVY, 6000.0), &free_against(&[1])), 2, "the capital, though further");
    let rows = rows_with(&[near_fighter, (2, 1, Vector3::new(0.0, 9000.0, 0.0), true)], 0.0);
    assert_eq!(pick_with(&rows, &gun(MOUNT_HEAVY, 6000.0), &free_against(&[1])), 1, "a fighter when no capital is in reach");
}

#[test]
fn neither_gun_picks_a_friend_a_neutral_or_the_station() {
    let rows = rows_with(
        &[(1, 0, Vector3::new(0.0, 300.0, 0.0), false), (2, 3, Vector3::new(0.0, 400.0, 0.0), false)],
        0.0,
    );
    assert_eq!(pick_with(&rows, &gun(MOUNT_LIGHT, 3000.0), &free_against(&[0, 1, 3])), 0);
    assert_eq!(pick_with(&rows, &gun(MOUNT_HEAVY, 6000.0), &free_against(&[0, 1, 3])), 0);
}

#[test]
fn the_stations_hull_hides_a_target_from_a_gun_on_its_far_side() {
    // A raider under the station is nearer, but the hull lies between it and the gun on top.
    let rows = rows_with(
        &[(1, 1, Vector3::new(0.0, -300.0, 0.0), false), (2, 1, Vector3::new(0.0, 1200.0, 0.0), false)],
        0.0,
    );
    let m = gun(MOUNT_LIGHT, 3000.0);
    assert_eq!(pick_with(&rows, &m, &free_against(&[1])), 2);
    let from = Vector3::new(0.0, 52.0 + tk::LINE_LIFT_M as f32, 0.0);
    assert!(line_blocked(&rows, &[0], from, Vector3::new(0.0, -300.0, 0.0)));
    assert!(!line_blocked(&rows, &[0], from, Vector3::new(0.0, 1200.0, 0.0)));
    // A gun standing inside a volume's box still fires out of it.
    let inside = Vector3::new(0.0, 49.0, 0.0);
    assert!(!line_blocked(&rows, &[0], inside, Vector3::new(0.0, 1200.0, 0.0)));
}

#[test]
fn the_latch_sets_once_per_side_and_holds_again() {
    let mut latch = Latch::default();
    assert!(latch.set(0, 1));
    assert!(!latch.set(0, 1));
    assert!(latch.set(0, 2));
    assert!(latch.is_free(0, 1) && latch.free_any(0) && !latch.free_any(1));
    latch.hold(0, Some(1));
    assert!(!latch.is_free(0, 1) && latch.is_free(0, 2));
    latch.hold(0, None);
    assert!(!latch.free_any(0));
}

#[test]
fn a_hit_frees_the_grid_on_the_station_or_a_friend_near_a_gun_only() {
    let rows = rows_with(
        &[
            (1, 1, Vector3::new(0.0, 900.0, 0.0), false),
            (2, 0, Vector3::new(0.0, 700.0, 0.0), false),
            (3, 0, Vector3::new(0.0, 40_000.0, 0.0), false),
            (4, 3, Vector3::new(0.0, 600.0, 0.0), false),
        ],
        0.0,
    );
    let rel = table();
    let near = |p: Vector3| f64::from(p.length()) <= 3000.0;
    assert!(hit_frees(&rows, 0, 1, 0, &rel, STRIDE, near), "the station hit by a raider");
    assert!(hit_frees(&rows, 2, 1, 0, &rel, STRIDE, near), "a friend near a gun");
    assert!(!hit_frees(&rows, 3, 1, 0, &rel, STRIDE, near), "a friend far off");
    assert!(!hit_frees(&rows, 4, 1, 0, &rel, STRIDE, near), "a neutral is no friend");
    assert!(!hit_frees(&rows, 0, 3, 0, &rel, STRIDE, near), "a neutral's shot does not free it");
}

// Bolts by `(kind, faction, at, velocity)`, each living 5 s.
fn bolts_of(list: &[(u8, u32, Vector3, Vector3)]) -> Bolts {
    let mut b = Bolts::default();
    for (k, &(kind, faction, at, v)) in list.iter().enumerate() {
        b.ids.push(-(k as i64) - 1);
        b.positions.push(at);
        b.velocities.push(v);
        b.last_steps.push(Vector3::ZERO);
        b.faction_ix.push(faction);
        b.shooters.push(1);
        b.kinds.push(kind);
        b.radii.push(0.3);
        b.damage.push(6.0);
        b.expires_at.push(5.0);
        b.spent.push(false);
    }
    b
}

#[test]
fn an_interceptor_sees_only_hostile_shots_whose_path_meets_the_hull() {
    let rows = rows_with(&[], 0.0);
    let down = Vector3::new(0.0, -350.0, 0.0);
    let bolts = bolts_of(&[
        (KIND_BOLT, 1, Vector3::new(0.0, 800.0, 0.0), down),                     // at the hull
        (KIND_BOLT, 1, Vector3::new(0.0, 800.0, 0.0), Vector3::new(0.0, 350.0, 0.0)), // away
        (KIND_BEAM, 1, Vector3::new(0.0, 800.0, 0.0), down),                     // a beam: never
        (KIND_BOLT, 0, Vector3::new(0.0, 800.0, 0.0), down),                     // friendly
        (KIND_BOLT, 3, Vector3::new(0.0, 800.0, 0.0), down),                     // neutral
        (KIND_BOLT, 1, Vector3::new(0.0, 2800.0, 0.0), down),                    // out of reach
        (KIND_MISSILE, 2, Vector3::new(20.0, 900.0, 0.0), down),                 // a missile at the hull
    ]);
    let mut out = Vec::new();
    let pivot = Vector3::new(0.0, 52.0, 0.0);
    incoming(&rows, &[0], &bolts, 0, &table(), STRIDE, pivot, 1500.0, 0.0, &mut out);
    let seen: Vec<u32> = out.iter().map(|c| c.bolt).collect();
    assert_eq!(seen, vec![0, 6]);
    assert!((out[0].hit_in_s - 750.0 / 350.0).abs() < 1e-3, "it meets the roof at y 50 ({})", out[0].hit_in_s);
    assert!(out[1].missile);
}

#[test]
fn an_interceptor_takes_a_missile_first_then_the_bolt_that_hits_soonest() {
    let c = |bolt: u32, missile: bool, hit_in_s: f64| Incoming { bolt, missile, hit_in_s };
    let list = [c(0, false, 0.5), c(1, false, 0.2), c(2, true, 3.0), c(3, true, 1.0)];
    assert_eq!(choose(&list, &[false; 4]).unwrap().bolt, 3, "the missile that hits soonest");
    assert_eq!(choose(&list, &[false, false, false, true]).unwrap().bolt, 2, "another battery took that one");
    assert_eq!(choose(&list, &[false, false, true, true]).unwrap().bolt, 1, "then the bolt that hits soonest");
    assert_eq!(choose(&list, &[true; 4]), None);
}

#[test]
fn a_beam_is_never_interceptable() {
    let bolts = bolts_of(&[(KIND_BEAM, 1, Vector3::ZERO, Vector3::ZERO), (KIND_BOLT, 1, Vector3::ZERO, Vector3::ZERO)]);
    assert!(!interceptable(&bolts, 0, 0, &table(), STRIDE));
    assert!(interceptable(&bolts, 1, 0, &table(), STRIDE));
}

#[test]
fn a_drum_guns_shot_carries_the_skin_speed_under_it() {
    let rows = rows_with(&[], 0.148);
    let v = mount_velocity(&rows, 0, Vector3::new(300.0, 0.0, 0.0));
    assert!((v.y - 0.148 * 300.0).abs() < 1e-3 && v.x.abs() < 1e-3, "{v:?}");
    let still = rows_with(&[], 0.0);
    assert_eq!(mount_velocity(&still, 0, Vector3::new(300.0, 0.0, 0.0)), Vector3::ZERO);
}

#[test]
fn a_capital_is_a_capital_kind_or_a_hull_bigger_than_a_fighter() {
    let rows = rows_with(&[(1, 1, Vector3::ZERO, true), (2, 1, Vector3::ZERO, false)], 0.0);
    assert!(is_capital(&rows, 1) && !is_capital(&rows, 2));
}
