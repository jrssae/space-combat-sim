// The capitals' interceptor batteries (M10-T13, Q81), beside the kernel and outside its engine-free guard (test builds only):
// the rate, real pulses that can miss, toughness, the guarded set, the order, friendly fire and the disguise, a silent mount,
// and two runs alike. A small sim moves the bolts as the core does (no step on a pulse's launch tick).
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::Basis;

use super::*;
use crate::capital_gun_kernels::{GunSpec, Missile, WARHEAD_MISSILE};
use crate::rows::{FLAG_DISGUISE_SHIFT, FLAG_HULL_ACTIVE, FLAG_RIGID, LOOK_NONE, ROLE_COMBAT, ROLE_SURFACE, Surface};
use crate::surface::from_packed;
use crate::v3::{add, scale};

const LIVE: u32 = FLAG_RIGID | FLAG_HULL_ACTIVE;
const DT: f64 = 1.0 / 60.0;
// Bodies: 1 our capital (faction 0), 3 a friendly capital (faction 2), 4 a hostile capital (faction 1), 2 a hostile fighter
// (faction 1), 5 a friendly fighter (faction 0), 6 a neutral fighter (faction 3).
const OURS: i64 = 1;
const FIGHTER: i64 = 2;
const FRIEND: i64 = 3;
const ENEMY: i64 = 4;
const WINGMAN: i64 = 5;
const NEUTRAL: i64 = 6;
const N: usize = 4;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

// A capital's hull: a long box along z (half extents 20 x 10 x 200) round its centre.
fn hull() -> Surface {
    from_packed(&[0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0, 10.0, 200.0], 0.0)
}

// Faction 0 and 1 hostile; 0 and 2 friendly (and each to itself); 3 neutral to all.
fn hostile_table() -> Vec<bool> {
    let mut t = vec![false; N * N];
    t[1] = true;
    t[N] = true;
    t
}

fn friendly_table() -> Vec<bool> {
    let mut t = vec![false; N * N];
    for a in 0..N {
        t[a * N + a] = true;
    }
    t[2] = true;
    t[2 * N] = true;
    t
}

fn world_rows(friend_at: Vector3) -> Rows {
    let bodies: [(i64, Vector3, f64, u8, u32, bool); 6] = [
        (OURS, v(0.0, 0.0, 0.0), 210.0, 1, 0, true),
        (FIGHTER, v(0.0, 900.0, 0.0), 8.0, 0, 1, false),
        (FRIEND, friend_at, 210.0, 1, 2, true),
        (ENEMY, v(-3000.0, 0.0, 0.0), 210.0, 1, 1, true),
        (WINGMAN, v(0.0, -900.0, 0.0), 8.0, 0, 0, false),
        (NEUTRAL, v(900.0, 900.0, 0.0), 8.0, 0, 3, false),
    ];
    let mut rows = Rows::default();
    let mut map = HashMap::new();
    for &(body, at, radius, kind, faction, big) in &bodies {
        rows.body_ids.push(body);
        rows.ids.push(body + 5000);
        rows.faction_ix.push(faction);
        rows.positions.push(at);
        rows.velocities.push(Vector3::ZERO);
        rows.bases.push(Basis::IDENTITY);
        rows.angular.push(Vector3::ZERO);
        rows.radii.push(radius);
        rows.kinds.push(kind);
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
        rows.roles.push(if big { ROLE_SURFACE } else { ROLE_COMBAT });
        if big {
            map.insert(body, Arc::new(hull()));
        }
    }
    rows.node_count = bodies.len();
    rows.surfaces = Some(Arc::new(map));
    rows
}

fn battery_spec(cycle_s: f64, barrels: u32, spread_deg: f64) -> GunSpec {
    GunSpec {
        role: ROLE_PD,
        barrels,
        burst_shots: 1,
        cycle_s,
        speed_mps: 2000.0,
        range_m: 1500.0,
        lifetime_s: 1.0,
        hit_radius_m: 2.5,
        spread_rad: spread_deg.to_radians(),
        traverse_rad_s: 360f64.to_radians(),
        elevation_rad_s: 360f64.to_radians(),
        color: [1.0; 4],
        look: LOOK_NONE,
        toughness: 1,
        ..GunSpec::default()
    }
}

struct Sim {
    rows: Rows,
    bolts: Bolts,
    mounts: Vec<Mount>,
    owners: Vec<Owner>,
    owner_of: Vec<u32>,
    missiles: Vec<Missile>,
    guards: Guards,
    next_id: i64,
    now_s: f64,
    tick: i64,
    pulses: Vec<PulseShot>,
    mets: Vec<Met>,
}

impl Sim {
    // Our capital with one battery on its top (10 m up, its base facing up: the hemisphere over the deck).
    fn new(spec: GunSpec) -> Sim {
        Sim::with_rows(world_rows(v(500.0, 0.0, 0.0)), spec)
    }

    fn with_rows(rows: Rows, spec: GunSpec) -> Sim {
        let battery = Mount::new(OURS, 7, v(0.0, 10.0, 0.0), v(0.0, 1.0, 0.0), v(0.0, 0.0, -1.0), 90f64.to_radians(), false, 3.0, spec);
        Sim {
            rows,
            bolts: Bolts::default(),
            mounts: vec![battery],
            owners: vec![Owner { body: OURS, bodies: vec![OURS], order: 0, order_aim: None }],
            owner_of: vec![0],
            missiles: Vec::new(),
            guards: Guards::default(),
            next_id: 0,
            now_s: 0.0,
            tick: 0,
            pulses: Vec::new(),
            mets: Vec::new(),
        }
    }

    // A shot by body `shooter` (its row's faction) from `at` at `velocity`, taking `hits` pulses; its id.
    fn shoot(&mut self, shooter: i64, kind: u8, at: Vector3, velocity: Vector3, hits: u8) -> i64 {
        let faction = self.rows.faction_ix[self.row(shooter).unwrap()];
        self.add(shooter, faction, kind, at, velocity, 0.5, hits, self.now_s + 5.0)
    }

    #[allow(clippy::too_many_arguments)]
    fn add(&mut self, shooter: i64, faction: u32, kind: u8, at: Vector3, velocity: Vector3, radius: f64, hits: u8, expires: f64) -> i64 {
        self.next_id -= 1;
        let id = self.next_id;
        self.bolts.insert_owned(id, at, velocity, faction, shooter, kind, radius, 10.0, [1.0; 4], LOOK_NONE, expires, self.tick);
        self.bolts.set_newest_owned_hits(hits);
        id
    }

    fn row(&self, body: i64) -> Option<usize> {
        self.rows.body_ids.iter().position(|&b| b == body)
    }

    fn tick(&mut self) {
        let shooter_rows: Vec<i32> =
            self.bolts.shooters.iter().map(|&s| self.row(s).map_or(-1, |r| r as i32)).collect();
        let (hostile, friendly) = (hostile_table(), friendly_table());
        self.guards.meet(&self.mounts, &mut self.bolts, &self.rows, &shooter_rows, &hostile, N, &self.missiles, &mut self.mets);
        let rows = &self.rows;
        let owner_rows: Vec<i32> = self.owners.iter().map(|o| rows.body_ids.iter().position(|&b| b == o.body).map_or(-1, |r| r as i32)).collect();
        let hull_rows: Vec<u32> = (0..rows.body_ids.len() as u32).collect();
        let world = GunWorld {
            rows,
            hull_rows: &hull_rows,
            owner_rows: &owner_rows,
            hostile: &hostile,
            factions: N,
            row_of: |id: i64| rows.body_ids.iter().position(|&b| b == id),
            rest: Vector3::ZERO,
            tier_targets: false,
        };
        let view = GuardView { friendly: &friendly, shooter_rows: &shooter_rows };
        let mut fired = Vec::new();
        self.guards.step(
            &mut self.mounts, &self.owners, &self.owner_of, &world, &view, &self.bolts, &self.missiles, self.now_s, DT,
            self.tick, &mut fired,
        );
        for p in &fired {
            let spec = self.mounts[p.mount as usize].spec;
            let faction = self.rows.faction_ix[0];
            let id = self.add(OURS, faction, ik::KIND_INTERCEPT, p.start, p.velocity, spec.hit_radius_m, 1, self.now_s + spec.lifetime_s);
            self.guards.note_pulse(id, p.mount_id, p.target, p.meet_at);
        }
        self.pulses.extend(fired);
        // The bolts move after the step; a row launched this tick does not (the core's rule).
        let b = &mut self.bolts;
        for i in 0..b.ids.len() {
            if b.spent[i] || b.launched[i] == self.tick {
                b.last_steps[i] = Vector3::ZERO;
                continue;
            }
            let step = scale(b.velocities[i], DT as f32);
            b.last_steps[i] = step;
            b.positions[i] = add(b.positions[i], step);
            if self.now_s + DT > b.expires_at[i] {
                b.spent[i] = true;
            }
        }
        self.now_s += DT;
        self.tick += 1;
    }

    fn run(&mut self, ticks: usize) {
        for _ in 0..ticks {
            self.tick();
        }
    }

    fn spent(&self, id: i64) -> bool {
        self.bolts.ids.iter().position(|&b| b == id).is_some_and(|i| self.bolts.spent[i])
    }

    fn pulses_at(&self, id: i64) -> usize {
        self.pulses.iter().filter(|p| p.target == id).count()
    }
}

// A bolt from the hostile fighter 900 m over our deck, straight down at it (1 000 m/s).
fn bolt_at_our_deck(sim: &mut Sim, x: f32, hits: u8) -> i64 {
    sim.shoot(FIGHTER, ik::KIND_BOLT, v(x, 900.0, 0.0), v(0.0, -1000.0, 0.0), hits)
}

#[test]
fn a_battery_fires_four_pulses_a_second_from_its_barrels_in_turn() {
    let mut sim = Sim::new(battery_spec(0.25, 4, 0.0));
    // A stream of bolts at the deck, more than it can take.
    for k in 0..12 {
        bolt_at_our_deck(&mut sim, k as f32 * 4.0, 1);
    }
    sim.run(60);
    assert_eq!(sim.pulses.len(), 4, "4 pulses a second (Q81)");
    assert_eq!(sim.pulses.iter().map(|p| p.barrel).collect::<Vec<_>>(), vec![0, 1, 2, 3], "the barrels in turn");
    // The Nova's pods: 2 a second.
    let mut pod = Sim::new(battery_spec(0.5, 2, 0.0));
    for k in 0..12 {
        bolt_at_our_deck(&mut pod, k as f32 * 4.0, 1);
    }
    pod.run(60);
    assert_eq!(pod.pulses.len(), 2);
}

#[test]
fn a_led_pulse_meets_its_bolt_and_a_wide_spread_misses_and_tries_again() {
    let mut sim = Sim::new(battery_spec(0.25, 4, 0.0));
    let id = bolt_at_our_deck(&mut sim, 0.0, 1);
    sim.run(40);
    assert!(sim.spent(id), "led true, the pulse meets it");
    assert_eq!(sim.guards.tally.down[usize::from(SHOT_BOLT)], 1);
    assert_eq!(sim.pulses_at(id), 1, "one pulse was enough: the cover kept the others off it");
    // A spread far wider than the shot: the first pulse misses, and once its meeting is past the battery fires again.
    let mut wild = Sim::new(battery_spec(0.25, 4, 25.0));
    let far = wild.shoot(FIGHTER, ik::KIND_BOLT, v(0.0, 1400.0, 0.0), v(0.0, -300.0, 0.0), 1);
    wild.run(150);
    assert!(wild.pulses_at(far) >= 2, "a miss is shot at again ({} pulses)", wild.pulses_at(far));
    assert!(wild.guards.tally.met < wild.guards.tally.pulses, "not every pulse met: they can miss");
}

#[test]
fn toughness_takes_that_many_pulses() {
    let mut sim = Sim::new(battery_spec(0.25, 4, 0.0));
    let heavy = sim.shoot(FIGHTER, ik::KIND_BOLT, v(0.0, 1400.0, 0.0), v(0.0, -400.0, 0.0), 2);
    sim.run(200);
    assert!(sim.spent(heavy));
    assert_eq!(sim.guards.tally.met, 2, "two pulses for a heavy bolt");
    assert_eq!(sim.guards.tally.down[usize::from(SHOT_HEAVY)], 1);
    let mut torpedo = Sim::new(battery_spec(0.25, 4, 0.0));
    let t = torpedo.shoot(ENEMY, ik::KIND_MISSILE, v(0.0, 1450.0, 0.0), v(0.0, -400.0, 0.0), 3);
    torpedo.missiles.push(Missile { bolt: t, target: OURS, mount: 0, nav_gain: 0.0, turn_rad_s: 0.0, warhead: WARHEAD_TORPEDO });
    torpedo.run(300);
    assert!(torpedo.spent(t));
    assert_eq!(torpedo.guards.tally.met, 3, "three for a torpedo");
    assert_eq!(torpedo.guards.tally.down[usize::from(SHOT_TORPEDO)], 1);
}

#[test]
fn it_guards_its_hull_and_a_friendly_capital_never_a_hostile_hull_or_a_fighter() {
    let mut sim = Sim::new(battery_spec(0.25, 4, 0.0));
    // The friend 500 m to starboard; bolts down onto it, onto the hostile hull's own side, onto our wingman, and past us.
    let at_friend = sim.shoot(FIGHTER, ik::KIND_BOLT, v(500.0, 900.0, 0.0), v(0.0, -1000.0, 0.0), 1);
    let at_wingman = sim.shoot(FIGHTER, ik::KIND_BOLT, v(0.0, -400.0, 300.0), v(0.0, -1000.0, 0.0), 1);
    let wide = sim.shoot(FIGHTER, ik::KIND_BOLT, v(200.0, 900.0, 0.0), v(0.0, -1000.0, 0.0), 1);
    sim.run(60);
    assert!(sim.pulses_at(at_friend) >= 1 && sim.spent(at_friend), "a friendly capital is covered");
    assert_eq!(sim.pulses_at(at_wingman), 0, "fighters are not guarded");
    assert_eq!(sim.pulses_at(wide), 0, "a shot that meets no guarded hull is left");
    // A neutral's shot at the hostile capital's hull is nothing of ours.
    let mut other = Sim::new(battery_spec(0.25, 4, 0.0));
    other.rows.positions[3] = v(0.0, 0.0, -900.0); // the hostile hull just ahead of us
    let at_enemy = other.shoot(NEUTRAL, ik::KIND_BOLT, v(0.0, 300.0, -900.0), v(0.0, -1000.0, 0.0), 1);
    other.run(60);
    assert_eq!(other.pulses_at(at_enemy), 0);
}

#[test]
fn missiles_first_then_its_own_hull_before_a_friends() {
    let mut sim = Sim::new(battery_spec(0.25, 4, 0.0));
    // Fired at once: a bolt at the friend that hits first, a bolt at our deck later, and a slow missile at the friend.
    let at_friend = sim.shoot(FIGHTER, ik::KIND_BOLT, v(500.0, 600.0, 0.0), v(0.0, -1000.0, 0.0), 1);
    let at_us = sim.shoot(FIGHTER, ik::KIND_BOLT, v(0.0, 1200.0, 0.0), v(0.0, -1000.0, 0.0), 1);
    let missile = sim.shoot(FIGHTER, ik::KIND_MISSILE, v(450.0, 1400.0, 0.0), v(0.0, -300.0, 0.0), 1);
    sim.missiles.push(Missile { bolt: missile, target: FRIEND, mount: 0, nav_gain: 0.0, turn_rad_s: 0.0, warhead: WARHEAD_MISSILE });
    sim.run(40);
    let order: Vec<i64> = sim.pulses.iter().map(|p| p.target).collect();
    assert_eq!(order[..3], [missile, at_us, at_friend], "the missile, then our hull, then the friend's");
}

#[test]
fn friendly_fire_and_a_still_disguised_shooters_shots_are_left_alone() {
    let mut sim = Sim::new(battery_spec(0.25, 4, 0.0));
    // Our wingman's stray shot at our deck: friendly fire.
    let stray = sim.shoot(WINGMAN, ik::KIND_BOLT, v(0.0, 900.0, 0.0), v(0.0, -1000.0, 0.0), 1);
    // The hostile fighter broadcasting faction 2 (friendly): its shot is not taken while it is disguised.
    sim.rows.flags[1] = LIVE | (3 << FLAG_DISGUISE_SHIFT);
    let _masked = sim.shoot(FIGHTER, ik::KIND_BOLT, v(5.0, 900.0, 0.0), v(0.0, -1000.0, 0.0), 1);
    sim.run(30);
    assert_eq!(sim.pulses.len(), 0, "{:?}", sim.pulses);
    // Revealed: its shots are taken from now on (the one still flying too); the wingman's never.
    sim.rows.flags[1] = LIVE;
    let revealed = sim.shoot(FIGHTER, ik::KIND_BOLT, v(10.0, 900.0, 0.0), v(0.0, -1000.0, 0.0), 1);
    sim.run(30);
    assert!(sim.pulses_at(revealed) >= 1);
    assert_eq!(sim.pulses_at(stray), 0);
}

#[test]
fn a_lost_mount_or_a_hulk_fires_no_pulse() {
    for (works, rate) in [(false, 1.0), (true, 0.0)] {
        let mut sim = Sim::new(battery_spec(0.25, 4, 0.0));
        sim.mounts[0].works = works;
        sim.mounts[0].rate = rate;
        bolt_at_our_deck(&mut sim, 0.0, 1);
        sim.run(60);
        assert!(sim.pulses.is_empty(), "works {works}, rate {rate}");
    }
}

#[test]
fn a_guided_missile_is_judged_by_its_target_not_its_straight_path() {
    let mut sim = Sim::new(battery_spec(0.25, 4, 0.0));
    // Flying past us now, guided at the friend: taken. Flying straight at our deck, guided at the hostile hull: left.
    let at_friend = sim.shoot(FIGHTER, ik::KIND_MISSILE, v(-300.0, 600.0, 0.0), v(0.0, 0.0, -300.0), 1);
    let elsewhere = sim.shoot(WINGMAN, ik::KIND_MISSILE, v(30.0, 900.0, 0.0), v(0.0, -300.0, 0.0), 1);
    sim.missiles.push(Missile { bolt: at_friend, target: FRIEND, mount: 0, nav_gain: 0.0, turn_rad_s: 0.0, warhead: WARHEAD_MISSILE });
    sim.missiles.push(Missile { bolt: elsewhere, target: ENEMY, mount: 0, nav_gain: 0.0, turn_rad_s: 0.0, warhead: WARHEAD_MISSILE });
    sim.run(20);
    assert!(sim.pulses_at(at_friend) >= 1);
    assert_eq!(sim.pulses_at(elsewhere), 0);
}

#[test]
fn a_ships_share_counts_the_shots_at_its_hull_and_those_shot_down() {
    let mut sim = Sim::new(battery_spec(0.25, 4, 0.0));
    for k in 0..6 {
        bolt_at_our_deck(&mut sim, k as f32 * 4.0, 1);
    }
    sim.run(90);
    let (seen, down) = sim.guards.share_of(OURS);
    assert_eq!(seen, 6);
    assert!(down >= 1 && down < seen, "{down} of {seen}: four a second cannot take all six before they land");
}

#[test]
fn two_runs_of_a_seeded_exchange_fire_and_meet_alike() {
    let run = || {
        let mut sim = Sim::new(battery_spec(0.25, 4, 1.5));
        for k in 0..20 {
            sim.shoot(FIGHTER, ik::KIND_BOLT, v(k as f32 * 7.0 - 70.0, 1300.0, k as f32 * 3.0), v(5.0, -400.0, -2.0), 1 + (k % 3) as u8);
        }
        sim.run(240);
        (sim.pulses.clone(), sim.guards.tally, sim.bolts.spent.clone())
    };
    let (a, b) = (run(), run());
    assert!(!a.0.is_empty());
    assert_eq!(a, b);
}
