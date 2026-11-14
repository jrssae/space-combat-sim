// The brains at a big hull (M7-T10): the station is a contact in any crowd, a raid answers whoever fired at it first and
// aims at the station's weapon mounts, and a docking lane holds the hull the way the lane asks.
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::{Basis, Vector3};

use super::*;
use crate::kernels::contact::{Grid, Query, Work, sorted_cells_into};
use crate::rows::{Bolts, FLAG_HULL_ACTIVE, FLAG_RIGID, ROLE_SURFACE, Rows, Surface};

const STATION: i64 = 100;
const RAIDER: i64 = 200;
// Factions: 0 the station's people, 1 raiders.
const RAIDER_SEES: [u8; 2] = [pilot::HOSTILE, pilot::FRIENDLY];

// The station: one box 100 m across and `2 * half_z` long about its origin, spinning at `spin` about +z.
fn hull(half_z: f64, spin: f64) -> Surface {
    let p = vec![0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 50.0, 50.0, half_z];
    surface::from_packed(&p, spin)
}

// Row 0 the station, then a ship per `(id, faction, at)`.
fn rows_with(ships: &[(i64, u32, Vector3)], half_z: f64, spin: f64) -> Rows {
    let mut map = HashMap::new();
    map.insert(STATION, Arc::new(hull(half_z, spin)));
    let mut rows = Rows {
        body_ids: vec![STATION],
        ids: vec![STATION],
        positions: vec![Vector3::ZERO],
        velocities: vec![Vector3::ZERO],
        bases: vec![Basis::IDENTITY],
        angular: vec![Vector3::ZERO],
        radii: vec![half_z + 60.0],
        rigid: vec![false],
        is_static: vec![false],
        is_mine: vec![false],
        reach: vec![0.0],
        faction_ix: vec![0],
        flags: vec![FLAG_HULL_ACTIVE],
        kinds: vec![6],
        hull_fraction: vec![1.0],
        target_ids: vec![-1],
        name_ids: vec![0],
        roles: vec![ROLE_SURFACE],
        surfaces: Some(Arc::new(map)),
        ..Rows::default()
    };
    for &(id, faction, at) in ships {
        rows.body_ids.push(id);
        rows.ids.push(id);
        rows.positions.push(at);
        rows.velocities.push(Vector3::ZERO);
        rows.bases.push(Basis::IDENTITY);
        rows.angular.push(Vector3::ZERO);
        rows.radii.push(8.0);
        rows.rigid.push(true);
        rows.is_static.push(false);
        rows.is_mine.push(false);
        rows.reach.push(0.0);
        rows.faction_ix.push(faction);
        rows.flags.push(FLAG_RIGID | FLAG_HULL_ACTIVE);
        rows.kinds.push(0);
        rows.hull_fraction.push(1.0);
        rows.target_ids.push(-1);
        rows.name_ids.push(0);
        rows.roles.push(0);
    }
    rows.id_rows = rows.ids.iter().enumerate().map(|(r, &id)| (id, r as u32)).collect();
    rows.id_rows.sort_unstable();
    rows
}

fn capability() -> Capability {
    Capability {
        a_main: 40.0,
        a_retro: 30.0,
        a_rcs_x: 20.0,
        a_rcs_y: 20.0,
        rate_max: Vector3::new(1.5, 1.5, 2.0),
        alpha_max: Vector3::new(4.0, 4.0, 4.0),
    }
}

fn raider_brain(kinds: &[u8]) -> Brain {
    let tactics = Tactics {
        closing_far_mps: 120.0,
        closing_near_mps: 60.0,
        near_range_m: 1500.0,
        face_lead_delta_v_mps: 40.0,
        fire_range_m: 1200.0,
        fire_cone_deg: 2.5,
        fire_miss_m: 5.0,
        break_range_m: 300.0,
        max_time_on_target_s: 8.0,
        break_speed_mps: 120.0,
        break_duration_s: 2.5,
        extend_min_s: 4.0,
        extend_range_m: 1400.0,
        max_speed_mps: 0.0,
    };
    let profile = Profile {
        weights: [1.0; KINDS],
        stickiness: 0.1,
        emergency_margin: 0.3,
        min_dwell_s: 1.0,
        cruise_mps: 80.0,
        fires: true,
        tactics,
        ..Profile::default()
    };
    let mut brain = Brain::new(profile, Temperament::new(0.5, 0.5), 7, kinds);
    brain.ship = Ship {
        capability: capability(),
        muzzle_speed_mps: 900.0,
        weapon_lifetime_s: 2.0,
        radius: 8.0,
        tie_hash: 12345,
        own_body_id: RAIDER,
        self_id: RAIDER,
        ..Ship::default()
    };
    brain
}

struct Bench {
    rows: Rows,
    bolts: Bolts,
    grid: Grid,
    field: Field,
    query: Query,
    scratch: Scratch,
    keep: Vec<i64>,
}

impl Bench {
    fn new(rows: Rows) -> Bench {
        let bolts = Bolts::default();
        let mut grid = Grid { cell_m: 5000.0, ..Grid::default() };
        sorted_cells_into(&rows.positions, grid.cell_m, &mut grid.cells);
        let mut field = Field::default();
        field.build(&rows, &bolts, grid.cell_m);
        Bench { rows, bolts, grid, field, query: Query::default(), scratch: Scratch::default(), keep: Vec::new() }
    }

    // One think of `brain` (the row whose id is `RAIDER`) at `now_s`, hit last by `attacker` at `hit_s`, seeing `k` nearest.
    fn think(&mut self, brain: &mut Brain, now_s: f64, attacker: i64, hit_s: f64, k: i64) -> Output {
        let own_row = self.rows.ids.iter().position(|&id| id == RAIDER).unwrap();
        let inputs = Inputs {
            relations: &RAIDER_SEES,
            own_body_id: RAIDER,
            now_s,
            dt: 1.0 / 60.0,
            hull_fraction: 1.0,
            self_id: RAIDER,
            selected_id: 0,
            last_hit_s: hit_s,
            last_bolt_hit_s: f64::NEG_INFINITY,
            last_attacker_id: attacker,
            friendly_fire: false,
            origin: [0.0; 3],
            nearest_k: k,
            static_k: 8,
            lean: false,
        };
        brain.think(
            &self.rows,
            &self.bolts,
            &mut Work { grid: &self.grid, query: &mut self.query },
            &self.field,
            own_row,
            &mut self.scratch,
            &mut self.keep,
            &inputs,
        )
    }
}

const NEVER: f64 = f64::NEG_INFINITY;

#[test]
fn a_big_hull_near_is_a_contact_however_crowded_the_cut() {
    // The raider 300 m off the skin of a hull 10 km long, 4.5 km along it from the centre, with three friends nearer than
    // the hull's centre and a cut of the two nearest.
    let at = Vector3::new(350.0, 0.0, 4500.0);
    let ships = [
        (RAIDER, 1, at),
        (201, 1, at + Vector3::new(40.0, 0.0, 0.0)),
        (202, 1, at + Vector3::new(0.0, 60.0, 0.0)),
        (203, 1, at + Vector3::new(0.0, 0.0, 90.0)),
    ];
    let mut bench = Bench::new(rows_with(&ships, 5000.0, 0.0));
    let mut brain = raider_brain(&[KIND_IDLE]);
    bench.think(&mut brain, 1.0, 0, NEVER, 2);
    assert!(bench.scratch.contacts.contains(&0), "the hull is listed: {:?}", bench.scratch.contacts);
    assert!(bench.scratch.contacts.is_sorted(), "in row order: {:?}", bench.scratch.contacts);
    // Its centre is beyond the sensors' 5 km here and its skin 300 m off: still listed, with no cut at all.
    let far_end = Vector3::new(350.0, 0.0, 5200.0);
    let mut bench = Bench::new(rows_with(&[(RAIDER, 1, far_end)], 5000.0, 0.0));
    bench.think(&mut brain, 1.0, 0, NEVER, 12);
    assert_eq!(bench.scratch.contacts, vec![0], "listed by its skin, not its centre");
    // Beyond the sight distance off the skin it is left to the ordinary scan (its centre here is 3 km off: listed);
    // from 6 km out along its axis neither rule lists it.
    let mut bench = Bench::new(rows_with(&[(RAIDER, 1, Vector3::new(0.0, 0.0, 11_000.0))], 5000.0, 0.0));
    bench.think(&mut brain, 1.0, 0, NEVER, 12);
    assert!(bench.scratch.contacts.is_empty(), "6 km off the bow is out of sight");
}

#[test]
fn a_raid_at_the_station_answers_whoever_fired_at_it_first() {
    // Two of the station's fighters: 300 the nearer, 301 the farther.
    let at = Vector3::new(600.0, 0.0, 0.0);
    let ships = [
        (RAIDER, 1, at),
        (300, 0, at + Vector3::new(400.0, 0.0, 0.0)),
        (301, 0, at + Vector3::new(0.0, 1500.0, 0.0)),
    ];
    let mut bench = Bench::new(rows_with(&ships, 500.0, 0.0));
    let mut brain = raider_brain(&[KIND_ATTACK, KIND_IDLE]);
    bench.think(&mut brain, 10.0, 0, NEVER, 12);
    assert_eq!(brain.wanted_target_id, 300, "unprovoked: the nearer fighter");
    // The farther one hit it a moment ago: it is answered first.
    let mut brain = raider_brain(&[KIND_ATTACK, KIND_IDLE]);
    bench.think(&mut brain, 10.0, 301, 9.5, 12);
    assert_eq!(brain.wanted_target_id, 301, "the one that fired at it");
    // The station's guns hit it: the station itself, though its fighters are in reach.
    let mut brain = raider_brain(&[KIND_ATTACK, KIND_IDLE]);
    bench.think(&mut brain, 10.0, STATION, 9.5, 12);
    assert_eq!(brain.wanted_target_id, STATION, "the station that fired at it");
    // A hit long ago is forgotten.
    let mut brain = raider_brain(&[KIND_ATTACK, KIND_IDLE]);
    bench.think(&mut brain, 100.0, STATION, 9.5, 12);
    assert_eq!(brain.wanted_target_id, 300, "an old hit no longer decides");
}

#[test]
fn away_from_any_big_hull_the_last_attacker_does_not_reorder_the_pick() {
    // The same two fighters with the station far out of sight: the pick is M5's, nearest first.
    let at = Vector3::new(0.0, 0.0, 20_000.0);
    let ships = [
        (RAIDER, 1, at),
        (300, 0, at + Vector3::new(400.0, 0.0, 0.0)),
        (301, 0, at + Vector3::new(0.0, 1500.0, 0.0)),
    ];
    let mut bench = Bench::new(rows_with(&ships, 500.0, 0.0));
    let mut brain = raider_brain(&[KIND_ATTACK, KIND_IDLE]);
    bench.think(&mut brain, 10.0, 301, 9.5, 12);
    assert_eq!(brain.wanted_target_id, 300);
}

fn aim_mount(brain: &Brain) -> i64 {
    brain
        .describe()
        .numbers
        .iter()
        .find(|(k, _)| *k == "aim_mount")
        .map_or(-1, |(_, v)| *v as i64)
}

#[test]
fn a_run_on_the_station_aims_at_its_weapon_mounts_first() {
    // The raider above the hull's top, nearer mount 4 (z = +200) than mount 2 (z = -300).
    let at = Vector3::new(0.0, 900.0, 150.0);
    let mut bench = Bench::new(rows_with(&[(RAIDER, 1, at)], 500.0, 0.0));
    let top = |z: f32| Vector3::new(0.0, 52.0, z);
    bench.field.sub_points = vec![
        SubPoint { row: 0, slot: 2, local: top(-300.0) },
        SubPoint { row: 0, slot: 4, local: top(200.0) },
    ];
    let mut brain = raider_brain(&[KIND_ATTACK, KIND_IDLE]);
    bench.think(&mut brain, 10.0, STATION, 9.5, 12);
    assert_eq!(brain.wanted_target_id, STATION);
    assert_eq!(aim_mount(&brain), 4, "the nearest working mount");
    // The wish closes on the mount, not on the hull's centre.
    let to_mount = normalized(sub(top(200.0), at));
    let wish = normalized(brain.desired_velocity);
    assert!(dot(wish, to_mount) > 0.99, "flying at the mount: {wish:?} against {to_mount:?}");
    // Nearer the other mount now, the run keeps the one it began on while that works.
    bench.rows.positions[1] = Vector3::new(0.0, 900.0, -280.0);
    bench.think(&mut brain, 10.1, STATION, 9.5, 12);
    assert_eq!(aim_mount(&brain), 4, "kept while it works");
    // Knocked out (gone from the points): the other mount.
    bench.field.sub_points.remove(1);
    bench.think(&mut brain, 10.2, STATION, 9.5, 12);
    assert_eq!(aim_mount(&brain), 2, "the next working mount");
    // None left: the nearest skin, straight below.
    bench.field.sub_points.clear();
    bench.think(&mut brain, 10.3, STATION, 9.5, 12);
    assert_eq!(aim_mount(&brain), -1);
    let wish = normalized(brain.desired_velocity);
    assert!(wish.y < -0.99, "at the skin below: {wish:?}");
}

#[test]
fn a_mount_on_the_turning_drum_is_led_with_its_skin_speed() {
    // A mount 50 m out on a hull spinning at 0.148 rad/s about +z moves at 7.4 m/s; the approach's wish carries it.
    let at = Vector3::new(0.0, 900.0, 0.0);
    let mut bench = Bench::new(rows_with(&[(RAIDER, 1, at)], 500.0, 0.148));
    bench.field.sub_points = vec![SubPoint { row: 0, slot: 1, local: Vector3::new(0.0, 50.0, 0.0) }];
    let mut brain = raider_brain(&[KIND_ATTACK, KIND_IDLE]);
    bench.think(&mut brain, 10.0, STATION, 9.5, 12);
    // w x r = (0, 0, 0.148) x (0, 50, 0) = (-7.4, 0, 0).
    assert!((brain.desired_velocity.x + 7.4).abs() < 0.05, "the skin's speed in the wish: {:?}", brain.desired_velocity);
}

fn lane(points: &[[f64; 3]], holds: &[f64], faces: &[Vector3], spins: &[Vector3]) -> Route {
    Route {
        points: points.to_vec(),
        demos: vec![0; points.len()],
        holds: holds.to_vec(),
        cruise_mps: 40.0,
        precise: true,
        arrival_m: 15.0,
        faces: faces.to_vec(),
        spins: spins.to_vec(),
        ..Route::default()
    }
}

#[test]
fn a_docking_lane_matches_the_tunnels_roll_on_its_way_in() {
    // Far from any hull, flying +z down a lane whose second leg asks for the drum's turn about +z.
    let at = Vector3::new(0.0, 0.0, 20_000.0);
    let mut bench = Bench::new(rows_with(&[(RAIDER, 1, at)], 500.0, 0.0));
    bench.rows.bases[1] = Basis::from_cols(Vector3::new(-1.0, 0.0, 0.0), Vector3::UP, Vector3::new(0.0, 0.0, -1.0));
    let spin = Vector3::new(0.0, 0.0, 0.148);
    let mut brain = raider_brain(&[KIND_FOLLOW_PATH, KIND_IDLE]);
    brain.ctx.route = Some(lane(
        &[[0.0, 0.0, 20_100.0], [0.0, 0.0, 21_000.0]],
        &[0.0, 0.0],
        &[Vector3::ZERO, Vector3::ZERO],
        &[Vector3::ZERO, spin],
    ));
    let out = bench.think(&mut brain, 1.0, 0, NEVER, 12);
    assert_eq!(out.flight.rot.z, 0.0, "no roll asked on the first leg");
    assert!(out.flight.main_left > 0.0, "it flies up the lane");
    // Past the first waypoint (within the lane's 15 m), the roll is the drum's about the nose, as a share of the roll rate.
    bench.rows.positions[1] = Vector3::new(0.0, 0.0, 20_095.0);
    let out = bench.think(&mut brain, 1.1, 0, NEVER, 12);
    let want = brain_maths::match_roll(&bench.rows.bases[1], spin, capability().rate_max);
    assert!(want.abs() > 0.05, "a roll worth commanding: {want}");
    assert_eq!(f64::from(out.flight.rot.z), f64::from(want as f32), "far from the drum: its rate alone");
    // The roll is about the nose: turned the other way round, the same drum asks the opposite roll.
    assert!((want.abs() - 0.148 / 2.0).abs() < 1e-6, "0.148 rad/s of a 2 rad/s roll rate: {want}");
}

#[test]
fn a_docking_lane_backs_a_freighter_in_and_holds_it_stern_to_the_bay() {
    // The lane runs +z to the hold point; the nose is kept on -z (away from the bay), so the way in is astern.
    let at = Vector3::new(0.0, 0.0, 20_000.0);
    let mut bench = Bench::new(rows_with(&[(RAIDER, 1, at)], 500.0, 0.0));
    let away = Vector3::new(0.0, 0.0, -1.0);
    let mut brain = raider_brain(&[KIND_FOLLOW_PATH, KIND_IDLE]);
    brain.ctx.route = Some(lane(&[[0.0, 0.0, 20_400.0]], &[30.0], &[away], &[Vector3::ZERO]));
    let out = bench.think(&mut brain, 1.0, 0, NEVER, 12);
    assert!(out.flight.retro_left > 0.0 && out.flight.main_left == 0.0, "astern on the retros: {:?}", out.flight);
    assert!(f64::from(length(out.flight.rot)) < 1e-6, "nose already away from the bay: {:?}", out.flight.rot);
    assert!(brain.desired_velocity.z > 0.0 && brain.desired_all_axes, "toward the bay on every thruster");
    // Nose toward the bay (not yet turned): it turns where it is and makes no way.
    bench.rows.bases[1] = Basis::from_cols(Vector3::new(-1.0, 0.0, 0.0), Vector3::UP, Vector3::new(0.0, 0.0, -1.0));
    let out = bench.think(&mut brain, 1.05, 0, NEVER, 12);
    assert!(f64::from(length(brain.desired_velocity)) < 1e-6, "no way made until it has turned: {:?}", brain.desired_velocity);
    assert!(f64::from(length(out.flight.rot)) > 0.5, "turning: {:?}", out.flight.rot);
    bench.rows.bases[1] = Basis::IDENTITY;
    // Close in it creeps: far slower than cruise 30 m short of a waypoint that holds.
    bench.rows.positions[1] = Vector3::new(0.0, 0.0, 20_370.0);
    bench.think(&mut brain, 1.1, 0, NEVER, 12);
    assert!(brain.desired_velocity.z < 20.0, "slowing into the hold: {:?}", brain.desired_velocity);
    // Arrived (inside 15 m): the brake, and the nose still held away from the bay when it has swung off.
    bench.rows.positions[1] = Vector3::new(0.0, 0.0, 20_392.0);
    let (s, c) = 0.3_f32.sin_cos();
    bench.rows.bases[1] = Basis::from_cols(Vector3::new(c, 0.0, -s), Vector3::UP, Vector3::new(s, 0.0, c));
    let out = bench.think(&mut brain, 1.2, 0, NEVER, 12);
    assert!(out.flight.brake, "holding");
    assert!(out.flight.rot.y.abs() > 0.05, "the hold turns the nose back: {:?}", out.flight.rot);
}
