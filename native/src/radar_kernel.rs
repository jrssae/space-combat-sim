// The player's radar sphere (M4-T23, docs/architecture.md 17.21): `RadarModel.plot`'s maths over packed contacts, in the
// same steps and precision as the GDScript it replaced, so the HUD's thousand-contact frame at `battle` 1 000 costs a native
// pass instead of a GDScript loop. Engine-free: plain columns in, plain columns out; `radar_plot.rs` is its shell.
use godot::builtin::{Basis, Vector3};

use crate::v3::{length_squared, xform_inv};

/// `RadarModel`'s constants.
pub const MAX_RANGE_M: f64 = 25000.0;
pub const LINEAR_RANGE_M: f64 = 5000.0;
pub const LINEAR_RADIUS: f64 = 0.6;
pub const TILT_RAD: f64 = 0.35;
pub const PERSPECTIVE: f64 = 0.18;
const INDEX_BITS: i64 = 20;
const INDEX_MASK: i64 = (1 << INDEX_BITS) - 1;
const RANGE_KEYS: i64 = 1 << 42;
const RANGE_CAP_M: f64 = 4.0e9;

/// One frame's plot: the contacts drawn (as indices into the input, far to near, the selected one last) and, per drawn
/// contact, its point on the sphere, its range, whether it sits on the rim, and its point and stalk foot on a unit radar.
#[derive(Default)]
pub struct Plot {
    pub order: Vec<u32>,
    pub points: Vec<Vector3>,
    pub ranges: Vec<f64>,
    pub rims: Vec<u8>,
    pub units: Vec<(f32, f32)>,
    pub feet: Vec<(f32, f32)>,
    pub selected: i32,
}

/// The sphere radius (0..1) for a range: linear to `LINEAR_RADIUS` at 5 km, logarithmic to 1 at 25 km, clamped beyond.
pub fn radius_for_range(range_m: f64) -> f64 {
    if range_m <= 0.0 {
        return 0.0;
    }
    if range_m <= LINEAR_RANGE_M {
        return LINEAR_RADIUS * range_m / LINEAR_RANGE_M;
    }
    let t = (range_m.min(MAX_RANGE_M) / LINEAR_RANGE_M).ln() / (MAX_RANGE_M / LINEAR_RANGE_M).ln();
    LINEAR_RADIUS + (1.0 - LINEAR_RADIUS) * t
}

/// `RadarModel.to_screen` on a unit radar at the origin.
pub fn to_unit(point: Vector3) -> (f32, f32) {
    let (x, y, z) = (f64::from(point.x), f64::from(point.y), f64::from(point.z));
    let up = y * TILT_RAD.cos() + z * TILT_RAD.sin();
    let depth = z * TILT_RAD.cos() - y * TILT_RAD.sin();
    let scale = 1.0 + PERSPECTIVE * depth;
    ((x * scale) as f32, (-up * scale) as f32)
}

// `TargetingSystem.range_between`: 64-bit.
fn range_between(from: Vector3, to: Vector3) -> f64 {
    let dx = f64::from(to.x) - f64::from(from.x);
    let dy = f64::from(to.y) - f64::from(from.y);
    let dz = f64::from(to.z) - f64::from(from.z);
    (dx * dx + dy * dy + dz * dz).sqrt()
}

/// `RadarModel.plot` without the colours: every contact (`ids`, World `positions`, broadcast `reach`) within
/// `MAX_RANGE_M` of a ship at `own_position` with attitude `own_basis`, or within its own reach (then on the rim).
pub fn plot(
    ids: &[i64],
    positions: &[Vector3],
    reach: &[f64],
    own_position: Vector3,
    own_basis: &Basis,
    selected_id: i64,
    out: &mut Plot,
) {
    *out = Plot {
        selected: -1,
        ..Plot::default()
    };
    let n = ids.len().min(positions.len()).min(reach.len());
    let mut points = vec![Vector3::ZERO; n];
    let mut ranges = vec![0.0; n];
    let mut keys: Vec<i64> = Vec::with_capacity(n);
    let mut selected_at: i64 = -1;
    for i in 0..n {
        let at = positions[i];
        let range_m = range_between(own_position, at);
        if range_m > MAX_RANGE_M && range_m > reach[i] {
            continue;
        }
        let rel = Vector3::new(
            at.x - own_position.x,
            at.y - own_position.y,
            at.z - own_position.z,
        );
        let body = xform_inv(own_basis, rel);
        let d = Vector3::new(body.x, -body.z, body.y);
        let d = if f64::from(length_squared(d)) > 1e-12 {
            let l = length_squared(d).sqrt();
            Vector3::new(d.x / l, d.y / l, d.z / l)
        } else {
            Vector3::ZERO
        };
        let radius = if range_m >= MAX_RANGE_M {
            1.0
        } else {
            radius_for_range(range_m)
        } as f32;
        points[i] = Vector3::new(d.x * radius, d.y * radius, d.z * radius);
        ranges[i] = range_m;
        if ids[i] == selected_id {
            selected_at = i as i64;
            continue;
        }
        // Farthest first: the key grows as the range shrinks; equal millimetres keep the contacts' order.
        let mm = (range_m.min(RANGE_CAP_M) * 1000.0) as i64;
        keys.push(((RANGE_KEYS - mm) << INDEX_BITS) | i as i64);
    }
    keys.sort_unstable();
    if selected_at >= 0 {
        keys.push(selected_at);
    }
    for key in keys {
        let i = (key & INDEX_MASK) as usize;
        let point = points[i];
        out.order.push(i as u32);
        out.points.push(point);
        out.ranges.push(ranges[i]);
        out.rims.push(u8::from(ranges[i] > MAX_RANGE_M));
        out.units.push(to_unit(point));
        out.feet.push(to_unit(Vector3::new(point.x, point.y, 0.0)));
    }
    if selected_at >= 0 {
        out.selected = out.order.len() as i32 - 1;
    }
}
