extends GutTest
## Asimov liners in the station's traffic (M10-T53, Q85) on the real main scene, free flight with its jumpgate: the console
## spawns one (`traffic liner`), a second takes the other standoff spot under another name and a third is refused; a liner
## at its spot sends both shuttles into Babylon 5's docking bay and takes them back into its own bay, and leaves once its
## stay is over; the schedule brings visits through the gate by the run's clock, a pair at times, timed again from the
## departure. The whole visit from gate to gate is `test_liner_visit` (a slow file).

const SPEED_UP: float = 8.0

var main: Main
var liners: LinerTraffic
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


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


func _start() -> bool:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 5
	main.encounters = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if main.far_props.station == null or main.gates.gate() == null or not main.traffic.lanes_ready():
		return false
	main.combatant.damageable.invulnerable = true
	liners = main.traffic.liners
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	return true


# Flies until `done` or `limit_s` of sim time; whether it was done.
func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func test_the_console_spawns_liners_two_at_the_most_each_at_its_own_spot() -> void:
	if not await _start():
		pending("the station or the jumpgate is not generated")
		return
	var first: ConsoleResult = _run("traffic liner near 600")
	assert_true(first.ok, first.text())
	assert_eq(liners.in_play(), 1)
	var a: LinerVisit = liners.visits[0]
	assert_eq(a.phase, LinerVisit.HOLDING)
	assert_eq(a.stay_s, 600.0)
	assert_eq(a.shuttles.size(), 2, "the bay's crew shuttle and Kestrel")
	assert_true(a.ship.tier_exempt, "flown in full for its visit")
	assert_false(a.ship.hangar.auto, "its hangar is the traffic's to drive")
	var through_gate: ConsoleResult = _run("traffic liner")
	assert_true(through_gate.ok, through_gate.text())
	assert_eq(liners.in_play(), 2)
	var b: LinerVisit = liners.visits[1]
	assert_eq(b.phase, LinerVisit.GATE, "it waits for the gate's vortex")
	assert_ne(a.name, b.name, "two liners never share a name")
	assert_ne(a.slot, b.slot, "each has its own standoff spot")
	assert_false(_run("traffic liner").ok, "never more than two")
	assert_true(await _until(func() -> bool: return b.phase == LinerVisit.INBOUND, 30.0), "the second came out of the gate")
	var gate: Jumpgate = main.gates.gate()
	assert_lt(b.ship.global_position.distance_to(gate.global_position), 3000.0, "out of the jumpgate")
	var spot_a: Vector3 = main.far_props.station.global_transform * liners.spots[a.slot]
	assert_lt(a.ship.global_position.distance_to(spot_a), liners.arrive_m + 50.0, "the first holds at its spot")
	var state: String = str(DebugConsole.registry.execute("get traffic.liners")[0].text())
	assert_string_contains(state, a.name)
	assert_string_contains(state, "holding")
	assert_string_contains(state, "inbound")
	assert_string_contains(_run("traffic status").text(), "liners: ")
	# The lane, the freighters' lane and the run's two sides stay clear of both spots.
	var plan: DockingPlan = main.traffic.plan
	for spot: Vector3 in liners.spots:
		assert_gt(Vector2(spot.x, spot.y).length(), 1500.0, "off the docking lane's axis")
		assert_gt(spot.distance_to(plan.mouth), 2500.0, "off the docking sphere")
		assert_gt(spot.distance_to(plan.freighter[plan.freighter_hold_index]["at"] as Vector3), 2000.0)
	assert_gt(liners.spots[0].distance_to(liners.spots[1]), 2000.0)
	assert_string_contains(_run("traffic clear").text(), "2")
	assert_eq(liners.in_play(), 0)
	# `show` starts one at its spot and puts the player beside it, the liner ahead in view.
	assert_true(_run("traffic liner show").ok)
	var shown: CapitalShip = liners.visits[0].ship
	var to_liner: Vector3 = shown.global_position - main.ship.global_position
	assert_between(to_liner.length(), 1000.0, 2000.0)
	assert_gt((-main.ship.global_basis.z).dot(to_liner.normalized()), 0.9, "the player looks at it")
	assert_gt(to_liner.normalized().dot((main.far_props.station.global_transform * plan.mouth - shown.global_position).normalized()),
			0.9, "with the docking sphere beyond it")
	liners.clear()
	# No liner comes out of the gate while another flies out toward it: the two ways share the gate's axis.
	assert_eq(liners.start(0.0, true), "")
	var leaving: LinerVisit = liners.visits[0]
	assert_true(await _until(func() -> bool: return leaving.phase == LinerVisit.OUTBOUND, 5.0), "a stay of nothing: it leaves")
	assert_true(_run("traffic liner").ok)
	var waiting: LinerVisit = liners.visits[1]
	await _until(func() -> bool: return false, 20.0)
	assert_eq(waiting.phase, LinerVisit.GATE)
	assert_false(waiting.asked, "its arrival is not asked of the gate yet")
	liners.clear()
	# Four liners came and went: the pool holds the shuttles a visit needs, not two more a visit, and all are back in it.
	for type: StringName in [&"ea_shuttle", &"ea_atmo_shuttle"]:
		assert_lte(main.ships.pool_size(type), 2, "%s in the pool" % type)
		assert_eq(main.ships.free_count(type), main.ships.pool_size(type))


func test_a_liner_at_its_spot_sends_both_shuttles_into_the_docking_bay_and_takes_them_back() -> void:
	if not await _start():
		pending("the station or the jumpgate is not generated")
		return
	liners.inside_s = Vector2(5.0, 5.0)
	watch_signals(main.traffic)
	assert_eq(liners.start(60.0, true), "")
	var visit: LinerVisit = liners.visits[0]
	var hull: float = visit.ship.damageable.hull.fraction()
	var rams: Array[int] = [0]
	var seen: Dictionary = {}
	var inside: Array[int] = [0]
	var check_1: Callable = func() -> bool:
		for s: Dictionary in visit.shuttles:
			var c: Combatant = s.get("combatant")
			if c != null and not seen.has(c):
				seen[c] = true
				c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
					rams[0] += 1 if info != null and info.cause == HitInfo.CAUSE_RAM else 0)
			inside[0] = maxi(inside[0], main.traffic.inside_count())
		return liners.trips_flown >= 2
	assert_true(await _until(check_1, 900.0), "both shuttles flew to the docking bay and home: %s" % liners.text())
	assert_signal_emit_count(main.traffic, "docked", 2, "each went in behind the inner doors")
	assert_gt(inside[0], 0, "and was inside the station, off the radar")
	assert_eq(rams[0], 0, "no shuttle rammed the station, the liner or the other")
	assert_eq(visit.ship.damageable.hull.fraction(), hull, "the liner is untouched")
	assert_eq(visit.ship.hangar.out_count(), 0, "both are back in its bay")
	assert_eq(main.traffic.alive_count(), 0, "and off the traffic's list")
	# Its stay ran out meanwhile: no second trip starts, and it leaves for the gate.
	assert_true(await _until(func() -> bool: return visit.phase == LinerVisit.OUTBOUND, 30.0), liners.text())
	for s: Dictionary in visit.shuttles:
		assert_eq(s["leg"], LinerVisit.ABOARD)
		assert_eq(int(s["trip"]), 1)
	assert_eq(main.gates.gate().departing(), 1, "the gate expects it")
	assert_lt(liners.mean_us(), 200.0, "a liner and its shuttles cost little here")
	gut.p("liner tick: mean %.1f us" % liners.mean_us())


func test_the_schedule_brings_visits_through_the_gate_and_times_the_next_from_the_departure() -> void:
	if not await _start():
		pending("the station or the jumpgate is not generated")
		return
	var traffic: StationTraffic = main.traffic
	traffic.lane_ships = 0
	traffic.auto_forced = true
	traffic.auto = true
	liners.schedule = LinerSchedule.from_data({"first_s": [4, 4], "gap_s": [20, 20], "stay_s": [0, 0], "pair_share": 1.0}, 5, 21)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(liners.next_in_s(), 4.0, 0.2, "the first visit is timed on the run's clock")
	assert_eq(liners.in_play(), 0)
	assert_true(await _until(func() -> bool: return liners.in_play() == 2, 6.0), "a pair came by the schedule")
	assert_eq(liners.visits_started, 1)
	assert_ne(liners.visits[0].name, liners.visits[1].name)
	assert_ne(liners.visits[0].slot, liners.visits[1].slot)
	assert_eq(liners.next_in_s(), -1.0, "no visit is timed while liners are at the station")
	var both_in: Callable = func() -> bool:
		return liners.visits[0].phase == LinerVisit.INBOUND and liners.visits[1].phase == LinerVisit.INBOUND
	assert_true(await _until(both_in, 90.0), liners.text())
	var first: CapitalShip = liners.visits[0].ship
	var second: CapitalShip = liners.visits[1].ship
	assert_gt(first.global_position.distance_to(second.global_position), 2500.0, "one at a time out of the gate")
	await _until(func() -> bool: return false, 30.0)
	assert_eq(liners.visits_started, 1, "nor does one start, however long they take")
	assert_eq(first.damageable.hull.fraction(), 1.0, "they never met")
	assert_eq(second.damageable.hull.fraction(), 1.0)
	# Both leave their spots (a stay of nothing, no shuttle out), one well ahead of the other; the next visit is timed a gap
	# from the last one's departure.
	var leader: LinerVisit = liners.visits[0]
	var follower: LinerVisit = liners.visits[1]
	leader.phase = LinerVisit.HOLDING
	follower.phase = LinerVisit.HOLDING
	assert_true(await _until(func() -> bool: return leader.phase == LinerVisit.OUTBOUND, 5.0), liners.text())
	await _until(func() -> bool: return false, 10.0)
	assert_eq(follower.phase, LinerVisit.HOLDING, "the second waits for the first to draw ahead")
	assert_eq(liners.next_in_s(), -1.0, "and no visit is timed until it has left too")
	# The first put well ahead (to the station's side of the second, away from the gate both still fly near).
	first.global_position = second.global_position + (first.global_position - second.global_position).normalized() \
			* (LinerTraffic.OUT_GAP_M + 500.0)
	assert_true(await _until(func() -> bool: return follower.phase == LinerVisit.OUTBOUND, 5.0), liners.text())
	assert_almost_eq(liners.next_in_s(), 20.0, 1.0, "a gap from the last departure")
	liners.schedule.pair_share = 0.0
	liners.clear()
	assert_true(await _until(func() -> bool: return liners.visits_started == 2, 25.0), "the next visit came")
	assert_eq(liners.in_play(), 1, "a single liner this time")
	# Control's shelter holds the schedule back.
	liners.clear()
	traffic.set_shelter(true)
	await _until(func() -> bool: return false, 30.0)
	assert_eq(liners.visits_started, 2, "no liner comes while the civilians shelter")
