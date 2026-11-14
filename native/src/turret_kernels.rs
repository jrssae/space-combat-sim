//! Defensive turrets (M5-T21, D61): a gunner on a ship, not a pilot. The mounts, the attacker memory and the kernels that
//! drive them, with no engine type in this file (`test_sim_core` reads it and fails on one). The pick is a decision: it
//! runs in the AI job one tick behind on a frozen copy (`PickJob`), and its answers are applied at the join against each
//! mount's stamp. The aim, the fire gate and the shot write a bolt row the same tick, so they run on the main thread in
//! the core's step. Work is linear in mounts times remembered attackers, never a sweep over every ship. These extend
//! M4-T20's turret stand-ins (`weapon_kernels.rs`) into real mounts: arcs, slew rates, lead and a spread. A ship's own hull
//! blocks its turrets' fire (Q33): the gate and the pick test the line against the ship's own hit volumes.
#![allow(clippy::too_many_arguments)]

use std::collections::HashMap;
use std::f64::consts::{FRAC_PI_2, PI, TAU};

use godot::builtin::{Basis, Vector3};

use crate::brain_maths::solve;
use crate::grid_kernels::{self, Latch, MOUNT_INTERCEPTOR, MOUNT_TURRET};
use crate::kernels::contact::{Grid, Query};
use crate::rows::{FLAG_HULL_ACTIVE, FLAG_RIGID, FLAG_TIER, Rows};
use crate::v3::{add, col_a, col_b, col_c, cross, dist_sq, dot, normalized, scale, sub, xform};

/// Where a turret's line of fire starts (Q33): this far above its base along its up, about the barrels' trunnion, which
/// stands clear of the hull however the barrel points (the tip may dip into the hull; the trunnion cannot).
pub const LINE_LIFT_M: f64 = 1.5;

/// How long a ship stays an attacker of a victim after one of its bolts hit it, s (D61).
pub const MEMORY_S: f64 = 30.0;
/// How far from a turret's ship a civilian or ally may be for the turret to defend it, m (D61).
pub const PROTECT_M: f64 = 2000.0;
/// How much further than its range a turret picks a target, so it is already aimed when the target comes in.
pub const PICK_REACH: f64 = 1.25;
/// The faction table's relations as the core packs them (`Factions.Relation`).
pub const REL_FRIENDLY: u8 = 0;
pub const REL_NEUTRAL: u8 = 1;
pub const REL_HOSTILE: u8 = 2;
// A gate's slack on its ready time, as the cannons' gate has.
const TIME_EPSILON_S: f64 = 1e-6;

/// What a mount's gun is: set once when it is registered.
#[derive(Clone, Copy, Default)]
pub struct Gun {
    pub muzzle_speed: f64,
    pub interval_s: f64,
    pub lifetime_s: f64,
    pub damage: f64,
    pub hit_radius: f64,
    pub range_m: f64,
    pub spread_rad: f64,
    pub traverse_rad_s: f64,
    pub elevation_rad_s: f64,
    pub color: [f32; 4],
    pub look: u8,
}

/// Every mount, column by column, by slot (a removed mount's slot is reused). Bound to its ship by body id: the ship's
/// row gives the pose each tick. The stamp changes whenever the binding does, so a pick for an older binding is dropped.
#[derive(Default, Clone)]
pub struct Mounts {
    pub taken: Vec<bool>,
    pub id: Vec<i64>,
    pub stamp: Vec<u32>,
    pub body: Vec<i64>,
    pub faction_ix: Vec<u32>,
    pub live: Vec<bool>,
    pub local: Vec<Vector3>,
    pub up: Vec<Vector3>,
    pub forward: Vec<Vector3>,
    pub min_elevation: Vec<f64>,
    pub barrel_m: Vec<f64>,
    pub gun: Vec<Gun>,
    pub azimuth: Vec<f64>,
    pub elevation: Vec<f64>,
    pub target: Vec<i64>,
    pub ready_at: Vec<f64>,
    pub shots: Vec<i64>,
    /// `grid_kernels::MOUNT_*`: a ship's turret, or one of the station grid's kinds (M7-T07).
    pub kind: Vec<u8>,
    /// Knocked out (M7-T07: a grid mount whose health is gone): it neither picks nor fires until repaired.
    pub out: Vec<bool>,
}

impl Mounts {
    /// Adds a mount on body `body` at `local` (body frame) facing `up`, with a cone of `arc_deg` round `up`, and returns
    /// its slot. `id` is what its spread is hashed from; `stamp` its first binding.
    pub fn add(
        &mut self,
        id: i64,
        stamp: u32,
        body: i64,
        faction_ix: u32,
        local: Vector3,
        up: Vector3,
        arc_deg: f64,
        barrel_m: f64,
        gun: Gun,
    ) -> usize {
        let up = unit_or(up, Vector3::new(0.0, 1.0, 0.0));
        let forward = rest_forward(up);
        let min_elevation = (90.0 - arc_deg.clamp(0.0, 360.0) * 0.5).to_radians();
        let slot = self
            .taken
            .iter()
            .position(|&u| !u)
            .unwrap_or(self.taken.len());
        if slot == self.taken.len() {
            self.taken.push(false);
            self.id.push(0);
            self.stamp.push(0);
            self.body.push(0);
            self.faction_ix.push(0);
            self.live.push(false);
            self.local.push(Vector3::ZERO);
            self.up.push(Vector3::ZERO);
            self.forward.push(Vector3::ZERO);
            self.min_elevation.push(0.0);
            self.barrel_m.push(0.0);
            self.gun.push(Gun::default());
            self.azimuth.push(0.0);
            self.elevation.push(0.0);
            self.target.push(0);
            self.ready_at.push(f64::NEG_INFINITY);
            self.shots.push(0);
            self.kind.push(MOUNT_TURRET);
            self.out.push(false);
        }
        self.taken[slot] = true;
        self.id[slot] = id;
        self.stamp[slot] = stamp;
        self.body[slot] = body;
        self.faction_ix[slot] = faction_ix;
        self.live[slot] = true;
        self.local[slot] = local;
        self.up[slot] = up;
        self.forward[slot] = forward;
        self.min_elevation[slot] = min_elevation.min(FRAC_PI_2);
        self.barrel_m[slot] = barrel_m.max(0.0);
        self.gun[slot] = gun;
        self.azimuth[slot] = 0.0;
        self.elevation[slot] = min_elevation.max(0.0).min(FRAC_PI_2);
        self.target[slot] = 0;
        self.ready_at[slot] = f64::NEG_INFINITY;
        self.shots[slot] = 0;
        self.kind[slot] = MOUNT_TURRET;
        self.out[slot] = false;
        slot
    }

    /// Whether `slot` holds a mount.
    pub fn has(&self, slot: usize) -> bool {
        slot < self.taken.len() && self.taken[slot]
    }

    /// Frees a slot; any pick still out for it is stale.
    pub fn remove(&mut self, slot: usize) {
        if self.has(slot) {
            self.taken[slot] = false;
            self.live[slot] = false;
            self.target[slot] = 0;
            self.stamp[slot] = self.stamp[slot].wrapping_add(1);
        }
    }

    /// Mounts in use.
    pub fn count(&self) -> usize {
        self.taken.iter().filter(|&&u| u).count()
    }
}

/// Who hit whom: a ship is an attacker of a victim until `until_s`, refreshed by each hit. Written on the main thread in
/// the hit sweep's order; the pick reads a frozen copy.
#[derive(Default, Clone)]
pub struct Memory {
    pub victim: Vec<i64>,
    pub attacker: Vec<i64>,
    pub until_s: Vec<f64>,
    pub civilian: Vec<bool>,
}

impl Memory {
    /// One hit of `attacker`'s bolt on `victim` at `now_s`.
    pub fn note(&mut self, victim: i64, attacker: i64, now_s: f64, civilian: bool) {
        if victim == attacker || victim == 0 || attacker == 0 {
            return;
        }
        let until = now_s + MEMORY_S;
        for k in 0..self.victim.len() {
            if self.victim[k] == victim && self.attacker[k] == attacker {
                self.until_s[k] = self.until_s[k].max(until);
                self.civilian[k] = civilian;
                return;
            }
        }
        self.victim.push(victim);
        self.attacker.push(attacker);
        self.until_s.push(until);
        self.civilian.push(civilian);
    }

    /// Drops what is older than the memory lasts, keeping the order of the rest.
    pub fn prune(&mut self, now_s: f64) {
        self.retain(|m, k| m.until_s[k] >= now_s);
    }

    /// Forgets a ship as attacker and as victim (it was destroyed: a ship from the pool is someone new).
    pub fn forget(&mut self, body: i64) {
        self.retain(|m, k| m.victim[k] != body && m.attacker[k] != body);
    }

    pub fn len(&self) -> usize {
        self.victim.len()
    }

    pub fn is_empty(&self) -> bool {
        self.victim.is_empty()
    }

    pub fn clear(&mut self) {
        self.victim.clear();
        self.attacker.clear();
        self.until_s.clear();
        self.civilian.clear();
    }

    fn retain(&mut self, keep: impl Fn(&Memory, usize) -> bool) {
        let mut w = 0;
        for k in 0..self.victim.len() {
            if keep(self, k) {
                self.victim[w] = self.victim[k];
                self.attacker[w] = self.attacker[k];
                self.until_s[w] = self.until_s[k];
                self.civilian[w] = self.civilian[k];
                w += 1;
            }
        }
        self.victim.truncate(w);
        self.attacker.truncate(w);
        self.until_s.truncate(w);
        self.civilian.truncate(w);
    }
}

/// One mount as the pick sees it.
#[derive(Clone, Copy)]
pub struct PickMount {
    pub slot: u32,
    pub stamp: u32,
    pub body: i64,
    pub faction_ix: u32,
    pub local: Vector3,
    pub up: Vector3,
    pub min_elevation: f64,
    pub reach_m: f64,
    /// `grid_kernels::MOUNT_*` (M7-T07).
    pub kind: u8,
}

/// A pick's answer: the target for a mount's binding (0 for none).
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Pick {
    pub slot: u32,
    pub stamp: u32,
    pub target: i64,
}

/// The pick's share of a job: the live mounts and the memory as the launch found them, the relations by the core's
/// faction indices (`stride` wide), and the answers.
#[derive(Default)]
pub struct PickJob {
    pub mounts: Vec<PickMount>,
    pub memory: Memory,
    pub relations: Vec<u8>,
    pub stride: usize,
    pub picks: Vec<Pick>,
    /// The turreted ships' own hit volumes (Q33), copied again only when they changed (`hulls_version`).
    pub hulls: Hulls,
    /// The grid's weapons-free latch and the big hulls that block its guns (M7-T07), and the grid pick's scratch.
    pub latch: Latch,
    pub surface_bodies: Vec<i64>,
    pub query: Query,
    pub found: Vec<i32>,
    pub surface_rows: Vec<usize>,
    /// Every working grid mount, interceptors too (M7-T10): what a raid on the station aims at.
    pub points: Vec<AimPoint>,
}

/// A working grid mount as the launch found it: its slot, its hull's body and its pivot in that hull's frame.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct AimPoint {
    pub slot: u32,
    pub body: i64,
    pub local: Vector3,
}

impl PickJob {
    /// Fills the job from the mounts and memory as they stand (the launch's copy).
    pub fn take_from(
        &mut self,
        mounts: &Mounts,
        memory: &Memory,
        relations: &[u8],
        stride: usize,
        hulls: &Hulls,
        latch: &Latch,
        surface_bodies: &[i64],
    ) {
        if self.hulls.version != hulls.version {
            self.hulls.clone_from(hulls);
        }
        self.points.clear();
        for s in 0..mounts.taken.len() {
            if mounts.taken[s] && mounts.live[s] && !mounts.out[s] && mounts.kind[s] != MOUNT_TURRET {
                self.points.push(AimPoint {
                    slot: s as u32,
                    body: mounts.body[s],
                    local: mounts.local[s],
                });
            }
        }
        self.mounts.clear();
        for s in 0..mounts.taken.len() {
            // An interceptor's choice is made on the main thread, where it shoots the same tick.
            if !mounts.taken[s] || !mounts.live[s] || mounts.out[s] || mounts.kind[s] == MOUNT_INTERCEPTOR {
                continue;
            }
            self.mounts.push(PickMount {
                slot: s as u32,
                stamp: mounts.stamp[s],
                body: mounts.body[s],
                faction_ix: mounts.faction_ix[s],
                local: mounts.local[s],
                up: mounts.up[s],
                min_elevation: mounts.min_elevation[s],
                reach_m: mounts.gun[s].range_m * PICK_REACH,
                kind: mounts.kind[s],
            });
        }
        self.memory.clone_from(memory);
        self.relations.clear();
        self.relations.extend_from_slice(relations);
        self.stride = stride;
        self.latch.clone_from(latch);
        self.surface_bodies.clear();
        self.surface_bodies.extend_from_slice(surface_bodies);
        self.picks.clear();
    }

    pub fn clear(&mut self) {
        self.points.clear();
        self.mounts.clear();
        self.memory.clear();
        self.picks.clear();
    }
}

/// How faction `a` regards faction `b` in a packed table; neutral when either is outside it.
pub fn relation(relations: &[u8], stride: usize, a: u32, b: u32) -> u8 {
    let (a, b) = (a as usize, b as usize);
    if a >= stride || b >= stride {
        return if a == b { REL_FRIENDLY } else { REL_NEUTRAL };
    }
    relations.get(a * stride + b).copied().unwrap_or(REL_NEUTRAL)
}

/// Every live mount's target, from the frozen rows (`row_of` gives a body's row, or -1) and the frozen memory at `now_s`; the
/// grid's guns look through the brains' broad phase `grid` (M7-T07).
pub fn pick_all<F: Fn(i64) -> i64>(rows: &Rows, row_of: F, now_s: f64, job: &mut PickJob, grid: &Grid) {
    let PickJob {
        mounts,
        memory,
        relations,
        stride,
        picks,
        hulls,
        latch,
        surface_bodies,
        query,
        found,
        surface_rows,
        ..
    } = job;
    picks.clear();
    grid_kernels::surface_rows_of(rows, &row_of, surface_bodies, surface_rows);
    for m in mounts.iter() {
        let target = if m.kind == MOUNT_TURRET {
            pick(rows, &row_of, m, memory, relations, *stride, now_s, hulls.of(m.body))
        } else {
            let mut ctx = grid_kernels::PickCtx {
                relations,
                stride: *stride,
                latch,
                surface_rows,
                grid,
                query,
                found,
            };
            grid_kernels::pick(rows, &row_of, m, &mut ctx)
        };
        picks.push(Pick {
            slot: m.slot,
            stamp: m.stamp,
            target,
        });
    }
}

/// One mount's pick: the nearest remembered attacker of its own ship, or of a civilian or ally within `PROTECT_M` of it,
/// that is alive, not friendly and within the mount's reach; one inside the arc before one outside it. An attacker its own
/// hull hides (`own`, the ship's volumes, Q33) is not picked, so a turret never holds a target it cannot shoot. 0 for none.
pub fn pick<F: Fn(i64) -> i64>(
    rows: &Rows,
    row_of: &F,
    m: &PickMount,
    memory: &Memory,
    relations: &[u8],
    stride: usize,
    now_s: f64,
    own_hull: &[Volume],
) -> i64 {
    if memory.is_empty() {
        return 0;
    }
    let Some(own) = usable_row(rows, row_of(m.body)) else {
        return 0;
    };
    let ship_at = rows.positions[own];
    let basis = &rows.bases[own];
    let pivot = add(xform(basis, m.local), ship_at);
    let up = normalized(xform(basis, m.up));
    let reach_sq = m.reach_m * m.reach_m;
    let protect_sq = PROTECT_M * PROTECT_M;
    let mut best = 0;
    let mut best_score = f64::INFINITY;
    for k in 0..memory.len() {
        if memory.until_s[k] < now_s {
            continue;
        }
        let attacker = memory.attacker[k];
        if attacker == m.body {
            continue;
        }
        let victim = memory.victim[k];
        if victim != m.body {
            let Some(v) = usable_row(rows, row_of(victim)) else {
                continue;
            };
            // Between skins for a big civilian hull (M5-T16): two 260 m freighters 2 km apart still cover each other.
            let skins = skin(rows, own) + skin(rows, v);
            let near = if skins > 0.0 {
                let limit = PROTECT_M + skins;
                f64::from(dist_sq(rows.positions[v], ship_at)) <= limit * limit
            } else {
                f64::from(dist_sq(rows.positions[v], ship_at)) <= protect_sq
            };
            if !near {
                continue;
            }
            let rel = relation(relations, stride, m.faction_ix, rows.faction_ix[v]);
            let civilian = memory.civilian[k] || rows.is_civilian(v);
            let defended = rel == REL_FRIENDLY || (civilian && rel != REL_HOSTILE);
            if !defended {
                continue;
            }
        }
        let Some(a) = usable_row(rows, row_of(attacker)) else {
            continue;
        };
        if relation(relations, stride, m.faction_ix, rows.faction_ix[a]) == REL_FRIENDLY {
            continue;
        }
        let d_sq = f64::from(dist_sq(rows.positions[a], pivot));
        if d_sq > reach_sq {
            continue;
        }
        let toward = normalized(sub(rows.positions[a], pivot));
        let elevation = f64::from(dot(toward, up)).clamp(-1.0, 1.0).asin();
        // Out of the arc only when nothing in it is remembered: a turret cannot shoot through its own hull.
        let score = if elevation >= m.min_elevation {
            d_sq
        } else {
            d_sq + reach_sq * 4.0
        };
        // The line is tested only for a candidate that would win: the volume test stays off the common path.
        if score < best_score {
            let from = add(pivot, scale(up, LINE_LIFT_M as f32));  // `line_start` of the mount's frame
            if line_blocked(basis, ship_at, from, rows.positions[a], own_hull) {
                continue;
            }
            best_score = score;
            best = attacker;
        }
    }
    best
}

// How far a civilian hull's skin lies from its centre (its radius); 0 for any other row.
fn skin(rows: &Rows, r: usize) -> f64 {
    if rows.is_civilian(r) { rows.radii[r] } else { 0.0 }
}

/// A mount's place and axes in the World frame: its pivot, its up, its rest direction (azimuth 0) and the side axis.
pub struct Frame {
    pub pivot: Vector3,
    pub up: Vector3,
    pub forward: Vector3,
    pub side: Vector3,
}

/// The mount's frame on its ship's pose.
pub fn frame(basis: &Basis, origin: Vector3, local: Vector3, up: Vector3, forward: Vector3) -> Frame {
    let u = normalized(xform(basis, up));
    let f = normalized(xform(basis, forward));
    Frame {
        pivot: add(xform(basis, local), origin),
        up: u,
        forward: f,
        side: cross(u, f),
    }
}

/// A direction as the mount's azimuth (round `up`, from `forward` toward `side`) and elevation (above its base), rad.
pub fn angles_of(f: &Frame, direction: Vector3) -> (f64, f64) {
    let along = f64::from(dot(direction, f.forward));
    let across = f64::from(dot(direction, f.side));
    let lift = f64::from(dot(direction, f.up)).clamp(-1.0, 1.0);
    (across.atan2(along), lift.asin())
}

/// The barrel's direction at an azimuth and elevation.
pub fn direction_of(f: &Frame, azimuth: f64, elevation: f64) -> Vector3 {
    let (sa, ca) = azimuth.sin_cos();
    let (se, ce) = elevation.sin_cos();
    let flat = add(scale(f.forward, ca as f32), scale(f.side, sa as f32));
    normalized(add(scale(flat, ce as f32), scale(f.up, se as f32)))
}

/// One step of the mount's slew toward a wanted azimuth and elevation: the traverse by the shorter way round, at most
/// `traverse_step`; the elevation held inside the arc (`min_elevation` to straight up), at most `elevation_step`.
pub fn slew(
    azimuth: f64,
    elevation: f64,
    want_azimuth: f64,
    want_elevation: f64,
    min_elevation: f64,
    traverse_step: f64,
    elevation_step: f64,
) -> (f64, f64) {
    let turn = wrap(want_azimuth - azimuth).clamp(-traverse_step, traverse_step);
    let lift_to = want_elevation.clamp(min_elevation, FRAC_PI_2);
    let lift = (lift_to - elevation).clamp(-elevation_step, elevation_step);
    (wrap(azimuth + turn), (elevation + lift).clamp(min_elevation, FRAC_PI_2))
}

/// What one aim step gives: the new angles and barrel axis, how far off the lead the barrel points, whether the lead is
/// inside the arc and solvable, the target's range now and the lead point's range from the pivot.
pub struct Aim {
    pub azimuth: f64,
    pub elevation: f64,
    pub axis: Vector3,
    pub error_rad: f64,
    pub in_arc: bool,
    pub lead_ok: bool,
    pub range_m: f64,
    pub lead_range_m: f64,
    /// Where the lead says the bolt meets the target (the target itself when the lead has no solution).
    pub lead_point: Vector3,
}

/// One tick of a mount's aim at a target: the lead by the brains' intercept maths (`InterceptMath.solve`: the bolt
/// inherits the ship's velocity), then the slew toward it inside the arc.
pub fn aim(
    f: &Frame,
    ship_velocity: Vector3,
    azimuth: f64,
    elevation: f64,
    min_elevation: f64,
    gun: &Gun,
    target_at: Vector3,
    target_velocity: Vector3,
    delta: f64,
) -> Aim {
    let lead = solve(
        f.pivot,
        ship_velocity,
        target_at,
        target_velocity,
        gun.muzzle_speed,
        gun.lifetime_s,
    );
    let wanted = lead.aim_dir;
    let (want_az, want_el) = angles_of(f, wanted);
    let (az, el) = slew(
        azimuth,
        elevation,
        want_az,
        want_el,
        min_elevation,
        gun.traverse_rad_s * delta,
        gun.elevation_rad_s * delta,
    );
    let axis = direction_of(f, az, el);
    let cos_error = f64::from(dot(axis, wanted)).clamp(-1.0, 1.0);
    Aim {
        azimuth: az,
        elevation: el,
        axis,
        error_rad: cos_error.acos(),
        in_arc: want_el >= min_elevation,
        lead_ok: lead.ok,
        range_m: f64::from(dist_sq(target_at, f.pivot)).sqrt(),
        lead_range_m: if lead.ok { gun.muzzle_speed * lead.t } else { 0.0 },
        lead_point: if lead.ok {
            add(f.pivot, scale(wanted, (gun.muzzle_speed * lead.t) as f32))
        } else {
            target_at
        },
    }
}

/// The fire gate: the lead inside the arc and solvable, the target within range, the gun ready, and the barrel's miss at
/// the lead point no wider than the bolt's own spread there plus the target's size.
pub fn gate(a: &Aim, gun: &Gun, target_radius: f64, ready_at: f64, now_s: f64) -> bool {
    if !a.lead_ok || !a.in_arc || a.range_m > gun.range_m || now_s + TIME_EPSILON_S < ready_at {
        return false;
    }
    if a.error_rad >= FRAC_PI_2 {
        return false;
    }
    a.lead_range_m * a.error_rad.sin() <= a.lead_range_m * gun.spread_rad.tan() + target_radius
}

/// A shot's direction: the axis thrown off by up to `spread_rad`, evenly over the cone's disc, from a hash of the mount's
/// id and the tick, so every run of a seeded fight throws the same.
pub fn spread(axis: Vector3, spread_rad: f64, id: i64, tick: i64) -> Vector3 {
    if spread_rad <= 0.0 {
        return axis;
    }
    let u1 = unit_hash(id, tick, 1);
    let u2 = unit_hash(id, tick, 2);
    let off = spread_rad * u1.sqrt();
    let turn = TAU * u2;
    let helper = if axis.x.abs() < 0.9 {
        Vector3::new(1.0, 0.0, 0.0)
    } else {
        Vector3::new(0.0, 1.0, 0.0)
    };
    let p = normalized(cross(axis, helper));
    let q = cross(axis, p);
    let side = add(scale(p, turn.cos() as f32), scale(q, turn.sin() as f32));
    normalized(add(scale(axis, off.cos() as f32), scale(side, off.sin() as f32)))
}

/// Where a shot leaves (the barrel's tip) and how fast (the ship's velocity plus the muzzle speed along `direction`).
pub fn shot(
    pivot: Vector3,
    axis: Vector3,
    direction: Vector3,
    barrel_m: f64,
    ship_velocity: Vector3,
    muzzle_speed: f64,
) -> (Vector3, Vector3) {
    (
        add(pivot, scale(axis, barrel_m as f32)),
        add(ship_velocity, scale(direction, muzzle_speed as f32)),
    )
}

/// One of a ship's own hit volumes (Q33), in its body frame: a box (`half` its half extents) or a capsule along its local y
/// (`half` = [half segment, radius, 0]), placed by `basis` and `origin`; `reach` bounds it from `origin`.
#[derive(Clone, Copy, Debug)]
pub struct Volume {
    pub capsule: bool,
    pub basis: Basis,
    pub origin: Vector3,
    pub half: [f64; 3],
    pub reach: f64,
}

impl Volume {
    /// A box or capsule from its placement and size; `reach` is worked out here.
    pub fn new(capsule: bool, basis: Basis, origin: Vector3, half: [f64; 3]) -> Self {
        let reach = if capsule {
            half[0] + half[1]
        } else {
            (half[0] * half[0] + half[1] * half[1] + half[2] * half[2]).sqrt()
        };
        Volume {
            capsule,
            basis,
            origin,
            half,
            reach,
        }
    }
}

/// How many numbers one volume packs into (`set_turret_hull`): capsule flag, the basis' columns x, y and z, the origin,
/// the size (a box's half extents; a capsule's half segment, radius, 0).
pub const VOLUME_LEN: usize = 16;

/// The turreted ships' own hit volumes by body id, and a version that grows with every change (the job copies on change).
#[derive(Default, Clone)]
pub struct Hulls {
    pub by_body: HashMap<i64, Vec<Volume>>,
    pub version: u64,
}

impl Hulls {
    /// Body `body`'s volumes from packed numbers (`VOLUME_LEN` each); a short tail is dropped.
    pub fn set(&mut self, body: i64, packed: &[f64]) {
        let volumes = packed
            .chunks_exact(VOLUME_LEN)
            .map(|v| {
                let col = |k: usize| Vector3::new(v[k] as f32, v[k + 1] as f32, v[k + 2] as f32);
                Volume::new(
                    v[0] != 0.0,
                    Basis::from_cols(col(1), col(4), col(7)),
                    col(10),
                    [v[13], v[14], v[15]],
                )
            })
            .collect();
        self.by_body.insert(body, volumes);
        self.version += 1;
    }

    /// Body `body`'s volumes (none when it has not been given any).
    pub fn of(&self, body: i64) -> &[Volume] {
        HashMap::get(&self.by_body, &body).map_or(&[], |v| v.as_slice())
    }
}

/// Where a mount's line of fire starts: `LINE_LIFT_M` above its base.
pub fn line_start(f: &Frame) -> Vector3 {
    add(f.pivot, scale(f.up, LINE_LIFT_M as f32))
}

/// Whether the ship's own hull lies across the line from `from` to `to` (World frame), the ship at `origin` turned by
/// `basis`: the line passes through one of its volumes that `from` is not already inside (a turret on its pad still
/// fires out of it).
pub fn line_blocked(basis: &Basis, origin: Vector3, from: Vector3, to: Vector3, volumes: &[Volume]) -> bool {
    if volumes.is_empty() {
        return false;
    }
    let a = to_frame(basis, origin, from);
    let b = to_frame(basis, origin, to);
    volumes.iter().any(|v| segment_hits(a, b, v))
}

/// Whether the segment from `a` to `b` (body frame, metres) enters volume `v` from outside it.
pub fn segment_hits(a: [f64; 3], b: [f64; 3], v: &Volume) -> bool {
    let o = [f64::from(v.origin.x), f64::from(v.origin.y), f64::from(v.origin.z)];
    if segment_point_distance(a, b, o) > v.reach {
        return false;
    }
    let la = to_local(v, a);
    let lb = to_local(v, b);
    if v.capsule {
        let (h, r) = (v.half[0], v.half[1]);
        let inside = |p: [f64; 3]| {
            let y = p[1].clamp(-h, h);
            p[0] * p[0] + (p[1] - y) * (p[1] - y) + p[2] * p[2] <= r * r
        };
        if inside(la) {
            return false;
        }
        segment_segment_distance(la, lb, [0.0, -h, 0.0], [0.0, h, 0.0]) <= r
    } else {
        let inside = (0..3).all(|k| la[k].abs() <= v.half[k]);
        !inside && segment_crosses_box(la, lb, v.half)
    }
}

// The slab test: whether the segment from `a` to `b` meets the axis-aligned box of half extents `half` about the origin.
fn segment_crosses_box(a: [f64; 3], b: [f64; 3], half: [f64; 3]) -> bool {
    let (mut t0, mut t1) = (0.0_f64, 1.0_f64);
    for k in 0..3 {
        let d = b[k] - a[k];
        if d.abs() < 1e-12 {
            if a[k].abs() > half[k] {
                return false;
            }
            continue;
        }
        let (mut near, mut far) = ((-half[k] - a[k]) / d, (half[k] - a[k]) / d);
        if near > far {
            std::mem::swap(&mut near, &mut far);
        }
        t0 = t0.max(near);
        t1 = t1.min(far);
        if t0 > t1 {
            return false;
        }
    }
    true
}

// The least distance between segments `p0 p1` and `q0 q1`.
fn segment_segment_distance(p0: [f64; 3], p1: [f64; 3], q0: [f64; 3], q1: [f64; 3]) -> f64 {
    let d1 = sub3(p1, p0);
    let d2 = sub3(q1, q0);
    let r = sub3(p0, q0);
    let (a, e, f) = (dot3(d1, d1), dot3(d2, d2), dot3(d2, r));
    let (s, t);
    if a <= 1e-12 && e <= 1e-12 {
        return dot3(r, r).sqrt();
    }
    if a <= 1e-12 {
        s = 0.0;
        t = (f / e).clamp(0.0, 1.0);
    } else {
        let c = dot3(d1, r);
        if e <= 1e-12 {
            t = 0.0;
            s = (-c / a).clamp(0.0, 1.0);
        } else {
            let b = dot3(d1, d2);
            let denom = a * e - b * b;
            let mut s0 = if denom > 1e-12 { ((b * f - c * e) / denom).clamp(0.0, 1.0) } else { 0.0 };
            let mut t0 = (b * s0 + f) / e;
            if t0 < 0.0 {
                t0 = 0.0;
                s0 = (-c / a).clamp(0.0, 1.0);
            } else if t0 > 1.0 {
                t0 = 1.0;
                s0 = ((b - c) / a).clamp(0.0, 1.0);
            }
            s = s0;
            t = t0;
        }
    }
    let gap = sub3(add3(p0, scale3(d1, s)), add3(q0, scale3(d2, t)));
    dot3(gap, gap).sqrt()
}

// The distance from point `p` to the segment `a b`.
fn segment_point_distance(a: [f64; 3], b: [f64; 3], p: [f64; 3]) -> f64 {
    let ab = sub3(b, a);
    let len_sq = dot3(ab, ab);
    let t = if len_sq > 1e-12 { (dot3(sub3(p, a), ab) / len_sq).clamp(0.0, 1.0) } else { 0.0 };
    let gap = sub3(p, add3(a, scale3(ab, t)));
    dot3(gap, gap).sqrt()
}

// A World point in the ship's body frame (the basis is a rotation, so its transpose undoes it).
fn to_frame(basis: &Basis, origin: Vector3, p: Vector3) -> [f64; 3] {
    let o = [f64::from(origin.x), f64::from(origin.y), f64::from(origin.z)];
    frame_of(basis, o, [f64::from(p.x), f64::from(p.y), f64::from(p.z)])
}

// A body-frame point in a volume's own frame.
fn to_local(v: &Volume, p: [f64; 3]) -> [f64; 3] {
    frame_of(&v.basis, [f64::from(v.origin.x), f64::from(v.origin.y), f64::from(v.origin.z)], p)
}

// `p` less `origin`, read along the basis' columns.
fn frame_of(basis: &Basis, origin: [f64; 3], p: [f64; 3]) -> [f64; 3] {
    let d = sub3(p, origin);
    [col_a(basis), col_b(basis), col_c(basis)].map(|c| d[0] * f64::from(c.x) + d[1] * f64::from(c.y) + d[2] * f64::from(c.z))
}

fn sub3(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn add3(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

fn scale3(a: [f64; 3], s: f64) -> [f64; 3] {
    [a[0] * s, a[1] * s, a[2] * s]
}

fn dot3(a: [f64; 3], b: [f64; 3]) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

/// The row of a body a turret may read (alive, not in the low-attention tier), if any.
pub fn usable_row(rows: &Rows, row: i64) -> Option<usize> {
    let r = usize::try_from(row).ok()?;
    if r >= rows.flags.len() {
        return None;
    }
    let flags = rows.flags[r];
    (flags & FLAG_HULL_ACTIVE != 0 && flags & FLAG_TIER == 0).then_some(r)
}

/// The row of a ship a mount may fire from: a live rigid body, not a tier row.
pub fn firing_row(rows: &Rows, row: i64) -> Option<usize> {
    let r = usize::try_from(row).ok()?;
    if r >= rows.flags.len() {
        return None;
    }
    let flags = rows.flags[r];
    (flags & FLAG_RIGID != 0 && flags & FLAG_TIER == 0).then_some(r)
}

// The mount's rest direction (azimuth 0): the ship's nose laid flat on the mount's base, or its top when the base faces
// along the nose.
fn rest_forward(up: Vector3) -> Vector3 {
    let nose = Vector3::new(0.0, 0.0, -1.0);
    let flat = sub(nose, scale(up, dot(up, nose)));
    if f64::from(dot(flat, flat)) > 1e-4 {
        return normalized(flat);
    }
    let top = Vector3::new(0.0, 1.0, 0.0);
    normalized(sub(top, scale(up, dot(up, top))))
}

fn unit_or(v: Vector3, fallback: Vector3) -> Vector3 {
    if f64::from(dot(v, v)) < 1e-12 {
        fallback
    } else {
        normalized(v)
    }
}

// An angle brought into (-pi, pi].
fn wrap(angle: f64) -> f64 {
    let mut a = angle % TAU;
    if a > PI {
        a -= TAU;
    } else if a <= -PI {
        a += TAU;
    }
    a
}

// A number in [0, 1) from a mount's id, the tick and a lane (splitmix64).
fn unit_hash(id: i64, tick: i64, lane: u64) -> f64 {
    let mut z = (id as u64)
        .wrapping_mul(0x9e37_79b9_7f4a_7c15)
        .wrapping_add((tick as u64).wrapping_mul(0xbf58_476d_1ce4_e5b9))
        .wrapping_add(lane.wrapping_mul(0x94d0_49bb_1331_11eb));
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^= z >> 31;
    (z >> 11) as f64 / (1u64 << 53) as f64
}

#[cfg(test)]
mod tests;
