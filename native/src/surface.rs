// Big hulls with a surface of their own (M7-T06, docs/architecture.md 20.3): the station's frame and drum as boxes and
// capsules in their body's frame. The hit sweep lands bolts on them, avoidance and the fire lane go round them and the
// brains measure ranges to them instead of to a bounding sphere 4 km across; the ram tracker gives a turning one's skin
// its speed. Engine-free: plain data in and out, the row tables and the vector maths only.
use godot::builtin::{Basis, Vector3};

use crate::rows::{Rows, Surface, SurfaceVolume};
use crate::v3::{col_a, col_b, col_c, cross, normalized, scale, sub};

/// Numbers one volume packs into (`ScsSimCore.set_surface`): capsule flag (0 or 1), the volume's own x, y and z axes in
/// the body frame, its centre, its size (a box's half extents; a capsule's half segment, radius, 0).
pub const VOLUME_LEN: usize = 16;

type V = [f64; 3];

fn wide(v: Vector3) -> V {
    [f64::from(v.x), f64::from(v.y), f64::from(v.z)]
}

fn dot3(a: V, b: V) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn sub3(a: V, b: V) -> V {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn add3(a: V, b: V) -> V {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

fn scale3(a: V, s: f64) -> V {
    [a[0] * s, a[1] * s, a[2] * s]
}

fn len3(a: V) -> f64 {
    dot3(a, a).sqrt()
}

fn unit3(a: V) -> V {
    let l = len3(a);
    if l > 1e-12 { scale3(a, 1.0 / l) } else { a }
}

/// A surface from packed volumes (`VOLUME_LEN` numbers each; a short tail and a volume that is not finite are dropped)
/// and its spin.
pub fn from_packed(packed: &[f64], spin_rad_s: f64) -> Surface {
    let volumes = packed
        .chunks_exact(VOLUME_LEN)
        .filter(|v| v.iter().all(|x| x.is_finite()))
        .map(|v| {
            let capsule = v[0] != 0.0;
            let half = [v[13].abs(), v[14].abs(), v[15].abs()];
            SurfaceVolume {
                capsule,
                axes: [
                    unit3([v[1], v[2], v[3]]),
                    unit3([v[4], v[5], v[6]]),
                    unit3([v[7], v[8], v[9]]),
                ],
                centre: [v[10], v[11], v[12]],
                half,
                reach: if capsule {
                    half[0] + half[1]
                } else {
                    len3(half)
                },
            }
        })
        .collect();
    Surface {
        volumes,
        hulls: Vec::new(),
        spin_rad_s: if spin_rad_s.is_finite() {
            spin_rad_s
        } else {
            0.0
        },
    }
}

/// Adds convex hulls to `s`'s volumes from `flat`: per hull its volume's index, its point count and the points (body frame),
/// one after another. A hull for a volume that does not exist, or with fewer than four points, is skipped.
pub fn add_hulls(s: &mut Surface, flat: &[f64]) {
    s.hulls.resize(s.volumes.len(), Vec::new());
    let mut at = 0;
    while at + 2 <= flat.len() {
        let (index, count) = (flat[at], flat[at + 1]);
        at += 2;
        if !(index.is_finite() && count.is_finite()) || count < 0.0 {
            return;
        }
        let n = count as usize;
        if at + n * 3 > flat.len() {
            return;
        }
        let points: Vec<V> = flat[at..at + n * 3]
            .chunks_exact(3)
            .map(|p| [p[0], p[1], p[2]])
            .collect();
        at += n * 3;
        let k = index as usize;
        if index >= 0.0 && k < s.volumes.len() && n >= 4 {
            s.hulls[k] = hull_planes(&points);
        }
    }
}

/// The face planes of the convex hull of `points` (`[nx, ny, nz, d]`, unit normals pointing out): every plane through three
/// of the points that has them all on its inner side, duplicates dropped. Brute force, for the few dozen points a
/// collision hull holds (`collision.py` keeps 32 at most), once when the station is built.
pub fn hull_planes(points: &[V]) -> Vec<[f64; 4]> {
    let n = points.len();
    let mut size = 0.0_f64;
    for p in points {
        size = size.max(len3(sub3(*p, points[0])));
    }
    let eps = 1e-6 * size.max(1.0);
    let mut planes: Vec<[f64; 4]> = Vec::new();
    for i in 0..n {
        for j in (i + 1)..n {
            for k in (j + 1)..n {
                let normal = cross3(sub3(points[j], points[i]), sub3(points[k], points[i]));
                let l = len3(normal);
                if l < eps * eps {
                    continue; // three points in a line
                }
                let mut normal = scale3(normal, 1.0 / l);
                let mut d = dot3(normal, points[i]);
                let (mut above, mut below) = (false, false);
                for p in points {
                    let s = dot3(normal, *p) - d;
                    above |= s > eps;
                    below |= s < -eps;
                }
                if above && below {
                    continue;
                }
                if above {
                    normal = scale3(normal, -1.0);
                    d = -d;
                }
                let same = planes.iter().any(|q| {
                    dot3([q[0], q[1], q[2]], normal) > 1.0 - 1e-9 && (q[3] - d).abs() <= eps
                });
                if !same {
                    planes.push([normal[0], normal[1], normal[2], d]);
                }
            }
        }
    }
    planes
}

fn cross3(a: V, b: V) -> V {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

// Where the body-frame segment from `a` to `b` first enters the convex hull of `planes` grown by `inflate` on every face, or
// none; 0 when `a` is inside (Cyrus-Beck).
fn hull_entry(a: V, b: V, planes: &[[f64; 4]], inflate: f64) -> Option<f64> {
    let d = sub3(b, a);
    let (mut t0, mut t1) = (0.0_f64, 1.0_f64);
    for p in planes {
        let n = [p[0], p[1], p[2]];
        let dist = dot3(n, a) - (p[3] + inflate);
        let denom = dot3(n, d);
        if denom.abs() < 1e-15 {
            if dist > 0.0 {
                return None;
            }
            continue;
        }
        let t = -dist / denom;
        if denom < 0.0 {
            t0 = t0.max(t);
        } else {
            t1 = t1.min(t);
        }
        if t0 > t1 {
            return None;
        }
    }
    Some(t0)
}

/// World point `p` in the frame of a body at `origin` turned by `basis` (its columns are its axes), in 64 bits.
pub fn into_body(basis: &Basis, origin: Vector3, p: Vector3) -> V {
    let d = sub3(wide(p), wide(origin));
    [
        dot3(d, wide(col_a(basis))),
        dot3(d, wide(col_b(basis))),
        dot3(d, wide(col_c(basis))),
    ]
}

/// Body-frame point `q` back in the World.
pub fn from_body(basis: &Basis, origin: Vector3, q: V) -> Vector3 {
    let w = add3(
        add3(
            scale3(wide(col_a(basis)), q[0]),
            scale3(wide(col_b(basis)), q[1]),
        ),
        scale3(wide(col_c(basis)), q[2]),
    );
    let o = wide(origin);
    Vector3::new(
        (o[0] + w[0]) as f32,
        (o[1] + w[1]) as f32,
        (o[2] + w[2]) as f32,
    )
}

// `q` (body frame) in the volume's own frame.
fn local(v: &SurfaceVolume, q: V) -> V {
    let d = sub3(q, v.centre);
    [dot3(d, v.axes[0]), dot3(d, v.axes[1]), dot3(d, v.axes[2])]
}

// A point of the volume's own frame in the body frame.
fn to_body(v: &SurfaceVolume, l: V) -> V {
    add3(
        v.centre,
        add3(
            add3(scale3(v.axes[0], l[0]), scale3(v.axes[1], l[1])),
            scale3(v.axes[2], l[2]),
        ),
    )
}

/// How far body-frame point `q` is from volume `v` (0 inside it) and the volume's nearest point to it (body frame).
pub fn nearest_on(v: &SurfaceVolume, q: V) -> (f64, V) {
    let l = local(v, q);
    let near = if v.capsule {
        let (h, r) = (v.half[0], v.half[1]);
        let y = l[1].clamp(-h, h);
        let off = [l[0], l[1] - y, l[2]];
        let d = len3(off);
        if d <= r {
            return (0.0, q);
        }
        let k = r / d;
        [l[0] * k, y + off[1] * k, l[2] * k]
    } else {
        [
            l[0].clamp(-v.half[0], v.half[0]),
            l[1].clamp(-v.half[1], v.half[1]),
            l[2].clamp(-v.half[2], v.half[2]),
        ]
    };
    (len3(sub3(l, near)), to_body(v, near))
}

/// The surface's nearest point to body-frame point `q`: its distance, the point and the volume, or none for an empty
/// surface. Ties go to the earlier volume.
pub fn nearest(s: &Surface, q: V) -> Option<(f64, V, usize)> {
    let mut best: Option<(f64, V, usize)> = None;
    for (k, v) in s.volumes.iter().enumerate() {
        // Nothing of a volume is nearer than its centre less its reach.
        if let Some((d, _, _)) = best
            && len3(sub3(q, v.centre)) - v.reach >= d
        {
            continue;
        }
        let (d, p) = nearest_on(v, q);
        if best.is_none_or(|(b, _, _)| d < b) {
            best = Some((d, p, k));
        }
    }
    best
}

// The distance from point `p` to the segment from `a` to `b`.
fn segment_point_distance(a: V, b: V, p: V) -> f64 {
    let ab = sub3(b, a);
    let len_sq = dot3(ab, ab);
    let t = if len_sq > 1e-18 {
        (dot3(sub3(p, a), ab) / len_sq).clamp(0.0, 1.0)
    } else {
        0.0
    };
    len3(sub3(add3(a, scale3(ab, t)), p))
}

// Where along the segment from `a` to `b` (0..1) it first enters the box of half extents `half` about the origin, or
// none; 0 when `a` is inside (the slab test, as `SweepMath.segment_box`).
fn box_entry(a: V, b: V, half: V) -> Option<f64> {
    let (mut t0, mut t1) = (0.0_f64, 1.0_f64);
    for k in 0..3 {
        let d = b[k] - a[k];
        if d.abs() < 1e-12 {
            if a[k].abs() > half[k] {
                return None;
            }
            continue;
        }
        let (mut near, mut far) = ((-half[k] - a[k]) / d, (half[k] - a[k]) / d);
        if near > far {
            std::mem::swap(&mut near, &mut far);
        }
        t0 = t0.max(near);
        t1 = t1.min(far);
        if t0 > t1 {
            return None;
        }
    }
    Some(t0)
}

// The smallest root in 0..1 of |a + t (b - a) - c|^2 = r^2, or none.
fn sphere_entry(a: V, b: V, c: V, r: f64) -> Option<f64> {
    let d = sub3(b, a);
    let m = sub3(a, c);
    let qa = dot3(d, d);
    let qb = 2.0 * dot3(m, d);
    let qc = dot3(m, m) - r * r;
    if qc <= 0.0 {
        return Some(0.0);
    }
    if qa < 1e-18 {
        return None;
    }
    let disc = qb * qb - 4.0 * qa * qc;
    if disc < 0.0 {
        return None;
    }
    let t = (-qb - disc.sqrt()) / (2.0 * qa);
    (0.0..=1.0).contains(&t).then_some(t)
}

// Where the segment from `a` to `b` first comes within `r` of the axis from (0, -h, 0) to (0, h, 0), or none; 0 when `a`
// already is.
fn capsule_entry(a: V, b: V, h: f64, r: f64) -> Option<f64> {
    if segment_point_distance([0.0, -h, 0.0], [0.0, h, 0.0], a) <= r {
        return Some(0.0);
    }
    let mut best: Option<f64> = None;
    let mut keep = |t: f64| {
        if best.is_none_or(|b| t < b) {
            best = Some(t);
        }
    };
    let d = sub3(b, a);
    let qa = d[0] * d[0] + d[2] * d[2];
    if qa > 1e-18 {
        let qb = 2.0 * (a[0] * d[0] + a[2] * d[2]);
        let qc = a[0] * a[0] + a[2] * a[2] - r * r;
        let disc = qb * qb - 4.0 * qa * qc;
        if disc >= 0.0 {
            let t = (-qb - disc.sqrt()) / (2.0 * qa);
            if (0.0..=1.0).contains(&t) && (a[1] + d[1] * t).abs() <= h {
                keep(t);
            }
        }
    }
    for end in [-h, h] {
        if let Some(t) = sphere_entry(a, b, [0.0, end, 0.0], r) {
            keep(t);
        }
    }
    best
}

/// Where the body-frame segment from `a` to `b` first enters one of the surface's volumes grown by `inflate` (a box on
/// each half extent, a capsule on its radius, a hull on each face): the fraction along it (0 when `a` starts inside one) and that volume, or
/// none. Ties go to the earlier volume.
pub fn sweep(s: &Surface, a: V, b: V, inflate: f64) -> Option<(f64, usize)> {
    let mut best: Option<(f64, usize)> = None;
    for (k, v) in s.volumes.iter().enumerate() {
        if segment_point_distance(a, b, v.centre) > v.reach + inflate.abs() * 1.8 {
            continue; // the grown volume lies within its reach plus the growth at a corner
        }
        if let Some(planes) = s.hulls.get(k).filter(|p| !p.is_empty()) {
            if let Some(t) = hull_entry(a, b, planes, inflate)
                && best.is_none_or(|(b, _)| t < b)
            {
                best = Some((t, k));
            }
            continue;
        }
        let (la, lb) = (local(v, a), local(v, b));
        let t = if v.capsule {
            capsule_entry(la, lb, v.half[0], v.half[1] + inflate)
        } else {
            box_entry(
                la,
                lb,
                [
                    v.half[0] + inflate,
                    v.half[1] + inflate,
                    v.half[2] + inflate,
                ],
            )
        };
        if let Some(t) = t
            && best.is_none_or(|(b, _)| t < b)
        {
            best = Some((t, k));
        }
    }
    best
}

/// The velocity of World point `point` on a body at `origin` turned by `basis` that spins at `spin_rad_s` about its own
/// +z: the turning drum's skin under a ship that touches it (Q9).
pub fn surface_velocity(
    basis: &Basis,
    origin: Vector3,
    spin_rad_s: f64,
    point: Vector3,
) -> Vector3 {
    let axis = normalized(col_c(basis));
    scale(cross(axis, sub(point, origin)), spin_rad_s as f32)
}

/// Row `j`'s nearest surface point to World point `p` and how far it is, or none for a row without a surface.
pub fn nearest_of_row(rows: &Rows, j: usize, p: Vector3) -> Option<(Vector3, f64)> {
    let s = rows.surface(j)?;
    let (basis, origin) = (&rows.bases[j], rows.positions[j]);
    let (d, q, _) = nearest(s, into_body(basis, origin, p))?;
    Some((from_body(basis, origin, q), d))
}

/// For each volume of row `j` within `within` m of World point `p`: its nearest point to `p` (World) and the distance,
/// in volume order. Nothing for a row without a surface.
pub fn near_volumes(
    rows: &Rows,
    j: usize,
    p: Vector3,
    within: f64,
    mut each: impl FnMut(Vector3, f64),
) {
    let Some(s) = rows.surface(j) else {
        return;
    };
    let (basis, origin) = (&rows.bases[j], rows.positions[j]);
    let q = into_body(basis, origin, p);
    for v in &s.volumes {
        if len3(sub3(q, v.centre)) - v.reach > within {
            continue;
        }
        let (d, near) = nearest_on(v, q);
        if d <= within {
            each(from_body(basis, origin, near), d);
        }
    }
}

/// Whether the World segment from `a` to `b` enters row `j`'s surface grown by `inflate`; false without a surface.
pub fn segment_enters(rows: &Rows, j: usize, a: Vector3, b: Vector3, inflate: f64) -> bool {
    let Some(s) = rows.surface(j) else {
        return false;
    };
    let (basis, origin) = (&rows.bases[j], rows.positions[j]);
    sweep(
        s,
        into_body(basis, origin, a),
        into_body(basis, origin, b),
        inflate,
    )
    .is_some()
}

#[cfg(test)]
mod tests;
