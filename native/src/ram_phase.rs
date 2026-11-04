// The ram resolver's broad phase on the core's rows (M4-T15, docs/architecture.md 17.13); `RamBroadPhase` (GDScript,
// M4-T03) stays the reference.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use std::cmp::Ordering;

use godot::prelude::*;

use crate::sim_core::{FLAG_RIGID, ScsSimCore};

// `RamBroadPhase.MARGIN_M`: room round every box, metres.
const MARGIN_M: f64 = 1.0;

/// Which pairs of the core's hull rows could come near each other in the coming tick: each hull's bounding sphere swept
/// along its path through the tick, boxed; the boxes sorted along x and swept once. Repeats `RamBroadPhase.pairs` step
/// for step (32-bit vectors, the same box, the same sort and the same keys), so both give the same pairs in the same
/// order. Reads the rows, never the engine.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsRamPhase {
    base: Base<RefCounted>,
    lows: Vec<Vector3>,
    highs: Vec<Vector3>,
    order: Vec<(f32, u32)>,
    keys: Vec<i64>,
}

#[godot_api]
impl ScsRamPhase {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// `RamBroadPhase.pairs` over the core's hull rows (in their order): hull `i` moves from its position to `position +
    /// velocity * delta` through the tick (a prop, which moved itself already, from `position - velocity * delta` to its
    /// position) inside its bounding sphere. The pairs as `i * count + j` with `i < j`, ascending, `always` (the same
    /// form) added.
    #[func]
    fn pairs(
        &mut self,
        core: Gd<ScsSimCore>,
        delta: f64,
        always: PackedInt64Array,
    ) -> PackedInt64Array {
        let core = core.bind();
        let rows = &core.rows;
        let hulls = &core.hull_rows;
        let count = hulls.len();
        self.lows.clear();
        self.highs.clear();
        self.order.clear();
        let dt = delta as f32;
        for (i, &row) in hulls.iter().enumerate() {
            let j = row as usize;
            let at = rows.positions[j];
            let step = scale(rows.velocities[j], dt);
            let (start, end) = if rows.flags[j] & FLAG_RIGID != 0 {
                (at, add(at, step))
            } else {
                (sub(at, step), at)
            };
            // `Vector3.ONE * (radius + MARGIN_M)`: the radius as the 32-bit float the resolver packs, then one 32-bit scale.
            let grow_s = (f64::from(rows.radii[j] as f32) + MARGIN_M) as f32;
            let grow = Vector3::new(grow_s, grow_s, grow_s);
            let low = sub(min(start, end), grow);
            self.lows.push(low);
            self.highs.push(add(max(start, end), grow));
            self.order.push((low.x, i as u32));
        }
        self.order.sort_by(|a, b| {
            a.0.partial_cmp(&b.0)
                .unwrap_or(Ordering::Equal)
                .then(a.1.cmp(&b.1))
        });
        self.keys.clear();
        self.keys.extend_from_slice(always.as_slice());
        let count_i = count as i64;
        for a in 0..count {
            let i = self.order[a].1 as usize;
            let low_i = self.lows[i];
            let high_i = self.highs[i];
            for b in (a + 1)..count {
                let j = self.order[b].1 as usize;
                let low_j = self.lows[j];
                if low_j.x > high_i.x {
                    break; // every later box starts farther along x
                }
                let high_j = self.highs[j];
                if low_j.y > high_i.y
                    || low_i.y > high_j.y
                    || low_j.z > high_i.z
                    || low_i.z > high_j.z
                {
                    continue;
                }
                let (lo, hi) = if i < j { (i, j) } else { (j, i) };
                self.keys.push(lo as i64 * count_i + hi as i64);
            }
        }
        self.keys.sort_unstable();
        self.keys.dedup();
        PackedInt64Array::from(self.keys.as_slice())
    }
}

// Godot's Vector3 maths in 32 bits, in the engine's order of operations.
fn add(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x + b.x, a.y + b.y, a.z + b.z)
}

fn sub(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x - b.x, a.y - b.y, a.z - b.z)
}

fn scale(a: Vector3, s: f32) -> Vector3 {
    Vector3::new(a.x * s, a.y * s, a.z * s)
}

// `Vector3.min` and `max`, component by component.
fn min(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x.min(b.x), a.y.min(b.y), a.z.min(b.z))
}

fn max(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x.max(b.x), a.y.max(b.y), a.z.max(b.z))
}
