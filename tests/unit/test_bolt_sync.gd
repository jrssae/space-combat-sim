extends GutTest
## The bolts' read at the core's two sync points (M4-T34, architecture §17.13). `ScsBoltSync` fills the core's bolt table
## for less than the core's own read, which stays the reference behind `perf_native_bolt_sync`: on a seeded crowd of bolts
## (plain bolts, missiles and beams; on their launch tick or flown; spent, freed and new ones each round) both give the same
## bolt rows bit for bit at the first sync and at the hit resolver's. Skips, saying why, when the native library is not built.

const PROJECTILE_SCENE: PackedScene = preload("res://src/weapons/projectile.tscn")
const SIDES: Array[StringName] = [Factions.RAIDERS, Factions.EARTH_ALLIANCE, Factions.NEUTRAL, &"drifters"]
const DELTA: float = 1.0 / 60.0
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_bolt_sync"]
const NO_NODES: Array[Node] = []

var world: WorldFrame
var projectiles: Node3D
var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"perf_native_core", true)
	ContactScan.invalidate()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func after_each() -> void:
	ContactScan.invalidate()
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])


func _skipped() -> bool:
	if NativeLib.has_class(SimCore.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no core to test")
	return true


# A bolt as the game launches it; `flown` gives it one tick of flight, as `_physics_process` would.
func _bolt(rng: RandomNumberGenerator, flown: bool) -> Projectile:
	var bolt := PROJECTILE_SCENE.instantiate() as Projectile
	bolt.faction = SIDES[rng.randi_range(0, 3)]
	bolt.shooter_id = rng.randi_range(1, 1 << 30)
	bolt.damage = 5.0
	projectiles.add_child(bolt)
	var roll: float = rng.randf()
	bolt.set_kind(Projectile.KIND_MISSILE if roll < 0.1 else (Projectile.KIND_BEAM if roll < 0.15 else Projectile.KIND_BOLT))
	var at := Vector3(rng.randf_range(-9000.0, 9000.0), rng.randf_range(-3000.0, 3000.0), rng.randf_range(-9000.0, 9000.0))
	var velocity := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() \
			* rng.randf_range(200.0, 1200.0)
	bolt.launch(at, velocity, 0.0)
	if flown:
		_fly(bolt)
	return bolt


# One tick of a bolt's flight by hand, as `Projectile._physics_process` does it.
func _fly(bolt: Projectile) -> void:
	bolt.last_step = bolt.velocity * DELTA
	bolt.global_position += bolt.last_step


func _group() -> Array[Node]:
	return get_tree().get_nodes_in_group(Projectile.GROUP)


# Fails, naming the first column that differs, unless both cores hold the same bolt rows.
func _assert_same_bolts(reference: Object, fast: Object, label: String) -> void:
	var a: Array = reference.bolt_columns() + reference.bolt_scan()
	var b: Array = fast.bolt_columns() + fast.bolt_scan()
	for c: int in a.size():
		if a[c] != b[c]:
			fail_test("%s: bolt column %d differs (sizes %d and %d)" % [label, c, a[c].size(), b[c].size()])
			return
	pass_test("%s: the same %d bolt rows" % [label, reference.bolt_count()])


func test_the_reader_fills_the_same_bolt_rows_as_the_core() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 34
	var reference: Object = NativeLib.instantiate(SimCore.NATIVE_CLASS)
	var fast: Object = NativeLib.instantiate(SimCore.NATIVE_CLASS)
	var reader: Object = NativeLib.instantiate(SimCore.BOLT_SYNC_CLASS)
	assert_not_null(reader, "the library has the bolt reader")
	if reader == null:
		return
	for i: int in 60:
		_bolt(rng, i % 2 == 0)
	var spent_seen: bool = false
	for round: int in 8:
		var tick: int = 100 + round
		# The first sync: positions and velocities, the scan's.
		reference.sync_in(_group(), tick, DELTA)
		fast.sync_in(NO_NODES, tick, DELTA)
		reader.read(fast, _group(), tick, DELTA, true, false)
		_assert_same_bolts(reference, fast, "round %d, first sync" % round)
		# The tick goes on: every bolt flies, some are spent (queued, still in the group), a few are launched.
		for node: Node in _group():
			var bolt := node as Projectile
			if not bolt.is_queued_for_deletion():
				_fly(bolt)
			if rng.randf() < 0.1:
				bolt.spend()
				spent_seen = true
		for i: int in rng.randi_range(0, 6):
			_bolt(rng, false)
		# The hit resolver's sync: positions and last steps.
		reference.sync_bolts(_group(), DELTA)
		fast.sync_bolts(NO_NODES, DELTA)
		reader.read(fast, _group(), tick, DELTA, false, true)
		_assert_same_bolts(reference, fast, "round %d, the hit resolver's sync" % round)
		# The frame ends: the spent bolts are freed.
		for node: Node in _group():
			if node.is_queued_for_deletion():
				node.free()
	assert_true(spent_seen, "spent bolts were in the group in some round")
	assert_eq(reader.known_count(), _group().size(), "the reader forgets the bolts that left")


func test_sim_core_reads_the_bolts_through_the_reader_and_counts_its_calls() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	for i: int in 40:
		_bolt(rng, i % 3 != 0)
	var rows: Array = []
	var calls := PackedInt64Array()
	for on: bool in [false, true]:
		Settings.set_value(&"perf_native_bolt_sync", on)
		var core: SimCore = SimCore.attach(world)
		assert_not_null(core, "a core attaches")
		if core == null:
			return
		assert_eq(core.bolt_path(), &"reader" if on else &"core", "the setting picks the bolt read")
		core.sync_now()
		core.sync_bolts_now()
		core.sync_out_now()
		core.sync_now()
		core.sync_bolts_now()
		core.sync_out_now()
		rows.append(core.core.bolt_columns())
		calls.append(core.engine_calls()[0])
		core.free()
	assert_eq(rows[1], rows[0], "the same bolt rows either way")
	assert_gt(calls[1], 2 * 40, "the reader's calls are counted with the sync's")
	assert_eq(calls[1], calls[0], "and counted as the core counts its own")
