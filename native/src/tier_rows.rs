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
    // A row about to get its body back must not come back inside a rock or a mine (M4-T23): it flew through them as
    // a row, so it is moved clear first.
    fn clear_row_of_statics(&mut self, i: usize) {
        let r = &self.rows;
        let mut centers: Vec<Vector3> = Vec::new();
        let mut radii: Vec<f64> = Vec::new();
        for j in 0..r.body_ids.len() {
            if r.is_static[j] {
                centers.push(r.positions[j]);
                radii.push(r.radii[j]);
            }
        }
        let t = &mut self.tier;
        if let Some(at) = tier::clear_of_statics(
            t.positions[i],
            &t.bases[i],
            t.half_extents[i],
            t.radii[i],
            &centers,
            &radii,
        ) {
            t.positions[i] = at;
            self.tier_cleared += 1;
        }
    }

    // The target columns of tier rows `list` (M4-T23): what a selection, the radar or a candidate list reads of a row.
    fn tier_target_columns(&self, list: &[usize]) -> VarArray {
        let t = &self.tier;
        let mut ids = PackedInt64Array::new();
        let mut positions = PackedVector3Array::new();
        let mut velocities = PackedVector3Array::new();
        let mut factions: Array<StringName> = Array::new();
        let mut reach = PackedFloat64Array::new();
        let mut names = PackedStringArray::new();
        let mut radii = PackedFloat64Array::new();
        let mut hulls = PackedFloat64Array::new();
        let mut bodies = PackedInt64Array::new();
        for &i in list {
            ids.push(t.marker_ids[i]);
            positions.push(t.positions[i]);
            velocities.push(t.velocities[i]);
            factions.push(
                &self
                    .factions
                    .get(t.faction_ix[i] as usize)
                    .cloned()
                    .unwrap_or_default(),
            );
            reach.push(t.reach[i]);
            names.push(&self.tier_names[i]);
            radii.push(t.radii[i]);
            hulls.push(t.hull_fraction[i]);
            bodies.push(t.body_ids[i]);
        }
        let mut out = VarArray::new();
        out.push(&ids.to_variant());
        out.push(&positions.to_variant());
        out.push(&velocities.to_variant());
        out.push(&factions.to_variant());
        out.push(&reach.to_variant());
        out.push(&names.to_variant());
        out.push(&radii.to_variant());
        out.push(&hulls.to_variant());
        out.push(&bodies.to_variant());
        out
    }

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

    /// Promotes body `body_id`: its row's state (`position`, `velocity`, `basis`, `angular`, `pod_yaw`, `assist_on`,
    /// `hulk`, `command`, `cruise`, `kind`), the row removed. Empty when the body is not in the tier.
    #[func]
    fn tier_take(&mut self, body_id: i64) -> VarDictionary {
        let Some(i) = self.tier.index_of(body_id) else {
            return VarDictionary::new();
        };
        self.clear_row_of_statics(i);
        let out = self.tier_dict(i);
        if let Some((at, moved)) = self.tier.remove(body_id) {
            self.tier_names.swap_remove(at);
            debug_assert!(moved.is_none() || self.tier_names.len() == self.tier.len());
        }
        self.tier_promotions += 1;
        out
    }

    /// Removes body `body_id`'s row with no promotion (fix round 1: a release or a death in the tier): no clearance, not
    /// counted as a promotion. False when it is not in the tier.
    #[func]
    fn tier_remove(&mut self, body_id: i64) -> bool {
        match self.tier.remove(body_id) {
            Some((at, _)) => {
                self.tier_names.swap_remove(at);
                true
            }
            None => false,
        }
    }

    /// A capital row's hull box, half extents in its own frame (fix round 1): it is cleared of rocks by its hull, not by its
    /// bounding sphere.
    #[func]
    fn tier_set_box(&mut self, body_id: i64, half_extents: Vector3) -> bool {
        let Some(i) = self.tier.index_of(body_id) else {
            return false;
        };
        self.tier.half_extents[i] = half_extents;
        true
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

    /// Sets the beat: a row's forces are recomputed every `period` ticks (1 or more).
    #[func]
    fn tier_set_period(&mut self, period: i64) {
        self.tier_period = period.max(1);
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

    /// Adds a hit to the fighters' rolled hits as a roll would (the tests: a hit pending while its shooter is promoted).
    #[func]
    fn tier_push_hit(&mut self, target: i64, shooter: i64, damage: f64, at: Vector3) {
        self.tier_hits.push(target, shooter, damage, at);
    }

    /// The rams that land now (fix round 1): every committed rammer whose target is in its row command, where one of the
    /// two flies in the tier, that comes within ram reach of its target over the next `delta` seconds and was not touching
    /// it at the last check. `[rammers (body ids), targets (body ids), rammers' velocities, targets' velocities, points]`.
    /// Two near ships ram through the ram resolver, not here.
    #[func]
    fn tier_ram_contacts(&mut self, delta: f64) -> VarArray {
        let r = &self.rows;
        let mut touching = std::collections::HashSet::new();
        let (mut rammers, mut targets) = (Vec::new(), Vec::new());
        let (mut v_rammers, mut v_targets, mut points) = (Vec::new(), Vec::new(), Vec::new());
        for i in 0..r.body_ids.len() {
            let Some(rc) = self.row_commands.get(&r.body_ids[i]) else {
                continue;
            };
            if !rc.ram || rc.target <= 0 {
                continue;
            }
            let Ok(j) = usize::try_from(r.row_of_id(rc.target)) else {
                continue;
            };
            if (r.flags[i] | r.flags[j]) & crate::rows::FLAG_TIER == 0
                || r.flags[j] & crate::rows::FLAG_HULL == 0
            {
                continue;
            }
            if !crate::tier_fire::ram_touch(
                r.positions[i],
                r.velocities[i],
                r.radii[i],
                r.positions[j],
                r.velocities[j],
                r.radii[j],
                delta,
            ) {
                continue;
            }
            let pair = (r.body_ids[i], r.body_ids[j]);
            touching.insert(pair);
            if self.tier_ram_pairs.contains(&pair) {
                continue;
            }
            rammers.push(pair.0);
            targets.push(pair.1);
            v_rammers.push(r.velocities[i]);
            v_targets.push(r.velocities[j]);
            points.push(r.positions[j]);
        }
        self.tier_ram_pairs = touching;
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(rammers.as_slice()).to_variant());
        out.push(&PackedInt64Array::from(targets.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(v_rammers.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(v_targets.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(points.as_slice()).to_variant());
        out
    }

    /// How far outside its pilot's gate a tier shot leaves, m (`tier_fire::gate_excess_m`; the tests).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn tier_gate_excess(
        &self,
        at: Vector3,
        v: Vector3,
        forward: Vector3,
        target_at: Vector3,
        target_v: Vector3,
        muzzle_speed_mps: f64,
        cone_rad: f64,
        miss_m: f64,
    ) -> f64 {
        crate::tier_fire::gate_excess_m(
            at,
            v,
            forward,
            target_at,
            target_v,
            muzzle_speed_mps,
            cone_rad,
            miss_m,
        )
    }

    /// The fighters' rolled hits waiting to be taken (the director takes them only when there are some).
    #[func]
    fn tier_hit_count(&self) -> i64 {
        self.tier_hits.targets.len() as i64
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
    /// bounding radius, the bolt's hit radius and speed, the closing speed (m/s), the shooter's aim error (rad), its gate's
    /// miss distance (m), the bolt's reach (m) and how far outside the gate the shot left (m).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn tier_hit_chance(
        &self,
        range_m: f64,
        target_radius_m: f64,
        hit_radius_m: f64,
        muzzle_speed_mps: f64,
        closing_mps: f64,
        aim_error_rad: f64,
        miss_m: f64,
        reach_m: f64,
        excess_m: f64,
    ) -> f64 {
        crate::tier_fire::hit_chance(
            range_m,
            target_radius_m,
            hit_radius_m,
            muzzle_speed_mps,
            closing_mps,
            aim_error_rad,
            miss_m,
            reach_m,
            excess_m,
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
    fn tier_promotions(&self) -> i64 {
        self.tier_promotions
    }

    /// Promotions moved clear of a rock or mine they overlapped so far (M4-T23).
    #[func]
    fn tier_cleared(&self) -> i64 {
        self.tier_cleared
    }

    /// How body `body_id`'s row is drawn (M4-T23): `class` -1 a far dot in `paint` (linear), else that far hull class.
    #[func]
    fn tier_set_proxy(&mut self, body_id: i64, class: i64, paint: Color) -> bool {
        let Some(i) = self.tier.index_of(body_id) else {
            return false;
        };
        self.tier.proxy[i] = class.clamp(-1, i64::from(i32::MAX)) as i32;
        self.tier.paint[i] = [paint.r, paint.g, paint.b];
        true
    }

    /// Rows drawn as far dots.
    #[func]
    fn tier_dot_count(&self) -> i64 {
        tier::dot_count(&self.tier) as i64
    }

    /// Writes the far dots into `buffer` (`FarDots`' layout) from instance `start` on, each at its row's position plus
    /// `offset`: `[the buffer, grown when it was short, how many]`.
    #[func]
    fn tier_fill_dots(&self, buffer: PackedFloat32Array, start: i64, offset: Vector3) -> VarArray {
        let start = start.max(0) as usize;
        let need = (start + tier::dot_count(&self.tier)) * tier::DOT_STRIDE;
        let mut buf = buffer;
        if buf.len() < need {
            buf.resize(need);
        }
        let n = tier::fill_dots(&self.tier, offset, buf.as_mut_slice(), start);
        let mut out = VarArray::new();
        out.push(&buf.to_variant());
        out.push(&(n as i64).to_variant());
        out
    }

    /// The rows of far hull class `class` as MultiMesh transforms at their poses plus `offset`.
    #[func]
    fn tier_fill_hulls(&self, class: i64, offset: Vector3) -> PackedFloat32Array {
        let mut out: Vec<f32> = Vec::new();
        tier::fill_hulls(&self.tier, class as i32, offset, &mut out);
        PackedFloat32Array::from(out.as_slice())
    }

    /// The tier rows a ship at `own_position` could select (M4-T23): not body `own_body`, within `sensor_range` or their
    /// own broadcast reach, as `[marker ids, positions, velocities, factions, reach, names, radii, hulls 0..1, body ids]`.
    #[func]
    fn tier_targets(&self, own_position: Vector3, own_body: i64, sensor_range: f64) -> VarArray {
        let t = &self.tier;
        let list: Vec<usize> = (0..t.len())
            .filter(|&i| {
                t.body_ids[i] != own_body
                    && tier_range(own_position, t.positions[i]) <= sensor_range.max(t.reach[i])
            })
            .collect();
        self.tier_target_columns(&list)
    }

    /// The tier row whose marker id is `marker_id`, in `tier_targets`' columns (empty when none).
    #[func]
    fn tier_target(&self, marker_id: i64) -> VarArray {
        let list: Vec<usize> = self
            .tier
            .marker_ids
            .iter()
            .position(|&m| m == marker_id)
            .into_iter()
            .collect();
        self.tier_target_columns(&list)
    }

    /// Where body `body_id`'s row is now: xyz, w 1; w 0 when it is not in the tier.
    #[func]
    fn tier_position(&self, body_id: i64) -> Vector4 {
        match self.tier.index_of(body_id) {
            Some(i) => {
                let p = self.tier.positions[i];
                Vector4::new(p.x, p.y, p.z, 1.0)
            }
            None => Vector4::ZERO,
        }
    }
}

// The range between two points in 64 bits, as `TargetingSystem.range_between` takes it.
fn tier_range(a: Vector3, b: Vector3) -> f64 {
    let dx = f64::from(b.x) - f64::from(a.x);
    let dy = f64::from(b.y) - f64::from(a.y);
    let dz = f64::from(b.z) - f64::from(a.z);
    (dx * dx + dy * dy + dz * dz).sqrt()
}
