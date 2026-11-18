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

#[test]
fn a_docking_lanes_hold_in_the_drum_keeps_turning_with_it() {
    // Waiting in the void behind the doors (M7-T61): a hold that asks for the drum's turn is not the brake (which stops
    // the roll and leaves a wide hull askew in the doorway) but the roll, kept on its point by the thrusters.
    let at = Vector3::new(0.0, 0.0, 20_000.0);
    let mut bench = Bench::new(rows_with(&[(RAIDER, 1, at)], 500.0, 0.0));
    let spin = Vector3::new(0.0, 0.0, 0.148);
    let mut brain = raider_brain(&[KIND_FOLLOW_PATH, KIND_IDLE]);
    brain.ctx.route = Some(lane(&[[0.0, 0.0, 20_000.0]], &[600.0], &[Vector3::ZERO], &[spin]));
    let out = bench.think(&mut brain, 1.0, 0, NEVER, 12);
    assert!(!out.flight.brake, "no brake while it waits: {:?}", out.flight);
    let want = brain_maths::match_roll(&bench.rows.bases[1], spin, capability().rate_max);
    assert!(want.abs() > 0.05, "a roll worth commanding: {want}");
    assert_eq!(f64::from(out.flight.rot.z), f64::from(want as f32), "turning with the drum");
    assert!(f64::from(length(brain.desired_velocity)) < 1e-3, "on its point, it stays: {:?}", brain.desired_velocity);
    // Drifted 10 m off its point: pulled gently back.
    bench.rows.positions[1] = Vector3::new(10.0, 0.0, 20_000.0);
    let out = bench.think(&mut brain, 1.1, 0, NEVER, 12);
    assert!(!out.flight.brake);
    let back = brain.desired_velocity;
    assert!(back.x < -0.5 && f64::from(length(back)) <= 2.0 + 1e-4, "back toward its point, slowly: {back:?}");
}

// A bolt of faction `faction` from `shooter`, at `at` flying at `v`.
fn bolt(bench: &mut Bench, shooter: i64, faction: u32, at: Vector3, v: Vector3) {
    let b = &mut bench.bolts;
    b.ids.push(900 + b.ids.len() as i64);
    b.positions.push(at);
    b.velocities.push(v);
    b.last_steps.push(Vector3::ZERO);
    b.faction_ix.push(faction);
    b.shooters.push(shooter);
    b.kinds.push(0);
    b.radii.push(0.5);
    bench.field.build(&bench.rows, &bench.bolts, bench.grid.cell_m);
}

// A civilian (the thinking row, of the station's people) far from the station, a fighter of its own people 600 m off its
// beam, and a kin freighter 3 km ahead to run to.
fn civilian_bench() -> Bench {
    let at = Vector3::new(0.0, 0.0, 30_000.0);
    let ships = [
        (RAIDER, 0, at),
        (400, 0, at + Vector3::new(600.0, 0.0, 0.0)),
        (401, 0, at + Vector3::new(0.0, 0.0, -3000.0)),
    ];
    let mut rows = rows_with(&ships, 500.0, 0.0);
    rows.roles[1] = crate::rows::ROLE_CIVILIAN;
    rows.roles[3] = crate::rows::ROLE_CIVILIAN;
    Bench::new(rows)
}

// The civilian thinks as one of the station's people: its own side friendly, raiders hostile.
fn civilian_think(bench: &mut Bench, brain: &mut Brain, now_s: f64) -> Output {
    let inputs = Inputs {
        relations: &[pilot::FRIENDLY, pilot::HOSTILE],
        own_body_id: RAIDER,
        now_s,
        dt: 1.0 / 60.0,
        hull_fraction: 1.0,
        self_id: RAIDER,
        selected_id: 0,
        last_hit_s: NEVER,
        last_bolt_hit_s: NEVER,
        last_attacker_id: 0,
        friendly_fire: false,
        origin: [0.0; 3],
        nearest_k: 12,
        static_k: 8,
        lean: false,
    };
    brain.think(
        &bench.rows,
        &bench.bolts,
        &mut Work { grid: &bench.grid, query: &mut bench.query },
        &bench.field,
        1,
        &mut bench.scratch,
        &mut bench.keep,
        &inputs,
    )
}

fn civilian_brain() -> Brain {
    let mut brain = raider_brain(&[KIND_RETREAT, KIND_IDLE]);
    brain.ship.radius = 40.0;
    brain
}

#[test]
fn a_civilian_flees_from_a_friends_fire_that_comes_close_and_toward_its_kin() {
    let mut bench = civilian_bench();
    let mut brain = civilian_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "nothing to fear yet");
    // The fighter's bolt passes 30 m from the civilian's centre: inside its hull's radius and the margin.
    let at = bench.rows.positions[1];
    bolt(&mut bench, 400, 0, at + Vector3::new(500.0, 30.0, 0.0), Vector3::new(-900.0, 0.0, 0.0));
    civilian_think(&mut bench, &mut brain, 1.1);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT), "it runs");
    assert!(brain.flight_flags().1, "and its alarm spreads to its kin");
    let wish = normalized(brain.desired_velocity);
    assert!(wish.z < -0.9, "to its kin ahead (M5's rule), not to the friend that fired: {wish:?}");
    assert!(wish.x <= 0.01, "and no nearer the ship that fired: {wish:?}");
    assert_eq!(brain.provoked_by, 0, "stray fire: the shooter had something else selected");
    // The bolt gone, the fright holds for the panic's time, then it calms.
    bench.bolts = Bolts::default();
    bench.field.build(&bench.rows, &bench.bolts, bench.grid.cell_m);
    civilian_think(&mut bench, &mut brain, 10.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT), "still running 9 s on");
    civilian_think(&mut bench, &mut brain, 1.1 + civilian::PANIC_HOLD_S + 2.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "calm again");
}

// `civilian_bench` moved to hold 300 m off the station's flank, where the station is among its contacts.
fn station_side_bench() -> Bench {
    let at = Vector3::new(0.0, 300.0, 0.0);
    let ships = [
        (RAIDER, 0, at),
        (400, 0, at + Vector3::new(600.0, 0.0, 0.0)),
        (401, 0, at + Vector3::new(0.0, 0.0, -3000.0)),
    ];
    let mut rows = rows_with(&ships, 500.0, 0.0);
    rows.roles[1] = crate::rows::ROLE_CIVILIAN;
    rows.roles[3] = crate::rows::ROLE_CIVILIAN;
    Bench::new(rows)
}

#[test]
fn the_stations_own_grid_fire_does_not_frighten_its_traffic() {
    // A grid bolt (its shooter the station's body) passes 30 m from the civilian, the station having it selected.
    let mut bench = station_side_bench();
    bench.rows.target_ids[0] = RAIDER;
    let at = bench.rows.positions[1];
    let mut brain = civilian_brain();
    bolt(&mut bench, STATION, 0, at + Vector3::new(500.0, 30.0, 0.0), Vector3::new(-900.0, 0.0, 0.0));
    civilian_think(&mut bench, &mut brain, 1.0);
    assert!(bench.scratch.contacts.contains(&0), "the station is a contact");
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "the station's fire is not aimed at its traffic");
    assert_eq!(brain.provoked_by, 0, "nor a provocation");
    // The same pass by a friendly fighter's bolt still frightens it.
    let mut bench = station_side_bench();
    let mut brain = civilian_brain();
    bolt(&mut bench, 400, 0, at + Vector3::new(500.0, 30.0, 0.0), Vector3::new(-900.0, 0.0, 0.0));
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT));
}

#[test]
fn fire_from_a_ship_that_has_the_civilian_selected_is_a_provocation_and_a_wide_miss_is_nothing() {
    let mut bench = civilian_bench();
    let mut brain = civilian_brain();
    let at = bench.rows.positions[1];
    // 200 m wide of a 40 m hull: no fright.
    bolt(&mut bench, 400, 0, at + Vector3::new(500.0, 200.0, 0.0), Vector3::new(-900.0, 0.0, 0.0));
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT));
    assert_eq!(brain.provoked_by, 0);
    // Close, with the civilian selected by the shooter: the turrets are told.
    bench.bolts = Bolts::default();
    bench.rows.target_ids[2] = RAIDER;
    bolt(&mut bench, 400, 0, at + Vector3::new(500.0, 10.0, 0.0), Vector3::new(-900.0, 0.0, 0.0));
    civilian_think(&mut bench, &mut brain, 1.1);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT));
    assert_eq!(brain.provoked_by, 400, "fired on by the ship that selected it");
    // A fighter (not a civilian) under the same fire does not run: M5's rule stands for every other ship.
    let mut bench = civilian_bench();
    bench.rows.roles[1] = 0;
    let mut brain = civilian_brain();
    bolt(&mut bench, 400, 0, at + Vector3::new(500.0, 10.0, 0.0), Vector3::new(-900.0, 0.0, 0.0));
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT));
}

// --- a civilian under attack (M7-T55) ---------------------------------------------------------------------------------

const ATTACKER: i64 = 500;

// Turned about its top to face +z.
const FACING_BACK: Basis = Basis {
    rows: [Vector3::new(-1.0, 0.0, 0.0), Vector3::new(0.0, 1.0, 0.0), Vector3::new(0.0, 0.0, -1.0)],
};

// The station, a civilian of its people (the thinking row) at `civilian_at` and a raider at `raider_at`.
fn attacked_bench(civilian_at: Vector3, raider_at: Vector3) -> Bench {
    let ships = [(RAIDER, 0, civilian_at), (ATTACKER, 1, raider_at)];
    let mut rows = rows_with(&ships, 500.0, 0.0);
    rows.roles[1] = crate::rows::ROLE_CIVILIAN;
    Bench::new(rows)
}

// The civilian's brain with the `civilian` profile's flee range.
fn attacked_brain() -> Brain {
    let mut brain = civilian_brain();
    brain.retreat.retreat_within_m = 3000.0;
    brain
}

fn move_row(bench: &mut Bench, row: usize, at: Vector3) {
    bench.rows.positions[row] = at;
    bench.field.build(&bench.rows, &bench.bolts, bench.grid.cell_m);
}

#[test]
fn an_attacked_civilian_keeps_running_while_its_attacker_swings_out_for_another_pass() {
    // The m5-054 report: a raider pulling out beyond the flee range turned the civilian back onto its route at once.
    let at = Vector3::new(0.0, 0.0, 30_000.0);
    let mut bench = attacked_bench(at, at + Vector3::new(0.0, 0.0, -2000.0));
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT), "it runs from a raider 2 km off");
    move_row(&mut bench, 2, at + Vector3::new(0.0, 0.0, -4000.0));
    civilian_think(&mut bench, &mut brain, 6.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT), "still running with the raider 4 km off, swinging round");
    civilian_think(&mut bench, &mut brain, 1.0 + civilian::PANIC_HOLD_S + 1.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "calm once it has kept off for the panic's time");
    // The plain retreat for every other ship is unchanged: it runs only while the raider is near.
    let mut bench = attacked_bench(at, at + Vector3::new(0.0, 0.0, -2000.0));
    bench.rows.roles[1] = 0;
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT));
    move_row(&mut bench, 2, at + Vector3::new(0.0, 0.0, -4000.0));
    civilian_think(&mut bench, &mut brain, 6.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "a fighter's retreat ends with the threat's range");
}

#[test]
fn a_civilian_burns_its_main_engine_to_turn_its_run_around() {
    // A freighter flying at the raider at 100 m/s: its nose goes onto the change of velocity, not the new heading, so the
    // main engine (which fires only near the nose's line) can do the work its weak thrusters cannot.
    let at = Vector3::new(0.0, 0.0, 30_000.0);
    let mut bench = attacked_bench(at, at + Vector3::new(0.0, 0.0, -2500.0));
    bench.rows.velocities[1] = Vector3::new(0.0, 0.0, -100.0);
    let mut brain = attacked_brain();
    // Nose already on the change of velocity (+z: away from the raider and against its run).
    bench.rows.bases[1] = FACING_BACK;
    let out = civilian_think(&mut bench, &mut brain, 1.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT));
    assert!(out.flight.main_left > 0.5, "the main engine burns: {}", out.flight.main_left);
}

#[test]
fn an_attacked_civilian_runs_round_to_the_far_side_of_a_station_of_its_people() {
    // The station (faction 0, the civilian's) 5 km off; the raider on the civilian's far side from it.
    let at = Vector3::new(5000.0, 0.0, 0.0);
    let mut bench = attacked_bench(at, Vector3::new(6500.0, 0.0, 1500.0));
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT));
    let seen = brain.describe();
    assert_eq!(seen.state, "shelter", "the station is a shelter");
    assert!(seen.names.contains(&("goal", STATION)), "to the station: {:?}", seen.names);
    // The far side lies through the hull from here: it flies round the hull, no nearer the raider.
    let wish = normalized(brain.desired_velocity);
    let to_raider = normalized(sub(bench.rows.positions[2], at));
    assert!(dot(wish, to_raider) < 0.0, "no nearer the raider: {wish:?}");
    assert!(dot(wish, normalized(neg(at))).abs() < 0.3, "round the hull, not into it: {wish:?}");
    let civilian_seen = civilian::View {
        rows: &bench.rows,
        contacts: &[],
        own_row: 1,
        radius: 40.0,
        speed_mps: 130.0,
        fleeing: &[],
        shun: -1,
        hulls: &bench.field.surface_rows,
        brake_mps2: 0.0,
    };
    let point = civilian::station_point(&civilian_seen, 0, bench.rows.positions[2]);
    assert!(point.x < 0.0 && point.z < 0.0, "the point is on the station's far side from the raider: {point:?}");
    let (_, skin) = surface::nearest_of_row(&bench.rows, 0, point).unwrap();
    assert!((skin - civilian::STATION_STANDOFF_M - 40.0).abs() < 1.0, "off its skin by the standoff: {skin}");
    // A fellow freighter nearer than the station's skin: the station is still the shelter.
    let mut bench = attacked_bench(at, Vector3::new(6500.0, 0.0, 1500.0));
    let kin = bench.rows.ids.len();
    bench.rows.body_ids.push(401);
    bench.rows.ids.push(401);
    for col in [&mut bench.rows.positions, &mut bench.rows.velocities, &mut bench.rows.angular] {
        col.push(Vector3::ZERO);
    }
    bench.rows.positions[kin] = at + Vector3::new(0.0, 0.0, -800.0);
    bench.rows.bases.push(Basis::IDENTITY);
    bench.rows.radii.push(40.0);
    bench.rows.rigid.push(true);
    bench.rows.is_static.push(false);
    bench.rows.is_mine.push(false);
    bench.rows.reach.push(0.0);
    bench.rows.faction_ix.push(0);
    bench.rows.flags.push(FLAG_RIGID | FLAG_HULL_ACTIVE);
    bench.rows.kinds.push(0);
    bench.rows.hull_fraction.push(1.0);
    bench.rows.target_ids.push(-1);
    bench.rows.name_ids.push(0);
    bench.rows.roles.push(crate::rows::ROLE_CIVILIAN);
    bench.rows.id_rows = bench.rows.ids.iter().enumerate().map(|(r, &id)| (id, r as u32)).collect();
    bench.rows.id_rows.sort_unstable();
    let bench_rows = std::mem::take(&mut bench.rows);
    let mut bench = Bench::new(bench_rows);
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert!(brain.describe().names.contains(&("goal", STATION)), "the station before a fellow freighter");
    // A station of another people is no shelter.
    let mut bench = attacked_bench(at, Vector3::new(6500.0, 0.0, 1500.0));
    bench.rows.faction_ix[0] = 2;
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_eq!(brain.describe().state, "extend", "straight away instead");
}

// Makes the bench's station a neutral port (Babylon 5).
fn make_port(rows: &mut Rows) {
    let map = Arc::make_mut(rows.surfaces.as_mut().unwrap());
    Arc::make_mut(map.get_mut(&STATION).unwrap()).port = true;
}

#[test]
fn babylon_5_shelters_an_attacked_civilian_of_another_people() {
    // The maintainer's decision (2026-11-16): Babylon 5 is a neutral port, so a Narn freighter runs to it as an Earth
    // Alliance one does; the station is of another people (faction 2) and a port.
    let at = Vector3::new(5000.0, 0.0, 0.0);
    let mut bench = attacked_bench(at, Vector3::new(6500.0, 0.0, 1500.0));
    bench.rows.faction_ix[0] = 2;
    make_port(&mut bench.rows);
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT));
    let seen = brain.describe();
    assert_eq!(seen.state, "shelter", "the port is a shelter");
    assert!(seen.names.contains(&("goal", STATION)), "to the station: {:?}", seen.names);
    let wish = normalized(brain.desired_velocity);
    assert!(dot(wish, normalized(sub(bench.rows.positions[2], at))) < 0.0, "no nearer the raider: {wish:?}");
    // Under the port's guns it keeps its course too: the docking lanes stay untouched.
    let near = Vector3::new(0.0, 300.0, 0.0);
    let mut bench = attacked_bench(near, near + Vector3::new(0.0, 1500.0, 0.0));
    bench.rows.faction_ix[0] = 2;
    make_port(&mut bench.rows);
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "under the port's guns");
}

#[test]
fn panic_sends_a_civilian_to_a_station_of_its_people_away_from_the_alarm() {
    // The alarmed kin (row 2) 3 km off toward +x; the station at the origin, 6 km off the panicked civilian (row 1).
    let at = Vector3::new(6000.0, 0.0, 0.0);
    let rows = rows_with(&[(RAIDER, 0, at), (401, 0, at + Vector3::new(3000.0, 0.0, 0.0))], 500.0, 0.0);
    let hulls = [0_u32];
    let seen = civilian::View {
        rows: &rows,
        contacts: &[2],
        own_row: 1,
        radius: 40.0,
        speed_mps: 130.0,
        fleeing: &[],
        shun: -1,
        hulls: &hulls,
        brake_mps2: 0.0,
    };
    let flight = civilian::flee_alarm(&seen, 2);
    assert_eq!(flight.goal, 0, "to the station");
    assert!(flight.shelter);
    assert!(flight.point.x < 0.0, "on its far side from the alarm: {:?}", flight.point);
    assert!(flight.velocity.x < -100.0, "away from the alarm, toward the station: {:?}", flight.velocity);
}

#[test]
fn a_civilian_under_a_stations_guns_keeps_its_course() {
    // 300 m off the station's flank (its docking lane's place): a raider 1.5 km off does not turn it.
    let at = Vector3::new(0.0, 300.0, 0.0);
    let mut bench = attacked_bench(at, at + Vector3::new(0.0, 1500.0, 0.0));
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "under the guns");
}

#[test]
fn a_civilian_running_round_to_a_stations_far_side_keeps_running_under_its_guns() {
    // Council round 1 (O2): its way round the hull passes within the cover; it must not drop the run there.
    let mut bench = attacked_bench(Vector3::new(5000.0, 0.0, 0.0), Vector3::new(6500.0, 0.0, 1500.0));
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_eq!(brain.describe().state, "shelter", "(it runs to the station)");
    let inside = Vector3::new(700.0, 0.0, 0.0); // 650 m off the hull's skin, inside the cover
    move_row(&mut bench, 1, inside);
    move_row(&mut bench, 2, inside + Vector3::new(1500.0, 0.0, 800.0));
    civilian_think(&mut bench, &mut brain, 2.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT), "still running round, under the guns");
    // Once the run is over the shelter goes with it: back under the guns it keeps its course again.
    move_row(&mut bench, 2, Vector3::new(0.0, 0.0, -60_000.0));
    civilian_think(&mut bench, &mut brain, 3.0 + civilian::PANIC_HOLD_S);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "(calm, the raider gone)");
    move_row(&mut bench, 2, inside + Vector3::new(1500.0, 0.0, 800.0));
    civilian_think(&mut bench, &mut brain, 4.0 + civilian::PANIC_HOLD_S);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "a new raider under the guns does not turn it");
}

#[test]
fn a_civilian_scared_under_a_stations_guns_goes_back_to_its_course_after_the_fright() {
    // Council round 2 (N1): a friend's bolt grazes it on the lane during a raid; it runs for the fright's time, then keeps
    // its course again, the raider still in range.
    let mut bench = station_side_bench();
    bench.rows.faction_ix[3] = 1; // row 3 is now the raider, 1.5 km off its side
    bench.rows.roles[3] = 0;
    let at = bench.rows.positions[1];
    move_row(&mut bench, 3, at + Vector3::new(0.0, 1500.0, 0.0));
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "(under the guns, the raider does not turn it)");
    bolt(&mut bench, 400, 0, at + Vector3::new(500.0, 30.0, 0.0), Vector3::new(-900.0, 0.0, 0.0));
    civilian_think(&mut bench, &mut brain, 2.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT), "the friend's fire frightens it");
    let seen = brain.describe();
    assert_eq!(seen.state, "shelter", "(to the station's far side)");
    assert!(seen.names.contains(&("goal", STATION)), "(the station): {:?}", seen.names);
    bench.bolts = Bolts::default();
    bench.field.build(&bench.rows, &bench.bolts, bench.grid.cell_m);
    civilian_think(&mut bench, &mut brain, 2.0 + civilian::PANIC_HOLD_S + 1.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "back to its course, the raider still 1.5 km off");
}

#[test]
fn a_civilian_running_to_a_warship_of_its_people_keeps_its_course_under_a_stations_guns() {
    // Council round 2 (N1): only a run to the station itself goes on under its guns.
    let at = Vector3::new(5000.0, 0.0, 0.0);
    let ships = [
        (RAIDER, 0, at),
        (ATTACKER, 1, at + Vector3::new(1500.0, 0.0, 1500.0)),
        (400, 0, at + Vector3::new(-300.0, 0.0, 0.0)),
    ];
    let mut rows = rows_with(&ships, 500.0, 0.0);
    rows.roles[1] = crate::rows::ROLE_CIVILIAN;
    let mut bench = Bench::new(rows);
    let mut brain = attacked_brain();
    civilian_think(&mut bench, &mut brain, 1.0);
    assert_eq!(brain.current_kind(), i32::from(KIND_RETREAT));
    let seen = brain.describe();
    assert_eq!(seen.state, "shelter", "(it shelters by the warship)");
    assert!(seen.names.contains(&("goal", 400)), "(the warship, not the station): {:?}", seen.names);
    let inside = Vector3::new(700.0, 0.0, 0.0); // 650 m off the hull's skin, inside the cover
    move_row(&mut bench, 1, inside);
    move_row(&mut bench, 2, inside + Vector3::new(1500.0, 0.0, 800.0));
    move_row(&mut bench, 3, inside + Vector3::new(-100.0, 0.0, 0.0));
    civilian_think(&mut bench, &mut brain, 2.0);
    assert_ne!(brain.current_kind(), i32::from(KIND_RETREAT), "under the guns it keeps its course");
}

// --- the wing at a big hull (M7-T38) ----------------------------------------------------------------------------------

const LEADER: i64 = 300;
const MATE: i64 = 400;

// A wingman (the brain's row, id `RAIDER`, faction 1) on `slot` behind `LEADER`, both flying -z at 100 m/s, the leader
// at `leader_at` and the wingman `behind` m astern of it; `MATE` (another wingman) at `mate_at` when given.
fn wing_bench(leader_at: Vector3, behind: f64, mate_at: Option<Vector3>) -> Bench {
    let mut ships = vec![(LEADER, 1, leader_at), (RAIDER, 1, leader_at + Vector3::new(0.0, 0.0, behind as f32))];
    if let Some(at) = mate_at {
        ships.push((MATE, 1, at));
    }
    let mut rows = rows_with(&ships, 1000.0, 0.0);
    for v in rows.velocities.iter_mut().skip(1) {
        *v = Vector3::new(0.0, 0.0, -100.0);
    }
    Bench::new(rows)
}

fn wingman(slot: Vector3) -> Brain {
    let mut brain = raider_brain(&[KIND_FORMATION, KIND_IDLE]);
    brain.ctx.order = ORDER_FORM_ON_ME;
    brain.ctx.leader_id = LEADER;
    brain.ctx.has_slot = true;
    brain.ctx.slot_offset = slot;
    brain.ctx.wing_ids = vec![LEADER, MATE];
    brain
}

// Flies the bench's leader and wingman 0.25 s on along -z, thinking at each step for `steps` steps.
fn fly_on(bench: &mut Bench, brain: &mut Brain, steps: usize) {
    for k in 0..steps {
        for r in 1..3 {
            let v = bench.rows.velocities[r];
            bench.rows.positions[r] += v * 0.25;
        }
        bench.think(brain, 0.25 * k as f64, 0, NEVER, 12);
    }
}

#[test]
fn a_wingman_whose_slot_lies_inside_the_hull_follows_the_leaders_own_way() {
    // The leader skims the 100 m box 30 m above its top; the slot 80 m below it lies inside the hull. The wingman leaves
    // the slot and flies the leader's way (its height), never down into the hull.
    let mut bench = wing_bench(Vector3::new(0.0, 80.0, 600.0), 100.0, None);
    let mut brain = wingman(Vector3::new(0.0, -80.0, 40.0));
    fly_on(&mut bench, &mut brain, 16);
    assert!(brain.formation.trailing, "on the trail");
    assert!(brain.desired_velocity.y > -5.0, "not down to the slot: {:?}", brain.desired_velocity);
    // The same slot 80 m above the leader is clear: formation as before.
    let mut bench = wing_bench(Vector3::new(0.0, 80.0, 600.0), 100.0, None);
    let mut brain = wingman(Vector3::new(0.0, 80.0, 40.0));
    fly_on(&mut bench, &mut brain, 16);
    assert!(!brain.formation.trailing, "in formation");
}

#[test]
fn the_trail_is_kept_relative_to_the_hull_so_a_rebase_leaves_it() {
    let mut bench = wing_bench(Vector3::new(0.0, 80.0, 600.0), 100.0, None);
    let mut brain = wingman(Vector3::new(0.0, -80.0, 40.0));
    fly_on(&mut bench, &mut brain, 16);
    let before = brain.desired_velocity;
    // Every row moved 3 km, as a rebase moves them: the same wish.
    let mut moved = wing_bench(Vector3::new(0.0, 80.0, 600.0), 100.0, None);
    let mut twin = wingman(Vector3::new(0.0, -80.0, 40.0));
    fly_on(&mut moved, &mut twin, 15);
    for p in moved.rows.positions.iter_mut() {
        *p += Vector3::new(3000.0, 0.0, 0.0);
    }
    moved = Bench::new(moved.rows.clone());
    fly_on_from(&mut moved, &mut twin, 15);
    assert!((twin.desired_velocity - before).length() < 1e-3, "{:?} {before:?}", twin.desired_velocity);
}

// One more step of `fly_on`, as its step `k`.
fn fly_on_from(bench: &mut Bench, brain: &mut Brain, k: usize) {
    for r in 1..3 {
        let v = bench.rows.velocities[r];
        bench.rows.positions[r] += v * 0.25;
    }
    bench.think(brain, 0.25 * k as f64, 0, NEVER, 12);
}

#[test]
fn a_wingman_does_not_close_on_a_wingmate_it_could_not_stop_short_of_near_a_hull_or_away_from_one() {
    // A wingmate 60 m to the side flying with it, the wingman already drifting at it at 40 m/s; its slot lies beyond the
    // wingmate, but the wish has no way toward it: near the hull (M7-T38), and away from any hull too (M7-T76).
    for leader_at in [Vector3::new(0.0, 300.0, 600.0), Vector3::new(0.0, 300.0, 9000.0)] {
        let mut bench = wing_bench(leader_at, 0.0, Some(leader_at + Vector3::new(60.0, 0.0, 0.0)));
        bench.rows.velocities[2] = Vector3::new(40.0, 0.0, -100.0);
        bench.rows.velocities[3] = Vector3::new(0.0, 0.0, -100.0);
        let mut brain = wingman(Vector3::new(150.0, 0.0, 0.0));
        bench.think(&mut brain, 0.0, 0, NEVER, 12);
        assert!(brain.desired_velocity.x <= 1e-3, "at {leader_at:?}, no closing: {:?}", brain.desired_velocity);
    }
    // Away from a hull, with room to stop (the wingmate 300 m off), the wish goes for the slot.
    let leader_at = Vector3::new(0.0, 300.0, 9000.0);
    let mut bench = wing_bench(leader_at, 0.0, Some(leader_at + Vector3::new(300.0, 0.0, 0.0)));
    bench.rows.velocities[2] = Vector3::new(40.0, 0.0, -100.0);
    bench.rows.velocities[3] = Vector3::new(0.0, 0.0, -100.0);
    let mut brain = wingman(Vector3::new(150.0, 0.0, 0.0));
    bench.think(&mut brain, 0.0, 0, NEVER, 12);
    assert!(brain.desired_velocity.x > 1.0, "for the slot: {:?}", brain.desired_velocity);
}

#[test]
fn a_wingman_whose_slot_swings_across_its_leader_comes_round_over_it_from_the_left_and_under_it_from_the_right() {
    // M7-T76: the leader turned about, so a slot behind it now lies ahead on the other side, straight across the leader
    // from the wingman. The wingman comes round at its own distance instead of through the leader: over its top from its
    // left, under it from its right, so the two arms never meet. Away from any hull.
    let leader_at = Vector3::new(0.0, 300.0, 9000.0);
    for (side, up) in [(-1.0_f32, 1.0_f32), (1.0, -1.0)] {
        let mut bench = wing_bench(leader_at, 0.0, None);
        bench.rows.positions[2] = leader_at + Vector3::new(40.0 * side, 0.0, 40.0);
        let mut brain = wingman(Vector3::new(-40.0 * side, 0.0, -40.0));
        bench.think(&mut brain, 0.0, 0, NEVER, 12);
        assert!(brain.formation.swing_axis.is_some(), "side {side}: coming round");
        let rise = brain.desired_velocity.y * up;
        assert!(rise > 5.0, "side {side}: {:?}", brain.desired_velocity);
    }
    // A slot it is already beside is flown to straight.
    let mut bench = wing_bench(leader_at, 0.0, None);
    bench.rows.positions[2] = leader_at + Vector3::new(-60.0, 0.0, 40.0);
    let mut brain = wingman(Vector3::new(-40.0, 0.0, 40.0));
    bench.think(&mut brain, 0.0, 0, NEVER, 12);
    assert!(brain.formation.swing_axis.is_none(), "straight to the slot");
}

#[test]
fn a_wingman_coming_round_keeps_off_the_line_its_leader_burns_back_along() {
    // The leader turned about and burns back at 30 m/s^2 toward the wing behind it: a wingman coming round from straight
    // behind it aims 50 m off that line, not down it; an aim already wide of it, or ahead, is kept.
    let leader_at = Vector3::new(0.0, 300.0, 9000.0);
    let mut bench = wing_bench(leader_at, 0.0, None);
    bench.rows.positions[2] = leader_at + Vector3::new(0.0, 0.0, 80.0);
    let mut brain = wingman(Vector3::new(0.0, 0.0, -80.0));
    for k in 0..2 {
        bench.rows.velocities[1] = Vector3::new(0.0, 0.0, -100.0 + 30.0 * 0.25 * k as f32);
        bench.think(&mut brain, 0.25 * k as f64, 0, NEVER, 12);
    }
    let aim = FormationState::clear_of_burn(
        bench.rows.positions[1],
        Vector3::new(0.0, 0.0, 30.0),
        Vector3::new(0.0, 1.0, 0.0),
        leader_at + Vector3::new(0.0, 0.0, 60.0),
    );
    let off = aim - bench.rows.positions[1];
    assert!(brain.formation.swing_axis.is_some(), "coming round");
    assert!(off.x.hypot(off.y) >= 49.9, "off the line: {off:?}");
    for kept in [Vector3::new(70.0, 0.0, 60.0), Vector3::new(0.0, 0.0, -60.0)] {
        let burn = Vector3::new(0.0, 0.0, 30.0);
        let aim = FormationState::clear_of_burn(leader_at, burn, Vector3::new(0.0, 1.0, 0.0), leader_at + kept);
        assert_eq!(aim, leader_at + kept);
    }
}

#[test]
fn a_wingman_holds_off_a_hull_its_leader_flies_into() {
    // M7-T76: the leader flies into the hull's end face at 100 m/s and on inside; the wingman 600 m out behind it, its slot
    // just outside the face, asks to close on the face no faster than it could still stop short of it (a turn, then the
    // retros), outside avoidance's band. Far from any hull the same wish follows the leader.
    let mut bench = wing_bench(Vector3::new(0.0, 0.0, 980.0), 600.0, None);
    let mut brain = wingman(Vector3::new(0.0, 0.0, 40.0));
    bench.think(&mut brain, 0.0, 0, NEVER, 12);
    let turn = 0.5 * std::f64::consts::PI / 1.5 + 1.0;
    let gap = 1580.0 - 1000.0 - (8.0 + pilot::MARGIN_M + pilot::SLIDE_BAND_M);
    let most = 30.0 * ((turn * turn + 2.0 * gap / 30.0).sqrt() - turn);
    let closing = -f64::from(brain.desired_velocity.z);
    assert!(closing <= most + 0.5, "closing {closing} against at most {most}");
    let mut far = wing_bench(Vector3::new(0.0, 0.0, 9980.0), 600.0, None);
    let mut brain = wingman(Vector3::new(0.0, 0.0, 40.0));
    far.think(&mut brain, 0.0, 0, NEVER, 12);
    assert!(-f64::from(brain.desired_velocity.z) > most + 5.0, "{:?}", brain.desired_velocity);
}

#[test]
fn keeping_off_friends_walls_off_the_closing_and_with_none_the_answer_is_avoids() {
    // M7-T76: a wingmate 200 m ahead at rest, the ship closing on it at 100 m/s (a stop across the nose needs 400 m): with
    // the wingmate kept off the answer does not close on it; with no friends kept off it is `avoid`'s, bit for bit.
    let rows = rows_with(&[(RAIDER, 1, Vector3::new(0.0, 0.0, 9000.0)), (MATE, 1, Vector3::new(0.0, 0.0, 8800.0))], 1000.0, 0.0);
    let ship = pilot::Ship {
        position: rows.positions[1],
        velocity: Vector3::new(0.0, 0.0, -100.0),
        radius: 8.0,
        a_retro: 30.0,
        rate_max_x: 1.5,
        rate_max_y: 1.5,
        a_rcs_x: 20.0,
        a_rcs_y: 20.0,
        tie_hash: 5,
    };
    let wish = Vector3::new(30.0, 0.0, -100.0);
    let plain = pilot::avoid(&rows, &ship, &[2], &[], 0, wish);
    let none = pilot::avoid_keeping_off(&rows, &ship, &[2], &[], 0, &[], wish);
    assert_eq!(plain.v_des, none.v_des);
    let kept = pilot::avoid_keeping_off(&rows, &ship, &[2], &[], 0, &[2], wish);
    assert!(kept.v_des.z >= -1e-3, "no closing: {:?}", kept.v_des);
    assert!((kept.v_des.x - plain.v_des.x).abs() < 1e-3, "across it is left alone: {:?} {:?}", kept.v_des, plain.v_des);
}
