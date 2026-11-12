extends TestSteps
## Running lights in play (M3-T27, AC36, AC37): on the real main scene. Every ship has its three markers at its generated hardpoints,
## built once; a patrol hides until it attacks, an attack wave does not; a pool ship starts as its new pilot wants; the player's toggle
## (a `UiCommand` edge), the HUD, the console and the wing; radar and AI lists are unmoved; the cockpit's red lamp stays on when the
## ship goes dark. How they look is the GPU's and the maintainer's (P11, AC39).

const DT: float = 1.0 / 60.0

var main: Main
var source: FakeInputSource
var _scale_backup: float = 1.0


func before_each() -> void:
	get_tree().paused = false
	_scale_backup = Engine.time_scale
	ContactScan.invalidate()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _start(scenario: String = ScenarioLoader.FREE_FLIGHT_PATH, raiders: int = 2, allies: int = 3) -> void:
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = scenario
	main.raider_pool_size = raiders
	main.ally_pool_size = allies
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)


func _collect(node: Node, type: Variant, out: Array = []) -> Array:
	if is_instance_of(node, type):
		out.append(node)
	for child: Node in node.get_children():
		_collect(child, type, out)
	return out


func _lights_of(ship: Ship) -> RunningLights:
	return ship.get_node(^"RunningLights") as RunningLights


func _brain(spec: Dictionary) -> PilotBrain:
	var made: Dictionary = BrainFactory.from_behaviour(spec, main.world.to_universe(main.ship.global_position), 3)
	assert_true(made["ok"], made["error"])
	return made["brain"]


func _acquire(spec: Dictionary, offset: Vector3, type: StringName = ShipPool.DEFAULT_TYPE) -> Combatant:
	var at: UniversePos = main.world.to_universe(main.ship.global_position + offset)
	var placed: Combatant = main.ships.acquire("SHIP %d" % main.ships.alive().size(), at, Basis.IDENTITY, Vector3.ZERO, _brain(spec), type)
	assert_not_null(placed)
	return placed


func _patrol(far: Vector3) -> Dictionary:
	return {"type": "ai", "profile": "raider", "patrol": {"waypoints": [[far.x, far.y, far.z], [far.x + 500.0, far.y, far.z]]}}


func _tap_toggle() -> void:
	source.hold(InputAdapter.TOGGLE_RUNNING_LIGHTS)
	await _ticks(2)  # a frame may resume this just before Main's tick; two make sure one tick saw it held
	source.release(InputAdapter.TOGGLE_RUNNING_LIGHTS)
	await _ticks(2)


# --- markers ---------------------------------------------------------------------------------------------------------------


func test_every_ship_type_has_red_green_and_white_at_its_generated_hardpoints() -> void:
	await _start()
	var ships: Array[Ship] = [main.ship]
	ships.append(_acquire({"type": "idle"}, Vector3(0.0, 0.0, -200.0)).ship)
	ships.append(_acquire({"type": "idle"}, Vector3(0.0, 50.0, -200.0), ShipPool.ALLY_TYPE).ship)
	for ship: Ship in ships:
		ship.global_transform = Transform3D(Basis(Vector3.UP, 1.1), ship.global_position)  # a turned ship: its left is its own -X
		ship.reset_physics_interpolation()
		var nav: Dictionary = ship.get_hardpoints().nav_lights
		assert_false(nav.is_empty(), "%s names its lights" % ship.spec.asset_id)
		var lights: RunningLights = _lights_of(ship)
		assert_eq(lights.marker_count(), 3, ship.spec.asset_id)
		assert_true(lights.markers_shown(), "on at spawn")
		# The player's markers are nodes; an AI ship's are instances of its lights' multimesh (M4-T11), in the same frame.
		assert_eq(lights.instanced, ship.lean)
		for i: int in lights.marker_count():
			var world_at: Vector3 = lights.global_transform * lights.marker_position(i)
			if not lights.instanced:
				world_at = lights.markers()[i].global_position
			assert_almost_eq(ship.to_local(world_at), nav[["port", "starboard", "top"][i]] as Vector3, Vector3.ONE * 1e-3)
		assert_lt(lights.marker_position(0).x, 0.0, "%s: port is its left, -X" % ship.spec.asset_id)
		var red: Color = lights.marker_tint(0)
		var green: Color = lights.marker_tint(1)
		assert_gt(red.r, 3.0 * red.g, "port is red")
		assert_gt(green.g, 3.0 * green.r, "starboard is green")
		assert_true(ship.running_lights)


func test_the_marker_count_never_changes_and_no_marker_is_a_light() -> void:
	await _start()
	var markers_before: int = _collect(main, RunningLights).size()
	var quads_before: int = 0
	for lights: Variant in _collect(main, RunningLights):
		quads_before += (lights as RunningLights).marker_count()
	assert_eq(quads_before, 3 * (1 + main.ships.pool_size()), "three per ship, the pool's included")
	var lamps_before: int = _collect(main, Light3D).size()
	assert_eq(lamps_before, 8, "AC30's 8 hold")
	for cycle: int in 3:
		var one: Combatant = _acquire(_patrol(Vector3(9000.0, 0.0, 0.0)), Vector3(9000.0, 0.0, 0.0))
		var two: Combatant = _acquire({"type": "idle"}, Vector3(0.0, 0.0, -200.0), ShipPool.ALLY_TYPE)
		await _ticks(2)
		main.ships.release(one)
		main.ships.release(two)
		await _ticks(1)
	assert_eq(_collect(main, RunningLights).size(), markers_before)
	var quads_after: int = 0
	for lights: Variant in _collect(main, RunningLights):
		quads_after += (lights as RunningLights).marker_count()
	assert_eq(quads_after, quads_before)
	assert_eq(_collect(main, Light3D).size(), lamps_before)


func test_a_parked_ship_shows_none() -> void:
	await _start()
	var raider: Combatant = _acquire({"type": "idle"}, Vector3(0.0, 0.0, -200.0))
	assert_true(_lights_of(raider.ship).markers_shown())
	main.ships.release(raider)
	assert_false(_lights_of(raider.ship).markers_shown())


# --- the dark rule -------------------------------------------------------------------------------------------------------------


func test_a_patrolling_raider_stays_dark_on_its_run_in_and_lights_up_with_its_first_shot() -> void:
	await _start()
	var far := Vector3(9000.0, 0.0, 0.0)
	var raider: Combatant = _acquire(_patrol(far), far)
	assert_false(raider.ship.running_lights, "dark from the acquire")
	await _ticks(30)
	var pilot := raider.driver.brain as AiPilot
	assert_eq(pilot.current.id, &"follow_path", "nobody in sensor range: it patrols")
	assert_false(raider.ship.running_lights, "and hides")
	assert_false(_lights_of(raider.ship).markers_shown(), "no markers")
	# The player flies into its sensor range.
	main.ship.global_position = raider.ship.global_position + Vector3(0.0, 0.0, -1500.0)
	main.ship.reset_physics_interpolation()
	var fired_tick: int = -1
	var lit_tick: int = -1
	var closed_in_dark: bool = false
	for tick: int in 900:
		await _ticks(1)
		if fired_tick < 0 and raider.ship.get_combat_command().fire:
			fired_tick = tick
		if lit_tick < 0 and raider.ship.running_lights:
			lit_tick = tick
		closed_in_dark = closed_in_dark or (pilot.current.id == &"attack" and not raider.ship.running_lights)
		if lit_tick >= 0:
			break
	assert_true(closed_in_dark, "it attacks with its lights off")
	assert_gt(fired_tick, -1, "it fires")
	assert_eq(lit_tick, fired_tick, "its lights come on with the first shot")
	assert_true(_lights_of(raider.ship).markers_shown())


func test_a_raider_spawned_to_attack_is_lit_from_the_start() -> void:
	await _start()
	assert_true(_acquire({"type": "ai", "profile": "raider"}, Vector3(9000.0, 0.0, 0.0)).ship.running_lights, "an AI raider")
	assert_true(_acquire({"type": "attack"}, Vector3(9500.0, 0.0, 0.0)).ship.running_lights, "an attack brain")


func test_a_spawn_field_makes_any_ship_dark() -> void:
	await _start()
	var raider: Combatant = _acquire({"type": "idle", "running_lights": "off"}, Vector3(0.0, 0.0, -200.0))
	assert_false(raider.ship.running_lights)
	await _ticks(3)
	assert_false(raider.ship.running_lights, "idle never attacks")


func test_a_console_spawn_can_say_lights_off() -> void:
	await _start()
	assert_true(DebugConsole.registry.execute("spawn raider idle 200 lights=off")[0].ok)
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	assert_false(raider.ship.running_lights)
	assert_string_contains(str(main.ships._console_list(ShipPool.DEFAULT_TYPE)), "dark", "the provider says so")
	assert_false(DebugConsole.registry.execute("spawn raider idle 200 lights=maybe")[0].ok, "a bad word is refused")


func test_a_reacquired_pool_ship_does_not_keep_the_last_pilots_lights() -> void:
	await _start(ScenarioLoader.FREE_FLIGHT_PATH, 1, 0)
	var first: Combatant = _acquire(_patrol(Vector3(9000.0, 0.0, 0.0)), Vector3(9000.0, 0.0, 0.0))
	assert_false(first.ship.running_lights)
	main.ships.release(first)
	var again: Combatant = _acquire({"type": "idle"}, Vector3(0.0, 0.0, -200.0))
	assert_eq(again, first, "the same ship")
	assert_true(again.ship.running_lights, "a dark ship reacquired by a lit pilot is lit")
	assert_true(_lights_of(again.ship).markers_shown())
	main.ships.release(again)
	var third: Combatant = _acquire(_patrol(Vector3(9000.0, 0.0, 0.0)), Vector3(9000.0, 0.0, 0.0))
	assert_false(third.ship.running_lights, "and the other way round")


func test_the_sandboxs_patrol_wave_spawns_dark_and_its_strike_wave_lit() -> void:
	await _start(ScenarioLoader.SANDBOX_PATH, 9, 4)
	# At the moment each enters play; a patrol ship stays dark until its first shot.
	var at_spawn: Array[bool] = []
	main.ships.acquired.connect(func(c: Combatant) -> void: at_spawn.append(c.ship.running_lights))
	assert_true(DebugConsole.registry.execute("wave start 2")[0].ok)
	Engine.time_scale = 8.0
	while main.waves.plan.state != WavePlan.State.ACTIVE or main.ships.alive(ShipPool.DEFAULT_TYPE).is_empty():
		await _ticks(1)
	Engine.time_scale = 1.0
	assert_eq(at_spawn.size(), main.ships.alive(ShipPool.DEFAULT_TYPE).size(), "one for each")
	assert_false(at_spawn.has(true), "the PATROL wave starts dark")
	at_spawn.clear()
	assert_true(DebugConsole.registry.execute("wave start 3")[0].ok)
	Engine.time_scale = 8.0
	while main.waves.plan.state != WavePlan.State.ACTIVE or main.ships.alive(ShipPool.DEFAULT_TYPE).is_empty():
		await _ticks(1)
	Engine.time_scale = 1.0
	assert_false(at_spawn.is_empty())
	assert_false(at_spawn.has(false), "the STRIKE wave is lit from the start")


# --- the player ----------------------------------------------------------------------------------------------------------------


func _wingman(slot: int) -> Combatant:
	var wing: Wing = main.wings.player_wing()
	var ally: Combatant = _acquire({"type": "ai", "profile": "ally_starfury"}, Vector3(float(slot) * 60.0, 0.0, 60.0), ShipPool.ALLY_TYPE)
	assert_eq(main.wings.add_member(wing, ally), slot)
	return ally


func test_the_toggle_switches_the_player_the_hud_shows_it_and_the_wing_follows() -> void:
	await _start()
	var ally: Combatant = _wingman(1)
	var other: Combatant = _wingman(2)
	await _tap_toggle()
	assert_false(main.ship.running_lights, "the action turned them off")
	assert_false(_lights_of(main.ship).markers()[0].visible)
	await _ticks(1)
	assert_false(ally.ship.running_lights, "the wing follows, well within 1 s")
	assert_false(other.ship.running_lights)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(main.hud.frame.running_lights_dark, "the HUD shows it")
	assert_eq(main.hud.frame.running_lights_text, "LIGHTS OFF")
	await _tap_toggle()
	assert_true(main.ship.running_lights, "the second press turned them on")
	await _ticks(1)
	assert_true(ally.ship.running_lights, "and the wing")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(main.hud.frame.running_lights_dark)
	assert_eq(main.hud.frame.running_lights_text, "LIGHTS ON")


func test_a_replacement_joins_dark_when_the_player_is_dark() -> void:
	await _start()
	main.ship.running_lights = false
	var ally: Combatant = _wingman(1)
	await _ticks(1)
	assert_false(ally.ship.running_lights)


func test_the_console_does_the_same() -> void:
	await _start()
	var ally: Combatant = _wingman(1)
	var off: ConsoleResult = DebugConsole.registry.execute("running_lights off")[0]
	assert_true(off.ok, off.error)
	assert_false(main.ship.running_lights, "off")
	await _ticks(1)
	assert_false(ally.ship.running_lights, "the wing follows")
	assert_true(DebugConsole.registry.execute("running_lights on")[0].ok)
	assert_true(main.ship.running_lights, "on")
	assert_true(DebugConsole.registry.execute("running_lights")[0].ok, "alone, it toggles")
	assert_false(main.ship.running_lights, "toggled")
	assert_false(DebugConsole.registry.execute("running_lights maybe")[0].ok, "a bad word is refused")


func test_a_respawn_puts_the_lights_back_on() -> void:
	await _start()
	main.ship.running_lights = false
	main.respawn()
	assert_true(main.ship.running_lights)


func test_the_instructor_stays_lit() -> void:
	await _start("res://data/scenarios/instructor_route.json", 0, 1)
	assert_not_null(main.instructor)
	await _tap_toggle()
	assert_false(main.ship.running_lights)
	await _ticks(2)
	assert_true(main.instructor.ship.running_lights, "it is nobody's wingman")


func test_radar_and_ai_contact_lists_do_not_change() -> void:
	await _start()
	var raider: Combatant = _acquire(_patrol(Vector3(0.0, 0.0, -1000.0)), Vector3(0.0, 0.0, -1000.0))
	await _ticks(2)
	raider.ship.running_lights = true
	ContactScan.invalidate()
	var scan: ContactScan = ContactScan.shared(get_tree())
	var seen_lit: int = scan.contacts_for(main.ship.get_instance_id(), main.ship.global_position, main.combatant.faction).size()
	var candidates_lit: int = main.ship.targeting.candidates().size()
	await _ticks(3)
	await get_tree().process_frame
	await get_tree().process_frame
	var dots_lit: int = main.hud.frame.radar_dots.size()
	raider.ship.running_lights = false
	ContactScan.invalidate()
	scan = ContactScan.shared(get_tree())
	var seen_dark: int = scan.contacts_for(main.ship.get_instance_id(), main.ship.global_position, main.combatant.faction).size()
	await _ticks(3)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(seen_lit, 0, "the raider is a contact")
	assert_eq(seen_dark, seen_lit, "AI lists")
	assert_eq(main.ship.targeting.candidates().size(), candidates_lit, "targeting")
	assert_eq(main.hud.frame.radar_dots.size(), dots_lit, "radar")


# --- the cabin lamp --------------------------------------------------------------------------------------------------------------


func test_the_cabin_light_is_red_and_a_dark_ship_keeps_it() -> void:
	await _start()
	var rig: LightRig = LightRig.of(main.ship)
	main.camera_rig.set_mode(CameraRig.Mode.COCKPIT)
	main.ship.running_lights = false
	rig.update(main.camera_rig.cockpit_camera.global_position)
	var cabin: LightEmitter = null
	for emitter: LightEmitter in rig.picked():
		if emitter != null and emitter.priority == LightEmitter.PRIORITY_CABIN:
			cabin = emitter
	assert_not_null(cabin, "it still lights the cockpit when dark")
	assert_gt(cabin.color.r, 3.0 * cabin.color.g, "red")
	main.camera_rig.set_mode(CameraRig.Mode.CHASE)


# --- buoys ---------------------------------------------------------------------------------------------------------------------------


func test_buoys_keep_a_steady_light_and_breathe_on_the_sim_clock() -> void:
	await _start()
	assert_gt(main.buoys.size(), 1)
	var a: NavBuoy = main.buoys[0]
	var b: NavBuoy = main.buoys[1]
	assert_almost_eq(a.fade_phase_s, NavBuoy.fade_phase_of(a.display_name), 1e-6, "seeded per buoy")
	assert_ne(a.fade_phase_s, b.fade_phase_s)
	for tick: int in 10:
		await _ticks(1)
		a._process(0.0)
		assert_true(a.beacon.visible, "the steady light never goes out")
		var expected: float = 1.0 - NavBuoy.fade_level(SimClock.now(), a.fade_phase_s)
		assert_almost_eq(a.beacon_fade.transparency, expected, 1e-5, "the fade follows the curve on sim time")
	assert_eq(_collect(a, Light3D).size(), 0, "no light node")
