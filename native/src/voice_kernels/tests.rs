// The engine voices' ship query (M5-T28), beside the kernel and outside its engine-free guard (test builds only).
use godot::builtin::Basis;

use super::*;
use crate::rows::FLAG_HULL_ACTIVE;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

// One node row per (body, position, flags, kind).
fn rows_of(bodies: &[(i64, Vector3, u32, u8)]) -> Rows {
    let mut rows = Rows::default();
    for &(body, at, flags, kind) in bodies {
        rows.body_ids.push(body);
        rows.ids.push(body);
        rows.faction_ix.push(0);
        rows.positions.push(at);
        rows.velocities.push(Vector3::ZERO);
        rows.bases.push(Basis::IDENTITY);
        rows.angular.push(Vector3::ZERO);
        rows.radii.push(10.0);
        rows.kinds.push(kind);
        rows.flags.push(flags);
        rows.hull_ids.push(body);
        rows.handles.push(body);
        rows.rigid.push(flags & FLAG_RIGID != 0);
        rows.is_static.push(false);
        rows.is_mine.push(false);
        rows.hull_fraction.push(1.0);
        rows.target_ids.push(-1);
        rows.reach.push(0.0);
        rows.name_ids.push(0);
        rows.roles.push(0);
    }
    rows.node_count = bodies.len();
    rows
}

const LIVE: u32 = FLAG_RIGID | FLAG_HULL_ACTIVE;

fn near(rows: &Rows, radius: f64) -> Vec<(f32, u32)> {
    let mut out = Vec::new();
    ships_near(rows, Vector3::ZERO, radius, &mut out);
    out
}

#[test]
fn ships_in_range_come_nearest_first() {
    let rows = rows_of(&[
        (1, v(0.0, 0.0, 900.0), LIVE, 0),
        (2, v(0.0, 0.0, 100.0), LIVE, 0),
        (3, v(0.0, 400.0, 0.0), LIVE, 0),
        (4, v(0.0, 0.0, 1400.0), LIVE, 0),
    ]);
    let rows_in_order: Vec<u32> = near(&rows, 1500.0).iter().map(|e| e.1).collect();
    assert_eq!(rows_in_order, vec![1, 2, 0, 3]);
}

#[test]
fn the_squared_distance_comes_with_the_row() {
    let rows = rows_of(&[(1, v(3.0, 4.0, 0.0), LIVE, 0)]);
    assert_eq!(near(&rows, 10.0), vec![(25.0, 0)]);
}

#[test]
fn a_ship_just_beyond_the_range_is_left_out_and_one_on_it_is_in() {
    let rows = rows_of(&[(1, v(0.0, 0.0, 1500.0), LIVE, 0), (2, v(0.0, 0.0, 1500.5), LIVE, 0)]);
    let found = near(&rows, 1500.0);
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].1, 0);
}

#[test]
fn tier_rows_statics_and_other_kinds_are_never_listed() {
    let mut rows = rows_of(&[
        (1, v(0.0, 0.0, 10.0), LIVE | FLAG_TIER, 0),
        (2, v(0.0, 0.0, 20.0), LIVE, 1),
        (3, v(0.0, 0.0, 30.0), FLAG_HULL_ACTIVE, 0),
        (4, v(0.0, 0.0, 40.0), LIVE, 0),
        (5, v(0.0, 0.0, 50.0), LIVE, 0),
    ]);
    rows.is_static[4] = true;
    let found = near(&rows, 1500.0);
    assert_eq!(found.iter().map(|e| e.1).collect::<Vec<_>>(), vec![3], "only the live rigid ship with a node");
}

#[test]
fn rows_past_the_node_rows_are_not_looked_at() {
    let mut rows = rows_of(&[(1, v(0.0, 0.0, 10.0), LIVE, 0), (2, v(0.0, 0.0, 20.0), LIVE, 0)]);
    rows.node_count = 1; // the second is a late or static row
    assert_eq!(near(&rows, 1500.0).len(), 1);
}

#[test]
fn ties_keep_row_order_and_the_buffer_is_cleared() {
    let rows = rows_of(&[(1, v(0.0, 0.0, 50.0), LIVE, 0), (2, v(0.0, 50.0, 0.0), LIVE, 0), (3, v(50.0, 0.0, 0.0), LIVE, 0)]);
    let mut out = vec![(1.0, 99)];
    ships_near(&rows, Vector3::ZERO, 100.0, &mut out);
    assert_eq!(out.iter().map(|e| e.1).collect::<Vec<_>>(), vec![0, 1, 2]);
}

#[test]
fn what_the_query_hands_back_follows_the_ships_in_range_not_the_rows() {
    // 300 ships far away and three near: the answer is the three. (The scan of the rows is the core's, in Rust.)
    let mut bodies = Vec::new();
    for i in 0..300 {
        bodies.push((i as i64 + 10, v(50_000.0 + i as f32, 0.0, 0.0), LIVE, 0u8));
    }
    for i in 0..3 {
        bodies.push((i as i64 + 1, v(0.0, 0.0, 100.0 * (i as f32 + 1.0)), LIVE, 0u8));
    }
    let rows = rows_of(&bodies);
    let found = near(&rows, 1500.0);
    assert_eq!(found.len(), 3);
    assert_eq!(found.iter().map(|e| rows.body_ids[e.1 as usize]).collect::<Vec<_>>(), vec![1, 2, 3]);
}
