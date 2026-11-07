extends GutTest
## The bolts' read at the core's two sync points (M4-T34, architecture §17.13). `ScsBoltSync` fills the core's bolt table
## for less than the core's own read did: on a seeded crowd of bolts (plain bolts, missiles and beams; on their launch tick
## or flown; spent, freed and new ones each round) it gives the bolt rows that read gave, bit for bit, at the first sync and
## at the hit resolver's (recorded in `tests/fixtures/parity/bolt_sync.json` before M4-T37 removed the core's own read and
## `perf_native_bolt_sync`).

const FIXTURE: String = "bolt_sync"
const PROJECTILE_SCENE: PackedScene = preload("res://src/weapons/projectile.tscn")
const SIDES: Array[StringName] = [Factions.RAIDERS, Factions.EARTH_ALLIANCE, Factions.NEUTRAL, &"drifters"]
const DELTA: float = 1.0 / 60.0
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core"]

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


# The bolt rows a core holds, without the bolts' instance ids (which differ between runs): the columns and the scan's arrays.
static func _rows(core: Object) -> Array:
	var columns: Array = core.bolt_columns() + core.bolt_scan()
	columns.remove_at(0)
	return columns


func test_the_reader_fills_the_same_bolt_rows_as_the_core() -> void:
	if _skipped():
		return
	var recorded: Variant = ParityFixture.stored(FIXTURE, "crowd_seed_34")
	var fast: Array = _crowd()
	assert_not_null(recorded, "the core's own read was recorded")
	assert_eq(fast.size(), 16, "two syncs a round for eight rounds")
	assert_eq(ParityFixture.encode(fast), recorded, "the reader fills the bolt rows the core's own read filled, every sync")


# The seeded crowd of bolts (seed 34) over eight rounds, read by the reader: a digest of the bolt rows at each round's two
# syncs.
func _crowd() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 34
	var core: Object = NativeLib.instantiate(SimCore.NATIVE_CLASS)
	var reader: Object = NativeLib.instantiate(SimCore.BOLT_SYNC_CLASS)
	for i: int in 60:
		_bolt(rng, i % 2 == 0)
	var spent_seen: bool = false
	var out: Array = []
	for round: int in 8:
		var tick: int = 100 + round
		# The first sync: positions and velocities, the scan's.
		core.sync_in(tick, DELTA)
		reader.read(core, _group(), tick, DELTA, true, false)
		out.append(ParityFixture.digest(_rows(core)))
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
		core.sync_bolts()
		reader.read(core, _group(), tick, DELTA, false, true)
		out.append(ParityFixture.digest(_rows(core)))
		# The frame ends: the spent bolts are freed.
		for node: Node in _group():
			if node.is_queued_for_deletion():
				node.free()
	assert_true(spent_seen, "spent bolts were in the group in some round")
	assert_eq(reader.known_count(), _group().size(), "the reader forgets the bolts that left")
	for node: Node in _group():
		node.free()
	return out


func test_sim_core_reads_the_bolts_through_the_reader_and_counts_its_calls() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	for i: int in 40:
		_bolt(rng, i % 3 != 0)
	var core: SimCore = SimCore.attach(world)
	assert_not_null(core, "a core attaches")
	if core == null:
		return
	core.sync_now()
	core.sync_bolts_now()
	core.sync_out_now()
	core.sync_now()
	core.sync_bolts_now()
	core.sync_out_now()
	assert_eq((core.core.bolt_columns()[0] as PackedInt64Array).size(), 40, "every bolt has a row")
	assert_gt(core.engine_calls()[0], 2 * 40, "the reader's calls are counted with the sync's")
	core.free()
