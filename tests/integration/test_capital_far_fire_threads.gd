extends GutTest
## Far capitals fire the same with one thread and six (M10-T85): 24 Omegas in two hostile lines broadside 2.4 km apart (3 km
## between neighbours, so no two hulls touch), 20 km off the player, every one a tier row firing its guns and launchers as seeded rolls (from the tick the comparison starts, as
## `test_capital_far_fleet` compares). The far hits each tick, the hulls' rows and the counts match byte for byte. Reports the
## far rolls' cost and their landing's with the fleet.

const TICKS: int = 900
const PER_SIDE: int = 12
## The sim clock's ticks the fleet spawns on and the comparison starts on.
const SPAWN_TICK: int = 30
const START_TICK: int = 240

var _threads_backup: Variant = null
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	DebugConsole.flags.invulnerable = false


func test_a_far_fleet_fires_the_same_with_one_thread_and_six() -> void:
	var one: Dictionary = await _fleet(1)
	var six: Dictionary = await _fleet(6)
	assert_eq(int(one["far"]), 2 * PER_SIDE, "every Omega a tier row")
	assert_gt(int(one["hits"]), 100, "they hit each other (%d far hits)" % int(one["hits"]))
	assert_eq(_first_difference(one["digests"], six["digests"]), -1, "the same far hits and rows each tick")


func _first_difference(a: Array, b: Array) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i: int in a.size():
		if a[i] != b[i]:
			return i
	return -1


func _fleet(threads: int) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	SimClock.reset()  # every run's frame and seeds from the same clock, as the seeded battle's
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 3
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	DebugConsole.flags.invulnerable = true
	while SimClock.ticks < SPAWN_TICK:
		await get_tree().physics_frame
	var rest: Vector3 = main.world.rest_velocity()
	var nose: Basis = main.ship.global_basis
	var caps: Array[CapitalShip] = []
	for side: int in 2:
		for k: int in PER_SIDE:
			var faction: StringName = Factions.EARTH_ALLIANCE if side == 0 else Factions.RAIDERS
			var cap: CapitalShip = CapitalShip.create(&"ea_omega", faction, "Omega %d-%d" % [side, k], rest)
			var at: Vector3 = main.ship.global_position - nose.z * (20000.0 + 2400.0 * side) + nose.x * (3000.0 * (k - PER_SIDE / 2))
			main.world.spawn(cap, main.world.to_universe(at), nose.rotated(nose.y, PI * 0.5))
			cap.damageable.invulnerable = true
			caps.append(cap)
	var core: Object = SimCore.for_tree(get_tree()).core
	var guns: CapitalGuns = CapitalGuns.of(main.world)
	var rows: Object = guns._native()
	await get_tree().physics_frame
	for cap: CapitalShip in caps:
		guns.hold(cap, true)  # nothing fires until the comparison starts, the tier holding them all
		CapitalBeams.of(main.world).hold(cap, true)
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, 4)
	while SimClock.ticks < START_TICK:
		await get_tree().physics_frame
	var far: int = int(core.tier_capitals())
	for cap: CapitalShip in caps:
		guns.hold(cap, false)
		CapitalBeams.of(main.world).hold(cap, false)
	rows.set_far_log(true)
	var start: PackedInt64Array = rows.far_readouts()
	var digests: Array[int] = []
	var roll_us: Array[float] = []
	var land_us: Array[float] = []
	# Ships by their place in the fleet: instance ids differ from run to run.
	var index_of: Dictionary = {}
	for k: int in caps.size():
		index_of[caps[k].get_instance_id()] = k
		index_of[caps[k].damageable.get_instance_id()] = k
	while SimClock.ticks < START_TICK + TICKS:
		await get_tree().physics_frame
		var text: String = _log_text(rows.far_log(), index_of) + str(rows.far_readouts())
		for cap: CapitalShip in caps:
			var st: Dictionary = core.tier_state(cap.get_instance_id())
			text += str(st.get("position")) + str(st.get("basis"))
		digests.append(text.hash())
		rows.set_far_log(true)
		roll_us.append(float(rows.far_us()))
		land_us.append(float(guns.far.land_us))
	var end: PackedInt64Array = rows.far_readouts()
	if threads == 1:
		roll_us.sort()
		land_us.sort()
		var mean := func(a: Array[float]) -> float:
			var s: float = 0.0
			for x: float in a:
				s += x
			return s / maxf(a.size(), 1.0)
		gut.p("far fleet of %d Omegas: rolls median %.0f us, mean %.0f, p99 %.0f; landing (GDScript and the batch) mean %.0f us, p99 %.0f; %d bolts rolled, %d far hits, %d taken by batteries in %d ticks" % [
				caps.size(), roll_us[roll_us.size() / 2], mean.call(roll_us), roll_us[roll_us.size() * 99 / 100], mean.call(land_us),
				land_us[land_us.size() * 99 / 100], end[1] - start[1], end[3] - start[3], end[5] - start[5], TICKS])
	var out: Dictionary = {"digests": digests, "far": far, "hits": end[3] - start[3]}
	remove_child(main)
	main.free()
	await get_tree().physics_frame
	return out


# The far hits of a tick by fleet index, damage and point.
func _log_text(log: Array, index_of: Dictionary) -> String:
	var text: String = ""
	for column: int in 3:
		for id: int in log[column] as PackedInt64Array:
			text += "%d," % int(index_of.get(id, -1))
	return text + str(log[3]) + str(log[4]) + str(log[5])
