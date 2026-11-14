extends GutTest
## The station sandbox and its exterior tour on the real main scene (M7-T12): `station_showcase` starts the player in a Cobra bay with
## the station's traffic on (the maintenance bots, the cargo ferry with its Saturn); the `tour` command plays the seven stops end to
## end on the cinematic camera, every shot at least a second, each stop's subject on screen; A or Start skips it; a stop plays alone;
## the camera goes back to the player's view afterwards.

const DT: float = 1.0 / 60.0
const SCENARIO: String = "res://data/scenarios/station_showcase.json"

var main: Main
var station: Station
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	source = FakeInputSource.new()
	main.input_source = source
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	station = main.far_props.station


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# Skips the launch (the sandbox opens on the rack) and lets the hand-off settle, so the tour has a free player to film.
func _fly_free() -> void:
	DebugConsole.registry.execute("launch skip")
	for i: int in 1500:  # a drop due under the spine waits for the arm to turn clear
		if not main.launches.locks_controls():
			break
		await _ticks(1)
	await _ticks(5)
	assert_false(main.launches.locks_controls(), "the player is away from the rack")


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _subject_world(point_name: String) -> Vector3:
	return (main.tours._actor_pose(TourBook.subject_actor(point_name)) as Transform3D).origin


func test_the_sandbox_starts_in_a_bay_with_the_stations_traffic() -> void:
	await _start()
	assert_not_null(station, "the scenario anchors on Babylon 5")
	assert_eq(main.launches.start_bay, "cobra_bay_alpha_3", "the launch plays at the start")
	assert_true(main.controls_locked(), "the controls are held on the rack")
	assert_not_null(station.bots, "the maintenance bots")
	assert_eq(station.bots.bots.size(), 8, "eight loop bots")
	assert_eq(station.bots.ferry_bots.size(), 5, "the cargo ferry's bots")
	assert_not_null(station.bots.cargo.freighter, "the Saturn backed in at the cargo bay")
	assert_not_null(main.tours.book, "the tour is loaded")


func test_the_tour_waits_for_the_launch() -> void:
	await _start()
	var refused: ConsoleResult = _run("tour")
	assert_false(refused.ok, "no tour from the rack")
	assert_string_contains(refused.error, "launch")
	assert_false(main.tours.playing)


func test_the_tour_plays_every_stop_end_to_end() -> void:
	await _start()
	await _fly_free()
	var mode_before: CameraRig.Mode = main.camera_rig.chosen_mode()
	var started: ConsoleResult = _run("tour")
	assert_true(started.ok, started.error)
	assert_true(main.tours.playing)
	assert_true(main.camera_rig.is_playing_shot(), "the cinematic camera takes over")
	assert_true(main.letterbox.shown)
	var book: TourBook = main.tours.book
	var total_s: float = 0.0
	for entry: Dictionary in main.tours.stops:
		total_s += float(entry["duration_s"])
	var seen := PackedStringArray()
	var checked: int = 0
	var ticks: int = 0
	while main.tours.playing and ticks < int(total_s / DT) + 600:
		await _ticks(1)
		ticks += 1
		var shot: CinematicShot = main.camera_rig.playing_shot()
		if shot != null and (seen.is_empty() or seen[-1] != String(shot.id)):
			seen.append(String(shot.id))
		# The subject is on screen at the start, the middle and near the end of every shot.
		if shot != null and main.tours.index >= 0:
			var at: float = main.camera_rig.shot_time_s()
			var third: float = shot.duration_s / 3.0
			if int(at / DT) % int(third / DT) == 2 and at > 0.5:
				var point_name: String = main.tours.current()["point"]
				var camera: Camera3D = main.camera_rig.cinematic_camera
				main.camera_rig.update_cinematic(1.0)
				var subject: Vector3 = _subject_world(point_name)
				assert_false(camera.is_position_behind(subject), "%s at %.1f s: the subject is ahead" % [point_name, at])
				var px: Vector2 = camera.unproject_position(subject)
				var view: Vector2 = main.get_viewport().get_visible_rect().size
				assert_true(Rect2(view * 0.2, view * 0.6).has_point(px), "%s at %.1f s: the subject is in the middle of the picture (%s of %s)" % [point_name, at, px, view])
				checked += 1
	assert_false(main.tours.playing, "the tour ended")
	assert_eq(seen.size(), 7, "seven shots: %s" % [seen])
	for i: int in book.order.size():
		assert_true(seen[i].begins_with("tour_%s_" % book.order[i]), "stop %d is %s (%s)" % [i + 1, book.order[i], seen[i]])
	assert_gte(checked, 7, "every shot was checked on screen")
	# Each shot ran its whole length, and none was shorter than the second.
	var played: Array[Dictionary] = main.tours.played
	assert_eq(played.size(), 7)
	for i: int in range(1, played.size()):
		var held: float = float(played[i]["start_s"]) - float(played[i - 1]["start_s"])
		assert_almost_eq(held, float(main.tours.stops[i - 1]["duration_s"]), 0.1, "%s held its whole shot" % played[i - 1]["point"])
		assert_gte(held, 1.0, "%s held at least a second" % played[i - 1]["point"])
	assert_false(main.camera_rig.is_playing_shot(), "no shot on at the end")
	assert_false(main.letterbox.shown, "the bars go")
	assert_eq(main.camera_rig.chosen_mode(), mode_before, "the camera is back on the player's view")
	assert_false(main.controls_locked(), "the player has the ship again")


func test_a_or_start_skips_the_tour() -> void:
	await _start()
	await _fly_free()
	assert_true(_run("tour").ok)
	await _ticks(90)
	assert_true(main.tours.playing)
	source.hold(InputAdapter.PAUSE)
	await _ticks(1)
	source.release(InputAdapter.PAUSE)
	await _ticks(2)
	assert_false(main.tours.playing, "Start ends the whole tour")
	assert_false(main.camera_rig.is_playing_shot())
	assert_false(main.pause_menu.is_open(), "Start skipped; it did not pause")
	assert_eq(main.tours.played.size(), 1, "no later stop came on")
	# A fresh press of A skips a tour started again.
	assert_true(_run("tour").ok)
	await _ticks(30)
	source.hold(InputAdapter.FIRE)
	await _ticks(2)
	source.release(InputAdapter.FIRE)
	await _ticks(2)
	assert_false(main.tours.playing, "A skips it too")


func test_one_stop_plays_alone_and_stop_ends_it() -> void:
	await _start()
	await _fly_free()
	var bad: ConsoleResult = _run("tour nowhere")
	assert_false(bad.ok)
	assert_string_contains(bad.error, "defence_grid")
	assert_true(_run("tour cobra_arm").ok)
	assert_eq(main.tours.stops.size(), 1)
	assert_eq(String(main.tours.current()["point"]), "cobra_arm")
	assert_eq(DebugConsole.registry.execute("get tour.point")[0].lines[0], "tour.point = cobra_arm")
	assert_true(_run("tour status").ok)
	await _ticks(120)
	assert_true(_run("tour stop").ok)
	assert_false(main.tours.playing)
	assert_false(main.camera_rig.is_playing_shot())
	assert_false(_run("tour stop").ok, "nothing to stop")


func test_a_shot_of_the_arm_turns_with_the_drum_and_survives_a_rebase() -> void:
	await _start()
	await _fly_free()
	assert_true(_run("tour cobra_arm").ok)
	await _ticks(60)
	var camera: Camera3D = main.camera_rig.cinematic_camera
	main.camera_rig.update_cinematic(1.0)
	var turn: float = float(main.tours._turns["cobra_arm"])
	var arm_up: Vector3 = station.global_basis * Basis(Vector3.BACK, station.drum_angle + turn) * Vector3.UP
	assert_gt(camera.global_basis.y.dot(arm_up), 0.9, "the picture is upright against the arm")
	var before: UniversePos = main.world.to_universe(camera.global_position)
	var subject_px: Vector2 = camera.unproject_position(_subject_world("cobra_arm"))
	main.world.rebase(Vector3(3000.0, -500.0, 1200.0))
	main.camera_rig.update_cinematic(1.0)
	assert_lt(before.distance_to(main.world.to_universe(camera.global_position)), 0.05, "the camera stays at its universe place")
	assert_almost_eq(camera.unproject_position(_subject_world("cobra_arm")), subject_px, Vector2.ONE * 0.1, "and the subject where it was")
	_run("tour stop")


func test_the_arm_filmed_is_clear_of_the_spine_and_named_in_the_caption() -> void:
	await _start()
	await _fly_free()
	assert_true(_run("tour cobra_arm").ok)
	var wing: String = String(main.tours.current()["wing"])
	assert_false(wing.is_empty(), "the stop names the wing it films")
	assert_string_contains(main.tours._caption.text, wing.to_upper())
	var angle_deg: float = 0.0
	for arm: Dictionary in station.hardpoints.cobra_arm["arms"]:
		if arm["wing"] == wing:
			angle_deg = float(arm["angle_deg"])
	var rate: float = station.spin.rate_rad_s
	for t: float in [0.0, 4.5, 9.0]:
		assert_false(station.hardpoints.launch_blocked(angle_deg + rad_to_deg(station.drum_angle + rate * t)),
				"wing %s is out from under the spine %.1f s into the shot" % [wing, t])
	_run("tour stop")


func test_the_defence_grid_stop_has_its_light_turrets_on_screen() -> void:
	await _start()
	await _fly_free()
	assert_true(_run("tour defence_grid").ok)
	var camera: Camera3D = main.camera_rig.cinematic_camera
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	var shown: PackedStringArray = main.tours.book.points["defence_grid"]["shows"]
	assert_gte(shown.size(), 2)
	for step: int in 4:
		await _ticks(120)
		main.camera_rig.update_cinematic(1.0)
		for mount_name: String in shown:
			var drum := Transform3D(Basis(Vector3.BACK, station.visual_angle(1.0)), station.drum_origin)
			var at: Vector3 = main.tours.book.mount_point("defence_grid", mount_name, station.hardpoints, station.global_transform, drum, main.tours._turns)
			assert_false(camera.is_position_behind(at), "%s is ahead of the camera" % mount_name)
			assert_true(Rect2(Vector2.ZERO, view).grow(-view.y * 0.05).has_point(camera.unproject_position(at)), "%s is on screen" % mount_name)
	_run("tour stop")
