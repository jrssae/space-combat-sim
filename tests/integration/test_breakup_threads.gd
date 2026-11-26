extends GutTest
## A capital's staged break-up with threads (M10-T11, D12.8, architecture §17.13): an Omega whose magazine blows among a raider
## group plays the same plan and its blasts land the same hits, damage and points byte for byte with one thread and six. The
## plan is drawn from the ship's name, its blasts land in the native batch on the main thread.

const RAIDERS: int = 10

var _settings_backup: Dictionary = {}


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	get_tree().paused = false
	_settings_backup = {&"perf_threads": Settings.get_value(&"perf_threads"),
			&"physics_max_steps_per_frame": Settings.get_value(&"physics_max_steps_per_frame")}
	Settings.set_value(&"physics_max_steps_per_frame", 1)  # a slow frame never lets two ticks pass unseen (Main reads it)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	BlastResolver.set_hit_log(false)
	for key: StringName in _settings_backup:
		Settings.set_value(key, _settings_backup[key])


func test_a_break_up_lands_the_same_blasts_with_one_thread_and_six() -> void:
	var one: Array = await _break_up(1)
	var six: Array = await _break_up(6)
	assert_gt(one.size(), RAIDERS, "the blasts hurt the raiders (%d hits)" % one.size())
	assert_eq(one.size(), six.size(), "the same count of blast hits")
	var first: int = -1
	for i: int in mini(one.size(), six.size()):
		if one[i] != six[i]:
			first = i
			break
	if first >= 0:
		gut.p("one: %s\nsix: %s" % [str(one.slice(maxi(first - 2, 0), first + 3)), str(six.slice(maxi(first - 2, 0), first + 3))])
	assert_eq(first, -1, "the same hits, damage and points byte for byte (first difference at %d)" % first)


# The break-up with `threads` threads: every blast hit as [tick, the hull's place, damage, point, points removed].
func _break_up(threads: int) -> Array:
	Settings.set_value(&"perf_threads", threads)
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.waves_auto_start = false
	main.raider_pool_size = RAIDERS
	add_child(main)
	await wait_physics_frames(2)
	var rest: Vector3 = main.world.rest_velocity()
	var basis: Basis = main.ship.global_basis
	var cap: CapitalShip = CapitalShip.create(&"ea_omega", Factions.EARTH_ALLIANCE, "EAS Agamemnon", rest)
	assert_not_null(cap)
	if cap == null:
		main.queue_free()
		return []
	var centre: Vector3 = main.ship.global_position - basis.z * 6000.0
	main.world.spawn(cap, main.world.to_universe(centre), basis)
	cap.set_course(-basis.z, rest)
	var index_of: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k: int in RAIDERS:
		assert_true(DebugConsole.registry.execute("spawn raider idle 900")[0].ok)
		var alive: Array[Combatant] = main.ships.alive(ShipPool.DEFAULT_TYPE)
		var c: Combatant = alive[alive.size() - 1]
		var along: float = rng.randf_range(-900.0, 900.0)
		var off := Vector3(rng.randf_range(-400.0, 400.0), rng.randf_range(-400.0, 400.0), along)
		c.ship.global_transform = Transform3D(basis, centre + basis * off)
		c.ship.linear_velocity = rest
		c.ship.angular_velocity = Vector3.ZERO
		index_of[c.ship.get_instance_id()] = k
	index_of[cap.get_instance_id()] = -1
	await wait_physics_frames(3)
	BlastResolver.set_hit_log(true)
	assert_true(DebugConsole.registry.execute_tokens(["capital", "focus", String(cap.name)]).ok)
	var blow: float = cap.damage.sections["magazine"].max_hp * 2.0
	assert_true(DebugConsole.registry.execute_tokens(["capital", "damage", "magazine", "%.0f" % blow]).ok)
	assert_true(cap.damageable.hull.destroyed, "the magazine blew")
	var log: Array = []
	var wrecks: CapitalWrecks = CapitalWrecks.of(main.world)
	var ticks: int = 0
	while ticks < 900:
		for info: HitInfo in BlastResolver.hit_log():
			# Only the hulls placed here: the scenario's nav buoys turn with the clock, which a second scene starts later.
			if index_of.has(info.target_id):
				log.append([ticks, index_of[info.target_id], info.damage, info.point, info.applied])
		BlastResolver.set_hit_log(true)
		if wrecks != null and wrecks.playing().is_empty():
			break
		await get_tree().physics_frame
		ticks += 1
	BlastResolver.set_hit_log(false)
	main.queue_free()
	await wait_physics_frames(2)
	return log
