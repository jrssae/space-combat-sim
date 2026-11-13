//! The station's defence grid (M7-T07, D75): its guns and interceptor batteries as kinds of the turret rows
//! (`turret_kernels`), with no engine type in this file (`test_sim_core` reads it and fails on one).
//!
//! - **Never first.** The guns hold fire until a hostile fires on the station or on a friendly near it; from then on the grid
//!   is weapons free against that side (`Latch`, written on the main thread in the hit sweep's order and by the interceptors'
//!   look at incoming fire). The pick reads a frozen copy in the AI job.
//! - **The pick** (in the AI job, one tick behind) looks up hostiles near each gun through the brains' broad phase, not the
//!   attacker memory: light pulse turrets take fighters, heavy cannons take capitals first and fighters only when none is in
//!   reach; inside the arc before outside it, nearest first.
//! - **Interceptors** (main thread: a shot down projectile is gone the same tick) take hostile missiles and pulse bolts whose
//!   path meets the station's hull: missiles first, then the bolt that hits soonest, one per battery per interval. Beams
//!   are never candidates.
//! - **Line of fire.** Every big hull's surface (the station's frame and drum) blocks a grid gun's line.
#![allow(clippy::too_many_arguments)]

use godot::builtin::{Basis, Vector3};

use crate::kernels::contact::{self, Grid, Query, View};
use crate::rows::{Bolts, Rows};
use crate::surface;
use crate::turret_kernels::{self as tk, PickMount, REL_FRIENDLY, REL_HOSTILE, relation};
use crate::v3::{add, dist_sq, dot, normalized, scale, sub, xform};

/// A mount's kind: a ship's defensive turret (M5-T21's remembered-attacker pick) or one of the grid's three.
pub const MOUNT_TURRET: u8 = 0;
pub const MOUNT_LIGHT: u8 = 1;
pub const MOUNT_HEAVY: u8 = 2;
pub const MOUNT_INTERCEPTOR: u8 = 3;
/// Hulls up to this radius are fighters to the grid; anything larger (and every capital) is a capital, m. As the capitals'
/// stand-in guns read it (`weapon_kernels::FIGHTER_RADIUS_MAX_M`).
pub const FIGHTER_RADIUS_MAX_M: f64 = 50.0;
/// `BodyKind` values and projectile kinds as the core packs them (`sim_core::KIND_NAMES`).
pub const KIND_CAPITAL: u8 = 1;
pub const KIND_MISSILE: u8 = 3;
pub const KIND_BOLT: u8 = 7;
/// How far ahead an interceptor follows a projectile's straight path to the hull, s (its own life when shorter).
pub const INTERCEPT_HORIZON_S: f64 = 6.0;
// Score offsets that rank the pick's classes ahead of distance: out of the arc, then the heavy cannon's fighters.
const ARC_PENALTY: f64 = 4.0;
const CLASS_PENALTY: f64 = 16.0;

/// Which grid people are weapons free against which side: `(grid faction, enemy faction)` pairs in the order they were set.
#[derive(Default, Clone, Debug, PartialEq)]
pub struct Latch {
    pub pairs: Vec<(u32, u32)>,
}

impl Latch {
    /// Sets the grid of `grid` weapons free against `enemy`; true when it was not already.
    pub fn set(&mut self, grid: u32, enemy: u32) -> bool {
        if self.is_free(grid, enemy) {
            return false;
        }
        self.pairs.push((grid, enemy));
        true
    }

    pub fn is_free(&self, grid: u32, enemy: u32) -> bool {
        self.pairs.iter().any(|&p| p == (grid, enemy))
    }

    pub fn free_any(&self, grid: u32) -> bool {
        self.pairs.iter().any(|&(g, _)| g == grid)
    }

    /// Holds fire against `enemy` again (all sides for `None`).
    pub fn hold(&mut self, grid: u32, enemy: Option<u32>) {
        self.pairs.retain(|&(g, e)| g != grid || enemy.is_some_and(|x| x != e));
    }
}

/// Whether row `r` is a capital to the grid: a capital or any hull bigger than a fighter.
pub fn is_capital(rows: &Rows, r: usize) -> bool {
    rows.kinds.get(r).copied() == Some(KIND_CAPITAL) || rows.radii[r] > FIGHTER_RADIUS_MAX_M
}

/// Whether the World line from `from` to `to` enters a big hull among `surface_rows` (rows with a surface) that `from` is not
/// already inside: the station's own frame and drum blocking a grid gun.
pub fn line_blocked(rows: &Rows, surface_rows: &[usize], from: Vector3, to: Vector3) -> bool {
    surface_rows.iter().any(|&j| {
        rows.surface(j).is_some_and(|s| {
            let (basis, origin) = (&rows.bases[j], rows.positions[j]);
            surface::enters_from_outside(s, surface::into_body(basis, origin, from), surface::into_body(basis, origin, to))
        })
    })
}

/// The rows with a surface, by body id in `bodies`' order (`row_of` gives a body's row or -1).
pub fn surface_rows_of<F: Fn(i64) -> i64>(rows: &Rows, row_of: &F, bodies: &[i64], out: &mut Vec<usize>) {
    out.clear();
    for &b in bodies {
        if let Ok(r) = usize::try_from(row_of(b))
            && r < rows.flags.len()
            && rows.surface(r).is_some()
        {
            out.push(r);
        }
    }
}

/// The row a grid mount fires from: a live hull (a big hull has no rigid body), not a tier row.
pub fn firing_row(rows: &Rows, row: i64) -> Option<usize> {
    tk::usable_row(rows, row)
}

/// A grid mount's velocity at `pivot`: its row's, plus a turning surface's skin speed there (the drum's mounts).
pub fn mount_velocity(rows: &Rows, r: usize, pivot: Vector3) -> Vector3 {
    let v = rows.velocities[r];
    match rows.surface(r) {
        Some(s) if s.spin_rad_s != 0.0 => add(
            v,
            surface::surface_velocity(&rows.bases[r], rows.positions[r], s.spin_rad_s, pivot),
        ),
        _ => v,
    }
}

/// What a grid gun's pick works with besides the rows: the relations, the latch, the big hulls that block it, the brains'
/// broad phase and the caller's scratch.
pub struct PickCtx<'a> {
    pub relations: &'a [u8],
    pub stride: usize,
    pub latch: &'a Latch,
    pub surface_rows: &'a [usize],
    pub grid: &'a Grid,
    pub query: &'a mut Query,
    pub found: &'a mut Vec<i32>,
}

/// A grid gun's target (a body id, 0 for none): the nearest hostile of a side the grid is weapons free against within its
/// reach, looked up through the broad phase. A light pulse turret takes fighters only; a heavy cannon takes capitals first.
/// Inside the arc before outside it; a target the station's hull hides is never picked.
pub fn pick<F: Fn(i64) -> i64>(rows: &Rows, row_of: &F, m: &PickMount, ctx: &mut PickCtx<'_>) -> i64 {
    if (m.kind != MOUNT_LIGHT && m.kind != MOUNT_HEAVY) || !ctx.latch.free_any(m.faction_ix) {
        return 0;
    }
    let Some(own) = firing_row(rows, row_of(m.body)) else {
        return 0;
    };
    let basis = &rows.bases[own];
    let pivot = add(xform(basis, m.local), rows.positions[own]);
    let up = normalized(xform(basis, m.up));
    let from = add(pivot, scale(up, tk::LINE_LIFT_M as f32));
    let view = View {
        body_ids: &rows.body_ids,
        positions: &rows.positions,
        body_faction: &rows.faction_ix,
        is_ship: &rows.rigid,
        reach: &rows.reach,
        is_static: &rows.is_static,
        is_mine: &rows.is_mine,
        radii: &rows.radii,
        bolt_positions: &[],
        bolt_velocities: &[],
        bolt_faction: &[],
        bolt_shooters: &[],
    };
    let mut work = contact::Work {
        grid: ctx.grid,
        query: ctx.query,
    };
    contact::contacts_into(&view, &mut work, m.body, pivot, m.reach_m, ctx.found);
    let reach_sq = m.reach_m * m.reach_m;
    let mut best = 0;
    let mut best_score = f64::INFINITY;
    for &c in ctx.found.iter() {
        let Some(j) = tk::usable_row(rows, i64::from(c)) else {
            continue;
        };
        if !rows.rigid[j] || rows.surface(j).is_some() {
            continue;
        }
        let side = rows.faction_ix[j];
        if relation(ctx.relations, ctx.stride, m.faction_ix, side) != REL_HOSTILE || !ctx.latch.is_free(m.faction_ix, side) {
            continue;
        }
        let capital = is_capital(rows, j);
        if m.kind == MOUNT_LIGHT && capital {
            continue;
        }
        let d_sq = f64::from(dist_sq(rows.positions[j], pivot));
        if d_sq > reach_sq {
            continue;
        }
        let toward = normalized(sub(rows.positions[j], pivot));
        let elevation = f64::from(dot(toward, up)).clamp(-1.0, 1.0).asin();
        let mut score = d_sq;
        if elevation < m.min_elevation {
            score += ARC_PENALTY * reach_sq;
        }
        if m.kind == MOUNT_HEAVY && !capital {
            score += CLASS_PENALTY * reach_sq;
        }
        // The hull is tested only for a candidate that would win, off the common path.
        if score < best_score && !line_blocked(rows, ctx.surface_rows, from, rows.positions[j]) {
            best_score = score;
            best = rows.body_ids[j];
        }
    }
    best
}

/// A projectile an interceptor may take: its bolt row, whether it is a missile and how soon its path meets the hull, s.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Incoming {
    pub bolt: u32,
    pub missile: bool,
    pub hit_in_s: f64,
}

/// How soon bolt `p`'s straight path meets one of `surface_rows`' hulls, s (followed for its life, at most
/// `INTERCEPT_HORIZON_S`), or none. The path is taken relative to each hull's motion.
pub fn time_to_hull(rows: &Rows, surface_rows: &[usize], bolts: &Bolts, p: usize, now_s: f64) -> Option<f64> {
    let life = bolts.expires_at[p] - now_s;
    let horizon = if life.is_finite() && life > 0.0 { life.min(INTERCEPT_HORIZON_S) } else { INTERCEPT_HORIZON_S };
    let start = bolts.positions[p];
    let mut best: Option<f64> = None;
    for &j in surface_rows {
        let Some(s) = rows.surface(j) else {
            continue;
        };
        let (basis, origin): (&Basis, Vector3) = (&rows.bases[j], rows.positions[j]);
        let relative = sub(bolts.velocities[p], rows.velocities[j]);
        let end = add(start, scale(relative, horizon as f32));
        let a = surface::into_body(basis, origin, start);
        let b = surface::into_body(basis, origin, end);
        if let Some((t, _)) = surface::sweep(s, a, b, bolts.radii[p]) {
            let when = t * horizon;
            if best.is_none_or(|w| when < w) {
                best = Some(when);
            }
        }
    }
    best
}

/// Whether bolt `p` is a projectile an interceptor of faction `grid` may take: a missile or a pulse bolt (never a beam or a
/// mine), not spent, of a side hostile to it.
pub fn interceptable(bolts: &Bolts, p: usize, grid: u32, relations: &[u8], stride: usize) -> bool {
    let kind = bolts.kinds[p];
    (kind == KIND_MISSILE || kind == KIND_BOLT)
        && !bolts.spent[p]
        && relation(relations, stride, grid, bolts.faction_ix[p]) == REL_HOSTILE
}

/// An interceptor battery's incoming fire at `pivot` within `reach_m`: each hostile missile or bolt (`interceptable`) whose
/// path meets the hull, in bolt order.
pub fn incoming(
    rows: &Rows,
    surface_rows: &[usize],
    bolts: &Bolts,
    grid: u32,
    relations: &[u8],
    stride: usize,
    pivot: Vector3,
    reach_m: f64,
    now_s: f64,
    out: &mut Vec<Incoming>,
) {
    out.clear();
    let reach_sq = reach_m * reach_m;
    for p in 0..bolts.ids.len() {
        if !interceptable(bolts, p, grid, relations, stride) || f64::from(dist_sq(bolts.positions[p], pivot)) > reach_sq {
            continue;
        }
        if let Some(hit_in_s) = time_to_hull(rows, surface_rows, bolts, p, now_s) {
            out.push(Incoming {
                bolt: p as u32,
                missile: bolts.kinds[p] == KIND_MISSILE,
                hit_in_s,
            });
        }
    }
}

/// The battery's choice among `candidates` not yet `taken` this tick: a missile before any bolt, then the one that hits the
/// hull soonest; among equals the earlier bolt row.
pub fn choose(candidates: &[Incoming], taken: &[bool]) -> Option<Incoming> {
    let mut best: Option<Incoming> = None;
    for c in candidates {
        if taken.get(c.bolt as usize).copied().unwrap_or(false) {
            continue;
        }
        let better = match best {
            None => true,
            Some(b) => (c.missile && !b.missile) || (c.missile == b.missile && c.hit_in_s < b.hit_in_s),
        };
        if better {
            best = Some(*c);
        }
    }
    best
}

/// Whether a hit on `victim` (a row) by a ship of `enemy` sets the grid of `grid` weapons free: the enemy is hostile to it,
/// and the victim is a big hull friendly to it (the station itself) or a friendly within `near(victim)` of a grid gun.
pub fn hit_frees<N: Fn(Vector3) -> bool>(
    rows: &Rows,
    victim: usize,
    enemy: u32,
    grid: u32,
    relations: &[u8],
    stride: usize,
    near: N,
) -> bool {
    if relation(relations, stride, grid, enemy) != REL_HOSTILE {
        return false;
    }
    if relation(relations, stride, grid, rows.faction_ix[victim]) != REL_FRIENDLY {
        return false;
    }
    rows.surface(victim).is_some() || near(rows.positions[victim])
}

#[cfg(test)]
mod tests;
