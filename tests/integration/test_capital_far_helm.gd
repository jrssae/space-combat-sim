extends GutTest
## Far capitals steer live (M10-T16, the maintainer, 2026-11-26): a capital beyond the low-attention tier's radius is a tier row
## with no body, and its native helm still flies it, by its own thrusters (the tier flies it as a fighter's row), while its
## brain keeps thinking. An Omega 15 km off told a course turns onto it and holds its speed; two hostile Omegas far off close on
## each other under their brains; back in play an Omega keeps the course its helm had out there. Scenario capitals with
## `helm: free` start under their brains (`capitals[].helm`).

const SPEED_UP: float = 16.0
const FAR_M: float = 15000.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	await _launch(ScenarioLoader.FREE_FLIGHT_PATH)


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	DebugConsole.flags.invulnerable = false


func _launch(path: String) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = path
	main.scenario_seed = 7
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func _omega(display_name: String, faction: StringName, ahead_m: float, yaw_deg: float = 0.0) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(&"ea_omega", faction, display_name, rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var nose: Basis = main.ship.global_basis
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - nose.z * ahead_m), nose.rotated(nose.y,
			deg_to_rad(yaw_deg)))
	return cap


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func _core() -> Object:
	return SimCore.for_tree(get_tree()).core


func test_a_far_omega_told_a_course_turns_onto_it_and_holds_its_speed() -> void:
	var cap: CapitalShip = _omega("Far Omega", Factions.EARTH_ALLIANCE, FAR_M)
	if cap == null:
		return
	var id: int = cap.get_instance_id()
	await _fly(10.0, func() -> bool: return bool(_core().tier_has(id)))
	assert_true(bool(_core().tier_has(id)), "15 km off it is a tier row")
	var rest: Vector3 = main.world.rest_velocity()
	var start: Dictionary = _core().tier_state(id)
	var heading: Vector3 = (-(start["basis"] as Basis).z).rotated((start["basis"] as Basis).y, deg_to_rad(90.0))
	cap.set_course(heading, rest + heading * 15.0)
	await _fly(240.0)
	assert_true(bool(_core().tier_has(id)), "still far")
	var s: Dictionary = _core().tier_state(id)
	var nose: Vector3 = -(s["basis"] as Basis).z
	assert_lt(rad_to_deg(nose.angle_to(heading)), 3.0, "it turned onto its course out there")
	assert_almost_eq(((s["velocity"] as Vector3) - rest).length(), 15.0, 1.5, "and holds the speed its helm was told")
	var top: Vector3 = (s["basis"] as Basis).y
	var level: Vector3 = (Vector3.UP - nose * Vector3.UP.dot(nose)).normalized()
	assert_lt(rad_to_deg(top.angle_to(level)), 3.0, "level")


func test_two_far_hostile_omegas_close_on_each_other_under_their_brains() -> void:
	var a: CapitalShip = _omega("Far Omega", Factions.EARTH_ALLIANCE, FAR_M)
	var b: CapitalShip = _omega("Far Raider Omega", Factions.RAIDERS, FAR_M + 9000.0, 180.0)
	if a == null or b == null:
		return
	await _fly(10.0, func() -> bool: return bool(_core().tier_has(a.get_instance_id())) and bool(_core().tier_has(b.get_instance_id())))
	var gap: float = _gap(a, b)
	var thinks: int = int(CapitalBrains.of(main.world).brain_state(a).get("thinks", 0))
	await _fly(120.0)
	assert_true(bool(_core().tier_has(a.get_instance_id())), "both stay far")
	assert_gt(int(CapitalBrains.of(main.world).brain_state(a).get("thinks", 0)), thinks + 100, "its brain kept thinking")
	assert_eq(CapitalBrains.of(main.world).brain_state(a).get("state"), &"approach", "it approaches its target")
	assert_lt(_gap(a, b), gap - 2000.0, "they closed on each other (%.0f to %.0f m)" % [gap, _gap(a, b)])


func _gap(a: CapitalShip, b: CapitalShip) -> float:
	var pa: Vector3 = _core().tier_state(a.get_instance_id())["position"]
	var pb: Vector3 = _core().tier_state(b.get_instance_id())["position"]
	return pa.distance_to(pb)


func test_back_in_play_it_keeps_the_course_its_helm_had_out_there() -> void:
	var cap: CapitalShip = _omega("Far Omega", Factions.EARTH_ALLIANCE, FAR_M)
	if cap == null:
		return
	var id: int = cap.get_instance_id()
	await _fly(10.0, func() -> bool: return bool(_core().tier_has(id)))
	var rest: Vector3 = main.world.rest_velocity()
	var heading: Vector3 = -cap.global_basis.z
	cap.set_course(heading, rest - heading * 30.0)  # astern toward the player, back inside the tier's radius
	await _fly(300.0, func() -> bool: return not bool(_core().tier_has(id)))
	assert_false(bool(_core().tier_has(id)), "it came back in play")
	await _fly(2.0)
	assert_almost_eq((cap.cruise_velocity - rest).length(), 30.0, 0.5, "its course is the helm's, not the one it left with")
	assert_almost_eq((cap.linear_velocity - rest).length(), 30.0, 2.0, "and it flies it")


func test_a_scenario_capital_with_a_free_helm_starts_under_its_brain() -> void:
	remove_child(main)
	main.queue_free()
	await wait_physics_frames(1)
	await _launch("res://tests/fixtures/scenarios/capital_helm_free.json")
	await _fly(3.0)
	var held: Array = []
	for cap: CapitalBody in main.scenario_capitals:
		var ship := cap as CapitalShip
		if ship != null:
			held.append(bool(CapitalBrains.of(main.world).brain_state(ship).get("held", true)))
	assert_eq(held, [true, false], "the line-up's default holds it; `helm: free` leaves the other to its brain")
