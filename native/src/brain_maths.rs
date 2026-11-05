//! The brain maths (M4-T17a, docs/architecture.md 17.13): `PilotSteering`, `InterceptMath`, the `AiTemperament` tables,
//! the five `Manoeuvres`, Godot's `hash([seed, "label"])` and its `RandomNumberGenerator`, each repeated op for op so the
//! native brains roll, aim and steer the bits the GDScript brains do. Plain data in and out; no engine type beyond the two
//! maths builtins (the guard in `test_sim_core` reads this file).
use std::f64::consts::TAU;

use godot::builtin::{Basis, Vector3};

use crate::v3::{
    AXIS_SIGN, BACK, FORWARD, RIGHT, add, clampf, col_a, col_b, col_c, deg_to_rad, div_cw, div_s,
    dot, length, length_squared, lerpf, minf, mul_cw, neg, normalized, rad_to_deg, scale, signf,
    snappedf, sub, xform_inv,
};

// --- Godot's hash and random numbers ----------------------------------------------------------------------------------

const HASH_MURMUR3_SEED: u32 = 0x7F07C65;
// `Variant::Type::ARRAY`.
const VARIANT_ARRAY: u32 = 28;
const PCG_DEFAULT_INC: u64 = 1442695040888963407;
const PCG_MULT: u64 = 6364136223846793005;

/// `hash([seed, label])` as GDScript computes it: the Array hash over an int and a String.
pub fn hash_seed(seed: i64, label: &str) -> i64 {
    let mut h = murmur3_one_32(VARIANT_ARRAY, HASH_MURMUR3_SEED);
    h = murmur3_one_32(hash_one_uint64(seed as u64), h);
    h = murmur3_one_32(string_hash(label), h);
    i64::from(fmix32(h))
}

// `hash_one_uint64`.
fn hash_one_uint64(p_int: u64) -> u32 {
    let mut v = p_int;
    v = (!v).wrapping_add(v << 18);
    v ^= v >> 31;
    v = v.wrapping_mul(21);
    v ^= v >> 11;
    v = v.wrapping_add(v << 6);
    v ^= v >> 22;
    v as u32
}

// `String::hash()`: djb2 over the characters.
fn string_hash(text: &str) -> u32 {
    let mut h: u32 = 5381;
    for c in text.chars() {
        h = (h << 5).wrapping_add(h).wrapping_add(c as u32);
    }
    h
}

fn murmur3_one_32(mut p_in: u32, mut seed: u32) -> u32 {
    p_in = p_in.wrapping_mul(0xcc9e2d51);
    p_in = p_in.rotate_left(15);
    p_in = p_in.wrapping_mul(0x1b873593);
    seed ^= p_in;
    seed = seed.rotate_left(13);
    seed.wrapping_mul(5).wrapping_add(0xe6546b64)
}

fn fmix32(mut h: u32) -> u32 {
    h ^= h >> 16;
    h = h.wrapping_mul(0x85ebca6b);
    h ^= h >> 13;
    h = h.wrapping_mul(0xc2b2ae35);
    h ^= h >> 16;
    h
}

/// Godot's `RandomNumberGenerator` after `seed = value`: PCG32 with the engine's increment, `randf` from two draws.
#[derive(Clone, Copy, Debug, Default)]
pub struct Pcg {
    state: u64,
    inc: u64,
}

impl Pcg {
    pub fn seeded(seed: i64) -> Self {
        let mut rng = Pcg {
            state: 0,
            inc: (PCG_DEFAULT_INC << 1) | 1,
        };
        rng.next_u32();
        rng.state = rng.state.wrapping_add(seed as u64);
        rng.next_u32();
        rng
    }

    /// `randi()`: one 32-bit draw.
    pub fn randi(&mut self) -> u32 {
        self.next_u32()
    }

    fn next_u32(&mut self) -> u32 {
        let old = self.state;
        self.state = old.wrapping_mul(PCG_MULT).wrapping_add(self.inc);
        let xorshifted = (((old >> 18) ^ old) >> 27) as u32;
        let rot = (old >> 59) as u32;
        xorshifted.rotate_right(rot)
    }

    /// `randf()`: a float in 0..1 from the exponent of one draw and the mantissa of the next, its top and bottom bits set
    /// as the engine sets them (the bottom bit breaks the conversion's rounding ties upward).
    pub fn randf(&mut self) -> f32 {
        let proto_exp_offset = self.next_u32();
        if proto_exp_offset == 0 {
            return 0.0;
        }
        let mantissa = (self.next_u32() | 0x8000_0001) as f32;
        ldexpf(mantissa, -32 - proto_exp_offset.leading_zeros() as i32)
    }

    /// `randf_range(from, to)` in the engine's 32-bit arithmetic.
    pub fn randf_range(&mut self, from: f32, to: f32) -> f32 {
        self.randf() * (to - from) + from
    }
}

// `ldexpf`: an exact power-of-two scale (the exponents here keep the result normal).
fn ldexpf(x: f32, exp: i32) -> f32 {
    let mut value = x;
    let mut e = exp;
    while e < -126 {
        value *= f32::from_bits(1u32 << 23); // 2^-126
        e += 126;
    }
    value * f32::from_bits(((e + 127) as u32) << 23)
}

// --- the ship as the maths sees it -----------------------------------------------------------------------------------

/// `ShipCapability`: what the ship can do, in the terms a brain steers with.
#[derive(Clone, Copy, Debug, Default)]
pub struct Capability {
    pub a_main: f64,
    pub a_retro: f64,
    pub a_rcs_x: f64,
    pub a_rcs_y: f64,
    pub rate_max: Vector3,
    pub alpha_max: Vector3,
}

/// The flight half of a `PilotCommand`, as the brains fill it.
#[derive(Clone, Copy, Debug, Default)]
pub struct FlightCmd {
    pub main_left: f64,
    pub main_right: f64,
    pub retro_left: f64,
    pub retro_right: f64,
    pub strafe_x: f32,
    pub strafe_y: f32,
    pub rot: Vector3,
    pub brake: bool,
}

/// `PilotSteering.seek`'s answer: `{"main", "retro", "strafe"}`.
#[derive(Clone, Copy, Debug, Default)]
pub struct Seek {
    pub main: f64,
    pub retro: f64,
    pub strafe_x: f32,
    pub strafe_y: f32,
}

// --- PilotSteering -----------------------------------------------------------------------------------------------------

pub const K_FACE: f64 = 2.5;
pub const COAST_BELOW_MPS: f64 = 1.0;
pub const MAINS_CONE_DEG: f64 = 12.0;
pub const RETRO_CONE_DEG: f64 = 150.0;
#[allow(dead_code)] // the behaviours (T17b)
pub const HORIZON_S: f64 = 1.0;

/// `PilotSteering.angle_to`: the angle between the nose and `direction`, 0 for a zero direction.
pub fn angle_to(basis: &Basis, direction: Vector3) -> f64 {
    if f64::from(length_squared(direction)) < 1e-12 {
        return 0.0;
    }
    let d_b = xform_inv(basis, normalized(direction));
    f64::from(length(Vector3::new(d_b.y, -d_b.x, 0.0))).atan2(f64::from(-d_b.z))
}

/// `PilotSteering.face`: the pilot `rot` that turns the nose toward `direction`; no roll.
pub fn face(basis: &Basis, direction: Vector3, rate_max: Vector3, gain: f64) -> Vector3 {
    if f64::from(length_squared(direction)) < 1e-12 {
        return Vector3::ZERO;
    }
    let d_b = xform_inv(basis, normalized(direction));
    let mut axis = Vector3::new(d_b.y, -d_b.x, 0.0);
    let sin_angle = f64::from(length(axis));
    let angle = sin_angle.atan2(f64::from(-d_b.z));
    if sin_angle < 1e-6 {
        if -d_b.z > 0.0 {
            return Vector3::ZERO;
        }
        axis = Vector3::new(1.0, 0.0, 0.0);
    } else {
        axis = div_s(axis, sin_angle as f32);
    }
    let w_b = scale(axis, (gain * angle) as f32);
    let rot = div_cw(mul_cw(w_b, AXIS_SIGN), rate_max);
    Vector3::new(
        clampf(f64::from(rot.x), -1.0, 1.0) as f32,
        clampf(f64::from(rot.y), -1.0, 1.0) as f32,
        0.0,
    )
}

/// `PilotSteering.face_tracking`: `face` with the direction's own turn rate fed forward.
pub fn face_tracking(
    basis: &Basis,
    direction: Vector3,
    omega: Vector3,
    rate_max: Vector3,
    gain: f64,
) -> Vector3 {
    let rot = face(basis, direction, rate_max, gain);
    let w_ff = xform_inv(basis, omega);
    let ff = div_cw(
        mul_cw(Vector3::new(w_ff.x, w_ff.y, 0.0), AXIS_SIGN),
        rate_max,
    );
    Vector3::new(
        clampf(f64::from(rot.x) + f64::from(ff.x), -1.0, 1.0) as f32,
        clampf(f64::from(rot.y) + f64::from(ff.y), -1.0, 1.0) as f32,
        0.0,
    )
}

/// `PilotSteering.align_roll`: the pilot roll that turns the ship's top toward `up`.
pub fn align_roll(basis: &Basis, up: Vector3, rate_max: Vector3, gain: f64) -> f64 {
    let u_b = xform_inv(basis, up);
    let flat_sq = u_b.x * u_b.x + u_b.y * u_b.y;
    if f64::from(flat_sq) < 1e-12 {
        return 0.0;
    }
    let angle = f64::from(u_b.x).atan2(f64::from(u_b.y));
    if angle.abs() < 1e-9 {
        return 0.0;
    }
    let w_bz = -gain * angle;
    clampf(
        w_bz * f64::from(AXIS_SIGN.z) / f64::from(rate_max.z),
        -1.0,
        1.0,
    )
}

/// `PilotSteering.seek`: the thrust levels that move the velocity toward `v_des`.
pub fn seek(
    velocity: Vector3,
    v_des: Vector3,
    basis: &Basis,
    cap: &Capability,
    horizon_s: f64,
    all_axes: bool,
) -> Seek {
    let mut out = Seek::default();
    let dv = sub(v_des, velocity);
    let dv_len = f64::from(length(dv));
    if dv_len < COAST_BELOW_MPS {
        return out;
    }
    let dv_b = xform_inv(basis, dv);
    let angle_deg = if all_axes {
        0.0
    } else {
        rad_to_deg(f64::from(length(Vector3::new(dv_b.x, dv_b.y, 0.0))).atan2(f64::from(-dv_b.z)))
    };
    if all_axes || angle_deg < MAINS_CONE_DEG {
        out.main = clampf(f64::from(-dv_b.z) / (cap.a_main * horizon_s), 0.0, 1.0);
    }
    if all_axes || angle_deg > RETRO_CONE_DEG {
        out.retro = clampf(f64::from(dv_b.z) / (cap.a_retro * horizon_s), 0.0, 1.0);
    }
    out.strafe_x = clampf(f64::from(dv_b.x) / (cap.a_rcs_x * horizon_s), -1.0, 1.0) as f32;
    out.strafe_y = clampf(f64::from(dv_b.y) / (cap.a_rcs_y * horizon_s), -1.0, 1.0) as f32;
    out
}

/// `PilotSteering.lean_toward`: the nose nearest `base` from which the RCS and the pods together give `accel`.
pub fn lean_toward(base: Vector3, accel: Vector3, a_side: f64, max_lean_rad: f64) -> Vector3 {
    let along = f64::from(dot(accel, base));
    let side = sub(accel, scale(base, along as f32));
    let side_len = f64::from(length(side));
    if side_len <= a_side || side_len < 1e-9 {
        return base;
    }
    let amplitude = (side_len * side_len + along * along).sqrt();
    let mut lean = clampf(a_side / amplitude, 0.0, 1.0).acos() - along.abs().atan2(side_len);
    lean = clampf(lean, 0.0, max_lean_rad);
    let toward = if along >= 0.0 {
        div_s(side, side_len as f32)
    } else {
        div_s(neg(side), side_len as f32)
    };
    normalized(add(
        scale(base, lean.cos() as f32),
        scale(toward, lean.sin() as f32),
    ))
}

/// `PilotSteering.apply_seek`: both pods together, so they add no yaw.
pub fn apply_seek(cmd: &mut FlightCmd, result: &Seek) {
    cmd.main_left = result.main;
    cmd.main_right = result.main;
    cmd.retro_left = result.retro;
    cmd.retro_right = result.retro;
    cmd.strafe_x = result.strafe_x;
    cmd.strafe_y = result.strafe_y;
}

// --- InterceptMath -----------------------------------------------------------------------------------------------------

const LINEAR_EPSILON: f64 = 1e-9;

/// `InterceptMath.solve`'s answer.
#[derive(Clone, Copy, Debug)]
pub struct Lead {
    pub ok: bool,
    pub t: f64,
    pub aim_dir: Vector3,
    pub lead_point: Vector3,
}

/// `InterceptMath.solve`: when and where a bolt that inherits the shooter's velocity meets the target. The negated
/// comparisons are GDScript's: a NaN root is no solution.
#[allow(clippy::neg_cmp_op_on_partial_ord)]
pub fn solve(
    shooter_pos: Vector3,
    shooter_vel: Vector3,
    target_pos: Vector3,
    target_vel: Vector3,
    bolt_speed: f64,
    max_time: f64,
) -> Lead {
    let rx = f64::from(target_pos.x) - f64::from(shooter_pos.x);
    let ry = f64::from(target_pos.y) - f64::from(shooter_pos.y);
    let rz = f64::from(target_pos.z) - f64::from(shooter_pos.z);
    let ux = f64::from(target_vel.x) - f64::from(shooter_vel.x);
    let uy = f64::from(target_vel.y) - f64::from(shooter_vel.y);
    let uz = f64::from(target_vel.z) - f64::from(shooter_vel.z);
    let rr = rx * rx + ry * ry + rz * rz;
    let t = meeting_time(
        rr,
        rx * ux + ry * uy + rz * uz,
        ux * ux + uy * uy + uz * uz,
        bolt_speed,
    );
    if !(t > 0.0 && t <= max_time) {
        let mut sight = Vector3::ZERO;
        if rr > 0.0 {
            let l = rr.sqrt();
            sight = Vector3::new((rx / l) as f32, (ry / l) as f32, (rz / l) as f32);
        }
        return Lead {
            ok: false,
            t: -1.0,
            aim_dir: sight,
            lead_point: target_pos,
        };
    }
    let st = bolt_speed * t;
    let dx = (rx + ux * t) / st;
    let dy = (ry + uy * t) / st;
    let dz = (rz + uz * t) / st;
    let l = (dx * dx + dy * dy + dz * dz).sqrt();
    Lead {
        ok: true,
        t,
        aim_dir: Vector3::new((dx / l) as f32, (dy / l) as f32, (dz / l) as f32),
        lead_point: Vector3::new(
            (f64::from(target_pos.x) + ux * t) as f32,
            (f64::from(target_pos.y) + uy * t) as f32,
            (f64::from(target_pos.z) + uz * t) as f32,
        ),
    }
}

// The smallest positive root of `(uu - s^2) t^2 + 2 ru t + rr = 0`, or -1.
#[allow(clippy::neg_cmp_op_on_partial_ord)]
fn meeting_time(rr: f64, ru: f64, uu: f64, bolt_speed: f64) -> f64 {
    if !(bolt_speed > 0.0) || !(rr > 0.0) {
        return -1.0;
    }
    let qa = uu - bolt_speed * bolt_speed;
    let qb = 2.0 * ru;
    if qa.abs() <= LINEAR_EPSILON * bolt_speed * bolt_speed {
        return if qb < 0.0 { -rr / qb } else { -1.0 };
    }
    let disc = qb * qb - 4.0 * qa * rr;
    if !(disc >= 0.0) {
        return -1.0;
    }
    let root = disc.sqrt();
    let q = -0.5 * (if qb >= 0.0 { qb + root } else { qb - root });
    if q == 0.0 {
        return -1.0;
    }
    let mut best = -1.0;
    for candidate in [q / qa, rr / q] {
        if candidate > 0.0 && (best < 0.0 || candidate < best) {
            best = candidate;
        }
    }
    best
}

// --- AiTemperament -----------------------------------------------------------------------------------------------------

#[allow(dead_code)] // the behaviours (T17b)
pub const REGULAR: f64 = 0.45;
pub const BALANCED: f64 = 0.5;
#[allow(dead_code)] // the behaviours (T17b)
pub const PROVOKED_S: f64 = 10.0;

const AIM: [(f64, f64); 4] = [(0.2, 2.5), (0.45, 1.0), (0.7, 0.65), (0.95, 0.4)];
const REACTION: [(f64, f64); 4] = [(0.2, 0.6), (0.45, 0.25), (0.7, 0.17), (0.95, 0.1)];
const MISS: [(f64, f64); 4] = [(0.2, 1.6), (0.45, 1.0), (0.7, 0.8), (0.95, 0.6)];
const JINK: [(f64, f64); 4] = [(0.2, 1.3), (0.45, 1.0), (0.7, 0.85), (0.95, 0.7)];
const SPREAD: [(f64, f64); 4] = [(0.2, 20.0), (0.45, 45.0), (0.7, 62.0), (0.95, 80.0)];
const ATTACK_W: [(f64, f64); 5] = [
    (0.0, 0.6),
    (0.25, 0.85),
    (0.5, 1.0),
    (0.75, 1.15),
    (1.0, 1.3),
];
const EVADE_W: [(f64, f64); 5] = [
    (0.0, 1.3),
    (0.25, 1.15),
    (0.5, 1.0),
    (0.75, 0.8),
    (1.0, 0.5),
];
const RETREAT_W: [(f64, f64); 5] = [
    (0.0, 1.3),
    (0.25, 1.15),
    (0.5, 1.0),
    (0.75, 0.8),
    (1.0, 0.0),
];
const RETREAT_AT: [(f64, f64); 5] = [(0.0, 2.5), (0.25, 2.0), (0.5, 1.0), (0.75, 0.5), (1.0, 0.0)];
const SLASH: [(f64, f64); 4] = [(0.2, 1.0), (0.45, 0.8), (0.7, 0.65), (0.95, 0.5)];
const AWARE: [(f64, f64); 4] = [(0.2, 0.4), (0.45, 0.75), (0.7, 1.0), (0.95, 1.2)];
const PRESS: [(f64, f64); 5] = [(0.0, 1.2), (0.25, 1.1), (0.5, 1.0), (0.75, 0.9), (1.0, 0.8)];

/// `AiTemperament`: a pilot's skill and aggressiveness, 0..1 each.
#[derive(Clone, Copy, Debug)]
pub struct Temperament {
    pub skill: f64,
    pub aggression: f64,
}

impl Temperament {
    pub fn new(skill: f64, aggression: f64) -> Self {
        Temperament {
            skill: clampf(skill, 0.0, 1.0),
            aggression: clampf(aggression, 0.0, 1.0),
        }
    }

    pub fn aim_factor(&self) -> f64 {
        lerp_table(&AIM, self.skill)
    }

    pub fn reaction_s(&self) -> f64 {
        lerp_table(&REACTION, self.skill)
    }

    pub fn miss_factor(&self) -> f64 {
        lerp_table(&MISS, self.skill)
    }

    pub fn jink_factor(&self) -> f64 {
        lerp_table(&JINK, self.skill)
    }

    pub fn reversal_spread_deg(&self) -> f64 {
        lerp_table(&SPREAD, self.skill)
    }

    pub fn attack_weight_factor(&self) -> f64 {
        lerp_table(&ATTACK_W, self.aggression)
    }

    pub fn evade_weight_factor(&self) -> f64 {
        lerp_table(&EVADE_W, self.aggression)
    }

    pub fn retreat_weight_factor(&self) -> f64 {
        lerp_table(&RETREAT_W, self.aggression)
    }

    pub fn retreat_threshold_factor(&self) -> f64 {
        lerp_table(&RETREAT_AT, self.aggression)
    }

    pub fn press_factor(&self) -> f64 {
        lerp_table(&PRESS, self.aggression)
    }

    pub fn never_starts(&self) -> bool {
        self.aggression <= 0.0
    }

    pub fn may_ram(&self) -> bool {
        self.aggression >= 1.0
    }

    pub fn slash_chance(&self) -> f64 {
        lerp_table(&SLASH, self.skill)
    }

    pub fn close_pass_chance(&self) -> f64 {
        let t = clampf((self.aggression - BALANCED) / (1.0 - BALANCED), 0.0, 1.0);
        t * t
    }

    pub fn awareness(&self) -> f64 {
        lerp_table(&AWARE, self.skill)
    }

    /// `AiTemperament.apply` on one weight: scaled and kept within 0..1.
    pub fn weight(&self, base: f64, factor: f64) -> f64 {
        clampf(base * factor, 0.0, 1.0)
    }
}

// Piecewise-linear through the anchors, held flat beyond the first and last.
fn lerp_table(table: &[(f64, f64)], x: f64) -> f64 {
    if x <= table[0].0 {
        return table[0].1;
    }
    for i in 1..table.len() {
        let x1 = table[i].0;
        if x <= x1 {
            let x0 = table[i - 1].0;
            let t = (x - x0) / (x1 - x0);
            return lerpf(table[i - 1].1, table[i].1, t);
        }
    }
    table[table.len() - 1].1
}

// --- Manoeuvres --------------------------------------------------------------------------------------------------------

/// What a manoeuvre reads of a tick's perception.
#[derive(Clone, Copy, Debug)]
pub struct Pose {
    pub now_s: f64,
    pub position: Vector3,
    pub basis: Basis,
    pub velocity: Vector3,
    pub angular: Vector3,
    pub origin: [f64; 3],
}

impl Pose {
    /// `Perception.to_local`: a universe point as a World-local point this tick, the subtraction in 64 bits.
    pub fn local_of(&self, point: [f64; 3]) -> Vector3 {
        Vector3::new(
            (point[0] - self.origin[0]) as f32,
            (point[1] - self.origin[1]) as f32,
            (point[2] - self.origin[2]) as f32,
        )
    }

    /// `UniversePos.plus_local` from this tick's origin.
    pub fn universe_of(&self, local: Vector3) -> [f64; 3] {
        [
            self.origin[0] + f64::from(local.x),
            self.origin[1] + f64::from(local.y),
            self.origin[2] + f64::from(local.z),
        ]
    }

    /// `Perception.forward()`: the nose, `-basis.z`.
    pub fn forward(&self) -> Vector3 {
        neg(col_c(&self.basis))
    }
}

/// `Manoeuvres.NAMES`, by kind index.
pub const MANOEUVRE_NAMES: [&str; 5] = [
    "roll",
    "flip_and_burn",
    "strafe_box",
    "pod_turn",
    "all_stop",
];
pub const TIMEOUT_S: f64 = 45.0;

/// One demo move's state (`Manoeuvre` and the five `Manoeuvres`): a state machine on the measured state.
#[derive(Clone, Debug)]
pub struct Manoeuvre {
    pub kind: u8,
    pub done: bool,
    pub timed_out: bool,
    pub elapsed_s: f64,
    pub desired_velocity: Vector3,
    pub has_desired_velocity: bool,
    started: bool,
    // roll
    rolled_rad: f64,
    last_rate: f64,
    // flip and burn
    burning: bool,
    speed0_mps: f64,
    flip_s: f64,
    burn_s: f64,
    retro: Vector3,
    velocity: Vector3,
    // strafe box
    legs_m: Vec<f64>,
    closure_m: f64,
    start: [f64; 3],
    t0: f64,
    v0: Vector3,
    forward: Vector3,
    corners: [Vector3; 4],
    last_corner: Vector3,
    // pod turn
    yaw_deg: f64,
    forward0: Vector3,
    right0: Vector3,
    // all stop
    speed_mps: f64,
    rate_dps: f64,
}

/// A manoeuvre's measured outcome, as `result()` reports it (`legs_m` for the box, else empty).
#[derive(Clone, Debug, Default)]
pub struct Outcome {
    pub keys: Vec<&'static str>,
    pub values: Vec<f64>,
    pub flags: Vec<(&'static str, bool)>,
    pub ints: Vec<(&'static str, i64)>,
    pub legs_m: Option<Vec<f64>>,
}

impl Manoeuvre {
    /// A fresh move by kind (`MANOEUVRE_NAMES` index), or none for an unknown kind.
    pub fn create(kind: u8) -> Option<Self> {
        if usize::from(kind) >= MANOEUVRE_NAMES.len() {
            return None;
        }
        Some(Manoeuvre {
            kind,
            done: false,
            timed_out: false,
            elapsed_s: 0.0,
            desired_velocity: Vector3::ZERO,
            has_desired_velocity: false,
            started: false,
            rolled_rad: 0.0,
            last_rate: 0.0,
            burning: false,
            speed0_mps: 0.0,
            flip_s: 0.0,
            burn_s: 0.0,
            retro: BACK,
            velocity: Vector3::ZERO,
            legs_m: Vec::new(),
            closure_m: -1.0,
            start: [0.0; 3],
            t0: 0.0,
            v0: Vector3::ZERO,
            forward: FORWARD,
            corners: [Vector3::ZERO; 4],
            last_corner: Vector3::ZERO,
            yaw_deg: 0.0,
            forward0: FORWARD,
            right0: RIGHT,
            speed_mps: -1.0,
            rate_dps: -1.0,
        })
    }

    /// `Manoeuvre.needs_speed`: the move takes speed away, so it is shown from cruise.
    #[allow(dead_code)] // the follow-path behaviour (T17b)
    pub fn needs_speed(&self) -> bool {
        self.kind == 1 || self.kind == 4
    }

    /// `Manoeuvre.step`: one tick; coasts once done.
    pub fn step(&mut self, p: &Pose, cap: &Capability, dt: f64) -> FlightCmd {
        self.has_desired_velocity = false;
        if self.done {
            return FlightCmd::default();
        }
        if !self.started {
            self.started = true;
            self.begin(p);
            if self.done {
                return FlightCmd::default();
            }
        } else {
            self.elapsed_s += dt;
        }
        if self.elapsed_s >= TIMEOUT_S {
            self.done = true;
            self.timed_out = true;
            return FlightCmd::default();
        }
        match self.kind {
            0 => self.step_roll(p, cap, dt),
            1 => self.step_flip(p, cap),
            2 => self.step_box(p, cap),
            3 => self.step_pod_turn(p),
            _ => self.step_all_stop(p),
        }
    }

    /// `Manoeuvre.state_name` (the console's `step`).
    #[allow(dead_code)] // the follow-path behaviour (T17b)
    pub fn state_name(&self) -> String {
        if self.done {
            return "done".to_string();
        }
        match self.kind {
            0 => {
                if TAU - self.rolled_rad > deg_to_rad(90.0) {
                    "rolling".to_string()
                } else {
                    "stopping".to_string()
                }
            }
            1 => {
                if self.burning {
                    "burn".to_string()
                } else {
                    "flip".to_string()
                }
            }
            2 => ["right", "up", "left", "down"][self.legs_m.len().min(3)].to_string(),
            3 => "left main".to_string(),
            _ => "brake".to_string(),
        }
    }

    /// `Manoeuvre.result`: the measured outcome so far, `timed_out` included.
    pub fn result(&self) -> Outcome {
        let mut out = Outcome::default();
        match self.kind {
            0 => out.put("roll_deg", snappedf(rad_to_deg(self.rolled_rad), 0.01)),
            1 => {
                let along = if self.speed0_mps >= 2.0 {
                    f64::from(dot(self.velocity, neg(self.retro)))
                } else {
                    f64::from(length(self.velocity))
                };
                out.put("speed0_mps", snappedf(self.speed0_mps, 0.001));
                out.put(
                    "speed_mps",
                    snappedf(f64::from(length(self.velocity)), 0.001),
                );
                out.put("along_mps", snappedf(along, 0.001));
                out.flags.push(("reversed", along < 0.0));
                out.put("flip_s", snappedf(self.flip_s, 0.01));
                out.put("burn_s", snappedf(self.burn_s, 0.01));
            }
            2 => {
                out.legs_m = Some(self.legs_m.iter().map(|&l| snappedf(l, 0.01)).collect());
                out.ints.push(("legs_done", self.legs_m.len() as i64));
                out.put("closure_m", snappedf(self.closure_m, 0.01));
            }
            3 => out.put("yaw_deg", snappedf(self.yaw_deg, 0.01)),
            _ => {
                out.put("speed_mps", snappedf(self.speed_mps, 0.001));
                out.put("rate_dps", snappedf(self.rate_dps, 0.001));
            }
        }
        out.flags.push(("timed_out", self.timed_out));
        out
    }

    fn begin(&mut self, p: &Pose) {
        match self.kind {
            0 => self.last_rate = roll_rate(p),
            1 => {
                self.velocity = p.velocity;
                self.speed0_mps = f64::from(length(p.velocity));
                if self.speed0_mps < 2.0 {
                    self.done = true;
                    return;
                }
                self.retro = div_s(neg(p.velocity), self.speed0_mps as f32);
            }
            2 => {
                self.start = p.universe_of(p.position);
                self.t0 = p.now_s;
                self.v0 = p.velocity;
                self.forward = p.forward();
                let right = scale(col_a(&p.basis), 50.0);
                let up = scale(col_b(&p.basis), 50.0);
                self.corners = [right, add(right, up), up, Vector3::ZERO];
            }
            3 => {
                self.forward0 = p.forward();
                self.right0 = col_a(&p.basis);
            }
            _ => {}
        }
    }

    fn step_roll(&mut self, p: &Pose, cap: &Capability, dt: f64) -> FlightCmd {
        let rate = roll_rate(p);
        if self.elapsed_s > 0.0 {
            self.rolled_rad += 0.5 * (rate + self.last_rate) * dt;
        }
        self.last_rate = rate;
        let left = TAU - self.rolled_rad;
        let mut cmd = FlightCmd::default();
        if left.abs() < deg_to_rad(1.0) && rate.abs() < deg_to_rad(5.0) {
            self.done = true;
            return cmd;
        }
        let limit = f64::from(cap.rate_max.z);
        let stop = (2.0 * 0.5 * f64::from(cap.alpha_max.z) * left.abs()).sqrt();
        let w = signf(left) * minf(limit, minf(K_FACE * left.abs(), stop));
        cmd.rot = Vector3::new(0.0, 0.0, clampf(w / limit, -1.0, 1.0) as f32);
        cmd
    }

    fn step_flip(&mut self, p: &Pose, cap: &Capability) -> FlightCmd {
        self.velocity = p.velocity;
        let mut cmd = FlightCmd::default();
        if self.burning
            && (f64::from(length(p.velocity)) < 2.0
                || f64::from(dot(p.velocity, neg(self.retro))) < 0.0)
        {
            self.done = true;
            return cmd;
        }
        cmd.rot = face(&p.basis, self.retro, cap.rate_max, K_FACE);
        if !self.burning {
            self.flip_s = self.elapsed_s;
            if rad_to_deg(angle_to(&p.basis, self.retro)) >= 3.0 {
                return cmd;
            }
            self.burning = true;
        }
        self.burn_s = self.elapsed_s - self.flip_s;
        self.seek_to(&mut cmd, p, cap, Vector3::ZERO, 0.2);
        cmd
    }

    /// `StrafeBox.offset`: where the ship is against the start point moving on at the starting velocity.
    fn box_offset(&self, p: &Pose) -> Vector3 {
        sub(
            sub(p.position, p.local_of(self.start)),
            scale(self.v0, (p.now_s - self.t0) as f32),
        )
    }

    fn step_box(&mut self, p: &Pose, cap: &Capability) -> FlightCmd {
        let rel = self.box_offset(p);
        let mut cmd = FlightCmd::default();
        let leg = self.legs_m.len();
        let mut to = sub(self.corners[leg], rel);
        if f64::from(length(to)) < 2.0 && f64::from(length(sub(p.velocity, self.v0))) < 1.0 {
            self.legs_m
                .push(f64::from(length(sub(rel, self.last_corner))));
            self.last_corner = rel;
            if self.legs_m.len() == self.corners.len() {
                self.done = true;
                self.closure_m = f64::from(length(rel));
                return cmd;
            }
            to = sub(self.corners[self.legs_m.len()], rel);
        }
        let d = f64::from(length(to));
        let speed = minf(
            15.0,
            (2.0 * 0.8 * minf(cap.a_rcs_x, cap.a_rcs_y) * d).sqrt(),
        );
        let v_rel = if d > 1e-6 {
            scale(div_s(to, d as f32), speed as f32)
        } else {
            Vector3::ZERO
        };
        cmd.rot = face(&p.basis, self.forward, cap.rate_max, K_FACE);
        self.seek_to(&mut cmd, p, cap, add(self.v0, v_rel), 0.15);
        cmd
    }

    fn step_pod_turn(&mut self, p: &Pose) -> FlightCmd {
        let nose = p.forward();
        self.yaw_deg = rad_to_deg(
            f64::from(dot(nose, self.right0)).atan2(f64::from(dot(nose, self.forward0))),
        );
        let mut cmd = FlightCmd::default();
        if self.yaw_deg > 30.0 {
            self.done = true;
            return cmd;
        }
        cmd.main_left = 1.0;
        cmd
    }

    fn step_all_stop(&mut self, p: &Pose) -> FlightCmd {
        self.speed_mps = f64::from(length(p.velocity));
        self.rate_dps = rad_to_deg(f64::from(length(p.angular)));
        let mut cmd = FlightCmd::default();
        if self.speed_mps < 0.5 && self.rate_dps < 1.0 {
            self.done = true;
            return cmd;
        }
        cmd.brake = true;
        cmd
    }

    // `Manoeuvre._seek`: the thrust toward `v_des`, recorded as this tick's wish.
    fn seek_to(
        &mut self,
        cmd: &mut FlightCmd,
        p: &Pose,
        cap: &Capability,
        v_des: Vector3,
        horizon_s: f64,
    ) {
        self.desired_velocity = v_des;
        self.has_desired_velocity = true;
        apply_seek(
            cmd,
            &seek(p.velocity, v_des, &p.basis, cap, horizon_s, false),
        );
    }
}

impl Outcome {
    fn put(&mut self, key: &'static str, value: f64) {
        self.keys.push(key);
        self.values.push(value);
    }
}

/// `Manoeuvre.roll_rate`: the roll rate in pilot terms (+ = rolling right), measured from the perception.
pub fn roll_rate(p: &Pose) -> f64 {
    f64::from(xform_inv(&p.basis, p.angular).z) * f64::from(AXIS_SIGN.z)
}

/// `[deg_to_rad(x), rad_to_deg(x), lerpf(x, b, t)]`, for the differential test of the engine's helpers.
pub fn deg_to_rad_lerp(x: f64, b: f64, t: f64) -> [f64; 3] {
    [deg_to_rad(x), rad_to_deg(x), lerpf(x, b, t)]
}

/// `clampf(v, 0, 1)`.
pub fn clamp01(v: f64) -> f64 {
    clampf(v, 0.0, 1.0)
}
