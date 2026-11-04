// What each AI ship perceives this tick, answered natively behind ContactScan (M4-T05b, docs/architecture.md 17.5).
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use std::cmp::Ordering;

use godot::obj::InstanceId;
use godot::prelude::*;

// The closest-approach test of incoming fire, as `ContactScan` defines it.
const INCOMING_MISS_M: f64 = 15.0;
const INCOMING_HORIZON_S: f64 = 2.0;
// Grid queries pad their box so a body the 32-bit range test accepts is never in an unvisited cell.
const PAD_REL: f64 = 1e-6;
const PAD_M: f64 = 1.0;
// `BodyKind` values of the rows that are obstacles, not contacts (src/ai/body_kind.gd).
const KIND_MINE: u8 = 4;
const KIND_STATIC: u8 = 5;

/// One tick's bodies and bolts, handed over once by `ContactScan`, with per-ship queries that return body indices in
/// scan order. The maths repeats GDScript's: 32-bit vectors, 64-bit scalars, the engine's order of operations and no
/// fused multiply-add, so both paths give the same answers bit for bit. Never calls `Factions`: the facade sends each
/// querying faction's hostility row.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsContactField {
    base: Base<RefCounted>,
    body_ids: Vec<i64>,
    positions: Vec<Vector3>,
    body_faction: Vec<usize>,
    is_ship: Vec<bool>,
    reach: Vec<f64>,
    factions: Vec<StringName>,
    hostile_rows: Vec<(StringName, Vec<bool>)>,
    bolt_positions: Vec<Vector3>,
    bolt_velocities: Vec<Vector3>,
    bolt_faction: Vec<usize>,
    bolt_shooters: Vec<i64>,
    // Rocks and mines (M4-T09): never contacts, found by `statics` by their surface distance.
    is_static: Vec<bool>,
    radii: Vec<f64>,
    max_static_radius: f64,
    cell_m: f64,
    // Bodies sorted by grid cell, then by scan index.
    cells: Vec<((i32, i32, i32), u32)>,
    visited: i64,
    candidates: Vec<u32>,
    in_range: Vec<(f32, u32)>,
    in_reach: Vec<(f64, u32)>,
}

#[godot_api]
impl ScsContactField {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Takes this tick's scan: bodies (with each one's broadcast reach, empty when not a broadcast scan), bolts, and
    /// the grid's cell size (the sensor range). Returns false, after logging why, when the arrays do not line up; the
    /// field then holds an empty scan, so every query answers nothing and the caller can fall back to GDScript.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn load(
        &mut self,
        body_ids: PackedInt64Array,
        positions: PackedVector3Array,
        factions: Array<StringName>,
        is_ship: PackedByteArray,
        reach: PackedFloat64Array,
        bolt_positions: PackedVector3Array,
        bolt_velocities: PackedVector3Array,
        bolt_factions: Array<StringName>,
        bolt_shooters: PackedInt64Array,
        cell_m: f64,
    ) -> bool {
        let n = body_ids.len();
        let lined_up = positions.len() == n
            && factions.len() == n
            && is_ship.len() == n
            && (reach.is_empty() || reach.len() == n)
            && bolt_velocities.len() == bolt_positions.len()
            && bolt_factions.len() == bolt_positions.len()
            && bolt_shooters.len() == bolt_positions.len();
        if !lined_up {
            godot_error!(
                "ScsContactField.load: array lengths differ (bodies {n}, positions {}, factions {}, is_ship {}, reach {}, \
                 bolts {}, velocities {}, bolt factions {}, shooters {}); the scan is dropped",
                positions.len(),
                factions.len(),
                is_ship.len(),
                reach.len(),
                bolt_positions.len(),
                bolt_velocities.len(),
                bolt_factions.len(),
                bolt_shooters.len()
            );
            self.clear();
            return false;
        }
        self.body_ids = body_ids.as_slice().to_vec();
        self.positions = positions.as_slice().to_vec();
        self.is_ship = is_ship.as_slice().iter().map(|&b| b == 1).collect();
        self.reach = reach.as_slice().to_vec();
        self.factions.clear();
        self.hostile_rows.clear();
        self.body_faction = factions
            .iter_shared()
            .map(|f| self.faction_index(f))
            .collect();
        self.bolt_positions = bolt_positions.as_slice().to_vec();
        self.bolt_velocities = bolt_velocities.as_slice().to_vec();
        self.bolt_faction = bolt_factions
            .iter_shared()
            .map(|f| self.faction_index(f))
            .collect();
        self.bolt_shooters = bolt_shooters.as_slice().to_vec();
        self.is_static = vec![false; n];
        self.radii.clear();
        self.max_static_radius = 0.0;
        self.cell_m = cell_m;
        let cell = self.cell_m;
        self.cells = self
            .positions
            .iter()
            .enumerate()
            .map(|(i, p)| {
                let key = (
                    cell_of(f64::from(p.x), cell),
                    cell_of(f64::from(p.y), cell),
                    cell_of(f64::from(p.z), cell),
                );
                (key, i as u32)
            })
            .collect();
        self.cells.sort_unstable();
        self.visited = 0;
        true
    }

    /// Says which loaded bodies are rocks or mines (`BodyKind` values, M4-T09) and every body's radius: those rows are
    /// never contacts, and `statics` finds them. Returns false, after logging why, when the arrays do not match the
    /// loaded bodies; the field then holds an empty scan, as a rejected `load` does.
    #[func]
    fn set_kinds(&mut self, kinds: PackedByteArray, radii: PackedFloat64Array) -> bool {
        let n = self.body_ids.len();
        if kinds.len() != n || radii.len() != n {
            godot_error!(
                "ScsContactField.set_kinds: array lengths differ (bodies {n}, kinds {}, radii {}); the scan is dropped",
                kinds.len(),
                radii.len()
            );
            self.clear();
            return false;
        }
        self.is_static = kinds
            .as_slice()
            .iter()
            .map(|&k| k == KIND_MINE || k == KIND_STATIC)
            .collect();
        self.radii = radii.as_slice().to_vec();
        self.max_static_radius = (0..n)
            .filter(|&i| self.is_static[i])
            .map(|i| self.radii[i].abs())
            .fold(0.0, f64::max);
        true
    }

    /// Every faction in the scan, in the order `set_hostile_row` expects.
    #[func]
    fn factions(&self) -> Array<StringName> {
        self.factions.iter().cloned().collect()
    }

    /// Which factions (in `factions()` order) are hostile to `faction`.
    #[func]
    fn set_hostile_row(&mut self, faction: StringName, row: PackedByteArray) {
        let flags: Vec<bool> = row.as_slice().iter().map(|&b| b == 1).collect();
        self.hostile_rows.retain(|(f, _)| *f != faction);
        self.hostile_rows.push((faction, flags));
    }

    /// Whether every body in the scan still exists.
    #[func]
    fn bodies_alive(&self) -> bool {
        self.body_ids
            .iter()
            .all(|&id| InstanceId::try_from_i64(id).is_some_and(|i| i.lookup_validity()))
    }

    /// Bodies the latest contact or nearest query tested against its range (the work count).
    #[func]
    fn visited(&self) -> i64 {
        self.visited
    }

    /// `ContactScan.contacts_for`: the bodies within `range` of `at`, not `own_body_id`, in scan order.
    #[func]
    fn contacts(&mut self, own_body_id: i64, at: Vector3, range: f64) -> PackedInt32Array {
        let range_sq = range * range;
        self.gather(own_body_id, at, range, |_, d_sq| {
            f64::from(d_sq) <= range_sq
        });
        let out: Vec<i32> = self.in_range.iter().map(|&(_, i)| i as i32).collect();
        PackedInt32Array::from(out.as_slice())
    }

    /// `ContactScan.nearest_for` before its keeper: with `k` or fewer in range (or `k` 0 or less), all of them in scan order; otherwise
    /// the nearest `k` (equal ranges to the earlier body) plus the nearest hostile ship, in any order, then -1 to say
    /// the cut left something out.
    #[func]
    fn nearest(
        &mut self,
        own_body_id: i64,
        at: Vector3,
        faction: StringName,
        k: i64,
        range: f64,
    ) -> PackedInt32Array {
        let range_sq = range * range;
        // GDScript's nearest loop skips only what is beyond the range, so its test is "not greater".
        self.gather(own_body_id, at, range, |_, d_sq| {
            f64::from(d_sq).partial_cmp(&range_sq) != Some(Ordering::Greater)
        });
        // k of 0 or less means no cut: every contact in range, as `ContactScan.nearest_for` defines it.
        if k <= 0 || self.in_range.len() <= k as usize {
            let out: Vec<i32> = self.in_range.iter().map(|&(_, i)| i as i32).collect();
            return PackedInt32Array::from(out.as_slice());
        }
        let hostile = self.hostile_row(&faction);
        let mut nearest_hostile: Option<(f32, u32)> = None;
        for &(d_sq, i) in &self.in_range {
            let j = i as usize;
            let is_hostile =
                self.is_ship[j] && hostile.is_some_and(|row| hostile_at(row, self.body_faction[j]));
            if is_hostile && nearest_hostile.is_none_or(|(best, _)| d_sq < best) {
                nearest_hostile = Some((d_sq, i));
            }
        }
        // Ranked by range, then by scan index (in_range is in scan order, so a stable sort keeps that).
        let k = k as usize;
        let mut ranked = self.in_range.clone();
        ranked.select_nth_unstable_by(k - 1, |a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
        let mut out: Vec<i32> = ranked[..k].iter().map(|&(_, i)| i as i32).collect();
        if let Some((_, h)) = nearest_hostile
            && !out.contains(&(h as i32))
        {
            out.push(h as i32);
        }
        out.push(-1);
        PackedInt32Array::from(out.as_slice())
    }

    /// `ContactScan.statics_for`: the rocks and mines whose surface is within `range` of `at`, not `own_body_id`; with `k`
    /// or fewer, all of them, otherwise the `k` nearest by surface distance (equal ones to the earlier row); in scan order.
    #[func]
    fn statics(&mut self, own_body_id: i64, at: Vector3, k: i64, range: f64) -> PackedInt32Array {
        if k <= 0 {
            return PackedInt32Array::new();
        }
        let reach = range.abs();
        self.in_reach.clear();
        self.collect_candidates(at, reach + self.max_static_radius, reach.is_finite());
        for &i in &self.candidates {
            let j = i as usize;
            if !self.is_static[j] || self.body_ids[j] == own_body_id {
                continue;
            }
            // `position.distance_to(at) - radius`, with GDScript's 32-bit length.
            let surface = f64::from(length(sub(at, self.positions[j]))) - self.radii[j];
            if surface <= reach {
                self.in_reach.push((surface, i));
            }
        }
        let k = k as usize;
        if self.in_reach.len() > k {
            self.in_reach
                .select_nth_unstable_by(k - 1, |a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
            self.in_reach.truncate(k);
            self.in_reach.sort_unstable_by_key(|e| e.1);
        }
        let out: Vec<i32> = self.in_reach.iter().map(|&(_, i)| i as i32).collect();
        PackedInt32Array::from(out.as_slice())
    }

    /// `ContactScan.broadcasts_for`: the bodies beyond `near` and within their own reach, not `own_body_id`, in scan order.
    #[func]
    fn broadcasts(&self, own_body_id: i64, at: Vector3, near: f64) -> PackedInt32Array {
        let near_sq = near * near;
        let mut out: Vec<i32> = Vec::new();
        for (i, p) in self.positions.iter().enumerate() {
            if self.body_ids[i] == own_body_id {
                continue;
            }
            let d_sq = f64::from(dist_sq(*p, at));
            let reach = self.reach.get(i).copied().unwrap_or(0.0);
            if d_sq > near_sq && d_sq <= reach * reach {
                out.push(i as i32);
            }
        }
        PackedInt32Array::from(out.as_slice())
    }

    /// `ContactScan.incoming_fire`: hostile bolts, not this ship's own, that pass within 15 m in the next 2 s.
    #[func]
    fn incoming(
        &self,
        own_body_id: i64,
        at: Vector3,
        velocity: Vector3,
        faction: StringName,
    ) -> i64 {
        let Some(hostile) = self.hostile_row(&faction) else {
            return 0;
        };
        let mut count: i64 = 0;
        for i in 0..self.bolt_positions.len() {
            if !hostile_at(hostile, self.bolt_faction[i]) || self.bolt_shooters[i] == own_body_id {
                continue;
            }
            let rel_pos = sub(self.bolt_positions[i], at);
            let rel_vel = sub(self.bolt_velocities[i], velocity);
            let reach = f64::from(length(rel_vel)) * INCOMING_HORIZON_S + INCOMING_MISS_M + 1.0;
            if f64::from(length_squared(rel_pos)) > reach * reach {
                continue;
            }
            if closest_approach(rel_pos, rel_vel, INCOMING_HORIZON_S) < INCOMING_MISS_M {
                count += 1;
            }
        }
        count
    }
}

impl ScsContactField {
    // Forgets the whole scan, so a rejected load leaves nothing for a query to index.
    fn clear(&mut self) {
        self.body_ids.clear();
        self.positions.clear();
        self.body_faction.clear();
        self.is_ship.clear();
        self.reach.clear();
        self.factions.clear();
        self.hostile_rows.clear();
        self.bolt_positions.clear();
        self.bolt_velocities.clear();
        self.bolt_faction.clear();
        self.bolt_shooters.clear();
        self.is_static.clear();
        self.radii.clear();
        self.max_static_radius = 0.0;
        self.cells.clear();
        self.candidates.clear();
        self.in_range.clear();
        self.visited = 0;
    }

    // The index of `faction` in this scan's faction list, added on first sight.
    fn faction_index(&mut self, faction: StringName) -> usize {
        if let Some(at) = self.factions.iter().position(|f| *f == faction) {
            return at;
        }
        self.factions.push(faction);
        self.factions.len() - 1
    }

    fn hostile_row(&self, faction: &StringName) -> Option<&[bool]> {
        self.hostile_rows
            .iter()
            .find(|(f, _)| f == faction)
            .map(|(_, row)| row.as_slice())
    }

    // Fills `in_range` with the bodies near `at` that `accept` takes by squared distance, but not `own_body_id` and never a
    // rock or mine, in scan order.
    fn gather(
        &mut self,
        own_body_id: i64,
        at: Vector3,
        range: f64,
        accept: impl Fn(usize, f32) -> bool,
    ) {
        self.in_range.clear();
        self.collect_candidates(at, range.abs(), range.is_finite());
        for &i in &self.candidates {
            let j = i as usize;
            if self.is_static[j] {
                continue;
            }
            let d_sq = dist_sq(self.positions[j], at);
            if accept(j, d_sq) && self.body_ids[j] != own_body_id {
                self.in_range.push((d_sq, i));
            }
        }
    }

    // Fills `candidates` with the bodies in the grid cells within `reach` of `at`, in scan order, or every body when that
    // box would hold more cells than bodies. Counts them as the latest query's visits.
    fn collect_candidates(&mut self, at: Vector3, reach: f64, finite: bool) {
        self.candidates.clear();
        let pad = reach * (1.0 + PAD_REL) + PAD_M;
        let lo = |v: f32| cell_of(f64::from(v) - pad, self.cell_m);
        let hi = |v: f32| cell_of(f64::from(v) + pad, self.cell_m);
        let (lx, ly, lz) = (lo(at.x), lo(at.y), lo(at.z));
        let (hx, hy, hz) = (hi(at.x), hi(at.y), hi(at.z));
        // A huge range saturates the cell indices, so the box can hold more cells than a 64-bit count: too many to walk.
        let span = |l: i32, h: i32| i64::from(h) - i64::from(l) + 1;
        let columns = span(lx, hx).checked_mul(span(ly, hy));
        let grid_usable =
            self.cell_m > 0.0 && finite && columns.is_some_and(|c| c <= self.cells.len() as i64);
        if grid_usable {
            for cx in lx..=hx {
                for cy in ly..=hy {
                    let start = self.cells.partition_point(|e| e.0 < (cx, cy, lz));
                    let end = self.cells.partition_point(|e| e.0 <= (cx, cy, hz));
                    self.candidates
                        .extend(self.cells[start..end].iter().map(|e| e.1));
                }
            }
            self.candidates.sort_unstable();
        } else {
            self.candidates.extend(0..self.positions.len() as u32);
        }
        self.visited = self.candidates.len() as i64;
    }
}

// Whether faction `index` is hostile in `row`; a row too short to hold it says no.
fn hostile_at(row: &[bool], index: usize) -> bool {
    row.get(index).copied().unwrap_or(false)
}

// The grid cell holding coordinate `v`.
fn cell_of(v: f64, cell_m: f64) -> i32 {
    if cell_m > 0.0 {
        (v / cell_m).floor() as i32
    } else {
        0
    }
}

// Godot's Vector3 maths in 32 bits, in the engine's order of operations.
fn sub(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x - b.x, a.y - b.y, a.z - b.z)
}

fn length_squared(v: Vector3) -> f32 {
    let x2 = v.x * v.x;
    let y2 = v.y * v.y;
    let z2 = v.z * v.z;
    x2 + y2 + z2
}

fn length(v: Vector3) -> f32 {
    length_squared(v).sqrt()
}

fn dot(a: Vector3, b: Vector3) -> f32 {
    a.x * b.x + a.y * b.y + a.z * b.z
}

// `a.distance_squared_to(b)`.
fn dist_sq(a: Vector3, b: Vector3) -> f32 {
    length_squared(sub(b, a))
}

// `AvoidanceMath.closest_approach`: 64-bit scalars around 32-bit vectors, as GDScript evaluates it.
fn closest_approach(rel_pos: Vector3, rel_vel: Vector3, horizon_s: f64) -> f64 {
    let speed_sq = f64::from(length_squared(rel_vel));
    if speed_sq < 1e-12 {
        return f64::from(length(rel_pos));
    }
    let raw = -f64::from(dot(rel_pos, rel_vel)) / speed_sq;
    let t = if raw < 0.0 {
        0.0
    } else if raw > horizon_s {
        horizon_s
    } else {
        raw
    };
    // A Vector3 times a float rounds the float to 32 bits first.
    let t32 = t as f32;
    let at = Vector3::new(
        rel_pos.x + rel_vel.x * t32,
        rel_pos.y + rel_vel.y * t32,
        rel_pos.z + rel_vel.z * t32,
    );
    f64::from(length(at))
}
