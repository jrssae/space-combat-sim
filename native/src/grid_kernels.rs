//! The station's defense grid (M7-T07, D75): its guns and interceptor batteries as kinds of the turret rows
//! (`turret_kernels`), with no engine type in this file (`test_sim_core` reads it and fails on one).
//!
//! - **Never first.** The guns hold fire until a hostile fires on the station or on a friendly near it; from then on the grid
//!   is weapons free against that side (`Latch`, written on the main thread in the hit sweep's order and by the interceptors'
//!   look at incoming fire). The pick reads a frozen copy in the AI job.
//! - **The pick** (in the AI job, one tick behind) looks up hostiles near each gun through the brains' broad phase, not the
//!   attacker memory: light pulse turrets take fighters first, heavy cannons capitals first, each the other class only when
//!   none of its own is in reach; inside the arc before outside it, nearest first. A knocked-out mount neither picks nor fires.
//! - **Sub-points.** Each grid mount's place and whether it still works (`mount_points`), for the AI to aim at (T10).
//! - **Interceptors** (main thread: a shot down projectile is gone the same tick) take hostile missiles and pulse bolts whose
//!   path meets the station's hull, on the battery model the capitals share (`intercept_kernels`, M10-T13): missiles first,
//!   then the bolt that hits soonest, one per battery per interval, inside its arc and not behind the station's hull; a pulse
//!   flies, can miss, and a tough shot takes several (Q81). The grid reads true factions (Q55) and guards every big hull.
//! - **Line of fire.** Every big hull's surface (the station's frame and drum) blocks a grid gun's line.
#![allow(clippy::too_many_arguments)]

// The grid's tests read the builtins through this module.
#[cfg_attr(not(test), allow(unused_imports))]
use godot::builtin::{Basis, Vector3};

use crate::intercept_kernels::{self as ik, Incoming};
#[cfg(test)]
use crate::intercept_kernels::{
    Barrel, Battery, BatteryShot, NOT_SWEPT, PulseHit, PulseScratch, battery_shot, first_touch, lay_on, muzzle_point,
    time_to_hull,
};
use crate::kernels::contact::{self, Grid, Query, View};
use crate::rows::{Bolts, Rows};
use crate::surface;
use crate::turret_kernels::{self as tk, PickMount, REL_FRIENDLY, REL_HOSTILE, relation};
use crate::v3::{add, dist_sq, dot, normalized, scale, sub, xform};
#[cfg(test)]
use crate::v3::length;

/// A mount's kind: a ship's defensive turret (M5-T21's remembered-attacker pick) or one of the grid's three.
pub const MOUNT_TURRET: u8 = 0;
pub const MOUNT_LIGHT: u8 = 1;
pub const MOUNT_HEAVY: u8 = 2;
pub const MOUNT_INTERCEPTOR: u8 = 3;
/// Hulls up to this radius are fighters to the grid; anything larger (and every capital) is a capital, m. As the capitals'
/// stand-in guns read it (`weapon_kernels::FIGHTER_RADIUS_MAX_M`).
pub const FIGHTER_RADIUS_MAX_M: f64 = 50.0;
/// `BodyKind` values and projectile kinds as the core packs them (`sim_core::KIND_NAMES`); the shots and pulses are the shared
/// battery model's (`intercept_kernels`).
pub const KIND_CAPITAL: u8 = 1;
pub const KIND_MISSILE: u8 = ik::KIND_MISSILE;
#[cfg(test)]
pub const KIND_BOLT: u8 = ik::KIND_BOLT;
pub const KIND_INTERCEPT: u8 = ik::KIND_INTERCEPT;
// Score offsets that rank the pick's classes ahead of distance: out of the arc, then the heavy cannon's fighters.
const ARC_PENALTY: f64 = 4.0;
const CLASS_PENALTY: f64 = 16.0;
// Under covering fire, every hostile outside the covered ship's radius ranks behind every one inside it.
const COVER_PENALTY: f64 = 64.0;

/// Which grid people are weapons free against which side: `(grid faction, enemy faction)` pairs in the order they were set.
/// Beside it the station's own orders (M8-T34): grids switched off, and covering fire asked for round a ship.
#[derive(Default, Clone, Debug, PartialEq)]
pub struct Latch {
    pub pairs: Vec<(u32, u32)>,
    /// Grid people whose grid is off: no gun or interceptor of theirs fires.
    pub off: Vec<u32>,
    /// Covering fire: each grid's guns take hostiles near the ship that asked first, latched or not.
    pub cover: Vec<Cover>,
}

/// A covering-fire order (M8-T34): the guns of grid people `grid` engage hostiles within `radius_m` of body `body`, the one
/// nearest that body first, whether or not the grid is weapons free against their side.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Cover {
    pub grid: u32,
    pub body: i64,
    pub radius_m: f64,
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

    /// Switches grid `grid` off (no fire at all) or on again; true when that changed it.
    pub fn set_off(&mut self, grid: u32, off: bool) -> bool {
        let was = self.is_off(grid);
        self.off.retain(|&g| g != grid);
        if off {
            self.off.push(grid);
        }
        was != off
    }

    pub fn is_off(&self, grid: u32) -> bool {
        self.off.contains(&grid)
    }

    /// Covering fire for grid `grid` round body `body` within `radius_m`, or none (`body` 0).
    pub fn set_cover(&mut self, grid: u32, body: i64, radius_m: f64) {
        self.cover.retain(|c| c.grid != grid);
        if body != 0 && radius_m > 0.0 {
            self.cover.push(Cover { grid, body, radius_m });
        }
    }

    pub fn cover_of(&self, grid: u32) -> Option<Cover> {
        self.cover.iter().copied().find(|c| c.grid == grid)
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
/// reach, looked up through the broad phase. A light pulse turret takes fighters first and a capital only when no fighter is
/// in reach; a heavy cannon the other way round.
/// Inside the arc before outside it; a target the station's hull hides is never picked. A grid that is off picks nothing.
/// Under covering fire (M8-T34) any hostile within the covered ship's radius comes first, nearest that ship first, whatever
/// its class and whether or not the grid is weapons free against its side.
pub fn pick<F: Fn(i64) -> i64>(rows: &Rows, row_of: &F, m: &PickMount, ctx: &mut PickCtx<'_>) -> i64 {
    if (m.kind != MOUNT_LIGHT && m.kind != MOUNT_HEAVY) || ctx.latch.is_off(m.faction_ix) {
        return 0;
    }
    let cover = ctx.latch.cover_of(m.faction_ix).and_then(|c| {
        tk::usable_row(rows, row_of(c.body)).map(|r| (rows.positions[r], c.radius_m * c.radius_m))
    });
    if cover.is_none() && !ctx.latch.free_any(m.faction_ix) {
        return 0;
    }
    let Some(own) = firing_row(rows, row_of(m.body)) else {
        return 0;
    };
    let basis = &rows.bases[own];
    let pivot = add(xform(basis, m.local), rows.positions[own]);
    let up = normalized(xform(basis, m.up));
    let from = add(pivot, scale(up, m.line_lift_m as f32));
    let view = View {
        body_ids: &rows.body_ids,
        positions: &rows.positions,
        body_faction: &rows.faction_ix,
        body_flags: &[],
        observer: u32::MAX,
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
        if relation(ctx.relations, ctx.stride, m.faction_ix, side) != REL_HOSTILE {
            continue;
        }
        let covered = cover.map(|(at, _)| f64::from(dist_sq(rows.positions[j], at)));
        let near = cover.is_some_and(|(_, r_sq)| covered.is_some_and(|d| d <= r_sq));
        if !near && !ctx.latch.is_free(m.faction_ix, side) {
            continue;
        }
        let capital = is_capital(rows, j);
        let d_sq = f64::from(dist_sq(rows.positions[j], pivot));
        if d_sq > reach_sq {
            continue;
        }
        let toward = normalized(sub(rows.positions[j], pivot));
        let elevation = f64::from(dot(toward, up)).clamp(-1.0, 1.0).asin();
        let mut score = if near { covered.unwrap_or(d_sq) } else { d_sq };
        if elevation < m.min_elevation {
            score += ARC_PENALTY * reach_sq;
        }
        if !near {
            // Each gun's own class first: a light turret's fighters, a heavy cannon's capitals (maintainer, after T07).
            if (m.kind == MOUNT_HEAVY) != capital {
                score += CLASS_PENALTY * reach_sq;
            }
            if cover.is_some() {
                score += COVER_PENALTY * reach_sq;
            }
        }
        // The hull is tested only for a candidate that would win, off the common path.
        if score < best_score && !line_blocked(rows, ctx.surface_rows, from, rows.positions[j]) {
            best_score = score;
            best = rows.body_ids[j];
        }
    }
    best
}

/// Every grid mount's World place and whether it still works (not knocked out, its body's row usable), in slot order, with its
/// slot and kind: what an attacker can aim at (M7-T10). Ship turrets are left out.
pub fn mount_points<F: Fn(i64) -> i64>(rows: &Rows, row_of: &F, mounts: &tk::Mounts, out: &mut Vec<MountPoint>) {
    out.clear();
    for s in 0..mounts.taken.len() {
        if !mounts.taken[s] || mounts.kind[s] == MOUNT_TURRET {
            continue;
        }
        let row = firing_row(rows, row_of(mounts.body[s]));
        let at = row.map_or(Vector3::ZERO, |r| add(xform(&rows.bases[r], mounts.local[s]), rows.positions[r]));
        out.push(MountPoint {
            slot: s as u32,
            kind: mounts.kind[s],
            at,
            alive: row.is_some() && mounts.live[s] && !mounts.out[s],
        });
    }
}

/// One grid mount as an attacker sees it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MountPoint {
    pub slot: u32,
    pub kind: u8,
    pub at: Vector3,
    pub alive: bool,
}

/// Whether bolt `p` is a shot an interceptor of faction `grid` may take: a missile or a pulse bolt (never a beam or a mine),
/// not spent, of a side hostile to it (the grid reads true factions, Q55).
pub fn interceptable(bolts: &Bolts, p: usize, grid: u32, relations: &[u8], stride: usize) -> bool {
    ik::is_shot(bolts, p) && relation(relations, stride, grid, bolts.faction_ix[p]) == REL_HOSTILE
}

/// A grid battery's incoming fire at `pivot` within `reach_m`: each hostile missile or bolt (`interceptable`) whose path meets
/// the station's hull, in bolt order (the shared `intercept_kernels::gather`, every big hull guarded). `hull_times` (one per
/// bolt, `NOT_SWEPT` at the tick's start, shared by the batteries) keeps each bolt's `time_to_hull` so it is swept once a
/// tick, not once per battery.
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
    hull_times: &mut [f64],
    out: &mut Vec<Incoming>,
) {
    ik::gather(
        bolts,
        0..bolts.ids.len(),
        pivot,
        reach_m,
        |p| interceptable(bolts, p, grid, relations, stride),
        |p| {
            let when = &mut hull_times[p];
            if when.is_nan() {
                *when = ik::time_to_hull(rows, surface_rows, bolts, p, now_s).unwrap_or(f64::INFINITY);
            }
            *when
        },
        out,
    );
}

/// The battery's order among `candidates` not yet `taken` this tick, reach aside: a missile before any bolt, then the one that
/// hits the hull soonest; among equals the earlier bolt row. Play uses `intercept_kernels::fire_battery`.
#[cfg(test)]
pub fn choose(candidates: &[Incoming], taken: &[bool]) -> Option<Incoming> {
    ik::choose_by(candidates, |_| 0, |c| !taken.get(c.bolt as usize).copied().unwrap_or(false))
}

/// `choose` among the candidates a battery at `f` can shoot (M7-T40): inside its arc (`min_elevation` up) and with its line
/// clear of every big hull, as a grid gun's.
#[cfg(test)]
pub fn choose_in_reach(
    rows: &Rows,
    surface_rows: &[usize],
    bolts: &Bolts,
    f: &tk::Frame,
    min_elevation: f64,
    candidates: &[Incoming],
    taken: &[bool],
) -> Option<Incoming> {
    let from = tk::line_start(f);
    ik::choose_by(candidates, |_| 0, |c| {
        let at = bolts.positions[c.bolt as usize];
        let (_, elevation) = tk::angles_of(f, normalized(sub(at, f.pivot)));
        !taken.get(c.bolt as usize).copied().unwrap_or(false)
            && elevation >= min_elevation
            && !line_blocked(rows, surface_rows, from, at)
    })
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
/// This tick's hits of every pulse in flight (M7-T41): the shared sweep (`intercept_kernels::pulse_hits_by`) with the grid's
/// true-faction relations: a pulse takes only a side hostile to its own.
pub fn pulse_hits(bolts: &Bolts, relations: &[u8], stride: usize, scratch: &mut PulseScratch, out: &mut Vec<PulseHit>) {
    ik::pulse_hits_by(
        bolts,
        |_| true,
        |p, q| relation(relations, stride, bolts.faction_ix[p], bolts.faction_ix[q]) == REL_HOSTILE,
        scratch,
        out,
    );
}

#[cfg(test)]
mod tests;
