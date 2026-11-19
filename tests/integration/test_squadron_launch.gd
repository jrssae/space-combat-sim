extends GutTest
## The squadron-launch cinematic on the real main scene (M8-T03, D81, AC2), on the tutorial's setup (the player commands a flight
## of three, the rest of Alpha launches as flights): the squadron's Starfuries launch from Alpha's arm through doors that open and
## shut again, each flips, burns and settles on its slot in the formation, filmed from outside only; the player waits stowed, then
## launches alone and its hand-off gives the controls back and lets the squadron go on its slots. A skip lands in the same state.

const DT: float = 1.0 / 60.0
const SCENARIO: String = "res://tests/fixtures/flights/station_flight.json"
const LIMIT_TICKS: int = 90 * 60

var main: Main
var station: Station
var source: FakeInputSource
var shots_seen: PackedStringArray = PackedStringArray()
var _full: Dictionary = {}  # the full run's end state, for the skip's comparison


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	shots_seen = PackedStringArray()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
		await get_tree().physics_frame
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	source = FakeInputSource.new()
	main.input_source = source
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	station = main.far_props.station
	shots_seen = PackedStringArray()


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
		var shot: CinematicShot = main.camera_rig.playing_shot() if main != null else null
		if shot != null and (shots_seen.is_empty() or shots_seen[-1] != String(shot.id)):
			shots_seen.append(String(shot.id))


func _station_point(p: Vector3) -> Vector3:
	return station.global_transform.affine_inverse() * p


func _station_velocity(v: Vector3) -> Vector3:
	return station.global_basis.inverse() * (v - main.world.anchored_velocity())


# Every squadron ship's state in the station's frame, and the player's hand-off in the drum's frame, at the hand-off's tick.
func _snapshot(sq: SquadronLaunch) -> Dictionary:
	var ships: Dictionary = {}
	for id: String in sq.ships:
		var c: Combatant = sq.ships[id]
		ships[id] = {"point": _station_point(c.ship.global_position), "velocity": _station_velocity(c.ship.linear_velocity),
				"nose": station.global_basis.inverse() * -c.ship.global_basis.z, "slot": (sq.slots[id] as Transform3D).origin}
	var h: Dictionary = main.launches.last_handoff
	var turn := Basis(Vector3.BACK, float(h["drum_angle"]))
	var arm: Vector3 = _station_point((h["transform"] as Transform3D).origin) - station.drum_origin
	var v: Vector3 = _station_velocity(h["velocity"])
	return {"ships": ships, "bay": h["bay"], "skipped": h["skipped"], "point": turn.inverse() * arm,
			"velocity": turn.inverse() * (v - Vector3(0.0, 0.0, station.spin.rate_rad_s).cross(arm))}


# One squadron launch to its hand-off, skipped `skip_at` ticks in (-1 never). Returns the end state and what was seen on the way.
func _run(skip_at: int) -> Dictionary:
	await _start()
	var why: String = main.launches.launch_squadron("alpha")
	assert_eq(why, "", "the squadron launch starts")
	var sq: SquadronLaunch = main.launches.squadron
	var seen: Dictionary = {"end": {}, "door": [] as Array[int], "unlocked": 0, "unfilmed": 0, "player_doors": {}}
	main.launches.player_released.connect(func() -> void: (seen["end"] as Dictionary).merge(_snapshot(sq)))
	var seq: LaunchSequence = sq.launch["seq"]
	var states: Array[int] = seen["door"]
	states.append(int(seq.doors[0]["state"]))
	for tick: int in LIMIT_TICKS:
		if tick == skip_at:
			source.hold(InputAdapter.PAUSE)
		elif tick == skip_at + 1:
			source.release(InputAdapter.PAUSE)
		await _ticks(1)
		if not sq.running():
			break
		if int(seq.doors[0]["state"]) != states[-1]:
			states.append(int(seq.doors[0]["state"]))
		if not main.controls_locked():
			seen["unlocked"] = int(seen["unlocked"]) + 1
		if not main.camera_rig.is_playing_shot() and skip_at < 0:
			seen["unfilmed"] = int(seen["unfilmed"]) + 1
		var own: Dictionary = main.launches.player_launch()
		if not own.is_empty():
			var player_seq: LaunchSequence = own["seq"]
			var f: Dictionary = player_seq.fighter(main.combatant.display_name)
			(seen["player_doors"] as Dictionary)[int(player_seq.doors[f["bay"]]["state"])] = true
	seen["sq"] = sq
	return seen


func _assert_formed_up(end: Dictionary, label: String) -> void:
	assert_false(end.is_empty(), "%s: the player was handed over" % label)
	var ships: Dictionary = end.get("ships", {})
	assert_eq(ships.size(), 11, "%s: the player's two wingmen and three AI flights of three" % label)
	for id: String in ships:
		var e: Dictionary = ships[id]
		assert_almost_eq(e["point"] as Vector3, e["slot"] as Vector3, Vector3.ONE * 0.05, "%s: %s on its slot" % [label, id])
		assert_almost_eq(e["velocity"] as Vector3, Vector3.ZERO, Vector3.ONE * 0.05, "%s: %s at rest against the station" % [label, id])
		assert_almost_eq(e["nose"] as Vector3, Vector3.FORWARD, Vector3.ONE * 0.01, "%s: %s flipped to the heading" % [label, id])
	var points: Array = ships.values().map(func(e: Dictionary) -> Vector3: return e["slot"])
	for i: int in points.size():
		for k: int in range(i + 1, points.size()):
			assert_gt((points[i] as Vector3).distance_to(points[k]), 30.0, "%s: no two slots on top of each other" % label)


func test_the_squadron_launches_forms_up_and_the_player_goes_last() -> void:
	var seen: Dictionary = await _run(-1)
	var sq: SquadronLaunch = seen["sq"]
	var end: Dictionary = seen["end"]
	_full = end
	_assert_formed_up(end, "full run")
	assert_false(sq.running(), "the cinematic is over")
	assert_false(bool(end["skipped"]), "the player's launch played")
	assert_eq(end["bay"], "cobra_bay_alpha_3", "the player went last, from the data's door")
	assert_eq(int(seen["unlocked"]), 0, "the controls are held through the cinematic")
	assert_lt(int(seen["unfilmed"]), 3, "a shot is on screen throughout")
	var names: Array[String] = []
	for state: int in seen["door"] as Array[int]:
		names.append(LaunchSequence.DOOR_NAMES[state])
	assert_eq(names, ["closed", "opening", "open", "closing", "closed"] as Array[String], "the squadron's first door opens and shuts")
	for state: int in [LaunchSequence.DoorState.OPENING, LaunchSequence.DoorState.OPEN]:
		assert_true((seen["player_doors"] as Dictionary).has(state), "the player's door opens for its own launch")
	for id: String in shots_seen:
		assert_true(id.begins_with("sq_") or id.begins_with("ext_"), "%s: only exterior shots in the cinematic" % id)
	assert_true(Array(shots_seen).any(func(id: String) -> bool: return id.begins_with("sq_") and id != "sq_fallback"),
			"the squadron's shots played (%s)" % ", ".join(shots_seen))
	assert_true(Array(shots_seen).any(func(id: String) -> bool: return id.begins_with("ext_")), "and the player's exterior launch")
	await _ticks(2)
	assert_false(main.controls_locked(), "the controls are the pilot's again")
	for id: String in sq.ships:
		var ship: Ship = (sq.ships[id] as Combatant).ship
		assert_ne(ship.collision_layer, 0, "%s flies free" % id)
		assert_false(ship.clamped, "%s has its own engines back" % id)
	assert_eq(main.wings.flights_of("ALPHA").size(), 4, "the player's flight and three AI flights")


func test_skipping_lands_in_the_same_state() -> void:
	var full: Dictionary = _full
	if full.is_empty():
		var first: Dictionary = await _run(-1)
		full = first["end"]
	var seen: Dictionary = await _run(90)
	var end: Dictionary = seen["end"]
	_assert_formed_up(end, "skipped")
	assert_true(bool(end["skipped"]), "the skip jumped the player to its hand-off")
	assert_eq(end["bay"], full["bay"])
	assert_almost_eq(end["point"] as Vector3, full["point"] as Vector3, Vector3.ONE * 0.01, "the same release point on the drum")
	assert_almost_eq(end["velocity"] as Vector3, full["velocity"] as Vector3, Vector3.ONE * 0.01, "the same velocity against the drum")
	var full_ships: Dictionary = full["ships"]
	for id: String in end["ships"] as Dictionary:
		assert_true(full_ships.has(id), "%s flew in the full run too" % id)
		if full_ships.has(id):
			var a: Dictionary = (end["ships"] as Dictionary)[id]
			var b: Dictionary = full_ships[id]
			assert_almost_eq(a["point"] as Vector3, b["point"] as Vector3, Vector3.ONE * 0.05, "%s: the same place" % id)
			assert_almost_eq(a["velocity"] as Vector3, b["velocity"] as Vector3, Vector3.ONE * 0.05, "%s: the same velocity" % id)
	await _ticks(2)
	assert_false(main.controls_locked(), "the controls are back")
	assert_true(main.launches.launches.all(func(l: Dictionary) -> bool: return not bool(l.get("squadron", false))),
			"the squadron's own launch is over, its doors shut")


func test_the_console_and_the_mission_api_start_it() -> void:
	await _start()
	var result: ConsoleResult = DebugConsole.registry.execute("launch squadron")[0]
	assert_true(result.ok, "launch squadron: %s %s" % [result.error, "\n".join(result.lines)])
	assert_true(main.launches.locks_controls(), "the player is out of the pilot's hands")
	assert_false(DebugConsole.registry.execute("launch squadron")[0].ok, "only one at a time")
	DebugConsole.registry.execute("launch skip")
	for i: int in 600:
		await _ticks(1)
		if not main.launches.squadron.running():
			break
	assert_false(main.launches.squadron.running(), "skipped to the end")
	await _start()
	var stage := MissionStage.new()
	stage.setup(main, null)
	var api := MissionApi.new(null, null, stage)
	api.launch_squadron()  # a script awaits it; here it runs to its first wait
	assert_eq(api.journal[-1], "launch_squadron  0", "journaled as a world change")
	assert_true(stage.launching(), "the cinematic has the player")
	stage.skip_launch()
	for i: int in 600:
		await _ticks(1)
		if not stage.launching():
			break
	assert_false(stage.launching(), "the skip runs it to the hand-off")
	api.release()
	stage.teardown()
