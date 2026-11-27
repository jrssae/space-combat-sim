extends GutTest
## A far capital fleet (M10-T16, the maintainer, 2026-11-26): 24 Omegas, two hostile groups 20 to 40 km off the player, every one
## a low-attention tier row steered live by its native helm and brain, keep the same brains, helms and tier rows byte for byte
## with one thread and six. Reports the tier step's cost and the brains' with the fleet.

const TICKS: int = 600
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


func test_a_far_fleet_steers_the_same_with_one_thread_and_six() -> void:
	var one: Dictionary = await _fleet(1)
	var six: Dictionary = await _fleet(6)
	assert_eq(int(one["far"]), 2 * PER_SIDE, "every Omega a tier row")
	assert_gt(int(one["thinks"]), 2 * PER_SIDE * (TICKS / 12) - 4 * PER_SIDE, "their brains thought (%d)" % int(one["thinks"]))
	assert_gt(float(one["moved_m"]), 100.0, "and their helms flew them (%.0f m between the groups' ends)" % float(one["moved_m"]))
	assert_eq(_first_difference(one["digests"], six["digests"]), -1, "the same brains, helms and tier rows each tick")


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
	# Everything on the sim clock's ticks, so both runs spawn, hand over and are compared on the same ticks whatever the
	# frames did while the scene loaded.
	while SimClock.ticks < SPAWN_TICK:
		await get_tree().physics_frame
	var rest: Vector3 = main.world.rest_velocity()
	var nose: Basis = main.ship.global_basis
	var caps: Array[CapitalShip] = []
	for side: int in 2:
		for k: int in PER_SIDE:
			var faction: StringName = Factions.EARTH_ALLIANCE if side == 0 else Factions.RAIDERS
			var cap: CapitalShip = CapitalShip.create(&"ea_omega", faction, "Omega %d-%d" % [side, k], rest)
			var at: Vector3 = main.ship.global_position - nose.z * (20000.0 + 20000.0 * side) + nose.x * (2500.0 * (k - PER_SIDE / 2))
			main.world.spawn(cap, main.world.to_universe(at), nose.rotated(nose.y, PI * side))
			cap.damageable.invulnerable = true
			caps.append(cap)
	var sim: SimCore = SimCore.for_tree(get_tree())
	var core: Object = sim.core
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, 4)
	while SimClock.ticks < START_TICK:  # the tier has taken them all by then
		await get_tree().physics_frame
	var far: int = int(core.tier_capitals())
	var start: PackedInt64Array = core.capital_readouts()
	var gap0: float = _gap(core, caps)
	var digests: Array[int] = []
	var tier_us: Array[float] = []
	while SimClock.ticks < START_TICK + TICKS:
		await get_tree().physics_frame
		var text: String = str(core.capital_digest())
		for cap: CapitalShip in caps:
			var s: Dictionary = core.tier_state(cap.get_instance_id())
			text += str(s.get("position")) + str(s.get("basis"))
		digests.append(text.hash())
		tier_us.append(float(core.tier_step_us()))
	var end: PackedInt64Array = core.capital_readouts()
	var thinks: int = int(end[3] - start[3])
	if threads == 1:
		tier_us.sort()
		gut.p("far fleet of %d Omegas (%d tier rows): the tier step median %.0f us (%.1f a capital, their helms included), the brains %.2f us a think (%.2f us a tick a capital)" % [
				caps.size(), far, tier_us[tier_us.size() / 2], tier_us[tier_us.size() / 2] / float(caps.size()),
				float(end[4] - start[4]) / 1000.0 / maxf(thinks, 1), float(end[4] - start[4]) / 1000.0 / float(TICKS * caps.size())])
	var out: Dictionary = {"digests": digests, "thinks": thinks, "far": far, "moved_m": absf(gap0 - _gap(core, caps))}
	remove_child(main)
	main.free()
	await get_tree().physics_frame
	return out


# How far apart the two groups' first ships are, from their tier rows.
func _gap(core: Object, caps: Array[CapitalShip]) -> float:
	var a: Dictionary = core.tier_state(caps[0].get_instance_id())
	var b: Dictionary = core.tier_state(caps[PER_SIDE].get_instance_id())
	if a.is_empty() or b.is_empty():
		return 0.0
	return (a["position"] as Vector3).distance_to(b["position"] as Vector3)
