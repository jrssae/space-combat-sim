extends GutTest
## Engine bursts in the game (M5-T19, AC15, D60): `engine_loop` and `thruster_loop` are gone; every ship has a `main_burst`
## voice at each pod and the player's ship an `rcs_burst` voice at each RCS cluster, children of the ship at their
## nozzles; thrust and RCS demand bring them up; parked and distant ships are silent; `engine_voice_cap` bounds the voices,
## and a frame's engine work follows the voices, not the ships (work counts). The re-rank asks the native core for the ships
## near the listener (M5-T28): its rows are the tick's, so a test that spawns or moves a ship waits a tick before it re-ranks.
## A hull with no cannon (a civilian) is voiced, a ship the pool parks is revoked, `unwatch_ship` removes one for good, and a
## ship the flight batch flies (it no longer ticks itself) is voiced when it thrusts.

var main: Main
var source: FakeInputSource
var _cap_backup: Variant


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	_cap_backup = Settings.get_value(&"engine_voice_cap")
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	Settings.set_value(&"engine_voice_cap", _cap_backup)
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


## The engine voices on `ship` whose names start with `prefix` (`EnginePod` or `EngineRcs`), in name order.
func _voices(ship: Ship, prefix: String) -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for i: int in 64:
		var node := ship.get_node_or_null("%s%d" % [prefix, i]) as AudioStreamPlayer3D
		if node == null:
			break
		out.append(node)
	return out


func _playing(nodes: Array[AudioStreamPlayer3D]) -> int:
	var n: int = 0
	for node: AudioStreamPlayer3D in nodes:
		n += 1 if node.playing else 0
	return n


func _spawn_raiders(count: int, metres: float) -> void:
	for i: int in count:
		assert_true(DebugConsole.registry.execute("spawn raider idle %d %d" % [int(metres), 20 * i - 80])[0].ok)


func test_the_old_loops_are_gone() -> void:
	assert_false(AudioDirector.SOUND_NAMES.has(&"engine_loop"))
	assert_false(AudioDirector.SOUND_NAMES.has(&"thruster_loop"))
	assert_true(main.audio.has_sound(&"main_burst"), "run scripts/gen_assets.sh, then import")
	assert_true(main.audio.has_sound(&"rcs_burst"))
	var ships: Array[Ship] = [main.ship]
	for pooled: Combatant in main.ships.all_ships():
		ships.append(pooled.ship)
	for ship: Ship in ships:
		assert_null(ship.get_node_or_null("EngineHum"), "no hum")
		assert_null(ship.get_node_or_null("ThrusterHiss"), "no hiss")
	for node: AudioStreamPlayer3D in _voices(main.ship, "EnginePod") + _voices(main.ship, "EngineRcs"):
		assert_eq((node.stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % node.name)
		assert_eq(node.bus, AudioDirector.BUS)


func test_the_players_voices_sit_at_its_pods_and_rcs_clusters() -> void:
	var layout: ThrusterLayout = main.ship.get_layout()
	var pods: Array[AudioStreamPlayer3D] = _voices(main.ship, "EnginePod")
	assert_eq(pods.size(), layout.pod_count())
	for pod: int in pods.size():
		assert_eq(pods[pod].position, layout.nozzle_positions[pod], "at the pod's main nozzle")
		assert_eq(pods[pod].stream.resource_name, "main_burst")
	var clusters: Array[Dictionary] = EngineVoices.rcs_clusters(layout)
	var jets: Array[AudioStreamPlayer3D] = _voices(main.ship, "EngineRcs")
	assert_eq(jets.size(), clusters.size())
	assert_between(jets.size(), 2, 8, "a handful of clusters")
	for c: int in jets.size():
		assert_almost_eq(jets[c].position, clusters[c]["position"] as Vector3, Vector3.ONE * 1e-4)
		assert_eq(jets[c].stream.resource_name, "rcs_burst")


func test_other_ships_have_pod_voices_only() -> void:
	assert_eq(main.audio.engine_ship_count(), 1 + main.ships.pool_size(), "the player and every pooled ship")
	for pooled: Combatant in main.ships.all_ships():
		assert_eq(_voices(pooled.ship, "EnginePod").size(), pooled.ship.get_layout().pod_count(), pooled.ship.name)
		assert_eq(_voices(pooled.ship, "EngineRcs").size(), 0, "%s: RCS is the player's alone" % pooled.ship.name)


func test_main_thrust_brings_up_the_pod_voices() -> void:
	var pods: Array[AudioStreamPlayer3D] = _voices(main.ship, "EnginePod")
	await get_tree().process_frame
	assert_eq(_playing(pods), 0, "silent at rest")
	source.hold(InputAdapter.MAIN_LEFT)
	source.hold(InputAdapter.MAIN_RIGHT)
	await _ticks(10)
	await get_tree().process_frame
	assert_eq(_playing(pods), pods.size(), "every main pod roars")
	for pod: AudioStreamPlayer3D in pods:
		assert_almost_eq(pod.volume_db, AudioDirector.POD_DB, 1.0, "%s near full level" % pod.name)
	source.release_all()
	await _ticks(20)  # 0.33 s: the 40 ms cut is long over
	await _frames(2)
	var output: FlightOutput = main.ship.get_flight_output()
	assert_eq(_max(output.main_levels) + _max(output.retro_levels), 0.0, "the pods have stopped")
	assert_eq(_playing(pods), 0, "and so have their voices")


func test_rcs_demand_brings_up_the_cluster_voices_brighter_as_they_build() -> void:
	var jets: Array[AudioStreamPlayer3D] = _voices(main.ship, "EngineRcs")
	source.hold(InputAdapter.YAW_LEFT)
	await _ticks(1)
	await get_tree().process_frame
	var early: float = _max_pitch(jets)
	await _ticks(20)
	await get_tree().process_frame
	assert_gt(_playing(jets), 0, "the jets that yaw the ship are heard")
	var later: float = _max_pitch(jets)
	assert_between(later, EngineVoices.RCS_DULL_PITCH, 1.0)
	assert_gt(later, early, "brighter as the burst builds")


func test_parked_ships_are_silent_and_a_ship_beyond_hearing_loses_its_voices() -> void:
	Settings.set_value(&"engine_voice_cap", 64)
	for pooled: Combatant in main.ships.all_ships():
		if not main.ships.alive().has(pooled):
			assert_eq(main.audio.engine_voices_of(pooled.ship), 0, "%s is parked" % pooled.ship.name)
			assert_eq(_playing(_voices(pooled.ship, "EnginePod")), 0)
	_spawn_raiders(1, 400.0)
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	await _ticks(2)
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_voices_of(raider.ship), 2, "400 m away: heard")
	raider.ship.global_position = main.ship.global_position + Vector3(0.0, 0.0, -EngineVoices.AUDIBLE_RANGE_M - 500.0)
	await _ticks(2)
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_voices_of(raider.ship), 0, "out of range")
	await get_tree().process_frame
	assert_eq(_playing(_voices(raider.ship, "EnginePod")), 0)


func test_the_cap_holds_with_every_ship_near() -> void:
	_spawn_raiders(9, 300.0)
	await _ticks(2)
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_voices_granted(), 24, "the default cap, filled")
	assert_eq(main.audio.engine_voices_of(main.ship), 8, "the player's own first")
	Settings.set_value(&"engine_voice_cap", 12)
	await _frames(2)  # `process_frame` fires before the frame's `_process`
	assert_eq(main.audio.engine_voices_granted(), 12, "a new cap applies on the next frame")
	assert_lte(main.audio.engine_voices_sounding(), 12)
	assert_eq(main.audio.engine_voices_of(main.ship), 8)


func test_a_frames_engine_work_follows_the_voices_not_the_ships() -> void:
	# Each granted voice is stepped and applied, and each voiced ship (at most one per voice) checked and read: the bound
	# is the cap's, whatever the number of ships. The unit test (test_engine_voices.gd) shows it with 300 ships.
	Settings.set_value(&"engine_voice_cap", 12)
	await _frames(2)
	var bound: int = 4 * 12
	var few: int = main.audio.engine_frame_work
	assert_between(few, 2 * 12, bound)
	_spawn_raiders(9, 300.0)
	await _ticks(2)
	main.audio.reallocate_engines()
	await _frames(2)
	assert_eq(main.audio.engine_voices_granted(), 12)
	assert_between(main.audio.engine_frame_work, 2 * 12, bound, "nine more ships in range: bounded by the cap, not the ships")
	main.audio.reallocate_engines()
	# The player, then the ships in earshot until the cap is spent: never the ships in play (the pool holds more).
	assert_lte(main.audio.engine_allocate_work(), 1 + 1 + 2, "the player, its own row and the two ships that fit")
	assert_lt(main.audio.engine_allocate_work(), main.audio.engine_ship_count())


## A civilian hull as the encounters will build one: `FREIGHTER`, assembled and spawned 400 m ahead of the player.
const FREIGHTER: StringName = &"saturn_3_freighter"


func _civilian(watch_first: bool, drop_cannon: bool) -> Combatant:
	var civilian: Combatant = ShipAssembly.build(ShipCatalog.spec_for(FREIGHTER), main.world, main.projectiles, {
		ShipAssembly.OPT_FACTION: Factions.NEUTRAL, ShipAssembly.OPT_DISPLAY_NAME: "FREIGHTER", ShipAssembly.OPT_LEAN: true,
		ShipAssembly.OPT_CIVILIAN: true})
	if watch_first:
		main.audio.watch_ship(civilian)  # before the ship is ready: its voices wait for its layout
	main.world.spawn(civilian.ship, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -400.0)))
	if drop_cannon:
		civilian.cannon = null  # a hull with no cannon at all
		main.audio.watch_ship(civilian)
	return civilian


func test_a_ship_watched_before_it_is_ready_gets_its_voices_when_it_is() -> void:
	var civilian: Combatant = _civilian(true, false)
	var pods: int = civilian.ship.get_layout().pod_count()
	assert_gt(pods, 0)
	assert_eq(_voices(civilian.ship, "EnginePod").size(), pods, "a voice per pod, built at its ready")
	await _ticks(2)
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_voices_of(civilian.ship), pods, "400 m away: heard")


func test_a_hull_with_no_cannon_gets_pod_voices_and_no_rcs() -> void:
	Settings.set_value(&"engine_voice_cap", 64)
	var civilian: Combatant = _civilian(false, true)
	var pods: int = civilian.ship.get_layout().pod_count()
	assert_eq(_voices(civilian.ship, "EnginePod").size(), pods)
	assert_eq(_voices(civilian.ship, "EngineRcs").size(), 0, "RCS voices are the player's alone")
	await _ticks(2)
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_voices_of(civilian.ship), pods, "voiced like any ship in earshot")


func test_a_ship_the_pool_parks_loses_its_voices_at_once() -> void:
	_spawn_raiders(1, 400.0)
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	await _ticks(2)
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_voices_of(raider.ship), 2)
	main.ships.release(raider)
	# The core's rows still list it until the next sync; its node says it is gone.
	await _frames(2)
	assert_eq(main.audio.engine_voices_of(raider.ship), 0, "revoked")
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_voices_of(raider.ship), 0, "and not granted again from the stale rows")
	await _ticks(2)
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_voices_of(raider.ship), 0, "nor from the fresh ones")
	assert_eq(_playing(_voices(raider.ship, "EnginePod")), 0)


func test_unwatching_a_ship_takes_its_voices_away_for_good() -> void:
	var civilian: Combatant = _civilian(false, false)
	main.audio.watch_ship(civilian)
	var ships_before: int = main.audio.engine_ship_count()
	await _ticks(2)
	main.audio.reallocate_engines()
	var pods: int = civilian.ship.get_layout().pod_count()
	assert_eq(main.audio.engine_voices_of(civilian.ship), pods)
	main.audio.unwatch_ship(civilian)
	assert_eq(main.audio.engine_voices_of(civilian.ship), 0)
	assert_eq(main.audio.engine_ship_count(), ships_before - 1)
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_voices_of(civilian.ship), 0, "still in earshot, still silent")
	await _frames(2)
	assert_eq(_voices(civilian.ship, "EnginePod").size(), 0, "its voice nodes are freed")
	main.audio.unwatch_ship(civilian)  # twice is harmless
	main.audio.watch_ship(civilian)  # and a ship can be watched again
	assert_eq(_voices(civilian.ship, "EnginePod").size(), pods)


func test_a_ship_the_flight_batch_flies_is_voiced_when_it_thrusts() -> void:
	# No AI driver hands this hull a command each think, so the one it is given stays; the batch flies it, the ship's own
	# tick does not.
	var civilian: Combatant = _civilian(false, false)
	main.audio.watch_ship(civilian)
	var command := FlightCommand.new()
	command.main_left = 1.0
	command.main_right = 1.0
	civilian.ship.set_flight_command(command)
	await _ticks(10)
	main.audio.reallocate_engines()
	await _frames(2)
	assert_true(civilian.ship.is_batch_owned(), "the batch flies it")
	assert_eq(main.audio.engine_voices_of(civilian.ship), civilian.ship.get_layout().pod_count())
	assert_gt(_playing(_voices(civilian.ship, "EnginePod")), 0, "its pods roar")


func test_ships_beyond_hearing_cost_the_re_rank_nothing() -> void:
	# Three hundred bodies far away are rows in the core (bodies of ships' kind, no meshes) and are never listed, so the
	# re-rank walks no more than it did. The tier rows' side of this is in test_voice_query.
	var sim: SimCore = SimCore.for_tree(get_tree())
	assert_not_null(sim, "the game runs on the core")
	main.audio.reallocate_engines()
	var walked: int = main.audio.engine_allocate_work()
	var granted: int = main.audio.engine_voices_granted()
	var rows_before: int = sim.rows()
	for i: int in 300:
		var body := RigidBody3D.new()
		body.freeze = true
		main.world.add_child(body)
		body.add_to_group(WorldFrame.SHIFTABLE_GROUP)
		body.global_position = main.ship.global_position + Vector3(0.0, 0.0, -20000.0 - float(i))
		var hull := Damageable.new()
		hull.bounding_radius = 10.0
		body.add_child(hull)
		var marker := Targetable.new()
		marker.name = "Targetable"
		marker.display_name = "FAR %d" % i
		marker.faction = Factions.NEUTRAL
		body.add_child(marker)
	await _ticks(3)
	assert_gte(sim.rows(), rows_before + 300, "the rows hold them")
	main.audio.reallocate_engines()
	assert_eq(main.audio.engine_allocate_work(), walked, "300 more rows far away: the same work")
	assert_eq(main.audio.engine_voices_granted(), granted)


func test_engine_voice_cap_is_a_schema_entry() -> void:
	var entry: Dictionary = SettingsSchema.ENTRIES[&"engine_voice_cap"]
	assert_eq(entry["type"], TYPE_INT)
	assert_eq(entry["default"], 24)
	assert_gte(int(entry["min"]), 8, "the player's own voices always fit")


func _max(values: PackedFloat64Array) -> float:
	var top: float = 0.0
	for v: float in values:
		top = maxf(top, v)
	return top


func _max_pitch(nodes: Array[AudioStreamPlayer3D]) -> float:
	var top: float = 0.0
	for node: AudioStreamPlayer3D in nodes:
		if node.playing:
			top = maxf(top, node.pitch_scale)
	return top
