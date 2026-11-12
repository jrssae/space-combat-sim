// The kernels' unit tests (M5-T33): the ram pass's sphere reject against the sphere test it stands in for.
use godot::builtin::Vector3;

use super::ram::{cannot_reach, clearly_apart};
use crate::rows::{FLAG_RIGID, Rows};

// Two rows: positions, velocities, radii, and whether each is a rigid body.
fn pair(at: [Vector3; 2], v: [Vector3; 2], radii: [f64; 2], rigid: [bool; 2]) -> Rows {
    Rows {
        positions: at.to_vec(),
        velocities: v.to_vec(),
        radii: radii.to_vec(),
        flags: rigid
            .iter()
            .map(|&r| if r { FLAG_RIGID } else { 0 })
            .collect(),
        ..Rows::default()
    }
}

// The closest the two spheres' centres come over the tick, sampled finely along the relative path.
fn nearest(rows: &Rows, delta: f64) -> f64 {
    let start = |j: usize| {
        let (p, v) = (rows.positions[j], rows.velocities[j]);
        let back = if rows.flags[j] & FLAG_RIGID != 0 {
            0.0
        } else {
            delta
        };
        [
            f64::from(p.x) - f64::from(v.x) * back,
            f64::from(p.y) - f64::from(v.y) * back,
            f64::from(p.z) - f64::from(v.z) * back,
        ]
    };
    let (a, b) = (start(0), start(1));
    let (va, vb) = (rows.velocities[0], rows.velocities[1]);
    let mut best = f64::INFINITY;
    for step in 0..=2000 {
        let t = delta * f64::from(step) / 2000.0;
        let dx = a[0] - b[0] + f64::from(va.x - vb.x) * t;
        let dy = a[1] - b[1] + f64::from(va.y - vb.y) * t;
        let dz = a[2] - b[2] + f64::from(va.z - vb.z) * t;
        best = best.min((dx * dx + dy * dy + dz * dz).sqrt());
    }
    best
}

fn next(state: &mut u64) -> f32 {
    *state = state
        .wrapping_mul(6_364_136_223_846_793_005)
        .wrapping_add(1_442_695_040_888_963_407);
    ((*state >> 40) as f32) / (1u64 << 24) as f32 * 2.0 - 1.0
}

#[test]
fn a_pair_is_clearly_apart_only_when_its_spheres_never_come_near() {
    let delta = 1.0 / 60.0;
    let mut seed = 33u64;
    let (mut apart, mut near) = (0, 0);
    for _ in 0..20_000 {
        let origin = Vector3::new(next(&mut seed), next(&mut seed), next(&mut seed)) * 40_000.0;
        let offset = Vector3::new(next(&mut seed), next(&mut seed), next(&mut seed)) * 60.0;
        let v = [
            Vector3::new(next(&mut seed), next(&mut seed), next(&mut seed)) * 900.0,
            Vector3::new(next(&mut seed), next(&mut seed), next(&mut seed)) * 900.0,
        ];
        let radii = [
            f64::from(next(&mut seed).abs()) * 30.0,
            f64::from(next(&mut seed).abs()) * 30.0,
        ];
        let rigid = [next(&mut seed) > 0.0, next(&mut seed) > -0.5];
        let rows = pair([origin + offset, origin], v, radii, rigid);
        let gap = nearest(&rows, delta) - radii[0] - radii[1];
        if clearly_apart(&rows, 0, 1, delta) {
            apart += 1;
            assert!(
                gap > 0.04,
                "said apart with the spheres {gap} m from touching"
            );
        } else {
            near += 1;
            assert!(gap < 1.0, "kept a pair whose spheres stay {gap} m apart");
        }
        assert_eq!(
            clearly_apart(&rows, 1, 0, delta),
            clearly_apart(&rows, 0, 1, delta)
        );
    }
    assert!(
        apart > 2000 && near > 2000,
        "both answers seen: {apart} apart, {near} near"
    );
}

#[test]
fn a_row_that_is_not_a_number_is_never_clearly_apart() {
    let rows = pair(
        [
            Vector3::new(f32::NAN, 0.0, 0.0),
            Vector3::new(9000.0, 0.0, 0.0),
        ],
        [Vector3::ZERO, Vector3::ZERO],
        [5.0, 5.0],
        [true, true],
    );
    assert!(!clearly_apart(&rows, 0, 1, 1.0 / 60.0));
    let wide = pair(
        [Vector3::ZERO, Vector3::new(9000.0, 0.0, 0.0)],
        [Vector3::ZERO, Vector3::ZERO],
        [f64::INFINITY, 5.0],
        [true, false],
    );
    assert!(!clearly_apart(&wide, 0, 1, 1.0 / 60.0));
}

// `RamResolver._sphere_reaches` as the resolver runs it, in 32 bits: the first hull's sphere (padded 0.05 m), swept in
// the second's frame, against the second's box; touching edges do not count.
fn resolver_reaches(rows: &Rows, delta: f32, radius: f32, low: [f32; 3], high: [f32; 3]) -> bool {
    let start = |j: usize| {
        if rows.flags[j] & FLAG_RIGID != 0 {
            rows.positions[j]
        } else {
            rows.positions[j] - rows.velocities[j] * delta
        }
    };
    let end = |j: usize| {
        if rows.flags[j] & FLAG_RIGID != 0 {
            rows.positions[j] + rows.velocities[j] * delta
        } else {
            rows.positions[j]
        }
    };
    let to_second = rows.bases[1].transposed();
    let second_move = end(1) - start(1);
    let centre = to_second * (start(0) - start(1));
    let moved = to_second * (end(0) - start(0) - second_move);
    let r = radius + 0.05;
    let c = [centre.x, centre.y, centre.z];
    let m = [moved.x, moved.y, moved.z];
    (0..3).all(|k| {
        let lo = (c[k] - r).min(c[k] - r + m[k]);
        let hi = (c[k] + r).max(c[k] + r + m[k]);
        lo < high[k] && hi > low[k]
    })
}

#[test]
fn a_sphere_cannot_reach_a_box_only_where_the_resolvers_test_says_no() {
    use godot::builtin::{Basis, EulerOrder};
    let delta = 1.0 / 60.0;
    let mut seed = 4401u64;
    let (mut out, mut within) = (0, 0);
    for _ in 0..20_000 {
        let origin = Vector3::new(next(&mut seed), next(&mut seed), next(&mut seed)) * 30_000.0;
        let offset = Vector3::new(
            next(&mut seed) * 500.0,
            next(&mut seed) * 120.0,
            next(&mut seed) * 250.0,
        );
        let v = [
            Vector3::new(next(&mut seed), next(&mut seed), next(&mut seed)) * 400.0,
            Vector3::new(next(&mut seed), next(&mut seed), next(&mut seed)) * 30.0,
        ];
        let rigid = [true, next(&mut seed) > -0.5];
        let mut rows = pair([origin + offset, origin], v, [9.0, 614.0], rigid);
        let turn = Vector3::new(next(&mut seed), next(&mut seed), next(&mut seed)) * 3.0;
        rows.bases = vec![Basis::IDENTITY, Basis::from_euler(EulerOrder::YXZ, turn)];
        let radius = 5.0 + next(&mut seed).abs() * 10.0;
        let half = [
            60.0 + next(&mut seed).abs() * 500.0,
            20.0 + next(&mut seed).abs() * 100.0,
            40.0 + next(&mut seed).abs() * 200.0,
        ];
        let low = [-half[0], -half[1] + 10.0, -half[2]];
        let high = [half[0], half[1] + 10.0, half[2]];
        let wide = |b: [f32; 3]| [f64::from(b[0]), f64::from(b[1]), f64::from(b[2])];
        let said = cannot_reach(&rows, 0, 1, delta, f64::from(radius), wide(low), wide(high));
        let reaches = resolver_reaches(&rows, delta as f32, radius, low, high);
        if said {
            out += 1;
            assert!(
                !reaches,
                "said out of reach where the resolver's test passes"
            );
        } else {
            within += 1;
        }
        // The room is small: a sphere half a metre larger that still cannot reach by the resolver's test is rejected.
        if !said && !resolver_reaches(&rows, delta as f32, radius + 0.5, low, high) {
            panic!("kept a pair the resolver rejects with half a metre to spare");
        }
    }
    assert!(
        out > 2000 && within > 2000,
        "both answers seen: {out} out, {within} within"
    );
}

#[test]
fn a_hull_with_no_box_or_no_number_is_left_to_the_resolver() {
    let mut rows = pair(
        [Vector3::new(900.0, 0.0, 0.0), Vector3::ZERO],
        [Vector3::ZERO, Vector3::ZERO],
        [9.0, 600.0],
        [true, true],
    );
    rows.bases = vec![godot::builtin::Basis::IDENTITY; 2];
    let d = 1.0 / 60.0;
    assert!(cannot_reach(&rows, 0, 1, d, 9.0, [-100.0; 3], [100.0; 3]));
    assert!(!cannot_reach(
        &rows,
        0,
        1,
        d,
        9.0,
        [-100.0; 3],
        [900.0, 100.0, 100.0]
    ));
    assert!(!cannot_reach(
        &rows,
        0,
        1,
        d,
        f64::NAN,
        [-100.0; 3],
        [100.0; 3]
    ));
    assert!(!cannot_reach(
        &rows,
        0,
        1,
        d,
        9.0,
        [f64::NAN; 3],
        [100.0; 3]
    ));
    assert!(!cannot_reach(&rows, 0, 1, d, 9.0, [100.0; 3], [-100.0; 3]));
}

#[test]
fn a_static_shift_moves_only_the_owners_rows_by_the_same_32_bit_sum() {
    use super::statics::shift_owned;
    let mut seed = 71u64;
    let start: Vec<Vector3> = (0..500)
        .map(|_| Vector3::new(next(&mut seed) * 9.0e4, next(&mut seed) * 2.0e4, next(&mut seed) * 9.0e4))
        .collect();
    let worlds: Vec<i64> = (0..500).map(|i| if i % 5 == 0 { 0 } else { 42 }).collect();
    let offset = Vector3::new(-180.25, 0.003, 4999.9);
    let mut positions = start.clone();
    assert_eq!(shift_owned(&mut positions, &worlds, 42, offset), 400);
    for i in 0..500 {
        if worlds[i] == 42 {
            // The same bits as GDScript's `positions[s] += offset` on a 32-bit Vector3.
            let want = start[i] + offset;
            assert_eq!(positions[i].x.to_bits(), want.x.to_bits());
            assert_eq!(positions[i].y.to_bits(), want.y.to_bits());
            assert_eq!(positions[i].z.to_bits(), want.z.to_bits());
        } else {
            assert_eq!(positions[i], start[i], "a row of another world stays");
        }
    }
    assert_eq!(shift_owned(&mut positions, &worlds, 7, offset), 0, "no row of world 7");
}

#[test]
fn a_static_shift_with_columns_out_of_step_moves_nothing() {
    use super::statics::shift_owned;
    let mut positions = vec![Vector3::new(1.0, 2.0, 3.0); 3];
    assert_eq!(shift_owned(&mut positions, &[1, 1], 1, Vector3::ONE), 0);
    assert_eq!(positions, vec![Vector3::new(1.0, 2.0, 3.0); 3]);
}
