// The attitude a capital fights in (D12.10): the way its own hull should face the target so the most mount dps bears on
// it, broadside for a turret ship, bow-on for fixed bow guns, belly-on where the guns sit below. A mount bears along a
// direction when that direction lies inside its cone and its own hull does not stand in the way (worked out once against
// the hull's own volumes).
use godot::builtin::{Basis, Vector3};

use crate::rows::Surface;
use crate::surface;
use crate::v3::{add, cross, dot, length, neg, normalized, rotated, scale, xform};

use super::{CapitalSpec, Memory, Tuning};

const S2: f32 = std::f32::consts::FRAC_1_SQRT_2;
const S3: f32 = 0.577_350_26;

/// The attitudes weighed, in the ship's own frame: the target dead ahead first, then abeam, below, above, astern, then the
/// twelve edges and eight corners between them. Ties go to the earlier one.
pub const DIRECTIONS: [Vector3; 26] = [
    Vector3::new(0.0, 0.0, -1.0),
    Vector3::new(1.0, 0.0, 0.0),
    Vector3::new(-1.0, 0.0, 0.0),
    Vector3::new(0.0, -1.0, 0.0),
    Vector3::new(0.0, 1.0, 0.0),
    Vector3::new(0.0, 0.0, 1.0),
    Vector3::new(S2, 0.0, -S2),
    Vector3::new(-S2, 0.0, -S2),
    Vector3::new(0.0, -S2, -S2),
    Vector3::new(0.0, S2, -S2),
    Vector3::new(S2, -S2, 0.0),
    Vector3::new(-S2, -S2, 0.0),
    Vector3::new(S2, S2, 0.0),
    Vector3::new(-S2, S2, 0.0),
    Vector3::new(S2, 0.0, S2),
    Vector3::new(-S2, 0.0, S2),
    Vector3::new(0.0, -S2, S2),
    Vector3::new(0.0, S2, S2),
    Vector3::new(S3, S3, -S3),
    Vector3::new(-S3, S3, -S3),
    Vector3::new(S3, -S3, -S3),
    Vector3::new(-S3, -S3, -S3),
    Vector3::new(S3, S3, S3),
    Vector3::new(-S3, S3, S3),
    Vector3::new(S3, -S3, S3),
    Vector3::new(-S3, -S3, S3),
];

// How far out a mount's line along a direction is tested against its own hull, m, and how far off its base it starts.
const LINE_M: f32 = 2000.0;
const LIFT_M: f32 = 2.0;
// A mount's weight on a target out of its reach: it still bears once the range closes.
const OUT_OF_REACH: f64 = 0.25;

/// Each mount's bearings, one bit per `DIRECTIONS` entry: inside its cone and, with the hull's own volumes, clear of them.
pub fn bearings(spec: &CapitalSpec, own: Option<&Surface>) -> Vec<u32> {
    spec.mounts
        .iter()
        .map(|m| {
            let mut bits = 0u32;
            let from = add(m.at, scale(m.axis, LIFT_M));
            for (k, d) in DIRECTIONS.iter().enumerate() {
                if dot(*d, m.axis) < m.cos_half {
                    continue;
                }
                let blocked = own.is_some_and(|s| {
                    let to = add(from, scale(*d, LINE_M));
                    surface::enters_from_outside(s, wide(from), wide(to))
                });
                if !blocked {
                    bits |= 1 << k;
                }
            }
            bits
        })
        .collect()
}

/// The attitude toward a target `to_target` away (World), as an index of `DIRECTIONS`, and the heading and top that bring
/// the ship's hull round to it from `basis` by the shortest turn. The held attitude stays unless another brings `margin` more.
pub fn choose(
    spec: &CapitalSpec,
    memory: &Memory,
    basis: &Basis,
    to_target: Vector3,
    held: u8,
    t: &Tuning,
) -> (u8, Vector3, Vector3) {
    let range_m = f64::from(length(to_target));
    let mut scores = [0.0f64; DIRECTIONS.len()];
    for (i, m) in spec.mounts.iter().enumerate() {
        if !m.fights() {
            continue;
        }
        let bits = memory.bearings.get(i).copied().unwrap_or_else(|| cone_bits(m.axis, m.cos_half));
        let weight = m.dps * if m.range_m >= range_m { 1.0 } else { OUT_OF_REACH };
        for (k, s) in scores.iter_mut().enumerate() {
            if bits & (1 << k) != 0 {
                *s += weight;
            }
        }
    }
    let top = scores.iter().copied().fold(0.0, f64::max);
    let held = usize::from(held).min(DIRECTIONS.len() - 1);
    // Of the attitudes that bring nearly the most to bear (a flank and its mirror), the one the hull turns to soonest; the
    // held one while it is still among them.
    let want = unit_or(to_target, nose(basis));
    let mut best = held;
    if scores[held] * t.attitude_margin < top || top <= 0.0 {
        let mut least = f32::INFINITY;
        for (k, &score) in scores.iter().enumerate() {
            if score * t.attitude_margin < top {
                continue;
            }
            let turn = 1.0 - dot(normalized(xform(basis, DIRECTIONS[k])), want);
            if turn < least {
                least = turn;
                best = k;
            }
        }
    }
    let (heading, up) = heading_for(basis, DIRECTIONS[best], to_target);
    // Bow-on and stern-on attitudes leave the roll alone: every top serves.
    let up = if best == 0 || best == 5 { Vector3::ZERO } else { up };
    (best as u8, heading, up)
}

/// The heading (the bow's World direction) and top that turn the ship's own `local` axis onto `to_target` by the shortest
/// turn of the whole hull.
pub fn heading_for(basis: &Basis, local: Vector3, to_target: Vector3) -> (Vector3, Vector3) {
    let nose = nose(basis);
    let top = normalized(xform(basis, Vector3::new(0.0, 1.0, 0.0)));
    let want = unit_or(to_target, nose);
    let have = normalized(xform(basis, local));
    let axis = cross(have, want);
    let sin = length(axis);
    let cos = dot(have, want);
    if sin < 1e-6 {
        if cos > 0.0 {
            return (nose, top);
        }
        // Exactly the wrong way: half a turn about the ship's own up.
        return (rotated(nose, top, std::f32::consts::PI), top);
    }
    let (axis, angle) = (scale(axis, 1.0 / sin), sin.atan2(cos));
    (rotated(nose, axis, angle), rotated(top, axis, angle))
}

/// The bow's World direction.
pub fn nose(basis: &Basis) -> Vector3 {
    neg(Vector3::new(basis.rows[0].z, basis.rows[1].z, basis.rows[2].z))
}

/// `v` as a unit vector, or `fallback` when it is too short to have a direction.
pub fn unit_or(v: Vector3, fallback: Vector3) -> Vector3 {
    if length(v) > 1e-6 { normalized(v) } else { fallback }
}

// The bits of every direction inside a cone, for a mount whose hull lines are not worked out yet.
fn cone_bits(axis: Vector3, cos_half: f32) -> u32 {
    let mut bits = 0u32;
    for (k, d) in DIRECTIONS.iter().enumerate() {
        if dot(*d, axis) >= cos_half {
            bits |= 1 << k;
        }
    }
    bits
}

fn wide(v: Vector3) -> [f64; 3] {
    [f64::from(v.x), f64::from(v.y), f64::from(v.z)]
}
