extends GutTest
## Dialog, subtitles and the comms panel in the real main scene (architecture §18 D53, AC6, M5-T06), on
## `tests/fixtures/missions/test_comms.json`: a mission line shows in the chase and the cockpit view in its speaker's faction
## colour, `radio_open` and `radio_close` frame it, the `dialog_finished` trigger fires, a skip logs lines without showing them,
## the queue plays on sim time, and a dialog file that does not validate stops the mission from starting.

const MISSION_PATH: String = "res://tests/fixtures/missions/test_comms.json"
const BROKEN_PATH: String = "res://tests/fixtures/broken_missions/test_comms_broken.json"
const HAIL_TEXT: String = "Alpha wing, this is Control. Raiders have been seen heading for the relay. Move to intercept."
## The test script waits 0.2 s before the first line.
const HAIL_TICKS: int = 14

var main: Main
var source: FakeInputSource
var _game_state: GameFlow.State
var _game_result: Dictionary
var _show_hud_backup: Variant
var _window_size: Vector2i


func before_each() -> void:
	get_tree().paused = false
	_window_size = get_window().size
	get_window().size = Vector2i(1920, 1080)  # a headless run opens a 64x64 window; the geometry is checked at a real size
	_game_state = Game.flow.state
	_game_result = Game.flow.last_result
	_show_hud_backup = Settings.get_value(&"show_hud")
	source = FakeInputSource.new()
	main = await _make_main(MISSION_PATH)


func after_each() -> void:
	get_tree().paused = false
	Settings.set_value(&"show_hud", _show_hud_backup)
	get_window().size = _window_size
	Game.flow.state = _game_state
	Game.flow.last_result = _game_result


func _make_main(path: String) -> Main:
	var m := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	m.input_source = source
	m.scenario_path = path
	add_child_autofree(m)
	await _ticks(2)
	return m


func _ticks(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _comms() -> CommsPanel:
	return main.mission.comms


func _api() -> MissionApi:
	return main.mission.api


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# Runs ticks until `done` holds, at most `limit` of them.
func _until(done: Callable, limit: int = 400) -> bool:
	for _i: int in limit:
		if done.call():
			return true
		await _ticks(1)
	return bool(done.call())


# The first line is up and has been drawn.
func _first_line_showing() -> void:
	await _ticks(HAIL_TICKS)
	await _frames(2)


# Resizes the window the panel draws in (a headless run opens a 64x64 one), and lets it redraw.
func _resize_window(size: Vector2i) -> void:
	get_window().size = size
	await _frames(2)
	_comms()._canvas.queue_redraw()
	await _frames(2)


func _assert_plate_in_window(comms: CommsPanel) -> void:
	var window: Rect2 = main.get_viewport().get_visible_rect()
	assert_true(window.encloses(comms.drawn_plate), "the plate %s is inside the window %s" % [comms.drawn_plate, window])
	assert_gt(comms.drawn_plate.position.y, window.size.y * 0.5, "and in its lower half")
	assert_almost_eq(comms.drawn_plate.get_center().x, window.size.x * 0.5, 1.0, "centred")


# --- the line shows ----------------------------------------------------------------------------------------------------------


func test_a_mission_line_shows_in_the_chase_view_in_its_speakers_colour() -> void:
	assert_false(_comms().is_showing(), "nothing before the script speaks")
	await _first_line_showing()
	assert_eq(main.camera_rig.mode, CameraRig.Mode.CHASE)
	assert_true(_comms().is_showing())
	assert_eq(_comms().callsign(), "CONTROL")
	assert_gt(_comms().draws, 0, "it was drawn")
	assert_eq(_comms().drawn_text, HAIL_TEXT)
	assert_eq(_comms().drawn_callsign, "CONTROL")
	assert_eq(_comms().drawn_color, Factions.FRIENDLY_COLOR, "Earth Alliance reads friendly blue to the player")
	_assert_plate_in_window(_comms())


func test_a_mission_line_shows_in_the_cockpit_view_and_the_right_screen_keeps_the_roster() -> void:
	assert_true(_run("camera cockpit").ok)
	await _first_line_showing()
	assert_eq(main.camera_rig.mode, CameraRig.Mode.COCKPIT)
	assert_true(main.hud.frame.cockpit)
	assert_true(_comms().is_showing())
	assert_eq(_comms().drawn_text, HAIL_TEXT)
	_assert_plate_in_window(_comms())
	assert_true(main.hud.frame.screens.has(&"right"), "the console's right screen is in use")
	var items: Array[StringName] = (main.hud.frame.screens[&"right"] as HudSurface).items
	assert_has(items, HudSurface.ROSTER, "the wing roster stays on the right screen")
	assert_has(items, HudSurface.ACK, "and so do the acknowledgements")
	assert_does_not_have(items, &"comms", "the subtitles are not on a screen")


func test_the_plate_fits_the_window_at_1080p_and_at_960x540() -> void:
	await _first_line_showing()
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(960, 540)]:
		await _resize_window(size)
		assert_eq(main.get_viewport().get_visible_rect().size, Vector2(size), "the window is %s" % size)
		_assert_plate_in_window(_comms())
		var layout: CommsLayout = CommsLayout.compute(Vector2(size))
		assert_almost_eq(_comms().drawn_plate.end.y, layout.bottom_y, 0.5, "%s: bottom-anchored" % size)
		assert_gte(layout.text_px, 17 if size.y < 1000 else 24, "%s: legible" % size)


func test_the_subtitles_stay_when_the_hud_is_switched_off() -> void:
	Settings.set_value(&"show_hud", false)
	await _first_line_showing()
	assert_false(main.hud.visible)
	assert_true(_comms().visible, "a cinematic hides the HUD and still needs its subtitles")
	assert_gt(_comms().draws, 0)


func test_the_panel_sits_above_the_hud_and_below_the_pause_menu() -> void:
	assert_gt(_comms().layer, main.hud.layer)
	assert_lt(_comms().layer, 60, "the pause menu's layer")


# --- squelches and the queue -----------------------------------------------------------------------------------------------


func test_radio_open_and_close_frame_the_line() -> void:
	var audio: AudioDirector = main.audio
	assert_true(audio.has_sound(&"radio_open"), "built by scripts/gen_assets.sh and imported")
	assert_true(audio.has_sound(&"radio_close"))
	assert_eq(audio.times_played(&"radio_open"), 0)
	await _first_line_showing()
	assert_eq(audio.times_played(&"radio_open"), 1, "the channel opened as the line began")
	assert_eq(audio.times_played(&"radio_close"), 0, "and stays open while it is up")
	assert_true(await _until(func() -> bool: return not _comms().is_showing()))
	assert_eq(audio.times_played(&"radio_close"), 1, "the channel closed as it ended")
	assert_eq(audio.times_played(&"radio_open"), 1, "the next line waits out the gap")


func test_the_second_line_comes_after_the_first_in_its_own_colour() -> void:
	await _first_line_showing()
	assert_true(await _until(func() -> bool: return not _comms().is_showing()))
	assert_true(await _until(func() -> bool: return _comms().is_showing()), "the gap passes and the next line starts")
	await _frames(2)
	assert_eq(_comms().drawn_callsign, "RAIDER LEAD")
	assert_eq(_comms().drawn_color, Factions.HOSTILE_COLOR, "a raider reads hostile red")
	assert_eq(_comms().lines_shown, 2)


func test_a_line_waits_on_sim_time_and_not_while_paused() -> void:
	await _first_line_showing()
	var left: float = _comms().queue.remaining_s()
	main.set_paused(true)
	await _ticks(30)
	assert_eq(_comms().queue.remaining_s(), left, "paused: the line does not run down")
	assert_true(_comms().is_showing())
	main.set_paused(false)


# --- dialog_finished and skipping ------------------------------------------------------------------------------------------


func test_dialog_finished_fires_when_the_line_has_finished_showing() -> void:
	assert_eq(_api().objective_state(&"heard"), ObjectiveBook.HIDDEN)
	assert_true(await _until(func() -> bool: return _api().step_name() == &"warning"))
	assert_eq(_api().objective_state(&"heard"), ObjectiveBook.ACTIVE)
	assert_false(_api().world.line_finished(&"warning"))
	assert_true(await _until(func() -> bool: return _api().world.line_finished(&"warning")))
	await _ticks(1)
	assert_eq(_api().objective_state(&"heard"), ObjectiveBook.DONE, "its objective's trigger saw the line finish")
	assert_eq(_api().step_name(), &"close", "and the script moved on")
	assert_false(_api().has_ended(), "an optional objective does not end the mission")


func test_a_skip_logs_the_lines_and_shows_none_of_them() -> void:
	assert_true(_run("mission goto close").ok)
	await _ticks(2)
	await _frames(2)
	assert_eq(_api().step_name(), &"close")
	assert_has(_api().journal, "say hail")
	assert_has(_api().journal, "say warning")
	assert_true(_api().world.line_finished(&"hail"), "logged and finished")
	assert_true(_api().world.line_finished(&"warning"))
	assert_eq(_api().objective_state(&"heard"), ObjectiveBook.DONE, "a forced dialog_finished completes what waits on it")
	assert_eq(_comms().lines_shown, 0, "none was shown")
	assert_eq(_comms().draws, 0, "nothing was drawn")
	assert_false(_comms().is_showing())
	assert_eq(main.audio.times_played(&"radio_open"), 0, "and no squelch sounded")
	assert_eq(main.audio.times_played(&"radio_close"), 0)


func test_skipping_while_a_line_shows_cuts_it_without_a_closing_squelch() -> void:
	await _first_line_showing()
	assert_true(_comms().is_showing())
	assert_true(_run("mission skip").ok)
	assert_true(_api().world.line_finished(&"hail"))
	assert_false(_comms().is_showing() and _comms().callsign() == "CONTROL", "the cut line is gone")
	assert_eq(main.audio.times_played(&"radio_close"), 0, "a cut line makes no closing squelch")
	await _ticks(1)
	assert_eq(_api().step_name(), &"warning", "the next step runs normally, and its line shows")
	assert_eq(_comms().lines_shown, 2)


func test_the_mission_ending_takes_the_subtitle_down() -> void:
	await _first_line_showing()
	_api().end(false, "test")
	await _frames(2)
	assert_false(_comms().is_showing())


# --- data, console and a broken dialog -------------------------------------------------------------------------------------


func test_the_dialog_provider_reports_what_is_on_screen() -> void:
	assert_string_contains(_run("get dialog.showing").lines[0], "false")
	await _first_line_showing()
	assert_string_contains(_run("get dialog.line").lines[0], "hail")
	assert_string_contains(_run("get dialog.speaker").lines[0], "CONTROL")
	assert_string_contains(_run("get dialog.showing").lines[0], "true")
	assert_string_contains(_run("get dialog.lines_shown").lines[0], "1")


func test_a_dialog_file_that_does_not_validate_stops_the_mission_from_starting() -> void:
	main.queue_free()
	await _frames(1)
	main = await _make_main(BROKEN_PATH)
	assert_push_error("missing.json")
	assert_eq(main.mission.state_name(), "error")
	assert_string_contains(main.mission.error, "dialog")
	assert_string_contains(main.mission.error, "missing.json")
	assert_false(_comms().is_showing())
