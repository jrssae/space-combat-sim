extends GutTest
## Traffic at the station on the real main scene (M7-T10, AC9, Q8 as refined): a civilian flies into the main docking bay
## with the drum's roll matched and leaves the world at the inner airlock; one comes out and leaves; a Saturn backs in at the
## cargo bay's hold point and the station's maintenance bots start carrying its pods into the bay (M7-T30; the whole cycle of
## each hull is in `test_freighter_cargo`), and it leaves nose first; a wing scrambled from its Cobra
## arm is a wing with a leader and orders, and it engages a raid sent at the station. Flown with the physics rate and the
## time scale raised together.

const SCENARIO: String = "res://data/scenarios/station_launch.json"
const SPEED_UP: float = 8.0

var main: Main
var station: Station
var rams: int = 0
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	rams = 0
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
	if station == null:
		return false
	main.combatant.damageable.invulnerable = true
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


func _watch_rams(c: Combatant) -> void:
	c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
		rams += 1 if info != null and info.cause == HitInfo.CAUSE_RAM else 0)


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# Whether a bot the pod needs is not holding it.
static func _unheld(pod: FerryPod) -> bool:
	for k: int in pod.holding.size():
		if pod.needs(k) and pod.holding[k] == 0:
			return true
	return false


func test_a_civilian_matches_the_drums_roll_flies_in_and_leaves_the_world_at_the_airlock() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var result: ConsoleResult = _run("traffic dock near")
	assert_true(result.ok, "\n".join(result.lines))
	var c: Combatant = main.traffic.last_ship()
	assert_not_null(c, "a civilian took the lane")
	if c == null:
		return
	assert_true(DockingPlan.TUNNEL_TYPES.has(main.ships.type_of(c)), "a hull that fits the tunnel")
	_watch_rams(c)
	var mouth: Vector3 = main.traffic.plan.mouth
	var axis: Vector3 = (station.global_basis * Vector3.BACK).normalized()
	var rolls := PackedFloat64Array()
	var off_axis: Array[float] = [0.0]
	var docked: Array[String] = []
	main.traffic.docked.connect(func(ship_name: String) -> void: docked.append(ship_name))
	var ship: Ship = c.ship
	var ok: bool = await _until(func() -> bool:
		if docked.is_empty() and is_instance_valid(ship):
			var local: Vector3 = station.to_local(ship.global_position)
			if local.z > mouth.z - 120.0:
				# From 120 m outside the mouth on: the roll about the tunnel's axis, and how far off the axis it flies.
				rolls.append(ship.angular_velocity.dot(axis))
				off_axis[0] = maxf(off_axis[0], Vector2(local.x, local.y).length())
		return not docked.is_empty(), 90.0)
	assert_true(ok, "it reached the inner airlock (%s)" % main.traffic.last_event)
	assert_eq(main.traffic.docked_count, 1)
	assert_eq(main.traffic.alive_count(), 0, "and left the world: back in its pool")
	assert_eq(rams, 0, "without touching the turning tunnel")
	assert_gt(rolls.size(), 10)
	var spin: float = station.hardpoints.spin_rad_s
	for roll: float in rolls:
		if absf(roll - spin) > 0.2 * spin:
			fail_test("the roll matches the drum's %.3f rad/s from before the mouth: %.3f" % [spin, roll])
			break
	assert_lt(off_axis[0], 12.0, "on the tunnel's axis (17 m to its floor and roof)")
	gut.p("docking: roll %.3f to %.3f rad/s against the drum's %.3f, at most %.1f m off the axis" % [
			Array(rolls).min(), Array(rolls).max(), spin, off_axis[0]])


func test_a_civilian_comes_out_of_the_main_docking_bay_and_departs() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var result: ConsoleResult = _run("traffic undock")
	assert_true(result.ok, "\n".join(result.lines))
	var c: Combatant = main.traffic.last_ship()
	_watch_rams(c)
	var far: Vector3 = main.traffic.plan.dock_in[0]["at"]
	var ship: Ship = c.ship
	assert_almost_eq(ship.angular_velocity.dot(station.global_basis * Vector3.BACK), station.hardpoints.spin_rad_s, 0.01,
			"it starts turning with the drum")
	assert_true(await _until(func() -> bool: return station.to_local(ship.global_position).z < far.z + 200.0, 90.0),
			"it flew out past the approach's far point")
	assert_eq(rams, 0, "without touching the tunnel")
	assert_eq(main.traffic.alive_of(&"undock"), 1, "and flies on to where it leaves")


func test_a_freighter_backs_in_and_the_bots_carry_its_first_pod_into_the_cargo_bay() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var result: ConsoleResult = _run("traffic freighter saturn_3_freighter near")
	assert_true(result.ok, "\n".join(result.lines))
	var c: Combatant = main.traffic.last_ship()
	assert_eq(main.ships.type_of(c), DockingPlan.FREIGHTER_TYPE)
	_watch_rams(c)
	var ship: Ship = c.ship
	var hold: Vector3 = station.hardpoints.cargo_bay["cargo_bay_hold"]
	var entry: Vector3 = station.hardpoints.cargo_bay["cargo_bay_entry"]
	var to_bay: Vector3 = (station.global_basis * (entry - hold)).normalized()
	var unloading: Array[String] = []
	main.traffic.freighter_unloading.connect(func(ship_name: String) -> void: unloading.append(ship_name))
	# The last 300 m to the hold point are flown stern first.
	var backing: Array[float] = [1.0]
	var ok: bool = await _until(func() -> bool:
		var left: float = station.to_local(ship.global_position).distance_to(hold)
		if unloading.is_empty() and left < 300.0 and left > 20.0:
			backing[0] = minf(backing[0], (-ship.global_basis.z).dot(-to_bay))
		return not unloading.is_empty(), 240.0)
	assert_true(ok, "it reached the hold point and began to unload")
	assert_gt(backing[0], 0.9, "backing in: its nose away from the bay all the way (worst %.2f)" % backing[0])
	assert_lt(station.to_local(ship.global_position).distance_to(hold), 20.0, "at the hold point")
	assert_lt((-ship.global_basis.z).dot(to_bay), -0.9, "stern and pods toward the bay")
	assert_false(ship.hull.visible, "its hull is hidden: the stand-in parts and the pods show")
	var cargo := ship.get_node_or_null(NodePath(FreighterCargo.NODE_NAME)) as FreighterCargo
	assert_not_null(cargo)
	assert_eq(cargo.pod_count(), 3)
	assert_eq(cargo.crew_bots.size(), CargoFerryJob.CREW, "a crew of bots for it in the station's fleet")
	var moved_alone: Array[int] = [0]
	var last: Array = [null, 0.0]
	var carried: bool = await _until(func() -> bool:
		var pod: FerryPod = cargo.job.current() if is_instance_valid(cargo) and cargo.job != null else null
		if pod != null and pod == last[0] and absf(pod.s - float(last[1])) > 1e-6 and _unheld(pod):
			moved_alone[0] += 1
		last[0] = pod
		last[1] = pod.s if pod != null else 0.0
		return main.traffic.pods_in >= 1, 240.0)
	assert_true(carried, "a bot carried the first pod into the cargo bay")
	assert_eq(moved_alone[0], 0, "no pod moved by itself")
	assert_eq(main.traffic.alive_of(&"freighter"), 1, "the freighter never went in")
	assert_eq(rams, 0, "and touched nothing")
	var bots_before: int = station.bots.ferry_bots.size()
	_run("traffic clear")
	assert_eq(station.bots.ferry_bots.size(), bots_before - CargoFerryJob.CREW, "its crew went with it")
	assert_true(ship.hull.visible or ship.is_far_dot(), "back in its pool whole")


func test_a_scrambled_wing_is_a_wing_with_orders_and_engages_a_raid_on_the_station() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var result: ConsoleResult = _run("traffic raid 4")
	assert_true(result.ok, "\n".join(result.lines))
	assert_eq(main.traffic.alive_of(&"raid"), 4, "four raiders sent at the station")
	for entry: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		assert_eq(((entry.driver as AiPilotDriver).brain as AiPilot).context.objective_name, Station.DISPLAY_NAME)
	result = _run("traffic scramble beta")
	assert_true(result.ok, "\n".join(result.lines))
	var wing: Wing = main.wings.wing_named("BETA")
	assert_not_null(wing, "the launch made the station's wing")
	if wing == null:
		return
	assert_not_null(wing.leader, "with a leader")
	assert_eq(wing.members().size(), 11, "and eleven on its slots")
	assert_eq(wing.order, AiContext.Order.ENGAGE_AT_WILL)
	await get_tree().physics_frame
	var second: AiPilot = (wing.members()[0].driver as AiPilotDriver).brain as AiPilot
	assert_true(second.context.has_slot, "a member is briefed with its slot")
	assert_eq(second.context.leader_id, wing.leader.targetable.get_instance_id())
	# Both waves away, then the raid arrives: some of the wing fight it.
	var raider_ids: Dictionary = {}
	for raider: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		raider_ids[raider.targetable.get_instance_id()] = true
	var engaged: bool = await _until(func() -> bool:
		for ally: Combatant in main.ships.alive(ShipPool.ALLY_TYPE):
			if raider_ids.has(ally.ship.targeting.selected_id()):
				return true
		return main.ships.alive(ShipPool.DEFAULT_TYPE).size() < 4, 200.0)
	assert_true(engaged, "the wing engaged the raid")
