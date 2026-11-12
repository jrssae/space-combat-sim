// The hit broad phase's grid of levels with its cells in hash maps (M4-T34, docs/architecture.md 17.13): the hulls
// placed by level and cell, the candidates for every projectile found by one lookup per cell
// (M4-T37 removed the sorted reference grid). Engine-free and thread-ready: plain data in, plain data out, scratch passed in.
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

use godot::builtin::Vector3;

use crate::v3::dist_sq;

// The levels, as `HitBroadPhase` defines them.
const BASE_CELL_M: f64 = 64.0;
const LEVEL_FACTOR: f64 = 4.0;
const LEVELS: usize = 5;
const PAD_REL: f64 = 1e-6;
const PAD_M: f64 = 1.0;
// Room for the sphere test's 32-bit distance, as a share of how far out the look sits.
const OUTSIDE_PAD_REL: f64 = 1e-5;
// The most cells of a level's span that are marked (1 MiB of bits); a wider level asks its cell map for every cell.
const MAX_MARKED_CELLS: usize = 1 << 23;
const MAX_CELL_INDEX: f64 = 1_073_741_824.0;

// Cell keys hash by a few multiplies: the default hasher costs more than the lookup it guards.
#[derive(Default)]
pub struct CellHasher(u64);

impl Hasher for CellHasher {
    fn finish(&self) -> u64 {
        self.0 ^ (self.0 >> 31)
    }

    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0.rotate_left(8) ^ u64::from(b)).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        }
    }

    fn write_i32(&mut self, v: i32) {
        self.0 = (self.0.rotate_left(21) ^ u64::from(v as u32)).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    }
}

type Cell = (i32, i32, i32);
// The span of a level with no hull: no cell lies inside it.
const EMPTY_LOW: Cell = (i32::MAX, i32::MAX, i32::MAX);
const EMPTY_HIGH: Cell = (i32::MIN, i32::MIN, i32::MIN);
// A cell's hulls are one of the grid's `lists`, by its place there.
type Cells = HashMap<Cell, u32, BuildHasherDefault<CellHasher>>;

/// Hulls placed in a grid of levels: per level its cells (each holding its hulls ascending), its hulls ascending and its
/// largest reach; the hulls that fit no cell are loose.
#[derive(Default)]
pub struct CellGrid {
    cells: Vec<Cells>,
    // The cells' hull lists, kept from one placing to the next (M5-T35): the first `lists_used` are held by a cell.
    lists: Vec<Vec<u32>>,
    lists_used: usize,
    members: Vec<Vec<u32>>,
    level_reach: Vec<f64>,
    loose: Vec<u32>,
    // Per level, the lowest and highest cell that holds a hull (M5-T33): a look walks no cell outside them.
    spans: Vec<(Cell, Cell)>,
    // Per level, the box round its hulls' spheres (M5-T33): a look outside it counts the level's hulls without listing them.
    boxes: Vec<([f64; 3], [f64; 3])>,
    // Per level, a bit a cell of its span, set where the cell holds a hull (`mark_cells`, M5-T33); empty when not marked.
    marks: Vec<Vec<u64>>,
    // Per level, its hulls by x (`mark_cells`): a look that takes a whole sparse level lists only those near it along x.
    by_x: Vec<Vec<(f32, u32)>>,
    mids_x: Vec<f32>,
}

impl CellGrid {
    /// Puts every hull into its level's cell, or into the loose list when it fits no cell (the levels' rules).
    pub fn place(&mut self, hulls: &[Vector3], hull_reach: &[f64]) {
        self.cells.resize_with(LEVELS, Cells::default);
        self.members.resize_with(LEVELS, Vec::new);
        self.level_reach.clear();
        self.level_reach.resize(LEVELS, 0.0);
        for level in 0..LEVELS {
            self.cells[level].clear();
            self.members[level].clear();
        }
        self.lists_used = 0;
        self.loose.clear();
        self.spans.clear();
        self.spans.resize(LEVELS, (EMPTY_LOW, EMPTY_HIGH));
        self.marks.resize_with(LEVELS, Vec::new);
        for marks in self.marks.iter_mut() {
            marks.clear();
        }
        self.by_x.resize_with(LEVELS, Vec::new);
        for sorted in self.by_x.iter_mut() {
            sorted.clear();
        }
        self.mids_x.clear();
        self.mids_x.extend(hulls.iter().map(|mid| mid.x));
        self.boxes.clear();
        self.boxes
            .resize(LEVELS, ([f64::INFINITY; 3], [f64::NEG_INFINITY; 3]));
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
            let cell = (key.0 as i32, key.1 as i32, key.2 as i32);
            let span = &mut self.spans[level];
            span.0 = (
                span.0.0.min(cell.0),
                span.0.1.min(cell.1),
                span.0.2.min(cell.2),
            );
            span.1 = (
                span.1.0.max(cell.0),
                span.1.1.max(cell.1),
                span.1.2.max(cell.2),
            );
            let held = &mut self.boxes[level];
            for (k, at) in [mid.x, mid.y, mid.z].into_iter().enumerate() {
                held.0[k] = held.0[k].min(f64::from(at) - reach);
                held.1[k] = held.1[k].max(f64::from(at) + reach);
            }
            let next = self.lists_used;
            let list = *self.cells[level].entry(cell).or_insert(next as u32) as usize;
            if list == next {
                // A cell's first hull: it takes the next list, emptied of what it held at the last placing.
                if next == self.lists.len() {
                    self.lists.push(Vec::new());
                } else {
                    self.lists[next].clear();
                }
                self.lists_used += 1;
            }
            self.lists[list].push(j as u32);
            self.members[level].push(j as u32);
            if reach > self.level_reach[level] {
                self.level_reach[level] = reach;
            }
        }
    }

    /// Marks which cells hold a hull, for a grid that is kept and looked at many times (the rocks): a look then asks
    /// the cell map only for the cells that hold something. A level whose span is too large to mark stays unmarked.
    pub fn mark_cells(&mut self) {
        for level in 0..self.marks.len() {
            let sorted = &mut self.by_x[level];
            sorted.clear();
            sorted.extend(
                self.members[level]
                    .iter()
                    .map(|&j| (self.mids_x[j as usize], j)),
            );
            sorted.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
            self.marks[level].clear();
            let Some((_, dy, dz, bits)) = span_size(self.spans[level]) else {
                continue;
            };
            if bits > MAX_MARKED_CELLS {
                continue;
            }
            let low = self.spans[level].0;
            self.marks[level].resize(bits.div_ceil(64), 0);
            for cell in self.cells[level].keys() {
                let bit = mark_of(low, dy, dz, *cell);
                self.marks[level][bit / 64] |= 1 << (bit % 64);
            }
        }
    }

    // Fills `candidates` with the hulls a projectile at `at` with reach `own` must test, each once, in no order (the
    // sweep sorts the few that pass its sphere test: a capital's look lists hundreds). Returns how many
    // more hulls the look stands for without listing them: a level too sparse for its cells hands over every hull it
    // holds, and far from all of them none can pass the sphere test, so they are counted as work and left out.
    fn look(&self, at: Vector3, own: f64, candidates: &mut Vec<u32>) -> usize {
        candidates.clear();
        let mut unlisted = 0;
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
            #[allow(clippy::neg_cmp_op_on_partial_ord)]
            let walk_every_hull =
                !(span <= count as f64) || !within_grid(lx, ly, lz) || !within_grid(hx, hy, hz);
            if walk_every_hull {
                let sorted = &self.by_x[level];
                if self.outside(level, x, y, z, own) {
                    unlisted += count;
                } else if sorted.is_empty() {
                    candidates.extend_from_slice(&self.members[level]);
                } else {
                    // Farther along x than the two reaches and the room, a hull cannot pass the sphere test.
                    let room = own
                        + self.level_reach[level]
                        + PAD_M
                        + OUTSIDE_PAD_REL * (x.abs() + y.abs() + z.abs());
                    let from = sorted.partition_point(|e| f64::from(e.0) < x - room);
                    let to = sorted.partition_point(|e| f64::from(e.0) <= x + room);
                    candidates.extend(sorted[from..to].iter().map(|e| e.1));
                    unlisted += count - (to - from);
                }
                continue;
            }
            let cells = &self.cells[level];
            // Only the cells that hold a hull: far from every hull of the level, that is none.
            let (low, high) = self.spans[level];
            let marks = &self.marks[level];
            let (dy, dz) = match span_size((low, high)) {
                Some((_, dy, dz, _)) if !marks.is_empty() => (dy, dz),
                _ => (0, 0),
            };
            for cx in (lx as i32).max(low.0)..=(hx as i32).min(high.0) {
                for cy in (ly as i32).max(low.1)..=(hy as i32).min(high.1) {
                    for cz in (lz as i32).max(low.2)..=(hz as i32).min(high.2) {
                        if !marks.is_empty() {
                            let bit = mark_of(low, dy, dz, (cx, cy, cz));
                            if marks[bit / 64] & (1 << (bit % 64)) == 0 {
                                continue;
                            }
                        }
                        let key: &Cell = &(cx, cy, cz);
                        if let Some(&list) = cells.get(key) {
                            candidates.extend_from_slice(&self.lists[list as usize]);
                        }
                    }
                }
            }
        }
        candidates.extend_from_slice(&self.loose);
        unlisted
    }

    // Whether a sphere of `own` at (x, y, z) lies outside the box round `level`'s hulls, by more than the 32-bit sphere
    // test could misjudge. Never true where a hull of the level could pass that test.
    fn outside(&self, level: usize, x: f64, y: f64, z: f64, own: f64) -> bool {
        let (low, high) = &self.boxes[level];
        let room = own + PAD_M + OUTSIDE_PAD_REL * (x.abs() + y.abs() + z.abs());
        [x, y, z]
            .into_iter()
            .enumerate()
            .any(|(k, at)| at + room < low[k] || at - room > high[k])
    }
}

/// Each projectile against the placed hulls: its candidates, then the sphere test; keys as `bolt * hulls + hull`, ascending.
pub fn sweep(
    grid: &CellGrid,
    bolts: &[Vector3],
    bolt_reach: &[f64],
    hulls: &[Vector3],
    hull_reach: &[f64],
    candidates: &mut Vec<u32>,
    visited: &mut i64,
) -> Vec<i64> {
    let mut out: Vec<i64> = Vec::new();
    let hull_count = hulls.len() as i64;
    for (i, &at) in bolts.iter().enumerate() {
        let unlisted = grid.look(at, bolt_reach[i].abs(), candidates);
        *visited += (candidates.len() + unlisted) as i64;
        let first = out.len();
        for &j in candidates.iter() {
            let j = j as usize;
            let reach = bolt_reach[i] + hull_reach[j];
            if f64::from(dist_sq(at, hulls[j])) > reach * reach {
                continue;
            }
            out.push(i as i64 * hull_count + j as i64);
        }
        out[first..].sort_unstable();
    }
    out
}

// A span's cell counts along x, y and z and in all; none for a level with no hull.
fn span_size(span: (Cell, Cell)) -> Option<(usize, usize, usize, usize)> {
    let (low, high) = span;
    if low.0 > high.0 || low.1 > high.1 || low.2 > high.2 {
        return None;
    }
    let dx = (i64::from(high.0) - i64::from(low.0) + 1) as usize;
    let dy = (i64::from(high.1) - i64::from(low.1) + 1) as usize;
    let dz = (i64::from(high.2) - i64::from(low.2) + 1) as usize;
    let bits = dx.checked_mul(dy)?.checked_mul(dz)?;
    Some((dx, dy, dz, bits))
}

// The bit of `cell` in a span that starts at `low` and is `dy` by `dz` cells across y and z.
fn mark_of(low: Cell, dy: usize, dz: usize, cell: Cell) -> usize {
    let x = (i64::from(cell.0) - i64::from(low.0)) as usize;
    let y = (i64::from(cell.1) - i64::from(low.1)) as usize;
    let z = (i64::from(cell.2) - i64::from(low.2)) as usize;
    (x * dy + y) * dz + z
}

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

#[cfg(test)]
mod tests;
