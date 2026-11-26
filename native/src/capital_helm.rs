//! A capital ship's helm (M10-T16, Q70; it was T07's GDScript `CapitalHelm`): it holds a heading and a wanted velocity and
//! gives the flight step the command a pilot would. One per ship (it remembers a flip under way); stepped every tick on the
//! main thread from the core's rows, so the brain (5 Hz, in the AI job) only moves its heading and velocity.
//!
//! - A gravitic hull, or a reaction hull with retros, keeps its bow on the heading and pushes along every axis it has.
//! - A reaction hull with no retros cannot push backward: when it must slow by more than `FLIP_ENTER_MPS` it turns toward
//!   the velocity change, burns its mains, and turns back to its heading once the change is met.
//! - Turns are paced so the hull can stop on the heading with the torque it has (a 300 m hull turns slowly and must not
//!   swing past). A half turn is flown as a turn about the hull's own up, not a loop over its back.
//! - It keeps the hull level, its top on the World's up, unless told another top (an attitude that brings a flank's mounts to
//!   bear), so no turn leaves it rolled.
//!
//! Engine-free (the guard in test_sim_core reads this file): plain numbers in and out.
use godot::builtin::{Basis, Vector3};

use crate::brain_maths::{self, Capability, FlightCmd};
use crate::v3::{UP, col_a, col_c, dot, length, length_squared, maxf, minf, neg, normalized, scale, sub, xform_inv};

/// Mid-flip below this much velocity change left, m/s, the helm turns back; above `FLIP_ENTER_MPS` aft it starts a flip.
pub const FLIP_EXIT_MPS: f64 = 0.5;
pub const FLIP_ENTER_MPS: f64 = 3.0;
/// The velocity error is met in about this long at full thrust, s: gentle, as a big hull's helm is.
pub const HORIZON_S: f64 = 4.0;
/// The share of the turn rate a hull could still stop from that the helm asks for.
pub const TURN_MARGIN: f64 = 0.7;

/// What a hull's helm steers: its drive and what the drive can do.
#[derive(Clone, Copy, Debug, Default)]
pub struct HelmSpec {
    pub gravitic: bool,
    pub retros: bool,
    pub cap: Capability,
}

/// What the helm is told and what it remembers: the way the bow should point (World, unit; zero holds the bow where it is),
/// the velocity to hold (World frame, m/s), the way the ship's top should face (World, unit; zero: level, M10-T16: an attitude
/// that brings a flank's mounts to bear), whether it levels the hull at all (`level`: every ship's helm; off only for the parity
/// probe of T07's helm, which never rolled), and whether a hull with no retros is turned to burn against its motion.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Helm {
    pub heading: Vector3,
    pub velocity: Vector3,
    pub up: Vector3,
    pub level: bool,
    pub flipping: bool,
}

/// The bow within this of dead astern (cosine) turns about the hull's own up: a half turn is a turn, not a loop.
const HALF_TURN_COS: f32 = -0.98;
/// A bow within this of the World's up or down (cosine of the angle) has no level to hold.
const NO_LEVEL_COS: f32 = 0.95;

/// This tick's command for a hull at `basis` moving at `current` (World frame); the flip state moves on in `helm`.
pub fn command(spec: &HelmSpec, helm: &mut Helm, basis: &Basis, current: Vector3) -> FlightCmd {
    let mut cmd = FlightCmd::default();
    let dv = sub(helm.velocity, current);
    let nose = neg(col_c(basis));
    let aft_need = -f64::from(dot(dv, nose));
    if spec.retros {
        helm.flipping = false;
    } else if helm.flipping {
        helm.flipping = f64::from(length(dv)) > FLIP_EXIT_MPS;
    } else {
        helm.flipping = aft_need > FLIP_ENTER_MPS;
    }
    let face = if helm.flipping {
        dv
    } else if f64::from(length_squared(helm.heading)) > 1e-12 {
        helm.heading
    } else {
        nose
    };
    cmd.rot = turn(spec, basis, face, helm.level);
    if !helm.flipping
        && let Some(up) = top_wanted(helm, nose)
    {
        cmd.rot.z = roll(spec, basis, up) as f32;
    }
    let mut seek = brain_maths::seek(current, helm.velocity, basis, &spec.cap, HORIZON_S, !helm.flipping);
    if !spec.retros {
        seek.retro = 0.0;
    }
    brain_maths::apply_seek(&mut cmd, &seek);
    cmd
}

// The top the hull should roll onto: the one it is told, else level (the World's up square to the bow); none when it does
// not level or its bow points along the World's up.
fn top_wanted(helm: &Helm, nose: Vector3) -> Option<Vector3> {
    if f64::from(length_squared(helm.up)) > 1e-12 {
        return Some(helm.up);
    }
    if !helm.level || dot(nose, UP).abs() > NO_LEVEL_COS {
        return None;
    }
    Some(normalized(sub(UP, scale(nose, dot(nose, UP)))))
}

// Pilot `rot` toward `direction`, slowed so the hull can stop on it with the torque it has. Dead astern a levelling helm
// turns toward its own right first (about its own up), so a half turn keeps it level.
fn turn(spec: &HelmSpec, basis: &Basis, direction: Vector3, level: bool) -> Vector3 {
    let direction = if level && dot(normalized(direction), neg(col_c(basis))) < HALF_TURN_COS {
        col_a(basis)
    } else {
        direction
    };
    let angle = brain_maths::angle_to(basis, direction);
    if angle < 1e-6 {
        return Vector3::ZERO;
    }
    let cap = &spec.cap;
    let alpha = minf(f64::from(cap.alpha_max.x), f64::from(cap.alpha_max.y));
    let gain = minf(brain_maths::K_FACE, TURN_MARGIN * (2.0 * maxf(alpha, 1e-9) / angle).sqrt());
    brain_maths::face(basis, direction, cap.rate_max, gain)
}

// Pilot roll toward `up`, slowed as a turn is so the hull can stop on it.
fn roll(spec: &HelmSpec, basis: &Basis, up: Vector3) -> f64 {
    let u_b = xform_inv(basis, up);
    let angle = f64::from(u_b.x).atan2(f64::from(u_b.y)).abs();
    if angle < 1e-6 {
        return 0.0;
    }
    let alpha = f64::from(spec.cap.alpha_max.z);
    let gain = minf(brain_maths::K_FACE, TURN_MARGIN * (2.0 * maxf(alpha, 1e-9) / angle).sqrt());
    brain_maths::align_roll(basis, up, spec.cap.rate_max, gain)
}

#[cfg(test)]
mod tests;
