//! The constants the native code mirrors from GDScript (M5-T36, L13), as one table: `ScsSimCore.constants()` hands it to
//! GDScript, and `tests/unit/test_native_constants.gd` compares every entry with its GDScript twin, so a change on one
//! side fails the test. A key is `Class.CONST`; a second Rust copy of the same twin adds `@<module>`; `#size` means the
//! twin's array size.
use godot::builtin::Vector3;

use crate::{bolt_kernels as bolt, brain, brain_behaviours, kernels, tier_fire, v3, voice_kernels, weapon_kernels as weapon};

/// One number: `(key, value)`.
pub fn numbers() -> Vec<(&'static str, f64)> {
    vec![
        ("PulseCannonGate.TIME_EPSILON_S@bolt_kernels", bolt::TIME_EPSILON_S),
        ("PulseCannonGate.TIME_EPSILON_S@weapon_kernels", weapon::TIME_EPSILON_S),
        ("WeaponCapacitor.CHARGE_EPSILON", bolt::CHARGE_EPSILON),
        ("BoltSlotQuarantine.MAX_STEP_M", bolt::QUARANTINE_MAX_STEP_M),
        ("BoltSlotQuarantine.SIDE_SLACK_M", bolt::QUARANTINE_SIDE_SLACK_M),
        ("BoltSlotQuarantine.SIDE_SLACK_SHARE", bolt::QUARANTINE_SIDE_SLACK_SHARE),
        ("ContactScan.SENSOR_RANGE_M", brain::SENSOR_RANGE_M),
        ("AiPilot.TIE_ORDER#size", brain_behaviours::KINDS as f64),
        ("RamResolver.MARGIN_M", kernels::ram::MARGIN_M),
        ("RamResolver.SWEEP_CULL_PAD_M", kernels::ram::SWEEP_CULL_PAD_M),
        ("FlightAssist.FACE_DECEL_FRACTION", kernels::flight::FACE_DECEL_FRACTION),
        ("FireLane.CLEARANCE_M", kernels::pilot::CLEARANCE_M),
        ("TurretStandin.RANGE_M", weapon::RANGE_M),
        ("TurretStandin.INTERCEPT_RANGE_M@weapon_kernels", weapon::INTERCEPT_RANGE_M),
        ("TurretStandin.INTERCEPT_RANGE_M@tier_fire", tier_fire::INTERCEPT_RANGE_M),
        ("TurretStandin.TURN_RATE_RAD_S", weapon::TURN_RATE_RAD_S),
        ("TurretStandin.GATE_RAD", weapon::GATE_RAD),
        ("TurretStandin.FIGHTER_RADIUS_MAX_M", weapon::FIGHTER_RADIUS_MAX_M),
        ("TurretStandin.MUZZLE_SPEED_MPS", weapon::MUZZLE_SPEED_MPS),
        ("TurretStandin.BOLT_LIFETIME_S", weapon::BOLT_LIFETIME_S),
        ("TurretStandin.RETARGET_TICKS", weapon::RETARGET_TICKS as f64),
        ("TurretStandin.SHOT_INTERVAL_S", weapon::SHOT_INTERVAL_S),
        ("InterceptMath.LINEAR_EPSILON", weapon::LINEAR_EPSILON),
        ("BeamStandin.RANGE_M", weapon::BEAM_RANGE_M),
        ("MissileStandin.RANGE_M@weapon_kernels", weapon::STRIKE_RANGE_M),
        ("MissileStandin.RANGE_M@tier_fire", tier_fire::STRIKE_RANGE_M),
        ("StandinDirector.STRIKE_RETARGET_TICKS", weapon::STRIKE_RETARGET_TICKS as f64),
        ("MineStandin.TRIGGER_RADIUS_M", weapon::TRIGGER_RADIUS_M),
        ("MineStandin.BLAST_RADIUS_M", weapon::BLAST_RADIUS_M),
        ("MineStandin.TRIGGER_TICKS", weapon::TRIGGER_TICKS as f64),
        ("BodyKind.SHIP@voice_kernels", f64::from(voice_kernels::KIND_SHIP)),
        ("BodyKind.MINE@brain", f64::from(brain::KIND_MINE)),
        ("BodyKind.STATIC@brain", f64::from(brain::KIND_STATIC)),
    ]
}

/// The one vector: `FlightModel.AXIS_SIGN`.
pub fn axis_sign() -> Vector3 {
    v3::AXIS_SIGN
}
