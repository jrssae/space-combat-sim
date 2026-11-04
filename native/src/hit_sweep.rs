// The hit resolver's broad phase in native code, behind HitBroadPhase (M4-T08, docs/architecture.md 17.7).
// gdext's class derive writes `base: base` in the code it generates for this module.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

// The grid's levels, as `HitBroadPhase` defines them.
const BASE_CELL_M: f64 = 64.0;
const LEVEL_FACTOR: f64 = 4.0;
const LEVELS: usize = 5;
const PAD_REL: f64 = 1e-6;
const PAD_M: f64 = 1.0;
const MAX_CELL_INDEX: f64 = 1_073_741_824.0;

// A hull in the grid: its cell and its index.
type CellEntry = ((i32, i32, i32), u32);

/// Which projectile and hull pairs pass the hit resolver's bounding-sphere test this tick, found through a grid of levels so
/// a 10 m fighter and a 1 km hull are both found cheaply. Repeats `HitBroadPhase`'s GDScript step for step: the same levels,
/// the same cells, the same fallbacks, the sphere test in 32-bit vectors and 64-bit scalars, so both paths give the same pairs
/// and the same work count.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsHitSweep {
    base: Base<RefCounted>,
    visited: i64,
    // Per level: (cell, hull) sorted, the level's hulls ascending, and its largest reach.
    cells: Vec<Vec<CellEntry>>,
    members: Vec<Vec<u32>>,
    level_reach: Vec<f64>,
    loose: Vec<u32>,
    candidates: Vec<u32>,
}

#[godot_api]
impl ScsHitSweep {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Pairs the latest call put to the sphere test (the work count), or -1 when it refused its arrays.
    #[func]
    fn visited(&self) -> i64 {
        self.visited
    }

    /// `HitBroadPhase.pairs`: the pairs that pass the sphere test, as `bolt * hulls + hull`, ascending. Returns nothing, after
    /// logging why, when the arrays do not line up.
    #[func]
    fn pairs(
        &mut self,
        bolt_mids: PackedVector3Array,
        bolt_reach: PackedFloat64Array,
        hull_mids: PackedVector3Array,
        hull_reach: PackedFloat64Array,
    ) -> PackedInt64Array {
        self.visited = 0;
        if bolt_reach.len() != bolt_mids.len() || hull_reach.len() != hull_mids.len() {
            godot_error!(
                "ScsHitSweep.pairs: array lengths differ (bolts {} and {}, hulls {} and {}); no pairs",
                bolt_mids.len(),
                bolt_reach.len(),
                hull_mids.len(),
                hull_reach.len()
            );
            self.visited = -1;
            return PackedInt64Array::new();
        }
        let bolts = bolt_mids.as_slice();
        let bolt_reach = bolt_reach.as_slice();
        let hulls = hull_mids.as_slice();
        let hull_reach = hull_reach.as_slice();
        let mut out: Vec<i64> = Vec::new();
        if hulls.is_empty() || bolts.is_empty() {
            return PackedInt64Array::new();
        }
        self.place(hulls, hull_reach);
        let hull_count = hulls.len() as i64;
        for (i, &at) in bolts.iter().enumerate() {
            self.look(at, bolt_reach[i].abs());
            self.visited += self.candidates.len() as i64;
            for &j in &self.candidates {
                let j = j as usize;
                let reach = bolt_reach[i] + hull_reach[j];
                if f64::from(dist_sq(at, hulls[j])) > reach * reach {
                    continue;
                }
                out.push(i as i64 * hull_count + j as i64);
            }
        }
        PackedInt64Array::from(out.as_slice())
    }
}

impl ScsHitSweep {
    // Puts every hull into its level's cell, or into the loose list when it fits no cell.
    fn place(&mut self, hulls: &[Vector3], hull_reach: &[f64]) {
        self.cells.resize_with(LEVELS, Vec::new);
        self.members.resize_with(LEVELS, Vec::new);
        self.level_reach.clear();
        self.level_reach.resize(LEVELS, 0.0);
        for level in 0..LEVELS {
            self.cells[level].clear();
            self.members[level].clear();
        }
        self.loose.clear();
        for (j, &mid) in hulls.iter().enumerate() {
            let reach = hull_reach[j].abs();
            let Some(level) = level_for(reach).filter(|_| finite(mid)) else {
                self.loose.push(j as u32);
                continue;
            };
            let cell_m = cell_size(level);
            let key = (
                (f64::from(mid.x) / cell_m).floor(),
                (f64::from(mid.y) / cell_m).floor(),
                (f64::from(mid.z) / cell_m).floor(),
            );
            if !within_grid(key.0, key.1, key.2) {
                self.loose.push(j as u32);
                continue;
            }
            self.cells[level].push(((key.0 as i32, key.1 as i32, key.2 as i32), j as u32));
            self.members[level].push(j as u32);
            if reach > self.level_reach[level] {
                self.level_reach[level] = reach;
            }
        }
        for level in 0..LEVELS {
            self.cells[level].sort_unstable();
        }
    }

    // Fills `candidates` with the hulls a projectile at `at` with reach `own` must test, ascending.
    fn look(&mut self, at: Vector3, own: f64) {
        self.candidates.clear();
        for level in 0..LEVELS {
            let count = self.members[level].len();
            if count == 0 {
                continue;
            }
            let cell_m = cell_size(level);
            let half = (own + self.level_reach[level]) * (1.0 + PAD_REL) + PAD_M;
            let (x, y, z) = (f64::from(at.x), f64::from(at.y), f64::from(at.z));
            let (lx, ly, lz) = (
                ((x - half) / cell_m).floor(),
                ((y - half) / cell_m).floor(),
                ((z - half) / cell_m).floor(),
            );
            let (hx, hy, hz) = (
                ((x + half) / cell_m).floor(),
                ((y + half) / cell_m).floor(),
                ((z + half) / cell_m).floor(),
            );
            let span = (hx - lx + 1.0) * (hy - ly + 1.0) * (hz - lz + 1.0);
            // Not finite, beyond the grid, or more cells than hulls: testing every hull of the level is cheaper and safe.
            #[allow(clippy::neg_cmp_op_on_partial_ord)]
            let walk_every_hull =
                !(span <= count as f64) || !within_grid(lx, ly, lz) || !within_grid(hx, hy, hz);
            if walk_every_hull {
                self.candidates.extend_from_slice(&self.members[level]);
                continue;
            }
            let cells = &self.cells[level];
            let (lz, hz) = (lz as i32, hz as i32);
            for cx in lx as i32..=hx as i32 {
                for cy in ly as i32..=hy as i32 {
                    let start = cells.partition_point(|e| e.0 < (cx, cy, lz));
                    let end = cells.partition_point(|e| e.0 <= (cx, cy, hz));
                    self.candidates
                        .extend(cells[start..end].iter().map(|e| e.1));
                }
            }
        }
        self.candidates.extend_from_slice(&self.loose);
        self.candidates.sort_unstable();
    }
}

// The grid level for a hull of this reach, or none when it fits no level.
fn level_for(reach: f64) -> Option<usize> {
    if !reach.is_finite() {
        return None;
    }
    let mut cell_m = BASE_CELL_M;
    for level in 0..LEVELS {
        if 2.0 * reach <= cell_m {
            return Some(level);
        }
        cell_m *= LEVEL_FACTOR;
    }
    None
}

fn cell_size(level: usize) -> f64 {
    BASE_CELL_M * LEVEL_FACTOR.powi(level as i32)
}

fn finite(v: Vector3) -> bool {
    v.x.is_finite() && v.y.is_finite() && v.z.is_finite()
}

fn within_grid(x: f64, y: f64, z: f64) -> bool {
    x.abs() <= MAX_CELL_INDEX && y.abs() <= MAX_CELL_INDEX && z.abs() <= MAX_CELL_INDEX
}

// `a.distance_squared_to(b)` in 32 bits, in the engine's order of operations.
fn dist_sq(a: Vector3, b: Vector3) -> f32 {
    let (x, y, z) = (b.x - a.x, b.y - a.y, b.z - a.z);
    let x2 = x * x;
    let y2 = y * y;
    let z2 = z * z;
    x2 + y2 + z2
}
