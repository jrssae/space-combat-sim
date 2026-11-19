// The core's shell around the defensive turrets (M5-T21, D61): mounts bound to their ships' rows, the attacker memory,
// the main-thread step (aim, fire gate, shot as an owned bolt row) and the picks handed over at the AI job's join. Every
// engine type stays here; the maths is `turret_kernels`, engine-free.
use std::collections::{HashMap, HashSet};
use std::time::Instant;

use godot::prelude::*;

use crate::brain_maths::solve;
use crate::grid_kernels::{
    self as gk, Battery, Incoming, KIND_INTERCEPT, KIND_MISSILE, Latch, MOUNT_HEAVY, MOUNT_INTERCEPTOR, MOUNT_LIGHT,
    MOUNT_TURRET, PulseHit, PulseScratch,
};
use crate::sim_core::{KIND_BOLT, ScsSimCore};
use crate::v3::{add, scale, sub};
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
    // The clock of the turrets' last step: when a provocation handed over at the join is remembered from (M7-T29).
    provoked_now_s: f64,
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
    // The interceptors' scratch: candidates, the bolts taken this tick, each bolt's time to the hull this tick, the big
    // hulls' rows and their bodies.
    incoming: Vec<Incoming>,
    taken: Vec<bool>,
    hull_times: Vec<f64>,
    surface_rows: Vec<usize>,
    surface_bodies: Vec<i64>,
    /// Each interceptor battery's barrels by slot (M7-T41); none for the other kinds.
    pub batteries: Vec<Option<Battery>>,
    // The batteries' pulses in flight by bolt id: who fired each, at what and when its lead said it would meet it.
    pulses: HashMap<i64, Pulse>,
    // This tick's targets with a pulse on the way, and the earliest meeting each expects.
    cover: HashMap<i64, f64>,
    live_pulses: HashSet<i64>,
    pulse_scratch: PulseScratch,
    pulse_hits: Vec<PulseHit>,
    // Pulses the batteries fired (a readout).
    grid_pulses: i64,
}

// A battery's pulse in flight (M7-T41).
#[derive(Clone, Copy)]
struct Pulse {
    slot: usize,
    target: i64,
    meet_at: f64,
}

/// What the batteries did in a tick (M7-T41): the pulses fired (slot, muzzle, bolt id, barrel) and the projectiles they met (slot of
/// the battery that fired the pulse, -1 when it is gone; the projectile's id; where they met; its colour).
#[derive(Default)]
struct Interceptions {
    shot_slots: Vec<i32>,
    shot_starts: Vec<Vector3>,
    shot_ids: Vec<i64>,
    shot_barrels: Vec<i32>,
    kill_slots: Vec<i32>,
    kill_ids: Vec<i64>,
    kill_points: Vec<Vector3>,
    kill_colors: Vec<Color>,
}

impl TurretState {
    fn new_stamp(&mut self) -> u32 {
        self.next_stamp = self.next_stamp.wrapping_add(1).max(1);
        self.next_stamp
    }
}

impl ScsSimCore {
    /// The launch's copy for the AI job: the live mounts, the memory and the relations as they stand.
    pub(crate) fn turret_snapshot_into(&mut self, job: &mut PickJob) {
        let bodies = self.sorted_surface_bodies();
        let t = &self.turrets;
        job.take_from(&t.mounts, &t.memory, &t.relations, t.stride, &t.hulls, &t.latch, &bodies);
        self.turrets.surface_bodies = bodies;
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
        // Civilians fired on by a ship that had them selected (M7-T29): remembered from the tick the job read.
        if t.mounts.count() > 0 {
            for &(victim, shooter) in &job.provoked {
                t.memory.note_provoked(victim, shooter, t.provoked_now_s);
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

    /// `[light pulse shots, heavy cannon shots, projectiles shot down, of them missiles, shots the station's hull blocked,
    /// interceptor pulses fired]`.
    #[func]
    fn grid_readouts(&self) -> PackedInt64Array {
        let t = &self.turrets;
        PackedInt64Array::from(
            &[
                t.grid_light_shots,
                t.grid_heavy_shots,
                t.grid_intercepts,
                t.grid_missile_intercepts,
                t.grid_blocked,
                t.grid_pulses,
            ][..],
        )
    }

    /// An interceptor battery's barrels (M7-T41): the trunnion in the yaw frame, up to four muzzles in the pitch frame (metres,
    /// Godot axes, -z down the barrel) and each barrel's recharge, s; they fire in turn, the gun's interval apart. False for a
    /// slot that holds no battery.
    #[func]
    fn set_battery_barrels(&mut self, slot: i64, trunnion: Vector3, muzzles: PackedVector3Array, recharge_s: f64) -> bool {
        let Some(s) = self.mount_slot(slot) else {
            return false;
        };
        if self.turrets.mounts.kind[s] != MOUNT_INTERCEPTOR {
            return false;
        }
        self.turrets.batteries[s] = Some(Battery::with(trunnion, muzzles.as_slice(), recharge_s));
        true
    }

    /// How far up its base's axis a gun's trunnion stands, m (M7-T43: the heavy cannon's, 9.5 m over its recess floor): its line of
    /// fire and its shots start there. False for no gun in the slot.
    #[func]
    fn set_turret_lift(&mut self, slot: i64, lift_m: f64) -> bool {
        let Some(s) = self.mount_slot(slot) else {
            return false;
        };
        if self.turrets.mounts.kind[s] == MOUNT_INTERCEPTOR {
            return false;
        }
        self.turrets.mounts.lift_m[s] = lift_m.max(0.0);
        true
    }

    /// A gun's bursts (M7-T43): `shots` a burst, `spacing_s` apart, a new burst its interval after the last began. One shot a burst
    /// is a plain gun. False for no gun in the slot.
    #[func]
    fn set_turret_burst(&mut self, slot: i64, shots: i64, spacing_s: f64) -> bool {
        let Some(s) = self.mount_slot(slot) else {
            return false;
        };
        if self.turrets.mounts.kind[s] == MOUNT_INTERCEPTOR {
            return false;
        }
        let m = &mut self.turrets.mounts;
        m.burst_shots[s] = u32::try_from(shots.max(1)).unwrap_or(1);
        m.burst_spacing_s[s] = spacing_s.max(0.0);
        m.burst_fired[s] = 0;
        true
    }

    /// A battery's barrels as set: `[trunnion, muzzles...]` and `[recharge, next barrel, each barrel's ready time...]`; empty for
    /// no battery.
    #[func]
    fn battery_state(&self, slot: i64) -> VarArray {
        let mut out = VarArray::new();
        let Some(b) = self.mount_slot(slot).and_then(|s| self.turrets.batteries.get(s).copied().flatten()) else {
            return out;
        };
        let mut points = vec![b.trunnion];
        points.extend_from_slice(&b.muzzles[..b.count]);
        let mut numbers = vec![b.recharge_s, b.next as f64];
        numbers.extend_from_slice(&b.ready_at[..b.count]);
        out.push(&PackedVector3Array::from(points.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(numbers.as_slice()).to_variant());
        out
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
        let batteries = &mut self.turrets.batteries;
        if batteries.len() <= slot {
            batteries.resize(slot + 1, None);
        }
        batteries[slot] = (kind == MOUNT_INTERCEPTOR).then(|| Battery::single(barrel_m.max(0.0), gun.interval_s));
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
            if let Some(b) = self.turrets.batteries.get_mut(s) {
                *b = None;
            }
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

    /// Marks a body as a navigation marker (or not, M7-T27): a place the player targets that avoidance flies through.
    #[func]
    fn set_navigation(&mut self, body_id: i64, on: bool) {
        if on {
            self.nav_bodies.insert(body_id);
        } else {
            self.nav_bodies.remove(&body_id);
        }
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
        out.set("lift_m", m.lift_m[s]);
        out.set("burst_shots", i64::from(m.burst_shots[s]));
        out.set("burst_fired", i64::from(m.burst_fired[s]));
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
    /// the barrel's tip; then the station grid's interceptor pulses meet what they meet and the batteries fire new ones at
    /// what is coming at the hull (M7-T07, M7-T41). Returns `[slots that fired (the guns', then the batteries'), the shots'
    /// starts, their bolt ids, the batteries whose pulses met a projectile, the projectiles' ids, where they met, the
    /// projectiles' colours, each shot's barrel (-1 for a gun)]`.
    #[func]
    fn step_turrets(&mut self, now_s: f64, delta: f64) -> VarArray {
        let started = Instant::now();
        let mut slots: Vec<i32> = Vec::new();
        let mut starts: Vec<Vector3> = Vec::new();
        let mut ids: Vec<i64> = Vec::new();
        self.turrets.memory.prune(now_s);
        self.turrets.provoked_now_s = now_s;
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
            // A raised gun leads, gates and fires from its trunnion, so its shot runs down the line it aimed.
            let at = tk::raised(&f, m.lift_m[s]);
            // A drum's gun moves with the skin under it: its bolts and its lead take that speed.
            let ship_velocity = if grid {
                gk::mount_velocity(&self.rows, own, at.pivot)
            } else {
                self.rows.velocities[own]
            };
            let gun = m.gun[s];
            let a = tk::aim(
                &at,
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
            let from = add(f.pivot, scale(f.up, m.line_lift(s) as f32));
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
            m.ready_at[s] = m.fired(s, now_s);
            m.shots[s] += 1;
            match m.kind[s] {
                MOUNT_LIGHT => self.turrets.grid_light_shots += 1,
                MOUNT_HEAVY => self.turrets.grid_heavy_shots += 1,
                _ => {}
            }
            let direction = tk::spread(a.axis, gun.spread_rad, m.id[s], tick);
            let (start, velocity) = tk::shot(
                at.pivot,
                a.axis,
                direction,
                m.barrel_m[s],
                ship_velocity,
                gun.muzzle_speed,
            );
            let id = self.add_owned_bolt(
                start,
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
            starts.push(start);
            ids.push(id);
        }
        let i = self.step_interceptors(&mut m, &surface_rows, now_s, delta, tick);
        let mut barrels = vec![-1i32; slots.len()];
        barrels.extend_from_slice(&i.shot_barrels);
        slots.extend_from_slice(&i.shot_slots);
        starts.extend_from_slice(&i.shot_starts);
        ids.extend_from_slice(&i.shot_ids);
        self.turrets.mounts = m;
        self.turrets.surface_rows = surface_rows;
        self.turrets.shots_total += slots.len() as i64;
        self.turrets.step_us = started.elapsed().as_micros() as i64;
        let mut out = VarArray::new();
        out.push(&PackedInt32Array::from(slots.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(starts.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(ids.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(i.kill_slots.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(i.kill_ids.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(i.kill_points.as_slice()).to_variant());
        out.push(&PackedColorArray::from(i.kill_colors.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(barrels.as_slice()).to_variant());
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

    /// Whether any civilian remembers a provocation (M7-T29), and whether `shooter`'s bolts may land on `target` though
    /// their sides are not hostile: `shooter` is a civilian that `target` fired on with it selected, at `now_s`.
    #[func]
    fn provoked_count(&self) -> i64 {
        self.turrets.memory.provoked_count() as i64
    }

    #[func]
    fn provoked_pair(&self, shooter: i64, target: i64, now_s: f64) -> bool {
        self.turrets.memory.is_provoked(shooter, target, now_s)
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
            // Only a burst in progress adds words (M7-T43), so every digest without one is as it was.
            if m.burst_fired[s] > 0 {
                word(u64::from(m.burst_fired[s]));
                word(m.burst_started_s[s].to_bits());
            }
            // Only a battery adds words (M7-T41), so every digest without one is as it was.
            if let Some(Some(b)) = self.turrets.batteries.get(s) {
                word(b.next as u64);
                for r in &b.ready_at[..b.count] {
                    word(r.to_bits());
                }
            }
        }
        let mem = &self.turrets.memory;
        for k in 0..mem.len() {
            word(self.row_of_id(mem.victim[k]) as u64);
            word(self.row_of_id(mem.attacker[k]) as u64);
            word(mem.until_s[k].to_bits());
            if mem.provoked[k] {
                word(1); // only a provoked pair adds a word, so every digest without one is as it was
            }
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
        let bodies = self.sorted_surface_bodies();
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

    // The big hulls' body ids in order, in the turrets' reused buffer (the caller hands it back): no allocation a tick.
    fn sorted_surface_bodies(&mut self) -> Vec<i64> {
        let mut bodies = std::mem::take(&mut self.turrets.surface_bodies);
        bodies.clear();
        bodies.extend(self.surfaces.keys().copied());
        bodies.sort_unstable();
        bodies
    }

    // The interceptor batteries' tick (D75, M7-T41). First the pulses in flight meet what their last move touched (both spent).
    // Then each battery looks at the hostile missiles and pulse bolts within its reach whose path meets the hull (any such shot
    // sets the grid weapons free against its side: it was fired at the station), and when its next barrel is ready fires a
    // pulse at one it can reach (inside its arc, not behind the hull, not already covered by a pulse that gets there before it
    // hits, and one the pulse can catch): a missile first, then the one that hits soonest. The pulse leaves the barrel's
    // muzzle on a lead course from there, thrown off by a spread hashed from the battery, its shot count and the tick.
    fn step_interceptors(
        &mut self,
        m: &mut Mounts,
        surface_rows: &[usize],
        now_s: f64,
        delta: f64,
        tick: i64,
    ) -> Interceptions {
        let mut out = Interceptions::default();
        if !m.kind.contains(&MOUNT_INTERCEPTOR) || self.bolts.ids.is_empty() {
            return out;
        }
        self.meet_pulses(&mut out);
        if surface_rows.is_empty() {
            return out;
        }
        self.pulse_cover(now_s);
        let mut incoming = std::mem::take(&mut self.turrets.incoming);
        let mut taken = std::mem::take(&mut self.turrets.taken);
        taken.clear();
        taken.resize(self.bolts.ids.len(), false);
        let mut hull_times = std::mem::take(&mut self.turrets.hull_times);
        hull_times.clear();
        hull_times.resize(self.bolts.ids.len(), gk::NOT_SWEPT);
        let relations = std::mem::take(&mut self.turrets.relations);
        let mut cover = std::mem::take(&mut self.turrets.cover);
        let stride = self.turrets.stride;
        // New pulses join the rows after the loop: adding a row moves the rows the loop indexes.
        let mut fired: Vec<(usize, usize, Vector3, Vector3, i64, f64)> = Vec::new();
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
                &mut hull_times,
                &mut incoming,
            );
            for c in &incoming {
                self.turrets.latch.set(g, self.bolts.faction_ix[c.bolt as usize]);
            }
            let Some(mut battery) = self.turrets.batteries.get(s).copied().flatten() else {
                continue;
            };
            if now_s + 1e-6 < m.ready_at[s] || !battery.barrel_ready(now_s) {
                continue;
            }
            let gun = m.gun[s];
            let mount_velocity = gk::mount_velocity(&self.rows, own, f.pivot);
            let trunnion = gk::muzzle_point(&f, m.azimuth[s], m.elevation[s], battery.trunnion, Vector3::ZERO);
            let bolts = &self.bolts;
            // A pulse does not move on its launch tick: it is led to where the target will be when it starts to fly.
            let lead_from = |from: Vector3, p: usize| {
                let ahead = add(bolts.positions[p], scale(bolts.velocities[p], delta as f32));
                solve(from, mount_velocity, ahead, bolts.velocities[p], gun.muzzle_speed, gun.lifetime_s)
            };
            let pick = gk::choose_in_reach_if(
                &self.rows,
                surface_rows,
                bolts,
                &f,
                m.min_elevation[s],
                &incoming,
                &taken,
                |c| {
                    let p = c.bolt as usize;
                    let covered = cover.get(&bolts.ids[p]).is_some_and(|&meet| meet <= now_s + c.hit_in_s);
                    !covered && lead_from(trunnion, p).ok
                },
            );
            let Some(pick) = pick else {
                continue;
            };
            let p = pick.bolt as usize;
            taken[p] = true;
            let barrel = battery.fire(now_s);
            let shot = gk::battery_shot(
                &f,
                &gk::Barrel {
                    min_elevation: m.min_elevation[s],
                    azimuth: m.azimuth[s],
                    trunnion: battery.trunnion,
                    muzzle: battery.muzzles[barrel],
                },
                gun.muzzle_speed,
                {
                    let lead = lead_from(trunnion, p);
                    (lead.aim_dir, lead.t)
                },
                |from| Some(lead_from(from, p)).filter(|l| l.ok).map(|l| (l.aim_dir, l.t)),
            );
            let (muzzle, flight_s) = (shot.muzzle, shot.flight_s);
            let direction =
                tk::spread(shot.aim, gun.spread_rad, m.id[s].wrapping_mul(1 << 20).wrapping_add(m.shots[s]), tick);
            let velocity = add(mount_velocity, scale(direction, gun.muzzle_speed as f32));
            let meet_at = now_s + delta + flight_s;
            let target = bolts.ids[p];
            let earliest = cover.entry(target).or_insert(meet_at);
            *earliest = earliest.min(meet_at);
            self.turrets.batteries[s] = Some(battery);
            m.ready_at[s] = now_s + gun.interval_s;
            m.shots[s] += 1;
            m.azimuth[s] = shot.azimuth;
            m.elevation[s] = shot.elevation;
            fired.push((s, barrel, muzzle, velocity, target, meet_at));
        }
        for (s, barrel, muzzle, velocity, target, meet_at) in fired {
            let gun = m.gun[s];
            let id = self.add_owned_bolt(
                muzzle,
                velocity,
                m.faction_ix[s],
                m.body[s],
                KIND_INTERCEPT,
                gun.hit_radius,
                0.0,
                gun.color,
                gun.look,
                now_s + gun.lifetime_s,
            );
            self.turrets.pulses.insert(id, Pulse { slot: s, target, meet_at });
            self.turrets.grid_pulses += 1;
            out.shot_slots.push(s as i32);
            out.shot_starts.push(muzzle);
            out.shot_ids.push(id);
            out.shot_barrels.push(barrel as i32);
        }
        self.turrets.relations = relations;
        self.turrets.cover = cover;
        self.turrets.incoming = incoming;
        self.turrets.taken = taken;
        self.turrets.hull_times = hull_times;
        out
    }

    // The pulses that met a projectile along the bolts' last move (M7-T41): both spent, the projectile reported with the battery
    // that fired the pulse, where they met and the projectile's colour (its flash and spark).
    fn meet_pulses(&mut self, out: &mut Interceptions) {
        let mut hits = std::mem::take(&mut self.turrets.pulse_hits);
        let mut scratch = std::mem::take(&mut self.turrets.pulse_scratch);
        gk::pulse_hits(&self.bolts, &self.turrets.relations, self.turrets.stride, &mut scratch, &mut hits);
        for h in &hits {
            let (p, q) = (h.pulse as usize, h.target as usize);
            let b = &mut self.bolts;
            let step = b.last_steps[p];
            let at = add(sub(b.positions[p], step), scale(step, h.t as f32));
            b.spent[p] = true;
            b.spent[q] = true;
            let slot = self.turrets.pulses.get(&b.ids[p]).map_or(-1, |info| info.slot as i32);
            self.turrets.grid_intercepts += 1;
            self.turrets.grid_missile_intercepts += i64::from(b.kinds[q] == KIND_MISSILE);
            let c = b.colors[q];
            out.kill_slots.push(slot);
            out.kill_ids.push(b.ids[q]);
            out.kill_points.push(at);
            out.kill_colors.push(Color::from_rgba(c[0], c[1], c[2], c[3]));
        }
        self.turrets.pulse_hits = hits;
        self.turrets.pulse_scratch = scratch;
    }

    // The pulses still flying and, for each target, the earliest meeting a pulse on its way expects (M7-T41). A pulse past its
    // meeting by `COVER_SLACK_S` missed: its target is free to be shot at again. Records of pulses gone are dropped.
    fn pulse_cover(&mut self, now_s: f64) {
        let t = &mut self.turrets;
        t.cover.clear();
        t.live_pulses.clear();
        let b = &self.bolts;
        for p in 0..b.owned {
            if b.kinds[p] != KIND_INTERCEPT || b.spent[p] {
                continue;
            }
            t.live_pulses.insert(b.ids[p]);
            if let Some(info) = t.pulses.get(&b.ids[p])
                && now_s <= info.meet_at + gk::COVER_SLACK_S
            {
                let earliest = t.cover.entry(info.target).or_insert(info.meet_at);
                *earliest = earliest.min(info.meet_at);
            }
        }
        let live = &t.live_pulses;
        t.pulses.retain(|id, _| live.contains(id));
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
