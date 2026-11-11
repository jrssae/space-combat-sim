extends GutTest
## M4-T42: every world the game builds attaches the native core, so every hull read is the core's. Free flight has no
## ship pools, so before T42 nothing attached a core there and the resolvers and the scan read the tree their own way.

const SCENARIOS: Array[String] = [
	"res://data/scenarios/free_flight.json",
	"res://data/scenarios/combat_sandbox.json",
	"res://data/scenarios/dogfight.json",
	"res://data/scenarios/instructor_route.json",
]

var main: Main = null


func before_each() -> void:
	get_tree().paused = false


func after_each() -> void:
	get_tree().paused = false
	if main != null and is_instance_valid(main):
		main.free()
	main = null


func test_every_scenario_reads_its_hulls_from_the_core() -> void:
	for path: String in SCENARIOS:
		await _load(path)
		var sim: SimCore = main.world.get_node_or_null(NodePath(SimCore.NODE_NAME)) as SimCore
		assert_not_null(sim, "%s: the world has a core" % path)
		assert_eq(SimCore.for_tree(get_tree()), sim, "%s: the classes read that core" % path)
		assert_eq((main.get_node("Combat/HitResolver") as HitResolver).source(), &"core", "%s: the hit resolver" % path)
		assert_eq((main.get_node("Combat/RamResolver") as RamResolver).source(), &"core", "%s: the ram resolver" % path)
		assert_eq(ContactScan.shared(get_tree()).source(), &"core", "%s: the contact scan" % path)
		main.free()
		main = null


func test_free_flight_rows_are_its_bodies() -> void:
	# A world with no ship pools: the core's rows hold the player, the buoys and the jumpgate (M6-T14) as their nodes say.
	await _load(ScenarioLoader.FREE_FLIGHT_PATH)
	var scan: ContactScan = ContactScan.shared(get_tree())
	var bodies: Array[Node3D] = [main.ship]
	for buoy: NavBuoy in main.buoys:
		bodies.append(buoy)
	for gate: Jumpgate in main.gates.gates:
		bodies.append(gate)
	assert_eq(scan._body_ids.size(), bodies.size(), "one row per body, nothing else")
	for body: Node3D in bodies:
		var i: int = scan._body_ids.find(body.get_instance_id())
		assert_true(i >= 0, "%s has a row" % body.name)
		if i < 0:
			continue
		assert_eq(scan._positions[i], body.global_position, "%s: its position" % body.name)
		var marker := body.find_children("*", "Targetable", false, false)[0] as Targetable
		assert_eq(scan._factions[i], marker.faction, "%s: its faction" % body.name)
		var hull: Damageable = Damageable.of(body)
		assert_eq(scan._radii[i], hull.bounding_radius if hull != null else 0.0, "%s: its radius (none without a hull)" % body.name)


func test_a_bare_world_attaches_its_core() -> void:
	var world := WorldFrame.new()
	add_child_autofree(world)
	var sim: SimCore = world.get_node_or_null(NodePath(SimCore.NODE_NAME)) as SimCore
	assert_not_null(sim, "the world made its core as it became ready")
	assert_eq(SimCore.attach(world), sim, "attaching again finds it")
	assert_eq(SimCore.for_tree(get_tree()), sim)


func test_a_second_world_in_one_tree_is_refused_its_core() -> void:
	# One world per tree (fix round 1): the game only ever has one; a second world's core would be read half-way.
	var first := WorldFrame.new()
	add_child_autofree(first)
	var core: SimCore = first.get_node(NodePath(SimCore.NODE_NAME)) as SimCore
	var second := WorldFrame.new()
	add_child_autofree(second)
	assert_push_error("one world per tree", "the second world is refused, saying why")
	assert_null(second.get_node_or_null(NodePath(SimCore.NODE_NAME)), "and gets no core")
	assert_null(SimCore.attach(second), "attaching it by hand is refused too")
	assert_push_error_count(1, "said once")
	assert_eq(SimCore.for_tree(get_tree()), core, "the first world's core stays the one read")
	first.free()
	assert_null(SimCore.for_tree(get_tree()), "with the first world gone there is no core: nothing takes over")


func test_a_tree_with_no_world_has_nothing_to_resolve() -> void:
	SimCore.no_world_warnings = 0
	assert_null(SimCore.for_tree(get_tree()), "no world, so no core")
	assert_eq(SimCore.no_world_warnings, 0, "nothing to warn about with no bodies")
	var hits := HitResolver.new()
	add_child_autofree(hits)
	var rams := RamResolver.new()
	add_child_autofree(rams)
	var drone := (load("res://tests/fixtures/target_drone.tscn") as PackedScene).instantiate() as TargetDrone
	add_child_autofree(drone)
	hits.resolve(1.0 / 60.0)
	rams.resolve(1.0 / 60.0)
	assert_eq(hits.source(), &"none", "the hit resolver reads nothing")
	assert_eq(hits.hulls_last_tick, 0, "and gathers no hull")
	assert_eq(rams.source(), &"none", "the ram resolver reads nothing")
	assert_eq(rams.hulls_last_tick, 0, "and gathers no hull")
	assert_eq(ContactScan.shared(get_tree())._body_ids.size(), 0, "the scan sees nothing")
	assert_eq(SimCore.no_world_warnings, 1, "one warning says why: bodies but no world, so no core")


func before_all() -> void:
	SimCore.no_world_warnings = 0  # the warning is said once a run; this file checks it


func test_the_flight_batch_says_none_once_the_core_is_gone() -> void:
	var world := WorldFrame.new()
	add_child_autofree(world)
	var ship: Ship = Ship.create(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world)
	world.spawn(ship, world.to_universe(Vector3.ZERO))
	for i: int in 3:
		await get_tree().physics_frame
	var batch: FlightBatch = world.get_node(NodePath(FlightBatch.NODE_NAME)) as FlightBatch
	assert_eq(batch.source(), &"core", "the batch steps from the core")
	world.get_node(NodePath(SimCore.NODE_NAME)).free()
	for i: int in 2:
		await get_tree().physics_frame
	assert_eq(batch.source(), &"none", "with the core gone the batch steps nothing and says so")
	assert_eq(batch._source, &"none", "and keeps no stale source")


func _load(path: String) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = path
	add_child(main)
	for i: int in 3:
		await get_tree().physics_frame
