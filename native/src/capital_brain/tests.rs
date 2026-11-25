// The capital brain (M10-T16, D12.10): its states, its target and aim, its attitude and its stagger, on hand-made rows
// (test builds only, outside the kernel's engine-free guard).
use std::collections::HashMap;

use super::*;
use crate::capital_helm::{Helm, HelmSpec};
use crate::rows::{FLAG_HULL_ACTIVE, FLAG_RIGID, ROLE_SURFACE, Surface};
use crate::surface::from_packed;
use crate::v3::{dot, length, normalized};

const LIVE: u32 = FLAG_RIGID | FLAG_HULL_ACTIVE;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

// One capital row per (body, position, faction); body ids double as marker ids. Each has `hull()` as its surface.
fn rows_of(ships: &[(i64, Vector3, u32)]) -> Rows {
    let mut rows = Rows::default();
    let mut surfaces = HashMap::new();
    for &(body, at, faction) in ships {
        rows.body_ids.push(body);
        rows.ids.push(body);
        rows.faction_ix.push(faction);
        rows.positions.push(at);
        rows.velocities.push(Vector3::ZERO);
        rows.bases.push(Basis::IDENTITY);
        rows.angular.push(Vector3::ZERO);
        rows.radii.push(200.0);
        rows.kinds.push(KIND_CAPITAL);
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
        rows.roles.push(ROLE_SURFACE);
        surfaces.insert(body, Arc::new(hull()));
    }
    rows.node_count = ships.len();
    rows.surfaces = Some(Arc::new(surfaces));
    rows.id_rows = rows.ids.iter().enumerate().map(|(r, &id)| (id, r as u32)).collect();
    rows.id_rows.sort();
    rows
}

// A long box along z (half extents 20 x 10 x 200).
fn hull() -> Surface {
    from_packed(&[0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0, 10.0, 200.0], 0.0)
}

fn mount(at: Vector3, axis: Vector3, half_deg: f32, dps: f64, range_m: f64, kind: u8, role: u8) -> BrainMount {
    BrainMount {
        at,
        axis: normalized(axis),
        cos_half: half_deg.to_radians().cos(),
        dps,
        range_m,
        kind,
        role,
        works: true,
    }
}

// A broadside ship: four turrets on each flank (their cones round +-x), 10 dps each, 6 km.
fn broadside(body: i64) -> CapitalSpec {
    let mut mounts = Vec::new();
    for z in [-150.0, -50.0, 50.0, 150.0] {
        mounts.push(mount(v(21.0, 0.0, z), v(1.0, 0.0, 0.0), 85.0, 10.0, 6000.0, MOUNT_TURRET, ROLE_AC));
        mounts.push(mount(v(-21.0, 0.0, z), v(-1.0, 0.0, 0.0), 85.0, 10.0, 6000.0, MOUNT_TURRET, ROLE_AC));
    }
    spec(body, mounts)
}

// A ship whose main weapons are fixed bow guns, 8 deg gimbals, 7 km, beside a light turret on each flank.
fn bow_guns(body: i64) -> CapitalSpec {
    let mut mounts = vec![
        mount(v(5.0, 0.0, -201.0), v(0.0, 0.0, -1.0), 8.0, 40.0, 7000.0, MOUNT_FIXED, ROLE_AC),
        mount(v(-5.0, 0.0, -201.0), v(0.0, 0.0, -1.0), 8.0, 40.0, 7000.0, MOUNT_FIXED, ROLE_AC),
    ];
    mounts.push(mount(v(21.0, 0.0, 0.0), v(1.0, 0.0, 0.0), 85.0, 5.0, 3000.0, MOUNT_TURRET, ROLE_AF));
    mounts.push(mount(v(-21.0, 0.0, 0.0), v(-1.0, 0.0, 0.0), 85.0, 5.0, 3000.0, MOUNT_TURRET, ROLE_AF));
    spec(body, mounts)
}

fn spec(body: i64, mounts: Vec<BrainMount>) -> CapitalSpec {
    CapitalSpec {
        body,
        helm: HelmSpec::default(),
        hull_max: 30000.0,
        value: 2.0,
        doctrine: Doctrine::default(),
        carrier: false,
        mounts,
        points: vec![
            BrainPoint {
                at: v(0.0, 0.0, 200.0),
                kind: POINT_ENGINE,
                works: true,
            },
            BrainPoint {
                at: v(0.0, 0.0, 0.0),
                kind: POINT_REACTOR,
                works: true,
            },
        ],
    }
}

fn entry(spec: CapitalSpec, ordinal: i64) -> Entry {
    Entry {
        stamp: 1,
        ordinal,
        age: 0,
        spec: Arc::new(spec),
        status: Status {
            engines_live: 1,
            engines_total: 1,
            ..Default::default()
        },
        memory: Memory::default(),
        helm: Helm::default(),
    }
}

// Factions 0 and 1 at war.
fn job(entries: Vec<Entry>) -> CapitalJob {
    CapitalJob {
        entries,
        relations: vec![2, 1, 1, 2],
        stride: 2,
        tuning: Tuning::default(),
        rest: Vector3::ZERO,
        answers: Vec::new(),
        raiders_ix: None,
        think_ns: 0,
    }
}

fn row_of(rows: &Rows) -> impl Fn(i64) -> i64 + '_ {
    move |body| rows.body_ids.iter().position(|&b| b == body).map_or(-1, |r| r as i64)
}

// Thinks the job's capitals on their next beat (an entry with ordinal 0 thinks; one off the beat does not) and returns
// the answers.
fn think(job: &mut CapitalJob, rows: &Rows) -> Vec<Answer> {
    for e in job.entries.iter_mut() {
        e.age += 12;
    }
    think_all(job, rows, row_of(rows), [0.0; 3]);
    job.answers.clone()
}

// The answers' memories back into the entries, as the join does.
fn settle(job: &mut CapitalJob) {
    for a in job.answers.clone() {
        if let Some(e) = job.entries.iter_mut().find(|e| e.spec.body == a.body) {
            e.memory = a.memory.clone();
        }
    }
}

#[test]
fn a_far_hostile_capital_is_approached_bow_on() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(20000.0, 0.0, 0.0), 1)]);
    let mut j = job(vec![entry(broadside(1), 0)]);
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.memory.state, STATE_APPROACH);
    assert_eq!(a.order, 2, "its heavy weapons take the target");
    let (heading, velocity) = a.helm.map(|c| (c.heading, c.velocity)).expect("it steers");
    assert!(dot(heading, v(1.0, 0.0, 0.0)) > 0.99, "bow on toward the target");
    assert!(velocity.x > 30.0, "closing at its approach speed");
}

#[test]
fn in_range_a_turret_ship_turns_broadside() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(0.0, 0.0, -4000.0), 1)]);
    let mut j = job(vec![entry(broadside(1), 0)]);
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.memory.state, STATE_ENGAGE);
    // Its flank (or the quarter beside it, where the same four turrets bear and the turn is shorter) to the target.
    let side = attitude::DIRECTIONS[usize::from(a.memory.attitude)];
    assert!(side.x.abs() > 0.5 && side.y == 0.0, "a flank's attitude (got {})", a.memory.attitude);
    let (heading, _) = a.helm.map(|c| (c.heading, c.velocity)).unwrap();
    assert!(dot(heading, v(0.0, 0.0, -1.0)) < 0.8, "the bow turned off the target: {heading:?}");
    // Already abeam, it holds there.
    let mut j = job(vec![entry(broadside(1), 0)]);
    let abeam = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1)]);
    assert_eq!(think(&mut j, &abeam)[0].memory.attitude, 1, "the target abeam to starboard");
}

#[test]
fn of_a_flank_and_its_mirror_it_takes_the_nearer() {
    let mut j = job(vec![entry(broadside(1), 0)]);
    let port = rows_of(&[(1, Vector3::ZERO, 0), (2, v(-4000.0, 0.0, 0.0), 1)]);
    assert_eq!(think(&mut j, &port)[0].memory.attitude, 2, "abeam to port: no half turn to bring the other flank round");
}

#[test]
fn in_range_a_bow_gun_ship_points_its_bow() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1)]);
    let mut j = job(vec![entry(bow_guns(1), 0)]);
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.memory.state, STATE_ENGAGE);
    assert_eq!(a.memory.attitude, 0, "bow-on");
    let (heading, _) = a.helm.map(|c| (c.heading, c.velocity)).unwrap();
    assert!(dot(heading, v(1.0, 0.0, 0.0)) > 0.99);
}

#[test]
fn engage_holds_seven_tenths_of_the_main_weapons_range() {
    let s = broadside(1);
    assert_eq!(s.main_range_m(), 6000.0);
    let hold = 0.7 * 6000.0;
    let near = rows_of(&[(1, Vector3::ZERO, 0), (2, v(0.0, 0.0, -(hold as f32) + 1500.0), 1)]);
    let a = &think(&mut job(vec![entry(broadside(1), 0)]), &near)[0];
    assert!(a.helm.map(|c| (c.heading, c.velocity)).unwrap().1.z > 0.0, "too close: it opens the range");
    let far = rows_of(&[(1, Vector3::ZERO, 0), (2, v(0.0, 0.0, -(hold as f32) - 500.0), 1)]);
    let a = &think(&mut job(vec![entry(broadside(1), 0)]), &far)[0];
    assert!(a.helm.map(|c| (c.heading, c.velocity)).unwrap().1.z < 0.0, "a little far: it closes");
}

#[test]
fn a_held_attitude_needs_a_clear_gain_to_change() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(0.0, 0.0, -4000.0), 1)]);
    let mut j = job(vec![entry(broadside(1), 0)]);
    think(&mut j, &rows);
    settle(&mut j);
    let first = j.entries[0].memory.attitude;
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.memory.attitude, first, "the same side kept");
}

#[test]
fn friends_neutrals_and_fighters_are_no_targets() {
    let mut rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(3000.0, 0.0, 0.0), 0), (3, v(-3000.0, 0.0, 0.0), 1)]);
    rows.kinds[2] = 0; // a hostile fighter
    rows.roles[2] = 0;
    let a = &think(&mut job(vec![entry(broadside(1), 0)]), &rows)[0];
    assert_eq!(a.order, 0, "no capital target: the guns pick their own (fighters too, Q77)");
    assert_eq!(a.memory.state, STATE_IDLE);
    assert!(a.helm.is_none(), "idle, the helm keeps its course");
}

#[test]
fn the_target_is_threat_times_value_over_time_to_kill() {
    // A near weak cruiser and a far dangerous one of equal worth: the near one dies sooner and wins; a much bigger threat
    // close by wins.
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1), (3, v(-25000.0, 0.0, 0.0), 1)]);
    let mut j = job(vec![entry(broadside(1), 0), entry(broadside(2), 1), entry(bow_guns(3), 2)]);
    j.entries[1].ordinal = 5;
    j.entries[2].ordinal = 5;
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.body, 1);
    assert_eq!(a.order, 2, "the near one");
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1), (3, v(-4000.0, 0.0, 0.0), 1)]);
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.order, 3, "equal ranges: the bigger threat (80 dps against 80, more value per second)");
}

#[test]
fn a_held_target_is_kept_against_a_near_tie() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1), (3, v(-4100.0, 0.0, 0.0), 1)]);
    let mut j = job(vec![entry(broadside(1), 0)]);
    j.entries[0].memory.target = 3;
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.order, 3, "the held target keeps its bonus");
}

#[test]
fn outgunned_it_aims_at_the_mounts_bearing_on_it() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1)]);
    let mut weak = broadside(1);
    for m in weak.mounts.iter_mut().skip(2) {
        m.works = false;
    }
    let mut j = job(vec![entry(weak, 0), entry(broadside(2), 7)]);
    let a = &think(&mut j, &rows)[0];
    let aim = a.order_aim.expect("a subsystem aim");
    assert!(aim.x < -20.0, "a mount on the flank facing it: {aim:?}");
    // Even, it aims at the centre.
    let mut j = job(vec![entry(broadside(1), 0), entry(broadside(2), 7)]);
    assert_eq!(think(&mut j, &rows)[0].order_aim, None);
}

#[test]
fn a_cripple_doctrine_aims_at_a_withdrawing_targets_engines() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1)]);
    let mut own = broadside(1);
    own.doctrine.cripple = true;
    let mut fleeing = entry(broadside(2), 7);
    fleeing.memory.state = STATE_WITHDRAW;
    let mut j = job(vec![entry(own, 0), fleeing]);
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.order_aim, Some(v(0.0, 0.0, 200.0)), "its engine");
}

#[test]
fn it_withdraws_below_a_third_of_its_hull_and_fights_on_without_an_exit() {
    let mut rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1)]);
    rows.hull_fraction[0] = 0.25;
    let mut j = job(vec![entry(broadside(1), 0)]);
    let a = think(&mut j, &rows)[0].clone();
    assert_eq!(a.memory.state, STATE_WITHDRAW);
    assert_ne!(a.events & EVENT_WITHDRAW, 0, "it asks for an exit");
    settle(&mut j);
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.events & EVENT_WITHDRAW, 0, "once");
    // An exit found: it flies for it.
    j.entries[0].status.exit = EXIT_FOUND;
    j.entries[0].status.exit_at = [0.0, 0.0, 9000.0];
    let a = &think(&mut j, &rows)[0];
    assert!(dot(a.helm.map(|c| (c.heading, c.velocity)).unwrap().0, v(0.0, 0.0, 1.0)) > 0.99, "toward its exit");
    // None: it fights on.
    j.entries[0].status.exit = EXIT_NONE;
    assert_eq!(think(&mut j, &rows)[0].memory.state, STATE_ENGAGE);
}

#[test]
fn reactor_and_engines_also_send_it_home() {
    let t = Tuning::default();
    let mut s = Status {
        engines_live: 2,
        engines_total: 2,
        ..Default::default()
    };
    assert!(!withdraw_due(&s, 0.9, &t));
    s.reactor = 0.4;
    assert!(withdraw_due(&s, 0.9, &t), "reactor under half");
    s.reactor = 1.0;
    s.engines_live = 0;
    assert!(withdraw_due(&s, 0.9, &t), "every main engine lost");
}

#[test]
fn on_orders_it_holds_and_still_names_its_target() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(20000.0, 0.0, 0.0), 1)]);
    let mut j = job(vec![entry(broadside(1), 0)]);
    j.entries[0].status.mode = MODE_HELD;
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.memory.state, STATE_HOLD);
    assert!(a.helm.is_none(), "the helm is the caller's");
    assert_eq!(a.order, 2);
}

#[test]
fn a_hulk_thinks_nothing() {
    let mut rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1)]);
    rows.flags[0] |= FLAG_DISABLED;
    let mut j = job(vec![entry(broadside(1), 0)]);
    j.entries[0].memory.target = 2;
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.order, 0);
    assert!(a.helm.is_none());
    assert_ne!(a.events & EVENT_ORDER, 0, "its old order is withdrawn");
}

#[test]
fn an_escort_screens_its_charge() {
    let rows = rows_of(&[(1, v(3000.0, 0.0, 0.0), 0), (2, Vector3::ZERO, 0)]);
    let mut j = job(vec![entry(broadside(1), 0)]);
    j.entries[0].status.charge = 2;
    let a = &think(&mut j, &rows)[0];
    assert_eq!(a.memory.state, STATE_SCREEN);
    assert!(a.helm.map(|c| (c.heading, c.velocity)).unwrap().1.x < 0.0, "out of the band: it closes on its charge");
}

#[test]
fn thinks_are_staggered_at_five_a_second() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 0.0, 0.0), 1)]);
    let mut j = job(vec![entry(broadside(1), 0), entry(broadside(2), 3)]);
    let mut by_tick = Vec::new();
    for tick in 0..24 {
        for e in j.entries.iter_mut() {
            e.age = tick;
        }
        think_all(&mut j, &rows, row_of(&rows), [0.0; 3]);
        by_tick.push(j.answers.iter().map(|a| a.body).collect::<Vec<_>>());
    }
    assert_eq!(by_tick.iter().filter(|b| b.contains(&1)).count(), 2, "every 12 ticks");
    assert_eq!(by_tick[0], vec![1]);
    assert_eq!(by_tick[9], vec![2], "the other on its own beat");
}

#[test]
fn the_same_rows_give_the_same_answers() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(4000.0, 300.0, -800.0), 1), (3, v(-9000.0, 0.0, 0.0), 1)]);
    let mut a = job(vec![entry(broadside(1), 0), entry(bow_guns(2), 0), entry(broadside(3), 0)]);
    let mut b = a.clone();
    assert_eq!(think(&mut a, &rows), think(&mut b, &rows));
}

#[test]
fn bearings_see_the_own_hull_in_the_way() {
    // A turret on the top deck whose cone covers below the horizon: the line straight down passes through its own hull.
    let s = spec(1, vec![mount(v(0.0, 11.0, 0.0), v(0.0, 1.0, 0.0), 100.0, 10.0, 6000.0, MOUNT_TURRET, ROLE_AC)]);
    let bits = attitude::bearings(&s, Some(&hull()))[0];
    assert_ne!(bits & (1 << 4), 0, "straight up bears");
    assert_eq!(bits & (1 << 3), 0, "straight down is outside its cone");
    let low = spec(1, vec![mount(v(0.0, 11.0, -100.0), v(0.0, 1.0, 0.0), 120.0, 10.0, 6000.0, MOUNT_TURRET, ROLE_AC)]);
    let bits = attitude::bearings(&low, Some(&hull()))[0];
    assert_eq!(bits & (1 << 8), 0, "down and ahead: through its own hull");
}

#[test]
fn a_broadside_attitude_also_sets_the_ships_top() {
    let rows = rows_of(&[(1, Vector3::ZERO, 0), (2, v(0.0, 0.0, -4000.0), 1)]);
    let mut j = job(vec![entry(broadside(1), 0)]);
    let c = think(&mut j, &rows)[0].helm.expect("it steers");
    assert!(length(c.up) > 0.9, "a flank's attitude holds the roll too");
    assert!(dot(c.up, c.heading).abs() < 1e-3, "the top square to the bow");
}

#[test]
fn out_of_the_fight_it_takes_up_its_course_again() {
    let mut j = job(vec![entry(broadside(1), 0)]);
    j.entries[0].helm.heading = v(1.0, 0.0, 0.0);
    j.entries[0].helm.velocity = v(5.0, 0.0, 0.0);
    let fight = rows_of(&[(1, Vector3::ZERO, 0), (2, v(0.0, 0.0, -4000.0), 1)]);
    think(&mut j, &fight);
    settle(&mut j);
    assert!(j.entries[0].memory.cruise.is_some(), "it remembered its course");
    let quiet = rows_of(&[(1, Vector3::ZERO, 0)]);
    let a = think(&mut j, &quiet)[0].clone();
    assert_eq!(a.memory.state, STATE_IDLE);
    let c = a.helm.expect("back on its course");
    assert_eq!(c.heading, v(1.0, 0.0, 0.0));
    assert_eq!(c.velocity, v(5.0, 0.0, 0.0));
    assert!(a.memory.cruise.is_none());
}
