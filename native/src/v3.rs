//! Godot's 32-bit vector and basis maths, op for op (M4-T17; the one home of what the kernels copied three times). Every
//! function repeats the engine's order of operations with no fused multiply-add, so a kernel that uses them gives the bits
//! GDScript gives. The 64-bit scalar helpers are Godot's `clampf`, `minf`, `maxf`, `signf`, `lerpf`, `snappedf` and the
//! angle conversions with their exact comparisons. No engine type beyond the two maths builtins.
use std::f64::consts::PI;

use godot::builtin::{Basis, Vector3};

/// Pilot axes (pitch up, yaw right, roll right) to body axes, as `FlightModel.AXIS_SIGN`.
pub const AXIS_SIGN: Vector3 = Vector3::new(1.0, -1.0, -1.0);
/// Godot's `CMP_EPSILON` as `is_zero_approx` applies it to 32-bit components.
pub const CMP_EPSILON: f32 = 0.00001;
pub const UP: Vector3 = Vector3::new(0.0, 1.0, 0.0);
pub const RIGHT: Vector3 = Vector3::new(1.0, 0.0, 0.0);
pub const FORWARD: Vector3 = Vector3::new(0.0, 0.0, -1.0);
pub const BACK: Vector3 = Vector3::new(0.0, 0.0, 1.0);

pub fn add(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x + b.x, a.y + b.y, a.z + b.z)
}

pub fn sub(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x - b.x, a.y - b.y, a.z - b.z)
}

pub fn neg(a: Vector3) -> Vector3 {
    Vector3::new(-a.x, -a.y, -a.z)
}

/// `Vector3 * Vector3`, component by component.
pub fn mul_cw(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x * b.x, a.y * b.y, a.z * b.z)
}

/// `Vector3 / Vector3`, component by component.
pub fn div_cw(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x / b.x, a.y / b.y, a.z / b.z)
}

/// `Vector3 * float`: the float is rounded to 32 bits first, as the engine does.
pub fn scale(a: Vector3, s: f32) -> Vector3 {
    Vector3::new(a.x * s, a.y * s, a.z * s)
}

/// `Vector3 / float`, the float rounded to 32 bits first.
pub fn div_s(a: Vector3, s: f32) -> Vector3 {
    Vector3::new(a.x / s, a.y / s, a.z / s)
}

pub fn dot(a: Vector3, b: Vector3) -> f32 {
    a.x * b.x + a.y * b.y + a.z * b.z
}

pub fn cross(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    )
}

pub fn length_squared(a: Vector3) -> f32 {
    let x2 = a.x * a.x;
    let y2 = a.y * a.y;
    let z2 = a.z * a.z;
    x2 + y2 + z2
}

pub fn length(a: Vector3) -> f32 {
    length_squared(a).sqrt()
}

/// `a.distance_squared_to(b)`.
pub fn dist_sq(a: Vector3, b: Vector3) -> f32 {
    length_squared(sub(b, a))
}

/// `a.distance_to(b)`.
#[allow(dead_code)] // the behaviours (T17b)
pub fn distance(a: Vector3, b: Vector3) -> f32 {
    length(sub(b, a))
}

/// `Vector3.normalized()`: divide by the length, zero stays zero.
pub fn normalized(a: Vector3) -> Vector3 {
    let length_sq = length_squared(a);
    if length_sq == 0.0 {
        return Vector3::ZERO;
    }
    let l = length_sq.sqrt();
    Vector3::new(a.x / l, a.y / l, a.z / l)
}

/// `Vector3.limit_length(len)`: shortened to `len` when longer, in the engine's two steps.
#[allow(dead_code)] // the behaviours (T17b)
pub fn limit_length(a: Vector3, len: f32) -> Vector3 {
    let l = length(a);
    let mut v = a;
    if l > 0.0 && len < l {
        v = div_s(v, l);
        v = scale(v, len);
    }
    v
}

/// `Vector3.min` and `max`, component by component.
pub fn min_cw(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x.min(b.x), a.y.min(b.y), a.z.min(b.z))
}

pub fn max_cw(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x.max(b.x), a.y.max(b.y), a.z.max(b.z))
}

/// `Vector3.clamp(lo, hi)`, component by component, with the engine's exact comparisons.
pub fn clamp_cw(a: Vector3, lo: Vector3, hi: Vector3) -> Vector3 {
    let c = |v: f32, lo: f32, hi: f32| {
        if v < lo {
            lo
        } else if v > hi {
            hi
        } else {
            v
        }
    };
    Vector3::new(c(a.x, lo.x, hi.x), c(a.y, lo.y, hi.y), c(a.z, lo.z, hi.z))
}

pub fn is_zero_approx(a: Vector3) -> bool {
    a.x.abs() < CMP_EPSILON && a.y.abs() < CMP_EPSILON && a.z.abs() < CMP_EPSILON
}

/// `Basis * Vector3`: each row dotted with the vector.
pub fn xform(b: &Basis, v: Vector3) -> Vector3 {
    Vector3::new(dot(b.rows[0], v), dot(b.rows[1], v), dot(b.rows[2], v))
}

/// `Basis.transposed() * Vector3`: each column dotted with the vector.
pub fn xform_inv(b: &Basis, v: Vector3) -> Vector3 {
    Vector3::new(dot(col_a(b), v), dot(col_b(b), v), dot(col_c(b), v))
}

/// The basis columns: `basis.x`, `basis.y` and `basis.z` as GDScript reads them.
pub fn col_a(b: &Basis) -> Vector3 {
    Vector3::new(b.rows[0].x, b.rows[1].x, b.rows[2].x)
}

pub fn col_b(b: &Basis) -> Vector3 {
    Vector3::new(b.rows[0].y, b.rows[1].y, b.rows[2].y)
}

pub fn col_c(b: &Basis) -> Vector3 {
    Vector3::new(b.rows[0].z, b.rows[1].z, b.rows[2].z)
}

/// `Vector3.rotated(axis, angle)`: the engine's axis-angle basis applied to `v`, in 32 bits.
pub fn rotated(v: Vector3, axis: Vector3, angle: f32) -> Vector3 {
    let (x, y, z) = (axis.x, axis.y, axis.z);
    let sq = Vector3::new(x * x, y * y, z * z);
    let cosine = angle.cos();
    let r00 = sq.x + cosine * (1.0 - sq.x);
    let r11 = sq.y + cosine * (1.0 - sq.y);
    let r22 = sq.z + cosine * (1.0 - sq.z);
    let sine = angle.sin();
    let t = 1.0 - cosine;
    let (xyzt, zyxs) = (x * y * t, z * sine);
    let (r01, r10) = (xyzt - zyxs, xyzt + zyxs);
    let (xyzt, zyxs) = (x * z * t, y * sine);
    let (r02, r20) = (xyzt + zyxs, xyzt - zyxs);
    let (xyzt, zyxs) = (y * z * t, x * sine);
    let (r12, r21) = (xyzt - zyxs, xyzt + zyxs);
    Vector3::new(
        dot(Vector3::new(r00, r01, r02), v),
        dot(Vector3::new(r10, r11, r12), v),
        dot(Vector3::new(r20, r21, r22), v),
    )
}

// --- Godot's 64-bit scalar helpers with their exact comparisons --------------------------------------------------------

pub fn clampf(v: f64, lo: f64, hi: f64) -> f64 {
    if v < lo {
        lo
    } else if v > hi {
        hi
    } else {
        v
    }
}

pub fn minf(a: f64, b: f64) -> f64 {
    if a < b { a } else { b }
}

pub fn maxf(a: f64, b: f64) -> f64 {
    if a > b { a } else { b }
}

pub fn signf(v: f64) -> f64 {
    if v > 0.0 {
        1.0
    } else if v < 0.0 {
        -1.0
    } else {
        0.0
    }
}

/// `lerpf(a, b, t)`: `a + (b - a) * t`.
pub fn lerpf(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

/// `deg_to_rad`: the engine multiplies by the factor `PI / 180`.
pub fn deg_to_rad(deg: f64) -> f64 {
    deg * (PI / 180.0)
}

/// `rad_to_deg`: the engine multiplies by the factor `180 / PI`.
pub fn rad_to_deg(rad: f64) -> f64 {
    rad * (180.0 / PI)
}

/// `snappedf(value, step)`: the engine's `floor(value / step + 0.5) * step`.
pub fn snappedf(value: f64, step: f64) -> f64 {
    if step != 0.0 {
        return (value / step + 0.5).floor() * step;
    }
    value
}
