extends GutTest
## The turret kernels on the core's rows (M4-T20, architecture §17.13): a gun's target pick, aim step and fire gate, an
## interceptor's pick, and a capital's strike target for its beams and missiles run natively over the rows, bit for bit with
## the GDScript stand-ins, which stay the reference behind `perf_native_weapons`. The aim maths (`InterceptMath.solve`, the
## limited turn, the angle) are compared on seeded inputs; a seeded miniature battle is run once on each path and must log
## the same picks, axes, aim errors, fire ticks, bolts, kills, beams and launches every tick, also across a rebase between the
## sync and the step and across a switch between the paths mid-run. Skips, saying why, without the native library.

const NATIVE_CLASS: StringName = &"ScsWeaponRows"

var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in WeaponRowsScene.SETTINGS:
		_saved[key] = Settings.get_value(key)


func after_each() -> void:
	for key: StringName in _saved:
		Settings.set_value(key, _saved[key])
	MissileStandin.native_rows = null
	StaticRows.clear()
	ContactScan.invalidate()
	Factions.reset()


const FIXTURE: String = "turret_kernel"


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no weapon kernels to test")
	return true


# A unit vector from the seeded generator, now and then exactly on an axis.
static func _unit(rng: RandomNumberGenerator) -> Vector3:
	if rng.randf() < 0.05:
		return [Vector3.UP, Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN][rng.randi_range(0, 3)]
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()


func test_the_aim_maths_match_the_gdscript_bit_for_bit() -> void:
	if _skipped():
		return
	var rows: Object = ClassDB.instantiate(NATIVE_CLASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20
	var mismatches: Array[String] = []
	for i: int in 4000:
		var at := Vector3(rng.randf_range(-9e3, 9e3), rng.randf_range(-9e3, 9e3), rng.randf_range(-9e3, 9e3))
		var target := at + _unit(rng) * rng.randf_range(0.0, 6000.0)
		if i % 50 == 0:
			target = at  # on top of the shooter
		var shooter_v := _unit(rng) * rng.randf_range(0.0, 60.0)
		var target_v := _unit(rng) * rng.randf_range(0.0, 1200.0)  # some outrun the bolt
		var lead: Dictionary = InterceptMath.solve(at, shooter_v, target, target_v, TurretStandin.MUZZLE_SPEED_MPS,
				TurretStandin.BOLT_LIFETIME_S)
		var native: Vector4 = rows.solve_aim(at, shooter_v, target, target_v, TurretStandin.MUZZLE_SPEED_MPS,
				TurretStandin.BOLT_LIFETIME_S)
		var aim: Vector3 = lead["aim_dir"]
		if var_to_bytes(aim) != var_to_bytes(Vector3(native.x, native.y, native.z)) or float(lead["ok"]) != native.w:
			mismatches.append("solve %d: %s %s against %s" % [i, aim, lead["ok"], native])
		var from := _unit(rng)
		var wanted := _unit(rng)
		if i % 40 == 0:
			wanted = from  # no turn at all
		elif i % 40 == 1:
			wanted = -from  # straight behind: the fallback axis
		var max_angle: float = rng.randf_range(0.0, 0.2) if i % 9 != 0 else TurretStandin.TURN_RATE_RAD_S / 60.0
		var turned: Vector3 = TurretStandin.turned_toward(from, wanted, max_angle)
		var turned_native: Vector3 = rows.turned_toward(from, wanted, max_angle)
		if var_to_bytes(turned) != var_to_bytes(turned_native):
			mismatches.append("turn %d: %s against %s" % [i, turned, turned_native])
		if from.angle_to(wanted) != rows.angle_to(from, wanted):
			mismatches.append("angle %d" % i)
	assert_eq(mismatches.size(), 0, "the native aim maths equal the GDScript's bit for bit: %s" % [mismatches.slice(0, 5)])


func test_a_seeded_battle_gives_the_same_picks_aims_fire_ticks_and_kills_on_both_paths() -> void:
	if _skipped():
		return
	await _record("seed_7", 7, 600)
	var native: WeaponRowsScene = WeaponRowsScene.build(self, 7, true)
	native.run(600)
	assert_eq(native.director.weapons_path(), &"native", "the run is on the native rows")
	_assert_recorded("seed_7", native.log)
	# The scene exercised every part: picks, shots, kills, beams, launches and mines.
	var reference: WeaponRowsScene = native
	var last: Dictionary = reference.log[reference.log.size() - 1]
	var counts: Array = last["counts"]
	assert_gt(int(counts[0]), 10, "interceptors shot things down: %s" % [counts])
	assert_gt(int(counts[1]), 0, "missiles among them")
	assert_gt(int(counts[2]), 0, "beams fired")
	assert_gt(int(counts[3]), 0, "missiles were launched")
	var fired: int = 0
	for entry: Dictionary in reference.log:
		for made: Array in entry["made"]:
			fired += 1 if made[0] == String(Projectile.KIND_BOLT) else 0
	assert_gt(fired, 50, "the guns fired")


func test_a_rebase_between_the_sync_and_the_step_changes_nothing() -> void:
	if _skipped():
		return
	await _record("rebase_at_90", 11, 240, 90)
	var native: WeaponRowsScene = WeaponRowsScene.build(self, 11, true)
	native.rebase_at = 90
	native.run(240)
	assert_eq(native.director.weapons_path(), &"native")
	_assert_recorded("rebase_at_90", native.log)


func test_switching_paths_mid_run_carries_every_turrets_state() -> void:
	if _skipped():
		return
	var reference: WeaponRowsScene = WeaponRowsScene.build(self, 5, false)
	reference.run(450)
	reference.dispose()
	var mixed: WeaponRowsScene = WeaponRowsScene.build(self, 5, true)
	mixed.run(150)
	Settings.set_value(&"perf_native_weapons", false)
	mixed.run(150)
	assert_eq(mixed.director.weapons_path(), &"gdscript", "the setting off: the stand-ins answer")
	Settings.set_value(&"perf_native_weapons", true)
	mixed.run(150)
	assert_eq(mixed.director.weapons_path(), &"native", "on again: the rows answer")
	_assert_same_logs(reference.log, mixed.log, "native, GDScript, native")


func test_a_relation_changed_mid_run_is_followed_the_same_tick_on_both_paths() -> void:
	if _skipped():
		return
	if ParityFixture.recording():
		ParityFixture.record(FIXTURE, "relation_changed_at_120", WeaponRowsScene.digests(_relation_run(false)))
	var native_log: Array = _relation_run(true)
	_assert_recorded("relation_changed_at_120", native_log)
	# Within a retarget (six ticks) every gun has let go: the rows read the new table.
	var after: Dictionary = native_log[130]
	var held: int = 0
	for turret: Array in after["turrets"]:
		if turret.size() == 5 and turret[1] != "":
			held += 1
	assert_eq(held, 0, "no gun holds a target once no side is hostile")


func test_turrets_of_a_capital_that_is_not_bound_are_refused() -> void:
	if _skipped():
		return
	var rows: Object = ClassDB.instantiate(NATIVE_CLASS)
	rows.set_capitals(PackedInt64Array([0, 0]))
	var ok: bool = rows.set_turrets(PackedInt32Array([0, 2]), PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
			PackedByteArray([0, 0]))
	assert_engine_error("capital", "a turret of capital 2 of 2 is refused, saying why")
	assert_false(ok, "refused")
	ok = rows.set_turrets(PackedInt32Array([0, -1]), PackedVector3Array([Vector3.ZERO, Vector3.ZERO]), PackedByteArray([0, 0]))
	assert_engine_error("capital", "a negative capital is refused, saying why")
	assert_false(ok)
	assert_true(rows.set_turrets(PackedInt32Array([0, 1]), PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
			PackedByteArray([0, 1])), "bound capitals are taken")
	var out: Array = rows.step(1, 100.0, 1.0 / 60.0, 30, 120, 0, 2, 60)  # M4-T22 fix round 1: the ticks per second
	assert_eq((out[0] as PackedInt32Array).size(), 0, "no core: nothing fires, nothing breaks")


func test_the_stand_ins_answer_without_the_core() -> void:
	var scene: WeaponRowsScene = WeaponRowsScene.build(self, 3, true)
	Settings.set_value(&"perf_native_core", false)
	scene.run(5)
	assert_eq(scene.director.weapons_path(), &"gdscript", "no core this tick: the GDScript stand-ins step the weapons")
	assert_null(MissileStandin.native_rows, "and missiles steer in GDScript")


# Seed 17's scene for 120 ticks, then no side hostile for 120 more (the console's `relation` command changes the live table
# in place), on the native rows or the GDScript stand-ins: its log.
func _relation_run(native: bool) -> Array:
	var scene: WeaponRowsScene = WeaponRowsScene.build(self, 17, native)
	scene.run(120)
	assert_eq(Factions.table().set_relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.Relation.NEUTRAL), "")
	scene.run(120)
	assert_eq(scene.director.weapons_path(), &"native" if native else &"gdscript")
	var out: Array = scene.log
	scene.dispose()
	Factions.reset()
	return out


# Records (when recording) the GDScript stand-ins' log of the scene for `seed_value` over `ticks` (M4-T37).
func _record(case: String, seed_value: int, ticks: int, rebase_at: int = -1) -> void:
	if not ParityFixture.recording():
		return
	var reference: WeaponRowsScene = WeaponRowsScene.build(self, seed_value, false)
	reference.rebase_at = rebase_at
	reference.run(ticks)
	assert_eq(reference.director.weapons_path(), &"gdscript", "the reference ran on the GDScript stand-ins")
	ParityFixture.record(FIXTURE, case, WeaponRowsScene.digests(reference.log))
	reference.dispose()


# Fails at the first tick whose entry differs from the GDScript stand-ins' recorded log.
func _assert_recorded(case: String, log: Array) -> void:
	var recorded: Variant = ParityFixture.stored(FIXTURE, case)
	assert_not_null(recorded, "%s: the GDScript stand-ins' log was recorded" % case)
	if recorded == null:
		return
	var got: Array = WeaponRowsScene.digests(log)
	assert_eq(got.size(), (recorded as Array).size(), "%s: as many ticks as the recording" % case)
	for t: int in mini(got.size(), (recorded as Array).size()):
		if got[t] != recorded[t]:
			fail_test("%s: tick %d differs from the GDScript stand-ins' recording: %s" % [case, t, var_to_str(log[t]).left(400)])
			return
	pass_test("%s: %d ticks equal the recording byte for byte" % [case, got.size()])


# Fails at the first tick and field where the two logs differ.
func _assert_same_logs(a: Array, b: Array, label: String) -> void:
	assert_eq(a.size(), b.size(), "%s: as many ticks" % label)
	for t: int in mini(a.size(), b.size()):
		var x: Dictionary = a[t]
		var y: Dictionary = b[t]
		for key: String in x:
			if var_to_bytes(x[key]) != var_to_bytes(y.get(key)):
				fail_test("%s: tick %d differs in %s:\n gdscript %s\n native   %s" % [label, x["tick"], key,
						_differing(x[key], y.get(key)), _differing(y.get(key), x[key])])
				return
	pass_test("%s: %d ticks equal byte for byte" % [label, a.size()])


# The first element of `v` that differs from `w`, when both are arrays.
static func _differing(v: Variant, w: Variant) -> String:
	if v is Array and w is Array:
		for i: int in mini(v.size(), w.size()):
			if var_to_bytes(v[i]) != var_to_bytes(w[i]):
				return "[%d] %s" % [i, str(v[i])]
		return "size %d" % v.size()
	return str(v).left(300)
