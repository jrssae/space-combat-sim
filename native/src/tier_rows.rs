// The core's shell around the low-attention tier (M4-T21, docs/architecture.md 17.14): the director demotes a far ship
// into a tier row and promotes it back, the core steps the rows at each sync (`tier.rs`), and the readouts. Every engine
// type stays here; the table and the integrator are engine-free.
use std::time::Instant;

use godot::prelude::*;

use crate::flight_step::body_from_arrays;
use crate::row_commands::{CMD_LEN, RowCommand};
use crate::sim_core::ScsSimCore;
use crate::tier::{self, KIND_CAPITAL, KIND_FIGHTER, Type};

/// Ticks between a tier row's beats when nothing set the rate (20 Hz at 60 ticks a second).
const DEFAULT_PERIOD: i64 = 3;

impl ScsSimCore {
    /// One tick of the tier, inside `sync_in`: the integration since the last tick, with the brains' commands.
    pub(crate) fn tier_step(&mut self, delta: f64) {
        if self.tier.is_empty() {
            self.tier_step_us = 0;
            return;
        }
        let started = Instant::now();
        let period = if self.tier_period > 0 {
            self.tier_period
        } else {
            DEFAULT_PERIOD
        };
        // The core's own sync count, so the beat falls the same way in every run of a seeded fight.
        let clock = self.syncs();
        self.tier_beats += tier::step(
            &mut self.tier,
            &self.tier_types,
            &self.tier_gravity,
            &self.row_commands,
            clock,
            delta,
            period,
            &mut self.tier_scratch,
        ) as i64;
        self.tier_step_us = started.elapsed().as_micros() as i64;
    }

    // A tier row's state as a Dictionary: what a promotion needs and the tests read.
    fn tier_dict(&self, i: usize) -> VarDictionary {
        let t = &self.tier;
        let mut out = VarDictionary::new();
        out.set("kind", i64::from(t.kinds[i]));
        out.set("body_id", t.body_ids[i]);
        out.set("marker_id", t.marker_ids[i]);
        out.set("handle", t.handles[i]);
        out.set("position", t.positions[i]);
        out.set("velocity", t.velocities[i]);
        out.set("basis", t.bases[i]);
        out.set("angular", t.angular[i]);
        out.set("cruise", t.cruise[i]);
        out.set("pod_yaw", t.pod_yaw[i]);
        out.set("assist_on", t.assist_on[i]);
        out.set("hulk", t.hulk[i]);
        out.set("hull_fraction", t.hull_fraction[i]);
        out.set("accel", t.accel[i]);
        out.set("alpha", t.alpha[i]);
        let rc = &t.commands[i];
        let mut command = PackedFloat64Array::new();
        for v in rc.cmd {
            command.push(v);
        }
        command.push(f64::from(u8::from(rc.fire)));
        out.set("command", &command);
        out
    }
}

#[godot_api(secondary)]
impl ScsSimCore {
    /// Registers a fighter type the tier can fly, from the arrays `ScsFlightStep.register` takes plus the body-frame centre
    /// of mass its nozzles turn it about. Returns the type's index, or -1 after logging why.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn tier_register_type(
        &mut self,
        spec: PackedFloat64Array,
        spec_vectors: PackedVector3Array,
        nozzle_groups: PackedInt32Array,
        nozzle_positions: PackedVector3Array,
        nozzle_exhausts: PackedVector3Array,
        torque_axes: PackedVector3Array,
        center_of_mass: Vector3,
    ) -> i64 {
        let Some(body) = body_from_arrays(
            "ScsSimCore.tier_register_type",
            &spec,
            &spec_vectors,
            &nozzle_groups,
            &nozzle_positions,
            &nozzle_exhausts,
            &torque_axes,
        ) else {
            return -1;
        };
        self.tier_types.push(Type {
            body,
            center_of_mass,
        });
        (self.tier_types.len() - 1) as i64
    }

    /// Fighter types registered.
    #[func]
    fn tier_type_count(&self) -> i64 {
        self.tier_types.len() as i64
    }

    /// Demotes body `body_id` into the tier: `kind` 0 a fighter of type `type_ix`, 1 a capital; the pose and motion as the
    /// body holds them. Returns the row's handle, or 0 when the body is in the tier already (or a fighter's type is
    /// unknown). `tier_set_attrs` and `tier_set_control` complete the row.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn tier_add(
        &mut self,
        kind: i64,
        body_id: i64,
        hull_id: i64,
        type_ix: i64,
        position: Vector3,
        velocity: Vector3,
        basis: Basis,
        angular: Vector3,
    ) -> i64 {
        let kind = if kind == i64::from(KIND_CAPITAL) {
            KIND_CAPITAL
        } else {
            KIND_FIGHTER
        };
        let Ok(type_ix) = u32::try_from(type_ix) else {
            return 0;
        };
        if kind == KIND_FIGHTER && type_ix as usize >= self.tier_types.len() {
            godot_error!(
                "ScsSimCore.tier_add: fighter type {type_ix} is not registered ({} types)",
                self.tier_types.len()
            );
            return 0;
        }
        // Handles below zero: a body's handle is its slot and generation, always above.
        self.next_tier_handle -= 1;
        let handle = self.next_tier_handle;
        self.next_tier_ordinal += 1;
        let added = self.tier.add(
            kind,
            body_id,
            hull_id,
            handle,
            type_ix,
            position,
            velocity,
            basis,
            angular,
            self.next_tier_ordinal,
        );
        if added.is_none() {
            return 0;
        }
        self.tier_names.push(GString::new());
        self.tier_demotions += 1;
        handle
    }

    /// A tier row's marker id (0: none, the body's id stands), faction, name, radius, broadcast reach and hull 0..1, as its
    /// marker and hull hold them.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn tier_set_attrs(
        &mut self,
        body_id: i64,
        marker_id: i64,
        faction: StringName,
        name: GString,
        radius: f64,
        reach: f64,
        hull_fraction: f64,
    ) -> bool {
        let faction_ix = self.faction_index(faction);
        let Some(i) = self.tier.index_of(body_id) else {
            return false;
        };
        if marker_id != 0 {
            self.tier.marker_ids[i] = marker_id;
        }
        self.tier.faction_ix[i] = faction_ix;
        self.tier.radii[i] = radius;
        self.tier.reach[i] = reach;
        self.tier.hull_fraction[i] = hull_fraction;
        self.tier.name_keys[i] = name.to_string().to_lowercase();
        self.tier_names[i] = name;
        true
    }

    /// A tier row's control: a capital's cruise velocity, a fighter's held command (`CMD_LEN` numbers and the trigger, as
    /// `row_command` gives them; empty for none), its assist state and whether its assist is on.
    #[func]
    fn tier_set_control(
        &mut self,
        body_id: i64,
        cruise: Vector3,
        command: PackedFloat64Array,
        pod_yaw: f64,
        assist_on: bool,
    ) -> bool {
        let Some(i) = self.tier.index_of(body_id) else {
            return false;
        };
        self.tier.cruise[i] = cruise;
        self.tier.pod_yaw[i] = pod_yaw;
        self.tier.assist_on[i] = assist_on;
        let c = command.as_slice();
        if c.len() >= CMD_LEN {
            let mut rc = RowCommand::default();
            rc.cmd.copy_from_slice(&c[..CMD_LEN]);
            rc.fire = c.get(CMD_LEN).is_some_and(|&f| f != 0.0);
            self.tier.commands[i] = rc;
        }
        true
    }

    /// Marks body `body_id`'s tier row a hulk (or a live ship again): a hulk drifts with no force and no brain.
    #[func]
    fn tier_set_hulk(&mut self, body_id: i64, hulk: bool) -> bool {
        let Some(i) = self.tier.index_of(body_id) else {
            return false;
        };
        self.tier.hulk[i] = hulk;
        if hulk {
            self.tier.accel[i] = Vector3::ZERO;
            self.tier.alpha[i] = Vector3::ZERO;
            self.tier.speed_limit[i] = 0.0;
        }
        true
    }

    /// A tier row's hull changed (0..1).
    #[func]
    fn tier_set_hull(&mut self, body_id: i64, hull_fraction: f64) -> bool {
        let Some(i) = self.tier.index_of(body_id) else {
            return false;
        };
        self.tier.hull_fraction[i] = hull_fraction;
        true
    }

    /// Promotes body `body_id`: its row's state (`position`, `velocity`, `basis`, `angular`, `pod_yaw`, `assist_on`,
    /// `hulk`, `command`, `cruise`, `kind`), the row removed. Empty when the body is not in the tier.
    #[func]
    fn tier_take(&mut self, body_id: i64) -> VarDictionary {
        let Some(i) = self.tier.index_of(body_id) else {
            return VarDictionary::new();
        };
        let out = self.tier_dict(i);
        if let Some((at, moved)) = self.tier.remove(body_id) {
            self.tier_names.swap_remove(at);
            debug_assert!(moved.is_none() || self.tier_names.len() == self.tier.len());
        }
        self.tier_promotions += 1;
        out
    }

    /// A tier row's state without removing it (the tests and the console), or empty.
    #[func]
    fn tier_state(&self, body_id: i64) -> VarDictionary {
        match self.tier.index_of(body_id) {
            Some(i) => self.tier_dict(i),
            None => VarDictionary::new(),
        }
    }

    /// Whether body `body_id` is a tier row.
    #[func]
    fn tier_has(&self, body_id: i64) -> bool {
        self.tier.index_of(body_id).is_some()
    }

    /// The tier's rows: all, the fighters, the capitals, the hulks.
    #[func]
    fn tier_count(&self) -> i64 {
        self.tier.len() as i64
    }

    #[func]
    fn tier_fighters(&self) -> i64 {
        self.tier
            .kinds
            .iter()
            .filter(|&&k| k == KIND_FIGHTER)
            .count() as i64
    }

    #[func]
    fn tier_capitals(&self) -> i64 {
        self.tier
            .kinds
            .iter()
            .filter(|&&k| k == KIND_CAPITAL)
            .count() as i64
    }

    #[func]
    fn tier_hulks(&self) -> i64 {
        self.tier.hulk.iter().filter(|&&h| h).count() as i64
    }

    /// Every tier row's body id.
    #[func]
    fn tier_body_ids(&self) -> PackedInt64Array {
        PackedInt64Array::from(self.tier.body_ids.as_slice())
    }

    /// Sets the beat: a row's forces are recomputed every `period` ticks (1 or more).
    #[func]
    fn tier_set_period(&mut self, period: i64) {
        self.tier_period = period.max(1);
    }

    #[func]
    fn tier_period(&self) -> i64 {
        if self.tier_period > 0 {
            self.tier_period
        } else {
            DEFAULT_PERIOD
        }
    }

    /// The pull the tier's rows feel: point sources at World-local `positions` with parameters `gm` (m^3/s^2). Empty for
    /// none. Returns false, after logging why, when the arrays differ in length.
    #[func]
    fn tier_set_gravity(&mut self, positions: PackedVector3Array, gm: PackedFloat64Array) -> bool {
        if positions.len() != gm.len() {
            godot_error!(
                "ScsSimCore.tier_set_gravity: {} positions but {} parameters; the pull is dropped",
                positions.len(),
                gm.len()
            );
            self.tier_gravity.positions.clear();
            self.tier_gravity.gm.clear();
            return false;
        }
        self.tier_gravity.positions = positions.as_slice().to_vec();
        self.tier_gravity.gm = gm.as_slice().to_vec();
        true
    }

    /// The pull at `at` as the tier computes it (the tests).
    #[func]
    fn tier_gravity_at(&self, at: Vector3) -> Vector3 {
        self.tier_gravity.accel(at)
    }

    /// The fighters and capitals in Jolt beyond `radius` of `player_at` (the player's body `exclude` left out), by body id,
    /// at most `max`: what the director demotes this tick. Read from the rows as the last sync left them.
    #[func]
    fn tier_far_bodies(
        &self,
        player_at: Vector3,
        exclude: i64,
        radius: f64,
        max: i64,
    ) -> PackedInt64Array {
        let mut out = Vec::new();
        tier::far_bodies(
            &self.rows,
            player_at,
            exclude,
            radius,
            usize::try_from(max).unwrap_or(0),
            &mut out,
        );
        PackedInt64Array::from(out.as_slice())
    }

    /// The tier rows within `radius` of `player_at`, by body id, at most `max`: what the director promotes this tick.
    #[func]
    fn tier_near_rows(&self, player_at: Vector3, radius: f64, max: i64) -> PackedInt64Array {
        let mut out = Vec::new();
        tier::near_rows(
            &self.tier,
            player_at,
            radius,
            usize::try_from(max).unwrap_or(0),
            &mut out,
        );
        PackedInt64Array::from(out.as_slice())
    }

    // --- the tier's fire (M4-T22) -------------------------------------------------------------------------------------

    /// The seed every tier roll draws from (the fighters' shots, the far capitals' guns, beams and missiles).
    #[func]
    fn tier_set_seed(&mut self, seed: i64) {
        self.tier_seed = seed as u64;
    }

    /// The fighters' hits rolled since the last take, as `[targets (body ids), shooters (body ids), damage, places]`, in
    /// the order they were rolled; the list starts afresh.
    #[func]
    fn tier_take_hits(&mut self) -> VarArray {
        let h = &self.tier_hits;
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(h.targets.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(h.shooters.as_slice()).to_variant());
        out.push(&PackedFloat64Array::from(h.damage.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(h.points.as_slice()).to_variant());
        self.tier_hits.clear();
        out
    }

    /// Tier fighters' shots rolled so far, and the hits among them.
    #[func]
    fn tier_shots(&self) -> i64 {
        self.tier_shots_total
    }

    #[func]
    fn tier_hits(&self) -> i64 {
        self.tier_hits_total
    }

    /// The chance one tier fighter's shot hits (the roll's model, for the tests and the console): the range, the target's
    /// bounding radius, the bolt's hit radius and speed, the shooter's aim error (rad), its gate's miss distance (m) and
    /// the bolt's reach (m).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn tier_hit_chance(
        &self,
        range_m: f64,
        target_radius_m: f64,
        hit_radius_m: f64,
        muzzle_speed_mps: f64,
        aim_error_rad: f64,
        miss_m: f64,
        reach_m: f64,
    ) -> f64 {
        crate::tier_fire::hit_chance(
            range_m,
            target_radius_m,
            hit_radius_m,
            muzzle_speed_mps,
            aim_error_rad,
            miss_m,
            reach_m,
        )
    }

    /// The last tick's tier step, microseconds (wall clock; a readout).
    #[func]
    fn tier_step_us(&self) -> i64 {
        self.tier_step_us
    }

    /// Beats run, demotions and promotions so far.
    #[func]
    fn tier_beats(&self) -> i64 {
        self.tier_beats
    }

    #[func]
    fn tier_demotions(&self) -> i64 {
        self.tier_demotions
    }

    #[func]
    fn tier_promotions(&self) -> i64 {
        self.tier_promotions
    }
}
