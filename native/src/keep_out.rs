// Keeping clear of a jump vortex (M8-T17, maintainer 2026-11-20): from the moment a vortex is announced until it folds, an
// AI ship treats its funnel and a margin round it as a place it must not be, since a vortex kills whatever it forms or closes
// on. Engine-free (held to the kernels' rules by test_sim_core): the volumes come in once per event from GDScript
// (`VortexKeepOuts`), and every think bends its wish round them.
use godot::builtin::Vector3;

/// A ship already inside a volume leaves it at least this fast.
pub const ESCAPE_MPS: f64 = 80.0;
/// A ship heading in starts to give way this far beyond the distance it needs to stop.
pub const BUFFER_M: f64 = 200.0;
/// How far ahead a wish is followed to see whether it passes through a volume.
pub const LOOK_AHEAD_S: f64 = 15.0;
const SAMPLES: usize = 10;

/// One volume: a capsule round the funnel's axis, from the mouth's centre `a` to the base's centre `b` (universe
/// positions), `radius` round it, drifting at `velocity` (World-local, the frame's rest), with the ships it leaves alone
/// (its opener and the ships it carries, by body instance id, sorted).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct KeepOut {
    pub a: [f64; 3],
    pub b: [f64; 3],
    pub velocity: [f64; 3],
    pub radius: f64,
    pub exempt: Vec<i64>,
}

/// The thinking ship as the keep-out sees it.
pub struct Ship {
    pub position: Vector3,
    pub velocity: Vector3,
    pub radius: f64,
    /// The deceleration it can count on to stop, m/s^2.
    pub a_brake: f64,
    pub body_id: i64,
    pub tie_hash: i64,
}

/// The volumes from GDScript's flat arrays: per volume `FLOATS` numbers (a, b, velocity, radius, how many exempt ids) and
/// that many ids from `ids` in turn. Volumes that do not fit are dropped.
pub const FLOATS: usize = 11;

pub fn unpack(floats: &[f64], ids: &[i64]) -> Vec<KeepOut> {
    let mut out = Vec::new();
    let mut next_id = 0usize;
    for f in floats.as_chunks::<FLOATS>().0 {
        let count = if f[10] >= 0.0 { f[10] as usize } else { 0 };
        let end = (next_id + count).min(ids.len());
        let mut exempt = ids[next_id..end].to_vec();
        next_id = end;
        exempt.sort_unstable();
        if f[9].is_nan() || f[9] <= 0.0 {
            continue;
        }
        out.push(KeepOut {
            a: [f[0], f[1], f[2]],
            b: [f[3], f[4], f[5]],
            velocity: [f[6], f[7], f[8]],
            radius: f[9],
            exempt,
        });
    }
    out
}

/// `wish` (World-local velocity) bent so the ship leaves, stays out of or passes round every volume that does not leave
/// it alone; None when no volume asks anything. The bool says whether the turn is urgent (inside, or too fast to stop).
pub fn steer(outs: &[KeepOut], origin: [f64; 3], ship: &Ship, wish: Vector3) -> Option<(Vector3, bool)> {
    let x = of(ship.position);
    let mut w_abs = of(wish);
    let mut changed = false;
    let mut urgent = false;
    for k in outs {
        if k.exempt.binary_search(&ship.body_id).is_ok() {
            continue;
        }
        let a = sub3(k.a, origin);
        let b = sub3(k.b, origin);
        let vo = k.velocity;
        let w = sub3(w_abs, vo);
        let v = sub3(of(ship.velocity), vo);
        let r = k.radius + ship.radius;
        let c = closest_on(a, b, x);
        let d = sub3(x, c);
        let dist = len3(d);
        let n = if dist > 1e-6 { mul3(d, 1.0 / dist) } else { tie(sub3(b, a), w, ship.tie_hash) };
        let radial = dot3(w, n);
        let tangent = sub3(w, mul3(n, radial));
        let bent = if dist < r {
            urgent = true;
            Some(add3(tangent, mul3(n, radial.max(ESCAPE_MPS))))
        } else {
            let closing = -dot3(v, n);
            let gap = dist - r;
            let stop = if closing > 0.0 { closing * closing / (2.0 * ship.a_brake.max(1.0)) } else { 0.0 };
            if closing > 0.0 && gap < stop + BUFFER_M {
                // Coming in too fast to wait: no more inward speed, and out again if it cannot stop short.
                if gap < stop {
                    urgent = true;
                }
                (radial < 0.0 || gap < stop).then(|| add3(tangent, mul3(n, if gap < stop { radial.max(0.0) + 1.0 } else { 0.0 })))
            } else {
                pass_round(a, b, x, w, r, ship.tie_hash)
            }
        };
        if let Some(nw) = bent {
            w_abs = add3(nw, vo);
            changed = true;
        }
    }
    changed.then(|| (to(w_abs), urgent))
}

// A wish whose straight line passes through the capsule within the look-ahead, turned (at its speed) to miss it.
fn pass_round(a: [f64; 3], b: [f64; 3], x: [f64; 3], w: [f64; 3], r: f64, tie_hash: i64) -> Option<[f64; 3]> {
    let speed = len3(w);
    if speed < 1.0 {
        return None;
    }
    // The sampled point of the straight line nearest the axis: (miss, time, offset from the axis).
    let mut miss = f64::INFINITY;
    let mut t = 0.0;
    let mut off = [0.0; 3];
    for s in 1..=SAMPLES {
        let ts = LOOK_AHEAD_S * s as f64 / SAMPLES as f64;
        let q = add3(x, mul3(w, ts));
        let o = sub3(q, closest_on(a, b, q));
        let m = len3(o);
        if m < miss {
            (miss, t, off) = (m, ts, o);
        }
    }
    if miss >= r {
        return None;
    }
    // Sideways only: the turn keeps the speed and moves the line off the axis.
    let unit = mul3(w, 1.0 / speed);
    let perp = sub3(off, mul3(unit, dot3(off, unit)));
    let perp_len = len3(perp);
    let side = if perp_len > 1e-3 { mul3(perp, 1.0 / perp_len) } else { tie(w, sub3(b, a), tie_hash) };
    let turned = add3(w, mul3(side, (r - perp_len) / t.max(0.5)));
    let turned_len = len3(turned);
    (turned_len > 1e-9).then(|| mul3(turned, speed / turned_len))
}

// A way out at right angles to `along`, chosen by the ship's tie-break when nothing else decides.
fn tie(along: [f64; 3], other: [f64; 3], tie_hash: i64) -> [f64; 3] {
    let mut p = cross3(along, other);
    if len3(p) < 1e-6 {
        p = cross3(along, [0.0, 1.0, 0.0]);
    }
    if len3(p) < 1e-6 {
        p = cross3(along, [1.0, 0.0, 0.0]);
    }
    let l = len3(p).max(1e-9);
    let sign = if tie_hash & 1 == 0 { 1.0 } else { -1.0 };
    mul3(p, sign / l)
}

fn closest_on(a: [f64; 3], b: [f64; 3], x: [f64; 3]) -> [f64; 3] {
    let ab = sub3(b, a);
    let l2 = dot3(ab, ab);
    if l2 < 1e-9 {
        return a;
    }
    let t = (dot3(sub3(x, a), ab) / l2).clamp(0.0, 1.0);
    add3(a, mul3(ab, t))
}

fn of(v: Vector3) -> [f64; 3] {
    [f64::from(v.x), f64::from(v.y), f64::from(v.z)]
}

fn to(v: [f64; 3]) -> Vector3 {
    Vector3::new(v[0] as f32, v[1] as f32, v[2] as f32)
}

fn add3(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

fn sub3(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn mul3(a: [f64; 3], s: f64) -> [f64; 3] {
    [a[0] * s, a[1] * s, a[2] * s]
}

fn dot3(a: [f64; 3], b: [f64; 3]) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn cross3(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}

fn len3(a: [f64; 3]) -> f64 {
    dot3(a, a).sqrt()
}

#[cfg(test)]
mod tests;
