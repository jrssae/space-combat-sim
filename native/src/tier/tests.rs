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
        step(t, &[], pull, Rest::ZERO, &commands, tick, DT, PERIOD, &mut scratch);
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

// M6-T08: the ceiling reads a row's speed against the World's rest, so a row moving with a boosted frame's anchor is not slowed.
#[test]
fn the_speed_ceiling_reads_the_speed_against_the_rest() {
    let commands = CommandMap::default();
    let mut scratch = Vec::new();
    let v = rows().velocities[0];
    let (mut capped, mut riding) = (rows(), rows());
    capped.speed_limit[0] = 100.0;
    riding.speed_limit[0] = 100.0;
    step(&mut capped, &[], &[], Rest::ZERO, &commands, 1, DT, PERIOD, &mut scratch);
    let rest = Rest { velocity: v, accel: Vector3::ZERO };
    step(&mut riding, &[], &[], rest, &commands, 1, DT, PERIOD, &mut scratch);
    assert!((f64::from(length(capped.velocities[0])) - 100.0).abs() < 1e-3, "against zero: cut to the ceiling");
    assert_eq!(riding.velocities[0], v, "at rest against the anchor: nothing to cut");
    let mut fast = rows();
    fast.speed_limit[0] = 100.0;
    let slow = Rest { velocity: scale(v, 0.5), accel: Vector3::ZERO };
    step(&mut fast, &[], &[], slow, &commands, 1, DT, PERIOD, &mut scratch);
    let against = sub(fast.velocities[0], slow.velocity);
    assert!((f64::from(length(against)) - 100.0).abs() < 1e-3, "cut to the ceiling on top of the rest");
}

// M7-T26: a row with a far hull keeps it until its radius is under the dot size on screen, then is a dot; back a tenth inside.
fn hulled(radius: f64, distance: f32) -> TierRows {
    let mut t = TierRows::default();
    t.add(KIND_FIGHTER, 7, 0, -7, 0, Vector3::new(0.0, 0.0, -distance), Vector3::ZERO, Basis::IDENTITY, Vector3::ZERO, 0);
    t.radii[0] = radius;
    t.proxy[0] = 0;
    t
}

fn hull_count(t: &TierRows) -> usize {
    let mut out = Vec::new();
    fill_hulls(t, 0, Vector3::ZERO, &mut out)
}

#[test]
fn a_far_hull_turns_into_a_dot_by_its_size_on_screen_not_its_distance() {
    // 352 px per radian over a 2 px dot: a 70 m freighter is a dot past 24.6 km, a 10 m fighter past 3.5 km.
    let m_per_m = 704.0 / 2.0;
    let mut freighter = hulled(70.0, 20_000.0);
    let mut fighter = hulled(10.0, 20_000.0);
    update_view(&mut freighter, Vector3::ZERO, m_per_m);
    update_view(&mut fighter, Vector3::ZERO, m_per_m);
    assert_eq!((hull_count(&freighter), dot_count(&freighter)), (1, 0), "the freighter is still a hull at 20 km");
    assert_eq!((hull_count(&fighter), dot_count(&fighter)), (0, 1), "the fighter is a dot at 20 km");
    freighter.positions[0] = Vector3::new(0.0, 0.0, -25_000.0);
    update_view(&mut freighter, Vector3::ZERO, m_per_m);
    assert_eq!((hull_count(&freighter), dot_count(&freighter)), (0, 1), "a dot once under the size");
    let mut buf = vec![0.0; DOT_STRIDE];
    assert_eq!(fill_dots(&freighter, Vector3::ZERO, &mut buf, 0), 1);
}

#[test]
fn a_dotted_row_shows_its_hull_again_a_tenth_inside_and_repeating_the_view_changes_nothing() {
    let m_per_m = 352.0;
    let mut t = hulled(70.0, 25_000.0);
    update_view(&mut t, Vector3::ZERO, m_per_m);
    assert!(t.dotted[0]);
    t.positions[0] = Vector3::new(0.0, 0.0, -23_000.0);
    update_view(&mut t, Vector3::ZERO, m_per_m);
    update_view(&mut t, Vector3::ZERO, m_per_m);
    assert!(t.dotted[0], "still a dot inside the line until a tenth in");
    t.positions[0] = Vector3::new(0.0, 0.0, -22_000.0);
    update_view(&mut t, Vector3::ZERO, m_per_m);
    assert!(!t.dotted[0], "its hull again 10 % inside");
    update_view(&mut t, Vector3::ZERO, m_per_m);
    assert!(!t.dotted[0], "the same view twice decides the same");
}

#[test]
fn a_row_with_no_far_hull_is_always_a_dot_and_no_view_keeps_every_hull() {
    let mut t = hulled(70.0, 1.0e6);
    update_view(&mut t, Vector3::ZERO, 0.0);
    assert_eq!((hull_count(&t), dot_count(&t)), (1, 0), "no view set: the hull is kept");
    t.proxy[0] = -1;
    update_view(&mut t, Vector3::ZERO, 352.0);
    assert_eq!((hull_count(&t), dot_count(&t)), (0, 1));
    t.remove(7);
    assert!(t.dotted.is_empty(), "the column follows the rows");
}

// M10-T10 (D12.7): a disabled capital is a hulk row: its cruise is ignored, it keeps its velocity and its tumble bit for bit
// with nothing pulling, and falls with the pull like any body.
#[test]
fn a_capital_hulk_drifts_on_its_last_motion_and_ignores_its_cruise() {
    let v = Vector3::new(40.25, -3.5, 12.0);
    let spin = Vector3::new(0.0, 0.002, 0.001);
    let mut t = TierRows::default();
    t.add(KIND_CAPITAL, 9, 0, -9, 0, Vector3::new(9000.0, 0.0, 0.0), v, Basis::IDENTITY, spin, 0);
    t.cruise[0] = Vector3::new(-200.0, 0.0, 0.0);
    t.hulk[0] = true;
    run(&mut t, &[], 600);
    assert_eq!(t.velocities[0], v, "its cruise does not pull it");
    assert_eq!(t.angular[0], spin, "it keeps its tumble");
    assert_eq!(t.accel[0], Vector3::ZERO);
    assert_ne!(t.bases[0], Basis::IDENTITY, "and turns with it");
    let g = Vector3::new(0.0, -0.05, 0.0);
    let mut falling = TierRows::default();
    falling.add(KIND_CAPITAL, 9, 0, -9, 0, Vector3::ZERO, v, Basis::IDENTITY, spin, 0);
    falling.cruise[0] = v;
    falling.hulk[0] = true;
    run(&mut falling, &[g], 600);
    let dv = sub(falling.velocities[0], v);
    assert!(f64::from(length(sub(dv, scale(g, 10.0)))) < 0.01, "it falls with the pull, nothing holding it off: {dv:?}");
}
