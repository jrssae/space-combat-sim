// The far capitals' fire (M10-T85), beside the kernel and outside its engine-free guard (test builds only).
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::Basis;

use super::*;
use crate::capital_gun_kernels::{GunSpec, ROLE_AC, ROLE_DUAL, WARHEAD_MISSILE, WARHEAD_NONE};
use crate::rows::{FLAG_DISGUISE_SHIFT, FLAG_TIER, ROLE_COMBAT, ROLE_SURFACE, Surface};
use crate::surface::from_packed;

const TPS: i64 = 60;
const KIND_SHIP: u8 = 0;
const KIND_CAPITAL: u8 = 1;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

// A long box along z (half extents 20 x 10 x 200) round its centre.
fn hull() -> Surface {
    from_packed(&[0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0, 10.0, 200.0], 0.0)
}

// Tier rows of (body, position, radius, kind, faction, flags); every capital holds `hull()`.
fn rows_of(bodies: &[(i64, Vector3, f64, u8, u32, u32)]) -> Rows {
    let mut rows = Rows::default();
    let mut map = HashMap::new();
    for &(body, at, radius, kind, faction, flags) in bodies {
        rows.body_ids.push(body);
        rows.ids.push(body + 5000);
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
        rows.rigid.push(false);
        rows.is_static.push(false);
        rows.is_mine.push(false);
        rows.hull_fraction.push(1.0);
        rows.target_ids.push(-1);
        rows.reach.push(0.0);
        rows.name_ids.push(0);
        rows.roles.push(if kind == KIND_CAPITAL { ROLE_SURFACE } else { ROLE_COMBAT });
        if kind == KIND_CAPITAL {
            map.insert(body, Arc::new(hull()));
        }
    }
    rows.node_count = bodies.len();
    rows.surfaces = Some(Arc::new(map));
    rows
}

fn gun(role: u8) -> GunSpec {
    GunSpec {
        launcher: false,
        role,
        damage: 30.0,
        barrels: 1,
        burst_shots: 3,
        burst_spacing_s: 0.5,
        cycle_s: 3.0,
        speed_mps: 1800.0,
        range_m: 4000.0,
        lifetime_s: 2.5,
        hit_radius_m: 1.0,
        spread_rad: 0.2f64.to_radians(),
        traverse_rad_s: 1.0,
        elevation_rad_s: 1.0,
        nav_gain: 0.0,
        turn_rad_s: 0.0,
        warhead: WARHEAD_NONE,
        color: [1.0; 4],
        look: 0,
        toughness: 1,
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
    owner_rows: Vec<i32>,
    hostile: Vec<bool>,
    far: Far,
    tick: i64,
    hits: Vec<FarHit>,
    shots: Vec<FarShot>,
}

impl Run {
    // Ship 1 (faction 0) at the origin with a turret on its top facing up; target ship 2 (faction 1) 2 km off along -z.
    fn duel(spec: GunSpec, target: (f64, u8, u32)) -> Run {
        let rows = rows_of(&[
            (1, v(0.0, 0.0, 0.0), 200.0, KIND_CAPITAL, 0, FLAG_TIER),
            (2, v(0.0, 0.0, -2000.0), target.0, target.1, 1, FLAG_TIER | target.2),
        ]);
        let mount = Mount::new(1, 1, v(0.0, 10.0, 0.0), v(0.0, 1.0, 0.0), v(0.0, 0.0, -1.0), 100f64.to_radians(), false, 5.0, spec);
        Run {
            rows,
            mounts: vec![mount],
            owners: vec![Owner { body: 1, bodies: vec![1], order: 0, order_aim: None }, Owner { body: 2, bodies: vec![2], order: 0, order_aim: None }],
            owner_of: vec![0],
            owner_rows: vec![0, 1],
            hostile: table(),
            far: Far::default(),
            tick: 0,
            hits: Vec::new(),
            shots: Vec::new(),
        }
    }

    fn tick(&mut self, seed: u64) {
        let rows = &self.rows;
        let hull_rows: Vec<u32> = (0..rows.body_ids.len() as u32).collect();
        let world = GunWorld {
            rows,
            hull_rows: &hull_rows,
            owner_rows: &self.owner_rows,
            hostile: &self.hostile,
            factions: 3,
            row_of: |id: i64| rows.body_ids.iter().position(|&b| b == id),
            rest: Vector3::ZERO,
            tier_targets: true,
        };
        let clock = Clock { now_s: self.tick as f64 / TPS as f64, tick: self.tick, ticks_per_s: TPS, seed };
        let (mut scratch, mut tally) = (Scratch::default(), Tally::default());
        step(
            &mut self.far,
            &mut self.mounts,
            &self.owners,
            &self.owner_of,
            &world,
            &clock,
            &[0.0, 20.0, 100.0],
            &mut scratch,
            &mut tally,
            &mut self.hits,
            &mut self.shots,
        );
        self.tick += 1;
    }

    fn run(&mut self, seconds: i64, seed: u64) {
        for _ in 0..seconds * TPS {
            self.tick(seed);
        }
    }
}

#[test]
fn a_line_at_a_big_hull_meets_its_surface_and_names_the_volume() {
    let rows = rows_of(&[(2, v(0.0, 0.0, -2000.0), 200.0, KIND_CAPITAL, 1, FLAG_TIER)]);
    let clock = Clock { now_s: 0.0, tick: 0, ticks_per_s: TPS, seed: 7 };
    let (point, local, volume) = line_hit(&rows, 0, Vector3::ZERO, v(0.0, 0.0, -2000.0), 0.0, 0.0, &clock, 1, 0).expect("on the line");
    assert_eq!(volume, 0);
    assert!((point.z + 1800.0).abs() < 0.1, "the near end of the box (z {})", point.z);
    assert!((local.z - 200.0).abs() < 0.1, "in its own frame");
    // Aimed 100 m wide of a 40 m-wide box, it misses.
    assert!(line_hit(&rows, 0, Vector3::ZERO, v(100.0, 0.0, -2000.0), 0.0, 0.0, &clock, 1, 0).is_none());
}

#[test]
fn a_line_at_a_fighter_meets_its_sphere() {
    let rows = rows_of(&[(2, v(0.0, 0.0, -1000.0), 10.0, KIND_SHIP, 1, FLAG_TIER)]);
    let clock = Clock { now_s: 0.0, tick: 0, ticks_per_s: TPS, seed: 7 };
    let (point, _, volume) = line_hit(&rows, 0, Vector3::ZERO, v(0.0, 0.0, -1000.0), 0.0, 0.0, &clock, 1, 0).expect("on the line");
    assert_eq!(volume, -1);
    assert!((point.z + 993.0).abs() < 0.01, "on 0.7 of its radius");
}

#[test]
fn a_far_turret_fires_its_cycle_and_its_bolts_land_on_the_hull() {
    let mut run = Run::duel(gun(ROLE_DUAL), (200.0, KIND_CAPITAL, 0));
    run.owner_rows[1] = -1; // only the shooter rolls
    run.run(30, 7);
    // Bursts of 3 every 3 s (the first roll comes a second after it went far): 9 or 10 cycles.
    let shots = run.mounts[0].shots;
    assert!((27..=30).contains(&shots), "{shots} shots in 30 s");
    assert!(run.hits.len() as i64 >= shots * 6 / 10, "{} hits of {shots} on a 40 x 20 m end", run.hits.len());
    assert!(run.hits.iter().all(|h| h.volume == 0 && h.body == 2 && h.hull == 1002 && h.damage == 30.0));
    assert_eq!(run.far.tally.rolls, 29, "a roll a second once far");
}

#[test]
fn a_ship_just_gone_far_neither_bursts_nor_waits() {
    // Its near mount fired a moment ago: the far rolls wait out its cycle.
    let mut run = Run::duel(gun(ROLE_DUAL), (200.0, KIND_CAPITAL, 0));
    run.mounts[0].ready_at = 2.5;
    run.mounts[0].target = 2;
    run.run(2, 7);
    assert_eq!(run.mounts[0].shots, 0, "nothing before it is ready");
    run.run(2, 7);
    assert_eq!(run.mounts[0].shots, 2, "its burst from when it is ready (2.5 s and 3 s)");
    // One idle a long time fires one burst's worth from when it went far, not the cycles it missed.
    let mut idle = Run::duel(gun(ROLE_DUAL), (200.0, KIND_CAPITAL, 0));
    idle.mounts[0].ready_at = -100.0;
    idle.run(2, 7);
    assert!(idle.mounts[0].shots <= 3, "{} shots", idle.mounts[0].shots);
}

#[test]
fn the_rolls_are_seeded() {
    let mut a = Run::duel(gun(ROLE_DUAL), (12.0, KIND_SHIP, 0));
    let mut b = Run::duel(gun(ROLE_DUAL), (12.0, KIND_SHIP, 0));
    a.run(20, 7);
    b.run(20, 7);
    assert_eq!(a.hits, b.hits);
    assert!(!a.hits.is_empty() && a.hits.len() < a.mounts[0].shots as usize, "a fighter dodges some ({} of {})", a.hits.len(), a.mounts[0].shots);
}

#[test]
fn a_disguised_hostile_is_passed_by() {
    // Ship 2 broadcasts faction 2 (friendly to everyone): ship 1's turret never takes it.
    let disguise = (2 + 1) << FLAG_DISGUISE_SHIFT;
    let mut run = Run::duel(gun(ROLE_DUAL), (200.0, KIND_CAPITAL, disguise));
    run.run(10, 7);
    assert_eq!(run.mounts[0].shots, 0);
    assert!(run.hits.is_empty());
}

#[test]
fn a_ship_out_of_the_far_rows_rolls_nothing() {
    let mut run = Run::duel(gun(ROLE_DUAL), (200.0, KIND_CAPITAL, 0));
    run.owner_rows = vec![-1, -1]; // in play, a hulk or disabled: the shell names no far row
    run.run(10, 7);
    assert_eq!(run.mounts[0].shots, 0);
    assert_eq!(run.far.tally.rolls, 0);
}

#[test]
fn the_brains_order_takes_the_heavy_weapons() {
    // Two hostile capitals; the order names the farther one.
    let rows = rows_of(&[
        (1, v(0.0, 0.0, 0.0), 200.0, KIND_CAPITAL, 0, FLAG_TIER),
        (2, v(0.0, 0.0, -1500.0), 200.0, KIND_CAPITAL, 1, FLAG_TIER),
        (3, v(0.0, 0.0, 3000.0), 200.0, KIND_CAPITAL, 1, FLAG_TIER),
    ]);
    let mut run = Run::duel(gun(ROLE_AC), (200.0, KIND_CAPITAL, 0));
    run.rows = rows;
    run.owners[0].order = 3;
    run.owner_rows = vec![0, 1];
    run.run(5, 7);
    assert!(!run.hits.is_empty());
    assert!(run.hits.iter().all(|h| h.body == 3), "on its order, not the nearer ship");
}

#[test]
fn the_targets_batteries_take_their_share() {
    let mut run = Run::duel(gun(ROLE_DUAL), (200.0, KIND_CAPITAL, 0));
    let mut pd = Mount::new(2, 9, v(0.0, 10.0, 0.0), v(0.0, 1.0, 0.0), v(0.0, 0.0, -1.0), 100f64.to_radians(), false, 1.0, GunSpec { role: ROLE_PD, ..gun(ROLE_PD) });
    pd.works = true;
    run.mounts.push(pd);
    run.owner_of.push(1);
    run.run(120, 7);
    let landed = run.hits.len() as f64;
    let down = run.far.tally.bolts_down as f64;
    let share = down / (down + landed);
    assert!((share - PD_SHARE).abs() < 0.08, "{down} of {} taken", down + landed);
    // With its battery lost, nothing is taken.
    run.mounts[1].works = false;
    let before = run.far.tally.bolts_down;
    run.run(30, 7);
    assert_eq!(run.far.tally.bolts_down, before);
}

#[test]
fn a_far_round_arrives_after_its_flight_with_its_warhead() {
    let spec = GunSpec {
        launcher: true,
        burst_shots: 1,
        speed_mps: 350.0,
        range_m: 6000.0,
        lifetime_s: 20.0,
        cycle_s: 12.0,
        damage: 40.0,
        warhead: WARHEAD_MISSILE,
        ..gun(ROLE_DUAL)
    };
    let mut run = Run::duel(spec, (200.0, KIND_CAPITAL, 0));
    run.run(2, 7);
    assert_eq!(run.far.rounds.len(), 1, "a round in flight");
    assert!(run.hits.is_empty(), "not yet: 1 800 m at 350 m/s");
    run.run(5, 7);
    assert_eq!(run.hits.len(), 1);
    assert_eq!(run.hits[0].damage, 60.0, "its hit and its warhead's blast");
    assert_eq!(run.hits[0].volume, 0);
}

#[test]
fn a_round_whose_target_is_gone_is_lost() {
    let spec = GunSpec { launcher: true, burst_shots: 1, speed_mps: 350.0, range_m: 6000.0, lifetime_s: 20.0, cycle_s: 12.0, warhead: WARHEAD_MISSILE, ..gun(ROLE_DUAL) };
    let mut run = Run::duel(spec, (200.0, KIND_CAPITAL, 0));
    run.run(2, 7);
    run.rows.body_ids[1] = 99; // its target left the rows
    run.run(6, 7);
    assert!(run.hits.is_empty());
    assert_eq!(run.far.tally.rounds_lost, 1);
}
