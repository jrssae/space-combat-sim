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
//!   path meets the station's hull: missiles first, then the bolt that hits soonest, one per battery per interval, and only
//!   one inside the battery's arc that the station's hull does not hide from it. Beams are never candidates.
//! - **Interceptor pulses** (M7-T41): a battery's shot is a pulse in the projectile pool, fired from its next ready barrel on a
//!   lead course with a seeded spread; each tick every pulse sweeps against the hostile missiles and bolts near it (found through
//!   the hit broad phase's cells) and takes the first it meets. A pulse can miss; it never harms a ship or a hull.
//! - **Line of fire.** Every big hull's surface (the station's frame and drum) blocks a grid gun's line.
#![allow(clippy::too_many_arguments)]

use godot::builtin::{Basis, Vector3};

use crate::kernels::contact::{self, Grid, Query, View};
use crate::rows::{Bolts, Rows};
use crate::surface;
use crate::sweep_cells::CellGrid;
use crate::turret_kernels::{self as tk, PickMount, REL_FRIENDLY, REL_HOSTILE, relation};
use crate::v3::{add, dist_sq, dot, length, normalized, scale, sub, xform};

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
/// An interceptor battery's pulse (M7-T41): it flies like a bolt but meets only hostile missiles and bolts, never a hull.
pub const KIND_INTERCEPT: u8 = 9;
/// The most barrels a battery has.
pub const MAX_BARRELS: usize = 4;
/// A pulse still in flight covers its target until this long after the meeting its lead predicted, s; past it the pulse missed
/// and the target may be shot at again.
pub const COVER_SLACK_S: f64 = 0.1;
const TIME_EPSILON_S: f64 = 1e-6;
/// How often at most a battery's barrel is laid again on the lead from its muzzle, and the muzzle's move that ends it
/// (1 mm, squared).
const LAY_PASSES: usize = 6;
const LAY_SETTLED_M2: f64 = 1e-6;
/// How far ahead an interceptor follows a projectile's straight path to the hull, s (its own life when shorter).
pub const INTERCEPT_HORIZON_S: f64 = 6.0;
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

/// A bolt not yet swept against the hull this tick, in `incoming`'s cache of hull times.
pub const NOT_SWEPT: f64 = f64::NAN;

/// An interceptor battery's incoming fire at `pivot` within `reach_m`: each hostile missile or bolt (`interceptable`) whose
/// path meets the hull, in bolt order. `hull_times` (one per bolt, `NOT_SWEPT` at the tick's start, shared by the batteries)
/// keeps each bolt's `time_to_hull` so it is swept once a tick, not once per battery.
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
    out.clear();
    let reach_sq = reach_m * reach_m;
    for p in 0..bolts.ids.len() {
        if !interceptable(bolts, p, grid, relations, stride) || f64::from(dist_sq(bolts.positions[p], pivot)) > reach_sq {
            continue;
        }
        let when = &mut hull_times[p];
        if when.is_nan() {
            *when = time_to_hull(rows, surface_rows, bolts, p, now_s).unwrap_or(f64::INFINITY);
        }
        if when.is_finite() {
            out.push(Incoming {
                bolt: p as u32,
                missile: bolts.kinds[p] == KIND_MISSILE,
                hit_in_s: *when,
            });
        }
    }
}

/// The battery's order among `candidates` not yet `taken` this tick, reach aside: a missile before any bolt, then the one that
/// hits the hull soonest; among equals the earlier bolt row. Play uses `choose_in_reach`.
#[cfg(test)]
pub fn choose(candidates: &[Incoming], taken: &[bool]) -> Option<Incoming> {
    choose_where(candidates, taken, |_| true)
}

/// `choose` among the candidates a battery at `f` can shoot (M7-T40): inside its arc (`min_elevation` up) and with its line
/// clear of every big hull, as a grid gun's. Only a candidate that would win is tested, to keep the hull sweeps rare.
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
    choose_in_reach_if(rows, surface_rows, bolts, f, min_elevation, candidates, taken, |_| true)
}

/// `choose_in_reach` among the candidates `also` accepts too (M7-T41: not covered by a pulse already on its way, and one the
/// battery's pulse can reach); `also` is asked before the hull line, which costs most.
pub fn choose_in_reach_if<A: FnMut(&Incoming) -> bool>(
    rows: &Rows,
    surface_rows: &[usize],
    bolts: &Bolts,
    f: &tk::Frame,
    min_elevation: f64,
    candidates: &[Incoming],
    taken: &[bool],
    mut also: A,
) -> Option<Incoming> {
    let from = tk::line_start(f);
    choose_where(candidates, taken, |c| {
        let at = bolts.positions[c.bolt as usize];
        let (_, elevation) = tk::angles_of(f, normalized(sub(at, f.pivot)));
        elevation >= min_elevation && also(c) && !line_blocked(rows, surface_rows, from, at)
    })
}

// The best untaken candidate that `ok` accepts; `ok` is asked only of one that would beat the best so far.
fn choose_where<F: FnMut(&Incoming) -> bool>(candidates: &[Incoming], taken: &[bool], mut ok: F) -> Option<Incoming> {
    let mut best: Option<Incoming> = None;
    for c in candidates {
        if taken.get(c.bolt as usize).copied().unwrap_or(false) {
            continue;
        }
        let better = match best {
            None => true,
            Some(b) => (c.missile && !b.missile) || (c.missile == b.missile && c.hit_in_s < b.hit_in_s),
        };
        if better && ok(c) {
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

/// An interceptor battery's barrels (M7-T41): the trunnion in the yaw frame and each muzzle in the pitch frame (metres, as
/// `TurretMount`'s Yaw and Pitch nodes hold them), each barrel's recharge, when each is ready and which fires next. They fire
/// in turn: the battery's own interval spaces the shots, and a barrel fires again only once recharged.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Battery {
    pub trunnion: Vector3,
    pub muzzles: [Vector3; MAX_BARRELS],
    pub count: usize,
    pub recharge_s: f64,
    pub ready_at: [f64; MAX_BARRELS],
    pub next: usize,
}

impl Battery {
    /// One barrel `barrel_m` down the axis from the pivot, recharging as the gun's interval: a battery with no model data.
    pub fn single(barrel_m: f64, recharge_s: f64) -> Self {
        Self::with(Vector3::ZERO, &[Vector3::new(0.0, 0.0, -barrel_m as f32)], recharge_s)
    }

    /// Barrels at `muzzles` (at most `MAX_BARRELS`; none gives one at the trunnion), every one ready.
    pub fn with(trunnion: Vector3, muzzles: &[Vector3], recharge_s: f64) -> Self {
        let mut at = [Vector3::ZERO; MAX_BARRELS];
        let count = muzzles.len().clamp(1, MAX_BARRELS);
        for (k, m) in muzzles.iter().take(MAX_BARRELS).enumerate() {
            at[k] = *m;
        }
        Self {
            trunnion,
            muzzles: at,
            count,
            recharge_s: recharge_s.max(0.0),
            ready_at: [f64::NEG_INFINITY; MAX_BARRELS],
            next: 0,
        }
    }

    /// Whether the barrel next in turn has recharged at `now_s`.
    pub fn barrel_ready(&self, now_s: f64) -> bool {
        now_s + TIME_EPSILON_S >= self.ready_at[self.next]
    }

    /// Fires the barrel next in turn at `now_s` and returns it.
    pub fn fire(&mut self, now_s: f64) -> usize {
        let b = self.next;
        self.ready_at[b] = now_s + self.recharge_s;
        self.next = (b + 1) % self.count;
        b
    }
}

/// Where a muzzle is in the World: the mount turned to `azimuth` round its up and lifted to `elevation`, as `TurretMount` turns
/// its Yaw and Pitch nodes, `trunnion` in the yaw frame and `muzzle` in the pitch frame (Godot axes: -z down the barrel).
pub fn muzzle_point(f: &tk::Frame, azimuth: f64, elevation: f64, trunnion: Vector3, muzzle: Vector3) -> Vector3 {
    let (se, ce) = elevation.sin_cos();
    let (sa, ca) = azimuth.sin_cos();
    let (mx, my, mz) = (f64::from(muzzle.x), f64::from(muzzle.y), f64::from(muzzle.z));
    let (px, py, pz) = (mx, my * ce - mz * se, my * se + mz * ce);
    let (lx, ly, lz) = (f64::from(trunnion.x) + px, f64::from(trunnion.y) + py, f64::from(trunnion.z) + pz);
    let (yx, yy, yz) = (lx * ca + lz * sa, ly, -lx * sa + lz * ca);
    // The mount's Godot basis: x opposite the frame's side, y its up, z opposite its forward.
    let along = add(scale(f.side, -yx as f32), add(scale(f.up, yy as f32), scale(f.forward, -yz as f32)));
    add(f.pivot, along)
}

/// A battery's shot (M7-T41): where the pulse leaves, its line, its flight time to the meeting, and the angles the mount shows.
pub struct BatteryShot {
    pub muzzle: Vector3,
    pub aim: Vector3,
    pub flight_s: f64,
    pub azimuth: f64,
    pub elevation: f64,
}

/// The barrel a battery fires: the arc's floor, the azimuth the mount holds now, the trunnion in the yaw frame and the muzzle in
/// the pitch frame.
pub struct Barrel {
    pub min_elevation: f64,
    pub azimuth: f64,
    pub trunnion: Vector3,
    pub muzzle: Vector3,
}

/// The azimuth and elevation that bring a barrel's line through `point` (M8-T10): a barrel beside or over the trunnion needs a
/// little more or less turn and lift than the trunnion's own line. Turning cannot bring a barrel onto a point nearer the
/// mount's axis than the barrel stands beside it (a target right overhead), so the mount keeps its azimuth there. The
/// elevation stays inside the arc.
pub fn lay_on(f: &tk::Frame, b: &Barrel, point: Vector3) -> (f64, f64) {
    let rel = sub(point, f.pivot);
    let (along, across) = (f64::from(dot(rel, f.forward)), f64::from(dot(rel, f.side)));
    let beside = f64::from(b.trunnion.x) + f64::from(b.muzzle.x);
    let flat = along.hypot(across);
    let azimuth = if flat > beside.abs() {
        let turned = across.atan2(along) + (beside / flat).asin();
        turned - std::f64::consts::TAU * (turned / std::f64::consts::TAU).round()
    } else {
        b.azimuth
    };
    let (sa, ca) = azimuth.sin_cos();
    // The point as the trunnion sees it in the plane the barrels lift in.
    let ahead = along * ca + across * sa + f64::from(b.trunnion.z);
    let above = f64::from(dot(rel, f.up)) - f64::from(b.trunnion.y);
    let over = f64::from(b.muzzle.y);
    let reach = ahead.hypot(above);
    let less = if reach > over.abs() { (over / reach).asin() } else { 0.0 };
    (azimuth, (above.atan2(ahead) - less).clamp(b.min_elevation, std::f64::consts::FRAC_PI_2))
}

/// A battery's shot at a projectile: the pulse leaves the tip of the barrel as it is drawn and, wherever the mount can turn
/// that far, along that barrel, however close the target (M8-T10). The barrel is laid through the meeting the trunnion's lead
/// gives, the pulse led from the muzzle that puts, and the barrel laid again until the muzzle settles; the pulse's line is
/// always the lead from where it starts. A lead is its line and flight time at `pulse_speed`; `lead_from` leads from a point
/// (none without a solution).
pub fn battery_shot(
    f: &tk::Frame,
    b: &Barrel,
    pulse_speed: f64,
    trunnion_lead: (Vector3, f64),
    lead_from: impl Fn(Vector3) -> Option<(Vector3, f64)>,
) -> BatteryShot {
    let lay = |from: Vector3, (aim, flight_s): (Vector3, f64)| {
        let (az, el) = lay_on(f, b, add(from, scale(aim, (pulse_speed * flight_s) as f32)));
        (az, el, muzzle_point(f, az, el, b.trunnion, b.muzzle))
    };
    let mut lead = trunnion_lead;
    let (mut azimuth, mut elevation, mut at) = lay(muzzle_point(f, b.azimuth, 0.0, b.trunnion, Vector3::ZERO), lead);
    let mut settled = false;
    for _ in 0..LAY_PASSES {
        let Some(from_muzzle) = lead_from(at) else {
            settled = true;
            break;
        };
        lead = from_muzzle;
        let was = at;
        (azimuth, elevation, at) = lay(was, lead);
        if f64::from(dist_sq(at, was)) < LAY_SETTLED_M2 {
            settled = true;
            break;
        }
    }
    if !settled && let Some(from_muzzle) = lead_from(at) {
        lead = from_muzzle;
    }
    BatteryShot {
        muzzle: at,
        aim: lead.0,
        flight_s: lead.1,
        azimuth,
        elevation,
    }
}

/// When along the tick two spheres moving in straight lines first touch, as a share of the tick (0 to 1): `a` from `a_start`
/// by `a_step`, `b` likewise, their radii summed `reach`; none when they stay apart.
pub fn first_touch(a_start: Vector3, a_step: Vector3, b_start: Vector3, b_step: Vector3, reach: f64) -> Option<f64> {
    let d = sub(a_start, b_start);
    let v = sub(a_step, b_step);
    let (dx, dy, dz) = (f64::from(d.x), f64::from(d.y), f64::from(d.z));
    let (vx, vy, vz) = (f64::from(v.x), f64::from(v.y), f64::from(v.z));
    let c = dx * dx + dy * dy + dz * dz - reach * reach;
    if c <= 0.0 {
        return Some(0.0);
    }
    let a = vx * vx + vy * vy + vz * vz;
    let b = dx * vx + dy * vy + dz * vz;
    if a <= 0.0 || b >= 0.0 {
        return None;
    }
    let disc = b * b - a * c;
    if disc < 0.0 {
        return None;
    }
    let t = (-b - disc.sqrt()) / a;
    (t <= 1.0).then_some(t.max(0.0))
}

/// A pulse that met a projectile this tick: both bolt rows and where along the tick (0 to 1).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PulseHit {
    pub pulse: u32,
    pub target: u32,
    pub t: f64,
}

/// The pulse sweep's reused buffers.
#[derive(Default)]
pub struct PulseScratch {
    targets: Vec<u32>,
    mids: Vec<Vector3>,
    reach: Vec<f64>,
    candidates: Vec<u32>,
    gone: Vec<bool>,
    pub cells: CellGrid,
}

/// This tick's pulse hits (M7-T41), in pulse row order: each live pulse takes the first live missile or pulse bolt of a side
/// hostile to it that its swept sphere touches along the bolts' last move (the earliest touch; among equals the lower row), and
/// a projectile is taken once. The projectiles are placed in the hit broad phase's cells, so a pulse tests only those near it.
pub fn pulse_hits(bolts: &Bolts, relations: &[u8], stride: usize, scratch: &mut PulseScratch, out: &mut Vec<PulseHit>) {
    out.clear();
    let n = bolts.ids.len();
    if !(0..n).any(|p| bolts.kinds[p] == KIND_INTERCEPT && !bolts.spent[p]) {
        return;
    }
    let s = scratch;
    s.targets.clear();
    s.mids.clear();
    s.reach.clear();
    for p in 0..n {
        let kind = bolts.kinds[p];
        if (kind != KIND_MISSILE && kind != KIND_BOLT) || bolts.spent[p] {
            continue;
        }
        let step = bolts.last_steps[p];
        s.targets.push(p as u32);
        s.mids.push(sub(bolts.positions[p], scale(step, 0.5)));
        s.reach.push(f64::from(length(step)) * 0.5 + bolts.radii[p]);
    }
    if s.targets.is_empty() {
        return;
    }
    s.cells.place(&s.mids, &s.reach);
    s.gone.clear();
    s.gone.resize(s.targets.len(), false);
    for p in 0..n {
        if bolts.kinds[p] != KIND_INTERCEPT || bolts.spent[p] {
            continue;
        }
        let step = bolts.last_steps[p];
        let start = sub(bolts.positions[p], step);
        let mid = sub(bolts.positions[p], scale(step, 0.5));
        s.cells.look(mid, f64::from(length(step)) * 0.5 + bolts.radii[p], &mut s.candidates);
        let mut best: Option<(f64, usize)> = None;
        for &j in &s.candidates {
            let j = j as usize;
            let q = s.targets[j] as usize;
            if s.gone[j] || relation(relations, stride, bolts.faction_ix[p], bolts.faction_ix[q]) != REL_HOSTILE {
                continue;
            }
            let q_step = bolts.last_steps[q];
            let q_start = sub(bolts.positions[q], q_step);
            let Some(t) = first_touch(start, step, q_start, q_step, bolts.radii[p] + bolts.radii[q]) else {
                continue;
            };
            if best.is_none_or(|(bt, bj)| t < bt || (t == bt && j < bj)) {
                best = Some((t, j));
            }
        }
        if let Some((t, j)) = best {
            s.gone[j] = true;
            out.push(PulseHit {
                pulse: p as u32,
                target: s.targets[j],
                t,
            });
        }
    }
}

#[cfg(test)]
mod tests;
