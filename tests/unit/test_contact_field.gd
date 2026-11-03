extends GutTest
## The contact scan's queries in native code (M4-T05b, architecture §17.5): `ContactScan` hands its arrays to the native
## `ScsContactField` and builds what callers get from the indices it returns. The native path must answer exactly as the
## GDScript one (maintainer, 2026-11-02: bit-identical): the same contacts in the same order, the same `incoming_fire`
## and the same broadcasts, so seeded runs give the same outcome with `perf_native` on and off. Scans are filled by hand
## (no scene), so seeded worlds of any size are cheap. Skips, saying why, when the native library is not built.

const WORLDS: int = 40
const MAX_BODIES: int = 300
const QUERIES_PER_WORLD: int = 40
const SPREAD_GROUPS: int = 10
const GROUP_SIZE: int = 12
const GROUP_SPACING_M: float = 20000.0
const FACTIONS: Array[StringName] = [Factions.RAIDERS, Factions.EARTH_ALLIANCE, Factions.NEUTRAL, &"drifters"]

var _native_backup: bool


func before_each() -> void:
	_native_backup = bool(Settings.get_value(&"perf_native"))
	Settings.set_value(&"perf_native", true)
	Factions.reset()


func after_each() -> void:
	Settings.set_value(&"perf_native", _native_backup)
	Factions.reset()


# True (and the test marked pending, saying why) when there is no native library to compare against.
func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no native path to compare")
	return true


# A scan of the given bodies: body i has body id 1000 + i, contact id 5000 + i and name "SHIP i".
static func _scan(positions: PackedVector3Array, factions: Array[StringName], ships: PackedByteArray) -> ContactScan:
	var scan := ContactScan.new()
	for i: int in positions.size():
		scan._body_ids.append(1000 + i)
		scan._ids.append(5000 + i)
		scan._names.append("SHIP %d" % i)
		scan._factions.append(factions[i])
		scan._positions.append(positions[i])
		scan._velocities.append(Vector3.ZERO)
		scan._forwards.append(Vector3.FORWARD)
		scan._ups.append(Vector3.UP)
		scan._radii.append(10.0)
		scan._is_ship.append(ships[i])
		scan._hulls.append(1.0)
		scan._target_ids.append(-1)
	return scan


# Seeded positions in one of four shapes: a furball, spread groups, a coarse lattice (equal ranges) or far from the origin.
static func _positions(rng: RandomNumberGenerator, n: int, shape: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var far := Vector3(rng.randf_range(-2.0e5, 2.0e5), rng.randf_range(-2.0e5, 2.0e5), rng.randf_range(-2.0e5, 2.0e5))
	for i: int in n:
		match shape:
			0:
				out.append(Vector3(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0),
						rng.randf_range(-3000.0, 3000.0)))
			1:
				var group := Vector3(float(i / GROUP_SIZE) * GROUP_SPACING_M, 0.0, 0.0)
				out.append(group + Vector3(rng.randf_range(-1500.0, 1500.0), rng.randf_range(-1500.0, 1500.0),
						rng.randf_range(-1500.0, 1500.0)))
			2:
				out.append(Vector3(rng.randi_range(-14, 14), rng.randi_range(-14, 14), rng.randi_range(-14, 14)) * 625.0)
			_:
				out.append(far + Vector3(rng.randf_range(-6000.0, 6000.0), rng.randf_range(-6000.0, 6000.0),
						rng.randf_range(-6000.0, 6000.0)))
	# Some bodies exactly on the sensor range of body 0, and one just past it.
	if n > 3:
		out[1] = out[0] + Vector3(ContactScan.SENSOR_RANGE_M, 0.0, 0.0)
		out[2] = out[0] + Vector3(0.0, -ContactScan.SENSOR_RANGE_M, 0.0)
		out[3] = out[0] + Vector3(0.0, 0.0, ContactScan.SENSOR_RANGE_M + 0.001)
	return out


# A seeded world: bodies of every faction (some props), and bolts around them, some aimed straight at a body.
static func _world(rng: RandomNumberGenerator, n: int, shape: int) -> ContactScan:
	var positions := _positions(rng, n, shape)
	var factions: Array[StringName] = []
	var ships := PackedByteArray()
	for i: int in n:
		factions.append(FACTIONS[rng.randi_range(0, FACTIONS.size() - 1)])
		ships.append(1 if rng.randf() < 0.85 else 0)
	var scan := _scan(positions, factions, ships)
	for b: int in rng.randi_range(0, 400):
		# Half the bolts fly about the first 30 bodies, so the queries on them see some incoming fire.
		var target: int = rng.randi_range(0, mini(n, 30) - 1) if rng.randf() < 0.5 else rng.randi_range(0, n - 1)
		var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		direction = direction.normalized() if direction.length_squared() > 1e-6 else Vector3.FORWARD
		var at: Vector3 = positions[target] + direction * rng.randf_range(0.0, 1200.0)
		var velocity := Vector3(rng.randf_range(-600.0, 600.0), rng.randf_range(-600.0, 600.0), rng.randf_range(-600.0, 600.0))
		var faction: StringName = FACTIONS[rng.randi_range(0, FACTIONS.size() - 1)]
		if rng.randf() < 0.5:
			# Aimed at the body, by its enemy, with a miss of a few metres either side of the 15 m line.
			velocity = -direction * rng.randf_range(300.0, 600.0) + Vector3(rng.randf_range(-8.0, 8.0), 0.0, 0.0)
			if factions[target] == Factions.RAIDERS:
				faction = Factions.EARTH_ALLIANCE
			elif factions[target] == Factions.EARTH_ALLIANCE:
				faction = Factions.RAIDERS
		scan._bolt_positions.append(at)
		scan._bolt_velocities.append(velocity)
		scan._bolt_factions.append(faction)
		scan._bolt_shooters.append(1000 + rng.randi_range(0, n - 1) if rng.randf() < 0.7 else 0)
	return scan


# A broadcast scan (`from_broadcasters`' shape) over the same bodies, each with its own reach.
static func _broadcasters(rng: RandomNumberGenerator, scan: ContactScan) -> ContactScan:
	var reach_choices: Array[float] = [0.0, 3000.0, 100000.0, 1.0e6]
	var b := _scan(scan._positions, scan._factions, scan._is_ship)
	for i: int in scan._positions.size():
		b._reach.append(reach_choices[rng.randi_range(0, reach_choices.size() - 1)])
	return b


static func _ids(list: Array[Contact]) -> Array[int]:
	var out: Array[int] = []
	for c: Contact in list:
		out.append(c.id)
	return out


# Whether two answers are the very same contact objects in the same order (the facade shares each faction's list).
static func _same(a: Array[Contact], b: Array[Contact]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if not is_same(a[i], b[i]):
			return false
	return true


func test_the_scan_takes_the_native_path_when_the_library_is_loaded() -> void:
	if _skipped():
		return
	var scan := _scan(PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]), [Factions.RAIDERS, Factions.EARTH_ALLIANCE],
			PackedByteArray([1, 1]))
	assert_eq(scan.path(), &"native", "library loaded and perf_native on: the native field answers (%s)" % NativeLib.version(ContactScan.NATIVE_CLASS))
	scan.use_native = false
	assert_eq(scan.path(), &"gdscript", "use_native false forces GDScript")


func test_seeded_worlds_give_the_same_answers_on_both_paths() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026_11_03
	var compared: int = 0
	var cut: int = 0
	var under_fire: int = 0
	var hearing: int = 0
	for world: int in WORLDS:
		var n: int = 1 if world == 0 else (MAX_BODIES if world == 1 else rng.randi_range(1, MAX_BODIES))
		var shape: int = world % 4
		var scan := _world(rng, n, shape)
		var heard := _broadcasters(rng, scan)
		assert_eq(scan.path(), &"native", "world %d: the native path" % world)
		for q: int in mini(QUERIES_PER_WORLD, n + 2):
			var at_index: int = rng.randi_range(0, mini(n, 30) - 1) if rng.randf() < 0.5 else rng.randi_range(0, n - 1)
			var own_id: int = 1000 + at_index
			var own_at: Vector3 = scan._positions[at_index]
			if q == n:
				own_id = -1  # a ship the scan does not know
			elif q == n + 1 or rng.randf() < 0.2:
				own_at += Vector3(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0))
			var faction: StringName = FACTIONS[rng.randi_range(0, FACTIONS.size() - 1)] if rng.randf() < 0.3 \
					else scan._factions[at_index]
			var velocity := Vector3(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
			if rng.randf() < 0.6:
				velocity *= 0.02  # slow enough that the aimed bolts still arrive
			var range_m: float = ContactScan.SENSOR_RANGE_M
			if rng.randf() < 0.15:
				range_m = [0.0, 700.0, 2500.0, 8000.0, 30000.0][rng.randi_range(0, 4)]
			var k: int = rng.randi_range(1, 20)
			var kept_ids := PackedInt64Array([5000 + rng.randi_range(0, n - 1), 0, -1, 5000 + n + 7])
			var kept_names := PackedStringArray(["ship %d" % rng.randi_range(0, n - 1)])
			var keeper := func() -> Array: return [kept_ids, kept_names]
			var label: String = "world %d (%d bodies, shape %d), query %d, k %d, range %.0f" % [world, n, shape, q, k, range_m]
			var answers: Array = []
			for native: bool in [true, false]:
				scan.use_native = native
				heard.use_native = native
				answers.append([
					scan.contacts_for(own_id, own_at, faction, range_m),
					scan.nearest_for(own_id, own_at, faction, k, Callable(), range_m),
					scan.nearest_for(own_id, own_at, faction, k, keeper, range_m),
					scan.incoming_fire(own_id, own_at, velocity, faction),
					heard.broadcasts_for(own_id, own_at, faction),
				])
			var on: Array = answers[0]
			var off: Array = answers[1]
			assert_true(_same(on[0], off[0]), "%s: contacts_for %s against %s" % [label, _ids(on[0]), _ids(off[0])])
			assert_true(_same(on[1], off[1]), "%s: nearest_for %s against %s" % [label, _ids(on[1]), _ids(off[1])])
			assert_true(_same(on[2], off[2]), "%s: nearest_for with keeper %s against %s" % [label, _ids(on[2]), _ids(off[2])])
			assert_eq(on[3], off[3], "%s: incoming_fire" % label)
			assert_true(_same(on[4], off[4]), "%s: broadcasts_for %s against %s" % [label, _ids(on[4]), _ids(off[4])])
			compared += 1
			if (off[1] as Array).size() < (off[0] as Array).size():
				cut += 1
			if int(off[3]) > 0:
				under_fire += 1
			if not (off[4] as Array).is_empty():
				hearing += 1
	gut.p("%d queries compared over %d worlds: %d cut by nearest-k, %d under fire, %d hearing broadcasts" % [compared,
			WORLDS, cut, under_fire, hearing])
	assert_gt(cut, 50, "the nearest-k cut, the nearest hostile and the keeper were exercised")
	assert_gt(under_fire, 50, "incoming fire was counted")
	assert_gt(hearing, 50, "broadcasts were heard")


func test_incoming_fire_agrees_on_bolts_that_graze_the_15_m_line() -> void:
	if _skipped():
		return
	# Bolts whose closest approach is within a few micrometres of the line: the 32-bit rounding of GDScript's maths
	# decides about one in ten of them, so only the same precision gives the same counts.
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	var differ: int = 0
	var counted: int = 0
	for trial: int in 400:
		var own_at := Vector3(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0))
		var own_velocity := Vector3(rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0))
		var scan := _scan(PackedVector3Array([own_at]), [Factions.RAIDERS], PackedByteArray([1]))
		for b: int in 4:
			var along := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			var side: Vector3 = along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
			var miss: float = ContactScan.INCOMING_MISS_M + rng.randf_range(-5.0e-6, 5.0e-6)
			scan._bolt_positions.append(own_at + side * miss - along * rng.randf_range(100.0, 700.0))
			scan._bolt_velocities.append(own_velocity + along * rng.randf_range(400.0, 600.0))
			scan._bolt_factions.append(Factions.EARTH_ALLIANCE)
			scan._bolt_shooters.append(0)
		var native: int = scan.incoming_fire(1000, own_at, own_velocity, Factions.RAIDERS)
		scan.use_native = false
		var script: int = scan.incoming_fire(1000, own_at, own_velocity, Factions.RAIDERS)
		counted += script
		if native != script:
			differ += 1
	gut.p("400 ships, 1 600 grazing bolts: %d counted as incoming, %d ships with a different count" % [counted, differ])
	assert_eq(differ, 0, "the same count for every ship")
	assert_between(counted, 200, 1400, "the bolts straddle the line")


func test_k_of_zero_or_less_cuts_nothing_on_both_paths() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var scan := _world(rng, 60, 0)
	var own_at: Vector3 = scan._positions[4]
	var faction: StringName = scan._factions[4]
	for k: int in [0, -3]:
		var answers: Array = []
		for native: bool in [true, false]:
			scan.use_native = native
			answers.append(scan.nearest_for(1004, own_at, faction, k))
		scan.use_native = false
		var every: Array[Contact] = scan.contacts_for(1004, own_at, faction)
		assert_gt(every.size(), 12, "a crowd that k 12 would cut")
		assert_true(_same(answers[0], every), "k %d, native: contacts_for's list" % k)
		assert_true(_same(answers[1], every), "k %d, GDScript: contacts_for's list" % k)
		scan.use_native = true
		var raw: PackedInt32Array = scan._native().nearest(1004, own_at, faction, k, ContactScan.SENSOR_RANGE_M)
		assert_eq(raw.size(), every.size(), "k %d: the field itself cuts nothing and adds no marker" % k)


func test_a_query_visits_only_the_cells_its_range_reaches() -> void:
	if _skipped():
		return
	# Spread's shape: groups of 12, 20 km apart, so every body but its own group is out of range.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n: int = SPREAD_GROUPS * GROUP_SIZE
	var positions := PackedVector3Array()
	var factions: Array[StringName] = []
	var ships := PackedByteArray()
	for i: int in n:
		positions.append(Vector3(float(i / GROUP_SIZE) * GROUP_SPACING_M, 0.0, 0.0)
				+ Vector3(rng.randf_range(-1000.0, 1000.0), rng.randf_range(-1000.0, 1000.0), rng.randf_range(-1000.0, 1000.0)))
		factions.append(Factions.RAIDERS if i % 2 == 0 else Factions.EARTH_ALLIANCE)
		ships.append(1)
	var scan := _scan(positions, factions, ships)
	var worst: int = 0
	for i: int in n:
		scan.use_native = true
		var nearest: Array[Contact] = scan.nearest_for(1000 + i, positions[i], factions[i], 12)
		worst = maxi(worst, scan.native_visits())
		var contacts: Array[Contact] = scan.contacts_for(1000 + i, positions[i], factions[i])
		worst = maxi(worst, scan.native_visits())
		scan.use_native = false
		assert_true(_same(nearest, scan.nearest_for(1000 + i, positions[i], factions[i], 12)), "body %d: nearest" % i)
		assert_true(_same(contacts, scan.contacts_for(1000 + i, positions[i], factions[i])), "body %d: contacts" % i)
	gut.p("worst bodies visited by one query: %d of %d" % [worst, n])
	assert_between(worst, GROUP_SIZE, 2 * GROUP_SIZE, "a query tests its own group, not the %d bodies of the whole world" % n)


func test_perf_native_flips_the_path_live() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var scan := _world(rng, 80, 0)
	var own_at: Vector3 = scan._positions[5]
	var before: Array[Contact] = scan.nearest_for(1005, own_at, scan._factions[5], 12)
	assert_eq(scan.path(), &"native")
	Settings.set_value(&"perf_native", false)
	assert_eq(scan.path(), &"gdscript", "an existing scan follows the setting at once")
	assert_eq(scan.native_visits(), -1, "no native work count on the GDScript path")
	assert_true(_same(scan.nearest_for(1005, own_at, scan._factions[5], 12), before), "the same answer from GDScript")
	Settings.set_value(&"perf_native", true)
	assert_eq(scan.path(), &"native", "and back")
	assert_true(_same(scan.nearest_for(1005, own_at, scan._factions[5], 12), before))


func test_a_freed_body_is_noticed_on_both_paths() -> void:
	if _skipped():
		return
	var alive := Node.new()
	var doomed := Node.new()
	var scan := _scan(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)]), [Factions.RAIDERS, Factions.RAIDERS],
			PackedByteArray([1, 1]))
	scan._body_ids = PackedInt64Array([alive.get_instance_id(), doomed.get_instance_id()])
	for native: bool in [true, false]:
		scan.use_native = native
		assert_true(scan._bodies_alive(), "both exist (%s)" % scan.path())
	doomed.free()
	for native: bool in [true, false]:
		scan.use_native = native
		assert_false(scan._bodies_alive(), "one was freed (%s)" % scan.path())
	alive.free()


# The arguments of a valid `load` of three bodies and one bolt; a test replaces one entry to break it.
static func _load_args() -> Dictionary:
	var factions: Array[StringName] = [Factions.RAIDERS, Factions.EARTH_ALLIANCE, Factions.RAIDERS]
	var bolt_factions: Array[StringName] = [Factions.EARTH_ALLIANCE]
	return {
		"body_ids": PackedInt64Array([1000, 1001, 1002]),
		"positions": PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(20, 0, 0)]),
		"factions": factions,
		"is_ship": PackedByteArray([1, 1, 1]),
		"reach": PackedFloat64Array(),
		"bolt_positions": PackedVector3Array([Vector3(0, 0, 100)]),
		"bolt_velocities": PackedVector3Array([Vector3(0, 0, -300)]),
		"bolt_factions": bolt_factions,
		"bolt_shooters": PackedInt64Array([0]),
	}


static func _load_raw(field: Object, args: Dictionary) -> Variant:
	return field.load(args["body_ids"], args["positions"], args["factions"], args["is_ship"], args["reach"],
			args["bolt_positions"], args["bolt_velocities"], args["bolt_factions"], args["bolt_shooters"],
			ContactScan.SENSOR_RANGE_M)


func test_a_huge_finite_range_gives_the_same_answers_on_both_paths_and_finishes_quickly() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var n: int = 120
	var scan := _world(rng, n, 0)
	var own_at: Vector3 = scan._positions[7]
	var faction: StringName = scan._factions[7]
	# Past 2^31 cells of 5 km on every axis the box's cell count no longer fits a 64-bit product.
	for range_m: float in [1.0e13, 1.0e14, 1.0e30, 1.0e300]:
		var started: int = Time.get_ticks_msec()
		var answers: Array = []
		for native: bool in [true, false]:
			scan.use_native = native
			answers.append([scan.contacts_for(1007, own_at, faction, range_m),
					scan.nearest_for(1007, own_at, faction, 12, Callable(), range_m)])
			if native:
				assert_eq(scan.native_visits(), n, "range %s: too big a box to enumerate, so every body is tested" % range_m)
		assert_lt(Time.get_ticks_msec() - started, 2000, "range %s: finishes quickly" % range_m)
		assert_eq((answers[1][0] as Array).size(), n - 1, "range %s: GDScript sees every other body" % range_m)
		assert_true(_same(answers[0][0], answers[1][0]), "range %s: contacts_for" % range_m)
		assert_true(_same(answers[0][1], answers[1][1]), "range %s: nearest_for" % range_m)


func test_a_load_with_mismatched_array_lengths_is_rejected_and_the_field_answers_nothing() -> void:
	if _skipped():
		return
	var control: Object = NativeLib.instantiate(ContactScan.NATIVE_CLASS)
	assert_eq(_load_raw(control, _load_args()), true, "a consistent load is taken")
	assert_eq(control.contacts(1000, Vector3.ZERO, 5000.0).size(), 2, "and answers")
	var cases: Dictionary = {
		"positions short": ["positions", PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)])],
		"positions long": ["positions", PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3.ONE])],
		"factions short": ["factions", [Factions.RAIDERS] as Array[StringName]],
		"is_ship short": ["is_ship", PackedByteArray([1])],
		"reach wrong": ["reach", PackedFloat64Array([1.0, 2.0])],
		"body ids short": ["body_ids", PackedInt64Array([1000])],
		"bolt velocities short": ["bolt_velocities", PackedVector3Array()],
		"bolt factions long": ["bolt_factions", [Factions.RAIDERS, Factions.RAIDERS] as Array[StringName]],
		"bolt shooters long": ["bolt_shooters", PackedInt64Array([0, 0])],
	}
	for label: String in cases:
		var args: Dictionary = _load_args()
		args[cases[label][0]] = cases[label][1]
		var field: Object = NativeLib.instantiate(ContactScan.NATIVE_CLASS)
		_load_raw(field, _load_args())  # a scan the field already holds must be dropped too
		assert_eq(_load_raw(field, args), false, "%s: the load is rejected" % label)
		assert_engine_error("lengths", "%s: one error says why" % label)
		assert_eq(field.contacts(1000, Vector3.ZERO, 5000.0).size(), 0, "%s: no contacts" % label)
		assert_eq(field.nearest(1000, Vector3.ZERO, Factions.RAIDERS, 1, 5000.0).size(), 0, "%s: no nearest" % label)
		assert_eq(field.broadcasts(1000, Vector3.ZERO, 0.0).size(), 0, "%s: no broadcasts" % label)
		assert_eq(field.incoming(1000, Vector3.ZERO, Vector3.ZERO, Factions.RAIDERS), 0, "%s: no incoming fire" % label)
		assert_eq(field.factions().size(), 0, "%s: no factions" % label)
		assert_true(field.bodies_alive(), "%s: nothing to be freed" % label)


func test_the_facade_falls_back_to_gdscript_for_a_scan_the_field_rejects() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var scan := _world(rng, 50, 0)
	scan._is_ship.append(1)  # one flag too many: the field refuses it, GDScript never reads it
	var own_at: Vector3 = scan._positions[3]
	var faction: StringName = scan._factions[3]
	var found: Array[Contact] = scan.nearest_for(1003, own_at, faction, 12)
	assert_engine_error("lengths", "the field says why it refused")
	assert_eq(scan.path(), &"gdscript", "the scan answers from GDScript")
	assert_eq(scan.native_visits(), -1, "and has no native work count")
	assert_gt(found.size(), 0, "the query still answered")
	scan.use_native = false
	assert_true(_same(found, scan.nearest_for(1003, own_at, faction, 12)), "the same as the GDScript path")
	var expected_fire: int = scan.incoming_fire(1003, own_at, Vector3.ZERO, faction)
	var expected_contacts: Array[Contact] = scan.contacts_for(1003, own_at, faction)
	scan.use_native = true
	assert_eq(scan.path(), &"gdscript", "the refusal sticks for this scan")
	assert_eq(scan.incoming_fire(1003, own_at, Vector3.ZERO, faction), expected_fire, "incoming_fire still answers")
	assert_true(_same(scan.contacts_for(1003, own_at, faction), expected_contacts), "contacts_for still answers")
	assert_true(scan._bodies_alive() == false, "the freed-body check runs without the field (these ids are not nodes)")


func test_a_negative_range_acts_as_its_magnitude_on_both_paths() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var scan := _world(rng, 80, 0)
	var own_at: Vector3 = scan._positions[4]
	var faction: StringName = scan._factions[4]
	for magnitude: float in [2500.0, 5000.0, 9000.0]:
		var answers: Array = []
		for native: bool in [true, false]:
			scan.use_native = native
			answers.append([scan.contacts_for(1004, own_at, faction, -magnitude),
					scan.nearest_for(1004, own_at, faction, 12, Callable(), -magnitude)])
		assert_gt((answers[1][0] as Array).size(), 0, "range -%s: something is in range" % magnitude)
		assert_true(_same(answers[0][0], answers[1][0]), "range -%s: contacts_for" % magnitude)
		assert_true(_same(answers[0][1], answers[1][1]), "range -%s: nearest_for" % magnitude)
		scan.use_native = true
		assert_true(_same(answers[0][0], scan.contacts_for(1004, own_at, faction, magnitude)), "range -%s: as +%s" % [magnitude, magnitude])


func test_more_than_256_factions_are_told_apart() -> void:
	if _skipped():
		return
	# Bodies f0 to f299 along a line; only f0 and f290 are hostile. A faction index kept in a byte would read f290 as f34.
	var count: int = 300
	var ids: Array = []
	for i: int in count:
		ids.append({"id": "f%d" % i, "name": "F%d" % i})
	var table_dict: Dictionary = {"factions": ids,
			"relations": [{"a": "f0", "b": "f290", "relation": "hostile"}], "default": "neutral"}
	var parsed: Dictionary = FactionTable.from_dict(table_dict)
	assert_true(parsed["ok"], "the 300 faction table is valid: %s" % parsed["error"])
	Factions.use_table(parsed["table"])
	var positions := PackedVector3Array()
	var factions: Array[StringName] = []
	var ships := PackedByteArray()
	for i: int in count:
		positions.append(Vector3(float(i) * 10.0, 0.0, 0.0))
		factions.append(StringName("f%d" % i))
		ships.append(1)
	var scan := _scan(positions, factions, ships)
	scan._bolt_positions.append(Vector3(0.0, 0.0, 100.0))
	scan._bolt_velocities.append(Vector3(0.0, 0.0, -300.0))
	scan._bolt_factions.append(&"f290")
	scan._bolt_shooters.append(0)
	var answers: Array = []
	for native: bool in [true, false]:
		scan.use_native = native
		answers.append([scan.nearest_for(1000, Vector3.ZERO, &"f0", 3), scan.incoming_fire(1000, Vector3.ZERO, Vector3.ZERO, &"f0")])
	assert_eq(answers[1][1], 1, "GDScript: the f290 bolt is hostile to f0")
	assert_eq(answers[0][1], 1, "native: the same")
	assert_true(_same(answers[0][0], answers[1][0]), "nearest_for: the same contacts")
	assert_true(_ids(answers[0][0]).has(5290), "the cut keeps the nearest hostile ship, body 290")
	scan.use_native = true
	assert_eq(scan._native().factions().size(), count, "the field lists every faction")


func test_a_hostility_row_too_short_for_a_faction_counts_it_as_not_hostile() -> void:
	if _skipped():
		return
	var args: Dictionary = _load_args()
	args["positions"] = PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3(30, 0, 0)])
	args["body_ids"] = PackedInt64Array([1000, 1001, 1002, 1003])
	args["is_ship"] = PackedByteArray([1, 1, 1, 1])
	var factions: Array[StringName] = [&"a", &"b", &"c", &"b"]
	args["factions"] = factions
	var bolt_factions: Array[StringName] = [&"c"]
	args["bolt_factions"] = bolt_factions
	var field: Object = NativeLib.instantiate(ContactScan.NATIVE_CLASS)
	_load_raw(field, args)
	assert_eq(field.factions(), factions.slice(0, 3) as Array[StringName], "a, b, c in first-seen order")
	field.set_hostile_row(&"a", PackedByteArray([0, 0]))  # nothing for c at index 2
	assert_eq(field.incoming(1000, Vector3.ZERO, Vector3.ZERO, &"a"), 0, "the bolt of c is not hostile")
	assert_eq(field.nearest(1000, Vector3.ZERO, &"a", 1, 5000.0), PackedInt32Array([1, -1]), "no hostile ship is added")
	field.set_hostile_row(&"a", PackedByteArray([0, 0, 1]))
	assert_eq(field.incoming(1000, Vector3.ZERO, Vector3.ZERO, &"a"), 1, "with c in the row the bolt counts")
	assert_eq(field.nearest(1000, Vector3.ZERO, &"a", 1, 5000.0), PackedInt32Array([1, 2, -1]), "and c's ship joins the cut")
