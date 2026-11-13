// The civilian flight's unit tests (M5-T16), beside the kernels and outside their engine-free guard (test builds only):
// the flee rules, the role column, and what the role changes in avoidance, the tier's walks and the turrets' pick.
use godot::builtin::Basis;

use super::*;
use crate::kernels::pilot;
use crate::rows::{FLAG_HULL_ACTIVE, FLAG_RIGID, ROLE_CIVILIAN, ROLE_COMBAT};
use crate::tier::{self, TierRows};
use crate::turret_kernels::{self, Memory, PICK_REACH, PickMount, REL_FRIENDLY, REL_HOSTILE, REL_NEUTRAL};

const EA: u32 = 0;
const RAIDERS: u32 = 1;
const NARN: u32 = 2;

// One row per (body, faction, role, radius, position, velocity): live rigid ships.
fn rows_of(bodies: &[(i64, u32, u8, f64, Vector3, Vector3)]) -> Rows {
    let mut rows = Rows::default();
    for &(body, faction, role, radius, at, velocity) in bodies {
        rows.body_ids.push(body);
        rows.ids.push(body);
        rows.faction_ix.push(faction);
        rows.positions.push(at);
        rows.velocities.push(velocity);
        rows.bases.push(Basis::IDENTITY);
        rows.angular.push(Vector3::ZERO);
        rows.radii.push(radius);
        rows.kinds.push(0);
        rows.flags.push(FLAG_RIGID | FLAG_HULL_ACTIVE);
        rows.hull_ids.push(body);
        rows.handles.push(body);
        rows.rigid.push(true);
        rows.is_static.push(false);
        rows.is_mine.push(false);
        rows.hull_fraction.push(1.0);
        rows.target_ids.push(-1);
        rows.reach.push(0.0);
        rows.name_ids.push(0);
        rows.roles.push(role);
    }
    rows.node_count = bodies.len();
    rows.index_ids();
    rows
}

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

fn view<'a>(rows: &'a Rows, contacts: &'a [i32], fleeing: &'a [bool]) -> View<'a> {
    View {
        rows,
        contacts,
        own_row: 0,
        radius: 80.0,
        speed_mps: 130.0,
        fleeing,
    }
}

const STILL: Vector3 = Vector3::ZERO;

#[test]
fn a_row_without_the_column_is_a_combat_row() {
    let mut rows = rows_of(&[(1, EA, ROLE_CIVILIAN, 80.0, STILL, STILL)]);
    assert!(rows.is_civilian(0));
    rows.roles.clear();
    assert_eq!(rows.role(0), ROLE_COMBAT, "hand-made rows with no roles are combat rows");
    rows.clear();
    assert!(rows.roles.is_empty(), "clear empties the column");
}

#[test]
fn the_nearest_kin_is_of_the_own_people_of_any_kind() {
    // A freighter, a Narn transport closer than the Starfury, the Starfury, a farther Saturn.
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 80.0, STILL, STILL),
        (2, NARN, ROLE_CIVILIAN, 35.0, v(300.0, 0.0, 0.0), STILL),
        (3, EA, ROLE_COMBAT, 12.0, v(800.0, 0.0, 0.0), STILL),
        (4, EA, ROLE_CIVILIAN, 80.0, v(0.0, 0.0, 2500.0), STILL),
        (5, RAIDERS, ROLE_COMBAT, 10.0, v(0.0, 0.0, -1500.0), STILL),
    ]);
    let contacts = [1, 2, 3, 4];
    assert_eq!(nearest_kin(&view(&rows, &contacts, &[])), 2, "the Starfury, not the nearer Narn ship");
    assert_eq!(nearest_kin(&view(&rows, &[1, 4], &[])), -1, "only what the contacts list holds counts");
}

#[test]
fn a_freighter_shelters_on_the_far_side_of_a_warship_of_its_people() {
    let threat = v(0.0, 0.0, -1500.0);
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 80.0, STILL, STILL),
        (2, NARN, ROLE_CIVILIAN, 35.0, v(300.0, 0.0, 0.0), STILL),
        (3, EA, ROLE_COMBAT, 12.0, v(800.0, 0.0, 0.0), STILL),
        (5, RAIDERS, ROLE_COMBAT, 10.0, threat, STILL),
    ]);
    let contacts = [1, 2, 3];
    let away = v(0.0, 0.0, 1.0);
    let flight = flee_from(&view(&rows, &contacts, &[]), away, threat).expect("a kin to run to");
    assert_eq!(flight.goal, 2);
    assert!(flight.shelter, "a warship is a shelter");
    let point = shelter_point(rows.positions[2], threat, standoff_m(80.0, 12.0));
    let from_threat = normalized(sub(rows.positions[2], threat));
    assert!(dot(sub(point, rows.positions[2]), from_threat) > 0.0, "the point lies beyond the warship from the threat");
    assert!((f64::from(length(sub(point, rows.positions[2]))) - 240.0).abs() < 0.01, "three of the freighter's radii");
    let dir = normalized(flight.velocity);
    assert!(dot(dir, normalized(point)) > 0.99, "it heads for that point: {dir:?}");
    let pace = minf(130.0, f64::from(length(point)) / ARRIVE_S);
    assert!((f64::from(length(flight.velocity)) - pace).abs() < 0.01, "slowing into it over ARRIVE_S, at most the run's speed");
}

#[test]
fn at_the_shelter_it_holds_with_the_warship() {
    let threat = v(0.0, 0.0, -1500.0);
    let warship_v = v(20.0, 0.0, 0.0);
    let warship = v(0.0, 0.0, -300.0);
    let point = shelter_point(warship, threat, standoff_m(80.0, 12.0));
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 80.0, point, STILL),
        (3, EA, ROLE_COMBAT, 12.0, warship, warship_v),
    ]);
    let flight = flee_from(&view(&rows, &[1], &[]), v(0.0, 0.0, 1.0), threat).unwrap();
    assert!(f64::from(length(sub(flight.velocity, warship_v))) < 0.01, "it matches the warship there");
}

#[test]
fn a_freighter_runs_to_a_freighter_of_its_people_and_then_on_together() {
    let threat = v(0.0, 0.0, -1500.0);
    let away = v(0.0, 0.0, 1.0);
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 80.0, STILL, STILL),
        (2, EA, ROLE_CIVILIAN, 80.0, v(1200.0, 0.0, 0.0), STILL),
    ]);
    let flight = flee_from(&view(&rows, &[1], &[]), away, threat).unwrap();
    assert_eq!(flight.goal, 1);
    assert!(!flight.shelter);
    assert!(dot(normalized(flight.velocity), v(1.0, 0.0, 0.0)) > 0.99, "toward it");
    // Toward a kin on the threat's side it swings away from the threat.
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 80.0, STILL, STILL),
        (2, EA, ROLE_CIVILIAN, 80.0, v(1000.0, 0.0, -1000.0), STILL),
    ]);
    let flight = flee_from(&view(&rows, &[1], &[]), away, threat).unwrap();
    assert!(dot(flight.velocity, away) >= 0.0, "not into the threat: {:?}", flight.velocity);
    // Together: straight away.
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 80.0, STILL, STILL),
        (2, EA, ROLE_CIVILIAN, 80.0, v(250.0, 0.0, 0.0), STILL),
    ]);
    let flight = flee_from(&view(&rows, &[1], &[]), away, threat).unwrap();
    assert!(f64::from(length(sub(flight.velocity, scale(away, 130.0)))) < 0.01, "on away together");
}

#[test]
fn with_no_kin_and_no_group_the_plain_retreat_stands() {
    let threat = v(0.0, 0.0, -1500.0);
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 80.0, STILL, STILL),
        (2, NARN, ROLE_CIVILIAN, 35.0, v(300.0, 0.0, 0.0), STILL),
        (5, RAIDERS, ROLE_COMBAT, 10.0, threat, STILL),
    ]);
    assert!(flee_from(&view(&rows, &[1, 2], &[]), v(0.0, 0.0, 1.0), threat).is_none());
}

#[test]
fn panic_reaches_kin_within_about_radar_range_only() {
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 80.0, STILL, STILL),
        (2, EA, ROLE_CIVILIAN, 80.0, v(4500.0, 0.0, 0.0), v(0.0, 0.0, 130.0)),
        (3, EA, ROLE_CIVILIAN, 80.0, v(0.0, 5600.0, 0.0), STILL),
        (4, NARN, ROLE_CIVILIAN, 35.0, v(200.0, 0.0, 0.0), STILL),
        (5, EA, ROLE_COMBAT, 12.0, v(100.0, 0.0, 0.0), STILL),
    ]);
    let contacts = [1, 2, 3, 4];
    let none = [false; 5];
    assert_eq!(nearest_alarm(&view(&rows, &contacts, &[]), &none), -1, "no alarm, no panic");
    let far = [false, false, true, false, false];
    assert_eq!(nearest_alarm(&view(&rows, &contacts, &[]), &far), -1, "5.6 km is beyond the alarm");
    let near = [false, true, true, true, true];
    assert_eq!(nearest_alarm(&view(&rows, &contacts, &[]), &near), 1, "4.5 km is within; another people's or a warship's not");
    let flight = flee_alarm(&view(&rows, &contacts, &[]), 1);
    assert!(dot(normalized(flight.velocity), v(0.0, 0.0, 1.0)) > 0.99, "it runs with the alarmed ship");
    assert_eq!(PANIC_RANGE_M, 5000.0);
}

#[test]
fn fleeing_civilians_of_one_people_close_up() {
    let threat = v(0.0, 0.0, -1500.0);
    let away = v(0.0, 0.0, 1.0);
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 80.0, STILL, STILL),
        (2, NARN, ROLE_CIVILIAN, 35.0, v(-900.0, 0.0, 0.0), STILL),
        (3, NARN, ROLE_CIVILIAN, 35.0, v(-1500.0, 0.0, 0.0), STILL),
    ]);
    // Seen from the first Narn ship (row 1): its kin, row 2, flees 600 m off.
    let mut seen = view(&rows, &[0, 2], &[]);
    seen.own_row = 1;
    let fleeing = [true, false, true];
    seen.fleeing = &fleeing;
    let (centre, _, n) = fleeing_group(&seen);
    assert_eq!(n, 1, "only its own people's fleeing civilians");
    assert_eq!(centre, rows.positions[2]);
    let flight = flee_from(&seen, away, threat).unwrap();
    assert!(flight.velocity.x < 0.0, "it closes on its group: {:?}", flight.velocity);
    // Within the group's gap there is no pull.
    let (pulled, grouped) = close_up(&seen, scale(away, 130.0));
    assert!(grouped);
    assert!(pulled.x < 0.0);
    let rows = rows_of(&[
        (1, NARN, ROLE_CIVILIAN, 35.0, STILL, STILL),
        (2, NARN, ROLE_CIVILIAN, 35.0, v(-200.0, 0.0, 0.0), STILL),
    ]);
    let fleeing = [false, true];
    let mut close = view(&rows, &[1], &fleeing);
    close.radius = 35.0;
    let (pulled, grouped) = close_up(&close, scale(away, 130.0));
    assert!(grouped);
    assert_eq!(pulled, scale(away, 130.0), "already together");
}

#[test]
fn avoidance_sees_a_big_civilian_hull_early() {
    // A fighter at 150 m/s on a course that passes 40 m from a 130 m freighter's centre, 9 s out: past the ship-sized
    // horizon, inside the one a sideways burn needs to clear the hull.
    let freighter = v(0.0, 40.0, -1350.0);
    let ship = pilot::Ship {
        position: STILL,
        velocity: v(0.0, 0.0, -150.0),
        radius: 8.0,
        a_retro: 40.0,
        rate_max_x: 1.0,
        rate_max_y: 1.0,
        a_rcs_x: 2.0,
        a_rcs_y: 2.0,
        tie_hash: 7,
    };
    let wish = v(0.0, 0.0, -150.0);
    for (role, dodges) in [(ROLE_COMBAT, false), (ROLE_CIVILIAN, true)] {
        let rows = rows_of(&[(9, EA, role, 130.0, freighter, STILL)]);
        let avoided = pilot::avoid(&rows, &ship, &[0], &[], 0, wish);
        assert_eq!(avoided.v_des != wish, dodges, "role {role}: {:?}", avoided.v_des);
    }
}

#[test]
fn the_tier_measures_a_civilian_hull_from_its_skin() {
    let rows = rows_of(&[
        (1, EA, ROLE_COMBAT, 130.0, v(10_050.0, 0.0, 0.0), STILL),
        (2, EA, ROLE_CIVILIAN, 130.0, v(10_050.0, 0.0, 0.0), STILL),
    ]);
    let mut out = Vec::new();
    tier::far_bodies(&rows, STILL, 0, 10_000.0, 8, &mut out);
    assert_eq!(out, vec![1], "the freighter's near end is still inside");
    let mut t = TierRows::default();
    t.add(0, 3, 3, -1, 0, v(10_100.0, 0.0, 0.0), STILL, Basis::IDENTITY, STILL, 1);
    t.add(0, 4, 4, -2, 0, v(10_100.0, 0.0, 0.0), STILL, Basis::IDENTITY, STILL, 2);
    t.radii[0] = 130.0;
    t.radii[1] = 130.0;
    t.roles[1] = ROLE_CIVILIAN;
    tier::near_rows(&t, STILL, 10_000.0, 8, &mut out);
    assert_eq!(out, vec![4], "the freighter is promoted when its skin comes in");
    let mut appended = Rows::default();
    t.append_to(&mut appended);
    assert_eq!(appended.roles, vec![ROLE_COMBAT, ROLE_CIVILIAN], "the tier keeps the role in the scan");
    t.remove(3);
    assert_eq!(t.roles, vec![ROLE_CIVILIAN], "and in step when a row leaves");
}

#[test]
fn turrets_cover_a_civilian_hull_within_two_km_of_skin() {
    // Two 130 m freighters 2.15 km apart (1.89 km of space between them) and the raider shooting the second.
    let rows = rows_of(&[
        (1, EA, ROLE_CIVILIAN, 130.0, STILL, STILL),
        (2, NARN, ROLE_CIVILIAN, 130.0, v(2150.0, 0.0, 0.0), STILL),
        (3, RAIDERS, ROLE_COMBAT, 10.0, v(700.0, 300.0, 0.0), STILL),
    ]);
    let find = |b: i64| rows.body_ids.iter().position(|&x| x == b).map_or(-1, |r| r as i64);
    let t = vec![
        REL_FRIENDLY, REL_HOSTILE, REL_NEUTRAL, //
        REL_HOSTILE, REL_FRIENDLY, REL_HOSTILE, //
        REL_NEUTRAL, REL_HOSTILE, REL_FRIENDLY,
    ];
    let mount = PickMount {
        slot: 0,
        stamp: 1,
        body: 1,
        faction_ix: EA,
        local: v(0.0, 20.0, 0.0),
        up: v(0.0, 1.0, 0.0),
        min_elevation: (-10_f64).to_radians(),
        reach_m: 1500.0 * PICK_REACH,
        kind: 0,
    };
    let mut memory = Memory::default();
    memory.note(2, 3, 0.0, false);
    assert_eq!(turret_kernels::pick(&rows, &find, &mount, &memory, &t, 3, 1.0, &[]), 3,
        "the role alone makes it a civilian, measured between skins");
    let mut combat = rows.clone();
    combat.roles = vec![ROLE_COMBAT; 3];
    assert_eq!(turret_kernels::pick(&combat, &find, &mount, &memory, &t, 3, 1.0, &[]), 0, "a neutral warship 2.15 km off is not");
}
