extends GutTest
## The station's maintenance bots carrying a freighter's cargo on the real main scene (M7-T30): each of the five Saturns holding at
## the cargo bay has its pods or tanks carried into the bay by bots, pod by pod, nothing flying by itself, and then leaves; a
## Saturn come to load has its pods brought out to it and its hull whole again at the end; and when fighting starts the bots let go,
## the pod waits, and after the quiet they come back for it. Flown with the physics rate and the time scale raised together; a slow
## file (several minutes of cargo work per hull).

const SCENARIO: String = "res://data/scenarios/station_launch.json"
const SPEED_UP: float = 8.0
const PODS: Dictionary = {"saturn_3_freighter": 3, "saturn_4_transport": 2, "saturn_4_tanker": 2, "saturn_8_transport": 4,
		"saturn_8_tanker": 4}

var main: Main
var station: Station
var moved_alone: int = 0
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


# A slow file (M4-T36, Q58): runs with GUT_SLOW=1 (the full run and CI), skipped in focused runs.
@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	moved_alone = 0
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> bool:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	station = main.far_props.station
	if station == null or station.bots == null:
		return false
	main.combatant.damageable.invulnerable = true
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	return true


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# Whether a bot the pod needs is not holding it.
static func _unheld(pod: FerryPod) -> bool:
	for k: int in pod.holding.size():
		if pod.needs(k) and pod.holding[k] == 0:
			return true
	return false


# Flies until `done` or `limit_s` of sim time, watching that the current pod never moves without a bot holding it.
func _until(done: Callable, limit_s: float, cargo: FreighterCargo = null) -> bool:
	var t0: float = SimClock.now()
	var last_pod: FerryPod = null
	var last_s: float = 0.0
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		if cargo != null and is_instance_valid(cargo) and cargo.job != null:
			var pod: FerryPod = cargo.job.current()
			if pod != null and pod == last_pod and absf(pod.s - last_s) > 1e-6 and _unheld(pod):
				moved_alone += 1
			last_pod = pod
			last_s = pod.s if pod != null else 0.0
		await get_tree().physics_frame
	return bool(done.call())


# Starts `line` and returns the freighter's cargo once its bots are at work, or null.
func _freighter(line: String) -> FreighterCargo:
	var result: ConsoleResult = _run(line)
	assert_true(result.ok, "\n".join(result.lines))
	var c: Combatant = main.traffic.last_ship()
	if c == null:
		return null
	var cargo: Array[FreighterCargo] = [null]
	await _until(func() -> bool:
		cargo[0] = c.ship.get_node_or_null(NodePath(FreighterCargo.NODE_NAME)) as FreighterCargo
		return cargo[0] != null and cargo[0].job != null, 30.0)
	return cargo[0]


func test_each_saturn_is_unloaded_by_the_bots_and_leaves() -> void:
	if not await _start():
		pending("the babylon5_station asset (or its bots) is not generated")
		return
	var fleet: BotFleet = station.bots
	var baseline: int = fleet.ferry_bots.size()
	for hull: String in PODS:
		moved_alone = 0
		var before_in: int = main.traffic.pods_in
		var cargo: FreighterCargo = await _freighter("traffic freighter %s hold" % hull)
		assert_not_null(cargo, "%s: the bots came for its cargo" % hull)
		if cargo == null:
			continue
		var ship: Ship = cargo.ship
		assert_eq(cargo.pod_count(), int(PODS[hull]), hull)
		assert_eq(fleet.ferry_bots.size(), baseline + CargoFerryJob.CREW, "%s: its crew is in the fleet" % hull)
		var done: bool = await _until(func() -> bool: return main.traffic.pods_in - before_in == int(PODS[hull]), 900.0, cargo)
		assert_true(done, "%s: every pod carried into the bay (%d)" % [hull, main.traffic.pods_in - before_in])
		assert_eq(moved_alone, 0, "%s: no pod moved by itself" % hull)
		assert_true(await _until(func() -> bool: return fleet.ferry_bots.size() == baseline, 30.0), "%s: the crew is gone" % hull)
		var hold: Vector3 = station.hardpoints.cargo_bay["cargo_bay_hold"]
		var left: bool = await _until(func() -> bool:
			return not is_instance_valid(ship) or station.to_local(ship.global_position).distance_to(hold) > 150.0, 120.0)
		assert_true(left, "%s: it left once the bots were done" % hull)
		if is_instance_valid(ship) and ship.visible:
			assert_false(ship.hull.visible, "%s leaves without its pods" % hull)
		_run("traffic clear")


func test_a_saturn_come_to_load_gets_its_pods_and_its_hull_back() -> void:
	if not await _start():
		pending("the babylon5_station asset (or its bots) is not generated")
		return
	var cargo: FreighterCargo = await _freighter("traffic freighter saturn_4_transport hold load")
	assert_not_null(cargo)
	if cargo == null:
		return
	var ship: Ship = cargo.ship
	assert_false(ship.hull.visible, "it came without its pods")
	var done: bool = await _until(func() -> bool: return main.traffic.pods_out == 2, 600.0, cargo)
	assert_true(done, "both pods carried out onto it (%d)" % main.traffic.pods_out)
	assert_eq(moved_alone, 0, "no pod moved by itself")
	# The hull comes back once the bots are home from the last pod.
	var whole: bool = await _until(func() -> bool: return ship.get_node_or_null(NodePath(FreighterCargo.NODE_NAME)) == null, 120.0)
	assert_true(whole, "the stand-ins are gone")
	assert_true(ship.hull.visible or ship.is_far_dot(), "the hull is whole again once the last pod is on")


func test_fighting_makes_the_bots_let_go_and_after_the_quiet_they_come_back() -> void:
	if not await _start():
		pending("the babylon5_station asset (or its bots) is not generated")
		return
	var cargo: FreighterCargo = await _freighter("traffic freighter saturn_4_transport hold")
	assert_not_null(cargo)
	if cargo == null:
		return
	var pod: FerryPod = cargo.job.current()
	assert_true(await _until(func() -> bool: return pod.state == FerryPod.State.MOVING and pod.s > pod.trip.unberth_s + 100.0, 300.0, cargo),
			"the first pod is on its way")
	_run("bots hide")
	assert_true(await _until(func() -> bool: return pod.state == FerryPod.State.DROPPED, 5.0), "the bots let go")
	var lie: float = pod.s
	assert_true(await _until(func() -> bool: return cargo.job.crew_inside(), 120.0), "and went inside")
	await _until(func() -> bool: return false, 20.0)
	assert_almost_eq(pod.s, lie, 1e-6, "the pod waits where it was let go")
	var node: Node3D = station.bots.frame_parent().find_child(pod.trip.pod_name.to_pascal_case(), false, false) as Node3D
	assert_true(node != null and node.visible, "and is still there to see")
	_run("bots show")
	assert_true(await _until(func() -> bool: return pod.state == FerryPod.State.MOVING, 300.0), "after the quiet they took it again")
	assert_true(await _until(func() -> bool: return pod.done(), 300.0, cargo), "and carried it into the bay")
	assert_eq(moved_alone, 0, "no pod moved by itself")
