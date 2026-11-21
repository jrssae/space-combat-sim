extends GutTest
## Fighters first at the bay, in free flight with the station's run of civilians going (M8-T06; the maintainer's play-test,
## 2026-11-19: "2nd dock failed ... a narn transport also trying to dock and failing"). The player docks twice, each time
## with a civilian on the docking lane and more queued behind it. Before the fix the fighter waited on the lane's own line for
## the lane, every civilian in turn took the lane and could not pass it, and neither ever docked. Now the civilian on the lane
## stands aside, the queue holds, the fighter docks at once, and the civilians dock afterwards. Flown with the physics rate
## and the time scale raised together.

const SPEED_UP: float = 8.0
## Where the player starts each dock, in the station's frame: 1.2 km off the bay's mouth, off the lane's line.
const START := Vector3(200.0, -150.0, -4700.0)

var main: Main
var station: Station
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8
var _rams: PackedStringArray = PackedStringArray()
var _watched: Dictionary = {}


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()  # a quarter of an hour of traffic per run


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	_rams = PackedStringArray()
	_watched = {}
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# Flies until `done` or `limit_s` of sim time; whether it was done. Every civilian bound for the bay has its rams counted.
func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		_watch_civilians()
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func _watch_civilians() -> void:
	for c: Combatant in main.traffic.ships():
		var key: int = c.ship.get_instance_id()
		if _watched.has(key) or main.traffic.state_of(c) == &"raid":
			continue
		_watched[key] = true
		var callsign: String = c.display_name
		c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
			if info != null and info.cause == HitInfo.CAUSE_RAM:
				_rams.append("%s at %.0f s" % [callsign, SimClock.now()]))


# How far along the docking lane `ship` is from the mouth, m (negative outside).
func _along(ship: Ship) -> float:
	var plan: DockingPlan = main.docking.plan
	var axis: Vector3 = (plan.mouth - (plan.dock_in[0]["at"] as Vector3)).normalized()
	return (station.global_transform.affine_inverse() * ship.global_position - plan.mouth).dot(axis)


# The civilian that has the docking lane and can still be asked aside, or null.
func _on_the_lane() -> Combatant:
	for c: Combatant in main.traffic.ships():
		if main.traffic.state_of(c) == &"lane" and main.traffic.kind_of(c) == &"dock" \
				and _along(c.ship) < -main.docking.commit_out_m - 300.0 and _along(c.ship) > -4000.0:
			return c
	return null


# The player, put 1.2 km off the bay at rest, docks and launches again; `{took_s, skipped, yielded}`.
func _dock(label: String) -> Dictionary:
	var yielded_before: int = main.traffic.yielded_count
	main.ship.reset_to(Transform3D(Basis.looking_at(station.global_basis.z, station.global_basis.y), station.global_transform * START))
	main.ship.linear_velocity = main.world.anchored_velocity()
	await get_tree().physics_frame
	var docked: Array[int] = [0]
	var count := func() -> void: docked[0] += 1
	main.docking.player_docked.connect(count)
	var t0: float = SimClock.now()
	assert_eq(main.docking.start_player(DockVisit.WHY_CONSOLE), "", "%s dock: the autopilot takes the ship" % label)
	var ok: bool = await _until(func() -> bool: return docked[0] == 1, 240.0)
	main.docking.player_docked.disconnect(count)
	var took_s: float = SimClock.now() - t0
	var visit: DockVisit = main.docking.player_visit()
	var skipped: bool = visit != null and visit.skipped
	assert_true(ok, "%s dock: it docks (%s; %s)" % [label, main.docking.describe(), main.traffic.last_event])
	assert_true(await _until(func() -> bool: return main.docking.player_visit() == null, 60.0), "%s dock: launched again" % label)
	return {"took_s": took_s, "skipped": skipped, "yielded": main.traffic.yielded_count - yielded_before}


func test_the_player_docks_twice_through_the_stations_run_of_civilians_and_they_dock_after() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 5
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	station = main.far_props.station
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	main.combatant.damageable.invulnerable = true
	assert_true(_run("traffic auto on").ok)
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var docked_before: int = 0
	for label: String in ["first", "second"]:
		# A civilian has the lane, far enough out to be asked aside.
		assert_true(await _until(func() -> bool: return _on_the_lane() != null, 900.0),
				"%s dock: a civilian is flying the docking lane (%s)" % [label, main.traffic.last_event])
		var civilian: Combatant = _on_the_lane()
		if civilian == null:
			return
		var result: Dictionary = await _dock(label)
		gut.p("%s dock with %s on the lane at %.0f m: %.0f s, %d stood aside, %d civilians bound for the bay" % [label,
				civilian.display_name, _along(civilian.ship), result["took_s"], result["yielded"], main.traffic.alive_of(&"dock")])
		assert_false(bool(result["skipped"]), "%s dock: flown, not jumped by the timeout" % label)
		assert_lt(float(result["took_s"]), 120.0, "%s dock: no long wait behind the civilians" % label)
		assert_gte(int(result["yielded"]), 1, "%s dock: the civilian on the lane stood aside" % label)
		assert_false(main.docking.claims_bay(), "%s dock: the bay is the civilians' again" % label)
		docked_before = main.traffic.docked_count
	# Nobody stalls for good: the civilians that stood aside or queued dock once the fighter is in.
	var ok: bool = await _until(func() -> bool: return main.traffic.docked_count >= docked_before + 2, 1200.0)
	assert_true(ok, "two more civilians docked after the fighter (%d then, %d now; %s)" % [docked_before, main.traffic.docked_count,
			main.traffic.last_event])
	assert_eq(_rams.size(), 0, "no civilian hit anything on its way: %s" % [_rams])
