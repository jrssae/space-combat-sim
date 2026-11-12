extends TestSteps
## The target menu's preview panel on the real main scene (architecture §18.20, M5-T43): highlighting an entry of the second
## ring shows it (read once per highlight), the wireframe's viewport renders only while the panel shows, an unknown contact
## gives nothing away, and a hull's edges are found a slice a frame.

const DT: float = 1.0 / 60.0
const MISSION_PATH: String = "res://tests/fixtures/missions/test_mission.json"

var main: Main
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	WirePreview.clear_cache()
	await _boot(ScenarioLoader.FREE_FLIGHT_PATH)


func _boot(scenario: String) -> void:
	if main != null:
		main.queue_free()
		await _ticks(2)
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = scenario
	main.waves_auto_start = false
	main.raider_pool_size = 4
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	WirePreview.clear_cache()


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _raider(label: String, range_m: float, brain: PilotBrain = null) -> Combatant:
	var at: UniversePos = main.world.to_universe(main.ship.global_position).plus_local(Vector3(0.0, 0.0, -range_m))
	var raider: Combatant = main.ships.acquire(label, at, Basis.IDENTITY, Vector3.ZERO, brain if brain != null else IdleBrain.new())
	raider.damageable.invulnerable = true
	return raider


func _read(path: String) -> Variant:
	var read: Dictionary = DebugConsole.registry.read(path)
	assert_true(read["ok"], "%s: %s" % [path, read["error"]])
	return read["value"]


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# Waits until the wireframe's edges are found (a slice a frame).
func _built() -> void:
	var guard: int = 0
	while main.target_menu.preview.wire.building and guard < 2000:
		guard += 1
		await get_tree().process_frame


func test_highlighting_an_entry_of_the_second_ring_shows_it() -> void:
	_raider("RAIDER 1", 900.0)
	_raider("RAIDER 2", 1900.0)
	await _ticks(3)
	var preview: TargetPreview = main.target_menu.preview
	assert_false(preview.is_showing(), "nothing shows before the menu opens")
	assert_true(_run("targetmenu open").ok)
	assert_false(preview.is_showing(), "nor on the first ring")
	assert_true(_run("targetmenu pick enemies").ok)
	assert_true(preview.is_showing(), "the second ring opens with its first entry highlighted")
	assert_eq(preview.model.title, "RAIDER 1")
	assert_eq(preview.model.kind, TargetPreviewModel.Kind.SHIP)
	assert_eq(preview.model.subtitle, "Delta-V raider · Raiders")
	assert_eq(preview.model.row(&"range")["value"], "900 m")
	assert_eq(preview.model.row(&"hull")["value"], "100 %")
	assert_eq(_read("target_preview.hull"), "raider_fighter")
	assert_true(preview.wire.has_hull())
	await _built()
	assert_gt(preview.wire.edge_count, 100, "the raider's feature edges")
	assert_eq(_read("target_preview.edges"), preview.wire.edge_count)
	assert_eq(_read("target_preview.cache"), 1)
	var shows: int = preview.shows
	await _ticks(20)
	assert_eq(preview.shows, shows, "an entry is read once per highlight, not every tick")
	assert_true(_run("targetmenu highlight \"raider 2\"").ok)
	assert_eq(preview.model.title, "RAIDER 2")
	assert_eq(preview.model.row(&"range")["value"], "1.9 km")
	assert_eq(preview.shows, shows + 1)
	assert_false(preview.wire.building, "the same hull's edges are kept, not found again")
	assert_eq(_read("target_preview.cache"), 1)
	await _frames(2)
	assert_gt(preview.draws, 0)
	assert_true(preview.drawn_lines.has("RAIDER 2"), "the panel draws the name")
	assert_true(preview.drawn_lines.has("RANGE 1.9 km"))
	var view: Vector2 = get_viewport().get_visible_rect().size
	assert_gte(preview.drawn_panel.position.x, view.x * 0.5, "at the side opposite the ring")
	assert_almost_eq(preview.drawn_panel.get_center().y, view.y * 0.5, 1.0)
	if view.x >= 400.0:  # a window too small for both (the headless one) lets them touch
		assert_lte(main.target_menu.view.drawn_centre.x + main.target_menu.view.drawn_radius, preview.drawn_panel.position.x + 0.5)


func test_the_stick_moves_the_preview_with_the_highlight() -> void:
	_raider("RAIDER 1", 900.0)
	_raider("RAIDER 2", 1900.0)
	await _ticks(3)
	source.hold(InputAdapter.TARGET_CYCLE)
	await _ticks(ceili(main.adapter.target_hold_s / DT) + 3)
	source.release(InputAdapter.TARGET_CYCLE)
	await _ticks(2)
	source.hold(InputAdapter.RADIAL_SELECT)
	await _ticks(2)
	source.release(InputAdapter.RADIAL_SELECT)
	await _ticks(2)
	var preview: TargetPreview = main.target_menu.preview
	assert_eq(preview.model.title, "RAIDER 1")
	# The second entry is the next slice clockwise, 60 degrees from the top.
	source.hold(InputAdapter.RADIAL_RIGHT, sin(deg_to_rad(60.0)))
	source.hold(InputAdapter.RADIAL_UP, cos(deg_to_rad(60.0)))
	await _ticks(2)
	source.release(InputAdapter.RADIAL_RIGHT)
	source.release(InputAdapter.RADIAL_UP)
	await _ticks(2)
	assert_eq(preview.model.title, "RAIDER 2")
	source.hold(InputAdapter.RADIAL_DOWN)
	await _ticks(2)
	source.release(InputAdapter.RADIAL_DOWN)
	await _ticks(2)
	assert_eq(preview.model.title, "NONE", "none is an entry too")
	assert_eq(preview.model.subtitle, TargetMenuDirector.NONE_CLEARS_TARGET)
	assert_eq(preview.model.kind, TargetPreviewModel.Kind.NONE)
	assert_false(preview.wire.has_hull(), "with no wireframe")
	assert_false(preview.wire.live)


func test_the_viewport_renders_only_while_the_panel_shows() -> void:
	_raider("RAIDER 1", 900.0)
	await _ticks(3)
	var preview: TargetPreview = main.target_menu.preview
	assert_eq(preview.wire.render_target_update_mode, SubViewport.UPDATE_DISABLED, "closed: the viewport is off")
	assert_false(preview.is_processing())
	assert_false(preview.wire.is_processing())
	var draws: int = preview.draws
	await _ticks(10)
	await _frames(3)
	assert_eq(preview.draws, draws, "and the panel draws nothing")
	_run("targetmenu open")
	assert_eq(preview.wire.render_target_update_mode, SubViewport.UPDATE_DISABLED, "the first ring: still off")
	assert_false(preview.wire.is_processing())
	_run("targetmenu pick enemies")
	assert_eq(preview.wire.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "the second ring on a hull: on")
	assert_true(preview.wire.is_processing())
	assert_true(_read("target_preview.rendering"))
	_run("targetmenu highlight none")
	assert_eq(preview.wire.render_target_update_mode, SubViewport.UPDATE_DISABLED, "nothing to draw for none")
	_run("targetmenu highlight 0")
	assert_eq(preview.wire.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	_run("targetmenu back")
	assert_false(preview.is_showing(), "back on the first ring it hides")
	assert_eq(preview.wire.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	_run("targetmenu pick enemies")
	_run("targetmenu pick 0")
	assert_false(main.target_menu.is_open())
	assert_false(preview.is_showing(), "a pick closes it")
	assert_eq(preview.wire.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_false(preview.is_processing())
	assert_false(preview.wire.is_processing())
	assert_false(preview.wire.has_hull())
	assert_eq(_read("target_preview.visible"), false)
	assert_eq(_read("target_preview.entity"), "none")


func test_the_hull_turns_while_the_game_is_paused() -> void:
	_raider("RAIDER 1", 900.0)
	await _ticks(3)
	_run("targetmenu open")
	_run("targetmenu pick enemies")
	assert_true(get_tree().paused)
	var wire: WirePreview = main.target_menu.preview.wire
	await _frames(2)
	var before: float = wire.yaw()
	var started: int = Time.get_ticks_msec()
	await _frames(20)
	var elapsed_s: float = float(Time.get_ticks_msec() - started) / 1000.0
	var turned: float = rad_to_deg(angle_difference(before, wire.yaw()))
	assert_gt(turned, 0.0, "it turns behind the pause")
	assert_lt(turned, WireFraming.TURN_DEG_S * (elapsed_s + 0.5), "slowly")


func test_an_unknown_contact_shows_no_name_and_no_hull() -> void:
	_raider("RAIDER 9", 7000.0)
	await _ticks(3)
	_run("targetmenu open")
	_run("targetmenu pick unknown")
	var preview: TargetPreview = main.target_menu.preview
	assert_eq(preview.model.kind, TargetPreviewModel.Kind.UNKNOWN)
	assert_eq(preview.model.title, TargetMenu.UNKNOWN_LABEL)
	assert_eq(preview.model.placeholder, TargetPreviewModel.NO_ID)
	assert_false(preview.wire.has_hull(), "no wireframe gives its hull away")
	assert_eq(_read("target_preview.hull"), "none")
	assert_null(preview.model.row(&"hull"))
	await _frames(2)
	for line: String in preview.drawn_lines:
		assert_false(line.to_lower().contains("raider"), "nothing on the panel names it: %s" % line)
	assert_true(preview.drawn_lines.has(TargetPreviewModel.NO_ID))


func test_a_buoy_shows_its_wireframe_and_no_hull_bar() -> void:
	await _ticks(3)
	_run("targetmenu open")
	_run("targetmenu pick navigation")
	var preview: TargetPreview = main.target_menu.preview
	assert_eq(preview.model.kind, TargetPreviewModel.Kind.BEACON)
	assert_true(preview.model.subtitle.begins_with("Nav buoy"))
	assert_eq(_read("target_preview.hull"), "nav_buoy")
	assert_null(preview.model.row(&"hull"))
	assert_not_null(preview.model.row(&"range"))
	_run("targetmenu highlight none")
	assert_eq(preview.model.subtitle, TargetMenuDirector.NONE_CLEARS_WAYPOINT)


func test_an_objective_shows_its_text_and_its_actors_wireframe() -> void:
	await _boot(MISSION_PATH)
	main.mission.api.skip()
	await _ticks(3)
	_run("targetmenu open")
	_run("targetmenu pick objectives")
	_run("targetmenu highlight 1")
	var preview: TargetPreview = main.target_menu.preview
	assert_eq(preview.model.kind, TargetPreviewModel.Kind.OBJECTIVE)
	assert_eq(preview.model.title, "NAV ALPHA", "the objective's actor")
	assert_eq(preview.model.subtitle, TargetPreviewModel.OBJECTIVE_SUBTITLE)
	assert_true(str(preview.model.row(&"text")["value"]).to_lower().begins_with("keep nav alpha"), "its whole text")
	assert_not_null(preview.model.row(&"range"))
	assert_null(preview.model.row(&"hull"), "no hull bar")
	assert_eq(_read("target_preview.hull"), "nav_buoy", "the buoy it is about is drawn")
	await _frames(2)
	assert_gt(preview.draws, 0)


func test_a_raider_after_the_pilot_is_flagged() -> void:
	main.combatant.damageable.invulnerable = true
	var hunter: Combatant = _raider("RAIDER 1", 900.0, AttackBrain.new())
	var idler: Combatant = _raider("RAIDER 2", 1900.0)
	await _ticks(40)
	assert_eq(hunter.ship.targeting.selected_id(), main.combatant.targetable.get_instance_id(), "the hunter is on the pilot")
	assert_eq(idler.ship.targeting.selected_id(), main.combatant.targetable.get_instance_id(), "the idler has the pilot selected too")
	_run("targetmenu open")
	_run("targetmenu pick enemies")
	var preview: TargetPreview = main.target_menu.preview
	assert_eq(preview.model.flag, TargetPreviewModel.FLAG_ATTACKING)
	assert_eq(_read("target_preview.flag"), TargetPreviewModel.FLAG_ATTACKING)
	_run("targetmenu highlight \"raider 2\"")
	assert_eq(preview.model.flag, "", "a ship that only has the pilot selected is not attacking")


func test_the_console_points_at_an_entry_without_picking_it() -> void:
	_raider("RAIDER 1", 900.0)
	await _ticks(3)
	assert_false(_run("targetmenu highlight 0").ok, "closed: nothing to point at")
	_run("targetmenu open")
	_run("targetmenu pick enemies")
	assert_false(_run("targetmenu highlight \"raider 7\"").ok)
	var result: ConsoleResult = _run("targetmenu highlight none")
	assert_true(result.ok)
	assert_true(main.target_menu.is_open(), "highlight does not pick")
	assert_eq(_read("target_menu.highlight"), "NONE")
	assert_eq(_read("target_preview.kind"), "none")
	assert_eq(_read("target_preview.lines"), TargetMenuDirector.NONE_CLEARS_TARGET)


func test_the_largest_hulls_edges_are_found_in_slices() -> void:
	var mesh: Mesh = MeshAssets.for_asset("saturn_8_transport")
	if mesh == null:
		pending("the hulls are not generated (scripts/gen_assets.sh)")
		return
	var triangles: int = 0
	for s: int in mesh.get_surface_count():
		@warning_ignore("integer_division")
		triangles += mesh.surface_get_array_index_len(s) / 3
	var started: int = Time.get_ticks_usec()
	var whole: PackedVector3Array = FeatureEdges.from_mesh(mesh)
	var whole_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var job: FeatureEdgeJob = FeatureEdgeJob.for_mesh(mesh)
	var read_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	var longest_usec: int = 0
	while not job.done:
		var slice: int = Time.get_ticks_usec()
		job.step(WirePreview.BUILD_BUDGET_USEC)
		longest_usec = maxi(longest_usec, Time.get_ticks_usec() - slice)
	gut.p("saturn_8_transport: %d triangles, %d edges; in one go %.1f ms; sliced: reading the mesh %.1f ms, then %d slices, %.1f ms in all, the longest %.2f ms"
			% [triangles, whole.size() / 2, whole_ms, read_ms, job.steps, float(job.spent_usec) / 1000.0, float(longest_usec) / 1000.0])
	assert_eq(job.lines(), whole, "sliced or whole, the same lines")
	assert_gt(whole.size() / 2, 1000)
	assert_lt(whole.size() / 2, triangles / 2, "far fewer lines than a triangle wireframe's (1.5 per triangle)")
	assert_gt(job.steps, 3, "the work is spread over frames")
	assert_lt(whole_ms, 2000.0, "and bounded even on a slow machine")
