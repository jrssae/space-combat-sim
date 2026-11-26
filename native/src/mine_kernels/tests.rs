// The mines' kernel (M10-T15), beside it and outside its engine-free guard (test builds only).
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::Basis;

use super::*;
use crate::rows::{ROLE_COMBAT, ROLE_SURFACE, Surface};
use crate::surface::from_packed;

const LIVE: u32 = FLAG_RIGID | FLAG_HULL_ACTIVE;
const FRIEND: u32 = 0;
const FOE: u32 = 1;
const N: usize = 2;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

fn specs() -> [Spec; KINDS] {
    let prox = Spec { trigger_m: 60.0, blast_m: 120.0, radar_m: 1000.0, ..Spec::NONE };
    let energy = Spec {
        trigger_m: 200.0,
        speed_mps: 900.0,
        fuse_s: 5.0,
        capitals_only: true,
        blast_m: 300.0,
        toughness: 3,
        radar_m: 1000.0,
        ..Spec::NONE
    };
    let guided = Spec {
        trigger_m: 30.0,
        dormant_s: 60.0,
        speed_mps: 150.0,
        home_m: 800.0,
        turn_rad_s: 1.0,
        blast_m: 60.0,
        radar_m: 1000.0,
        ..Spec::NONE
    };
    [prox, energy, guided]
}

// The relations: side 0 and side 1 are enemies.
fn hostile() -> Vec<bool> {
    vec![false, true, true, false]
}

// One row per (body, faction, position, radius, flags); body 7 holds `surface` when one is given.
fn rows_of(bodies: &[(i64, u32, Vector3, f64, u32)], surface: Option<Surface>) -> Rows {
    let mut rows = Rows::default();
    for &(body, faction, at, radius, flags) in bodies {
        rows.body_ids.push(body);
        rows.ids.push(body);
        rows.faction_ix.push(faction);
        rows.positions.push(at);
        rows.velocities.push(Vector3::ZERO);
        rows.bases.push(Basis::IDENTITY);
        rows.angular.push(Vector3::ZERO);
        rows.radii.push(radius);
        rows.kinds.push(0);
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
        rows.roles.push(if body == 7 && surface.is_some() { ROLE_SURFACE } else { ROLE_COMBAT });
    }
    rows.node_count = bodies.len();
    if let Some(s) = surface {
        let mut map = HashMap::new();
        map.insert(7_i64, Arc::new(s));
        rows.surfaces = Some(Arc::new(map));
    }
    rows
}

// A capital's box: half extents 20 x 10 x 200.
fn hull() -> Surface {
    let p = vec![0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0, 10.0, 200.0];
    from_packed(&p, 0.0)
}

struct Sim {
    mines: Mines,
    rows: Rows,
    bolts: Bolts,
    out: StepOut,
    order: Vec<u32>,
    now_s: f64,
    tick: i64,
}

impl Sim {
    fn new(rows: Rows) -> Sim {
        let order = (0..rows.positions.len() as u32).collect();
        Sim { mines: Mines::default(), rows, bolts: Bolts::default(), out: StepOut::default(), order, now_s: 0.0, tick: 0 }
    }

    // A placed mine of `kind`, armed, at rest.
    fn place(&mut self, kind: u8, faction: u32, at: Vector3) -> usize {
        self.mines.lay(None, kind, faction, at, Vector3::ZERO, ARMED, 0.0, &specs()[kind as usize], 0).unwrap()
    }

    // One tick of a sixtieth of a second with the field's node at the World's origin.
    fn tick(&mut self) {
        let h = hostile();
        let w = World {
            rows: &self.rows,
            bolts: &self.bolts,
            hull_rows: &self.order,
            hostile: &h,
            factions: N,
            origin: Vector3::ZERO,
            frame_velocity: Vector3::ZERO,
            tick: self.tick,
            now_s: self.now_s,
            delta: 1.0 / 60.0,
        };
        step(&mut self.mines, &specs(), &w, &mut self.out);
        self.tick += 1;
        self.now_s += 1.0 / 60.0;
    }

    // Ticks until a mine goes off or `n` ticks pass; the slots that went off.
    fn run(&mut self, n: usize) -> Vec<u32> {
        for _ in 0..n {
            self.tick();
            if !self.out.dets.is_empty() {
                return self.out.dets.iter().map(|d| d.0).collect();
            }
        }
        Vec::new()
    }
}

#[test]
fn a_hostile_inside_the_trigger_sets_a_mine_off_and_a_friend_does_not() {
    let mut s = Sim::new(rows_of(&[(1, FRIEND, v(0.0, 0.0, 70.0), 10.0, LIVE)], None));
    s.place(PROX, FRIEND, Vector3::ZERO);
    assert!(s.run(9).is_empty(), "a friend 60 m off its surface sets nothing off");
    s.rows.faction_ix[0] = FOE;
    // 70 m centre to centre less a 10 m sphere is exactly 60 m: inside.
    assert_eq!(s.run(9), vec![0], "a hostile within 60 m of its surface sets it off");
    assert_eq!(s.out.dets[0].1, CAUSE_TRIGGER);
}

#[test]
fn a_disguise_does_not_fool_a_mine() {
    let disguised = LIVE | ((FRIEND + 1) << crate::rows::FLAG_DISGUISE_SHIFT);
    let mut s = Sim::new(rows_of(&[(1, FOE, v(0.0, 0.0, 40.0), 5.0, disguised)], None));
    s.place(PROX, FRIEND, Vector3::ZERO);
    assert_eq!(s.run(3), vec![0], "a ship broadcasting the mine's own side is still an enemy by its true faction");
}

#[test]
fn the_trigger_is_measured_from_a_big_hulls_surface_not_its_sphere() {
    // The hull's sphere is 400 m: by the sphere a mine 300 m off its middle would be inside; by the box it is 280 m off.
    let mut s = Sim::new(rows_of(&[(7, FOE, Vector3::ZERO, 400.0, LIVE)], Some(hull())));
    s.place(PROX, FRIEND, v(300.0, 0.0, 0.0));
    assert!(s.run(9).is_empty());
    s.mines.local[0] = v(70.0, 0.0, 0.0);
    s.mines.dirty = true;
    assert_eq!(s.run(9), vec![0], "70 m off the middle is 50 m off the box: inside the 60 m trigger");
}

#[test]
fn a_touch_sets_off_a_mine_of_any_side_on_any_tick_also_for_a_fast_hull() {
    let mut s = Sim::new(rows_of(&[(1, FRIEND, v(0.0, 0.0, 0.0), 2.0, LIVE)], None));
    s.place(PROX, FRIEND, v(0.0, 0.0, 0.0));
    s.tick();
    assert_eq!(s.out.dets, vec![(0, CAUSE_TOUCH)], "its own side's hull touching the body sets it off, off the cadence");
    // A fast hull between ticks: 3 000 m/s is 50 m a tick, from 30 m before the mine to 20 m past it.
    let mut s = Sim::new(rows_of(&[(1, FOE, v(0.0, 0.0, 20.0), 2.0, LIVE)], None));
    s.rows.velocities[0] = v(0.0, 0.0, 3000.0);
    s.place(PROX, FOE, Vector3::ZERO);
    s.tick();
    assert_eq!(s.out.dets, vec![(0, CAUSE_TOUCH)]);
}

#[test]
fn a_laid_mine_arms_late_and_ignores_its_own_ships_touch_for_a_while() {
    let mut s = Sim::new(rows_of(&[(5, FRIEND, v(0.0, 0.0, 0.0), 2.0, LIVE), (6, FOE, v(0.0, 0.0, 40.0), 5.0, LIVE)], None));
    let spec = Spec { arm_s: 2.0, ..specs()[PROX as usize] };
    s.mines.lay(None, PROX, FRIEND, Vector3::ZERO, Vector3::ZERO, DORMANT, 0.0, &spec, 5).unwrap();
    for _ in 0..60 {
        s.tick();
        assert!(s.out.dets.is_empty(), "unarmed for 2 s, and its own ship's touch is ignored for {OWN_GRACE_S} s");
    }
    for _ in 0..70 {
        s.tick();
    }
    assert_eq!(s.out.dets.iter().map(|d| d.0).collect::<Vec<_>>(), vec![0], "armed at 2 s the hostile 40 m off sets it off");
}

fn flying_energy(s: &mut Sim, from: Vector3, to: Vector3) -> usize {
    let spec = specs()[ENERGY as usize];
    let slot = s.mines.lay(None, ENERGY, FRIEND, from, Vector3::ZERO, FLYING, 0.0, &spec, 0).unwrap();
    let heading = normalized(sub(to, from));
    s.bolts.insert_owned(-1, from, scale(heading, 900.0), FRIEND, 0, 3, 1.0, 0.0, [1.0; 4], 255, 60.0, 0);
    s.mines.bolt[slot] = -1;
    s.mines.dest[slot] = to;
    slot
}

#[test]
fn an_energy_mine_arrives_and_arms_at_its_lead_point() {
    let mut s = Sim::new(rows_of(&[(1, FRIEND, v(0.0, 0.0, 9000.0), 8.0, LIVE)], None));
    let slot = flying_energy(&mut s, v(0.0, 0.0, -3000.0), v(0.0, 0.0, -1000.0));
    let mut ticks = 0;
    while s.mines.state[slot] == FLYING && ticks < 400 {
        s.tick();
        // The core's own bolt step moves the row between ticks.
        let step = scale(s.bolts.velocities[0], 1.0 / 60.0);
        s.bolts.positions[0] = add(s.bolts.positions[0], step);
        ticks += 1;
    }
    assert_eq!(s.mines.state[slot], ARMED, "it arrived and armed after {ticks} ticks");
    assert!(s.mines.fixed[slot]);
    assert_eq!(s.out.spends, vec![-1], "its bolt row is given up");
    assert!((f64::from(length(s.mines.local[slot])) - 1000.0).abs() < 1e-3, "it stops on the lead point");
}

#[test]
fn an_armed_energy_mine_goes_off_on_a_hostile_capital_and_not_on_a_fighter() {
    let mut s = Sim::new(rows_of(&[(1, FOE, v(0.0, 0.0, 100.0), 8.0, LIVE), (7, FOE, v(0.0, 0.0, 2000.0), 400.0, LIVE)], Some(hull())));
    s.rows.positions[1] = v(400.0, 0.0, 0.0);
    s.place(ENERGY, FRIEND, Vector3::ZERO);
    assert!(s.run(9).is_empty(), "a hostile fighter 90 m off and a capital 380 m off its surface do not trigger it");
    s.rows.positions[1] = v(215.0, 0.0, 0.0);
    assert_eq!(s.run(9), vec![0], "the capital's surface 195 m off does");
    assert_eq!(s.out.dets[0].1, CAUSE_TRIGGER);
}

#[test]
fn an_energy_mines_fuse_sets_it_off_five_seconds_after_it_arrives() {
    let mut s = Sim::new(rows_of(&[(1, FRIEND, v(0.0, 0.0, 9000.0), 8.0, LIVE)], None));
    let slot = flying_energy(&mut s, v(0.0, 0.0, -100.0), v(0.0, 0.0, 0.0));
    for _ in 0..30 {
        s.tick();
        let step = scale(s.bolts.velocities[0], 1.0 / 60.0);
        s.bolts.positions[0] = add(s.bolts.positions[0], step);
        if s.mines.state[slot] == ARMED {
            break;
        }
    }
    assert_eq!(s.mines.state[slot], ARMED);
    let armed_at = s.now_s;
    let went = s.run(60 * 6);
    assert_eq!(went, vec![slot as u32]);
    assert_eq!(s.out.dets[0].1, CAUSE_FUSE);
    assert!((s.now_s - armed_at - 5.0).abs() < 0.1, "it went off {} s after arriving", s.now_s - armed_at);
}

#[test]
fn a_shot_down_mine_is_out_of_play_without_a_blast_and_a_missing_row_goes_off() {
    let mut s = Sim::new(rows_of(&[(1, FRIEND, v(0.0, 0.0, 9000.0), 8.0, LIVE)], None));
    let slot = flying_energy(&mut s, v(0.0, 0.0, -3000.0), v(0.0, 0.0, -1000.0));
    s.bolts.spent[0] = true;
    s.tick();
    assert_eq!(s.out.downed, vec![slot as u32]);
    assert!(s.out.dets.is_empty());
    let mut s = Sim::new(rows_of(&[(1, FRIEND, v(0.0, 0.0, 9000.0), 8.0, LIVE)], None));
    let slot = flying_energy(&mut s, v(0.0, 0.0, -3000.0), v(0.0, 0.0, -1000.0));
    s.bolts.retain_owned(&[false]);
    s.tick();
    assert_eq!(s.out.dets, vec![(slot as u32, CAUSE_FLIGHT)], "a row that struck something is gone: the mine goes off");
}

#[test]
fn a_guided_mine_sleeps_wakes_homes_and_goes_off_within_its_trigger() {
    let mut s = Sim::new(rows_of(&[(1, FOE, v(0.0, 0.0, -500.0), 6.0, LIVE)], None));
    let slot = s.mines.lay(None, GUIDED, FRIEND, Vector3::ZERO, Vector3::ZERO, DORMANT, 0.0, &specs()[GUIDED as usize], 0).unwrap();
    for _ in 0..(60 * 59) {
        s.tick();
        assert_eq!(s.mines.state[slot], DORMANT, "dormant for 60 s");
    }
    for _ in 0..180 {
        s.tick();
        if s.mines.state[slot] == FLYING {
            break;
        }
    }
    assert_eq!(s.mines.state[slot], FLYING, "awake, it takes off toward the hostile 500 m off");
    assert_eq!(s.out.launches.len(), 1);
    let (_, _, vel) = s.out.launches[0];
    assert!((f64::from(length(vel)) - 150.0).abs() < 1e-3 && vel.z < 0.0);
}

#[test]
fn a_homing_mine_with_nothing_left_to_chase_stops_and_waits() {
    let mut s = Sim::new(rows_of(&[(1, FOE, v(0.0, 0.0, -500.0), 6.0, LIVE)], None));
    let slot = s.mines.lay(None, GUIDED, FRIEND, Vector3::ZERO, Vector3::ZERO, ARMED, 0.0, &specs()[GUIDED as usize], 0).unwrap();
    s.mines.state[slot] = FLYING;
    s.mines.fixed[slot] = false;
    s.bolts.insert_owned(-1, Vector3::ZERO, v(0.0, 0.0, -150.0), FRIEND, 0, 3, 1.0, 0.0, [1.0; 4], 255, 60.0, 0);
    s.mines.bolt[slot] = -1;
    s.rows.positions[0] = v(0.0, 0.0, -5000.0);
    s.tick();
    assert_eq!(s.out.spends, vec![-1]);
    assert_eq!((s.mines.state[slot], s.mines.fixed[slot]), (ARMED, true));
    // And in range again it is steered, and inside 30 m of the hull it goes off.
    s.rows.positions[0] = v(0.0, 0.0, -500.0);
    s.mines.state[slot] = FLYING;
    s.mines.fixed[slot] = false;
    s.mines.bolt[slot] = -1;
    s.tick();
    assert_eq!(s.out.steers.len(), 1);
    s.bolts.positions[0] = v(0.0, 0.0, -470.0);
    s.tick();
    assert_eq!(s.out.dets, vec![(slot as u32, CAUSE_TRIGGER)]);
}

#[test]
fn a_blast_reaches_the_mines_whose_body_it_touches() {
    let mut s = Sim::new(rows_of(&[], None));
    let (a, b, c) = (s.place(PROX, FRIEND, v(0.0, 0.0, 0.0)), s.place(PROX, FRIEND, v(100.0, 0.0, 0.0)), s.place(PROX, FRIEND, v(125.0, 0.0, 0.0)));
    s.mines.rebuild_grid();
    let mut out = Vec::new();
    in_blast(&s.mines, &specs(), Vector3::ZERO, Vector3::ZERO, 120.0, &mut out);
    assert_eq!(out, vec![a as u32, b as u32], "123 m (radius and body) reaches 100 m but not 125 m: {c}");
    s.mines.retire(b);
    out.clear();
    in_blast(&s.mines, &specs(), Vector3::ZERO, Vector3::ZERO, 120.0, &mut out);
    assert_eq!(out, vec![a as u32], "a spent mine is not reached");
}

#[test]
fn the_radar_shows_a_hostile_mine_only_close_and_its_own_always() {
    let mut s = Sim::new(rows_of(&[], None));
    let (own, far, near) = (s.place(PROX, FRIEND, v(0.0, 0.0, 3000.0)), s.place(PROX, FOE, v(0.0, 0.0, 1500.0)), s.place(PROX, FOE, v(0.0, 0.0, 900.0)));
    let h = hostile();
    let w = World {
        rows: &s.rows,
        bolts: &s.bolts,
        hull_rows: &s.order,
        hostile: &h,
        factions: N,
        origin: Vector3::ZERO,
        frame_velocity: Vector3::ZERO,
        tick: 0,
        now_s: 0.0,
        delta: 0.0,
    };
    let mut out = Vec::new();
    radar(&s.mines, &specs(), &w, Vector3::ZERO, FRIEND, 4000.0, &mut out);
    assert_eq!(out, vec![own as u32, near as u32], "an own mine 3 km off shows, an enemy's 1.5 km off does not ({far})");
}

#[test]
fn the_same_ticks_give_the_same_mines() {
    let build = || {
        let mut s = Sim::new(rows_of(&[(1, FOE, v(0.0, 0.0, 55.0), 6.0, LIVE), (2, FOE, v(300.0, 0.0, 0.0), 6.0, LIVE)], None));
        for k in 0..20 {
            s.place(PROX, FRIEND, v(k as f32 * 15.0, 0.0, 0.0));
        }
        let mut dets = Vec::new();
        for _ in 0..30 {
            s.tick();
            dets.extend(s.out.dets.iter().copied());
        }
        dets
    };
    assert_eq!(build(), build());
}

#[test]
fn a_mine_turns_no_faster_than_its_turn_rate() {
    let from = v(1.0, 0.0, 0.0);
    let to = v(0.0, 1.0, 0.0);
    let t = turn_toward(from, to, 0.1);
    assert!((f64::from(dot(t, from)).acos() - 0.1).abs() < 1e-4, "{t:?}");
    assert_eq!(turn_toward(from, to, 2.0), to, "within reach it points straight at it");
}

// A shot (an owned bolt of `kind` and side `faction`) lying `off` from the flying mine's row, not moving.
fn shot_beside_mine(s: &mut Sim, faction: u32, kind: u8, off: Vector3) -> usize {
    let at = add(s.bolts.positions[0], off);
    let p = s.bolts.insert_owned(-2 - s.bolts.owned as i64, at, Vector3::ZERO, faction, 0, kind, 0.25, 10.0, [1.0; 4], 255, 60.0, 0);
    s.bolts.last_steps[p] = Vector3::ZERO;
    p
}

#[test]
fn a_hostile_shot_that_meets_a_mine_in_flight_takes_one_of_its_hits_and_a_friendly_or_a_beam_does_not() {
    let mut s = Sim::new(rows_of(&[(1, FRIEND, v(0.0, 0.0, 9000.0), 8.0, LIVE)], None));
    let slot = flying_energy(&mut s, v(0.0, 0.0, -3000.0), v(0.0, 0.0, -1000.0));
    s.bolts.set_hits_left(0, 3);
    s.bolts.last_steps[0] = scale(s.bolts.velocities[0], 1.0 / 60.0);
    shot_beside_mine(&mut s, FRIEND, 7, v(1.0, 0.0, 0.0));
    shot_beside_mine(&mut s, FOE, 8, v(1.0, 0.0, 0.0));
    shot_beside_mine(&mut s, FOE, 7, v(40.0, 0.0, 0.0));
    s.tick();
    assert!(s.out.shot_hits.is_empty(), "the mine's own side's bolt, a beam and a bolt 40 m off meet nothing");
    let hit = shot_beside_mine(&mut s, FOE, 7, v(1.0, 0.0, 0.0));
    s.tick();
    assert_eq!(s.out.shot_hits, vec![(hit as u32, slot as u32, 2)], "a hostile bolt takes one of three hits");
    assert!(s.out.downed.is_empty());
}

#[test]
fn three_hostile_shots_shoot_an_energy_mine_down_and_a_fourth_finds_nothing() {
    let mut s = Sim::new(rows_of(&[(1, FRIEND, v(0.0, 0.0, 9000.0), 8.0, LIVE)], None));
    let slot = flying_energy(&mut s, v(0.0, 0.0, -3000.0), v(0.0, 0.0, -1000.0));
    s.bolts.set_hits_left(0, 3);
    s.bolts.last_steps[0] = scale(s.bolts.velocities[0], 1.0 / 60.0);
    let shots: Vec<usize> = (0..4).map(|_| shot_beside_mine(&mut s, FOE, 7, v(1.0, 0.0, 0.0))).collect();
    s.tick();
    let lefts: Vec<u8> = s.out.shot_hits.iter().map(|h| h.2).collect();
    assert_eq!(lefts, vec![2, 1, 0], "the first three bolts, in row order, take its three hits");
    assert!(s.out.shot_hits.iter().all(|h| h.1 == slot as u32 && h.0 != shots[3] as u32), "the fourth is not used");
}
