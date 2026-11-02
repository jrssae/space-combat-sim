extends GutTest
## AC33 in play (M3-T24, Q23): the player's own Starfury, and nobody else, carries the hero splat level in front of its LOD chain
## (level -1, from 400 px); the other levels are as they were, the node count is fixed once built, the hero counts in the visible
## splats, and the hero plus AC19's fight fits `settings.splat_budget`. The hero's import and VRAM cost are measured on the GPU.

const HERO_NODE: String = "HullSplatsHero"
const DOGFIGHT_PATH: String = "res://data/scenarios/dogfight.json"
const ALLY_COUNT: int = 4  # the dogfight's wing, one more than AC19's three
const RAIDER_COUNT: int = 9
const BUOY_COUNT: int = 5  # the most any scenario places

var main: Main
var _size_backup: Vector2i = Vector2i.ZERO


func before_each() -> void:
	_size_backup = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	get_tree().root.size = _size_backup
	DebugConsole.flags.invulnerable = false
	Settings.set_value(&"splat_hero", true)
	Settings.set_value(&"splat_budget", 2000000)
	Settings.set_value(&"splat_lod_bias", 0.0)


func _start(scenario: String = "") -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	if not scenario.is_empty():
		main.scenario_path = scenario
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _manifest(asset_id: String) -> Dictionary:
	return SplatLod.read_manifest(asset_id)


func _lod_splats(asset_id: String, level: int) -> int:
	return int(SplatLod.entry_for(_manifest(asset_id), level).get("splats", 0))


func _hero_nodes(root: Node) -> Array[Node]:
	return root.find_children(HERO_NODE, "GaussianSplatNode", true, false)


func _splat_nodes(node: Node, out: Array[GaussianSplatNode]) -> Array[GaussianSplatNode]:
	if node is GaussianSplatNode:
		out.append(node as GaussianSplatNode)
	for child: Node in node.get_children():
		_splat_nodes(child, out)
	return out


func _visible_levels(ship: Ship) -> int:
	var n: int = 0
	for child: Node in ship.get_children():
		if child is GaussianSplatNode and (child as GaussianSplatNode).visible:
			n += 1
	return n


# --- who has it ------------------------------------------------------------------------------------------------------


func test_the_player_carries_hero_then_lod0_to_lod3_and_shows_one() -> void:
	await _start()
	var ship: Ship = main.ship
	assert_eq(ship.lod_levels(), PackedInt32Array([-1, 0, 1, 2, 3]))
	var node := ship.get_node_or_null(NodePath(HERO_NODE)) as GaussianSplatNode
	assert_not_null(node, "a splat node of its own")
	assert_eq(node.gaussian.point_count, int(_manifest("starfury_aurora")["hero"]["splats"]), "the generated hero PLY")
	assert_not_null(node.lighting, "with its own lighting records")
	assert_true(node.relight_enabled)
	var counts: PackedInt32Array = ship.lod_splat_counts()
	assert_eq(counts.size(), 5)
	assert_eq(counts[0], node.gaussian.point_count)
	assert_eq(counts[1], _lod_splats("starfury_aurora", 0), "LOD0 is the asset's own")
	assert_eq(_visible_levels(ship), 1, "exactly one level shown")


func test_no_other_ship_loads_the_hero_level() -> void:
	await _start(DOGFIGHT_PATH)
	await get_tree().process_frame
	var heroes: Array[Node] = _hero_nodes(main)
	assert_eq(heroes.size(), 1, "one hero node in the whole game")
	assert_eq(heroes[0].get_parent(), main.ship, "the player's")
	var others: int = 0
	for ship: Node in get_tree().get_nodes_in_group(WorldFrame.SHIFTABLE_GROUP):
		if not (ship is Ship) or ship == main.ship:
			continue
		others += 1
		assert_false((ship as Ship).lod_levels().has(LodSwitcherMath.HERO), "%s has no hero level" % ship.name)
		assert_null(ship.get_node_or_null(NodePath(HERO_NODE)))
	assert_gt(others, 0, "the scenario's allies and raiders were checked")


func test_the_instructor_and_allies_read_a_spec_without_the_flag() -> void:
	for type: StringName in [&"starfury_ally", &"raider_fighter"]:
		assert_false(ShipCatalog.spec_for(type).splat_hero, str(type))
	assert_true(ShipCatalog.spec_for(ShipCatalog.PLAYER_TYPE).splat_hero)


func test_the_setting_off_builds_the_player_without_it() -> void:
	Settings.set_value(&"splat_hero", false)
	await _start()
	assert_eq(main.ship.lod_levels(), PackedInt32Array([0, 1, 2, 3]))
	assert_eq(_hero_nodes(main).size(), 0)


# --- choosing and showing the level -------------------------------------------------------------------------------------


func test_the_hero_is_picked_by_the_ships_size_on_screen_like_any_level() -> void:
	await _start()
	await get_tree().process_frame
	await get_tree().process_frame
	var camera: Camera3D = get_viewport().get_camera_3d()
	var px: float = LodSwitcherMath.projected_px(main.ship.bounding_radius(), camera.global_position.distance_to(main.ship.global_position),
			camera.fov, get_viewport().get_visible_rect().size.y)
	var expected: int = LodSwitcherMath.next_level(px, LodSwitcherMath.NONE, LodSwitcherMath.HERO)
	assert_eq(main.ship.lod_level(), expected, "the camera sees %.0f px" % px)
	gut.p("chase camera: the player is %.0f px across, level %s" % [px, LodSwitcher.level_name(main.ship.lod_level())])


func test_the_console_forces_the_hero_and_names_it() -> void:
	await _start()
	await get_tree().process_frame
	assert_true(_exec("lod player hero").ok)
	assert_eq(main.ship.lod_level(), LodSwitcherMath.HERO)
	assert_true((main.ship.get_node(NodePath(HERO_NODE)) as GaussianSplatNode).visible)
	assert_string_contains(str(DebugConsole.registry.read("lod.levels")["value"]), "PLAYER hero*")
	assert_true(_exec("lod player 2").ok)
	assert_eq(main.ship.lod_level(), 2)
	assert_string_contains(str(DebugConsole.registry.read("lod.levels")["value"]), "PLAYER 2*")
	assert_true(_exec("lod all auto").ok)
	assert_false(_exec("lod all heroic").ok)
	assert_false(_exec("lod all -1").ok, "hero is a word, not a number")


func test_the_hero_counts_in_the_visible_splats_and_nodes_never_change() -> void:
	await _start()
	await get_tree().process_frame
	var before: Array[GaussianSplatNode] = _splat_nodes(get_tree().root, [] as Array[GaussianSplatNode])
	var resources: Dictionary = {}
	for n: GaussianSplatNode in before:
		resources[n.get_instance_id()] = n.gaussian
	var hero_count: int = main.ship.lod_splat_counts()[0]
	_exec("lod player hero")
	assert_gte(int(DebugConsole.registry.read("lod.visible_splats")["value"]), hero_count, "the player's hero is part of the sum")
	for level: String in ["0", "1", "2", "3", "hero", "3", "hero"]:
		_exec("lod player %s" % level)
		await get_tree().process_frame
		assert_eq(_visible_levels(main.ship), 1)
	var after: Array[GaussianSplatNode] = _splat_nodes(get_tree().root, [] as Array[GaussianSplatNode])
	assert_eq(after.size(), before.size(), "no node added or freed")
	var swapped: int = 0
	for n: GaussianSplatNode in after:
		swapped += 1 if resources.get(n.get_instance_id()) != n.gaussian else 0
	assert_eq(swapped, 0, "no resource swapped: nothing for GDGS to rebuild")


func test_over_budget_the_hero_steps_down_to_lod0() -> void:
	await _start()
	await get_tree().process_frame
	var hero_count: int = main.ship.lod_splat_counts()[0]
	var lod0: int = main.ship.lod_splat_counts()[1]
	Settings.set_value(&"splat_budget", hero_count - 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var switcher: LodSwitcher = main.ship.get_node(^"LodSwitcher")
	assert_eq(switcher.wanted, LodSwitcherMath.HERO, "the chase camera asks for the hero")
	assert_eq(switcher.budget_extra, 1)
	assert_eq(main.ship.lod_level(), 0, "over budget the hero steps down to LOD0 (%d splats)" % lod0)


# --- the budget with the fight (AC19) ----------------------------------------------------------------------------------


# The worst case from the real manifests: the hero, the wing and raiders each at their finest level, the sky and the buoys.
func _worst_case_ships(distance_of_hero: float) -> Array:
	var ally_splats := PackedInt32Array([_lod_splats("starfury_aurora", 1), _lod_splats("starfury_aurora", 2), _lod_splats("starfury_aurora", 3)])
	var raider_splats := PackedInt32Array([_lod_splats("raider_fighter", 0), _lod_splats("raider_fighter", 1),
			_lod_splats("raider_fighter", 2), _lod_splats("raider_fighter", 3)])
	var hero_splats := PackedInt32Array([int(_manifest("starfury_aurora")["hero"]["splats"]), _lod_splats("starfury_aurora", 0),
			_lod_splats("starfury_aurora", 1), _lod_splats("starfury_aurora", 2), _lod_splats("starfury_aurora", 3)])
	var ships: Array = [{"wanted": LodSwitcherMath.HERO, "levels": PackedInt32Array([-1, 0, 1, 2, 3]), "splats": hero_splats,
			"distance": distance_of_hero, "forced": false}]
	for i: int in ALLY_COUNT:
		ships.append({"wanted": 1, "levels": PackedInt32Array([1, 2, 3]), "splats": ally_splats, "distance": 150.0 + 40.0 * i, "forced": false})
	for i: int in RAIDER_COUNT:
		ships.append({"wanted": 0, "levels": PackedInt32Array([0, 1, 2, 3]), "splats": raider_splats, "distance": 200.0 + 40.0 * i, "forced": false})
	return ships


func _fixed_splats() -> int:
	return _lod_splats("sky_default", 0) + BUOY_COUNT * _lod_splats("nav_buoy", 0)


func test_the_hero_plus_the_whole_fight_at_its_finest_fits_the_default_budget() -> void:
	var plan: Dictionary = SplatBudgetMath.plan(_worst_case_ships(35.0), _fixed_splats(), int(SettingsSchema.ENTRIES[&"splat_budget"]["default"]))
	assert_true(plan["fits"])
	var none := PackedInt32Array()
	none.resize(1 + ALLY_COUNT + RAIDER_COUNT)
	assert_eq(plan["extra"], none, "nothing needs to step down")
	gut.p("worst case: %d of %d splats (hero %d)" % [plan["total"], int(SettingsSchema.ENTRIES[&"splat_budget"]["default"]), _worst_case_ships(35.0)[0]["splats"][0]])
	assert_lt(float(plan["total"]), float(SettingsSchema.ENTRIES[&"splat_budget"]["default"]) * 0.8, "with margin for the renderer's own overhead")


func test_over_a_tight_budget_the_farthest_ships_give_way_and_the_player_goes_last() -> void:
	var ships: Array = _worst_case_ships(35.0)
	var fixed: int = _fixed_splats()
	var full: int = int(SplatBudgetMath.plan(ships, fixed, 100000000)["total"])
	var plan: Dictionary = SplatBudgetMath.plan(ships, fixed, full - 100000)
	var extra: PackedInt32Array = plan["extra"]
	assert_true(plan["fits"])
	assert_eq(extra[0], 0, "the player's hero is nearest, so it is not touched while others can give")
	var stepped: int = 0
	for i: int in range(1, extra.size()):
		stepped += extra[i]
	assert_gt(stepped, 0)
