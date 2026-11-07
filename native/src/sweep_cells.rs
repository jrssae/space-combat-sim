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
type Cells = HashMap<Cell, Vec<u32>, BuildHasherDefault<CellHasher>>;

/// Hulls placed in a grid of levels: per level its cells (each holding its hulls ascending), its hulls ascending and its
/// largest reach; the hulls that fit no cell are loose.
#[derive(Default)]
pub struct CellGrid {
    cells: Vec<Cells>,
    members: Vec<Vec<u32>>,
    level_reach: Vec<f64>,
    loose: Vec<u32>,
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
            self.cells[level]
                .entry((key.0 as i32, key.1 as i32, key.2 as i32))
                .or_default()
                .push(j as u32);
            self.members[level].push(j as u32);
            if reach > self.level_reach[level] {
                self.level_reach[level] = reach;
            }
        }
    }

    // Fills `candidates` with the hulls a projectile at `at` with reach `own` must test, ascending.
    fn look(&self, at: Vector3, own: f64, candidates: &mut Vec<u32>) {
        candidates.clear();
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
                candidates.extend_from_slice(&self.members[level]);
                continue;
            }
            let cells = &self.cells[level];
            for cx in lx as i32..=hx as i32 {
                for cy in ly as i32..=hy as i32 {
                    for cz in lz as i32..=hz as i32 {
                        let key: &Cell = &(cx, cy, cz);
                        if let Some(held) = cells.get(key) {
                            candidates.extend_from_slice(held);
                        }
                    }
                }
            }
        }
        candidates.extend_from_slice(&self.loose);
        candidates.sort_unstable();
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
        grid.look(at, bolt_reach[i].abs(), candidates);
        *visited += candidates.len() as i64;
        for &j in candidates.iter() {
            let j = j as usize;
            let reach = bolt_reach[i] + hull_reach[j];
            if f64::from(dist_sq(at, hulls[j])) > reach * reach {
                continue;
            }
            out.push(i as i64 * hull_count + j as i64);
        }
    }
    out
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
