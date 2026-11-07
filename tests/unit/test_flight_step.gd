extends GutTest
## The flight force step in native code (M4-T10, N4; architecture §17.9): `ScsFlightStep` must give, for the same command
## and state, the forces, torques, levels and assist state that `FlightModel.compute`, `SpeedGovernor` and the force
## application in `Ship._physics_process` give. Differential, with no scene: 10 000 seeded commands and states per ship type
## through both paths, bit for bit (the native maths repeats GDScript's 32-bit vectors and 64-bit scalars); any field that
## cannot be bit-identical is listed here with its tolerance.

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const STARFURY_FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const RAIDER_FIXTURE: String = "res://tests/fixtures/hardpoints_raider_nominal.json"
const SAMPLES: int = 10000
const DT: float = 1.0 / 60.0
## Fields whose native value may differ from GDScript's within this relative tolerance (none expected: every field is
## compared bit for bit, and a field is only listed here, with the reason, once a run shows the maths cannot match).
const TOLERATED: Dictionary = {}
const REL_TOL: float = 1e-6


# A fresh native step, or null (asserting) when the library lacks the class.
func _step() -> Object:
	var step: Object = NativeLib.instantiate(FlightBatch.NATIVE_CLASS)
	assert_not_null(step, "the native library provides %s" % FlightBatch.NATIVE_CLASS)
	return step


static func _load(spec_path: String, fixture: String) -> Array:
	var spec: ShipSpec = load(spec_path) as ShipSpec
	var layout: ThrusterLayout = ThrusterLayout.load_file(fixture)
	return [spec, layout]


# A random unit-ish direction, sometimes zero, sometimes dead astern or dead ahead (the face controller's edges).
static func _direction(rng: RandomNumberGenerator) -> Vector3:
	var pick: float = rng.randf()
	if pick < 0.15:
		return Vector3.ZERO
	if pick < 0.2:
		return Vector3(0.0, 0.0, rng.randf_range(1.0, 500.0))  # dead astern
	if pick < 0.25:
		return Vector3(0.0, 0.0, -rng.randf_range(1.0, 500.0))  # dead ahead
	return Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) * rng.randf_range(0.5, 3000.0)


# A level 0..1 with the extremes well represented (the trim and the deadzone live at the edges).
static func _level(rng: RandomNumberGenerator) -> float:
	var pick: float = rng.randf()
	if pick < 0.3:
		return 0.0
	if pick < 0.45:
		return 1.0
	return rng.randf()


static func _command(rng: RandomNumberGenerator) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = _level(rng)
	cmd.main_right = _level(rng)
	cmd.retro_left = _level(rng)
	cmd.retro_right = _level(rng)
	if rng.randf() < 0.5:
		cmd.strafe = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if rng.randf() < 0.7:
		cmd.rot = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	cmd.brake = rng.randf() < 0.15
	cmd.autotrack = rng.randf() < 0.2
	cmd.track_dir_b = _direction(rng)
	cmd.track_rate_b = Vector3(rng.randfn(0.0, 0.5), rng.randfn(0.0, 0.5), 0.0) if rng.randf() < 0.7 else Vector3.ZERO
	cmd.face_dir_b = _direction(rng)
	return cmd


static func _basis(rng: RandomNumberGenerator) -> Basis:
	if rng.randf() < 0.1:
		return Basis.IDENTITY
	var axis := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)).normalized()
	return Basis(axis, rng.randf_range(-PI, PI))


# World-frame velocity: at rest, cruising, near the assist's safe speed, or past the hard ceiling.
static func _velocity(rng: RandomNumberGenerator, spec: ShipSpec) -> Vector3:
	var pick: float = rng.randf()
	var dir := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)).normalized()
	if pick < 0.1:
		return Vector3.ZERO
	if pick < 0.6:
		return dir * rng.randf_range(0.0, 400.0)
	if pick < 0.85:
		return dir * rng.randf_range(spec.assist_speed_max_mps * 0.98, spec.assist_speed_max_mps * 1.02)
	return dir * rng.randf_range(spec.speed_limit_mps * 0.9, spec.speed_limit_mps * 1.2)


# The ship node's part after the model: the governor's gain, the nozzle and RCS forces in the world frame, the assist's
# speed cap, the environment, and the hard ceiling (`Ship._physics_process`, the reference).
static func _ship_forces(spec: ShipSpec, out: FlightOutput, b: Basis, v: Vector3, env: Vector3, assist_on: bool) -> Dictionary:
	var applied: Vector3 = spec.mass * env
	var gain: float = SpeedGovernor.thrust_gain(v.length(), spec.speed_limit_mps)
	for nozzle: Dictionary in out.nozzle_forces:
		var force: Vector3 = b * (nozzle["force"] as Vector3) * gain
		applied += force
	var rcs_force: Vector3 = b * out.rcs_force_b * gain
	applied += rcs_force
	var torque: Vector3 = b * out.rcs_torque_b
	if assist_on:
		var net: Vector3 = b * (out.pod_force_b + out.rcs_force_b) * gain
		applied += SpeedGovernor.assist_cap_correction(net, v, spec.assist_speed_max_mps)
	var velocity: Vector3 = v
	if spec.speed_limit_mps > 0.0 and v.length() > spec.speed_limit_mps:
		velocity = SpeedGovernor.clamp_velocity(v, spec.speed_limit_mps)
	return {"force": applied, "torque": torque, "velocity": velocity}


# Compares one native row with the reference; counts a mismatch per field in `misses` and the worst relative error in
# `worst`. Exact unless the field is in TOLERATED.
static func _check(misses: Dictionary, worst: Dictionary, field: String, native: Variant, reference: Variant) -> void:
	var same: bool = native == reference
	var rel: float = 0.0
	if not same:
		if native is Vector3:
			var n: Vector3 = native
			var r: Vector3 = reference
			rel = (n - r).length() / maxf(r.length(), 1e-30)
		else:
			rel = absf(float(native) - float(reference)) / maxf(absf(float(reference)), 1e-30)
		if TOLERATED.has(field) and rel <= REL_TOL:
			same = true
	if not same:
		misses[field] = int(misses.get(field, 0)) + 1
		worst[field] = maxf(float(worst.get(field, 0.0)), rel)


# The differential run for one ship type: returns the mismatch counts per field (empty when every sample matched).
func _differential(spec_path: String, fixture: String, seed: int) -> Dictionary:
	var loaded: Array = _load(spec_path, fixture)
	var spec: ShipSpec = loaded[0]
	var layout: ThrusterLayout = loaded[1]
	assert_true(layout.valid, layout.error)
	var model := FlightModel.new(spec, layout)
	var step: Object = _step()
	if step == null:
		return {"no native class": 1}
	var slot: int = FlightBatch.register_slot(step, RID(), spec, layout)
	assert_gte(slot, 0, "a compute-only slot registers")
	if slot < 0:
		return {"no slot": 1}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var scalars := PackedFloat64Array()
	scalars.resize(FlightBatch.CMD_SCALARS)
	var vectors := PackedVector3Array()
	vectors.resize(FlightBatch.CMD_VECTORS)
	var flags := PackedByteArray()
	flags.resize(FlightBatch.CMD_FLAGS)
	var states := PackedVector3Array()
	states.resize(FlightBatch.STATE_VECTORS)
	var misses: Dictionary = {}
	var worst: Dictionary = {}
	var stepped: int = 0
	for i: int in SAMPLES:
		var cmd: FlightCommand = _command(rng)
		var b: Basis = _basis(rng)
		var v: Vector3 = _velocity(rng, spec)
		var w: Vector3 = Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)) if rng.randf() < 0.8 else Vector3.ZERO
		var env: Vector3 = Vector3(rng.randfn(0.0, 0.02), rng.randfn(0.0, 0.02), rng.randfn(0.0, 0.02)) if rng.randf() < 0.3 else Vector3.ZERO
		var assist_on: bool = rng.randf() < 0.8
		var has_propellant: bool = rng.randf() < 0.9
		var dt: float = DT
		if rng.randf() < 0.05:
			dt = 0.0
		elif rng.randf() < 0.1:
			dt = 1.0 / 20.0
		# The reference, body frame in, exactly as the ship node does it.
		var to_body: Basis = b.transposed()
		var out: FlightOutput = model.compute(cmd, to_body * v, to_body * w, to_body * env, assist_on, dt, has_propellant)
		var forces: Dictionary = _ship_forces(spec, out, b, v, env, assist_on)
		# The native row.
		FlightBatch.pack_command(cmd, env, assist_on, has_propellant, scalars, vectors, flags, 0)
		# GDScript's `b.x` is the first column, so a row gathers one component of each column.
		states[0] = Vector3(b.x.x, b.y.x, b.z.x)
		states[1] = Vector3(b.x.y, b.y.y, b.z.y)
		states[2] = Vector3(b.x.z, b.y.z, b.z.z)
		states[3] = v
		states[4] = w
		if not step.step(PackedInt32Array([slot]), scalars, vectors, flags, states, dt):
			misses["step refused"] = int(misses.get("step refused", 0)) + 1
			continue
		stepped += 1
		var ov: PackedVector3Array = step.out_vectors()
		var os: PackedFloat64Array = step.out_scalars()
		if ov.size() != FlightBatch.OUT_VECTORS or os.size() != FlightBatch.OUT_SCALARS:
			misses["row size"] = int(misses.get("row size", 0)) + 1
			continue
		_check(misses, worst, "applied_force", ov[FlightBatch.Out.FORCE], forces["force"])
		_check(misses, worst, "applied_torque", ov[FlightBatch.Out.TORQUE], forces["torque"])
		_check(misses, worst, "pod_force_b", ov[FlightBatch.Out.POD_FORCE], out.pod_force_b)
		_check(misses, worst, "pod_torque_b", ov[FlightBatch.Out.POD_TORQUE], out.pod_torque_b)
		_check(misses, worst, "rcs_force_b", ov[FlightBatch.Out.RCS_FORCE], out.rcs_force_b)
		_check(misses, worst, "rcs_torque_b", ov[FlightBatch.Out.RCS_TORQUE], out.rcs_torque_b)
		_check(misses, worst, "rcs_force_level", ov[FlightBatch.Out.RCS_FORCE_LEVEL], out.rcs_force_level)
		_check(misses, worst, "rcs_torque_level", ov[FlightBatch.Out.RCS_TORQUE_LEVEL], out.rcs_torque_level)
		_check(misses, worst, "rate_target_b", ov[FlightBatch.Out.RATE_TARGET], out.rate_target_b)
		_check(misses, worst, "velocity", ov[FlightBatch.Out.VELOCITY], forces["velocity"])
		for g: int in ThrusterLayout.GROUP_COUNT:
			_check(misses, worst, "level_%s" % ThrusterLayout.group_name(g), os[g], out.group_levels[g])
		_check(misses, worst, "trim", os[FlightBatch.OutScalar.TRIM], out.trim)
		_check(misses, worst, "pod_yaw_cmd", os[FlightBatch.OutScalar.POD_YAW_CMD], out.pod_yaw_cmd)
		_check(misses, worst, "mass_flow", os[FlightBatch.OutScalar.MASS_FLOW], out.mass_flow_kg_s)
		_check(misses, worst, "face_error", os[FlightBatch.OutScalar.FACE_ERROR], out.face_error_rad)
		_check(misses, worst, "braking", os[FlightBatch.OutScalar.BRAKING], 1.0 if out.braking else 0.0)
		_check(misses, worst, "facing", os[FlightBatch.OutScalar.FACING], 1.0 if out.facing else 0.0)
		_check(misses, worst, "tracking", os[FlightBatch.OutScalar.TRACKING], 1.0 if out.tracking else 0.0)
		_check(misses, worst, "propellant_empty", os[FlightBatch.OutScalar.PROPELLANT_EMPTY], 1.0 if out.propellant_empty else 0.0)
		_check(misses, worst, "assist_state", step.assist_state(slot), model.assist.pod_yaw_smoothed)
	assert_eq(stepped, SAMPLES, "every sample stepped")
	for field: String in misses:
		gut.p("%s: %s mismatches in %d of %d samples, worst relative error %s" % [spec.asset_id, field, misses[field], SAMPLES,
				worst.get(field, 0.0)])
	return misses


func test_starfury_matches_the_model_bit_for_bit_over_ten_thousand_samples() -> void:
	var misses: Dictionary = _differential(STARFURY_SPEC, STARFURY_FIXTURE, 1)
	assert_eq(misses, {}, "every field equal on every sample (the listing above names any that differ)")


func test_raider_matches_the_model_bit_for_bit_over_ten_thousand_samples() -> void:
	var misses: Dictionary = _differential(RAIDER_SPEC, RAIDER_FIXTURE, 2)
	assert_eq(misses, {}, "every field equal on every sample (the listing above names any that differ)")


func test_assist_state_is_per_slot_and_reset_clears_it() -> void:
	var loaded: Array = _load(STARFURY_SPEC, STARFURY_FIXTURE)
	var step: Object = _step()
	if step == null:
		return
	var a: int = FlightBatch.register_slot(step, RID(), loaded[0], loaded[1])
	var b: int = FlightBatch.register_slot(step, RID(), loaded[0], loaded[1])
	assert_ne(a, b, "two ships, two slots")
	step.set_assist_state(a, 0.25)
	assert_eq(step.assist_state(a), 0.25)
	assert_eq(step.assist_state(b), 0.0, "the other slot is untouched")
	step.reset_assist(a)
	assert_eq(step.assist_state(a), 0.0)
	assert_eq(step.count(), 2)
	step.unregister(a)
	assert_eq(step.count(), 1)
	var c: int = FlightBatch.register_slot(step, RID(), loaded[0], loaded[1])
	assert_eq(c, a, "a freed slot is reused")
	assert_eq(step.assist_state(c), 0.0, "and starts clean")


func test_bad_input_is_refused_and_never_panics() -> void:
	var loaded: Array = _load(STARFURY_SPEC, STARFURY_FIXTURE)
	var spec: ShipSpec = loaded[0]
	var layout: ThrusterLayout = loaded[1]
	var step: Object = _step()
	if step == null:
		return
	var short := PackedFloat64Array([spec.mass])
	assert_eq(int(step.register(RID(), short, PackedVector3Array(), layout.nozzle_groups, layout.nozzle_positions,
			layout.nozzle_exhausts, PackedVector3Array())), -1, "a short spec is refused")
	assert_engine_error("line up", "one error says why")
	var slot: int = FlightBatch.register_slot(step, RID(), spec, layout)
	assert_gte(slot, 0)
	var scalars := PackedFloat64Array()
	scalars.resize(FlightBatch.CMD_SCALARS)
	var vectors := PackedVector3Array()
	vectors.resize(FlightBatch.CMD_VECTORS)
	var flags := PackedByteArray()
	flags.resize(FlightBatch.CMD_FLAGS)
	assert_false(step.step(PackedInt32Array([slot]), PackedFloat64Array(), vectors, flags, PackedVector3Array(), DT),
			"short scalars are refused")
	assert_engine_error("nothing applied", "one error says why")
	assert_false(step.step(PackedInt32Array([slot + 7]), scalars, vectors, flags, PackedVector3Array(), DT),
			"an unknown slot is refused")
	assert_engine_error("nothing applied", "one error says why")
	assert_eq(step.out_vectors().size(), 0, "a refused step leaves no rows")
	assert_true(step.step(PackedInt32Array([]), PackedFloat64Array(), PackedVector3Array(), PackedByteArray(),
			PackedVector3Array(), DT), "an empty step is fine")
	step.unregister(slot)
	assert_false(step.step(PackedInt32Array([slot]), scalars, vectors, flags, PackedVector3Array(), DT),
			"a slot that was unregistered is unknown")
	assert_engine_error("nothing applied", "one error says why")
	step.unregister(-5)
	step.unregister(1000)
	assert_eq(step.assist_state(1000), 0.0, "an unknown slot reads zero")
