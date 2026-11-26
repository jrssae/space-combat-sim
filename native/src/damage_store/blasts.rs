// The blast model's landing maths (M10-T76, Q70, D12.6): the falloff, the damage and the push a blast gives a hull, the nearest
// point of a fighter's hit volumes, and which hulls a blast lands on once each. `BlastResolver` did this in GDScript a hull at a
// time; the batch (`blast_batch.rs`) now lands every blast and its chain on the damage store, and this is its engine-free part.
// Every step repeats GDScript's order of operations (`BlastSpec`, `HitShape.nearest_point`, `BlastResolver.nearest_on`), so the
// numbers are the bits GDScript gave.
// A blast's numbers are tested as GDScript tests them, `not (x > 0.0)`, so NaN is nothing.
#![allow(clippy::neg_cmp_op_on_partial_ord)]
use godot::builtin::{Basis, Vector3};

use crate::v3::{add, affine_inverse_xform, clamp_cw, clampf, distance, length, maxf, minf, neg, scale, sub, xform};

/// One blast: damage at the centre, radius, push impulse per square metre at the centre, and the push's cap (m/s).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Spec {
    pub d0: f64,
    pub radius: f64,
    pub impulse: f64,
    pub cap: f64,
}

/// The curve `(1 - (d/R)^2)^2`: 1 at the centre (or inside a hull), 0 at the radius and beyond.
pub fn falloff(distance: f64, radius: f64) -> f64 {
    if !(radius > 0.0) || !(distance < radius) {
        return 0.0;
    }
    let x = maxf(distance, 0.0) / radius;
    let k = 1.0 - x * x;
    k * k
}

impl Spec {
    /// Hull points a hull whose nearest hit volume is `distance` away takes.
    pub fn damage_at(&self, distance: f64) -> f64 {
        self.d0 * falloff(distance, self.radius)
    }

    /// The speed a hull of `mass` with a mean box face of `area` gains `distance` away, capped.
    pub fn push_at(&self, distance: f64, area: f64, mass: f64) -> f64 {
        if !(mass > 0.0) {
            return 0.0;
        }
        minf(self.impulse * falloff(distance, self.radius) * maxf(area, 0.0) / mass, self.cap)
    }
}

/// One hit volume of a fighter in its body frame, as `HitShape` holds it: a box or a capsule (axis on its own Y), placed by
/// `basis` and `origin`, with the inverse the engine computed for it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Shape {
    pub capsule: bool,
    pub basis: Basis,
    pub origin: Vector3,
    pub inv_basis: Basis,
    pub inv_origin: Vector3,
    pub half: Vector3,
    pub radius: f64,
    pub half_segment: f64,
}

/// Numbers a shape packs into: capsule, basis rows (9), origin (3), the inverse's rows (9) and origin (3), half extents (3),
/// radius, half segment.
pub const SHAPE_LEN: usize = 30;

impl Shape {
    /// From `SHAPE_LEN` numbers.
    pub fn unpack(s: &[f64]) -> Option<Shape> {
        if s.len() < SHAPE_LEN {
            return None;
        }
        let v = |at: usize| Vector3::new(s[at] as f32, s[at + 1] as f32, s[at + 2] as f32);
        Some(Shape {
            capsule: s[0] != 0.0,
            basis: Basis::from_rows(v(1), v(4), v(7)),
            origin: v(10),
            inv_basis: Basis::from_rows(v(13), v(16), v(19)),
            inv_origin: v(22),
            half: v(25),
            radius: s[28],
            half_segment: s[29],
        })
    }

    /// The shape's point nearest the body-frame point `p_body`, body frame (`p_body` itself when inside).
    pub fn nearest_point(&self, p_body: Vector3) -> Vector3 {
        let p = add(xform(&self.inv_basis, p_body), self.inv_origin);
        let near = if self.capsule {
            let on_axis = Vector3::new(0.0, clampf(f64::from(p.y), -self.half_segment, self.half_segment) as f32, 0.0);
            let off = sub(p, on_axis);
            let d = f64::from(length(off));
            if d <= self.radius {
                p
            } else {
                add(on_axis, scale(off, (self.radius / d) as f32))
            }
        } else {
            clamp_cw(p, neg(self.half), self.half)
        };
        add(xform(&self.basis, near), self.origin)
    }
}

/// How far World point `at` is from the nearest of `shapes` on a body at `basis`, `origin`, and that nearest point in the World;
/// None for a hull with no shapes.
pub fn nearest_on(shapes: &[Shape], basis: &Basis, origin: Vector3, at: Vector3) -> Option<(f64, Vector3)> {
    if shapes.is_empty() {
        return None;
    }
    let local = affine_inverse_xform(basis, origin, at);
    let mut best_d = f64::INFINITY;
    let mut best = local;
    for s in shapes {
        let p = s.nearest_point(local);
        let d = f64::from(distance(p, local));
        if d < best_d {
            best_d = d;
            best = p;
        }
    }
    Some((best_d, add(xform(basis, best), origin)))
}

/// What a blast needs of one `Damageable` beyond its landing: whose hull answers for it (a rotor's capital), the body a push
/// moves, the push's area and its hit volumes.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct BlastTarget {
    pub owner: i64,
    pub push_body: i64,
    pub area: f64,
    pub shapes: Vec<Shape>,
}

/// One hull a blast reached, measured: which of the reached it was (the caller's index), the `Damageable`, the key it shares with
/// the pieces of its ship, how far its nearest hit volume is, that point, the surface volume it lies on (-1 for none) and where
/// its body is.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Reach {
    pub index: u32,
    pub hull: i64,
    pub owner: i64,
    pub distance: f64,
    pub point: Vector3,
    pub volume: i32,
    pub place: Vector3,
}

/// Each owner once, in the order it was first reached, by its nearest piece (a nearer later piece takes the earlier's place).
pub fn pick(reached: &[Reach], out: &mut Vec<Reach>) {
    out.clear();
    for r in reached {
        match out.iter_mut().find(|p| p.owner == r.owner) {
            Some(p) => {
                if r.distance < p.distance {
                    *p = *r;
                }
            }
            None => out.push(*r),
        }
    }
}

#[cfg(test)]
mod tests;
