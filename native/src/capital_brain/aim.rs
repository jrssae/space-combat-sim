// Where a capital's heavy weapons and beams aim on their target (D12.10, Q17; the maintainer, 2026-11-25): a vital spot when
// one is available, else the nearest standing part of the hull. Vital, in order: the doctrine's aims (a withdrawing target's
// engines under a cripple doctrine; outgunned, its mounts bearing on the ship), then its reactor, magazine and bridge.
// Available: still standing, inside the cone of one of the ship's own heavy weapons, with a line its own hull does not cross
// and that first meets the target on that part. Worked out at each think (5 Hz), so a lost or hidden part gives way at once.
use godot::builtin::Vector3;

use crate::rows::Rows;
use crate::surface;
use crate::v3::{add, dot, length, normalized, scale, sub, xform, xform_inv};

use super::{
    BrainPoint, CapitalSpec, POINT_BRIDGE, POINT_ENGINE, POINT_MAGAZINE, POINT_REACTOR, POINT_SECTION, ROLE_AF, STATE_WITHDRAW,
};

// A mount as a part to aim at: this far round its place, m.
const MOUNT_PART_M: f32 = 10.0;
// The line may first meet the target this far outside the part's box and still count as meeting it, m.
const EXPOSED_MARGIN_M: f32 = 5.0;
// A weapon's line starts this far off its base along its axis (as the bearings do).
const LIFT_M: f32 = 2.0;
// At most this many of the ship's weapons are tried for a line to one part (the cost stays flat on a big ship).
const WEAPONS_TRIED: usize = 8;

/// The point (target `target`'s frame, rotating pieces at rest) that capital `spec` at row `r` aims at on row `j`; none when the
/// target has no parts to aim at (its centre then).
pub fn aim(
    spec: &CapitalSpec,
    target: &CapitalSpec,
    target_state: u8,
    rows: &Rows,
    r: usize,
    j: usize,
    ratio: f64,
) -> Option<Vector3> {
    let view = View { spec, rows, r, j };
    let own_local = xform_inv(&rows.bases[j], sub(rows.positions[r], rows.positions[j]));
    let by_distance = |a: &(Vector3, Vector3), b: &(Vector3, Vector3)| {
        box_distance(own_local, a.0, a.1).total_cmp(&box_distance(own_local, b.0, b.1))
    };
    let part = Vector3::new(MOUNT_PART_M, MOUNT_PART_M, MOUNT_PART_M);
    // The doctrine's aims first: a withdrawing target's engines to cripple it.
    if spec.doctrine.cripple && target_state == STATE_WITHDRAW {
        let mut engines = parts(&target.points, &[POINT_ENGINE]);
        engines.sort_by(by_distance);
        if let Some(&(at, _)) = engines.iter().find(|(at, half)| view.available(*at, *half)) {
            return Some(at);
        }
    }
    // Outgunned, the mounts that bear on it, the strongest first.
    if target.dps() > ratio * spec.dps().max(1.0) {
        let mut bearing: Vec<(f64, Vector3)> = target
            .mounts
            .iter()
            .filter(|m| m.fights() && dot(normalized(sub(own_local, m.at)), m.axis) >= m.cos_half)
            .map(|m| (m.dps, m.at))
            .collect();
        bearing.sort_by(|a, b| {
            b.0.total_cmp(&a.0).then(box_distance(own_local, a.1, part).total_cmp(&box_distance(own_local, b.1, part)))
        });
        if let Some(&(_, at)) = bearing.iter().find(|(_, at)| view.available(*at, part)) {
            return Some(at);
        }
    }
    // Then the vital sections, the nearest first.
    let mut vital = parts(&target.points, &[POINT_REACTOR, POINT_MAGAZINE, POINT_BRIDGE]);
    vital.sort_by(by_distance);
    if let Some(&(at, _)) = vital.iter().find(|(at, half)| view.available(*at, *half)) {
        return Some(at);
    }
    // Else the nearest standing part of the hull.
    let mut standing = parts(&target.points, &[POINT_SECTION, POINT_REACTOR, POINT_MAGAZINE, POINT_BRIDGE]);
    standing.sort_by(by_distance);
    standing.first().map(|&(at, _)| at)
}

// The standing parts of `kinds` among `points`: place and half extents.
fn parts(points: &[BrainPoint], kinds: &[u8]) -> Vec<(Vector3, Vector3)> {
    points.iter().filter(|p| p.works && kinds.contains(&p.kind)).map(|p| (p.at, p.half)).collect()
}

// How far `p` is from the box round `at` with half extents `half`, 0 inside.
fn box_distance(p: Vector3, at: Vector3, half: Vector3) -> f32 {
    let d = sub(p, at);
    let out = Vector3::new((d.x.abs() - half.x).max(0.0), (d.y.abs() - half.y).max(0.0), (d.z.abs() - half.z).max(0.0));
    length(out)
}

// The shooter, its target and their rows, for the line checks.
struct View<'a> {
    spec: &'a CapitalSpec,
    rows: &'a Rows,
    r: usize,
    j: usize,
}

impl View<'_> {
    // Whether a part at `at` (half extents `half`, the target's frame) is in the cone of one of the ship's heavy weapons with
    // a line its own hull does not cross and that first meets the target on that part.
    fn available(&self, at: Vector3, half: Vector3) -> bool {
        let rows = self.rows;
        let (own_basis, own_origin) = (&rows.bases[self.r], rows.positions[self.r]);
        let (basis, origin) = (&rows.bases[self.j], rows.positions[self.j]);
        let point = add(origin, xform(basis, at));
        let mut tried = 0;
        for m in self.spec.mounts.iter().filter(|m| m.fights() && m.role != ROLE_AF) {
            let from = add(own_origin, xform(own_basis, add(m.at, scale(m.axis, LIFT_M))));
            if dot(xform_inv(own_basis, normalized(sub(point, from))), m.axis) < m.cos_half {
                continue;
            }
            tried += 1;
            if tried > WEAPONS_TRIED {
                return false;
            }
            if let Some(own) = rows.surface(self.r)
                && surface::enters_from_outside(
                    own,
                    surface::into_body(own_basis, own_origin, from),
                    surface::into_body(own_basis, own_origin, point),
                )
            {
                continue;
            }
            let Some(skin) = rows.surface(self.j) else {
                return true;
            };
            let a = surface::into_body(basis, origin, from);
            let b = [f64::from(at.x), f64::from(at.y), f64::from(at.z)];
            match surface::sweep(skin, a, b, 0.0) {
                None => return true,
                Some((t, _)) => {
                    let entry = Vector3::new(
                        (a[0] + (b[0] - a[0]) * t) as f32,
                        (a[1] + (b[1] - a[1]) * t) as f32,
                        (a[2] + (b[2] - a[2]) * t) as f32,
                    );
                    if box_distance(entry, at, half) <= EXPOSED_MARGIN_M {
                        return true;
                    }
                }
            }
        }
        false
    }
}
