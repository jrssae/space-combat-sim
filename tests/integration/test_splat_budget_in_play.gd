extends GutTest
## AC29 in play (M3-T20, Q22): over `settings.splat_budget` the `LodSwitcher` steps the farthest visible ships down a level until the
## visible sum fits, counts only ships in view, leaves forced levels alone, keeps its hysteresis state, and warns once when even the
## coarsest everywhere does not fit. Headless runs have no renderer, so the sum is the ships' own (nothing else counts against it).

var main: Main
var _size_backup: Vector2i = Vector2i.ZERO


func before_each() -> void:
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
	Settings.set_value(&"splat_budget", 2000000)
	DebugConsole.registry.execute("lod all auto")


func _raiders(count: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	var at: UniversePos = main.world.to_universe(main.ship.global_position)
	for i: int in count:
		out.append(main.ships.acquire("RAIDER %d" % (i + 1), at.plus_local(Vector3(300.0 * i, 3000.0, 0.0)), Basis.IDENTITY,
				Vector3.ZERO, null, ShipPool.DEFAULT_TYPE))
	return out


# In view, along the camera's axis, nearest first.
func _line_up(fleet: Array[Combatant], ranges: Array[float]) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var forward: Vector3 = -camera.global_basis.z
	for i: int in fleet.size():
		fleet[i].ship.global_position = camera.global_position + forward * ranges[i] + camera.global_basis.x * 2.0 * float(i)
		fleet[i].ship.linear_velocity = Vector3.ZERO


func _visible_sum() -> int:
	return int(DebugConsole.registry.read("lod.visible_splats")["value"])


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_inside_the_budget_nothing_steps_down() -> void:
	var fleet: Array[Combatant] = _raiders(3)
	_line_up(fleet, [100.0, 100.0, 100.0] as Array[float])
	await _settle()
	var plain: Array[int] = []
	for c: Combatant in fleet:
		plain.append(c.ship.lod_level())
		assert_eq(c.ship.get_node(^"LodSwitcher").budget_extra, 0)
	assert_eq(plain[0], 1, "100 m: LOD1 by its size on screen")
	assert_lte(_visible_sum(), int(Settings.get_value(&"splat_budget")))


# All nine raiders close enough for LOD0 and in view, nearest first, the player's own hull out of the way.
func _close_fleet() -> Array[Combatant]:
	var fleet: Array[Combatant] = _raiders(9)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var forward: Vector3 = -camera.global_basis.z
	for i: int in fleet.size():
		fleet[i].ship.global_position = camera.global_position + forward * (35.0 + 3.0 * float(i)) \
				+ camera.global_basis.x * (float(i % 3) - 1.0) * 25.0 + camera.global_basis.y * (float(i / 3) - 1.0) * 20.0
		fleet[i].ship.linear_velocity = Vector3.ZERO
	DebugConsole.registry.execute("lod PLAYER 3")
	return fleet


func test_the_farthest_ships_step_down_until_the_sum_fits() -> void:
	var fleet: Array[Combatant] = _close_fleet()
	await _settle()
	var levels: Array[int] = []
	for c: Combatant in fleet:
		levels.append(c.ship.lod_level())
	assert_eq(levels, [0, 0, 0, 0, 0, 0, 0, 0, 0] as Array[int], "close enough for LOD0")
	var sum: int = _visible_sum()
	var counts: PackedInt32Array = fleet[0].ship.lod_splat_counts()
	var saving: int = counts[0] - counts[1]
	assert_gt(sum, 150000, "over the budget this test sets")
	var budget: int = sum - saving * 3 - 1  # three levels' saving is one too few: it takes four ships
	Settings.set_value(&"splat_budget", budget)
	await _settle()
	levels.clear()
	for c: Combatant in fleet:
		levels.append(c.ship.lod_level())
	assert_eq(levels, [0, 0, 0, 0, 0, 1, 1, 1, 1] as Array[int], "the four farthest, one level each")
	assert_lte(_visible_sum(), budget)
	# Back inside: they return to what their size calls for, at once.
	Settings.set_value(&"splat_budget", 2000000)
	await _settle()
	assert_eq(fleet[8].ship.lod_level(), 0, "no step-down left over")
	assert_eq(_visible_sum(), sum)


func test_the_step_down_sits_on_top_of_the_hysteresis_state() -> void:
	var fleet: Array[Combatant] = _raiders(1)
	_line_up(fleet, [90.0] as Array[float])
	await _settle()
	var switcher: LodSwitcher = fleet[0].ship.get_node(^"LodSwitcher") as LodSwitcher
	var unbiased: int = switcher.unbiased
	switcher.budget_extra = 1
	switcher._apply()
	assert_eq(fleet[0].ship.lod_level(), switcher.wanted + 1, "drawn one level coarser")
	assert_eq(switcher.unbiased, unbiased, "the switcher's own level is untouched")
	assert_eq(switcher.wanted, unbiased, "and so is what it wants")


func test_ships_out_of_view_do_not_count() -> void:
	var fleet: Array[Combatant] = _close_fleet()
	var camera: Camera3D = get_viewport().get_camera_3d()
	fleet[8].ship.global_position = camera.global_position + camera.global_basis.z * 58.0  # the farthest, and behind the camera
	await _settle()
	var sum: int = _visible_sum()
	var counts: PackedInt32Array = fleet[0].ship.lod_splat_counts()
	Settings.set_value(&"splat_budget", sum - (counts[0] - counts[1]) * 2 - 1)
	await _settle()
	var switcher: LodSwitcher = fleet[8].ship.get_node(^"LodSwitcher") as LodSwitcher
	assert_eq(switcher.budget_extra, 0, "the renderer culls it, so it is not asked to step down")
	assert_eq(fleet[7].ship.lod_level(), 0, "the sum of what is in view already fits: the ship behind was never part of it")


func test_a_forced_level_stays_forced_and_counts() -> void:
	var fleet: Array[Combatant] = _close_fleet()
	await _settle()
	assert_true(DebugConsole.registry.execute("lod RAIDER 9 0")[0].ok)
	var sum: int = _visible_sum()
	var counts: PackedInt32Array = fleet[0].ship.lod_splat_counts()
	Settings.set_value(&"splat_budget", sum - (counts[0] - counts[1]) - 1)
	await _settle()
	assert_eq(fleet[8].ship.lod_level(), 0, "the farthest is forced: it stays")
	assert_eq(fleet[7].ship.lod_level(), 1, "the next one gives way")
	assert_eq(fleet[6].ship.lod_level(), 1)
	assert_eq(fleet[5].ship.lod_level(), 0)


func test_it_warns_once_per_spell_when_even_the_coarsest_does_not_fit() -> void:
	_raiders(2)
	await _settle()
	var before: int = LodSwitcher.budget_warnings
	# The lowest budget the setting allows, against the player's hull forced to LOD0: nothing can step down far enough.
	var schema_floor: int = 100000
	Settings.set_value(&"splat_budget", schema_floor)
	DebugConsole.registry.execute("lod all 0")  # forced levels cannot step down, so this cannot fit
	await _settle()
	await _settle()
	var after_first: int = LodSwitcher.budget_warnings
	assert_eq(after_first, before + 1, "one warning")
	await _settle()
	await _settle()
	assert_eq(LodSwitcher.budget_warnings, after_first, "still only one while it lasts")
	DebugConsole.registry.execute("lod all auto")
	Settings.set_value(&"splat_budget", 2000000)
	await _settle()
	Settings.set_value(&"splat_budget", schema_floor)
	DebugConsole.registry.execute("lod all 0")
	await _settle()
	await _settle()
	assert_eq(LodSwitcher.budget_warnings, after_first + 1, "a new spell warns again")


func test_the_setting_is_an_int_with_bounds() -> void:
	assert_true(DebugConsole.registry.execute("set settings.splat_budget 500000")[0].ok)
	assert_eq(Settings.get_value(&"splat_budget"), 500000)
	assert_eq(typeof(Settings.get_value(&"splat_budget")), TYPE_INT)
	assert_false(DebugConsole.registry.execute("set settings.splat_budget 10")[0].ok, "below the bound")
	assert_false(DebugConsole.registry.execute("set settings.splat_budget 99999999")[0].ok, "above the bound")
	assert_false(DebugConsole.registry.execute("set settings.splat_budget many")[0].ok)
	assert_eq(GaussianRenderManager.get_splat_budget(), 500000, "pushed into the renderer on change")


func test_the_render_provider_reports_without_a_backend() -> void:
	for key: String in ["gdgs_rebuilds", "gdgs_splat_uploads", "splat_visible", "splat_clipped", "splat_budget_mb", "gpu_ms"]:
		assert_true(DebugConsole.registry.read("render.%s" % key).get("ok", false), key)
	assert_almost_eq(float(DebugConsole.registry.read("render.splat_budget_mb")["value"]), 1168.0, 1.0, "at the default budget")
