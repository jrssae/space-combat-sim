// The blast model's reach (M10-T09), beside the kernel and outside its engine-free guard (test builds only).
use std::collections::HashMap;
use std::sync::Arc;

use godot::builtin::Basis;

use super::*;
use crate::rows::{FLAG_RIGID, ROLE_COMBAT, ROLE_SURFACE, Surface};
use crate::surface::from_packed;

const LIVE: u32 = FLAG_RIGID | FLAG_HULL_ACTIVE;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

// One row per (body, position, radius, flags); body 7 holds `surface` when one is given.
fn rows_of(bodies: &[(i64, Vector3, f64, u32)], surface: Option<Surface>) -> Rows {
    let mut rows = Rows::default();
    for &(body, at, radius, flags) in bodies {
        rows.body_ids.push(body);
        rows.ids.push(body);
        rows.faction_ix.push(0);
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

// A long box along z (half extents 20 x 10 x 200) and a capsule above it, the second volume.
fn hull() -> Surface {
    let mut p = vec![
        0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 20.0, 10.0, 200.0,
    ];
    p.extend([1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 40.0, 150.0, 5.0, 8.0, 0.0]);
    from_packed(&p, 0.0)
}

fn reached(rows: &Rows, centre: Vector3, radius: f64) -> Vec<Reached> {
    let order: Vec<u32> = (0..rows.positions.len() as u32).collect();
    let mut out = Vec::new();
    reach(rows, &order, centre, radius, &mut out);
    out
}

#[test]
fn a_fighter_is_reached_through_its_sphere_with_the_point_facing_the_blast() {
    let rows = rows_of(
        &[
            (1, v(60.0, 0.0, 0.0), 10.0, LIVE),
            (2, v(0.0, 0.0, 115.0), 10.0, LIVE),
            (3, v(0.0, 0.0, 105.0), 10.0, LIVE),
        ],
        None,
    );
    let got = reached(&rows, Vector3::ZERO, 100.0);
    assert_eq!(got.len(), 2, "115 m away with a 10 m sphere is out; 105 m is in: {got:?}");
    assert_eq!(got[0].row, 0);
    assert!((got[0].distance - 50.0).abs() < 1e-9);
    assert!((got[0].point.x - 50.0).abs() < 1e-4 && got[0].point.y == 0.0);
    assert_eq!(got[0].volume, -1);
    assert_eq!(got[1].row, 2);
    assert!((got[1].distance - 95.0).abs() < 1e-9);
}

#[test]
fn a_blast_inside_a_sphere_is_at_distance_zero() {
    let rows = rows_of(&[(1, v(3.0, 0.0, 0.0), 10.0, LIVE)], None);
    let got = reached(&rows, Vector3::ZERO, 20.0);
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].distance, 0.0);
    assert_eq!(got[0].point, Vector3::ZERO);
}

#[test]
fn a_big_hull_is_measured_to_its_nearest_volume_not_its_sphere() {
    // The hull's sphere (radius 210) reaches 50 m off its flank, but its box's side is 30 m from the blast.
    let rows = rows_of(&[(7, Vector3::ZERO, 210.0, LIVE)], Some(hull()));
    let got = reached(&rows, v(50.0, 0.0, 0.0), 100.0);
    assert_eq!(got.len(), 1);
    assert!((got[0].distance - 30.0).abs() < 1e-9, "{:?}", got[0]);
    assert_eq!(got[0].volume, 0);
    assert!((got[0].point.x - 20.0).abs() < 1e-4);
    // Above the bow the capsule is nearer than the box: that volume is named.
    let above = reached(&rows, v(0.0, 70.0, 150.0), 100.0);
    assert_eq!(above[0].volume, 1);
    assert!((above[0].distance - 17.0).abs() < 1e-9, "{:?}", above[0]);
    // Off the box's end, inside its sphere but past the radius of the blast: nothing.
    assert!(reached(&rows, v(150.0, 0.0, 0.0), 100.0).is_empty());
}

#[test]
fn a_turned_hull_is_measured_in_its_own_frame() {
    let mut rows = rows_of(&[(7, v(1000.0, 0.0, 0.0), 210.0, LIVE)], Some(hull()));
    // Turned a quarter about y: its long axis now runs along x, so its end faces a blast at x = 1250.
    rows.bases[0] = Basis::from_axis_angle(Vector3::UP, std::f32::consts::FRAC_PI_2);
    let got = reached(&rows, v(1250.0, 0.0, 0.0), 100.0);
    assert_eq!(got.len(), 1);
    assert!((got[0].distance - 50.0).abs() < 1e-3, "{:?}", got[0]);
    assert!((got[0].point.x - 1200.0).abs() < 1e-2);
}

#[test]
fn only_hulls_in_play_are_reached_and_in_the_rows_order() {
    use crate::rows::{FLAG_SHELTERED, FLAG_TIER};
    let rows = rows_of(
        &[
            (1, v(10.0, 0.0, 0.0), 5.0, FLAG_RIGID),
            (2, v(20.0, 0.0, 0.0), 5.0, LIVE | FLAG_SHELTERED),
            (3, v(30.0, 0.0, 0.0), 5.0, FLAG_TIER),
            (4, v(-5.0, 0.0, 0.0), 5.0, LIVE),
        ],
        None,
    );
    let mut out = Vec::new();
    reach(&rows, &[3, 2, 1, 0], Vector3::ZERO, 100.0, &mut out);
    let order: Vec<u32> = out.iter().map(|r| r.row).collect();
    assert_eq!(order, vec![3, 2], "an inactive hull and a sheltered one are skipped; the tier row counts");
    reach(&rows, &[0], Vector3::ZERO, f64::NAN, &mut out);
    reach(&rows, &[0], Vector3::ZERO, 0.0, &mut out);
    assert_eq!(out.len(), 2, "no radius, no reach");
}

#[test]
fn the_same_rows_give_the_same_answer_every_time() {
    let mut bodies = Vec::new();
    for i in 0..200_i64 {
        let a = i as f32 * 0.37;
        bodies.push((i + 10, v(a.cos() * (i as f32) * 3.0, a.sin() * 40.0, (i as f32) * 2.5 - 250.0), 8.0, LIVE));
    }
    let rows = rows_of(&bodies, None);
    let first = reached(&rows, v(5.0, -3.0, 20.0), 300.0);
    assert!(first.len() > 50);
    for _ in 0..3 {
        assert_eq!(reached(&rows, v(5.0, -3.0, 20.0), 300.0), first);
    }
}
