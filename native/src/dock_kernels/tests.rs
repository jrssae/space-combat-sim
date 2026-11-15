// The docking kernel (M12-T19), beside the kernel and outside its engine-free guard (test builds only).
use super::*;

fn v(x: f32, y: f32, z: f32) -> Vector3 {
    Vector3::new(x, y, z)
}

fn still() -> Carrier {
    Carrier { position: v(0.0, 0.0, 0.0), basis: Basis::IDENTITY, velocity: Vector3::ZERO, spin: Vector3::ZERO }
}

// A cradle on the carrier's top, 40 m up, the fighter's rest point 0.8 m under its origin, the approach point 60 m out.
fn top_row(phase: i32) -> Row {
    Row::new(phase, v(0.0, 40.0, 10.0), Basis::IDENTITY, 60.0, v(0.0, -0.8, 0.0))
}

fn close(a: Vector3, b: Vector3, tol: f32) -> bool {
    length(sub(a, b)) < tol
}

#[test]
fn a_docked_fighter_rests_its_belly_on_the_pad() {
    let row = top_row(PHASE_LAUNCH);
    assert!(close(docked_origin(&row, 0.0), v(0.0, 40.8, 10.0), 1e-5));
    assert!(close(approach_point(&row), v(0.0, 100.8, 10.0), 1e-4));
}

#[test]
fn a_launch_pushes_straight_out_and_releases_at_speed() {
    let mut row = top_row(PHASE_LAUNCH);
    let carrier = Carrier { velocity: v(0.0, 0.0, -30.0), ..still() };
    let mut last = step_row(&mut row, &carrier, Vector3::ZERO, Vector3::ZERO, 20.0, 150.0, 1.0 / 60.0);
    let first_height = last.position.y - 40.8;
    assert!(first_height > 0.0 && first_height < 0.01, "it starts on the pad: {first_height}");
    let mut ticks = 1;
    while last.event == EVENT_NONE {
        last = step_row(&mut row, &carrier, Vector3::ZERO, Vector3::ZERO, 20.0, 150.0, 1.0 / 60.0);
        ticks += 1;
        assert!(ticks < 1000);
    }
    assert_eq!(last.event, EVENT_RELEASED);
    assert!((ticks as f64 / 60.0 - LAUNCH_S).abs() < 0.05);
    assert!(close(last.position, v(0.0, 40.8 + RELEASE_M as f32, 10.0), 1e-3));
    assert!(close(last.velocity, v(0.0, (2.0 * RELEASE_M / LAUNCH_S) as f32, -30.0), 1e-3), "the carrier's velocity and the push");
}

#[test]
fn a_launch_follows_a_turned_and_spinning_carrier() {
    // The carrier yawed a quarter turn (its +X along World -Z) and spinning about World +Y.
    let basis = Basis::from_cols(v(0.0, 0.0, -1.0), v(0.0, 1.0, 0.0), v(1.0, 0.0, 0.0));
    let carrier = Carrier { position: v(100.0, 0.0, 0.0), basis, velocity: Vector3::ZERO, spin: v(0.0, 0.1, 0.0) };
    let mut row = Row::new(PHASE_LAUNCH, v(40.0, 0.0, 0.0), Basis::from_cols(v(0.0, 0.0, 1.0), v(1.0, 0.0, 0.0), v(0.0, 1.0, 0.0)), 60.0, Vector3::ZERO);
    let out = step_row(&mut row, &carrier, Vector3::ZERO, Vector3::ZERO, 20.0, 150.0, 1e-6);
    assert!(close(out.position, v(100.0, 0.0, -40.0), 1e-3), "the pad in the World: {:?}", out.position);
    assert!(close(out.velocity, v(-4.0, 0.0, 0.0), 1e-3), "the spin carries the pad: {:?}", out.velocity);
}

#[test]
fn a_returning_fighter_on_the_cradles_side_flies_to_the_approach_point_and_slows() {
    let mut row = top_row(PHASE_RETURN);
    let far = step_row(&mut row, &still(), v(0.0, 2000.0, 10.0), Vector3::ZERO, 20.0, 150.0, 1.0 / 60.0);
    assert!(close(far.position, v(0.0, 100.8, 10.0), 1e-3));
    assert!(far.velocity.y < -150.0 && far.velocity.y >= -(RETURN_MPS as f32));
    let near = step_row(&mut row, &still(), v(0.0, 130.8, 10.0), Vector3::ZERO, 20.0, 150.0, 1.0 / 60.0);
    assert!(near.velocity.y < 0.0 && near.velocity.y > -30.0, "slow near the point: {}", near.velocity.y);
    assert_eq!(near.event, EVENT_NONE);
    let there = step_row(&mut row, &still(), v(1.0, 103.0, 10.0), v(0.0, -8.0, 0.0), 20.0, 150.0, 1.0 / 60.0);
    assert_eq!(there.event, EVENT_AT_APPROACH);
    let too_fast = step_row(&mut row, &still(), v(1.0, 103.0, 10.0), v(0.0, -60.0, 0.0), 20.0, 150.0, 1.0 / 60.0);
    assert_eq!(too_fast.event, EVENT_NONE, "not taken while it is still fast");
}

#[test]
fn a_returning_fighter_behind_the_carrier_flies_round_outside_the_hull() {
    let row = top_row(PHASE_RETURN);
    for p in [v(0.0, -500.0, 0.0), v(300.0, -200.0, 50.0), v(0.0, -90.0, -300.0)] {
        let mut at = p;
        let mut steps = 0;
        // Fly the aim points: the way to the approach point never comes inside the shell.
        while !close(return_aim(&row, at, 150.0), approach_point(&row), 1e-3) {
            let aim = return_aim(&row, at, 150.0);
            assert!(length(aim) >= 149.9, "an aim point inside the shell: {:?}", aim);
            let toward = normalized(sub(aim, at));
            at = add(at, scale(toward, 5.0));
            assert!(length(at) > 80.0, "the path cut the hull at {:?} from {:?}", at, p);
            steps += 1;
            assert!(steps < 2000, "never came round from {:?}", p);
        }
    }
}

#[test]
fn the_wanted_velocity_rides_with_a_moving_carrier() {
    let mut row = top_row(PHASE_RETURN);
    let carrier = Carrier { velocity: v(0.0, 0.0, -30.0), ..still() };
    let out = step_row(&mut row, &carrier, v(0.0, 104.0, 10.0), v(0.0, 0.0, -30.0), 20.0, 150.0, 1.0 / 60.0);
    assert!((out.velocity.z + 30.0).abs() < 1e-3);
    assert_eq!(out.event, EVENT_AT_APPROACH, "at rest against the carrier counts as slow");
}

#[test]
fn a_capture_draws_the_fighter_onto_the_pad_and_squares_it_up() {
    let mut row = top_row(PHASE_RETURN);
    let tilted = Basis::from_cols(v(0.0, 0.0, -1.0), v(0.0, 1.0, 0.0), v(1.0, 0.0, 0.0));
    row.begin_capture(v(3.0, 98.0, 12.0), tilted);
    let mut last = step_row(&mut row, &still(), Vector3::ZERO, Vector3::ZERO, 20.0, 150.0, 1.0 / 60.0);
    assert!(close(last.position, v(3.0, 98.0, 12.0), 1.0), "it starts where it was taken");
    let mut height = last.position.y;
    while last.event == EVENT_NONE {
        last = step_row(&mut row, &still(), Vector3::ZERO, Vector3::ZERO, 20.0, 150.0, 1.0 / 60.0);
        assert!(last.position.y <= height + 1e-4, "it only comes in");
        height = last.position.y;
    }
    assert_eq!(last.event, EVENT_DOCKED);
    assert!(close(last.position, v(0.0, 40.8, 10.0), 1e-3));
    assert!(close(col_c(&last.basis), v(0.0, 0.0, 1.0), 1e-3) && close(col_b(&last.basis), v(0.0, 1.0, 0.0), 1e-3));
}

#[test]
fn a_row_depends_on_nothing_but_itself() {
    // Stepped alone, or after other rows in any order, a row gives the same answer bit for bit: a split across threads cannot change it.
    let carrier = Carrier { position: v(5.0, -3.0, 9.0), velocity: v(1.0, 2.0, -30.0), spin: v(0.0, 0.02, 0.0), ..still() };
    let make = || vec![top_row(PHASE_LAUNCH), top_row(PHASE_RETURN), Row::new(PHASE_RETURN, v(30.0, -20.0, 5.0), Basis::IDENTITY, 60.0, Vector3::ZERO)];
    let at = [v(0.0, 0.0, 0.0), v(400.0, -900.0, 30.0), v(-250.0, 80.0, 10.0)];
    let run = |order: &[usize]| {
        let mut rows = make();
        let mut out = vec![None; 3];
        for _ in 0..30 {
            for &k in order {
                out[k] = Some(step_row(&mut rows[k], &carrier, at[k], Vector3::ZERO, 18.0, 150.0, 1.0 / 60.0));
            }
        }
        out.into_iter().map(|o| { let o = o.unwrap(); (o.event, o.position, o.velocity) }).collect::<Vec<_>>()
    };
    assert_eq!(run(&[0, 1, 2]), run(&[2, 0, 1]));
}
