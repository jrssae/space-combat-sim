// The pulse cannons as rows (M4-T35, docs/architecture.md 17.13): every registered cannon's gate, capacitor and muzzles,
// stepped in one call a tick over the core's rows. A cannon fires when its ship's row command (or the trigger GDScript
// pushed) holds the trigger and `bolt_kernels::Gate` allows it; each shot becomes an owned bolt row at the muzzle's World
// position with the velocity `PulseCannon.step` computes. `PulseCannon` keeps the muzzle flash and the signal.
// gdext's `init` derive writes `base: base`, which clippy flags on the struct's `base` field.
#![allow(clippy::redundant_field_names)]
use godot::prelude::*;

use crate::bolt_kernels::{self, Capacitor, Gate};
use crate::rows::{FLAG_HULK, FLAG_HULL, FLAG_RIGID, FLAG_TIER};
use crate::sim_core::{KIND_BOLT, ScsSimCore};
use crate::tier_fire;

// One registered cannon: its ship, its muzzles in the ship's frame, its gate and what its bolts carry.
struct Cannon {
    body_id: i64,
    muzzles: Vec<Vector3>,
    gate: Gate,
    muzzle_speed: f64,
    convergence_m: f64,
    lifetime_s: f64,
    damage: f64,
    hit_radius: f64,
    color: [f32; 4],
    look: u8,
    faction: StringName,
    // The trigger GDScript last pushed (used when the ship flies no row command) and a pending mode cycle.
    trigger: bool,
    weapon_next: bool,
    // Whether the cannon's node processes (a parked ship's does not).
    live: bool,
}

/// The pulse cannons stepped as rows over the core.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsCannons {
    base: Base<RefCounted>,
    slots: Vec<Option<Cannon>>,
    fired: Vec<usize>,
    // The last step's shots as `(slot, muzzle, bolt id)` triples with each shot's start, and the live slots whose ship
    // had no row.
    shots: Vec<i64>,
    shot_at: Vec<Vector3>,
    fallback: Vec<i32>,
    shots_total: i64,
    // The tier ships' cannons found this step (slot and row), fired after the rest, and that pass's time (M4-T22).
    tier_slots: Vec<(usize, usize)>,
    tier_us: f64,
}

#[godot_api]
impl ScsCannons {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Registers a cannon on body `body_id` with its muzzles (origins in the body's frame, in muzzle order), its gate
    /// (`interval_s` per bolt, the capacitor's capacity, cost per shot and recharge per second) and what its bolts carry.
    /// Returns the slot, or -1 for no muzzles.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn register(
        &mut self,
        body_id: i64,
        muzzles: PackedVector3Array,
        interval_s: f64,
        capacity: f64,
        cost_per_shot: f64,
        recharge_per_s: f64,
        muzzle_speed: f64,
        convergence_m: f64,
        lifetime_s: f64,
        damage: f64,
        hit_radius: f64,
        color: Color,
        look: i64,
        faction: StringName,
    ) -> i64 {
        if muzzles.is_empty() {
            godot_error!("ScsCannons.register: a cannon needs at least one muzzle; not registered");
            return -1;
        }
        let cannon = Cannon {
            body_id,
            muzzles: muzzles.as_slice().to_vec(),
            gate: Gate::new(
                muzzles.len(),
                interval_s,
                Some(Capacitor::new(capacity, cost_per_shot, recharge_per_s)),
            ),
            muzzle_speed,
            convergence_m,
            lifetime_s,
            damage,
            hit_radius,
            color: [color.r, color.g, color.b, color.a],
            look: u8::try_from(look).unwrap_or(crate::rows::LOOK_NONE),
            faction,
            trigger: false,
            weapon_next: false,
            live: true,
        };
        if let Some(free) = self.slots.iter().position(Option::is_none) {
            self.slots[free] = Some(cannon);
            free as i64
        } else {
            self.slots.push(Some(cannon));
            (self.slots.len() - 1) as i64
        }
    }

    /// Forgets a cannon; its slot may be reused.
    #[func]
    fn unregister(&mut self, slot: i64) {
        if let Some(entry) = usize::try_from(slot)
            .ok()
            .and_then(|i| self.slots.get_mut(i))
        {
            *entry = None;
        }
    }

    #[func]
    fn count(&self) -> i64 {
        self.slots.iter().filter(|s| s.is_some()).count() as i64
    }

    /// This tick's combat command as GDScript hands it: the held trigger and a mode cycle (taken once, at the step).
    #[func]
    fn set_trigger(&mut self, slot: i64, fire: bool, weapon_next: bool) {
        if let Some(c) = self.cannon_mut(slot) {
            c.trigger = fire;
            c.weapon_next = c.weapon_next || weapon_next;
        }
    }

    /// Whether the cannon's node processes; a parked ship's cannon neither fires nor recharges.
    #[func]
    fn set_live(&mut self, slot: i64, live: bool) {
        if let Some(c) = self.cannon_mut(slot) {
            c.live = live;
        }
    }

    #[func]
    fn set_faction(&mut self, slot: i64, faction: StringName) {
        if let Some(c) = self.cannon_mut(slot) {
            c.faction = faction;
        }
    }

    /// The fire mode: true for linked (every muzzle together), false for alternating.
    #[func]
    fn linked(&self, slot: i64) -> bool {
        self.cannon(slot).is_some_and(|c| c.gate.linked)
    }

    #[func]
    fn set_linked(&mut self, slot: i64, linked: bool) {
        if let Some(c) = self.cannon_mut(slot) {
            c.gate.linked = linked;
        }
    }

    /// Forgets the cooldown and the muzzle turn and refills the capacitor (a respawn).
    #[func]
    fn reset(&mut self, slot: i64) {
        if let Some(c) = self.cannon_mut(slot) {
            c.gate.reset();
            c.weapon_next = false;
        }
    }

    #[func]
    fn cooldown_remaining(&self, slot: i64, now_s: f64) -> f64 {
        self.cannon(slot)
            .map_or(0.0, |c| c.gate.cooldown_remaining(now_s))
    }

    /// The capacitor's charge 0..1 at `now_s`.
    #[func]
    fn charge_fraction(&self, slot: i64, now_s: f64) -> f64 {
        self.cannon(slot).map_or(1.0, |c| {
            c.gate
                .capacitor
                .as_ref()
                .map_or(1.0, |cap| cap.fraction_at(now_s))
        })
    }

    #[func]
    fn set_charge_fraction(&mut self, slot: i64, fraction: f64, now_s: f64) {
        if let Some(cap) = self
            .cannon_mut(slot)
            .and_then(|c| c.gate.capacitor.as_mut())
        {
            cap.set_fraction(fraction, now_s);
        }
    }

    /// The gate's state as `[ready_at_s, next_alternating, linked]`, and setting it (carrying a gate over from the
    /// GDScript gate when a cannon joins the kernel).
    #[func]
    fn gate_state(&self, slot: i64) -> PackedFloat64Array {
        match self.cannon(slot) {
            Some(c) => PackedFloat64Array::from(
                &[
                    c.gate.ready_at(),
                    c.gate.next_alternating() as f64,
                    f64::from(u8::from(c.gate.linked)),
                ][..],
            ),
            None => PackedFloat64Array::new(),
        }
    }

    #[func]
    fn set_gate_state(&mut self, slot: i64, ready_at_s: f64, next_alternating: i64, linked: bool) {
        if let Some(c) = self.cannon_mut(slot) {
            c.gate
                .set_ready_at(ready_at_s, usize::try_from(next_alternating).unwrap_or(0));
            c.gate.linked = linked;
        }
    }

    /// One tick of every live cannon at sim time `now_s`: the trigger from the ship's row command (or the one pushed),
    /// the gate, and a bolt row per firing muzzle from the ship's row. Returns `[shots, positions, fallback]`: the shots
    /// as `(slot, muzzle, bolt id)` triples in firing order with each shot's start, and the live slots whose ship has no
    /// row this tick (GDScript steps those with `step_one` from the node, or skips them).
    #[func]
    fn step(&mut self, mut core: Gd<ScsSimCore>, now_s: f64, _delta: f64) -> VarArray {
        self.shots.clear();
        self.shot_at.clear();
        self.fallback.clear();
        let mut c = core.bind_mut();
        self.tier_slots.clear();
        for slot in 0..self.slots.len() {
            let Some(cannon) = self.slots[slot].as_mut() else {
                continue;
            };
            let row = c.row_for_kernel(cannon.body_id);
            if let Some(r) = usize::try_from(row)
                .ok()
                .filter(|&r| c.rows.flags[r] & FLAG_TIER != 0)
            {
                self.tier_slots.push((slot, r)); // fired below: a tier shot makes no bolt, so the order of the rows holds
                continue;
            }
            if !cannon.live {
                continue;
            }
            let Ok(r) = usize::try_from(row) else {
                self.fallback.push(slot as i32);
                continue;
            };
            if c.rows.flags[r] & FLAG_RIGID == 0 {
                self.fallback.push(slot as i32);
                continue;
            }
            let basis = c.rows.bases[r];
            let position = c.rows.positions[r];
            let velocity = c.rows.velocities[r];
            Self::fire_from(
                cannon,
                slot,
                &mut c,
                &basis,
                position,
                velocity,
                now_s,
                &mut self.fired,
                &mut self.shots,
                &mut self.shot_at,
            );
        }
        // The ships in the low-attention tier (M4-T22): each parked cannon's gate fires, each shot a roll, no bolt.
        let started = std::time::Instant::now();
        for &(slot, r) in &self.tier_slots {
            if let Some(cannon) = self.slots[slot].as_mut() {
                Self::fire_in_tier(cannon, &mut c, r, now_s, &mut self.fired);
            }
        }
        self.tier_us = started.elapsed().as_nanos() as f64 / 1000.0;
        self.shots_total += self.shot_at.len() as i64;
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(self.shots.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(self.shot_at.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(self.fallback.as_slice()).to_variant());
        out
    }

    /// `step` for one cannon whose ship the core had no row for, with the pose and velocity GDScript read from the node.
    /// Returns `[shots, positions]`: its shots as `(slot, muzzle, bolt id)` triples and each shot's start.
    #[func]
    fn step_one(
        &mut self,
        mut core: Gd<ScsSimCore>,
        slot: i64,
        basis: Basis,
        position: Vector3,
        velocity: Vector3,
        now_s: f64,
    ) -> VarArray {
        let mut shots: Vec<i64> = Vec::new();
        let mut shot_at: Vec<Vector3> = Vec::new();
        if let Some(cannon) = usize::try_from(slot)
            .ok()
            .filter(|&i| i < self.slots.len())
            .and_then(|i| self.slots[i].as_mut())
        {
            let mut c = core.bind_mut();
            Self::fire_from(
                cannon,
                slot as usize,
                &mut c,
                &basis,
                position,
                velocity,
                now_s,
                &mut self.fired,
                &mut shots,
                &mut shot_at,
            );
            self.shots_total += shot_at.len() as i64;
        }
        let mut out = VarArray::new();
        out.push(&PackedInt64Array::from(shots.as_slice()).to_variant());
        out.push(&PackedVector3Array::from(shot_at.as_slice()).to_variant());
        out
    }

    /// The last step's pass over the tier ships' cannons, microseconds (wall clock; a readout, M4-T22).
    #[func]
    fn tier_us(&self) -> f64 {
        self.tier_us
    }

    /// Bolts fired by the kernel so far.
    #[func]
    fn shots_total(&self) -> i64 {
        self.shots_total
    }
}

impl ScsCannons {
    // The gate and the shots of one cannon from a pose, as `PulseCannon.step` and `_spawn` make them.
    #[allow(clippy::too_many_arguments)]
    fn fire_from(
        cannon: &mut Cannon,
        slot: usize,
        core: &mut ScsSimCore,
        basis: &Basis,
        position: Vector3,
        velocity: Vector3,
        now_s: f64,
        fired: &mut Vec<usize>,
        shots: &mut Vec<i64>,
        shot_at: &mut Vec<Vector3>,
    ) {
        if cannon.weapon_next {
            cannon.weapon_next = false;
            cannon.gate.cycle_mode();
        }
        let trigger = core
            .live_command(cannon.body_id)
            .map_or(cannon.trigger, |rc| rc.fire);
        cannon.gate.update(now_s, trigger, fired);
        if fired.is_empty() {
            return;
        }
        let faction_ix = core.faction_index(cannon.faction.clone());
        for &m in fired.iter() {
            let muzzle = bolt_kernels::muzzle_world(basis, position, cannon.muzzles[m]);
            let shot = bolt_kernels::shot_velocity(
                basis,
                position,
                velocity,
                muzzle,
                cannon.convergence_m,
                cannon.muzzle_speed,
            );
            let id = core.add_owned_bolt(
                muzzle,
                shot,
                faction_ix,
                cannon.body_id,
                KIND_BOLT,
                cannon.hit_radius,
                cannon.damage,
                cannon.color,
                cannon.look,
                now_s + cannon.lifetime_s,
            );
            shots.push(slot as i64);
            shots.push(m as i64);
            shots.push(id);
            shot_at.push(muzzle);
        }
    }

    // A tier ship's shots (M4-T22): the gate as on its body, each shot rolled against the target its pilot wants from the
    // shot's range and the pilot's skill; a hit is kept for GDScript to land through the target's `Damageable`.
    fn fire_in_tier(
        cannon: &mut Cannon,
        core: &mut ScsSimCore,
        r: usize,
        now_s: f64,
        fired: &mut Vec<usize>,
    ) {
        if core.rows.flags[r] & FLAG_HULK != 0 {
            return;
        }
        let command = core.live_command(cannon.body_id).copied();
        let rc = command.unwrap_or_default();
        let target = if rc.target > 0 {
            usize::try_from(core.rows.row_of_id(rc.target))
                .ok()
                .filter(|&j| {
                    core.rows.flags[j] & FLAG_HULL != 0 && core.rows.body_ids[j] != cannon.body_id
                })
        } else {
            None
        };
        let trigger = command.map_or(cannon.trigger, |rc| rc.fire);
        cannon.gate.update(now_s, trigger, fired);
        if fired.is_empty() {
            return;
        }
        let ordinal = core
            .tier
            .index_of(cannon.body_id)
            .map_or(0, |i| core.tier.ordinal[i]);
        for &m in fired.iter() {
            core.tier_shots_total += 1;
            let Some(j) = target else {
                continue;
            };
            let b = &core.rows.bases[r];
            let forward = Vector3::new(-b.rows[0].z, -b.rows[1].z, -b.rows[2].z);
            let excess = tier_fire::gate_excess_m(
                core.rows.positions[r],
                core.rows.velocities[r],
                forward,
                core.rows.positions[j],
                core.rows.velocities[j],
                cannon.muzzle_speed,
                rc.cone_rad,
                rc.miss_m,
            );
            let range = f64::from(crate::v3::distance(
                core.rows.positions[r],
                core.rows.positions[j],
            ));
            let chance = tier_fire::hit_chance(
                range,
                core.rows.radii[j],
                cannon.hit_radius,
                cannon.muzzle_speed,
                tier_fire::closing_speed(
                    core.rows.positions[r],
                    core.rows.velocities[r],
                    core.rows.positions[j],
                    core.rows.velocities[j],
                ),
                rc.aim_error_rad,
                rc.miss_m,
                cannon.muzzle_speed * cannon.lifetime_s,
                excess,
            );
            if tier_fire::roll(core.tier_seed, core.syncs(), ordinal, m as i64) < chance {
                core.tier_hits_total += 1;
                let (body, at) = (core.rows.body_ids[j], core.rows.positions[j]);
                core.tier_hits.push(body, cannon.body_id, cannon.damage, at);
            }
        }
    }

    fn cannon(&self, slot: i64) -> Option<&Cannon> {
        usize::try_from(slot)
            .ok()
            .and_then(|i| self.slots.get(i))
            .and_then(Option::as_ref)
    }

    fn cannon_mut(&mut self, slot: i64) -> Option<&mut Cannon> {
        usize::try_from(slot)
            .ok()
            .and_then(|i| self.slots.get_mut(i))
            .and_then(Option::as_mut)
    }
}
