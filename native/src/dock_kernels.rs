// A carrier's docking (M12-T19, docs/architecture.md 19.20): how its fighters leave a cradle, fly back to one and are drawn
// in onto it. Engine-free (test_sim_core reads this file): plain numbers in, plain numbers out, no statics, and a row's
// result depends on that row alone, so any split across threads gives the same answer. The shell (`dock_rows.rs`) keeps
// the rows for GDScript, which owns the ships.
//
// Everything about a cradle is in the carrier's frame: where the fighter rests (`position`, on the pad), how it sits
// (`basis`: its nose along -Z, its back along +Y, straight out from the carrier's axis), and how far out along +Y its
// approach point lies. A fighter is in one of three phases:
//
// * LAUNCH: pushed straight out from the pad, faster and faster, for `LAUNCH_S`; then it is released with that speed.
// * RETURN: it flies itself. The kernel gives the velocity to hold: round the carrier at a safe radius until the cradle's
//   side is in view, then to the approach point, slowing so it arrives nearly at rest against the carrier.
// * CAPTURE: from the approach point the cradle draws it in to the pad for `CAPTURE_S`; then it is docked.
use godot::builtin::{Basis, Vector3};

use crate::v3::{add, col_b, col_c, cross, dot, length, normalized, scale, sub, xform, xform_inv};

pub const PHASE_LAUNCH: i32 = 0;
pub const PHASE_RETURN: i32 = 1;
pub const PHASE_CAPTURE: i32 = 2;

pub const EVENT_NONE: i32 = 0;
/// The launch is over: the fighter flies on its own from `Out.position` with `Out.velocity`.
pub const EVENT_RELEASED: i32 = 1;
/// A returning fighter reached its approach point slowly enough: the cradle may take it (`Row::begin_capture`).
pub const EVENT_AT_APPROACH: i32 = 2;
/// The capture is over: the fighter sits on its pad.
pub const EVENT_DOCKED: i32 = 3;

/// A launch: how long the cradle pushes, s, and how far out the fighter is when it lets go, m.
pub const LAUNCH_S: f64 = 2.0;
pub const RELEASE_M: f64 = 30.0;
/// A capture: how long the cradle takes to draw the fighter in, s.
pub const CAPTURE_S: f64 = 4.0;
/// A returning fighter is taken once this near its approach point, m, and this slow against the carrier, m/s.
pub const CAPTURE_RADIUS_M: f64 = 10.0;
pub const CAPTURE_MPS: f64 = 20.0;
/// The fastest a returning fighter closes on the carrier, and the slowest it creeps to its approach point, m/s.
pub const RETURN_MPS: f64 = 220.0;
pub const CREEP_MPS: f64 = 6.0;
/// The share of its braking a returning fighter plans with.
pub const BRAKE_SHARE: f64 = 0.6;
/// A returning fighter heads straight for its approach point once that lies within this angle of it, seen from the
/// carrier's centre (cosine); otherwise it flies round outside the hull first.
pub const DIRECT_COS: f32 = 0.5;

/// The carrier this tick, World frame: its origin, axes, velocity and spin.
#[derive(Clone, Copy)]
pub struct Carrier {
    pub position: Vector3,
    pub basis: Basis,
    pub velocity: Vector3,
    pub spin: Vector3,
}

/// One fighter under the dock's control. `rest` is the point of the fighter (its own frame) that meets the pad; `start`
/// is where a capture began, in the carrier's frame.
#[derive(Clone, Copy)]
pub struct Row {
    pub phase: i32,
    pub age_s: f64,
    pub cradle_position: Vector3,
    pub cradle_basis: Basis,
    pub approach_m: f32,
    pub rest: Vector3,
    pub start_position: Vector3,
    pub start_basis: Basis,
}

/// What the row asks for this tick. LAUNCH and CAPTURE: the fighter's pose and velocity (World). RETURN: the velocity to
/// hold (World) in `velocity` and the point it flies to in `position`; `basis` is the docked attitude to turn to.
#[derive(Clone, Copy)]
pub struct Out {
    pub event: i32,
    pub position: Vector3,
    pub basis: Basis,
    pub velocity: Vector3,
}

impl Row {
    pub fn new(phase: i32, cradle_position: Vector3, cradle_basis: Basis, approach_m: f32, rest: Vector3) -> Self {
        Row {
            phase,
            age_s: 0.0,
            cradle_position,
            cradle_basis,
            approach_m,
            rest,
            start_position: Vector3::ZERO,
            start_basis: cradle_basis,
        }
    }

    /// The cradle takes the fighter from where it is (the carrier's frame).
    pub fn begin_capture(&mut self, position: Vector3, basis: Basis) {
        self.phase = PHASE_CAPTURE;
        self.age_s = 0.0;
        self.start_position = position;
        self.start_basis = basis;
    }
}

/// The fighter's origin in the carrier's frame when it sits `height_m` out from its pad.
pub fn docked_origin(row: &Row, height_m: f32) -> Vector3 {
    let out = col_b(&row.cradle_basis);
    sub(add(row.cradle_position, scale(out, height_m)), xform(&row.cradle_basis, row.rest))
}

/// The approach point in the carrier's frame: where a returning fighter is handed to the cradle.
pub fn approach_point(row: &Row) -> Vector3 {
    docked_origin(row, row.approach_m)
}

/// How far out a launching fighter is `age_s` into its launch, and how fast it moves out, m and m/s.
pub fn launch_profile(age_s: f64) -> (f64, f64) {
    let t = (age_s / LAUNCH_S).clamp(0.0, 1.0);
    (RELEASE_M * t * t, 2.0 * RELEASE_M * t / LAUNCH_S)
}

/// The share of a capture done `age_s` into it: quick at first, settling onto the pad.
pub fn capture_share(age_s: f64) -> f64 {
    let t = (age_s / CAPTURE_S).clamp(0.0, 1.0);
    1.0 - (1.0 - t) * (1.0 - t)
}

/// Where a returning fighter at `p` (the carrier's frame) flies to now: its approach point when that is on its side of
/// the carrier, else a point further round at `shell_m` from the centre, so its way never crosses the hull.
pub fn return_aim(row: &Row, p: Vector3, shell_m: f32) -> Vector3 {
    let goal = approach_point(row);
    let goal_dir = normalized(goal);
    let here = normalized(p);
    if length(p) < 1e-3 || dot(here, goal_dir) > DIRECT_COS {
        return goal;
    }
    let mut round = add(here, scale(goal_dir, 0.8));
    if length(round) < 0.2 {
        // Straight across the carrier from the cradle: any way round will do; take the one along the carrier's axis.
        round = add(here, col_c(&row.cradle_basis));
    }
    scale(normalized(round), shell_m.max(length(goal)))
}

/// The speed a returning fighter holds `distance_m` from where it is going, able to shed it with `brake_mps2`.
pub fn return_speed(distance_m: f64, brake_mps2: f64) -> f64 {
    (2.0 * BRAKE_SHARE * brake_mps2.max(0.1) * distance_m)
        .sqrt()
        .clamp(CREEP_MPS, RETURN_MPS)
}

// An attitude part way from `a` to `b`: the nose and the back blended and squared up again.
fn blend(a: &Basis, b: &Basis, t: f32) -> Basis {
    let back = normalized(add(scale(col_c(a), 1.0 - t), scale(col_c(b), t)));
    let up_raw = add(scale(col_b(a), 1.0 - t), scale(col_b(b), t));
    let right = normalized(cross(up_raw, back));
    let up = cross(back, right);
    Basis::from_cols(right, up, back)
}

/// One tick of one row. `position` and `velocity` are the fighter's (World); `brake_mps2` is what it can brake with;
/// `shell_m` is the radius a returning fighter keeps from the carrier's centre while it flies round.
pub fn step_row(row: &mut Row, carrier: &Carrier, position: Vector3, velocity: Vector3, brake_mps2: f32, shell_m: f32, delta: f64) -> Out {
    let out_axis = xform(&carrier.basis, col_b(&row.cradle_basis));
    let attitude = carrier.basis * row.cradle_basis;
    match row.phase {
        PHASE_LAUNCH => {
            row.age_s += delta;
            let (height, speed) = launch_profile(row.age_s);
            let local = docked_origin(row, height as f32);
            let offset = xform(&carrier.basis, local);
            Out {
                event: if row.age_s >= LAUNCH_S { EVENT_RELEASED } else { EVENT_NONE },
                position: add(carrier.position, offset),
                basis: attitude,
                velocity: add(add(carrier.velocity, cross(carrier.spin, offset)), scale(out_axis, speed as f32)),
            }
        }
        PHASE_CAPTURE => {
            row.age_s += delta;
            let share = capture_share(row.age_s) as f32;
            let goal = docked_origin(row, 0.0);
            let local = add(scale(row.start_position, 1.0 - share), scale(goal, share));
            let offset = xform(&carrier.basis, local);
            Out {
                event: if row.age_s >= CAPTURE_S { EVENT_DOCKED } else { EVENT_NONE },
                position: add(carrier.position, offset),
                basis: carrier.basis * blend(&row.start_basis, &row.cradle_basis, share),
                velocity: add(carrier.velocity, cross(carrier.spin, offset)),
            }
        }
        _ => {
            row.age_s += delta;
            let local = xform_inv(&carrier.basis, sub(position, carrier.position));
            let goal = approach_point(row);
            let aim = return_aim(row, local, shell_m);
            let aim_world = add(carrier.position, xform(&carrier.basis, aim));
            let to_aim = sub(aim_world, position);
            let to_goal = f64::from(length(sub(goal, local)));
            let offset = sub(position, carrier.position);
            let frame_velocity = add(carrier.velocity, cross(carrier.spin, offset));
            let relative = f64::from(length(sub(velocity, frame_velocity)));
            // On the way round it keeps its speed; only the last leg is flown to a stop.
            let last_leg = length(sub(aim, goal)) < 1e-3;
            let speed = if last_leg { return_speed(to_goal, f64::from(brake_mps2)) } else { return_speed(to_goal.max(400.0), f64::from(brake_mps2)) };
            let wanted = add(frame_velocity, scale(normalized(to_aim), speed as f32));
            Out {
                event: if to_goal < CAPTURE_RADIUS_M && relative < CAPTURE_MPS { EVENT_AT_APPROACH } else { EVENT_NONE },
                position: aim_world,
                basis: attitude,
                velocity: wanted,
            }
        }
    }
}

#[cfg(test)]
mod tests;
