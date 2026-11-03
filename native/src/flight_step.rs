// The flight force step for every batched ship in one call (M4-T10, N4; docs/architecture.md 17.9).
use godot::classes::physics_server_3d::BodyState;
use godot::classes::PhysicsServer3D;
use godot::prelude::*;

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
const GROUPS: usize = 4;
// Pilot axes (pitch up, yaw right, roll right) to body axes, as `FlightModel.AXIS_SIGN`.
const AXIS_SIGN: Vector3 = Vector3::new(1.0, -1.0, -1.0);
// `FlightAssist.FACE_DECEL_FRACTION`.
const FACE_DECEL_FRACTION: f64 = 0.5;
// Godot's `CMP_EPSILON` as `is_zero_approx` applies it to 32-bit components.
const CMP_EPSILON: f32 = 0.00001;

// A ship type as `ShipSpec` holds it, in the units the flight model reads.
#[derive(Clone)]
struct Spec {
    mass: f64,
    pod_main_thrust: f64,
    pod_retro_thrust: f64,
    assist_gain_k: f64,
    pod_yaw_gain: f64,
    pod_yaw_deadzone: f64,
    pod_yaw_smoothing_s: f64,
    brake_gain_k: f64,
    exhaust_velocity: f64,
    speed_limit_mps: f64,
    assist_speed_max_mps: f64,
    inertia: Vector3,
    rcs_force_max: Vector3,
    rcs_torque_max: Vector3,
    rate_max_rad: Vector3,
}

// One ship's registration: its body, type, nozzles and the assist's only state.
struct Slot {
    rid: Rid,
    spec: Spec,
    nozzle_groups: Vec<usize>,
    nozzle_positions: Vec<Vector3>,
    nozzle_exhausts: Vec<Vector3>,
    torque_axes: [Vector3; GROUPS],
    main_total: f64,
    retro_total: f64,
    pod_yaw_smoothed: f64,
}

// One tick's command for one ship, in pilot terms as `FlightCommand` carries them.
struct Cmd {
    levels: [f64; GROUPS],
    strafe: Vector3,
    rot: Vector3,
    track_dir_b: Vector3,
    track_rate_b: Vector3,
    face_dir_b: Vector3,
    brake: bool,
    autotrack: bool,
}

// What `FlightModel.compute` reports, the parts the batch hands back.
struct ModelOut {
    levels: [f64; GROUPS],
    pod_force: Vector3,
    tau_pods: Vector3,
    rcs_force: Vector3,
    tau_rcs: Vector3,
    rate_target: Vector3,
    trim: f64,
    pod_yaw_cmd: f64,
    mass_flow: f64,
    face_error: f64,
    braking: bool,
    facing: bool,
    tracking: bool,
}

/// Flies every registered ship's tick in one call: `FlightModel.compute`, the `SpeedGovernor` and the forces
/// `Ship._physics_process` applies, by body RID through the physics server. The maths repeats GDScript's: 32-bit
/// vectors, 64-bit scalars, a scalar rounded to 32 bits before it scales a vector, the engine's order of operations and
/// no fused multiply-add, so both paths give the same forces bit for bit. Never reads a GDScript object: ships' types
/// and nozzles come in once (`register`), commands come in per tick as packed arrays, and the outputs go back the same way.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ScsFlightStep {
    base: Base<RefCounted>,
    slots: Vec<Option<Slot>>,
    out_vectors: Vec<Vector3>,
    out_scalars: Vec<f64>,
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
        let n = nozzle_groups.len();
        let lined_up = spec.len() == SPEC_SCALARS
            && spec_vectors.len() == SPEC_VECTORS
            && nozzle_positions.len() == n
            && nozzle_exhausts.len() == n
            && torque_axes.len() == GROUPS
            && nozzle_groups.as_slice().iter().all(|&g| (0..GROUPS as i32).contains(&g));
        if !lined_up {
            godot_error!(
                "ScsFlightStep.register: arrays do not line up (spec {}, spec vectors {}, nozzles {}, positions {}, exhausts {}, \
                 torque axes {}); the ship is not registered",
                spec.len(),
                spec_vectors.len(),
                n,
                nozzle_positions.len(),
                nozzle_exhausts.len(),
                torque_axes.len()
            );
            return -1;
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
        let groups: Vec<usize> = nozzle_groups.as_slice().iter().map(|&g| g as usize).collect();
        let mut counts = [0i64; GROUPS];
        for &g in &groups {
            counts[g] += 1;
        }
        let axes = torque_axes.as_slice();
        let slot = Slot {
            rid,
            main_total: spec.pod_main_thrust * (counts[0] + counts[1]) as f64,
            retro_total: spec.pod_retro_thrust * (counts[2] + counts[3]) as f64,
            spec,
            nozzle_groups: groups,
            nozzle_positions: nozzle_positions.as_slice().to_vec(),
            nozzle_exhausts: nozzle_exhausts.as_slice().to_vec(),
            torque_axes: [axes[0], axes[1], axes[2], axes[3]],
            pod_yaw_smoothed: 0.0,
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
        if let Some(entry) = usize::try_from(slot).ok().and_then(|i| self.slots.get_mut(i)) {
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
        let n = slots.len();
        let lined_up = scalars.len() == n * CMD_SCALARS
            && vectors.len() == n * CMD_VECTORS
            && flags.len() == n * CMD_FLAGS
            && (states.is_empty() || states.len() == n * STATE_VECTORS)
            && slots.as_slice().iter().all(|&s| self.slot(i64::from(s)).is_some());
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
        for (i, &slot_id) in slots.as_slice().iter().enumerate() {
            let cmd = Cmd {
                levels: [sc[i * 4], sc[i * 4 + 1], sc[i * 4 + 2], sc[i * 4 + 3]],
                strafe: vc[i * CMD_VECTORS],
                rot: vc[i * CMD_VECTORS + 1],
                track_dir_b: vc[i * CMD_VECTORS + 2],
                track_rate_b: vc[i * CMD_VECTORS + 3],
                face_dir_b: vc[i * CMD_VECTORS + 4],
                brake: fl[i * CMD_FLAGS] != 0,
                autotrack: fl[i * CMD_FLAGS + 1] != 0,
            };
            let env_w = vc[i * CMD_VECTORS + 5];
            let assist_on = fl[i * CMD_FLAGS + 2] != 0;
            let has_propellant = fl[i * CMD_FLAGS + 3] != 0;
            let slot = self.slots[slot_id as usize].as_mut().expect("checked above");
            // The body's pose and motion: from the caller, or from the physics server as `RigidBody3D` reads them.
            let (basis, v_w, w_w, apply) = if st.is_empty() {
                let rid = slot.rid;
                let Some(body) = (rid.is_valid()).then(|| server.body_get_direct_state(rid)).flatten() else {
                    // Not in a space (parked or freed): nothing to fly; the row reads as zeros.
                    self.out_vectors.extend([Vector3::ZERO; OUT_VECTORS]);
                    self.out_scalars.extend([0.0; OUT_SCALARS]);
                    continue;
                };
                (body.get_transform().basis, body.get_linear_velocity(), body.get_angular_velocity(), true)
            } else {
                let b = Basis { rows: [st[i * STATE_VECTORS], st[i * STATE_VECTORS + 1], st[i * STATE_VECTORS + 2]] };
                (b, st[i * STATE_VECTORS + 3], st[i * STATE_VECTORS + 4], false)
            };
            let v_b = xform_inv(&basis, v_w);
            let w_b = xform_inv(&basis, w_w);
            let env_b = xform_inv(&basis, env_w);
            let out = compute(slot, &cmd, v_b, w_b, env_b, assist_on, dt, has_propellant);
            let spec = &slot.spec;
            // The ship's part: the governor's gain on every thrust, the forces at the nozzles, the assist's speed cap and the
            // environment, then the hard ceiling (`Ship._physics_process`).
            let mass_f = spec.mass as f32;
            let mut applied = scale(env_w, mass_f);
            let gain = thrust_gain(f64::from(length(v_w)), spec.speed_limit_mps) as f32;
            for k in 0..slot.nozzle_groups.len() {
                let level = out.levels[slot.nozzle_groups[k]];
                let magnitude = level * group_thrust(spec, slot.nozzle_groups[k]);
                let force_b = scale(neg(slot.nozzle_exhausts[k]), magnitude as f32);
                let force_w = scale(xform(&basis, force_b), gain);
                let at_w = xform(&basis, slot.nozzle_positions[k]);
                if apply {
                    server.body_apply_force_ex(slot.rid, force_w).position(at_w).done();
                }
                applied = add(applied, force_w);
            }
            let rcs_w = scale(xform(&basis, out.rcs_force), gain);
            if apply {
                server.body_apply_central_force(slot.rid, rcs_w);
            }
            applied = add(applied, rcs_w);
            let torque_w = xform(&basis, out.tau_rcs);
            if apply {
                server.body_apply_torque(slot.rid, torque_w);
            }
            if assist_on {
                let net = scale(xform(&basis, add(out.pod_force, out.rcs_force)), gain);
                let cap = assist_cap_correction(net, v_w, spec.assist_speed_max_mps);
                if apply {
                    server.body_apply_central_force(slot.rid, cap);
                }
                applied = add(applied, cap);
            }
            if apply {
                server.body_apply_central_force(slot.rid, scale(env_w, mass_f));
            }
            let mut v_after = v_w;
            if spec.speed_limit_mps > 0.0 && f64::from(length(v_w)) > spec.speed_limit_mps {
                v_after = scale(normalized(v_w), spec.speed_limit_mps as f32);
                if apply {
                    server.body_set_state(slot.rid, BodyState::LINEAR_VELOCITY, &Variant::from(v_after));
                }
            }
            self.out_vectors.extend([
                applied,
                torque_w,
                out.pod_force,
                out.tau_pods,
                out.rcs_force,
                out.tau_rcs,
                level_of(out.rcs_force, spec.rcs_force_max),
                level_of(out.tau_rcs, spec.rcs_torque_max),
                out.rate_target,
                v_after,
            ]);
            self.out_scalars.extend([
                out.levels[0],
                out.levels[1],
                out.levels[2],
                out.levels[3],
                out.trim,
                out.pod_yaw_cmd,
                out.mass_flow,
                out.face_error,
                f64::from(u8::from(out.braking)),
                f64::from(u8::from(out.facing)),
                f64::from(u8::from(out.tracking)),
                f64::from(u8::from(!has_propellant)),
            ]);
        }
        true
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
    fn slot(&self, slot: i64) -> Option<&Slot> {
        usize::try_from(slot).ok().and_then(|i| self.slots.get(i)).and_then(Option::as_ref)
    }

    fn slot_mut(&mut self, slot: i64) -> Option<&mut Slot> {
        usize::try_from(slot).ok().and_then(|i| self.slots.get_mut(i)).and_then(Option::as_mut)
    }
}

// `FlightModel.compute`: one tick of architecture 5.2, body frame.
#[allow(clippy::too_many_arguments)]
fn compute(slot: &mut Slot, cmd: &Cmd, v_b: Vector3, w_b: Vector3, env_b: Vector3, assist_on: bool, dt: f64, has_propellant: bool) -> ModelOut {
    let spec = slot.spec.clone();
    // 1. Pilot demand per nozzle group and RCS translation.
    let mut levels = cmd.levels;
    let mut rcs_force = Vector3::new(
        (f64::from(cmd.strafe.x) * f64::from(spec.rcs_force_max.x)) as f32,
        (f64::from(cmd.strafe.y) * f64::from(spec.rcs_force_max.y)) as f32,
        0.0,
    );
    // 2. Brake overrides all translational demand: symmetric sides, so zero pod torque.
    if cmd.brake {
        let a_des = sub(scale(v_b, (-spec.brake_gain_k) as f32), env_b);
        let f_z = clampf(spec.mass * f64::from(a_des.z), -slot.main_total, slot.retro_total);
        let main_level = if f_z < 0.0 && slot.main_total > 0.0 { -f_z / slot.main_total } else { 0.0 };
        let retro_level = if f_z > 0.0 && slot.retro_total > 0.0 { f_z / slot.retro_total } else { 0.0 };
        levels = [main_level, main_level, retro_level, retro_level];
        rcs_force = clamp_cw(
            scale(Vector3::new(a_des.x, a_des.y, 0.0), spec.mass as f32),
            neg(spec.rcs_force_max),
            spec.rcs_force_max,
        );
    }
    // 2b. No reaction mass: nothing that burns it can fire.
    if !has_propellant {
        levels = [0.0; GROUPS];
        rcs_force = Vector3::ZERO;
    }
    // 3. Pod torque about the centre of mass at the demanded levels.
    let mut group_torque_y = [0.0f64; GROUPS];
    let mut tau_pods = pod_torque(slot, &levels, &mut group_torque_y);
    // 4. Rotation.
    let tracking = cmd.autotrack && !cmd.brake && !is_zero_approx(cmd.track_dir_b);
    let mut lam = 1.0;
    let mut rate_target = Vector3::ZERO;
    let mut facing = false;
    let mut face_error = 0.0;
    let mut pod_yaw_cmd = 0.0;
    if assist_on {
        update_pod_yaw(slot, cmd, dt);
    }
    let tau_rcs;
    if cmd.brake {
        // 4c. All stop, or the nose onto `face_dir_b`; RCS supplies the whole rate-controller torque.
        let w_face = face_rate_target(&spec, cmd.face_dir_b);
        tau_rcs = clamp_cw(sub(rate_torque(&spec, w_face, w_b), tau_pods), neg(spec.rcs_torque_max), spec.rcs_torque_max);
        rate_target = w_face;
        facing = !is_zero_approx(cmd.face_dir_b);
        face_error = f64::from(length(face_error_vector(cmd.face_dir_b)));
    } else if assist_on || tracking {
        let mut w_target;
        if tracking {
            w_target = track_rate_target(&spec, cmd.track_dir_b, cmd.track_rate_b);
            w_target.z = (f64::from(cmd.rot.z) * f64::from(AXIS_SIGN.z) * f64::from(spec.rate_max_rad.z)) as f32;
            facing = true;
            face_error = f64::from(length(face_error_vector(cmd.track_dir_b)));
        } else {
            let rot = Vector3::new(
                cmd.rot.x,
                clampf(f64::from(cmd.rot.y) + pod_yaw_command(&spec, slot.pod_yaw_smoothed), -1.0, 1.0) as f32,
                cmd.rot.z,
            );
            w_target = mul_cw(mul_cw(rot, AXIS_SIGN), spec.rate_max_rad);
        }
        // 4b. Rate controller with the pods' torque as feed-forward; the groups fighting an RCS overflow are trimmed.
        let tau_des = rate_torque(&spec, w_target, w_b);
        let mut residual = sub(tau_des, tau_pods);
        let overflow = sub(residual, clamp_cw(residual, neg(spec.rcs_torque_max), spec.rcs_torque_max));
        if overflow.y != 0.0 {
            let overflow_y = f64::from(overflow.y);
            lam = yaw_trim_factor(overflow_y, &group_torque_y);
            if lam < 1.0 {
                for g in 0..GROUPS {
                    if is_trim_cause(group_torque_y[g], overflow_y) {
                        levels[g] *= lam;
                    }
                }
                tau_pods = pod_torque(slot, &levels, &mut group_torque_y);
                residual = sub(tau_des, tau_pods);
            }
        }
        tau_rcs = clamp_cw(residual, neg(spec.rcs_torque_max), spec.rcs_torque_max);
        rate_target = w_target;
        if assist_on {
            pod_yaw_cmd = pod_yaw_command(&spec, slot.pod_yaw_smoothed);
        }
    } else {
        // Raw: the stick commands RCS torque directly.
        tau_rcs = mul_cw(mul_cw(cmd.rot, AXIS_SIGN), spec.rcs_torque_max);
    }
    // 5. Outputs.
    let mut pod_force = Vector3::ZERO;
    let mut thrust_sum = 0.0;
    for k in 0..slot.nozzle_groups.len() {
        let g = slot.nozzle_groups[k];
        let magnitude = levels[g] * group_thrust(&spec, g);
        pod_force = add(pod_force, scale(neg(slot.nozzle_exhausts[k]), magnitude as f32));
        thrust_sum += magnitude.abs();
    }
    let mass_flow = if spec.exhaust_velocity > 0.0 {
        (thrust_sum + f64::from(length(rcs_force))) / spec.exhaust_velocity
    } else {
        0.0
    };
    ModelOut {
        levels,
        pod_force,
        tau_pods,
        rcs_force,
        tau_rcs,
        rate_target,
        trim: 1.0 - lam,
        pod_yaw_cmd,
        mass_flow,
        face_error,
        braking: cmd.brake,
        facing,
        tracking,
    }
}

fn group_thrust(spec: &Spec, group: usize) -> f64 {
    if group < 2 { spec.pod_main_thrust } else { spec.pod_retro_thrust }
}

// `FlightModel._pod_torque`: the groups' torque about the centre of mass, and each group's yaw part for the trim.
fn pod_torque(slot: &Slot, levels: &[f64; GROUPS], group_torque_y: &mut [f64; GROUPS]) -> Vector3 {
    let mut total = Vector3::ZERO;
    for g in 0..GROUPS {
        let tau_g = scale(slot.torque_axes[g], (levels[g] * group_thrust(&slot.spec, g)) as f32);
        group_torque_y[g] = f64::from(tau_g.y);
        total = add(total, tau_g);
    }
    total
}

// `FlightAssist.update_pod_yaw`: the smoothed pod-yaw command, one tick on.
fn update_pod_yaw(slot: &mut Slot, cmd: &Cmd, dt: f64) {
    let raw = if cmd.brake { 0.0 } else { (cmd.levels[1] - cmd.levels[0]) + (cmd.levels[2] - cmd.levels[3]) };
    let deadzone = clampf(slot.spec.pod_yaw_deadzone, 0.0, 0.999);
    let shaped = signf(raw) * maxf(0.0, raw.abs() - deadzone) / (1.0 - deadzone);
    let target = clampf(shaped, -1.0, 1.0);
    let tau = slot.spec.pod_yaw_smoothing_s;
    let mut alpha = 1.0;
    if tau > 0.0 && dt > 0.0 {
        alpha = 1.0 - (-dt / tau).exp();
    } else if dt <= 0.0 {
        alpha = 0.0;
    }
    slot.pod_yaw_smoothed += (target - slot.pod_yaw_smoothed) * alpha;
}

fn pod_yaw_command(spec: &Spec, smoothed: f64) -> f64 {
    spec.pod_yaw_gain * smoothed
}

// `FlightAssist.rate_torque`: the P rate controller's torque.
fn rate_torque(spec: &Spec, w_target: Vector3, w_b: Vector3) -> Vector3 {
    mul_cw(spec.inertia, scale(sub(w_target, w_b), spec.assist_gain_k as f32))
}

fn turn_accel_max(spec: &Spec) -> f64 {
    let pitch = if spec.inertia.x > 0.0 { f64::from(spec.rcs_torque_max.x) / f64::from(spec.inertia.x) } else { 0.0 };
    let yaw = if spec.inertia.y > 0.0 { f64::from(spec.rcs_torque_max.y) / f64::from(spec.inertia.y) } else { 0.0 };
    maxf(0.0, minf(pitch, yaw))
}

// `FlightAssist.face_rate_target`: the rate that swings the nose onto `dir_b`, stoppable within RCS authority.
fn face_rate_target(spec: &Spec, dir_b: Vector3) -> Vector3 {
    let error = face_error_vector(dir_b);
    let angle = f64::from(length(error));
    if angle == 0.0 {
        return Vector3::ZERO;
    }
    let decel = FACE_DECEL_FRACTION * turn_accel_max(spec);
    let rate = minf(spec.assist_gain_k / 4.0 * angle, (2.0 * decel * angle).sqrt());
    let w = scale(div_s(error, angle as f32), rate as f32);
    let cap = spec.rate_max_rad;
    let mut s = 1.0;
    if f64::from(w.x.abs()) > f64::from(cap.x) {
        s = minf(s, f64::from(cap.x) / f64::from(w.x.abs()));
    }
    if f64::from(w.y.abs()) > f64::from(cap.y) {
        s = minf(s, f64::from(cap.y) / f64::from(w.y.abs()));
    }
    scale(w, s as f32)
}

// `FlightAssist.track_rate_target`: the face correction plus the rate the lead direction itself turns at.
fn track_rate_target(spec: &Spec, dir_b: Vector3, dir_rate_b: Vector3) -> Vector3 {
    let mut w = face_rate_target(spec, dir_b);
    w.x = (f64::from(w.x) + f64::from(dir_rate_b.x)) as f32;
    w.y = (f64::from(w.y) + f64::from(dir_rate_b.y)) as f32;
    let cap = spec.rate_max_rad;
    w.x = clampf(f64::from(w.x), -f64::from(cap.x), f64::from(cap.x)) as f32;
    w.y = clampf(f64::from(w.y), -f64::from(cap.y), f64::from(cap.y)) as f32;
    w
}

// `FlightAssist.face_error_vector`: the shortest rotation that puts the nose on `dir_b`; pitch and yaw only.
fn face_error_vector(dir_b: Vector3) -> Vector3 {
    if is_zero_approx(dir_b) {
        return Vector3::ZERO;
    }
    let d = normalized(dir_b);
    let axis = Vector3::new(d.y, -d.x, 0.0);
    let sine = f64::from(length(axis));
    let angle = sine.atan2(f64::from(-d.z));
    if angle == 0.0 {
        return Vector3::ZERO;
    }
    if sine < 1e-9 {
        return Vector3::new(angle as f32, 0.0, 0.0);
    }
    scale(axis, (angle / sine) as f32)
}

// `FlightAssist.yaw_trim_factor`: how far the groups causing an RCS overflow are scaled down.
fn yaw_trim_factor(overflow_y: f64, group_torque_y: &[f64; GROUPS]) -> f64 {
    if overflow_y == 0.0 {
        return 1.0;
    }
    let mut cause_total = 0.0;
    for &t in group_torque_y {
        if is_trim_cause(t, overflow_y) {
            cause_total += t.abs();
        }
    }
    if cause_total <= 0.0 {
        return 1.0;
    }
    maxf(0.0, 1.0 - overflow_y.abs() / cause_total)
}

fn is_trim_cause(torque_y: f64, overflow_y: f64) -> bool {
    overflow_y != 0.0 && torque_y != 0.0 && signf(torque_y) == -signf(overflow_y)
}

// `SpeedGovernor.thrust_gain`: the share of the thrust that reaches the hull at this speed.
fn thrust_gain(speed: f64, limit: f64) -> f64 {
    if limit <= 0.0 {
        return 1.0;
    }
    let ratio = clampf(speed / limit, 0.0, 1.0);
    (1.0 - ratio * ratio).sqrt()
}

// `SpeedGovernor.assist_cap_correction`: cancels the part of the force that would speed the ship past the cap.
fn assist_cap_correction(force: Vector3, velocity: Vector3, cap: f64) -> Vector3 {
    if cap <= 0.0 {
        return Vector3::ZERO;
    }
    let speed = f64::from(length(velocity));
    if speed < cap {
        return Vector3::ZERO;
    }
    let heading = div_s(velocity, speed as f32);
    let along = f64::from(dot(force, heading));
    if along <= 0.0 {
        return Vector3::ZERO;
    }
    scale(neg(heading), along as f32)
}

// `FlightModel._level_of`: a vector as a share of its per-axis limit.
fn level_of(value: Vector3, limit: Vector3) -> Vector3 {
    let part = |v: f32, l: f32| if l > 0.0 { (f64::from(v) / f64::from(l)) as f32 } else { 0.0 };
    Vector3::new(part(value.x, limit.x), part(value.y, limit.y), part(value.z, limit.z))
}

// --- Godot's 32-bit vector arithmetic, op for op (gdext's own operators go through glam, so none are used) ---------

fn add(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x + b.x, a.y + b.y, a.z + b.z)
}

fn sub(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x - b.x, a.y - b.y, a.z - b.z)
}

fn neg(a: Vector3) -> Vector3 {
    Vector3::new(-a.x, -a.y, -a.z)
}

fn mul_cw(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x * b.x, a.y * b.y, a.z * b.z)
}

fn scale(a: Vector3, s: f32) -> Vector3 {
    Vector3::new(a.x * s, a.y * s, a.z * s)
}

fn div_s(a: Vector3, s: f32) -> Vector3 {
    Vector3::new(a.x / s, a.y / s, a.z / s)
}

fn dot(a: Vector3, b: Vector3) -> f32 {
    a.x * b.x + a.y * b.y + a.z * b.z
}

fn length(a: Vector3) -> f32 {
    let x2 = a.x * a.x;
    let y2 = a.y * a.y;
    let z2 = a.z * a.z;
    (x2 + y2 + z2).sqrt()
}

fn normalized(a: Vector3) -> Vector3 {
    let x2 = a.x * a.x;
    let y2 = a.y * a.y;
    let z2 = a.z * a.z;
    let length_sq = x2 + y2 + z2;
    if length_sq == 0.0 {
        return Vector3::ZERO;
    }
    let l = length_sq.sqrt();
    Vector3::new(a.x / l, a.y / l, a.z / l)
}

fn clamp_cw(a: Vector3, lo: Vector3, hi: Vector3) -> Vector3 {
    let c = |v: f32, lo: f32, hi: f32| if v < lo { lo } else if v > hi { hi } else { v };
    Vector3::new(c(a.x, lo.x, hi.x), c(a.y, lo.y, hi.y), c(a.z, lo.z, hi.z))
}

fn is_zero_approx(a: Vector3) -> bool {
    a.x.abs() < CMP_EPSILON && a.y.abs() < CMP_EPSILON && a.z.abs() < CMP_EPSILON
}

// `Basis * Vector3`: each row dotted with the vector.
fn xform(b: &Basis, v: Vector3) -> Vector3 {
    Vector3::new(dot(b.rows[0], v), dot(b.rows[1], v), dot(b.rows[2], v))
}

// `Basis.transposed() * Vector3`: each column dotted with the vector.
fn xform_inv(b: &Basis, v: Vector3) -> Vector3 {
    let col_x = Vector3::new(b.rows[0].x, b.rows[1].x, b.rows[2].x);
    let col_y = Vector3::new(b.rows[0].y, b.rows[1].y, b.rows[2].y);
    let col_z = Vector3::new(b.rows[0].z, b.rows[1].z, b.rows[2].z);
    Vector3::new(dot(col_x, v), dot(col_y, v), dot(col_z, v))
}

// --- Godot's 64-bit scalar helpers (`clampf`, `minf`, `maxf`, `signf`) with their exact comparisons ------------------

fn clampf(v: f64, lo: f64, hi: f64) -> f64 {
    if v < lo {
        lo
    } else if v > hi {
        hi
    } else {
        v
    }
}

fn minf(a: f64, b: f64) -> f64 {
    if a < b { a } else { b }
}

fn maxf(a: f64, b: f64) -> f64 {
    if a > b { a } else { b }
}

fn signf(v: f64) -> f64 {
    if v > 0.0 {
        1.0
    } else if v < 0.0 {
        -1.0
    } else {
        0.0
    }
}
