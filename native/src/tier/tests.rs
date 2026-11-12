// Gravity on the tier's rows (M6-T07): the pull each row feels is applied every tick on top of its engines.
use super::*;

const DT: f64 = 1.0 / 60.0;
const PERIOD: i64 = 3;

fn rows() -> TierRows {
    let mut t = TierRows::default();
    let v = Vector3::new(120.5, -7.25, -300.125);
    t.add(KIND_FIGHTER, 1, 0, -1, 0, Vector3::new(5000.0, 10.0, -2000.0), v, Basis::IDENTITY, Vector3::new(0.1, 0.0, 0.2), 0);
    t.add(KIND_CAPITAL, 2, 0, -2, 0, Vector3::new(-800.0, 0.0, 900.0), v, Basis::IDENTITY, Vector3::ZERO, 1);
    t.cruise[1] = v;
    t.add(KIND_FIGHTER, 3, 0, -3, 0, Vector3::new(0.0, 300.0, 0.0), v, Basis::IDENTITY, Vector3::ZERO, 2);
    t.hulk[2] = true;
    t
}

fn run(t: &mut TierRows, pull: &[Vector3], ticks: i64) {
    let commands = CommandMap::default();
    let mut scratch = Vec::new();
    for tick in 0..ticks {
        step(t, &[], pull, &commands, tick, DT, PERIOD, &mut scratch);
    }
}

#[test]
fn with_no_pull_the_rows_keep_their_bits_and_a_pull_of_zeros_changes_none() {
    let (mut a, mut b) = (rows(), rows());
    run(&mut a, &[], 300);
    run(&mut b, &[Vector3::ZERO; 3], 300);
    assert_eq!(a.positions, b.positions);
    assert_eq!(a.velocities, b.velocities);
    assert_eq!(a.accel, b.accel);
    assert_eq!(a.velocities[0], rows().velocities[0], "a row with no type and no pull coasts bit for bit");
}

#[test]
fn every_row_falls_with_its_pull_and_a_capital_holds_its_cruise_against_it() {
    let mut t = rows();
    let g = Vector3::new(0.0, -0.03, 0.01);
    let v0 = t.velocities.clone();
    run(&mut t, &[g; 3], 600);
    // Ten seconds: 0.3 m/s down, 0.1 m/s along z, within the 32-bit rounding of 600 kicks at 300 m/s (3e-5 a step).
    for i in [0, 2] {
        let dv = sub(t.velocities[i], v0[i]);
        assert!(f64::from(length(sub(dv, scale(g, 10.0)))) < 0.01, "row {i} took the pull: {dv:?}");
    }
    let held = sub(t.velocities[1], v0[1]);
    assert!(f64::from(length(held)) < 0.02, "the capital's engines hold off the pull: {held:?}");
    assert!(f64::from(length(t.accel[1])) > 0.0, "and they push against it");
}
