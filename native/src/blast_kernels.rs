// The blast model's reach (M10-T09, D12.6): which hulls one blast can touch and how far each one's nearest hit volume lies
// from its centre, over the rows the main thread holds. Every explosion asks it once (a death, a section blowing, a missile,
// a mine); the native blast batch (M10-T76, `blast_batch.rs`) lands the damage and the push. Engine-free
// (test_sim_core reads this file): rows in, plain numbers out, no statics, no threads, the same answer however many threads
// the core runs.
use godot::builtin::Vector3;

use crate::rows::{FLAG_HULL_ACTIVE, FLAG_SHELTERED, FLAG_TIER, Rows};
use crate::surface::{from_body, into_body, nearest};

/// One hull a blast reaches: its row, how far its nearest hit volume is from the blast's centre (a big hull's surface, else
/// its bounding sphere; 0 inside), that nearest point in the World, and the surface volume it lies on (-1 for a sphere).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Reached {
    pub row: u32,
    pub distance: f64,
    pub point: Vector3,
    pub volume: i32,
}

/// Whether a blast can hurt a row's hull: an active hull in play or a low-attention tier row, never a ship sheltered inside
/// a station (nothing outside reaches it there).
pub fn can_hurt(flags: u32) -> bool {
    flags & FLAG_SHELTERED == 0 && (flags & FLAG_TIER != 0 || flags & FLAG_HULL_ACTIVE != 0)
}

/// The hulls of `hull_rows` (the sweep's order: near hulls, then tier rows) whose nearest hit volume lies closer than
/// `radius` to `centre`, appended to `out` in that order.
pub fn reach(rows: &Rows, hull_rows: &[u32], centre: Vector3, radius: f64, out: &mut Vec<Reached>) {
    if !radius.is_finite() || radius <= 0.0 {
        return;
    }
    let c = [f64::from(centre.x), f64::from(centre.y), f64::from(centre.z)];
    for &r in hull_rows {
        let j = r as usize;
        if j >= rows.positions.len() || !can_hurt(rows.flags[j]) {
            continue;
        }
        let p = rows.positions[j];
        let off = [
            f64::from(p.x) - c[0],
            f64::from(p.y) - c[1],
            f64::from(p.z) - c[2],
        ];
        let centre_gap = (off[0] * off[0] + off[1] * off[1] + off[2] * off[2]).sqrt();
        let sphere_gap = centre_gap - rows.radii[j];
        // Nothing of a hull is nearer than its bounding sphere.
        if sphere_gap.is_nan() || sphere_gap >= radius {
            continue;
        }
        if let Some(s) = rows.surface(j) {
            let basis = &rows.bases[j];
            if let Some((d, q, k)) = nearest(s, into_body(basis, p, centre))
                && d < radius
            {
                out.push(Reached {
                    row: r,
                    distance: d,
                    point: from_body(basis, p, q),
                    volume: k as i32,
                });
            }
            continue;
        }
        let distance = sphere_gap.max(0.0);
        // The sphere's point facing the blast (the centre itself when the blast is inside it).
        let point = if sphere_gap > 0.0 {
            let k = sphere_gap / centre_gap;
            Vector3::new(
                (c[0] + off[0] * k) as f32,
                (c[1] + off[1] * k) as f32,
                (c[2] + off[2] * k) as f32,
            )
        } else {
            centre
        };
        out.push(Reached {
            row: r,
            distance,
            point,
            volume: -1,
        });
    }
}

#[cfg(test)]
mod tests;
