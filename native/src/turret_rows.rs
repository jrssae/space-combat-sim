// The core's shell around the defensive turrets (M5-T21, D61): mounts bound to their ships' rows, the attacker memory,
// the main-thread step (aim, fire gate, shot as an owned bolt row) and the picks handed over at the AI job's join. Every
// engine type stays here; the maths is `turret_kernels`, engine-free.
use std::collections::HashSet;
use std::time::Instant;

use godot::prelude::*;

use crate::sim_core::{KIND_BOLT, ScsSimCore};
use crate::turret_kernels::{
    self as tk, Gun, Memory, Mounts, PickJob, REL_NEUTRAL,
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
        job.take_from(&t.mounts, &t.memory, &t.relations, t.stride);
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
        self.turrets
            .mounts
            .add(id, stamp, body_id, faction_ix, local, up, arc_deg, barrel_m, gun) as i64
    }

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
    /// the barrel's tip. Returns `[slots that fired, the shots' starts, their bolt ids]`, in slot order.
    #[func]
    fn step_turrets(&mut self, now_s: f64, delta: f64) -> VarArray {
        let started = Instant::now();
        let mut slots: Vec<i32> = Vec::new();
        let mut starts: Vec<Vector3> = Vec::new();
        let mut ids: Vec<i64> = Vec::new();
        self.turrets.memory.prune(now_s);
        let tick = self.syncs();
        let mut m = std::mem::take(&mut self.turrets.mounts);
        for s in 0..m.taken.len() {
            if !m.taken[s] || !m.live[s] || m.target[s] == 0 {
                continue;
            }
            let body = m.body[s];
            let Some(own) = tk::firing_row(&self.rows, self.row_for_kernel(body)) else {
                continue;
            };
            let Some(tr) = tk::usable_row(&self.rows, self.row_for_kernel(m.target[s])) else {
                continue;
            };
            if self.rows.body_ids[tr] == body {
                continue;
            }
            let ship_velocity = self.rows.velocities[own];
            let f = tk::frame(
                &self.rows.bases[own],
                self.rows.positions[own],
                m.local[s],
                m.up[s],
                m.forward[s],
            );
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
            m.ready_at[s] = now_s + gun.interval_s;
            m.shots[s] += 1;
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
        self.turrets.mounts = m;
        self.turrets.shots_total += slots.len() as i64;
        self.turrets.step_us = started.elapsed().as_micros() as i64;
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(slots.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(starts.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(ids.as_slice()).to_variant());
        out
    }

    /// The tick's bolt hits in the sweep's order (`victims[k]` hit by `shooters[k]`'s bolt) at `now_s`: each shooter becomes
    /// an attacker of its victim for `MEMORY_S`. Nothing is kept while no turret is mounted.
    #[func]
    fn note_attackers(&mut self, victims: PackedInt64Array, shooters: PackedInt64Array, now_s: f64) {
        if self.turrets.mounts.count() == 0 {
            return;
        }
        let t = &mut self.turrets;
        for (&victim, &shooter) in victims.as_slice().iter().zip(shooters.as_slice()) {
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

    /// `[shots so far, picks applied, picks dropped as stale, the last step's microseconds]` (readouts).
    #[func]
    fn turret_readouts(&self) -> PackedInt64Array {
        let t = &self.turrets;
        PackedInt64Array::from(
            &[t.shots_total, t.picks_applied, t.picks_stale, t.step_us][..],
        )
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
        }
        let mem = &self.turrets.memory;
        for k in 0..mem.len() {
            word(self.row_of_id(mem.victim[k]) as u64);
            word(self.row_of_id(mem.attacker[k]) as u64);
            word(mem.until_s[k].to_bits());
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
