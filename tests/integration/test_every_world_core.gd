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
	# A world with no ship pools: the core's rows hold the player and the buoys as their nodes say.
	await _load(ScenarioLoader.FREE_FLIGHT_PATH)
	var scan: ContactScan = ContactScan.shared(get_tree())
	var bodies: Array[Node3D] = [main.ship]
	for buoy: NavBuoy in main.buoys:
		bodies.append(buoy)
	assert_eq(scan._body_ids.size(), bodies.size(), "one row per body, nothing else")
	for body: Node3D in bodies:
		var i: int = scan._body_ids.find(body.get_instance_id())
		assert_true(i >= 0, "%s has a row" % body.name)
		if i < 0:
			continue
		assert_eq(scan._positions[i], body.global_position, "%s: its position" % body.name)
		var marker := body.find_children("*", "Targetable", false, false)[0] as Targetable
		assert_eq(scan._factions[i], marker.faction, "%s: its faction" % body.name)
		assert_eq(scan._radii[i], Damageable.of(body).bounding_radius, "%s: its radius" % body.name)


func test_a_bare_world_attaches_its_core() -> void:
	var world := WorldFrame.new()
	add_child_autofree(world)
	var sim: SimCore = world.get_node_or_null(NodePath(SimCore.NODE_NAME)) as SimCore
	assert_not_null(sim, "the world made its core as it became ready")
	assert_eq(SimCore.attach(world), sim, "attaching again finds it")
	assert_eq(SimCore.for_tree(get_tree()), sim)


func test_the_older_world_keeps_its_core_when_a_newer_one_leaves() -> void:
	var first := WorldFrame.new()
	add_child_autofree(first)
	var second := WorldFrame.new()
	add_child(second)
	assert_eq(SimCore.for_tree(get_tree()), second.get_node(NodePath(SimCore.NODE_NAME)), "the newest core is read")
	second.free()
	assert_eq(SimCore.for_tree(get_tree()), first.get_node(NodePath(SimCore.NODE_NAME)), "then the one left")


func _load(path: String) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = path
	add_child(main)
	for i: int in 3:
		await get_tree().physics_frame
