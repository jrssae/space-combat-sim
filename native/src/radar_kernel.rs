// The player's radar sphere (M4-T23, docs/architecture.md 17.21): `RadarModel.plot`'s maths over packed contacts, in the
// same steps and precision as the GDScript it replaced, so the HUD's thousand-contact frame at `battle` 1 000 costs a native
// pass instead of a GDScript loop. Engine-free: plain columns in, plain columns out; `radar_plot.rs` is its shell.
use godot::builtin::{Basis, Color, Vector2, Vector3};

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
    /// 1 for a contact too far to identify (M5-T25): beyond the identification range with no transponder.
    pub unknown: Vec<u8>,
    pub units: Vec<(f32, f32)>,
    pub feet: Vec<(f32, f32)>,
    pub selected: i32,
    // Scratch kept between plots (code review, M5-T47): every contact's point and range, and the sort keys.
    scratch_points: Vec<Vector3>,
    scratch_ranges: Vec<f64>,
    scratch_keys: Vec<i64>,
}

impl Plot {
    // Empties the plot for the next frame, keeping every buffer's capacity.
    fn clear(&mut self) {
        self.order.clear();
        self.points.clear();
        self.ranges.clear();
        self.rims.clear();
        self.unknown.clear();
        self.units.clear();
        self.feet.clear();
        self.selected = -1;
    }
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
/// A contact beyond `ident_range_m` that does not broadcast is flagged unknown, except `known_id` (a selection the
/// pilot has already identified). Returns false, with an empty plot, when the three contact columns differ in length
/// (code review, M5-T47: a short column must not silently drop contacts).
#[allow(clippy::too_many_arguments)]
pub fn plot(
    ids: &[i64],
    positions: &[Vector3],
    reach: &[f64],
    own_position: Vector3,
    own_basis: &Basis,
    selected_id: i64,
    ident_range_m: f64,
    known_id: i64,
    out: &mut Plot,
) -> bool {
    out.clear();
    let n = ids.len();
    if positions.len() != n || reach.len() != n {
        return false;
    }
    let mut points = std::mem::take(&mut out.scratch_points);
    let mut ranges = std::mem::take(&mut out.scratch_ranges);
    let mut keys = std::mem::take(&mut out.scratch_keys);
    points.clear();
    points.resize(n, Vector3::ZERO);
    ranges.clear();
    ranges.resize(n, 0.0);
    keys.clear();
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
    for &key in &keys {
        let i = (key & INDEX_MASK) as usize;
        let point = points[i];
        out.order.push(i as u32);
        out.points.push(point);
        out.ranges.push(ranges[i]);
        out.rims.push(u8::from(ranges[i] > MAX_RANGE_M));
        out.unknown
            .push(u8::from(ranges[i] > ident_range_m && reach[i] <= 0.0 && ids[i] != known_id));
        out.units.push(to_unit(point));
        out.feet.push(to_unit(Vector3::new(point.x, point.y, 0.0)));
    }
    if selected_at >= 0 {
        out.selected = out.order.len() as i32 - 1;
    }
    out.scratch_points = points;
    out.scratch_ranges = ranges;
    out.scratch_keys = keys;
    true
}

/// Floats per instance of a 2D multimesh with colours: a 2x3 transform padded to 8, then the colour.
pub const DOT_STRIDE: usize = 12;

/// Instances in the three dot multimeshes for one frame's plot.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct DotCounts {
    pub plain: usize,
    pub rim: usize,
    pub backing: usize,
}

/// How many dots of each kind a plot of `rims` draws: a backing under every contact (when asked), and one plain or hollow
/// dot for every contact but the selected one, which the painter draws itself.
pub fn dot_counts(rims: &[u8], selected: i32, backings: bool) -> DotCounts {
    let n = rims.len();
    let rim_total = rims.iter().filter(|&&r| r == 1).count();
    let selected_is_rim = usize::try_from(selected).ok().and_then(|i| rims.get(i)).map(|&r| r == 1);
    let (mut plain, mut rim) = (n - rim_total, rim_total);
    match selected_is_rim {
        Some(true) => rim -= 1,
        Some(false) => plain -= 1,
        None => {}
    }
    DotCounts {
        plain,
        rim,
        backing: if backings { n } else { 0 },
    }
}

/// The multimesh size for `count` dots when it holds `held` now: unchanged while it is big enough, else doubled or the count
/// (it grows rarely and never shrinks); nothing to hold for no dots.
pub fn grown_capacity(held: usize, count: usize) -> usize {
    if count == 0 {
        0
    } else if count <= held {
        held
    } else {
        count.max(held * 2)
    }
}

// One instance: a uniform scale of `radius` at `p`, in `colour`.
fn put_dot(out: &mut [f32], p: Vector2, radius: f32, colour: Color) {
    out[..DOT_STRIDE].copy_from_slice(&[
        radius, 0.0, 0.0, p.x, 0.0, radius, 0.0, p.y, colour.r, colour.g, colour.b, colour.a,
    ]);
}

/// The multimesh buffers of a plot's dots on a screen radar of `radius_px` at `centre`, as the painter draws them: every
/// contact's dark backing (`backing`, when it is sized), the plain dots in their colours and the hollow rim ones, both
/// without the selected contact. The slices are `DOT_STRIDE` floats per instance, sized by `dot_counts` or larger (the tail
/// stays as it was).
#[allow(clippy::too_many_arguments)]
pub fn fill_dots(
    units: &[Vector2],
    colours: &[Color],
    rims: &[u8],
    selected: i32,
    centre: Vector2,
    radius_px: f32,
    sizes: (f32, f32),
    backing_colour: Color,
    plain: &mut [f32],
    rim: &mut [f32],
    backing: &mut [f32],
) {
    let (backing_radius, radius) = sizes;
    let (mut plain_at, mut rim_at, mut backing_at) = (0, 0, 0);
    for (i, u) in units.iter().enumerate().take(colours.len().min(rims.len())) {
        let p = Vector2::new(u.x * radius_px + centre.x, u.y * radius_px + centre.y);
        if backing_at + DOT_STRIDE <= backing.len() {
            put_dot(&mut backing[backing_at..], p, backing_radius, backing_colour);
            backing_at += DOT_STRIDE;
        }
        if i as i32 == selected {
            continue;
        }
        if rims[i] == 1 {
            put_dot(&mut rim[rim_at..], p, radius, colours[i]);
            rim_at += DOT_STRIDE;
        } else {
            put_dot(&mut plain[plain_at..], p, radius, colours[i]);
            plain_at += DOT_STRIDE;
        }
    }
}

#[cfg(test)]
mod tests;
