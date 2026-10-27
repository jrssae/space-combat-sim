extends GutTest
## AC10, the instructor on `instructor_route` (M3-T09, architecture §16 D37, maintainer Q5): the real main scene with the
## scenario's instructor, an allied Starfury from the pool on the `instructor` profile, leading the TRAINING route paced to the
## player, through Jolt and the real drivers. With the player parked it stops within 1 600 m and waits until the player closes
## to 800 m, also after it has gone beyond 1 600 m on a leg; with the player keeping up it visits every waypoint in order and
## every demo meets its goal; the HUD's waypoint marker projects to the route point; it is invulnerable and starts over when
## the player respawns. Sim time is sped up (`SPEED_UP`: 0.1 s steps); the demos at the game's 60 Hz are measured in
## `test_manoeuvres_jolt.gd`.

const SCENARIO_PATH: String = "res://data/scenarios/instructor_route.json"
## `Engine.time_scale`: each 60 Hz tick is 0.1 s of sim time.
const SPEED_UP: float = 6.0
## The player "keeps up" this far behind the instructor.
const KEEP_UP_M: float = 300.0
const DEMO_ORDER: Array[String] = ["roll", "strafe_box", "pod_turn", "flip_and_burn", "all_stop"]

var main: Main
var _scale_backup: float = 1.0
var _ticks_run: int = 0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true  # the player is teleported along the route in one test; its hull is not the point
	ContactScan.invalidate()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO_PATH
	add_child_autofree(main)
	await get_tree().physics_frame
	Engine.time_scale = SPEED_UP


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false
	ContactScan.invalidate()


func _path() -> BehaviourFollowPath:
	return main.instructor_path


func _instructor_ship() -> Ship:
	return main.instructor.ship


func _lag() -> float:
	return _instructor_ship().global_position.distance_to(main.ship.global_position)


## Ticks until `done.call()` is true or `max_s` of sim time pass; `each_tick` runs before every check. Returns whether it came true.
func _run_until(done: Callable, max_s: float, each_tick: Callable = Callable()) -> bool:
	var dt: float = SPEED_UP / float(Engine.physics_ticks_per_second)
	var ticks: int = roundi(max_s / dt)
	for i: int in ticks:
		await get_tree().physics_frame
		_ticks_run += 1
		if each_tick.is_valid():
			each_tick.call()
		if done.call():
			return true
	return false


## Puts the player (at rest) `distance_m` from the instructor, on the line from the instructor through `toward` (World).
func _place_player(distance_m: float, toward: Vector3) -> void:
	var from: Vector3 = _instructor_ship().global_position
	var dir: Vector3 = (toward - from).normalized()
	main.ship.reset_to(Transform3D(main.ship.global_basis, from + dir * distance_m))


## Degrees between the instructor's nose and the line to the player.
func _facing_error_deg() -> float:
	var to_player: Vector3 = main.ship.global_position - _instructor_ship().global_position
	return rad_to_deg(_instructor_ship().forward().angle_to(to_player))


func test_the_scenario_spawns_an_invulnerable_instructor_ahead_of_the_player() -> void:
	assert_not_null(main.instructor, "the scenario's instructor")
	assert_eq(main.instructor.display_name, "INSTRUCTOR")
	assert_eq(main.instructor.faction, Factions.EARTH_ALLIANCE)
	assert_eq(main.ships.type_of(main.instructor), ShipPool.ALLY_TYPE)
	assert_true(main.instructor.damageable.invulnerable)
	var pilot := main.instructor.driver.brain as AiPilot
	assert_not_null(pilot)
	assert_eq(pilot.profile, AiProfile.load_named(&"instructor"))
	assert_eq(pilot.context.route.pace_id, main.combatant.targetable.get_instance_id(), "paced to the player")
	assert_almost_eq(_lag(), 200.0, 1.0, "200 m ahead of the player")
	assert_lt((_instructor_ship().global_position - main.ship.global_position).normalized().dot(main.ship.forward()) - 1.0, 1e-3,
			"straight ahead")
	assert_eq(main.waves.plan.waves.size(), 0, "no waves")
	assert_eq(main.buoys.size(), 5)
	# Invulnerable: a hit arrives, nothing is taken off.
	var damageable: Damageable = main.instructor.damageable
	var info := HitInfo.new(_instructor_ship().get_instance_id(), 0, Factions.RAIDERS, 500.0, _instructor_ship().global_position)
	damageable.apply_hit(info)
	assert_eq(damageable.hull.fraction(), 1.0, "a hit takes nothing off")
	assert_eq(info.applied, 0.0)
	# The console sees the route.
	assert_true(DebugConsole.registry.has_provider(&"route"), "provider route on this scenario")
	assert_eq(DebugConsole.registry.format_path("route.count"), "route.count = 6")
	assert_eq(DebugConsole.registry.format_path("route.index"), "route.index = 1")
	# A respawn places it again; the pool's next user does not inherit the flag.
	await _run_until(func() -> bool: return _path().index >= 1, 30.0)
	main.respawn()
	await get_tree().physics_frame
	assert_eq(_path().index, 0, "the route starts over")
	assert_almost_eq(_lag(), 200.0, 15.0, "back 200 m ahead of the player")
	assert_true(main.instructor.damageable.invulnerable)
	var instructor: Combatant = main.instructor
	main.ships.release(instructor)
	var reused: Combatant = main.ships.acquire("ALPHA 2", UniversePos.new(0.0, 0.0, -900.0), Basis.IDENTITY, Vector3.ZERO, null,
			ShipPool.ALLY_TYPE)
	assert_eq(reused, instructor, "the same pooled Starfury")
	assert_false(reused.damageable.invulnerable, "acquire clears the flag")
	assert_false(main.route_active(), "no route on the HUD once the instructor is not flying it")
	assert_false(main._build_hud_input().has_waypoint)


func test_with_the_player_parked_it_stops_within_1600_m_and_waits_until_800_m() -> void:
	var path: BehaviourFollowPath = _path()
	# Parked at the start: it slows with the lag and stops at the first demo (NAV 2) to wait for the player.
	var stopped := func() -> bool:
		return path.state_name() == "wait" and _instructor_ship().linear_velocity.length() < 1.0
	assert_true(await _run_until(stopped, 120.0), "it stopped (state %s, %.1f m/s, lag %.0f m)" % [path.state_name(),
			_instructor_ship().linear_velocity.length(), _lag()])
	var first_stop_m: float = _lag()
	await _run_until(func() -> bool: return false, 3.0)
	gut.p("parked player: the instructor stopped at NAV %d, %.0f m from the player, facing it within %.1f deg" % [
			path.nav_number(), first_stop_m, _facing_error_deg()])
	assert_lt(first_stop_m, Route.WAIT_BEYOND_M, "stops within 1 600 m")
	assert_lt(_instructor_ship().linear_velocity.length(), 0.5, "and stays stopped")
	assert_lt(_facing_error_deg(), 10.0, "facing the player")
	assert_eq(path.demo_name(), "roll", "waiting to show the roll")
	# 1 000 m is not close enough; 700 m is.
	_place_player(1000.0, main.ship.global_position)
	await _run_until(func() -> bool: return false, 5.0)
	assert_eq(path.state_name(), "wait", "at 1 000 m it still waits")
	assert_lt(_instructor_ship().linear_velocity.length(), 0.5)
	_place_player(700.0, main.ship.global_position)
	assert_true(await _run_until(func() -> bool: return path.state_name() == "demo", 1.0), "inside 800 m the demo starts")
	assert_true(await _run_until(func() -> bool: return path.results.size() == 1, 15.0), "the roll finished")
	assert_eq(path.results[0]["demo"], "roll")
	# On the next leg the player falls 2 km behind: beyond 1 600 m it brakes, turns to face the player and waits.
	assert_true(await _run_until(func() -> bool: return path.state_name() == "lead" and _instructor_ship().linear_velocity.length() > 20.0,
			20.0), "it leads on (state %s)" % path.state_name())
	_place_player(2000.0, _instructor_ship().global_position - _instructor_ship().linear_velocity)
	assert_true(await _run_until(func() -> bool: return path.state_name() == "wait", 0.5), "beyond 1 600 m it waits")
	assert_true(await _run_until(func() -> bool: return _instructor_ship().linear_velocity.length() < 1.0, 15.0), "and brakes to a stop")
	await _run_until(func() -> bool: return false, 3.0)
	gut.p("left behind: stopped %.0f m from the player, facing it within %.1f deg" % [_lag(), _facing_error_deg()])
	assert_lt(_facing_error_deg(), 10.0, "facing the player")
	_place_player(1000.0, main.ship.global_position)
	await _run_until(func() -> bool: return false, 5.0)
	assert_eq(path.state_name(), "wait", "at 1 000 m it still waits")
	_place_player(700.0, main.ship.global_position)
	assert_true(await _run_until(func() -> bool: return path.state_name() == "lead", 1.0), "inside 800 m it resumes")
	assert_true(await _run_until(func() -> bool: return _instructor_ship().linear_velocity.length() > 20.0, 10.0), "and leads on")


func test_with_the_player_keeping_up_it_visits_every_waypoint_in_order_and_every_demo_meets_its_goal() -> void:
	var path: BehaviourFollowPath = _path()
	var route: Route = (main.instructor.driver.brain as AiPilot).context.route
	var hud_checked: Array[bool] = [false]
	var max_lag: Array[float] = [0.0]
	var keep_up := func() -> void:
		var instructor: Ship = _instructor_ship()
		var v: Vector3 = instructor.linear_velocity
		var behind: Vector3 = -v.normalized() if v.length() > 5.0 else (main.ship.global_position - instructor.global_position).normalized()
		main.ship.reset_to(Transform3D(main.ship.global_basis, instructor.global_position + behind * KEEP_UP_M))
		max_lag[0] = maxf(max_lag[0], float(path.lag_m))
		if not hud_checked[0] and path.index == 2 and path.state_name() == "lead":
			hud_checked[0] = true
			_check_waypoint_marker(route)
	var finished: bool = await _run_until(func() -> bool: return path.state_name() == "done", 300.0, keep_up)
	gut.p("route: %s after %.0f s, visited %s, lag at most %.0f m" % ["done" if finished else path.state_name(),
			float(_ticks_run) * SPEED_UP / 60.0, str(path.visited), max_lag[0]])
	assert_true(finished, "the route ended")
	assert_eq(path.visited, PackedInt32Array([0, 1, 2, 3, 4, 5]), "every waypoint, in order")
	assert_true(hud_checked[0], "the HUD was checked on the way")
	var demos: Array[String] = []
	for result: Dictionary in path.results:
		demos.append(String(result["demo"]))
		gut.p("  NAV %d %s: %s" % [int(result["index"]) + 1, result["demo"], str(result)])
		assert_false(bool(result["timed_out"]), "%s met its goal" % result["demo"])
	assert_eq(demos, DEMO_ORDER, "one of each demo, in the route's order")
	if demos != DEMO_ORDER:
		return
	var r: Array[Dictionary] = path.results
	assert_almost_eq(float(r[0]["roll_deg"]), 360.0, 10.0, "roll 360 +- 10")
	for leg: float in r[1]["legs_m"]:
		assert_gt(leg, 40.0, "strafe box legs over 40 m")
	assert_lt(float(r[1]["closure_m"]), 30.0, "strafe box back within 30 m")
	assert_gt(float(r[2]["yaw_deg"]), 30.0, "pod turn to the right by over 30 degrees")
	assert_true(bool(r[3]["reversed"]) or float(r[3]["speed_mps"]) < 2.0, "flip and burn: reversed or under 2 m/s")
	assert_gt(float(r[3]["speed0_mps"]), 0.85 * route.cruise_mps, "from cruise")
	assert_lt(float(r[4]["speed_mps"]), 0.5, "all stop under 0.5 m/s")
	assert_lt(float(r[4]["rate_dps"]), 1.0, "and 1 degree/s")
	assert_lt(_instructor_ship().linear_velocity.length(), 1.0, "it holds at the end")
	assert_eq(main.instructor_path.status_line("INSTRUCTOR"), "FOLLOW INSTRUCTOR — ROUTE COMPLETE")


# The HUD marks the instructor's next waypoint where the camera projects it (AC10).
func _check_waypoint_marker(route: Route) -> void:
	var input: HudInput = main._build_hud_input()
	var point: Vector3 = main.world.universe_to_local(route.waypoint(2).position)
	assert_true(input.has_waypoint, "a waypoint to mark")
	assert_eq(input.waypoint_label, "NAV 3")
	assert_almost_eq(input.waypoint_position, point, Vector3.ONE * 1e-3, "the route point, World frame")
	assert_eq(input.status_line, "FOLLOW INSTRUCTOR — NAV 3/6 — NEXT: STRAFE BOX")
	var f: HudFrame = HudLayout.compute(input)
	var camera: Camera3D = main.camera_rig.active_camera()
	assert_true(f.waypoint_present)
	if not camera.is_position_behind(point) and HudLayout.on_screen(input, camera.unproject_position(point)):
		assert_true(f.waypoint_on_screen)
		assert_almost_eq(f.waypoint_pos, camera.unproject_position(point), Vector2.ONE * 0.5, "on the projected route point")
	else:
		assert_true(f.waypoint_edge_visible, "off screen: the edge arrow")
	gut.p("HUD: %s at %s (on screen %s), %s" % [f.waypoint_label, f.waypoint_pos, f.waypoint_on_screen, input.status_line])
