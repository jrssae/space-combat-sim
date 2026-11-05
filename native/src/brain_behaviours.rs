//! The AI pilot's behaviours in native code (M4-T17b, docs/architecture.md 17.13): `AiContext.refresh`, the scoring and
//! selection of `AiPilot`, and the nine behaviours with `AttackBrain` and `AttackSlash`, as a pure function of the core's
//! frozen rows and one ship's state. Plain data in and out; no engine type (the guard in `test_sim_core` reads this file).
//! T17a lays down the per-ship constants; the behaviours follow in T17b.
#![allow(dead_code)]
use godot::builtin::Vector3;

use crate::brain_maths::Capability;

/// A ship's constants as its brain needs them: the capability, where the bolts leave (ship frame), the weapon's muzzle
/// speed and lifetime, the hull's bounding radius, and the avoidance tie-break (`hash(display_name)`).
#[derive(Clone, Copy, Debug, Default)]
pub struct Ship {
    pub capability: Capability,
    pub muzzle_local: Vector3,
    pub muzzle_speed_mps: f64,
    pub weapon_lifetime_s: f64,
    pub radius: f64,
    pub tie_hash: i64,
}
