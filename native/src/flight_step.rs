// The flight force step for every batched ship in one call (M4-T10, N4; docs/architecture.md 17.9).
// gdext's generated constructor writes `base: base`, which clippy 1.99 flags. The maths lives in kernels::flight; this class
// registers ships and applies what the kernel gives through the physics server.
#![allow(clippy::redundant_field_names)]
use godot::classes::PhysicsServer3D;
use godot::classes::physics_server_3d::BodyState;
use godot::prelude::*;

use std::sync::Mutex;

use crate::kernels::flight::{self, Applied, Body, Cmd, Spec};
use crate::rows::FLAG_RIGID;
use crate::sim_core::ScsSimCore;
use crate::threads::{self, Pass, Threads};
use crate::v3::{sub, xform_inv};

/// Per ship per tick: `main_right, main_left, retro_right, retro_left` (the nozzle groups' order).
pub const CMD_SCALARS: usize = 4;
/// Per ship per tick: strafe (x, y, 0), rot, track_dir_b, track_rate_b, face_dir_b, env_accel (world frame).
pub const CMD_VECTORS: usize = 6;
/// Per ship per tick: brake, autotrack, assist_on, has_propellant.
pub const CMD_FLAGS: usize = 4;
/// Per ship, when the caller supplies the state instead of the physics server: basis rows 0 to 2, linear velocity,
/// angular velocity (world frame).
pub const STATE_VECTORS: usize = 5;
/// Per ship out: applied force and torque (world), pod force, pod torque, RCS force, RCS torque, RCS force level, RCS
/// torque level, rate target (body), and the velocity after the hard ceiling (world).
pub const OUT_VECTORS: usize = 10;
/// Per ship out: the four group levels, trim, pod-yaw command, mass flow, face error, and the flags braking, facing,
/// tracking and propellant empty (0 or 1).
pub const OUT_SCALARS: usize = 12;
const SPEC_SCALARS: usize = 11;
const SPEC_VECTORS: usize = 4;

// One ship's registration: its body's RID, its type and nozzles (what the kernel reads) and the assist's only state.
struct Slot {
    rid: Rid,
    body: Body,
    pod_yaw_smoothed: f64,
    // Row flight (M5-T31): a ship whose native pilot commands it from the core's row flies with no GDScript gather; its
    // body, and the assist and propellant flags GDScript sets when they change.
    body_id: i64,
    row_mode: bool,
    assist_on: bool,
    has_propellant: bool,
}

// One ship of a step: read on the main thread, flown by the kernel on a worker, applied on the main thread (M4-T18).
#[derive(Default)]
struct Item {
    slot: usize,
    cmd: Option<Cmd>,
    env_w: Vector3,
    assist_on: bool,
    has_propellant: bool,
    basis: Basis,
    v_w: Vector3,
    w_w: Vector3,
    // Whether the ship flies at all (it has a pose) and whether its forces go to the physics server.
    fly: bool,
    apply: bool,
    pod_yaw: f64,
    forces: Vec<(Vector3, Vector3)>,
    applied: Option<Applied>,
}

// One ship's tick by the kernel: its slot's type, its item's command and pose; the result into the item.
fn fly(slot: &Slot, item: &mut Item, dt: f64) {
    if !item.fly {
        return;
    }
    let Some(cmd) = item.cmd.as_ref() else {
        return;
    };
    let mut pod_yaw = item.pod_yaw;
    item.applied = Some(flight::tick(
        &slot.body,
        &mut pod_yaw,
        cmd,
        &item.basis,
        item.v_w,
        item.w_w,
        item.env_w,
        item.assist_on,
        dt,
        item.has_propellant,
        &mut item.forces,
    ));
    item.pod_yaw = pod_yaw;
}

/// Flies every registered ship's tick in one call: `FlightModel.compute`, the `SpeedGovernor` and the forces
/// `Ship._physics_process` applies, by body RID through the physics server (`kernels::flight` is the maths, bit for bit
/// GDScript's). Never reads a GDScript object: ships' types and nozzles come in once (`register`), commands come in per
/// tick as packed arrays or, with the core, each ship's pose from its row, and the outputs go back the same way.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsFlightStep {
    base: Base<RefCounted>,
    slots: Vec<Option<Slot>>,
    out_vectors: Vec<Vector3>,
    out_scalars: Vec<f64>,
    // One entry per ship of a step, kept between ticks: its command, its pose and what the kernel gave (M4-T18).
    items: Vec<Item>,
    // The kernel needs no scratch of its own (each ship's nozzle forces go into its item), so the workers hold none.
    workers: Vec<Mutex<()>>,
    // One thread for a step with no core (the caller's states).
    serial: Threads,
    // Which slots the step lists, to find one listed twice.
    listed: Vec<bool>,
    // Ships the last `step_core` read from the physics server because the core had no row for them (M4-T15).
    fallback_reads: i64,
    // Ships the last step gave the frame's pull (M6-T07).
    pulled: i64,
    // The slot of each output row of the last step, and the output row of each slot (-1: not flown), M5-T31.
    out_slots: Vec<i32>,
    slot_rows: Vec<i32>,
    // Row-flown ships this step: their body ids, beside the gathered ones (scratch kept between ticks).
    row_bodies: Vec<i64>,
}

#[godot_api]
impl ScsFlightStep {
    /// The library's version, so a stale build is easy to spot.
    #[func]
    fn version() -> GString {
        GString::from(env!("CARGO_PKG_VERSION"))
    }

    /// Registers a ship and returns its slot, or -1 (after logging why) when the arrays do not line up. `rid` is the
    /// ship's body; an invalid RID makes a slot that only computes (the differential test's), never applies. `spec` holds
    /// mass, pod main and retro thrust, assist gain, pod-yaw gain, deadzone and smoothing, brake gain, exhaust velocity,
    /// the speed limit and the assist's safe speed; `spec_vectors` inertia, the RCS force and torque maxima and the rate
    /// maxima in rad/s. The nozzle arrays are the `ThrusterLayout`'s, `torque_axes` its four group torque axes.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn register(
        &mut self,
        rid: Rid,
        spec: PackedFloat64Array,
        spec_vectors: PackedVector3Array,
        nozzle_groups: PackedInt32Array,
        nozzle_positions: PackedVector3Array,
        nozzle_exhausts: PackedVector3Array,
        torque_axes: PackedVector3Array,
    ) -> i64 {
        let Some(body) = body_from_arrays(
            "ScsFlightStep.register",
            &spec,
            &spec_vectors,
            &nozzle_groups,
            &nozzle_positions,
            &nozzle_exhausts,
            &torque_axes,
        ) else {
            return -1;
        };
        let slot = Slot {
            rid,
            body,
            pod_yaw_smoothed: 0.0,
            body_id: 0,
            row_mode: false,
            assist_on: true,
            has_propellant: true,
        };
        if let Some(free) = self.slots.iter().position(Option::is_none) {
            self.slots[free] = Some(slot);
            free as i64
        } else {
            self.slots.push(Some(slot));
            (self.slots.len() - 1) as i64
        }
    }

    /// Forgets a ship; its slot number may be reused.
    #[func]
    fn unregister(&mut self, slot: i64) {
        if let Some(entry) = usize::try_from(slot)
            .ok()
            .and_then(|i| self.slots.get_mut(i))
        {
            *entry = None;
        }
    }

    /// Registered ships.
    #[func]
    fn count(&self) -> i64 {
        self.slots.iter().filter(|s| s.is_some()).count() as i64
    }

    /// The assist's smoothed pod-yaw command (`FlightAssist.pod_yaw_smoothed`) of a slot.
    #[func]
    fn assist_state(&self, slot: i64) -> f64 {
        self.slot(slot).map_or(0.0, |s| s.pod_yaw_smoothed)
    }

    /// Sets the smoothed pod-yaw command, so a ship that changes path carries its assist state over.
    #[func]
    fn set_assist_state(&mut self, slot: i64, value: f64) {
        if let Some(s) = self.slot_mut(slot) {
            s.pod_yaw_smoothed = value;
        }
    }

    /// Row flight (M5-T31): with `on`, the ship of `slot` (body `body_id`) flies its native pilot's row command with no
    /// gathered command whenever the core has that command and a row for the body; `assist_on` (the assist and not a
    /// hulk) and `has_propellant` stand in for the gathered flags until set again. Off, it is flown only when gathered.
    #[func]
    fn set_row_flight(&mut self, slot: i64, body_id: i64, on: bool, assist_on: bool, has_propellant: bool) {
        if let Some(s) = self.slot_mut(slot) {
            s.body_id = body_id;
            s.row_mode = on;
            s.assist_on = assist_on;
            s.has_propellant = has_propellant;
        }
    }

    /// The row-flight slots the core holds no command for (a flag that outlived its row): the batch gathers these as
    /// it gathers any ship, so no ship goes unflown.
    #[func]
    fn row_strays(&self, core: Gd<ScsSimCore>) -> PackedInt32Array {
        let c = core.bind();
        let mut out = PackedInt32Array::new();
        for (i, s) in self.slots.iter().enumerate() {
            if let Some(s) = s
                && s.row_mode
                && c.live_command(s.body_id).is_none()
                && c.row_of_id(s.body_id) >= 0
            {
                out.push(i as i32);
            }
        }
        out
    }

    /// The slot of each output row of the last step, in row order.
    #[func]
    fn out_slots(&self) -> PackedInt32Array {
        PackedInt32Array::from(self.out_slots.as_slice())
    }

    /// The output row of each slot in the last step (-1 for a slot it did not fly).
    #[func]
    fn slot_rows(&self) -> PackedInt32Array {
        PackedInt32Array::from(self.slot_rows.as_slice())
    }

    /// Clears the assist state, as `FlightModel.reset_assist` does on an assist toggle or a reset.
    #[func]
    fn reset_assist(&mut self, slot: i64) {
        self.set_assist_state(slot, 0.0);
    }

    /// One tick for the ships in `slots`: `CMD_SCALARS`, `CMD_VECTORS` and `CMD_FLAGS` entries per ship in the command
    /// arrays, `dt` the tick length. With `states` empty each ship's basis and velocities are read from its body, and
    /// the forces, torque and the hard speed ceiling are applied to it; with `STATE_VECTORS` entries per ship they are
    /// taken from there and nothing is applied (the test's path). Returns false, after logging why, when the arrays do
    /// not line up or a slot is unknown; nothing is applied then. Read `out_vectors` and `out_scalars` after.
    #[func]
    fn step(
        &mut self,
        slots: PackedInt32Array,
        scalars: PackedFloat64Array,
        vectors: PackedVector3Array,
        flags: PackedByteArray,
        states: PackedVector3Array,
        dt: f64,
    ) -> bool {
        self.fallback_reads = 0;
        self.pulled = 0;
        self.run(None, slots, scalars, vectors, flags, states, dt)
    }

    /// `step` with each ship's basis and velocities read from the core's rows (M4-T15): `body_ids` names the ships'
    /// bodies, one per slot; a ship the core has no row for (back from the pool this tick) is read from the physics
    /// server as `step` reads it, and counted in `fallback_reads`. The forces are applied as `step` applies them.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn step_core(
        &mut self,
        mut core: Gd<ScsSimCore>,
        slots: PackedInt32Array,
        body_ids: PackedInt64Array,
        scalars: PackedFloat64Array,
        vectors: PackedVector3Array,
        flags: PackedByteArray,
        dt: f64,
    ) -> bool {
        self.fallback_reads = 0;
        self.pulled = 0;
        if body_ids.len() != slots.len() {
            godot_error!(
                "ScsFlightStep.step_core: {} slots but {} body ids; nothing applied",
                slots.len(),
                body_ids.len()
            );
            self.out_vectors.clear();
            self.out_scalars.clear();
            return false;
        }
        let ok = self.run(
            Some((&core.bind(), body_ids.as_slice())),
            slots,
            scalars,
            vectors,
            flags,
            PackedVector3Array::new(),
            dt,
        );
        let mut c = core.bind_mut();
        if self.fallback_reads > 0 {
            c.note_fallback_read(self.fallback_reads);
        }
        c.ships_pulled = self.pulled;
        // Each flown ship's acceleration from its own forces, as `Ship.applied_force() / ship.mass` gives it (M4-T35: the
        // ram tracker's accel column, read natively). The gathered ships come first, then the row-flown ones.
        c.accels.clear();
        if ok {
            let gathered = body_ids.len();
            let total = gathered + self.row_bodies.len();
            for (i, item) in self.items[..total].iter().enumerate() {
                if let (Some(step), Some(slot)) =
                    (item.applied.as_ref(), self.slots[item.slot].as_ref())
                {
                    let mass = slot.body.spec.mass as f32;
                    let f = step.out_vectors[0];
                    let body = if i < gathered {
                        body_ids.as_slice()[i]
                    } else {
                        self.row_bodies[i - gathered]
                    };
                    c.accels.insert(body, Vector3::new(f.x / mass, f.y / mass, f.z / mass));
                }
            }
        }
        ok
    }

    /// Ships the last `step_core` had to read from the physics server.
    #[func]
    fn fallback_reads(&self) -> i64 {
        self.fallback_reads
    }

    /// The last step's vectors, `OUT_VECTORS` per ship in the order stepped.
    #[func]
    fn out_vectors(&self) -> PackedVector3Array {
        PackedVector3Array::from(self.out_vectors.as_slice())
    }

    /// The last step's scalars, `OUT_SCALARS` per ship in the order stepped.
    #[func]
    fn out_scalars(&self) -> PackedFloat64Array {
        PackedFloat64Array::from(self.out_scalars.as_slice())
    }
}

impl ScsFlightStep {
    // The step itself; with `core` each ship's state comes from its row when the core has one.
    #[allow(clippy::too_many_arguments)]
    fn run(
        &mut self,
        core: Option<(&ScsSimCore, &[i64])>,
        slots: PackedInt32Array,
        scalars: PackedFloat64Array,
        vectors: PackedVector3Array,
        flags: PackedByteArray,
        states: PackedVector3Array,
        dt: f64,
    ) -> bool {
        let n = slots.len();
        let lined_up = scalars.len() == n * CMD_SCALARS
            && vectors.len() == n * CMD_VECTORS
            && flags.len() == n * CMD_FLAGS
            && (states.is_empty() || states.len() == n * STATE_VECTORS)
            && slots
                .as_slice()
                .iter()
                .all(|&s| self.slot(i64::from(s)).is_some());
        if !lined_up {
            godot_error!(
                "ScsFlightStep.step: arrays do not line up or a slot is unknown ({n} ships, scalars {}, vectors {}, flags {}, \
                 states {}); nothing applied",
                scalars.len(),
                vectors.len(),
                flags.len(),
                states.len()
            );
            self.out_vectors.clear();
            self.out_scalars.clear();
            return false;
        }
        self.out_vectors.clear();
        self.out_scalars.clear();
        self.out_vectors.reserve(n * OUT_VECTORS);
        self.out_scalars.reserve(n * OUT_SCALARS);
        let sc = scalars.as_slice();
        let vc = vectors.as_slice();
        let fl = flags.as_slice();
        let st = states.as_slice();
        let mut server = PhysicsServer3D::singleton();
        if self.items.len() < n {
            self.items.resize_with(n, Item::default);
        }
        // On the main thread: each ship's command, and its pose and motion from the core's row, from the caller, or from
        // the physics server as `RigidBody3D` reads them.
        for (i, &slot_id) in slots.as_slice().iter().enumerate() {
            let item = &mut self.items[i];
            item.slot = slot_id as usize;
            item.cmd = Some(Cmd {
                levels: [sc[i * 4], sc[i * 4 + 1], sc[i * 4 + 2], sc[i * 4 + 3]],
                strafe: vc[i * CMD_VECTORS],
                rot: vc[i * CMD_VECTORS + 1],
                track_dir_b: vc[i * CMD_VECTORS + 2],
                track_rate_b: vc[i * CMD_VECTORS + 3],
                face_dir_b: vc[i * CMD_VECTORS + 4],
                brake: fl[i * CMD_FLAGS] != 0,
                autotrack: fl[i * CMD_FLAGS + 1] != 0,
            });
            // A native pilot's command comes from its row (M4-T33), not from the gathered arrays.
            if let Some(rc) = core.and_then(|(c, ids)| c.live_command(ids[i])) {
                rc.apply_to(item.cmd.as_mut().expect("set above"));
            }
            item.env_w = vc[i * CMD_VECTORS + 5];
            item.assist_on = fl[i * CMD_FLAGS + 2] != 0;
            item.has_propellant = fl[i * CMD_FLAGS + 3] != 0;
            item.applied = None;
            let slot = self.slots[item.slot].as_ref().expect("checked above");
            item.pod_yaw = slot.pod_yaw_smoothed;
            let row = core.and_then(|(c, ids)| {
                let r = c.row_for_kernel(ids[i]);
                usize::try_from(r)
                    .ok()
                    .filter(|&r| c.rows.flags[r] & FLAG_RIGID != 0)
            });
            item.fly = true;
            let mut position = None;
            if let (Some((c, _)), Some(r)) = (core, row) {
                item.basis = c.rows.bases[r];
                item.v_w = c.rows.velocities[r];
                item.w_w = c.rows.angular[r];
                item.apply = true;
                position = Some(c.rows.positions[r]);
            } else if st.is_empty() {
                if core.is_some() {
                    self.fallback_reads += 1;
                }
                let rid = slot.rid;
                match (rid.is_valid())
                    .then(|| server.body_get_direct_state(rid))
                    .flatten()
                {
                    Some(body) => {
                        let t = body.get_transform();
                        item.basis = t.basis;
                        item.v_w = body.get_linear_velocity();
                        item.w_w = body.get_angular_velocity();
                        item.apply = true;
                        position = Some(t.origin);
                    }
                    // Not in a space (parked or freed): nothing to fly; the row reads as zeros.
                    None => item.fly = false,
                }
            } else {
                item.basis = Basis {
                    rows: [
                        st[i * STATE_VECTORS],
                        st[i * STATE_VECTORS + 1],
                        st[i * STATE_VECTORS + 2],
                    ],
                };
                item.v_w = st[i * STATE_VECTORS + 3];
                item.w_w = st[i * STATE_VECTORS + 4];
                item.apply = false;
            }
            // The free-falling frame's residual (M6-T04, D66): the pull and the brake's feed-forward; GDScript packs zero.
            if let (Some((c, _)), Some(at)) = (core, position)
                && let Some(g) = c.frame_residual_at(at)
            {
                item.env_w += g;
                self.pulled += 1;
            }
        }
        // Row flight (M5-T31): every row-mode ship not gathered this tick, with a command in its row and a row in the core,
        // flies that command from the core's tables alone: its selected target's line of sight (only while it brakes) and
        // the frame's residual stand in for what the gather would have read.
        self.row_bodies.clear();
        let mut n = n;
        if let Some((c, _)) = core {
            self.listed.clear();
            self.listed.resize(self.slots.len(), false);
            for item in &self.items[..n] {
                self.listed[item.slot] = true;
            }
            for slot_ix in 0..self.slots.len() {
                let Some(slot) = self.slots[slot_ix].as_ref() else {
                    continue;
                };
                if !slot.row_mode || self.listed[slot_ix] {
                    continue;
                }
                let Some(rc) = c.live_command(slot.body_id) else {
                    continue;
                };
                if c.row_of_id(slot.body_id) < 0 {
                    continue; // not in play (parked): nothing to fly
                }
                if self.items.len() <= n {
                    self.items.resize_with(n + 1, Item::default);
                }
                let item = &mut self.items[n];
                item.slot = slot_ix;
                let mut cmd = Cmd {
                    levels: [0.0; flight::GROUPS],
                    strafe: Vector3::ZERO,
                    rot: Vector3::ZERO,
                    track_dir_b: Vector3::ZERO,
                    track_rate_b: Vector3::ZERO,
                    face_dir_b: Vector3::ZERO,
                    brake: false,
                    autotrack: false,
                };
                rc.apply_to(&mut cmd);
                item.assist_on = slot.assist_on;
                item.has_propellant = slot.has_propellant;
                item.applied = None;
                item.pod_yaw = slot.pod_yaw_smoothed;
                item.fly = true;
                let kernel_row = usize::try_from(c.row_for_kernel(slot.body_id))
                    .ok()
                    .filter(|&r| c.rows.flags[r] & FLAG_RIGID != 0);
                let position = if let Some(r) = kernel_row {
                    item.basis = c.rows.bases[r];
                    item.v_w = c.rows.velocities[r];
                    item.w_w = c.rows.angular[r];
                    item.apply = true;
                    Some(c.rows.positions[r])
                } else {
                    // Touched since the sync (teleported, shown): read from the physics server as the gathered path does.
                    self.fallback_reads += 1;
                    match (slot.rid.is_valid())
                        .then(|| server.body_get_direct_state(slot.rid))
                        .flatten()
                    {
                        Some(body) => {
                            let t = body.get_transform();
                            item.basis = t.basis;
                            item.v_w = body.get_linear_velocity();
                            item.w_w = body.get_angular_velocity();
                            item.apply = true;
                            Some(t.origin)
                        }
                        None => {
                            item.fly = false;
                            None
                        }
                    }
                };
                item.env_w = match position.and_then(|at| c.frame_residual_at(at)) {
                    Some(g) => {
                        self.pulled += 1;
                        g
                    }
                    None => Vector3::ZERO,
                };
                if cmd.brake
                    && let Some(at) = position
                {
                    cmd.face_dir_b = selected_offset(c, slot.body_id, at)
                        .map_or(Vector3::ZERO, |off| xform_inv(&item.basis, off));
                }
                item.cmd = Some(cmd);
                self.row_bodies.push(slot.body_id);
                n += 1;
            }
        }
        // The kernel, across the core's worker threads: each ship reads its own slot's type and writes only its item. A
        // slot listed twice flies its entries one after the other on this thread, each reading the assist state the one
        // before left, as the step always did.
        let threads = core.map_or(&self.serial, |(c, _)| c.worker_threads());
        threads::ensure_workers(&mut self.workers, threads);
        self.listed.clear();
        self.listed.resize(self.slots.len(), false);
        let mut repeated = false;
        for item in &self.items[..n] {
            repeated |= std::mem::replace(&mut self.listed[item.slot], true);
        }
        if repeated {
            for item in &mut self.items[..n] {
                if let Some(slot) = self.slots[item.slot].as_mut() {
                    item.pod_yaw = slot.pod_yaw_smoothed;
                    fly(slot, item, dt);
                    slot.pod_yaw_smoothed = item.pod_yaw;
                }
            }
        } else {
            let registered = &self.slots;
            threads.run(
                Pass::Flight,
                &mut self.items[..n],
                &self.workers,
                |item, _| {
                    if let Some(slot) = registered[item.slot].as_ref() {
                        fly(slot, item, dt);
                    }
                },
            );
        }
        // On the main thread, in row order: the assist state back, and the one engine write of the tick outside the sync
        // points, the forces, in `Ship._physics_process`'s order.
        self.out_slots.clear();
        self.slot_rows.clear();
        self.slot_rows.resize(self.slots.len(), -1);
        for (row, item) in self.items[..n].iter().enumerate() {
            self.out_slots.push(item.slot as i32);
            self.slot_rows[item.slot] = row as i32;
        }
        for item in &self.items[..n] {
            let Some(step) = item.applied.as_ref() else {
                self.out_vectors.extend([Vector3::ZERO; OUT_VECTORS]);
                self.out_scalars.extend([0.0; OUT_SCALARS]);
                continue;
            };
            let slot = self.slots[item.slot].as_mut().expect("checked above");
            slot.pod_yaw_smoothed = item.pod_yaw;
            if item.apply {
                for &(force_w, at_w) in &item.forces {
                    server
                        .body_apply_force_ex(slot.rid, force_w)
                        .position(at_w)
                        .done();
                }
                server.body_apply_central_force(slot.rid, step.rcs_w);
                server.body_apply_torque(slot.rid, step.torque_w);
                if let Some(cap) = step.cap {
                    server.body_apply_central_force(slot.rid, cap);
                }
                server.body_apply_central_force(slot.rid, step.env_force);
                if let Some(v_after) = step.clamped {
                    server.body_set_state(
                        slot.rid,
                        BodyState::LINEAR_VELOCITY,
                        &Variant::from(v_after),
                    );
                }
            }
            self.out_vectors.extend(step.out_vectors);
            self.out_scalars.extend(step.out_scalars);
        }
        true
    }

    fn slot(&self, slot: i64) -> Option<&Slot> {
        usize::try_from(slot)
            .ok()
            .and_then(|i| self.slots.get(i))
            .and_then(Option::as_ref)
    }

    fn slot_mut(&mut self, slot: i64) -> Option<&mut Slot> {
        usize::try_from(slot)
            .ok()
            .and_then(|i| self.slots.get_mut(i))
            .and_then(Option::as_mut)
    }
}

// The line of sight from `at` to the target body `body_id` has selected, world frame (`TargetingController.selected_offset`
// read from the core's rows: the selection column, then the target's row by marker id, tier rows included). None without a
// selection or a row for it.
fn selected_offset(c: &ScsSimCore, body_id: i64, at: Vector3) -> Option<Vector3> {
    let own = usize::try_from(c.row_of_id(body_id)).ok()?;
    let target = c.rows.target_ids[own];
    if target <= 0 {
        return None;
    }
    let row = usize::try_from(c.rows.row_of_id(target)).ok()?;
    Some(sub(c.rows.positions[row], at))
}

/// A ship type and its nozzles from the arrays `ScsFlightStep.register` takes (the tier registers its types the same way,
/// M4-T21): `spec` holds mass, pod main and retro thrust, assist gain, pod-yaw gain, deadzone and smoothing, brake gain,
/// exhaust velocity, the speed limit and the assist's safe speed; `spec_vectors` inertia, the RCS force and torque maxima
/// and the rate maxima; the nozzle arrays are the `ThrusterLayout`'s. None, after logging why as `who`, when they do not
/// line up.
pub(crate) fn body_from_arrays(
    who: &str,
    spec: &PackedFloat64Array,
    spec_vectors: &PackedVector3Array,
    nozzle_groups: &PackedInt32Array,
    nozzle_positions: &PackedVector3Array,
    nozzle_exhausts: &PackedVector3Array,
    torque_axes: &PackedVector3Array,
) -> Option<Body> {
    let n = nozzle_groups.len();
    let lined_up = spec.len() == SPEC_SCALARS
        && spec_vectors.len() == SPEC_VECTORS
        && nozzle_positions.len() == n
        && nozzle_exhausts.len() == n
        && torque_axes.len() == flight::GROUPS
        && nozzle_groups
            .as_slice()
            .iter()
            .all(|&g| (0..flight::GROUPS as i32).contains(&g));
    if !lined_up {
        godot_error!(
            "{who}: arrays do not line up (spec {}, spec vectors {}, nozzles {}, positions {}, exhausts {}, torque axes {}); \
             the ship is not registered",
            spec.len(),
            spec_vectors.len(),
            n,
            nozzle_positions.len(),
            nozzle_exhausts.len(),
            torque_axes.len()
        );
        return None;
    }
    let s = spec.as_slice();
    let v = spec_vectors.as_slice();
    let spec = Spec {
        mass: s[0],
        pod_main_thrust: s[1],
        pod_retro_thrust: s[2],
        assist_gain_k: s[3],
        pod_yaw_gain: s[4],
        pod_yaw_deadzone: s[5],
        pod_yaw_smoothing_s: s[6],
        brake_gain_k: s[7],
        exhaust_velocity: s[8],
        speed_limit_mps: s[9],
        assist_speed_max_mps: s[10],
        inertia: v[0],
        rcs_force_max: v[1],
        rcs_torque_max: v[2],
        rate_max_rad: v[3],
    };
    let groups: Vec<usize> = nozzle_groups
        .as_slice()
        .iter()
        .map(|&g| g as usize)
        .collect();
    let mut counts = [0i64; flight::GROUPS];
    for &g in &groups {
        counts[g] += 1;
    }
    let axes = torque_axes.as_slice();
    Some(Body {
        main_total: spec.pod_main_thrust * (counts[0] + counts[1]) as f64,
        retro_total: spec.pod_retro_thrust * (counts[2] + counts[3]) as f64,
        spec,
        nozzle_groups: groups,
        nozzle_positions: nozzle_positions.as_slice().to_vec(),
        nozzle_exhausts: nozzle_exhausts.as_slice().to_vec(),
        torque_axes: [axes[0], axes[1], axes[2], axes[3]],
    })
}
