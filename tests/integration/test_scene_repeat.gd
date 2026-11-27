extends GutTest
## A battle loaded again in the same process plays as its first run did (M10-T85 follow-up): three Omegas spawned in a line
## with their hulls overlapping (rotated 90 degrees, 1.5 km apart), pushed apart by Jolt and flown by their helms, in play and
## far off, give the same rows every tick in a first scene, a second one with one thread and a third with six. Jolt's results
## hang on the order its bodies were made in, so each `Main` takes a physics space of its own.

const SPAWN_TICK: int = 30
const END_TICK: int = 240

var _threads_backup: Variant = null


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)
	DebugConsole.flags.invulnerable = false


func test_a_scene_loaded_again_plays_as_its_first_run() -> void:
	for ahead_m: float in [3000.0, 20000.0]:
		var first: Dictionary = await _run(1, ahead_m)
		var again: Dictionary = await _run(1, ahead_m)
		var six: Dictionary = await _run(6, ahead_m)
		assert_ne(first["world"], again["world"], "each scene its own world")
		var rows: Array = first["rows"]
		assert_eq(rows.size(), END_TICK - SPAWN_TICK, "every tick recorded")
		assert_eq(_first_difference(rows, again["rows"]), -1, "%.0f m off: the second scene the same, tick for tick" % ahead_m)
		assert_eq(_first_difference(rows, six["rows"]), -1, "%.0f m off: and with six threads" % ahead_m)


func _first_difference(a: Array, b: Array) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i: int in a.size():
		if a[i] != b[i]:
			return i
	return -1


func _run(threads: int, ahead_m: float) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
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
	for k: int in 3:
		var cap: CapitalShip = CapitalShip.create(&"ea_omega", Factions.EARTH_ALLIANCE, "Omega %d" % k, rest)
		var at: Vector3 = main.ship.global_position - nose.z * ahead_m + nose.x * (1500.0 * k)
		main.world.spawn(cap, main.world.to_universe(at), nose.rotated(nose.y, PI * 0.5))
		cap.damageable.invulnerable = true
		if cap.hangar != null:
			cap.hangar.empty()
		caps.append(cap)
	var core: Object = SimCore.for_tree(get_tree()).core
	var rows: Array[int] = []
	while SimClock.ticks < END_TICK:
		await get_tree().physics_frame
		var text: String = ""
		for cap: CapitalShip in caps:
			var st: Dictionary = core.tier_state(cap.get_instance_id())
			if st.is_empty():
				text += str(cap.global_position) + str(cap.global_basis) + str(cap.linear_velocity)
			else:
				text += str(st["position"]) + str(st["basis"]) + str(st["velocity"])
		rows.append(text.hash())
	var world: World3D = main.get_world_3d()
	var out: Dictionary = {"rows": rows, "world": world.get_instance_id()}
	remove_child(main)
	main.free()
	await get_tree().physics_frame
	return out
