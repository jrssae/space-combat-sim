// A carrier's docking (M12-T19, docs/architecture.md 19.18): how its fighters leave a cradle, fly back to one and are drawn
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
//
// M10-T17: a bay of a capital carrier is a row too (`Row::bay`). Its fighter sits in the hall facing out of the mouth, and its
// launch runs along the bay's `out_axis` (not up off a pad) far enough to clear the mouth, at the cradle's acceleration. A bay
// with a lift (the Nova's hidden elevator) adds three phases: LIFT carries the fighter up from the hangar deck to the bay's floor
// before its launch; after a capture it waits on the floor (HOLD) until the lift is ready, and LOWER takes it down.
use godot::builtin::{Basis, Vector3};

use crate::v3::{add, col_b, col_c, cross, dot, length, normalized, scale, sub, xform, xform_inv};

pub const PHASE_LAUNCH: i32 = 0;
pub const PHASE_RETURN: i32 = 1;
pub const PHASE_CAPTURE: i32 = 2;
pub const PHASE_LIFT: i32 = 3;
pub const PHASE_LOWER: i32 = 4;
pub const PHASE_HOLD: i32 = 5;

pub const EVENT_NONE: i32 = 0;
/// The launch is over: the fighter flies on its own from `Out.position` with `Out.velocity`.
pub const EVENT_RELEASED: i32 = 1;
/// A returning fighter reached its approach point slowly enough: the cradle may take it (`Row::begin_capture`).
pub const EVENT_AT_APPROACH: i32 = 2;
/// The capture is over: the fighter sits on its pad (in a bay with a lift: down on the hangar deck).
pub const EVENT_DOCKED: i32 = 3;
/// The lift reached the bay's floor: the fighter's launch run begins and the lift is free to go down again.
pub const EVENT_LIFTED: i32 = 4;
/// A capture into a bay with a lift is over: the fighter waits on the floor for `Row::begin_lower`.
pub const EVENT_IN_BAY: i32 = 5;

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
/// A bay's lift takes this long to rise or sink its whole travel, s.
pub const LIFT_S: f64 = 4.0;
/// A fighter drawn into a bay enters no faster than this, so a long hall takes longer than a cradle's capture, m/s.
pub const BAY_ENTRY_MPS: f64 = 30.0;

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
    /// The way a launch leaves and a return comes in, the carrier's frame: a cradle's +Y, a bay's mouth.
    pub out_axis: Vector3,
    /// How far a launch pushes before it lets go, m, and how far below the floor a bay's lift starts, m (0: no lift).
    pub launch_m: f64,
    pub lift_m: f32,
    /// How long this row's capture takes, s (set when it begins).
    pub capture_s: f64,
    pub bay: bool,
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
            out_axis: col_b(&cradle_basis),
            launch_m: RELEASE_M,
            lift_m: 0.0,
            capture_s: CAPTURE_S,
            bay: false,
        }
    }

    /// A bay's row: the fighter rests at `position` (its floor point, the carrier's frame) with attitude `basis`, leaves along
    /// `out_axis` for `launch_m` and comes back to `approach_m` out along it; a lift starts it `lift_m` below the floor. A
    /// launch with a lift starts in LIFT whatever `phase` asks.
    #[allow(clippy::too_many_arguments)]
    pub fn bay(phase: i32, position: Vector3, basis: Basis, out_axis: Vector3, approach_m: f32, launch_m: f64, lift_m: f32, rest: Vector3) -> Self {
        let mut row = Row::new(phase, position, basis, approach_m, rest);
        row.out_axis = normalized(out_axis);
        row.launch_m = launch_m.max(1.0);
        row.lift_m = lift_m.max(0.0);
        row.bay = true;
        if phase == PHASE_LAUNCH && row.lift_m > 0.0 {
            row.phase = PHASE_LIFT;
        }
        row
    }

    /// The cradle takes the fighter from where it is (the carrier's frame). A bay's long hall is entered at a walk.
    pub fn begin_capture(&mut self, position: Vector3, basis: Basis) {
        self.phase = PHASE_CAPTURE;
        self.age_s = 0.0;
        self.start_position = position;
        self.start_basis = basis;
        self.capture_s = if self.bay {
            CAPTURE_S.max(2.0 * f64::from(length(sub(position, docked_origin(self, 0.0)))) / BAY_ENTRY_MPS)
        } else {
            CAPTURE_S
        };
    }

    /// The lift takes a fighter waiting on the bay's floor down to the hangar deck.
    pub fn begin_lower(&mut self) {
        if self.phase == PHASE_HOLD {
            self.phase = PHASE_LOWER;
            self.age_s = 0.0;
        }
    }

    /// How long this row's launch pushes, s: a longer push at the cradle's acceleration.
    pub fn launch_s(&self) -> f64 {
        LAUNCH_S * (self.launch_m / RELEASE_M).sqrt()
    }
}

/// The fighter's origin in the carrier's frame when it sits `height_m` out from its pad (along its bay's way out).
pub fn docked_origin(row: &Row, height_m: f32) -> Vector3 {
    sub(add(row.cradle_position, scale(row.out_axis, height_m)), xform(&row.cradle_basis, row.rest))
}

/// The fighter's origin while a lift has it `below_m` under the bay's floor.
fn lift_origin(row: &Row, below_m: f32) -> Vector3 {
    sub(docked_origin(row, 0.0), scale(col_b(&row.cradle_basis), below_m))
}

/// How far up its travel a lift is `age_s` after it set off (0 the deck, 1 the floor), easing in and out.
pub fn lift_share(age_s: f64) -> f64 {
    let t = (age_s / LIFT_S).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// The approach point in the carrier's frame: where a returning fighter is handed to the cradle.
pub fn approach_point(row: &Row) -> Vector3 {
    docked_origin(row, row.approach_m)
}

/// How far out a fighter launching `distance_m` over `time_s` is `age_s` into its launch, and how fast it moves out, m and m/s.
pub fn launch_profile_over(age_s: f64, distance_m: f64, time_s: f64) -> (f64, f64) {
    let t = (age_s / time_s).clamp(0.0, 1.0);
    (distance_m * t * t, 2.0 * distance_m * t / time_s)
}

/// The share of a capture of `time_s` done `age_s` into it: quick at first, settling onto the pad.
pub fn capture_share_over(age_s: f64, time_s: f64) -> f64 {
    let t = (age_s / time_s).clamp(0.0, 1.0);
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
        round = add(here, if row.bay { col_b(&row.cradle_basis) } else { col_c(&row.cradle_basis) });
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
    let out_axis = xform(&carrier.basis, row.out_axis);
    let attitude = carrier.basis * row.cradle_basis;
    let ride = |offset: Vector3| add(carrier.velocity, cross(carrier.spin, offset));
    match row.phase {
        PHASE_LIFT | PHASE_LOWER => {
            row.age_s += delta;
            let share = lift_share(row.age_s);
            let up = if row.phase == PHASE_LIFT { share } else { 1.0 - share };
            let below = row.lift_m * (1.0 - up as f32);
            let offset = xform(&carrier.basis, lift_origin(row, below));
            // The lift's speed: the ease's slope over its travel.
            let t = (row.age_s / LIFT_S).clamp(0.0, 1.0);
            let rate = (6.0 * t * (1.0 - t) / LIFT_S) as f32 * row.lift_m;
            let lift_axis = xform(&carrier.basis, col_b(&row.cradle_basis));
            let climb = if row.phase == PHASE_LIFT { rate } else { -rate };
            let done = row.age_s >= LIFT_S;
            let event = match (done, row.phase) {
                (true, PHASE_LIFT) => EVENT_LIFTED,
                (true, _) => EVENT_DOCKED,
                _ => EVENT_NONE,
            };
            if done && row.phase == PHASE_LIFT {
                row.phase = PHASE_LAUNCH;
                row.age_s = 0.0;
            }
            Out {
                event,
                position: add(carrier.position, offset),
                basis: attitude,
                velocity: add(ride(offset), scale(lift_axis, climb)),
            }
        }
        PHASE_HOLD => {
            row.age_s += delta;
            let offset = xform(&carrier.basis, docked_origin(row, 0.0));
            Out {
                event: EVENT_NONE,
                position: add(carrier.position, offset),
                basis: attitude,
                velocity: ride(offset),
            }
        }
        PHASE_LAUNCH => {
            row.age_s += delta;
            let time_s = row.launch_s();
            let (height, speed) = launch_profile_over(row.age_s, row.launch_m, time_s);
            let local = docked_origin(row, height as f32);
            let offset = xform(&carrier.basis, local);
            Out {
                event: if row.age_s >= time_s { EVENT_RELEASED } else { EVENT_NONE },
                position: add(carrier.position, offset),
                basis: attitude,
                velocity: add(add(carrier.velocity, cross(carrier.spin, offset)), scale(out_axis, speed as f32)),
            }
        }
        PHASE_CAPTURE => {
            row.age_s += delta;
            let share = capture_share_over(row.age_s, row.capture_s) as f32;
            let goal = docked_origin(row, 0.0);
            let local = add(scale(row.start_position, 1.0 - share), scale(goal, share));
            let offset = xform(&carrier.basis, local);
            let done = row.age_s >= row.capture_s;
            let lifted = row.lift_m > 0.0;
            if done && lifted {
                // Into the bay: it waits on the floor for the lift.
                row.phase = PHASE_HOLD;
                row.age_s = 0.0;
            }
            Out {
                event: match (done, lifted) {
                    (true, true) => EVENT_IN_BAY,
                    (true, false) => EVENT_DOCKED,
                    _ => EVENT_NONE,
                },
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
