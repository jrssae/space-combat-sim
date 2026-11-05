extends GutTest
## The missile kernel on the core's rows (M4-T20, architecture §17.13): a guided missile's proportional navigation runs
## natively over its target's row, bit for bit with `MissileStandin.steer`, which stays the reference behind
## `perf_native_weapons`. Compared on seeded inputs and on seeded flights at a weaving target, one missile steered by each
## path side by side; a target hidden after the tick's sync (not yet read again) is asked of the GDScript, which drops it as
## before, and a missile with no core to read steers in GDScript. Skips, saying why, without the native library.

const NATIVE_CLASS: StringName = &"ScsWeaponRows"
const DT: float = 1.0 / 60.0

var world: WorldFrame
var projectiles: Node3D
var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in WeaponRowsScene.SETTINGS:
		_saved[key] = Settings.get_value(key)
		Settings.set_value(key, true)
	ContactScan.invalidate()
	StaticRows.clear()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func after_each() -> void:
	for key: StringName in _saved:
		Settings.set_value(key, _saved[key])
	MissileStandin.native_rows = null
	ContactScan.invalidate()
	Factions.reset()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no weapon kernels to test")
	return true


func test_the_guidance_maths_match_the_gdscript_bit_for_bit() -> void:
	if _skipped():
		return
	var rows: Object = ClassDB.instantiate(NATIVE_CLASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var mismatches: Array[String] = []
	for i: int in 5000:
		var at := Vector3(rng.randf_range(-2e4, 2e4), rng.randf_range(-2e4, 2e4), rng.randf_range(-2e4, 2e4))
		var heading := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var velocity: Vector3 = heading * MissileStandin.SPEED_MPS
		var target: Vector3 = at + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) \
				* rng.randf_range(0.0, 6000.0)
		var target_v := Vector3(rng.randf_range(-300, 300), rng.randf_range(-300, 300), rng.randf_range(-300, 300))
		match i % 25:
			0:
				target = at  # on top of it
			1:
				velocity = Vector3.ZERO  # no speed
			2:
				target_v = velocity  # no closing at all
		var gain: float = MissileStandin.NAV_GAIN
		var rate: float = MissileStandin.TURN_RATE_RAD_S * (1.0 if i % 7 != 0 else 0.1)
		var expected: Vector3 = MissileStandin.steer(at, velocity, target, target_v, gain, rate, DT)
		var got: Vector3 = rows.steer(at, velocity, target, target_v, gain, rate, DT)
		if var_to_bytes(expected) != var_to_bytes(got):
			mismatches.append("%d: %s against %s" % [i, expected, got])
	assert_eq(mismatches.size(), 0, "the native guidance equals the GDScript's bit for bit: %s" % [mismatches.slice(0, 5)])


# A frozen fighter with a marker and a hull, moved by hand.
func _fighter(at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	world.add_child(body)
	body.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	body.global_position = at
	var hull := Damageable.new()
	hull.faction = Factions.RAIDERS
	hull.bounding_radius = 8.0
	body.add_child(hull)
	var marker := Targetable.new()
	marker.name = "Targetable"
	marker.faction = Factions.RAIDERS
	body.add_child(marker)
	return body


# A missile launched at `target` from `at`, stepped by hand.
func _missile(at: Vector3, target: Node3D) -> Projectile:
	var missile: Projectile = MissileStandin.launch(projectiles, at, target, 0, Factions.EARTH_ALLIANCE, SimClock.now())
	missile.set_physics_process(false)
	return missile


func _rows(core: SimCore) -> Object:
	var rows: Object = ClassDB.instantiate(NATIVE_CLASS)
	assert_true(rows.attach_core(core.core), "the kernels read the core")
	return rows


func test_a_missile_on_the_rows_flies_the_gdscript_missiles_path_bit_for_bit() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var core: SimCore = SimCore.attach(world)
	var rows: Object = _rows(core)
	for flight: int in 4:
		var start := Vector3(rng.randf_range(-3000, 3000), rng.randf_range(-500, 500), rng.randf_range(-3000, 3000))
		var target: RigidBody3D = _fighter(start + Vector3(rng.randf_range(2000, 4000), 0.0, rng.randf_range(-2000, 2000)))
		var on_rows: Projectile = _missile(start, target)
		var reference: Projectile = _missile(start, target)
		var weave: float = rng.randf_range(0.3, 1.5)
		var guide_rows: MissileStandin = MissileStandin.of(on_rows)
		var guide_ref: MissileStandin = MissileStandin.of(reference)
		var steps: int = 0
		for tick: int in 900:
			var t: float = float(tick) * DT
			var velocity := Vector3(150.0 * sin(weave * t), 40.0 * cos(2.0 * weave * t), 180.0)
			target.global_position += velocity * DT
			target.linear_velocity = velocity
			core.sync_now()
			MissileStandin.native_rows = rows
			var v_rows: Vector3 = guide_rows.step(on_rows, DT)
			MissileStandin.native_rows = null
			var v_ref: Vector3 = guide_ref.step(reference, DT)
			if var_to_bytes(v_rows) != var_to_bytes(v_ref):
				fail_test("flight %d tick %d: %s against %s" % [flight, tick, v_rows, v_ref])
				return
			for pair: Array in [[on_rows, v_rows], [reference, v_ref]]:
				var m: Projectile = pair[0]
				m.velocity = pair[1]
				m.global_position += m.velocity * DT
			steps += 1
			if on_rows.global_position.distance_to(target.global_position) < 5.0:
				break
		assert_eq(var_to_bytes(on_rows.global_position), var_to_bytes(reference.global_position), "flight %d: the same path, %d ticks" % [flight, steps])
		assert_eq(guide_rows.target_id, guide_ref.target_id, "the same target kept")
	assert_gt(MissileStandin.native_steers, 0, "the rows answered")


func test_a_target_hidden_after_the_sync_is_dropped_as_the_gdscript_drops_it() -> void:
	if _skipped():
		return
	var core: SimCore = SimCore.attach(world)
	var rows: Object = _rows(core)
	var target: RigidBody3D = _fighter(Vector3(0.0, 0.0, -3000.0))
	var missile: Projectile = _missile(Vector3.ZERO, target)
	var guide: MissileStandin = MissileStandin.of(missile)
	core.sync_now()
	target.visible = false  # parked after the sync: the core has not read it again
	MissileStandin.native_rows = rows
	var v: Vector3 = guide.step(missile, DT)
	assert_eq(guide.target_id, 0, "the hidden target is dropped")
	assert_eq(v, missile.velocity, "and the missile flies straight on")
	var other: Projectile = _missile(Vector3.ZERO, _fighter(Vector3(0.0, 0.0, -2500.0)))
	core.sync_now()
	var before: int = MissileStandin.native_steers
	MissileStandin.of(other).step(other, DT)
	assert_eq(MissileStandin.native_steers, before + 1, "a target on the rows and untouched is steered natively")


func test_a_missile_without_a_core_steers_in_gdscript() -> void:
	if _skipped():
		return
	var rows: Object = ClassDB.instantiate(NATIVE_CLASS)  # never attached: no rows to read
	var target: RigidBody3D = _fighter(Vector3(500.0, 0.0, -3000.0))
	target.linear_velocity = Vector3(100.0, 0.0, 0.0)
	var missile: Projectile = _missile(Vector3.ZERO, target)
	var reference: Projectile = _missile(Vector3.ZERO, target)
	MissileStandin.native_rows = rows
	var before: int = MissileStandin.native_steers
	var v: Vector3 = MissileStandin.of(missile).step(missile, DT)
	MissileStandin.native_rows = null
	assert_eq(MissileStandin.native_steers, before, "nothing on the rows: the GDScript answered")
	assert_eq(v, MissileStandin.of(reference).step(reference, DT), "with the reference's answer")
