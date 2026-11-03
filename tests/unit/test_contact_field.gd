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
		var near: Vector3 = positions[rng.randi_range(0, n - 1)]
		var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		direction = direction.normalized() if direction.length_squared() > 1e-6 else Vector3.FORWARD
		var at: Vector3 = near + direction * rng.randf_range(0.0, 1200.0)
		var velocity := Vector3(rng.randf_range(-600.0, 600.0), rng.randf_range(-600.0, 600.0), rng.randf_range(-600.0, 600.0))
		if rng.randf() < 0.4:
			velocity = -direction * rng.randf_range(300.0, 600.0) + Vector3(rng.randf_range(-8.0, 8.0), 0.0, 0.0)
		scan._bolt_positions.append(at)
		scan._bolt_velocities.append(velocity)
		scan._bolt_factions.append(FACTIONS[rng.randi_range(0, FACTIONS.size() - 1)])
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
	for world: int in WORLDS:
		var n: int = 1 if world == 0 else (MAX_BODIES if world == 1 else rng.randi_range(1, MAX_BODIES))
		var shape: int = world % 4
		var scan := _world(rng, n, shape)
		var heard := _broadcasters(rng, scan)
		assert_eq(scan.path(), &"native", "world %d: the native path" % world)
		for q: int in mini(QUERIES_PER_WORLD, n + 2):
			var at_index: int = rng.randi_range(0, n - 1)
			var own_id: int = 1000 + at_index
			var own_at: Vector3 = scan._positions[at_index]
			if q == n:
				own_id = -1  # a ship the scan does not know
			elif q == n + 1 or rng.randf() < 0.2:
				own_at += Vector3(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0))
			var faction: StringName = FACTIONS[rng.randi_range(0, FACTIONS.size() - 1)] if rng.randf() < 0.3 \
					else scan._factions[at_index]
			var velocity := Vector3(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
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
	gut.p("%d queries compared over %d worlds, %d of them cut by nearest-k" % [compared, WORLDS, cut])
	assert_gt(cut, 50, "the nearest-k cut, the nearest hostile and the keeper were exercised")


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
