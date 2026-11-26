extends GutTest
## An Asimov liner's whole visit in free flight (M10-T53, Q85), headless on the real main scene: it comes out of the jumpgate,
## flies the 50 km to its standoff spot off Babylon 5's docking sphere and holds there; its crew shuttle and its Kestrel
## leave its bay, fly into the main docking bay by the lane, wait inside, come out and are taken back into the bay, twice
## each (unload, load); then it flies back and leaves through the gate. Nothing rams anything. A slow file: about 40 min of
## flight on a shortened clock (short waits; the flying is not shortened).

const SPEED_UP: float = 8.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


# A slow file (M4-T36, Q58): runs with GUT_SLOW=1 (the full run and CI), skipped in focused runs.
@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false


# Flies until `done` or `limit_s` of sim time; whether it was done.
func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func test_a_liner_comes_through_the_gate_sends_its_shuttles_twice_and_leaves_through_the_gate() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 5
	main.encounters = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if main.far_props.station == null or main.gates.gate() == null or not main.traffic.lanes_ready():
		pending("the station or the jumpgate is not generated")
		return
	main.combatant.damageable.invulnerable = true
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var traffic: StationTraffic = main.traffic
	var liners: LinerTraffic = traffic.liners
	var gate: Jumpgate = main.gates.gate()
	liners.inside_s = Vector2(10.0, 10.0)
	liners.aboard_s = Vector2(10.0, 10.0)
	watch_signals(traffic)
	var arrived_before: int = gate.arrived
	var departed_before: int = gate.departed
	var t0: float = SimClock.now()
	# A stay long enough for both trips: it leaves when the stay is over and its shuttles are home.
	var answer: ConsoleResult = DebugConsole.registry.execute("traffic liner 1200")[0]
	assert_true(answer.ok, answer.text())
	var visit: LinerVisit = liners.visits[0]
	assert_true(await _until(func() -> bool: return visit.phase == LinerVisit.INBOUND, 30.0), "out of the gate")
	assert_eq(gate.arrived, arrived_before + 1)
	var liner: CapitalShip = visit.ship
	var hull: float = liner.damageable.hull.fraction()
	assert_lt(liner.global_position.distance_to(gate.global_position), 3000.0)
	assert_true(await _until(func() -> bool: return visit.phase == LinerVisit.HOLDING, 1500.0), "at its spot: %s" % liners.text())
	var inbound_s: float = SimClock.now() - t0
	var spot: Vector3 = main.far_props.station.global_transform * liners.spots[visit.slot]
	assert_lt(liner.global_position.distance_to(spot), liners.arrive_m)
	var rams: Array[int] = [0]
	var seen: Dictionary = {}
	var farthest: Array[float] = [0.0]
	var check_1: Callable = func() -> bool:
		for s: Dictionary in visit.shuttles:
			var c: Combatant = s.get("combatant")
			if c != null and not seen.has(c):
				seen[c] = true
				c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
					rams[0] += 1 if info != null and info.cause == HitInfo.CAUSE_RAM else 0)
		farthest[0] = maxf(farthest[0], liner.global_position.distance_to(spot))
		return visit.trips_done()
	assert_true(await _until(check_1, 2400.0), "both shuttles flew both trips: %s" % liners.text())
	var trips_s: float = SimClock.now() - t0 - inbound_s
	assert_eq(liners.trips_flown, 4)
	assert_signal_emit_count(traffic, "docked", 4, "four times into the docking bay")
	assert_eq(rams[0], 0, "no shuttle rammed anything")
	assert_lt(farthest[0], liners.arrive_m + 100.0, "the liner held station throughout")
	assert_eq(liner.hangar.out_count(), 0)
	assert_true(await _until(func() -> bool: return visit.phase == LinerVisit.OUTBOUND, 1300.0), "its stay over, it leaves: %s" % liners.text())
	assert_true(await _until(func() -> bool: return liners.liners_left == 1, 1500.0), "through the gate: %s" % liners.text())
	assert_eq(gate.departed, departed_before + 1, "by the gate's vortex, not let go past it")
	assert_eq(liners.in_play(), 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(is_instance_valid(liner), "the liner left the world")
	assert_eq(traffic.alive_count(), 0)
	gut.p("liner visit: %.0f s in from the gate, %.0f s for both shuttles' two trips, %.0f s in all; tick mean %.1f us" % [
			inbound_s, trips_s, SimClock.now() - t0, liners.mean_us()])
	assert_gt(hull, 0.0)
