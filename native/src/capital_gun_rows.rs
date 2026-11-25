// The core's shell around the capital turrets, launchers and interceptor batteries (M10-T14, M10-T13, D12.9): GDScript registers
// each capital's mounts once, tells the rows when a mount stops working or the rate of fire changes, and steps them once a
// tick from `SimCore.step_now`, before the bolts move: the interceptors' pulses meet what they meet, the batteries fire, the
// missiles in flight are steered, then every gun aims and fires, its shots added as owned bolt rows (with their toughness,
// Q81) that the core's hit sweep lands like any other. The maths is `capital_gun_kernels` and `capital_intercepts`,
// engine-free.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::capital_gun_kernels::{self as ck, GunSpec, GunWorld, Missile, Mount, Owner, Shot, Tally};
use crate::capital_intercepts::{GuardView, Guards, Met, PulseShot};
use crate::grid_kernels::{KIND_INTERCEPT, KIND_MISSILE};
use crate::sim_core::{KIND_BOLT, ScsSimCore};

/// Numbers a weapon packs into for `add_mount`: launcher, role (3: an interceptor battery), damage, barrels, burst shots,
/// burst spacing (s), cycle (s), speed (m/s), range (m), lifetime (s), hit radius (m), spread (deg), traverse (deg/s),
/// elevation (deg/s), nav gain, turn (rad/s), warhead, look, toughness (the pulses one of its shots takes, Q81).
const SPEC_LEN: usize = 19;

/// Every capital's gun turrets and launchers as rows with no node, stepped once a tick over the core's rows. Never calls
/// the engine or `Factions`: the caller passes the hostility table (by the core's faction indices).
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsCapitalGuns {
    base: Base<RefCounted>,
    core: Option<Gd<ScsSimCore>>,
    mounts: Vec<Mount>,
    owner_of: Vec<u32>,
    owners: Vec<Owner>,
    missiles: Vec<Missile>,
    hostile: Vec<bool>,
    friendly: Vec<bool>,
    factions: usize,
    guards: Guards,
    next_id: i64,
    // Per-step scratch, kept between ticks.
    owner_rows: Vec<i32>,
    shots: Vec<Shot>,
    steers: Vec<(usize, Vector3)>,
    tally: Tally,
    scratch: ck::Scratch,
    pulse_shots: Vec<PulseShot>,
    mets: Vec<Met>,
    shooter_rows: Vec<i32>,
    bolts_total: i64,
    missiles_total: i64,
    last_us: f64,
    kernel_us: f64,
}

#[godot_api]
impl ScsCapitalGuns {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Reads the core's rows, and adds its shots to the core's bolts, from now on.
    #[func]
    fn attach_core(&mut self, core: Gd<ScsSimCore>) -> bool {
        self.core = Some(core);
        true
    }

    /// The relations table, row-major by the core's faction indices (1 hostile, 2 friendly, 0 neutral): `count` factions square.
    #[func]
    fn set_hostility(&mut self, count: i64, matrix: PackedByteArray) -> bool {
        let n = usize::try_from(count).unwrap_or(0);
        if matrix.len() != n * n {
            godot_error!("ScsCapitalGuns.set_hostility: {} entries for {n} factions", matrix.len());
            return false;
        }
        self.factions = n;
        self.hostile = matrix.as_slice().iter().map(|&b| b == 1).collect();
        self.friendly = matrix.as_slice().iter().map(|&b| b == 2).collect();
        true
    }

    /// How many factions the core knows now (the hostility table must cover them all).
    #[func]
    fn faction_count(&self) -> i64 {
        self.core.as_ref().map_or(0, |c| c.bind().factions.len() as i64)
    }

    /// Ship `body` and its own bodies (hull and rotating sections), which never block or take its fire. Again: they change.
    #[func]
    fn add_owner(&mut self, body: i64, bodies: PackedInt64Array) {
        let list = bodies.as_slice().to_vec();
        match self.owners.iter_mut().find(|o| o.body == body) {
            Some(o) => o.bodies = list,
            None => self.owners.push(Owner { body, bodies: list, order: 0 }),
        }
    }

    /// One mount of ship `owner` (`add_owner` first): where it sits in the ship's frame, the cone it covers (`half_deg` round
    /// `axis`, azimuth 0 toward `zero`) and the wider one it picks targets in (`pick_half_deg`), whether its barrel rests on
    /// the axis (a fixed gun, a launcher), its barrel's length, and its weapon (`SPEC_LEN` numbers and its bolts' colour). Its
    /// index, or -1 when refused.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn add_mount(
        &mut self,
        owner: i64,
        local_at: Vector3,
        axis: Vector3,
        zero: Vector3,
        half_deg: f64,
        pick_half_deg: f64,
        rest_on_axis: bool,
        barrel_m: f64,
        spec: PackedFloat64Array,
        color: Color,
    ) -> i64 {
        let s = spec.as_slice();
        let Some(o) = self.owners.iter().position(|w| w.body == owner) else {
            godot_error!("ScsCapitalGuns.add_mount: ship {owner} has no add_owner");
            return -1;
        };
        if s.len() != SPEC_LEN || s.iter().any(|x| !x.is_finite()) {
            godot_error!("ScsCapitalGuns.add_mount: {} numbers (want {SPEC_LEN}, all finite)", s.len());
            return -1;
        }
        let made = GunSpec {
            launcher: s[0] != 0.0,
            role: (s[1] as i64).clamp(0, i64::from(ck::ROLE_PD)) as u8,
            damage: s[2],
            barrels: s[3].max(1.0) as u32,
            burst_shots: s[4].max(1.0) as u32,
            burst_spacing_s: s[5].max(0.0),
            cycle_s: s[6].max(1e-3),
            speed_mps: s[7].max(1.0),
            range_m: s[8].max(0.0),
            lifetime_s: s[9].max(1e-3),
            hit_radius_m: s[10].max(0.0),
            spread_rad: s[11].max(0.0).to_radians(),
            traverse_rad_s: s[12].max(0.0).to_radians(),
            elevation_rad_s: s[13].max(0.0).to_radians(),
            nav_gain: s[14],
            turn_rad_s: s[15].max(0.0),
            warhead: match s[16] as i64 {
                1 => ck::WARHEAD_MISSILE,
                2 => ck::WARHEAD_TORPEDO,
                _ => ck::WARHEAD_NONE,
            },
            color: [color.r, color.g, color.b, color.a],
            look: (s[17] as i64).clamp(0, 255) as u8,
            toughness: (s[18] as i64).clamp(1, 255) as u8,
        };
        self.next_id += 1;
        let mut mount = Mount::new(
            owner,
            self.next_id,
            local_at,
            axis,
            zero,
            half_deg.to_radians(),
            rest_on_axis,
            barrel_m,
            made,
        )
        .with_pick_cone(pick_half_deg.max(half_deg).to_radians());
        mount.pick_wait = (self.mounts.len() as u32) % ck::PICK_EVERY;
        self.mounts.push(mount);
        self.owner_of.push(o as u32);
        (self.mounts.len() - 1) as i64
    }

    /// Ship `body` leaves: its mounts go, the rest keep their order (GDScript drops the same entries). Its missiles in
    /// flight fly on, guided as before (`capital_gun_kernels::remove_owner`).
    #[func]
    fn remove_owner(&mut self, body: i64) {
        ck::remove_owner(&mut self.mounts, &mut self.owners, &mut self.owner_of, &mut self.missiles, body);
        self.guards.forget(body);
    }

    /// Whether mount `index` works, and its ship's rate of fire (0 to 1).
    #[func]
    fn set_works(&mut self, index: i64, works: bool, rate: f64) {
        if let Some(m) = usize::try_from(index).ok().and_then(|i| self.mounts.get_mut(i)) {
            m.works = works;
            m.rate = if rate.is_finite() { rate.clamp(0.0, 1.0) } else { 0.0 };
        }
    }

    /// The target ship `body`'s brain gives its anti-capital and dual mounts (0: they pick their own).
    #[func]
    fn set_order(&mut self, body: i64, target: i64) {
        if let Some(o) = self.owners.iter_mut().find(|w| w.body == body) {
            o.order = target;
        }
    }

    /// Ship `body`'s mounts ready at once and looking for a target now (the console's test shot). How many it has.
    #[func]
    fn ready_now(&mut self, body: i64) -> i64 {
        let mut n = 0;
        for m in self.mounts.iter_mut().filter(|m| m.owner == body) {
            m.ready_at = f64::NEG_INFINITY;
            m.burst_fired = 0;
            m.pick_wait = 0;
            m.target = 0;
            n += 1;
        }
        n
    }

    #[func]
    fn count(&self) -> i64 {
        self.mounts.len() as i64
    }

    /// Missiles and torpedoes in flight now.
    #[func]
    fn missile_count(&self) -> i64 {
        self.missiles.len() as i64
    }

    /// The warhead of bolt `bolt_id` when it is one of these missiles (`capital_gun_kernels::WARHEAD_*`), else 0.
    #[func]
    fn warhead_of(&self, bolt_id: i64) -> i64 {
        self.missiles.iter().find(|m| m.bolt == bolt_id).map_or(0, |m| i64::from(m.warhead))
    }

    /// Mount `index`'s state: `[target body, azimuth, elevation (rad), ready at (s), shots, works, rate]`; empty when none.
    #[func]
    fn state(&self, index: i64) -> VarArray {
        let mut out = VarArray::new();
        if let Some(m) = usize::try_from(index).ok().and_then(|i| self.mounts.get(i)) {
            out.push(&m.target.to_variant());
            out.push(&m.azimuth.to_variant());
            out.push(&m.elevation.to_variant());
            out.push(&m.ready_at.to_variant());
            out.push(&m.shots.to_variant());
            out.push(&m.works.to_variant());
            out.push(&m.rate.to_variant());
        }
        out
    }

    /// `[bolts fired, missiles launched, shots the own hull blocked, picks that found a target, candidates the own hull hid]` so
    /// far (readouts).
    #[func]
    fn readouts(&self) -> PackedInt64Array {
        PackedInt64Array::from(
            &[self.bolts_total, self.missiles_total, self.tally.blocked, self.tally.picks, self.tally.hidden][..],
        )
    }

    /// The interceptors' counts since the rows were made: `[pulses fired, pulses that met a shot, bolts down, heavy bolts down,
    /// missiles down, torpedoes down, pulses in flight]` (readouts).
    #[func]
    fn intercept_readouts(&self) -> PackedInt64Array {
        let t = &self.guards.tally;
        PackedInt64Array::from(
            &[t.pulses, t.met, t.down[0], t.down[1], t.down[2], t.down[3], self.guards.book.pulses.len() as i64][..],
        )
    }

    /// Ship `body`'s share: `[hostile shots its batteries saw headed for its own hull, of those shot down]`.
    #[func]
    fn intercept_share(&self, body: i64) -> PackedInt64Array {
        let (seen, down) = self.guards.share_of(body);
        PackedInt64Array::from(&[seen, down][..])
    }

    /// Wall-clock microseconds of the last step, and of its kernels alone (readouts, never gameplay).
    #[func]
    fn last_us(&self) -> f64 {
        self.last_us
    }

    #[func]
    fn kernel_us(&self) -> f64 {
        self.kernel_us
    }

    /// A hash of every mount's aim, target, gate and shots and of the missiles in flight, for comparing runs byte for byte
    /// (targets by their rows, which a seeded run lays out alike, not by instance ids).
    #[func]
    fn digest(&self) -> i64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut word = |w: u64| {
            for b in w.to_le_bytes() {
                h ^= u64::from(b);
                h = h.wrapping_mul(0x0000_0100_0000_01b3);
            }
        };
        let row = |id: i64| self.core.as_ref().map_or(-1, |c| c.bind().row_of_id(id));
        for m in &self.mounts {
            word(m.azimuth.to_bits());
            word(m.elevation.to_bits());
            word(row(m.target) as u64);
            for c in [m.aim_local.x, m.aim_local.y, m.aim_local.z] {
                word(u64::from(c.to_bits()));
            }
            word(m.ready_at.to_bits());
            word(m.shots as u64);
            word(m.battery.next as u64);
        }
        let t = &self.guards.tally;
        for w in [t.pulses, t.met, t.down[0], t.down[1], t.down[2], t.down[3]] {
            word(w as u64);
        }
        for missile in &self.missiles {
            word(u64::from(missile.mount));
            word(row(missile.target) as u64);
        }
        h as i64
    }

    /// One tick at sim time `now_s` (from `SimCore.step_now`, after the sync and before the bolts move): the interceptors' pulses
    /// meet what their last move touched, the batteries fire at what comes at their ships and friends, the missiles in flight
    /// are steered, then every gun aims and fires; each pulse and shot an owned bolt row (a missile's of the missile kind, a
    /// pulse's of the interceptor kind). Returns `[shots' mounts, their starts, their bolt ids, whether each is a missile
    /// (bytes), the body each was fired at, pulses' mounts, their starts, their barrels, meetings' mounts (-1 gone), the shots'
    /// ids, where they met, the shots' colours, whether each went down (bytes), what each was (`capital_intercepts::SHOT_*`)]`.
    #[func]
    fn step(&mut self, now_s: f64, delta: f64) -> VarArray {
        let started = std::time::Instant::now();
        self.shots.clear();
        self.steers.clear();
        self.pulse_shots.clear();
        let mut out = VarArray::new();
        let Some(mut core) = self.core.clone() else {
            return out;
        };
        let live = delta.is_finite() && delta > 0.0;
        // Each bolt's shooter's row, for what the guarding ship perceives of it (Q55): only while there are batteries.
        let guarding = !self.guards.book.pulses.is_empty() || self.mounts.iter().any(|m| m.spec.role == ck::ROLE_PD);
        self.shooter_rows.clear();
        if guarding {
            let c = core.bind();
            self.shooter_rows.extend(c.bolts.shooters.iter().map(|&b| i32::try_from(c.row_for_kernel(b)).unwrap_or(-1)));
        }
        let kernel_started = std::time::Instant::now();
        if live && guarding {
            let mut c = core.bind_mut();
            let c = &mut *c;
            self.guards.meet(
                &self.mounts,
                &mut c.bolts,
                &c.rows,
                &self.shooter_rows,
                &self.hostile,
                self.factions,
                &self.missiles,
                &mut self.mets,
            );
        } else {
            self.mets.clear();
        }
        let guard = core.bind();
        self.owner_rows.clear();
        let rows = &guard.rows;
        // A ship fires from a live rigid body in play, not from a tier row (the far fire is the tier's).
        self.owner_rows.extend(self.owners.iter().map(|o| {
            crate::turret_kernels::firing_row(rows, guard.row_for_kernel(o.body)).map_or(-1, |r| r as i32)
        }));
        let world = GunWorld {
            rows,
            hull_rows: &guard.sweep_rows,
            owner_rows: &self.owner_rows,
            hostile: &self.hostile,
            factions: self.factions,
            row_of: |id: i64| usize::try_from(guard.row_for_kernel(id)).ok(),
            rest: guard.frame_rest().velocity,
        };
        let tick = guard.syncs();
        if live {
            if guarding {
                let view = GuardView { friendly: &self.friendly, shooter_rows: &self.shooter_rows };
                self.guards.step(
                    &mut self.mounts,
                    &self.owners,
                    &self.owner_of,
                    &world,
                    &view,
                    &guard.bolts,
                    &self.missiles,
                    now_s,
                    delta,
                    tick,
                    &mut self.pulse_shots,
                );
            }
            ck::steer_missiles(&mut self.missiles, &guard.bolts, &world, delta, &mut self.steers);
            ck::step(
                &mut self.mounts,
                &self.owners,
                &self.owner_of,
                &world,
                now_s,
                delta,
                tick,
                &mut self.shots,
                &mut self.scratch,
                &mut self.tally,
            );
        }
        self.kernel_us = kernel_started.elapsed().as_secs_f64() * 1e6;
        let faction_of = |mount: u32| {
            let o = self.owner_of[mount as usize] as usize;
            usize::try_from(self.owner_rows[o]).map_or(0, |r| rows.faction_ix[r])
        };
        let factions: Vec<u32> = self.shots.iter().map(|s| faction_of(s.mount)).collect();
        let pulse_factions: Vec<u32> = self.pulse_shots.iter().map(|s| faction_of(s.mount)).collect();
        drop(guard);
        let mut c = core.bind_mut();
        for &(i, v) in &self.steers {
            if i < c.bolts.owned {
                c.bolts.velocities[i] = v;
            }
        }
        let np = self.pulse_shots.len();
        let mut pulse_mounts = Vec::with_capacity(np);
        let mut pulse_starts = Vec::with_capacity(np);
        let mut pulse_barrels = Vec::with_capacity(np);
        for (k, p) in self.pulse_shots.iter().enumerate() {
            let m = &self.mounts[p.mount as usize];
            let spec = m.spec;
            let id = c.add_owned_bolt(
                p.start,
                p.velocity,
                pulse_factions[k],
                m.owner,
                KIND_INTERCEPT,
                spec.hit_radius_m,
                0.0,
                spec.color,
                spec.look,
                now_s + spec.lifetime_s,
            );
            self.guards.note_pulse(id, p.mount_id, p.target, p.meet_at);
            pulse_mounts.push(p.mount as i32);
            pulse_starts.push(p.start);
            pulse_barrels.push(i32::from(p.barrel));
        }
        let n = self.shots.len();
        let mut mounts = Vec::with_capacity(n);
        let mut starts = Vec::with_capacity(n);
        let mut ids = Vec::with_capacity(n);
        let mut missile = Vec::with_capacity(n);
        let mut targets = Vec::with_capacity(n);
        for (k, s) in self.shots.iter().enumerate() {
            let m = &self.mounts[s.mount as usize];
            let spec = m.spec;
            let id = c.add_owned_bolt(
                s.start,
                s.velocity,
                factions[k],
                m.owner,
                if spec.launcher { KIND_MISSILE } else { KIND_BOLT },
                spec.hit_radius_m,
                spec.damage,
                spec.color,
                spec.look,
                now_s + spec.lifetime_s,
            );
            c.bolts.set_newest_owned_hits(spec.toughness);
            if spec.launcher {
                self.missiles.push(Missile {
                    bolt: id,
                    target: s.target,
                    mount: s.mount,
                    nav_gain: spec.nav_gain,
                    turn_rad_s: spec.turn_rad_s,
                    warhead: spec.warhead,
                });
                self.missiles_total += 1;
            } else {
                self.bolts_total += 1;
            }
            mounts.push(s.mount as i32);
            starts.push(s.start);
            ids.push(id);
            missile.push(u8::from(spec.launcher));
            targets.push(s.target);
        }
        drop(c);
        out.push(&PackedInt32Array::from(mounts.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(starts.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(ids.as_slice()).to_variant());
        out.push(&PackedByteArray::from(missile.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(targets.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(pulse_mounts.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(pulse_starts.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(pulse_barrels.as_slice()).to_variant());
        let mets = &self.mets;
        let met_mounts: Vec<i32> = mets.iter().map(|m| m.mount).collect();
        let met_ids: Vec<i64> = mets.iter().map(|m| m.shot).collect();
        let met_points: Vec<Vector3> = mets.iter().map(|m| m.at).collect();
        let met_colors: Vec<Color> = mets.iter().map(|m| Color::from_rgba(m.color[0], m.color[1], m.color[2], m.color[3])).collect();
        let met_down: Vec<u8> = mets.iter().map(|m| u8::from(m.downed)).collect();
        let met_kinds: Vec<u8> = mets.iter().map(|m| m.kind).collect();
        out.push(&PackedInt32Array::from(met_mounts.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(met_ids.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(met_points.as_slice()).to_variant());
        out.push(&PackedColorArray::from(met_colors.as_slice()).to_variant());
        out.push(&PackedByteArray::from(met_down.as_slice()).to_variant());
        out.push(&PackedByteArray::from(met_kinds.as_slice()).to_variant());
        self.last_us = started.elapsed().as_secs_f64() * 1e6;
        out
    }
}
