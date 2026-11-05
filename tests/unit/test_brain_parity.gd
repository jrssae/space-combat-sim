extends GutTest
## The brain maths in native code (M4-T17a, architecture §17.13): `PilotSteering`, `InterceptMath`, the temperament tables,
## the five `Manoeuvres`, Godot's `hash([seed, "label"])` and its `RandomNumberGenerator`, each reproduced in
## `native/src/brain_maths.rs` and compared here with the GDScript reference bit for bit on seeded inputs (the bytes of every
## vector and float). The shell `ScsBrains` only hands the maths over. Skips, saying why, when the library is not built.

const BRAINS_CLASS: StringName = &"ScsBrains"
const CASES: int = 400
## The seeds a brain rolls from, as `AiPilot` and its behaviours spell them.
const LABELS: Array[String] = ["ram", "evade", "attack", "attack brain", "runs", "aim"]
const MANOEUVRE_STEPS: int = 300
## Per step handed to the native manoeuvre: now_s, position, the basis rows, velocity, angular velocity, the frame origin
## (64-bit), dt.
const STEP_IN: int = 23
## Per step back: the four levels, strafe, rot, brake, done, timed out, has a desired velocity, the desired velocity.
const STEP_OUT: int = 16

var _saved_native: bool = true


func before_each() -> void:
	_saved_native = bool(Settings.get_value(&"perf_native"))
	Settings.set_value(&"perf_native", true)


func after_each() -> void:
	Settings.set_value(&"perf_native", _saved_native)


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no brain maths to test")
	return true


func _brains() -> Object:
	var brains: Object = NativeLib.instantiate(BRAINS_CLASS)
	assert_not_null(brains, "the library provides %s (%s)" % [BRAINS_CLASS, NativeLib.version(NativeProbe.NATIVE_CLASS)])
	return brains


static func _bytes(value: Variant) -> String:
	return var_to_bytes(value).hex_encode()


static func _v3(rng: RandomNumberGenerator, scale: float) -> Vector3:
	return Vector3(rng.randf_range(-scale, scale), rng.randf_range(-scale, scale), rng.randf_range(-scale, scale))


static func _basis(rng: RandomNumberGenerator) -> Basis:
	return Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))


static func _capability(rng: RandomNumberGenerator) -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = rng.randf_range(5.0, 40.0)
	cap.a_retro = rng.randf_range(2.0, 20.0)
	cap.a_rcs = Vector2(rng.randf_range(1.0, 12.0), rng.randf_range(1.0, 12.0))
	cap.rate_max_rad = Vector3(rng.randf_range(0.3, 2.5), rng.randf_range(0.3, 2.5), rng.randf_range(0.3, 3.0))
	cap.alpha_max_rad = Vector3(rng.randf_range(0.5, 4.0), rng.randf_range(0.5, 4.0), rng.randf_range(0.5, 6.0))
	return cap


## The capability as the native maths takes it: a_main, a_retro, a_rcs x and y, the rate maxima, the angular acceleration maxima.
static func _cap_array(cap: ShipCapability) -> PackedFloat64Array:
	return PackedFloat64Array([cap.a_main, cap.a_retro, cap.a_rcs.x, cap.a_rcs.y, cap.rate_max_rad.x, cap.rate_max_rad.y,
			cap.rate_max_rad.z, cap.alpha_max_rad.x, cap.alpha_max_rad.y, cap.alpha_max_rad.z])


# --- the seeds and the rolls -----------------------------------------------------------------------------------------


func test_the_seed_hash_is_godots_array_hash_bit_for_bit() -> void:
	if _skipped():
		return
	var brains: Object = _brains()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1701
	var seeds: Array[int] = [0, 1, -1, 2, 7, 100, 65535, 65536, 2147483647, 2147483648, 4294967295, 4294967296,
			1099511627776, -9223372036854775808, 9223372036854775807]
	for i: int in 60:
		seeds.append(rng.randi())
		seeds.append(rng.randi() * rng.randi() - rng.randi())
	var differences: PackedStringArray = []
	for seed_value: int in seeds:
		for label: String in LABELS:
			var expected: int = hash([seed_value, label])
			var got: int = brains.hash_seed(seed_value, label)
			if got != expected:
				differences.append("hash([%d, %s]): %d against %d" % [seed_value, label, got, expected])
		# The nested form: a behaviour's own seed is already a hash.
		var attack: int = hash([seed_value, "attack"])
		if brains.hash_seed(attack, "runs") != hash([attack, "runs"]):
			differences.append("nested hash for %d" % seed_value)
	assert_eq(differences.size(), 0, "every seed hash matches Godot's: %s" % differences.slice(0, 5))


func test_the_rolls_are_godots_random_number_generators_bit_for_bit() -> void:
	if _skipped():
		return
	var brains: Object = _brains()
	var differences: PackedStringArray = []
	var seeds: Array[int] = [0, 1, 2, 12345, hash([1, "evade"]), hash([7, "attack brain"]), 4294967295, -5, 9223372036854775807]
	for seed_value: int in seeds:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var expected := PackedFloat64Array()
		for i: int in 200:
			expected.append(rng.randf())
		var got: PackedFloat64Array = brains.randf_sequence(seed_value, 200)
		if _bytes(got) != _bytes(expected):
			differences.append("randf from seed %d" % seed_value)
		rng.seed = seed_value
		var ranged := PackedFloat64Array()
		var bounds: Array[Vector2] = [Vector2(0.05, 0.15), Vector2(0.15, 0.35), Vector2(0.0, TAU), Vector2(-45.0, 45.0),
				Vector2(2.0, 4.0), Vector2(-62.0, 62.0)]
		for i: int in 120:
			var b: Vector2 = bounds[i % bounds.size()]
			ranged.append(rng.randf_range(b.x, b.y))
		var got_ranged: PackedFloat64Array = brains.randf_range_sequence(seed_value, 120)
		if _bytes(got_ranged) != _bytes(ranged):
			differences.append("randf_range from seed %d" % seed_value)
	assert_eq(differences.size(), 0, "every roll matches Godot's generator: %s" % differences)


func test_the_angle_helpers_are_the_engines() -> void:
	if _skipped():
		return
	var brains: Object = _brains()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1702
	var differences: int = 0
	for i: int in 2000:
		var x: float = rng.randf_range(-720.0, 720.0) if i % 2 == 0 else rng.randf_range(-7.0, 7.0)
		var out: PackedFloat64Array = brains.angle_helpers(x, rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
		if out[0] != deg_to_rad(x) or out[1] != rad_to_deg(x):
			differences += 1
	assert_eq(differences, 0, "deg_to_rad and rad_to_deg are the engine's bit for bit")
	var lerp_differences: int = 0
	for i: int in 2000:
		var a: float = rng.randf_range(-10.0, 10.0)
		var b: float = rng.randf_range(-10.0, 10.0)
		var t: float = rng.randf_range(-0.5, 1.5)
		var out: PackedFloat64Array = brains.angle_helpers(a, b, t)
		if out[2] != lerpf(a, b, t):
			lerp_differences += 1
	assert_eq(lerp_differences, 0, "lerpf is the engine's")


# --- steering ----------------------------------------------------------------------------------------------------------


func test_pilot_steering_gives_the_same_bits() -> void:
	if _skipped():
		return
	var brains: Object = _brains()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1703
	var differences: PackedStringArray = []
	for i: int in CASES:
		var basis: Basis = _basis(rng)
		var cap: ShipCapability = _capability(rng)
		var direction: Vector3 = _v3(rng, 1000.0)
		match i % 8:
			0:
				direction = Vector3.ZERO
			1:
				direction = basis.z * rng.randf_range(1.0, 300.0)  # dead astern
			2:
				direction = -basis.z * rng.randf_range(1.0, 300.0)  # on the nose
			3:
				direction = (-basis.z + basis.x * 1e-7) * 50.0  # a hair off the nose
		var omega: Vector3 = _v3(rng, 2.0)
		var gain: float = PilotSteering.K_FACE if i % 3 != 0 else rng.randf_range(0.5, 6.0)
		var expected: Array = [PilotSteering.angle_to(basis, direction), PilotSteering.face(basis, direction, cap.rate_max_rad, gain),
				PilotSteering.face_tracking(basis, direction, omega, cap.rate_max_rad, gain),
				PilotSteering.align_roll(basis, direction, cap.rate_max_rad, gain)]
		var got: Array = brains.steering_face(basis, direction, omega, cap.rate_max_rad, gain)
		if _bytes(got) != _bytes(expected):
			differences.append("face case %d: %s against %s" % [i, got, expected])
		var velocity: Vector3 = _v3(rng, 200.0)
		var v_des: Vector3 = velocity + _v3(rng, [0.5, 30.0, 300.0][i % 3])
		if i % 7 == 0:
			v_des = velocity - basis.z * rng.randf_range(1.0, 100.0)  # straight ahead: the mains' cone
		elif i % 7 == 1:
			v_des = velocity + basis.z * rng.randf_range(1.0, 100.0)  # straight back: the retros' cone
		var horizon: float = [PilotSteering.HORIZON_S, 0.25, 0.2, 0.15][i % 4]
		var all_axes: bool = i % 5 == 0
		var seek: Dictionary = PilotSteering.seek(velocity, v_des, basis, cap, horizon, all_axes)
		var expected_seek: Array = [seek["main"], seek["retro"], seek["strafe"]]
		var got_seek: Array = brains.steering_seek(velocity, v_des, basis, _cap_array(cap), horizon, all_axes)
		if _bytes(got_seek) != _bytes(expected_seek):
			differences.append("seek case %d: %s against %s" % [i, got_seek, expected_seek])
		var base: Vector3 = _v3(rng, 1.0).normalized()
		var accel: Vector3 = _v3(rng, 20.0)
		if i % 6 == 0:
			accel = base * rng.randf_range(-20.0, 20.0)  # along the base: nothing sideways
		var a_side: float = rng.randf_range(0.5, 12.0)
		var lean_max: float = deg_to_rad(rng.randf_range(0.0, 60.0))
		var lean: Vector3 = PilotSteering.lean_toward(base, accel, a_side, lean_max)
		var got_lean: Vector3 = brains.steering_lean(base, accel, a_side, lean_max)
		if _bytes(got_lean) != _bytes(lean):
			differences.append("lean case %d: %s against %s" % [i, got_lean, lean])
	assert_eq(differences.size(), 0, "face, face_tracking, align_roll, angle_to, seek and lean_toward match: %s" % differences.slice(0, 4))


func test_the_intercept_solution_gives_the_same_bits() -> void:
	if _skipped():
		return
	var brains: Object = _brains()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1704
	var differences: PackedStringArray = []
	for i: int in CASES:
		var shooter: Vector3 = _v3(rng, 5000.0)
		var target: Vector3 = shooter + _v3(rng, [50.0, 1200.0, 4000.0][i % 3])
		var shooter_v: Vector3 = _v3(rng, 200.0)
		var target_v: Vector3 = _v3(rng, 200.0)
		var speed: float = [400.0, 1000.0, 50.0, 0.0][i % 4] if i % 9 == 0 else rng.randf_range(300.0, 1200.0)
		match i % 11:
			0:
				target = shooter  # on the shooter
			1:
				target_v = shooter_v + (target - shooter).normalized() * speed  # running at bolt speed
			2:
				target_v = shooter_v + _v3(rng, 1.0).normalized() * (speed * 3.0)  # outruns the bolt
		var lifetime: float = [4.0, 0.5, 10.0][i % 3]
		var expected: Dictionary = InterceptMath.solve(shooter, shooter_v, target, target_v, speed, lifetime)
		var got: Array = brains.intercept(shooter, shooter_v, target, target_v, speed, lifetime)
		var want: Array = [expected["ok"], expected["t"], expected["aim_dir"], expected["lead_point"]]
		if _bytes(got) != _bytes(want):
			differences.append("case %d: %s against %s" % [i, got, want])
	assert_eq(differences.size(), 0, "the lead solution matches: %s" % differences.slice(0, 4))


# --- the temperament ---------------------------------------------------------------------------------------------------


func test_the_temperament_tables_and_the_scaled_profile_give_the_same_bits() -> void:
	if _skipped():
		return
	var brains: Object = _brains()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1705
	var differences: PackedStringArray = []
	var base := AiProfile.new()
	base.tactics = load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	for i: int in CASES:
		var skill: float = [0.0, 0.2, 0.45, 0.7, 0.95, 1.0][i % 6] if i % 2 == 0 else rng.randf()
		var aggression: float = [0.0, 0.25, 0.5, 0.75, 1.0][i % 5] if i % 3 == 0 else rng.randf()
		var t := AiTemperament.new(skill, aggression)
		var expected: PackedFloat64Array = PackedFloat64Array([t.aim_factor(), t.reaction_s(), t.miss_factor(), t.jink_factor(),
				t.reversal_spread_deg(), t.attack_weight_factor(), t.evade_weight_factor(), t.retreat_weight_factor(),
				t.retreat_threshold_factor(), t.press_factor(), t.slash_chance(), t.close_pass_chance(), t.awareness(),
				1.0 if t.never_starts() else 0.0, 1.0 if t.may_ram() else 0.0])
		var got: PackedFloat64Array = brains.temperament_factors(skill, aggression)
		if _bytes(got) != _bytes(expected):
			differences.append("factors at %s/%s: %s against %s" % [skill, aggression, got, expected])
		base.weights = {&"attack": rng.randf(), &"evade": rng.randf(), &"retreat": rng.randf(), &"idle": 1.0}
		if i % 4 == 0:
			base.weights.erase(&"evade")  # an unnamed behaviour weighs 1
		base.retreat_below = rng.randf()
		base.aim_error_deg = rng.randf_range(0.0, 2.0)
		base.tactics.fire_miss_m = rng.randf_range(1.0, 10.0)
		base.tactics.near_range_m = rng.randf_range(500.0, 3000.0)
		base.tactics.break_range_m = rng.randf_range(100.0, 800.0)
		var applied: AiProfile = t.apply(base)
		var want: PackedFloat64Array = PackedFloat64Array([applied.weight(&"attack"), applied.weight(&"evade"),
				applied.weight(&"retreat"), applied.retreat_below, applied.aim_error_deg, applied.tactics.fire_miss_m,
				applied.tactics.near_range_m, applied.tactics.break_range_m])
		var scaled: PackedFloat64Array = brains.temperament_apply(skill, aggression, PackedFloat64Array([base.weight(&"attack"),
				base.weight(&"evade"), base.weight(&"retreat"), base.retreat_below, base.aim_error_deg, base.tactics.fire_miss_m,
				base.tactics.near_range_m, base.tactics.break_range_m]))
		if _bytes(scaled) != _bytes(want):
			differences.append("apply at %s/%s: %s against %s" % [skill, aggression, scaled, want])
	assert_eq(differences.size(), 0, "the temperament maths matches: %s" % differences.slice(0, 4))


# --- the manoeuvres ----------------------------------------------------------------------------------------------------


## A seeded sequence of perceptions for a manoeuvre: a random walk of the pose and motion, with stretches that let each
## move meet its goal (a roll rate that integrates past a turn, a velocity that reverses, a strafe that reaches its corner).
static func _steps(rng: RandomNumberGenerator, cap: ShipCapability, kind: int) -> Array[Perception]:
	var out: Array[Perception] = []
	var origin: UniversePos = UniversePos.new(rng.randf_range(-1e6, 1e6), rng.randf_range(-1e6, 1e6), rng.randf_range(-1e6, 1e6))
	var position: Vector3 = _v3(rng, 500.0)
	var basis: Basis = _basis(rng)
	var velocity: Vector3 = _v3(rng, 60.0) if kind != 1 else _v3(rng, 1.0).normalized() * rng.randf_range(0.0, 80.0)
	var angular: Vector3 = _v3(rng, 0.2)
	var now_s: float = rng.randf_range(0.0, 100.0)
	var dt: float = 1.0 / 60.0
	for i: int in MANOEUVRE_STEPS:
		var p := Perception.new()
		p.now_s = now_s
		p.position = position
		p.basis = basis
		p.velocity = velocity
		p.angular_velocity = angular
		p.capability = cap
		p.frame_origin = origin
		out.append(p)
		# The walk: the roll spins up, the flip reverses, the box drifts slowly, the stop winds down.
		match kind:
			0:
				angular = basis * Vector3(0.0, 0.0, minf(cap.rate_max_rad.z, float(i) * 0.05)) + _v3(rng, 0.01)
			1:
				velocity = velocity.lerp(-velocity.normalized() * 30.0, 0.01) + _v3(rng, 0.2)
			2:
				velocity += _v3(rng, 0.5)
			3:
				basis = basis * Basis(Vector3.UP, -0.01 * float(i % 50))
			_:
				velocity *= 0.97
				angular *= 0.95
		basis = (basis * Basis.from_euler(angular * dt)).orthonormalized()
		position += velocity * dt
		now_s += dt
		if i % 97 == 96:
			origin = UniversePos.new(origin.x + 2000.0, origin.y - 500.0, origin.z + 125.0)  # a rebase
			position -= Vector3(2000.0, -500.0, 125.0)
	return out


static func _pack_steps(steps: Array[Perception], dt: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for p: Perception in steps:
		out.append(p.now_s)
		for v: Vector3 in [p.position, p.basis.x, p.basis.y, p.basis.z, p.velocity, p.angular_velocity]:
			out.append_array([v.x, v.y, v.z])
		out.append_array([p.frame_origin.x, p.frame_origin.y, p.frame_origin.z, dt])
	return out


static func _pack_command(cmd: FlightCommand, m: Manoeuvre) -> PackedFloat64Array:
	return PackedFloat64Array([cmd.main_left, cmd.main_right, cmd.retro_left, cmd.retro_right, cmd.strafe.x, cmd.strafe.y,
			cmd.rot.x, cmd.rot.y, cmd.rot.z, 1.0 if cmd.brake else 0.0, 1.0 if m.done else 0.0, 1.0 if m.timed_out else 0.0,
			1.0 if m.has_desired_velocity else 0.0, m.desired_velocity.x, m.desired_velocity.y, m.desired_velocity.z])


func test_the_five_manoeuvres_fly_the_same_bits() -> void:
	if _skipped():
		return
	var brains: Object = _brains()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1706
	var differences: PackedStringArray = []
	for round: int in 6:
		for kind: int in Manoeuvres.NAMES.size():
			var cap: ShipCapability = _capability(rng)
			var steps: Array[Perception] = _steps(rng, cap, kind)
			var dt: float = 1.0 / 60.0
			var reference: Manoeuvre = Manoeuvres.create(Manoeuvres.NAMES[kind])
			var expected := PackedFloat64Array()
			for p: Perception in steps:
				var cmd: FlightCommand = reference.step(p, dt)
				expected.append_array(_pack_command(cmd, reference))
			var got: Array = brains.manoeuvre_run(kind, _cap_array(cap), _pack_steps(steps, dt))
			var got_steps: PackedFloat64Array = got[0]
			if _bytes(got_steps) != _bytes(expected):
				var first: int = -1
				for i: int in mini(got_steps.size(), expected.size()):
					if got_steps[i] != expected[i]:
						first = i
						break
				differences.append("%s round %d: first difference at step %d field %d (%s against %s)" % [Manoeuvres.NAMES[kind], round,
						first / STEP_OUT, first % STEP_OUT, got_steps[first] if first >= 0 else "", expected[first] if first >= 0 else ""])
			var result: Dictionary = reference.result()
			var got_result: Dictionary = got[1]
			for key: String in result:
				if not got_result.has(key) or _bytes(got_result[key]) != _bytes(result[key]):
					differences.append("%s round %d: result %s is %s against %s" % [Manoeuvres.NAMES[kind], round, key,
							got_result.get(key), result[key]])
			if got_result.size() != result.size():
				differences.append("%s round %d: result keys %s against %s" % [Manoeuvres.NAMES[kind], round, got_result.keys(), result.keys()])
	assert_eq(differences.size(), 0, "every manoeuvre flies the same on seeded walks: %s" % differences.slice(0, 5))
