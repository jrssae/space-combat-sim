// The core's shell around the defensive turrets (M5-T21, D61): mounts bound to their ships' rows, the attacker memory,
// the main-thread step (aim, fire gate, shot as an owned bolt row) and the picks handed over at the AI job's join. Every
// engine type stays here; the maths is `turret_kernels`, engine-free.
use std::collections::HashSet;
use std::time::Instant;

use godot::prelude::*;

use crate::grid_kernels::{self as gk, Incoming, Latch, MOUNT_HEAVY, MOUNT_INTERCEPTOR, MOUNT_LIGHT, MOUNT_TURRET};
use crate::sim_core::{KIND_BOLT, ScsSimCore};
use crate::turret_kernels::{
    self as tk, Gun, Hulls, Memory, Mounts, PickJob, REL_NEUTRAL,
};

/// How many numbers `add_turret`'s gun takes: muzzle speed (m/s), shot interval (s), lifetime (s), damage, hit radius
/// (m), range (m), spread (deg), traverse rate (deg/s), elevation rate (deg/s).
pub const GUN_LEN: usize = 9;

/// The turrets' state in the core: the mounts, who attacked whom, which ships are civilians, the relations the pick
/// reads, and the readouts.
#[derive(Default)]
pub struct TurretState {
    pub mounts: Mounts,
    pub memory: Memory,
    pub(crate) civilians: HashSet<i64>,
    relations: Vec<u8>,
    stride: usize,
    next_id: i64,
    next_stamp: u32,
    shots_total: i64,
    picks_applied: i64,
    picks_stale: i64,
    step_us: i64,
    /// The turreted ships' own hit volumes (Q33): what blocks their turrets' fire.
    pub hulls: Hulls,
    // Shots the gate would have fired but the own hull was in the way (a readout).
    blocked_total: i64,
    /// The station grid's weapons-free latch (M7-T07, D75): set on the main thread, read by the pick from the job's copy.
    pub latch: Latch,
    // The grid's readouts: shots by the light and heavy guns, projectiles shot down (and of them missiles), shots the
    // station's hull blocked.
    grid_light_shots: i64,
    grid_heavy_shots: i64,
    grid_intercepts: i64,
    grid_missile_intercepts: i64,
    grid_blocked: i64,
    // The interceptors' scratch: candidates, the bolts taken this tick, the big hulls' rows and their bodies.
    incoming: Vec<Incoming>,
    taken: Vec<bool>,
    surface_rows: Vec<usize>,
    surface_bodies: Vec<i64>,
}

impl TurretState {
    fn new_stamp(&mut self) -> u32 {
        self.next_stamp = self.next_stamp.wrapping_add(1).max(1);
        self.next_stamp
    }
}

impl ScsSimCore {
    /// The launch's copy for the AI job: the live mounts, the memory and the relations as they stand.
    pub(crate) fn turret_snapshot_into(&self, job: &mut PickJob) {
        let t = &self.turrets;
        let mut bodies: Vec<i64> = self.surfaces.keys().copied().collect();
        bodies.sort_unstable();
        job.take_from(&t.mounts, &t.memory, &t.relations, t.stride, &t.hulls, &t.latch, &bodies);
    }

    /// A joined job's picks: each lands on its mount when the mount's binding is still the one it was picked for.
    pub(crate) fn take_turret_picks(&mut self, job: &PickJob) {
        let t = &mut self.turrets;
        for p in &job.picks {
            let s = p.slot as usize;
            if t.mounts.has(s) && t.mounts.live[s] && t.mounts.stamp[s] == p.stamp {
                t.mounts.target[s] = p.target;
                t.picks_applied += 1;
            } else {
                t.picks_stale += 1;
            }
        }
    }
}

#[godot_api(secondary)]
impl ScsSimCore {
    /// Mounts a turret on body `body_id` at `local` (its frame) with its base facing `up`, a cone of `arc_deg` round it, a
    /// barrel `barrel_m` long, firing for `faction` with `gun` (`GUN_LEN` numbers) and bolts of `color` drawn with `look`.
    /// Returns its slot, or -1 when the gun's numbers are short.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn add_turret(
        &mut self,
        body_id: i64,
        local: Vector3,
        up: Vector3,
        arc_deg: f64,
        barrel_m: f64,
        faction: StringName,
        gun: PackedFloat64Array,
        color: Color,
        look: i64,
    ) -> i64 {
        self.mount_gun(body_id, local, up, arc_deg, barrel_m, faction, gun, color, look, MOUNT_TURRET)
    }

    /// Mounts one of the station grid's guns or interceptor batteries (M7-T07, D75) on body `body_id` (the station's frame
    /// or drum): `kind` 1 a light pulse turret, 2 a heavy cannon, 3 an interceptor battery; the rest as `add_turret`. Its
    /// line of fire is blocked by every big hull's surface, not by hit volumes. Returns its slot, or -1.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn add_grid_mount(
        &mut self,
        body_id: i64,
        local: Vector3,
        up: Vector3,
        arc_deg: f64,
        barrel_m: f64,
        faction: StringName,
        gun: PackedFloat64Array,
        color: Color,
        look: i64,
        kind: i64,
    ) -> i64 {
        let Ok(kind) = u8::try_from(kind).map_err(|_| ()).and_then(|k| {
            if (MOUNT_LIGHT..=MOUNT_INTERCEPTOR).contains(&k) { Ok(k) } else { Err(()) }
        }) else {
            godot_error!("ScsSimCore.add_grid_mount: kind {kind} is not 1, 2 or 3; not mounted");
            return -1;
        };
        self.mount_gun(body_id, local, up, arc_deg, barrel_m, faction, gun, color, look, kind)
    }

    /// The grid's people `grid` set weapons free against `side` (`on`), or holding fire against it again; `side` empty holds
    /// against every side. A held gun drops its target at once.
    #[func]
    fn set_grid_free(&mut self, grid: StringName, side: StringName, on: bool) {
        let g = self.faction_index(grid);
        if on {
            let e = self.faction_index(side);
            self.turrets.latch.set(g, e);
            return;
        }
        let e = if side.is_empty() { None } else { Some(self.faction_index(side)) };
        self.turrets.latch.hold(g, e);
        let t = &mut self.turrets;
        for s in 0..t.mounts.taken.len() {
            if t.mounts.taken[s] && t.mounts.kind[s] != MOUNT_TURRET && t.mounts.faction_ix[s] == g {
                t.mounts.target[s] = 0;
            }
        }
    }

    /// The sides grid people are weapons free against, as `[grid, side, grid, side, ...]` faction names in latch order.
    #[func]
    fn grid_free_sides(&self) -> PackedStringArray {
        let mut out = PackedStringArray::new();
        for &(g, e) in &self.turrets.latch.pairs {
            out.push(&GString::from(&self.factions[g as usize]));
            out.push(&GString::from(&self.factions[e as usize]));
        }
        out
    }

    /// `[light pulse shots, heavy cannon shots, projectiles shot down, of them missiles, shots the station's hull blocked]`.
    #[func]
    fn grid_readouts(&self) -> PackedInt64Array {
        let t = &self.turrets;
        PackedInt64Array::from(
            &[t.grid_light_shots, t.grid_heavy_shots, t.grid_intercepts, t.grid_missile_intercepts, t.grid_blocked][..],
        )
    }

    /// Knocks a mount out (`out`: its health is gone; it neither picks nor fires and drops its target) or repairs it (M7-T07).
    #[func]
    fn set_turret_out(&mut self, slot: i64, out: bool) {
        let Some(s) = self.mount_slot(slot) else {
            return;
        };
        let m = &mut self.turrets.mounts;
        m.out[s] = out;
        m.target[s] = 0;
    }

    /// Whether a mount is knocked out.
    #[func]
    fn turret_out(&self, slot: i64) -> bool {
        self.mount_slot(slot).is_some_and(|s| self.turrets.mounts.out[s])
    }

    /// The grid's mounts as points an attacker can aim at (M7-T10): `[slots, kinds, World places, alive (1) or not (0)]`, in
    /// slot order, from the rows as they stand.
    #[func]
    fn grid_points(&self) -> VarArray {
        let mut points = Vec::new();
        gk::mount_points(&self.rows, &|b| self.row_for_kernel(b), &self.turrets.mounts, &mut points);
        let slots: Vec<i32> = points.iter().map(|p| p.slot as i32).collect();
        let kinds: Vec<i32> = points.iter().map(|p| i32::from(p.kind)).collect();
        let at: Vec<Vector3> = points.iter().map(|p| p.at).collect();
        let alive: Vec<u8> = points.iter().map(|p| u8::from(p.alive)).collect();
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(slots.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(kinds.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(at.as_slice()).to_variant());
        out.push(&PackedByteArray::from(alive.as_slice()).to_variant());
        out
    }

    /// A mount's kind (`grid_kernels::MOUNT_*`), -1 for no mount.
    #[func]
    fn turret_kind(&self, slot: i64) -> i64 {
        self.mount_slot(slot).map_or(-1, |s| i64::from(self.turrets.mounts.kind[s]))
    }
}

impl ScsSimCore {
    // A turret of `kind` on its body: the gun's numbers checked, a new stamp and id, the slot.
    #[allow(clippy::too_many_arguments)]
    fn mount_gun(
        &mut self,
        body_id: i64,
        local: Vector3,
        up: Vector3,
        arc_deg: f64,
        barrel_m: f64,
        faction: StringName,
        gun: PackedFloat64Array,
        color: Color,
        look: i64,
        kind: u8,
    ) -> i64 {
        let g = gun.as_slice();
        if g.len() != GUN_LEN {
            godot_error!(
                "ScsSimCore.add_turret: the gun needs {GUN_LEN} numbers, got {}; not mounted",
                g.len()
            );
            return -1;
        }
        let gun = Gun {
            muzzle_speed: g[0],
            interval_s: g[1],
            lifetime_s: g[2],
            damage: g[3],
            hit_radius: g[4],
            range_m: g[5],
            spread_rad: g[6].to_radians(),
            traverse_rad_s: g[7].to_radians(),
            elevation_rad_s: g[8].to_radians(),
            color: [color.r, color.g, color.b, color.a],
            look: u8::try_from(look).unwrap_or(crate::rows::LOOK_NONE),
        };
        let faction_ix = self.faction_index(faction);
        let stamp = self.turrets.new_stamp();
        self.turrets.next_id += 1;
        let id = self.turrets.next_id;
        let slot = self
            .turrets
            .mounts
            .add(id, stamp, body_id, faction_ix, local, up, arc_deg, barrel_m, gun);
        self.turrets.mounts.kind[slot] = kind;
        slot as i64
    }
}

#[godot_api(secondary)]
impl ScsSimCore {

    /// Takes a turret off; a pick still out for it is dropped at the join.
    #[func]
    fn remove_turret(&mut self, slot: i64) {
        if let Ok(s) = usize::try_from(slot) {
            self.turrets.mounts.remove(s);
        }
    }

    /// Whether a turret is in play (its ship's node processes). Each change is a new binding: a pick made for the old one
    /// is dropped, and a turret back in play starts with no target.
    #[func]
    fn set_turret_live(&mut self, slot: i64, live: bool) {
        let Some(s) = self.mount_slot(slot) else {
            return;
        };
        if self.turrets.mounts.live[s] == live {
            return;
        }
        let stamp = self.turrets.new_stamp();
        let m = &mut self.turrets.mounts;
        m.live[s] = live;
        m.stamp[s] = stamp;
        m.target[s] = 0;
    }

    #[func]
    fn set_turret_faction(&mut self, slot: i64, faction: StringName) {
        let Some(s) = self.mount_slot(slot) else {
            return;
        };
        let faction_ix = self.faction_index(faction);
        let stamp = self.turrets.new_stamp();
        let m = &mut self.turrets.mounts;
        m.faction_ix[s] = faction_ix;
        m.stamp[s] = stamp;
    }

    /// Marks a ship as a civilian (or not): a turret defends a civilian of any people not hostile to it.
    #[func]
    fn set_civilian(&mut self, body_id: i64, on: bool) {
        if on {
            self.turrets.civilians.insert(body_id);
        } else {
            self.turrets.civilians.remove(&body_id);
        }
        // The rows' role column (M5-T16) is read with the body's attributes: read them again at the next sync.
        self.touch(body_id);
    }

    /// The relations the pick reads: `matrix[a * count + b]` is how the core's faction `a` regards `b` (`Factions.Relation`:
    /// 0 friendly, 1 neutral, 2 hostile).
    #[func]
    fn set_turret_relations(&mut self, count: i64, matrix: PackedByteArray) -> bool {
        let n = usize::try_from(count).unwrap_or(0);
        if matrix.len() != n * n {
            godot_error!(
                "ScsSimCore.set_turret_relations: {} entries for {n} factions",
                matrix.len()
            );
            return false;
        }
        self.turrets.stride = n;
        self.turrets.relations = matrix.as_slice().to_vec();
        true
    }

    /// How many factions the core knows now (the turrets' relations must cover them all).
    #[func]
    fn faction_count(&self) -> i64 {
        self.factions.len() as i64
    }

    /// How many factions the turrets' relations cover.
    #[func]
    fn turret_relations_count(&self) -> i64 {
        self.turrets.stride as i64
    }

    /// Turrets mounted now.
    #[func]
    fn turret_count(&self) -> i64 {
        self.turrets.mounts.count() as i64
    }

    /// One turret's state: azimuth and elevation (rad), its target (body id, 0 for none), when it may fire next, its shots,
    /// its stamp and whether it is in play; empty for no turret.
    #[func]
    fn turret_state(&self, slot: i64) -> VarDictionary {
        let mut out = VarDictionary::new();
        let Some(s) = self.mount_slot(slot) else {
            return out;
        };
        let m = &self.turrets.mounts;
        out.set("azimuth", m.azimuth[s]);
        out.set("elevation", m.elevation[s]);
        out.set("target", m.target[s]);
        out.set("ready_at", m.ready_at[s]);
        out.set("shots", m.shots[s]);
        out.set("stamp", i64::from(m.stamp[s]));
        out.set("live", m.live[s]);
        out.set("min_elevation", m.min_elevation[s]);
        out
    }

    /// Every slot's azimuth and elevation, two numbers a slot (what the turrets' models turn to each frame).
    #[func]
    fn turret_aims(&self) -> PackedFloat32Array {
        let m = &self.turrets.mounts;
        let mut out = Vec::with_capacity(m.taken.len() * 2);
        for s in 0..m.taken.len() {
            out.push(m.azimuth[s] as f32);
            out.push(m.elevation[s] as f32);
        }
        PackedFloat32Array::from(out.as_slice())
    }

    /// One tick of every turret in play at sim time `now_s`, on the main thread after the sync: the memory pruned, then
    /// each mount with a target aims (lead, slew inside its arc), and fires through its gate as an owned bolt row from
    /// the barrel's tip; then the station grid's interceptor batteries shoot down what is coming at the hull (M7-T07).
    /// Returns `[slots that fired, the shots' starts, their bolt ids, interceptor slots that fired, the bolt ids they shot
    /// down, where those were]`, each in slot order.
    #[func]
    fn step_turrets(&mut self, now_s: f64, delta: f64) -> VarArray {
        let started = Instant::now();
        let mut slots: Vec<i32> = Vec::new();
        let mut starts: Vec<Vector3> = Vec::new();
        let mut ids: Vec<i64> = Vec::new();
        self.turrets.memory.prune(now_s);
        let tick = self.syncs();
        let mut surface_rows = std::mem::take(&mut self.turrets.surface_rows);
        self.grid_surface_rows(&mut surface_rows);
        let mut m = std::mem::take(&mut self.turrets.mounts);
        for s in 0..m.taken.len() {
            if !m.taken[s] || !m.live[s] || m.out[s] || m.target[s] == 0 || m.kind[s] == MOUNT_INTERCEPTOR {
                continue;
            }
            let body = m.body[s];
            let grid = m.kind[s] != MOUNT_TURRET;
            let row = self.row_for_kernel(body);
            let Some(own) = (if grid { gk::firing_row(&self.rows, row) } else { tk::firing_row(&self.rows, row) }) else {
                continue;
            };
            let Some(tr) = tk::usable_row(&self.rows, self.row_for_kernel(m.target[s])) else {
                continue;
            };
            if self.rows.body_ids[tr] == body {
                continue;
            }
            let f = tk::frame(
                &self.rows.bases[own],
                self.rows.positions[own],
                m.local[s],
                m.up[s],
                m.forward[s],
            );
            // A drum's gun moves with the skin under it: its bolts and its lead take that speed.
            let ship_velocity = if grid {
                gk::mount_velocity(&self.rows, own, f.pivot)
            } else {
                self.rows.velocities[own]
            };
            let gun = m.gun[s];
            let a = tk::aim(
                &f,
                ship_velocity,
                m.azimuth[s],
                m.elevation[s],
                m.min_elevation[s],
                &gun,
                self.rows.positions[tr],
                self.rows.velocities[tr],
                delta,
            );
            m.azimuth[s] = a.azimuth;
            m.elevation[s] = a.elevation;
            if !tk::gate(&a, &gun, self.rows.radii[tr], m.ready_at[s], now_s) {
                continue;
            }
            // Q33: the ship's own hull stops the shot; the line runs from the trunnion to the lead point. A grid gun's is
            // the station's frame and drum (every big hull).
            let from = tk::line_start(&f);
            let blocked = if grid {
                gk::line_blocked(&self.rows, &surface_rows, from, a.lead_point)
            } else {
                let own_hull = self.turrets.hulls.of(body);
                tk::line_blocked(&self.rows.bases[own], self.rows.positions[own], from, a.lead_point, own_hull)
            };
            if blocked {
                self.turrets.blocked_total += 1;
                if grid {
                    self.turrets.grid_blocked += 1;
                }
                continue;
            }
            m.ready_at[s] = now_s + gun.interval_s;
            m.shots[s] += 1;
            match m.kind[s] {
                MOUNT_LIGHT => self.turrets.grid_light_shots += 1,
                MOUNT_HEAVY => self.turrets.grid_heavy_shots += 1,
                _ => {}
            }
            let direction = tk::spread(a.axis, gun.spread_rad, m.id[s], tick);
            let (at, velocity) = tk::shot(
                f.pivot,
                a.axis,
                direction,
                m.barrel_m[s],
                ship_velocity,
                gun.muzzle_speed,
            );
            let id = self.add_owned_bolt(
                at,
                velocity,
                m.faction_ix[s],
                body,
                KIND_BOLT,
                gun.hit_radius,
                gun.damage,
                gun.color,
                gun.look,
                now_s + gun.lifetime_s,
            );
            slots.push(s as i32);
            starts.push(at);
            ids.push(id);
        }
        let (kill_slots, kill_ids, kill_points) = self.step_interceptors(&mut m, &surface_rows, now_s);
        self.turrets.mounts = m;
        self.turrets.surface_rows = surface_rows;
        self.turrets.shots_total += slots.len() as i64;
        self.turrets.step_us = started.elapsed().as_micros() as i64;
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(slots.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(starts.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(ids.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(kill_slots.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(kill_ids.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(kill_points.as_slice()).to_variant());
        out
    }

    /// The tick's bolt hits in the sweep's order (`victims[k]` hit by `shooters[k]`'s bolt) at `now_s`: each shooter becomes
    /// an attacker of its victim for `MEMORY_S`. Nothing is kept while no turret is mounted.
    #[func]
    fn note_attackers(&mut self, victims: PackedInt64Array, shooters: PackedInt64Array, now_s: f64) {
        if self.turrets.mounts.count() == 0 {
            return;
        }
        for (&victim, &shooter) in victims.as_slice().iter().zip(shooters.as_slice()) {
            self.latch_on_hit(victim, shooter);
            let t = &mut self.turrets;
            let civilian = t.civilians.contains(&victim);
            t.memory.note(victim, shooter, now_s, civilian);
        }
    }

    /// Forgets a ship in the memory, as attacker and victim (it was destroyed).
    #[func]
    fn forget_attacker(&mut self, body_id: i64) {
        self.turrets.memory.forget(body_id);
    }

    /// The memory as `(victim, attacker)` pairs, flattened, in its order.
    #[func]
    fn attacker_pairs(&self) -> PackedInt64Array {
        let m = &self.turrets.memory;
        let mut out = Vec::with_capacity(m.len() * 2);
        for k in 0..m.len() {
            out.push(m.victim[k]);
            out.push(m.attacker[k]);
        }
        PackedInt64Array::from(out.as_slice())
    }

    #[func]
    fn attacker_count(&self) -> i64 {
        self.turrets.memory.len() as i64
    }

    /// `[shots so far, picks applied, picks dropped as stale, the last step's microseconds, shots the own hull blocked]`
    /// (readouts).
    #[func]
    fn turret_readouts(&self) -> PackedInt64Array {
        let t = &self.turrets;
        PackedInt64Array::from(
            &[t.shots_total, t.picks_applied, t.picks_stale, t.step_us, t.blocked_total][..],
        )
    }

    /// Body `body_id`'s own hit volumes (Q33), `VOLUME_LEN` numbers each in its body frame: what its turrets cannot fire
    /// through. Given when its first mount binds and again when its volumes change, never per tick.
    #[func]
    fn set_turret_hull(&mut self, body_id: i64, volumes: PackedFloat64Array) {
        self.turrets.hulls.set(body_id, volumes.as_slice());
    }

    /// How many hit volumes body `body_id` has given its turrets.
    #[func]
    fn turret_hull_count(&self, body_id: i64) -> i64 {
        self.turrets.hulls.of(body_id).len() as i64
    }

    /// A hash of every mount's aim, target, gate and shots and of the memory, for comparing runs byte for byte (ships by
    /// their rows, which a seeded run lays out alike, not by instance ids, which differ from run to run).
    #[func]
    fn turret_digest(&self) -> i64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut word = |w: u64| {
            for b in w.to_le_bytes() {
                h ^= u64::from(b);
                h = h.wrapping_mul(0x0000_0100_0000_01b3);
            }
        };
        let m = &self.turrets.mounts;
        for s in 0..m.taken.len() {
            if !m.taken[s] {
                word(0);
                continue;
            }
            word(m.azimuth[s].to_bits());
            word(m.elevation[s].to_bits());
            word(self.row_of_id(m.target[s]) as u64);
            word(m.ready_at[s].to_bits());
            word(m.shots[s] as u64);
            word(u64::from(m.out[s]));
        }
        let mem = &self.turrets.memory;
        for k in 0..mem.len() {
            word(self.row_of_id(mem.victim[k]) as u64);
            word(self.row_of_id(mem.attacker[k]) as u64);
            word(mem.until_s[k].to_bits());
        }
        for &(g, e) in &self.turrets.latch.pairs {
            word(u64::from(g) << 32 | u64::from(e));
        }
        h as i64
    }

    /// `turret_kernels::relation` over the table set now (tests).
    #[func]
    fn turret_relation(&self, a: i64, b: i64) -> i64 {
        let (Ok(a), Ok(b)) = (u32::try_from(a), u32::try_from(b)) else {
            return i64::from(REL_NEUTRAL);
        };
        i64::from(tk::relation(&self.turrets.relations, self.turrets.stride, a, b))
    }
}

impl ScsSimCore {
    fn mount_slot(&self, slot: i64) -> Option<usize> {
        usize::try_from(slot)
            .ok()
            .filter(|&s| self.turrets.mounts.has(s))
    }
}

impl ScsSimCore {
    // The rows of every big hull (the station's frame and drum): what blocks a grid gun and what an interceptor guards.
    fn grid_surface_rows(&mut self, out: &mut Vec<usize>) {
        let mut bodies = std::mem::take(&mut self.turrets.surface_bodies);
        bodies.clear();
        bodies.extend(self.surfaces.keys().copied());
        bodies.sort_unstable();
        out.clear();
        for &b in &bodies {
            if let Ok(r) = usize::try_from(self.row_for_kernel(b))
                && self.rows.surface(r).is_some()
            {
                out.push(r);
            }
        }
        self.turrets.surface_bodies = bodies;
    }

    // The interceptor batteries' tick (D75): each looks at the hostile missiles and pulse bolts within its reach whose path
    // meets the hull (any such shot sets the grid weapons free against its side: it was fired at the station), and when its
    // gun is ready shoots down one: a missile first, then the one that hits soonest. Returns the batteries that fired,
    // the bolt ids they took (the caller spends them) and where those were.
    fn step_interceptors(
        &mut self,
        m: &mut Mounts,
        surface_rows: &[usize],
        now_s: f64,
    ) -> (Vec<i32>, Vec<i64>, Vec<Vector3>) {
        let (mut slots, mut ids, mut points) = (Vec::new(), Vec::new(), Vec::new());
        if surface_rows.is_empty() || !m.kind.contains(&MOUNT_INTERCEPTOR) || self.bolts.ids.is_empty() {
            return (slots, ids, points);
        }
        let mut incoming = std::mem::take(&mut self.turrets.incoming);
        let mut taken = std::mem::take(&mut self.turrets.taken);
        taken.clear();
        taken.resize(self.bolts.ids.len(), false);
        let relations = std::mem::take(&mut self.turrets.relations);
        let stride = self.turrets.stride;
        for s in 0..m.taken.len() {
            if !m.taken[s] || !m.live[s] || m.out[s] || m.kind[s] != MOUNT_INTERCEPTOR {
                continue;
            }
            let Some(own) = gk::firing_row(&self.rows, self.row_for_kernel(m.body[s])) else {
                continue;
            };
            let f = tk::frame(&self.rows.bases[own], self.rows.positions[own], m.local[s], m.up[s], m.forward[s]);
            let g = m.faction_ix[s];
            gk::incoming(
                &self.rows,
                surface_rows,
                &self.bolts,
                g,
                &relations,
                stride,
                f.pivot,
                m.gun[s].range_m,
                now_s,
                &mut incoming,
            );
            for c in &incoming {
                self.turrets.latch.set(g, self.bolts.faction_ix[c.bolt as usize]);
            }
            if now_s + 1e-6 < m.ready_at[s] {
                continue;
            }
            let Some(pick) = gk::choose(&incoming, &taken) else {
                continue;
            };
            let p = pick.bolt as usize;
            taken[p] = true;
            m.ready_at[s] = now_s + m.gun[s].interval_s;
            m.shots[s] += 1;
            let at = self.bolts.positions[p];
            let (az, el) = tk::angles_of(&f, crate::v3::normalized(crate::v3::sub(at, f.pivot)));
            m.azimuth[s] = az;
            m.elevation[s] = el.clamp(m.min_elevation[s], std::f64::consts::FRAC_PI_2);
            self.turrets.grid_intercepts += 1;
            self.turrets.grid_missile_intercepts += i64::from(pick.missile);
            slots.push(s as i32);
            ids.push(self.bolts.ids[p]);
            points.push(at);
        }
        self.turrets.relations = relations;
        self.turrets.incoming = incoming;
        self.turrets.taken = taken;
        (slots, ids, points)
    }

    // A landed hit sets the grid weapons free against the shooter's side when the victim is the station or a friendly
    // within a grid gun's range of its mount (D75).
    fn latch_on_hit(&mut self, victim: i64, shooter: i64) {
        let t = &self.turrets;
        if !t.mounts.kind.iter().zip(&t.mounts.taken).any(|(&k, &u)| u && k != MOUNT_TURRET) {
            return;
        }
        let (Ok(v), Ok(a)) = (
            usize::try_from(self.row_for_kernel(victim)),
            usize::try_from(self.row_for_kernel(shooter)),
        ) else {
            return;
        };
        let enemy = self.rows.faction_ix[a];
        let mut set: Vec<u32> = Vec::new();
        for s in 0..t.mounts.taken.len() {
            if !t.mounts.taken[s] || t.mounts.kind[s] == MOUNT_TURRET {
                continue;
            }
            let g = t.mounts.faction_ix[s];
            if set.contains(&g) || t.latch.is_free(g, enemy) {
                continue;
            }
            let near = |p: Vector3| self.near_grid_gun(g, p);
            if gk::hit_frees(&self.rows, v, enemy, g, &t.relations, t.stride, near) {
                set.push(g);
            }
        }
        for g in set {
            self.turrets.latch.set(g, enemy);
        }
    }

    // Whether World point `p` lies within any of grid people `g`'s guns' ranges of its mount.
    fn near_grid_gun(&self, g: u32, p: Vector3) -> bool {
        let m = &self.turrets.mounts;
        (0..m.taken.len()).any(|s| {
            if !m.taken[s] || m.kind[s] == MOUNT_TURRET || m.faction_ix[s] != g {
                return false;
            }
            let Some(own) = gk::firing_row(&self.rows, self.row_for_kernel(m.body[s])) else {
                return false;
            };
            let pivot = crate::v3::add(crate::v3::xform(&self.rows.bases[own], m.local[s]), self.rows.positions[own]);
            let range = m.gun[s].range_m;
            f64::from(crate::v3::dist_sq(pivot, p)) <= range * range
        })
    }
}
