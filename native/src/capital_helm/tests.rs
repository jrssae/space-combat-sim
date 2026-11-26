// The capital helm (M10-T16; T07's GDScript helm tests, moved with it): brakes on retros with the bow held, flips a hull
// with no retros and turns back, coasts down a small slowing, slides a gravitic hull, paces a turn to its torque.
use super::*;

use crate::v3::{BACK, FORWARD, UP, col_b, col_c, dot, length, neg, normalized, scale, sub};

// A 300 m test hull's helm: 2 m/s^2 mains, 0.1 m/s^2 RCS, 4 deg/s turns, 0.01 rad/s^2 torque.
fn spec(retros: bool, gravitic: bool) -> HelmSpec {
    HelmSpec {
        gravitic,
        retros: retros || gravitic,
        cap: Capability {
            a_main: 2.0,
            a_retro: if retros || gravitic { 1.0 } else { 0.01 },
            a_rcs_x: if gravitic { 1.0 } else { 0.1 },
            a_rcs_y: if gravitic { 1.0 } else { 0.1 },
            rate_max: Vector3::new(0.0698, 0.0698, 0.0524),
            alpha_max: Vector3::new(0.01, 0.01, 0.01),
        },
    }
}

fn helm(heading: Vector3, velocity: Vector3) -> Helm {
    Helm {
        heading,
        velocity,
        up: Vector3::ZERO,
        level: false,
        flipping: false,
    }
}

#[test]
fn with_retros_it_brakes_with_its_bow_held() {
    let s = spec(true, false);
    let mut h = helm(FORWARD, Vector3::ZERO);
    let cmd = command(&s, &mut h, &Basis::IDENTITY, Vector3::new(0.0, 0.0, -20.0));
    assert!(!h.flipping);
    assert!(cmd.retro_left > 0.0, "the retros brake");
    assert_eq!(cmd.retro_left, cmd.retro_right, "both sides together");
    assert_eq!(cmd.main_left, 0.0);
    assert!(length(cmd.rot) < 1e-6, "the bow stays on its heading");
}

#[test]
fn without_retros_it_flips_burns_and_turns_back() {
    let s = spec(false, false);
    let mut h = helm(FORWARD, Vector3::ZERO);
    let moving = Vector3::new(0.0, 0.0, -20.0);
    let cmd = command(&s, &mut h, &Basis::IDENTITY, moving);
    assert!(h.flipping, "it must slow and has no retros");
    assert_eq!(cmd.retro_left, 0.0, "nothing pushes aft");
    assert_eq!(cmd.main_left, 0.0, "no burn while the bow points the wrong way");
    assert!(length(cmd.rot) > 0.1, "it turns");
    let turned = Basis::from_axis_angle(Vector3::UP, std::f32::consts::PI);
    let cmd = command(&s, &mut h, &turned, moving);
    assert!(h.flipping);
    assert!(cmd.main_left > 0.5, "turned round, it burns its mains against its motion");
    let cmd = command(&s, &mut h, &turned, Vector3::new(0.0, 0.0, -0.2));
    assert!(!h.flipping, "stopped, the flip is over");
    assert_eq!(cmd.main_left, 0.0);
    assert!(length(cmd.rot) > 0.1, "and it turns back to its heading");
}

#[test]
fn a_small_slowing_does_not_start_a_flip() {
    let s = spec(false, false);
    let mut h = helm(FORWARD, Vector3::new(0.0, 0.0, -18.0));
    command(&s, &mut h, &Basis::IDENTITY, Vector3::new(0.0, 0.0, -20.0));
    assert!(!h.flipping, "under FLIP_ENTER_MPS it coasts down rather than turning a 300 m hull");
}

#[test]
fn a_gravitic_hull_pushes_along_any_axis_without_turning() {
    let s = spec(false, true);
    let mut h = helm(FORWARD, Vector3::new(10.0, 0.0, 0.0));
    let cmd = command(&s, &mut h, &Basis::IDENTITY, Vector3::new(0.0, 0.0, -20.0));
    assert!(!h.flipping);
    assert!(cmd.retro_left > 0.0, "it brakes backward");
    assert!(cmd.strafe_x > 0.0, "and slides sideways");
    assert!(length(cmd.rot) < 1e-6, "with its bow held");
}

#[test]
fn a_turn_is_paced_to_what_the_torque_can_stop() {
    let s = spec(true, false);
    for angle_deg in [2.0f32, 20.0, 90.0] {
        let heading = crate::v3::rotated(FORWARD, Vector3::UP, angle_deg.to_radians());
        let mut h = helm(heading, Vector3::ZERO);
        let cmd = command(&s, &mut h, &Basis::IDENTITY, Vector3::ZERO);
        let asked = f64::from(cmd.rot.y.abs()) * f64::from(s.cap.rate_max.y);
        let stoppable = (2.0 * 0.01 * f64::from(angle_deg.to_radians())).sqrt();
        assert!(asked < stoppable + 1e-6, "at {angle_deg} deg it asks no faster a turn than it can stop from");
        assert!(asked > 0.0);
    }
}

#[test]
fn no_heading_holds_the_bow_where_it_is() {
    let s = spec(true, false);
    let mut h = helm(Vector3::ZERO, Vector3::ZERO);
    let basis = Basis::from_axis_angle(Vector3::UP, 0.7);
    let cmd = command(&s, &mut h, &basis, Vector3::ZERO);
    assert!(length(cmd.rot) < 1e-6);
    let mut h = helm(BACK, Vector3::ZERO);
    let cmd = command(&s, &mut h, &Basis::IDENTITY, Vector3::ZERO);
    assert!(length(cmd.rot) > 0.0, "dead astern it turns");
}

#[test]
fn a_top_to_hold_rolls_the_hull_onto_it_and_none_leaves_the_roll_alone() {
    let s = spec(true, false);
    let mut h = helm(FORWARD, Vector3::ZERO);
    h.up = Vector3::new(1.0, 0.0, 0.0);
    let cmd = command(&s, &mut h, &Basis::IDENTITY, Vector3::ZERO);
    assert!(cmd.rot.z.abs() > 0.0, "it rolls toward the top it is told");
    h.up = Vector3::ZERO;
    let cmd = command(&s, &mut h, &Basis::IDENTITY, Vector3::ZERO);
    assert_eq!(cmd.rot.z, 0.0);
}

// The hull turned by `cmd` for `dt` seconds at its asked rates (an ideal assist): the toy the turn tests fly.
fn fly(basis: Basis, cmd: &FlightCmd, rate: Vector3, dt: f32) -> Basis {
    let w = Vector3::new(cmd.rot.x * rate.x, -cmd.rot.y * rate.y, -cmd.rot.z * rate.z);
    if length(w) < 1e-9 {
        return basis;
    }
    (basis * Basis::from_axis_angle(normalized(w), length(w) * dt)).orthonormalized()
}

// The roll off level about the bow, deg.
fn roll_deg(basis: &Basis) -> f32 {
    let nose = neg(col_c(basis));
    let level = normalized(sub(UP, scale(nose, dot(nose, UP))));
    dot(col_b(basis), level).clamp(-1.0, 1.0).acos().to_degrees()
}

#[test]
fn a_half_turn_is_a_level_turn_and_a_rolled_hull_comes_back_level() {
    let s = spec(true, false);
    let mut h = helm(BACK, Vector3::ZERO);
    h.level = true;
    let cmd = command(&s, &mut h, &Basis::IDENTITY, Vector3::ZERO);
    assert!(cmd.rot.y.abs() > 0.0 && cmd.rot.x == 0.0, "dead astern it yaws, it does not loop: {:?}", cmd.rot);
    // Rolled 90 degrees and told a half turn, it turns and settles level.
    let mut basis = Basis::from_axis_angle(FORWARD, std::f32::consts::FRAC_PI_2);
    let heading = BACK;
    h.heading = heading;
    for _ in 0..40000 {
        let cmd = command(&s, &mut h, &basis, Vector3::ZERO);
        basis = fly(basis, &cmd, s.cap.rate_max, 0.05);
    }
    assert!(dot(neg(col_c(&basis)), heading) > 0.999, "on its heading");
    assert!(roll_deg(&basis) < 2.0, "and level ({} deg)", roll_deg(&basis));
    // T07's helm (no levelling, the parity probe) leaves the roll alone.
    let mut old = helm(FORWARD, Vector3::ZERO);
    let rolled = Basis::from_axis_angle(FORWARD, 0.5);
    assert_eq!(command(&s, &mut old, &rolled, Vector3::ZERO).rot.z, 0.0);
}
