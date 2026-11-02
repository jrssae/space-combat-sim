extends GutTest
## AC28 in play (M3-T19, Q22): every ship carries one splat node per level it can draw and shows exactly one; across a sweep
## from 40 m to 20 km and back with 13 ships the splat-node count never changes and no node's resource changes (a change of
## resource is what makes GDGS rebuild every buffer; headless runs have no GDGS backend to count rebuilds in, so the counters
## themselves, `render.gdgs_rebuilds` and `render.gdgs_splat_uploads`, are read on the GPU: M3-T20), each ship steps through its
## chain once each way; the `lod` provider and command and `settings.splat_lod_bias`.

var main: Main


var _size_backup: Vector2i = Vector2i.ZERO


func before_each() -> void:
	# Headless windows are 64 x 64 px; the rule is about a real screen, so the test gives the root window 1080p.
	_size_backup = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	DebugConsole.registry.execute("despawn all")


func after_each() -> void:
	get_tree().root.size = _size_backup
	DebugConsole.flags.invulnerable = false
	Settings.set_value(&"splat_lod_bias", 0.0)


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


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


# Thirteen ships in play: nine raiders and four allies, idle, out of the way of each other.
func _fleet() -> Array[Combatant]:
	var out: Array[Combatant] = []
	var at: UniversePos = main.world.to_universe(main.ship.global_position)
	for i: int in 9:
		out.append(main.ships.acquire("RAIDER %d" % (i + 1), at.plus_local(Vector3(300.0 * i, 3000.0, 0.0)), Basis.IDENTITY,
				Vector3.ZERO, null, ShipPool.DEFAULT_TYPE))
	for i: int in 4:
		out.append(main.ships.acquire("ALPHA %d" % (i + 2), at.plus_local(Vector3(300.0 * i, -3000.0, 0.0)), Basis.IDENTITY,
				Vector3.ZERO, null, ShipPool.ALLY_TYPE))
	return out


# Puts every ship `distance_m` from the camera, each on its own bearing round the view axis.
func _place(fleet: Array[Combatant], distance_m: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var forward: Vector3 = -camera.global_basis.z
	for i: int in fleet.size():
		var angle: float = TAU * float(i) / float(fleet.size())
		var dir: Vector3 = (forward + 0.35 * (camera.global_basis.x * cos(angle) + camera.global_basis.y * sin(angle))).normalized()
		fleet[i].ship.global_position = camera.global_position + dir * distance_m
		fleet[i].ship.linear_velocity = Vector3.ZERO


func test_every_ship_carries_one_node_per_level_and_shows_one() -> void:
	var fleet: Array[Combatant] = _fleet()
	await get_tree().process_frame
	assert_eq(main.ship.lod_levels(), PackedInt32Array([-1, 0, 1, 2, 3]), "the player: hero, LOD0-LOD3 (M3-T24)")
	assert_eq(fleet[0].ship.lod_levels(), PackedInt32Array([0, 1, 2, 3]), "a raider: LOD0-LOD3")
	assert_eq(fleet[9].ship.lod_levels(), PackedInt32Array([1, 2, 3]), "an ally: LOD1-LOD3")
	for c: Combatant in fleet:
		assert_eq(_visible_levels(c.ship), 1, "%s shows one level" % c.display_name)
		assert_not_null(c.ship.get_node_or_null(^"LodSwitcher"))


func test_a_sweep_changes_levels_by_visibility_only_once_each_way() -> void:
	var fleet: Array[Combatant] = _fleet()
	var nodes_before: Array[GaussianSplatNode] = _splat_nodes(get_tree().root, [] as Array[GaussianSplatNode])
	var resources: Dictionary = {}
	for n: GaussianSplatNode in nodes_before:
		resources[n.get_instance_id()] = n.gaussian
	var seen: Dictionary = {}  # ship name -> the levels it went through, in order
	assert_eq(get_viewport().get_visible_rect().size.y, 1080.0, "the test's 1080p viewport")
	var steps: int = 200
	for leg: int in 2:
		for i: int in steps + 1:
			var t: float = float(i) / float(steps)
			if leg == 1:
				t = 1.0 - t
			_place(fleet, 40.0 * pow(20000.0 / 40.0, t))  # 40 m to 20 km, evenly in log range
			await get_tree().process_frame
			for c: Combatant in fleet:
				var levels: Array = seen.get(c.display_name, [])
				if levels.is_empty() or levels[levels.size() - 1] != c.ship.lod_level():
					levels.append(c.ship.lod_level())
				seen[c.display_name] = levels
	var nodes_after: Array[GaussianSplatNode] = _splat_nodes(get_tree().root, [] as Array[GaussianSplatNode])
	assert_eq(nodes_after.size(), nodes_before.size(), "the splat-node count never changed")
	var swapped: int = 0
	for n: GaussianSplatNode in nodes_after:
		swapped += 1 if resources.get(n.get_instance_id()) != n.gaussian else 0
	assert_eq(swapped, 0, "no node's resource changed: nothing for GDGS to rebuild")
	gut.p("lod sweep: RAIDER 1 %s, ALPHA 2 %s" % [str(seen["RAIDER 1"]), str(seen["ALPHA 2"])])
	for c: Combatant in fleet:
		var levels: Array = seen[c.display_name]
		var chain: Array = Array(c.ship.lod_levels())
		var out_and_back: Array = []
		for l: int in chain.slice(chain.find(levels[0])):
			out_and_back.append(l)
		var back: Array = out_and_back.duplicate()
		back.reverse()
		out_and_back.append_array(back.slice(1))
		assert_eq(levels, out_and_back, "%s: every boundary once out, once back" % c.display_name)
		assert_eq(_visible_levels(c.ship), 1)


func test_the_console_forces_levels_and_reads_them() -> void:
	var fleet: Array[Combatant] = _fleet()
	_place(fleet, 3000.0)
	await get_tree().process_frame
	assert_true(_exec("lod all 1").ok)
	assert_eq(fleet[0].ship.lod_level(), 1)
	assert_eq(fleet[9].ship.lod_level(), 1)
	assert_string_contains(str(DebugConsole.registry.read("lod.levels")["value"]), "RAIDER 1 1*")
	assert_gt(int(DebugConsole.registry.read("lod.visible_splats")["value"]), 0)
	assert_true(_exec("lod raider 3 0").ok, "a ship by name")
	assert_eq(fleet[2].ship.lod_level(), 0)
	assert_true(_exec("lod all auto").ok)
	await get_tree().process_frame
	assert_eq(fleet[0].ship.lod_level(), 3, "back to its size on screen: far")
	assert_false(_exec("lod all 9").ok)
	assert_false(_exec("lod NOBODY 1").ok)


func test_the_console_sees_the_ships_in_play_while_paused() -> void:
	var fleet: Array[Combatant] = _fleet()
	_place(fleet, 3000.0)
	await get_tree().process_frame
	var in_play: int = main.ships.alive().size() + 1  # and the player
	get_tree().paused = true
	var result: ConsoleResult = _exec("lod all 1")
	assert_true(result.ok, result.error)
	assert_eq(fleet[0].ship.lod_level(), 1, "forced while paused")
	assert_eq((DebugConsole.registry.read("lod.levels")["value"] as PackedStringArray).size(), in_play, "every ship in play listed")
	assert_gt(int(DebugConsole.registry.read("lod.visible_splats")["value"]), 0)
	main.ships.release(fleet[1])
	assert_eq((DebugConsole.registry.read("lod.levels")["value"] as PackedStringArray).size(), in_play - 1, "a parked ship is not")
	get_tree().paused = false
	assert_true(_exec("lod all auto").ok)


func test_the_bias_shifts_every_level() -> void:
	var fleet: Array[Combatant] = _fleet()
	_place(fleet, 150.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var plain: int = fleet[0].ship.lod_level()
	assert_eq(plain, 1, "150 m on a 1080p screen: LOD1")
	Settings.set_value(&"splat_lod_bias", 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(fleet[0].ship.lod_level(), mini(plain + 1, 3), "one level coarser")
	Settings.set_value(&"splat_lod_bias", -1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(fleet[0].ship.lod_level(), maxi(plain - 1, 0), "one level finer")
