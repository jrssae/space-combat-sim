// The capital beams (M10-T12), beside the kernel and outside its engine-free guard (test builds only).
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::Basis;

use super::*;
use crate::rows::{FLAG_DISGUISE_SHIFT, FLAG_RIGID, ROLE_COMBAT, ROLE_SURFACE, Surface};
use crate::surface::from_packed;

const LIVE: u32 = FLAG_RIGID | FLAG_HULL_ACTIVE;
const DT: f64 = 1.0 / 60.0;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

// One row per (body, position, radius, kind, faction, flags); body 7 holds `surface` when one is given.
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
        rows.roles.push(if body == 7 && surface.is_some() {
            ROLE_SURFACE
        } else {
            ROLE_COMBAT
        });
    }
    rows.node_count = bodies.len();
    if let Some(s) = surface {
        let mut map = HashMap::new();
        map.insert(7_i64, Arc::new(s));
        rows.surfaces = Some(Arc::new(map));
    }
    rows
}

// A long box along z (half extents 20 x 10 x 200) and a capsule above it, the second volume.
fn hull() -> Surface {
    let mut p = vec![
        0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0, 10.0, 200.0,
    ];
    p.extend([
        1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 40.0, 150.0, 5.0, 8.0, 0.0,
    ]);
    from_packed(&p, 0.0)
}

fn pulsed() -> BeamSpec {
    BeamSpec {
        kind: PULSED,
        damage: 100.0,
        dps: 0.0,
        on_s: 0.0,
        cycle_s: 8.0,
        charge_s: 0.5,
        range_m: 8000.0,
        turn_rad_s: 4f64.to_radians(),
    }
}

fn sustained() -> BeamSpec {
    BeamSpec {
        kind: SUSTAINED,
        damage: 0.0,
        dps: 40.0,
        on_s: 3.0,
        cycle_s: 12.0,
        charge_s: 1.0,
        range_m: 7000.0,
        turn_rad_s: 3f64.to_radians(),
    }
}

// Factions 0 and 1 hostile to each other, 2 friendly to everyone.
fn table() -> Vec<bool> {
    vec![false, true, false, true, false, false, false, false, false]
}

struct Run {
    rows: Rows,
    beams: Vec<Beam>,
    owners: Vec<Owner>,
    owner_of: Vec<u32>,
    hostile: Vec<bool>,
}

impl Run {
    // A shooter at the origin (body 1, faction 0, a capital) with one emitter looking along -z, 45 deg each way.
    fn new(rows: Rows, spec: BeamSpec) -> Run {
        let mut beam = Beam::new(
            1,
            v(0.0, 0.0, -10.0),
            v(0.0, 0.0, -1.0),
            45f64.to_radians(),
            spec,
        );
        beam.pick_wait = 0;
        Run {
            rows,
            beams: vec![beam],
            owners: vec![Owner {
                body: 1,
                bodies: vec![1],
                order: 0,
            }],
            owner_of: vec![0],
            hostile: table(),
        }
    }

    // `ticks` steps; every hit and line, in order.
    fn steps(&mut self, ticks: usize) -> (Vec<BeamHit>, Vec<BeamDraw>) {
        let order: Vec<u32> = (0..self.rows.positions.len() as u32).collect();
        let owner_rows: Vec<i32> = self
            .owners
            .iter()
            .map(|o| {
                self.rows
                    .body_ids
                    .iter()
                    .position(|&b| b == o.body)
                    .map_or(-1, |r| r as i32)
            })
            .collect();
        let rows = &self.rows;
        let world = BeamWorld {
            rows,
            hull_rows: &order,
            owner_rows: &owner_rows,
            hostile: &self.hostile,
            factions: 3,
            row_of: |id: i64| rows.body_ids.iter().position(|&b| b == id),
        };
        let (mut hits, mut draws) = (Vec::new(), Vec::new());
        for _ in 0..ticks {
            step(
                &mut self.beams,
                &self.owners,
                &self.owner_of,
                &world,
                DT,
                &mut hits,
                &mut draws,
            );
        }
        (hits, draws)
    }
}

const SHOOTER: (i64, Vector3, f64, u8, u32, u32) = (1, Vector3::ZERO, 50.0, 1, 0, LIVE);

#[test]
fn a_pulse_charges_then_lands_once_on_a_hull_ahead_and_cools_for_its_cycle() {
    let rows = rows_of(
        &[SHOOTER, (7, v(0.0, 0.0, -3000.0), 210.0, 1, 1, LIVE)],
        Some(hull()),
    );
    let mut run = Run::new(rows, pulsed());
    let (hits, draws) = run.steps(60);
    assert_eq!(hits.len(), 1, "one pulse in a second: {hits:?}");
    assert_eq!(hits[0].row, 1);
    assert_eq!(hits[0].damage, 100.0);
    assert_eq!(hits[0].volume, 0, "the box, the volume the line enters");
    assert!(
        (hits[0].point.z - (-2800.0)).abs() < 0.5,
        "on the box's near face: {:?}",
        hits[0].point
    );
    assert!(
        draws.iter().any(|d| d.phase == CHARGING),
        "it charges first"
    );
    assert_eq!(run.beams[0].phase, COOLING);
    let (more, _) = run.steps(60 * 7);
    assert!(more.is_empty(), "nothing more before its 8 s cycle");
    let (again, _) = run.steps(60 * 2);
    assert_eq!(
        again.len(),
        1,
        "the next pulse after the cycle and a charge"
    );
}

#[test]
fn a_sustained_beam_lands_every_tick_while_on_for_its_dps() {
    let rows = rows_of(
        &[SHOOTER, (2, v(0.0, 0.0, -2000.0), 200.0, 1, 1, LIVE)],
        None,
    );
    let mut run = Run::new(rows, sustained());
    let (hits, draws) = run.steps(60 * 5);
    assert_eq!(hits.len(), 180, "3 s on at 60 ticks a second");
    let total: f64 = hits.iter().map(|h| h.damage).sum();
    assert!((total - 120.0).abs() < 1e-6, "40 dps for 3 s: {total}");
    assert!(draws.iter().filter(|d| d.phase == FIRING).count() == 180);
    assert_eq!(run.beams[0].phase, COOLING);
    assert!(
        (run.beams[0].timer - (9.0 - 1.0)).abs() < 0.05,
        "its cycle less its time on, counted from the beam's end: {}",
        run.beams[0].timer
    );
}

#[test]
fn the_first_hull_on_the_line_takes_the_beam_friend_or_foe() {
    let rows = rows_of(
        &[
            SHOOTER,
            (2, v(0.0, 0.0, -4000.0), 200.0, 1, 1, LIVE),
            (3, v(0.0, 2.0, -1000.0), 10.0, 0, 2, LIVE),
        ],
        None,
    );
    let mut run = Run::new(rows, pulsed());
    let (hits, _) = run.steps(60);
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].row, 2, "the friendly fighter in the way stops it");
}

#[test]
fn the_arc_limits_what_it_takes_and_it_turns_at_its_rate() {
    // Abeam (90 deg off a 45 deg arc): never taken.
    let rows = rows_of(
        &[SHOOTER, (2, v(3000.0, 0.0, 0.0), 200.0, 1, 1, LIVE)],
        None,
    );
    let mut run = Run::new(rows, pulsed());
    let (hits, _) = run.steps(600);
    assert!(hits.is_empty(), "outside its arc");
    assert_eq!(run.beams[0].target, 0);
    // 30 deg off the bow, a small hull: it turns 4 deg/s, so it bears after about 7 s and not before 6.
    let at = v(
        1000.0 * 30f32.to_radians().sin(),
        0.0,
        -1000.0 * 30f32.to_radians().cos(),
    );
    let rows = rows_of(&[SHOOTER, (2, at, 5.0, 1, 1, LIVE)], None);
    let mut run = Run::new(rows, pulsed());
    let (early, _) = run.steps(60 * 6);
    assert!(early.is_empty(), "still turning");
    let (late, _) = run.steps(60 * 3);
    assert_eq!(late.len(), 1, "on target after turning");
}

#[test]
fn a_mount_that_stops_working_stops_its_beam_and_holds_fire() {
    let rows = rows_of(
        &[SHOOTER, (2, v(0.0, 0.0, -2000.0), 200.0, 1, 1, LIVE)],
        None,
    );
    let mut run = Run::new(rows, sustained());
    let (on, _) = run.steps(90);
    assert!(!on.is_empty());
    run.beams[0].works = false;
    let (off, draws) = run.steps(60 * 30);
    assert!(
        off.is_empty() && draws.is_empty(),
        "a lost mount draws and lands nothing"
    );
    assert_eq!(run.beams[0].phase, COOLING);
    run.beams[0].works = true;
    let (back, _) = run.steps(60 * 15);
    assert!(!back.is_empty(), "whole again, it fires after its cycle");
}

#[test]
fn a_half_rate_doubles_the_cooldown() {
    let rows = rows_of(
        &[SHOOTER, (2, v(0.0, 0.0, -2000.0), 200.0, 1, 1, LIVE)],
        None,
    );
    let mut run = Run::new(rows, pulsed());
    run.beams[0].rate = 0.5;
    let (first, _) = run.steps(60);
    assert_eq!(first.len(), 1);
    let (none, _) = run.steps(60 * 15);
    assert!(none.is_empty(), "16 s cooldown at half rate");
    let (next, _) = run.steps(60 * 2);
    assert_eq!(next.len(), 1);
}

#[test]
fn it_picks_by_what_its_side_perceives_so_a_disguised_enemy_is_left_alone() {
    // Body 2 is faction 1 (hostile) broadcasting faction 2 (friendly): left alone until it shows its colours.
    let disguised = LIVE | ((2 + 1) << FLAG_DISGUISE_SHIFT);
    let rows = rows_of(
        &[SHOOTER, (2, v(0.0, 0.0, -2000.0), 200.0, 1, 1, disguised)],
        None,
    );
    let mut run = Run::new(rows, pulsed());
    let (hits, _) = run.steps(120);
    assert!(hits.is_empty(), "it takes the disguised hull for a friend");
    run.rows.flags[1] = LIVE;
    let (hits, _) = run.steps(120);
    assert_eq!(hits.len(), 1, "revealed, it is beamed");
}

#[test]
fn capitals_come_before_fighters_and_an_order_before_both() {
    let rows = rows_of(
        &[
            SHOOTER,
            (2, v(0.0, 0.0, -500.0), 8.0, 0, 1, LIVE),
            (3, v(300.0, 0.0, -3000.0), 300.0, 1, 1, LIVE),
            (4, v(-300.0, 0.0, -3000.0), 300.0, 1, 1, LIVE),
        ],
        None,
    );
    let mut run = Run::new(rows, pulsed());
    run.steps(1);
    assert_eq!(
        run.beams[0].target, 3,
        "the nearer capital, not the fighter (ties to the earlier row)"
    );
    run.owners[0].order = 4;
    run.beams[0].target = 0;
    run.steps(1);
    assert_eq!(run.beams[0].target, 4, "the brain's order");
}

#[test]
fn a_hull_only_piece_stops_a_line_but_is_never_taken_as_a_target() {
    let mut rows = rows_of(
        &[
            SHOOTER,
            (2, v(0.0, 0.0, -1500.0), 100.0, 0, 1, LIVE),
            (3, v(0.0, 0.0, -3000.0), 300.0, 1, 1, LIVE),
        ],
        None,
    );
    rows.ids[1] = 2; // no marker: a capital's rotating section
    let mut run = Run::new(rows, pulsed());
    let (hits, _) = run.steps(60);
    assert_eq!(run.beams[0].target, 3, "the marked capital is the target");
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].row, 1, "the piece in the way stops the line");
}

#[test]
fn its_own_hull_never_stops_its_beam() {
    let rows = rows_of(
        &[
            (7, Vector3::ZERO, 210.0, 1, 0, LIVE),
            (2, v(0.0, 0.0, -3000.0), 200.0, 1, 1, LIVE),
        ],
        Some(hull()),
    );
    let mut run = Run::new(rows, pulsed());
    run.beams[0].owner = 7;
    run.owners[0].body = 7;
    run.owners[0].bodies = vec![7];
    let (hits, _) = run.steps(60);
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].row, 1, "it passes through its own volumes");
}

#[test]
fn a_ship_out_of_the_rows_holds_its_beams() {
    let rows = rows_of(&[(2, v(0.0, 0.0, -2000.0), 200.0, 1, 1, LIVE)], None);
    let mut run = Run::new(rows, pulsed());
    let (hits, draws) = run.steps(120);
    assert!(hits.is_empty() && draws.is_empty());
    assert_eq!(run.beams[0].phase, READY);
}

#[test]
fn turned_moves_at_most_its_angle_and_lands_on_the_goal() {
    let a = v(0.0, 0.0, -1.0);
    let b = v(1.0, 0.0, 0.0);
    let t = turned(a, b, 0.1);
    assert!((f64::from(dot(t, a)).acos() - 0.1).abs() < 1e-5);
    assert_eq!(turned(a, b, 2.0), b);
    let back = turned(a, v(0.0, 0.0, 1.0), 0.2);
    assert!(
        (f64::from(dot(back, a)).acos() - 0.2).abs() < 1e-4,
        "opposite turns too"
    );
}

#[test]
fn the_same_rows_give_the_same_beams_every_run() {
    let make = || {
        let rows = rows_of(
            &[
                SHOOTER,
                (2, v(100.0, 0.0, -2000.0), 200.0, 1, 1, LIVE),
                (3, v(-40.0, 5.0, -900.0), 9.0, 0, 1, LIVE),
            ],
            None,
        );
        let mut run = Run::new(rows, sustained());
        run.steps(60 * 20)
    };
    assert_eq!(make(), make());
}
