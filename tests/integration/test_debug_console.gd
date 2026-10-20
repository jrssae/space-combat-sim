extends GutTest
## DebugConsole as a node (architecture §6.4; AC19-AC21). Command and startup behaviour runs on sandboxed instances
## (scratch Settings, scratch files, a recorded quit code). Keyboard handling runs on the real autoload, because the
## ` key, the prompt and the input mask only make sense on the one console that receives the viewport's input.

const DebugConsoleScript := preload("res://src/autoload/debug_console.gd")
const SettingsScript := preload("res://src/autoload/settings.gd")

const CONFIG_PATH := "user://test_console_settings.cfg"
const HISTORY_PATH := "user://test_console_history_it.txt"
const AUTOEXEC_PATH := "user://test_console_autoexec.cfg"
const SCRIPT_PATH := "user://test_console_script.cfg"
const SCRATCH_FILES: PackedStringArray = [CONFIG_PATH, HISTORY_PATH, AUTOEXEC_PATH, SCRIPT_PATH]


## GodotInputSource with one fake pad, so pad bindings can be driven with parse_input_event.
class OnePadSource:
	extends GodotInputSource

	func _pad_ids() -> Array[int]:
		var pads: Array[int] = [0]
		return pads

	func _pad_guid(_pad: int) -> String:
		return "fakepad0"

	func _pad_name(_pad: int) -> String:
		return "Fake Pad"


## Counts joypad events that reach _unhandled_input (what gameplay or GUI would see as events).
class PadEventProbe:
	extends Node

	var seen: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventJoypadButton:
			seen += 1


var settings: SettingsScript
var quit_codes: Array = []
var _autoload_settings_backup: Dictionary = {}
var _autoload_history_path: String = ""


func before_each() -> void:
	_delete_scratch_files()
	quit_codes.clear()
	settings = SettingsScript.new()
	settings.config_path = CONFIG_PATH
	settings.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(settings)
	for key: StringName in [&"console_enabled", &"console_pause_on_open", &"show_fps"]:
		_autoload_settings_backup[key] = Settings.get_value(key)
	_autoload_history_path = DebugConsole.history.path
	DebugConsole.history.path = HISTORY_PATH


func after_each() -> void:
	DebugConsole.close()
	DebugConsole.set_input_source(null)
	DebugConsole.history.path = _autoload_history_path
	DebugConsole.ui.prompt.clear()
	for key: StringName in _autoload_settings_backup.keys():
		Settings.set_value(key, _autoload_settings_backup[key])
	get_tree().paused = false
	Engine.time_scale = 1.0
	_release_inputs()


func after_all() -> void:
	_delete_scratch_files()


func _make_console(args: PackedStringArray = PackedStringArray(), startup: bool = false) -> DebugConsoleScript:
	var console: DebugConsoleScript = DebugConsoleScript.new()
	console.settings = settings
	console.history = ConsoleHistory.new(HISTORY_PATH)
	console.autoexec_path = AUTOEXEC_PATH
	console.user_args = args
	console.run_startup = startup
	console.mirror_stdout = false
	console.quit_handler = _on_quit
	add_child_autofree(console)
	return console


func _on_quit(code: int) -> void:
	quit_codes.append(code)


func _log(console: Node) -> String:
	return "\n".join(console.log_lines())


# --- settings: session vs saved (AC21) ---------------------------------------------------------------------------


func test_set_applies_now_and_only_save_writes_the_file() -> void:
	var console: DebugConsoleScript = _make_console()
	console.submit("set settings.stick_deadzone 0.2")
	assert_almost_eq(float(settings.get_value(&"stick_deadzone")), 0.2, 1e-9, "applied immediately")
	assert_true(settings.is_unsaved(&"stick_deadzone"))
	assert_false(FileAccess.file_exists(CONFIG_PATH), "set alone never writes the config file")
	assert_string_contains(_log(console), "> set settings.stick_deadzone 0.2\nsettings.stick_deadzone = 0.20")
	console.submit("state settings")
	assert_string_contains(_log(console), "settings.stick_deadzone = 0.20 *", "unsaved keys are marked")

	console.submit("save")
	assert_true(FileAccess.file_exists(CONFIG_PATH))
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(CONFIG_PATH), OK)
	assert_almost_eq(float(cfg.get_value("settings", "stick_deadzone")), 0.2, 1e-9)
	assert_false(settings.has_unsaved())


func test_invalid_value_is_rejected_and_nothing_changes() -> void:
	var console: DebugConsoleScript = _make_console()
	console.submit("set settings.stick_deadzone 0.9")
	assert_almost_eq(float(settings.get_value(&"stick_deadzone")), 0.15, 1e-9)
	assert_string_contains(_log(console), "error: settings.stick_deadzone must be in 0.0..0.3, got 0.9")
	assert_eq(quit_codes, [], "not strict: no quit")


func test_default_and_revert() -> void:
	var console: DebugConsoleScript = _make_console()
	console.submit("set settings.camera_default cockpit; save; set settings.invert_y on")
	assert_eq(settings.get_value(&"invert_y"), true)
	console.submit("revert")
	assert_eq(settings.get_value(&"invert_y"), false, "unsaved change dropped")
	assert_eq(settings.get_value(&"camera_default"), &"cockpit", "saved value kept")
	console.submit("default settings.camera_default")
	assert_eq(settings.get_value(&"camera_default"), &"chase")
	assert_true(settings.is_unsaved(&"camera_default"), "default is session-only until save")


# --- god / debug flags (AC19) ------------------------------------------------------------------------------------


func test_god_toggles_invulnerable_and_save_never_writes_it() -> void:
	var console: DebugConsoleScript = _make_console()
	console.submit("god")
	assert_true(console.flags.invulnerable, "god with no argument toggles")
	console.submit("god")
	assert_false(console.flags.invulnerable)
	console.submit("god on; get debug.invulnerable; save")
	assert_true(console.flags.invulnerable)
	assert_string_contains(_log(console), "debug.invulnerable = true")
	assert_true(FileAccess.file_exists(CONFIG_PATH))
	var text: String = FileAccess.get_file_as_string(CONFIG_PATH)
	assert_false(text.contains("invulnerable"), "save writes settings only, never debug flags")
	assert_false(text.contains("debug"))
	var fresh: DebugConsoleScript = _make_console()
	assert_false(fresh.flags.invulnerable, "a new session starts mortal")


# --- startup scripts and strict mode (AC21) ----------------------------------------------------------------------


func test_strict_startup_exits_1_on_the_first_error() -> void:
	var console: DebugConsoleScript = _make_console(PackedStringArray([
		"--console-strict", "--console-exec=set settings.stick_deadzone 0.9; quit 0"]), true)
	await wait_for_signal(console.startup_completed, 2.0)
	assert_eq(quit_codes, [1], "strict: the first error quits with 1, and quit 0 never runs")
	assert_almost_eq(float(settings.get_value(&"stick_deadzone")), 0.15, 1e-9)
	assert_string_contains(_log(console), "error: settings.stick_deadzone must be in")


func test_startup_runs_autoexec_then_files_then_exec() -> void:
	_write(AUTOEXEC_PATH, "set settings.invert_y on  # from autoexec\n\n")
	_write(SCRIPT_PATH, "get settings.invert_y\nset settings.show_fps on; get settings.show_fps\n")
	var start_frame: int = Engine.get_physics_frames()
	var console: DebugConsoleScript = _make_console(PackedStringArray([
		"--console-file=" + SCRIPT_PATH, "--console-exec", "get settings.roll_ramp_s; quit 4"]), true)
	await wait_for_signal(console.startup_completed, 2.0)
	assert_gt(Engine.get_physics_frames(), start_frame, "startup waits for a physics frame after the scene")
	assert_eq(quit_codes, [4])
	var echoes := PackedStringArray()
	for text: String in console.log_lines():
		if text.begins_with("> "):
			echoes.append(text)
	assert_eq(Array(echoes), ["> set settings.invert_y on", "> get settings.invert_y", "> set settings.show_fps on",
			"> get settings.show_fps", "> get settings.roll_ramp_s", "> quit 4"])
	assert_string_contains(_log(console), "settings.invert_y = true")


func test_missing_console_file_is_an_error_under_strict() -> void:
	var console: DebugConsoleScript = _make_console(PackedStringArray([
		"--console-strict", "--console-file=user://test_no_such_script.cfg", "--console-exec=quit 0"]), true)
	await wait_for_signal(console.startup_completed, 2.0)
	assert_eq(quit_codes, [1])
	assert_string_contains(_log(console), "no such file")


func test_parse_user_args() -> void:
	var parsed: Dictionary = DebugConsoleScript.parse_user_args(PackedStringArray([
		"--other", "--console-exec=help; quit", "--console-strict", "--console-file", "a.cfg", "--console-exec",
		"state"]))
	assert_true(parsed["strict"])
	assert_eq(Array(parsed["files"]), ["a.cfg"])
	assert_eq(Array(parsed["execs"]), ["help; quit", "state"])
	assert_false(DebugConsoleScript.parse_user_args(PackedStringArray())["strict"])


# --- queue: wait, exec, quit -------------------------------------------------------------------------------------


func test_wait_delays_the_rest_by_physics_frames() -> void:
	var console: DebugConsoleScript = _make_console()
	console.submit("wait 3; set settings.invert_y on")
	assert_true(console.is_waiting())
	assert_eq(settings.get_value(&"invert_y"), false, "held back")
	await wait_physics_frames(1)
	assert_eq(settings.get_value(&"invert_y"), false, "still held back after one frame")
	await wait_physics_frames(5)
	assert_false(console.is_waiting())
	assert_eq(settings.get_value(&"invert_y"), true, "ran after the wait")


func test_exec_runs_a_file_before_the_rest_of_the_line() -> void:
	_write(SCRIPT_PATH, "set settings.invert_y on\n# comment\nwait 1\nset settings.show_fps on\n")
	var console: DebugConsoleScript = _make_console()
	console.submit("exec %s; set settings.roll_ramp_s 0.5" % SCRIPT_PATH)
	assert_eq(settings.get_value(&"invert_y"), true)
	assert_eq(settings.get_value(&"show_fps"), false, "behind the file's wait")
	assert_almost_eq(float(settings.get_value(&"roll_ramp_s")), 0.25, 1e-9, "the rest of the line waits too")
	await wait_physics_frames(4)
	assert_eq(settings.get_value(&"show_fps"), true)
	assert_almost_eq(float(settings.get_value(&"roll_ramp_s")), 0.5, 1e-9)
	console.submit("exec test_no_such_script.cfg")
	assert_string_contains(_log(console), "error: no such file 'test_no_such_script.cfg' in user:// or res://")


func test_quit_drops_the_rest_of_the_queue() -> void:
	var console: DebugConsoleScript = _make_console()
	console.submit("quit 7; set settings.invert_y on")
	assert_eq(quit_codes, [7])
	assert_eq(settings.get_value(&"invert_y"), false)


# --- other core commands -----------------------------------------------------------------------------------------


func test_help_state_and_clear() -> void:
	var console: DebugConsoleScript = _make_console()
	console.submit("help")
	for usage: String in ["help [command]", "set <path> <value>", "timescale <0.05..1>", "quit [code]",
			"unwatch <path|all>", "fps [on|off]", "god [on|off]", "wait <frames>", "exec <file>"]:
		assert_string_contains(_log(console), usage)
	console.submit("help set")
	assert_string_contains(_log(console), "usage: set <path> <value>")
	console.submit("state")
	assert_string_contains(_log(console), "providers: debug, settings, time")
	console.submit("state time")
	assert_string_contains(_log(console), "time.timescale = 1.00")
	console.submit("clear")
	assert_eq(console.log_lines().size(), 0)
	console.submit("hepl")
	assert_string_contains(_log(console), "error: unknown command 'hepl' (did you mean help?)")


func test_timescale_is_clamped() -> void:
	var console: DebugConsoleScript = _make_console()
	console.submit("timescale 0.5")
	assert_almost_eq(Engine.time_scale, 0.5, 1e-9)
	console.submit("timescale 5")
	assert_almost_eq(Engine.time_scale, 1.0, 1e-9, "capped at 1 in M1")
	console.submit("timescale 0.001")
	assert_almost_eq(Engine.time_scale, 0.05, 1e-9)
	assert_string_contains(_log(console), "timescale = 0.05 (clamped to 0.05..1)")
	console.submit("get time.timescale")
	assert_string_contains(_log(console), "time.timescale = 0.05")


func test_fps_follows_show_fps() -> void:
	var console: DebugConsoleScript = _make_console()
	assert_false(console.fps_counter.visible)
	console.submit("fps")
	assert_eq(settings.get_value(&"show_fps"), true)
	assert_true(console.fps_counter.visible)
	assert_string_contains(console.fps_counter.compose_text(), "FPS")
	assert_string_contains(console.fps_counter.compose_text(), "ms")
	console.submit("fps off")
	assert_false(console.fps_counter.visible)
	settings.set_value(&"show_fps", true)
	assert_true(console.fps_counter.visible, "the counter follows the setting, however it is changed")


func test_watch_and_unwatch() -> void:
	var console: DebugConsoleScript = _make_console()
	console.submit("watch settings.invert_y")
	assert_true(console.fps_counter.visible, "watched values show even without the FPS line")
	assert_eq(console.fps_counter.compose_text(), "settings.invert_y = false")
	settings.set_value(&"invert_y", true)
	assert_eq(console.fps_counter.compose_text(), "settings.invert_y = true", "live")
	console.submit("watch settings.nope")
	assert_string_contains(_log(console), "error: unknown key 'settings.nope'")
	for key: String in ["stick_deadzone", "trigger_deadzone", "roll_ramp_s", "assist_default", "camera_default",
			"show_overlay", "show_fps"]:
		console.submit("watch settings." + key)
	assert_eq(console.watches().size(), DebugConsoleScript.MAX_WATCHES)
	console.submit("watch settings.console_enabled")
	assert_string_contains(_log(console), "error: the watch list is full (8)")
	console.submit("unwatch settings.invert_y")
	assert_eq(console.watches().size(), 7)
	console.submit("unwatch all")
	assert_eq(console.watches().size(), 0)
	assert_false(console.fps_counter.visible)


func test_input_provider_and_owner_pruning() -> void:
	var console: DebugConsoleScript = _make_console()
	var source := OnePadSource.new()
	var adapter := InputAdapter.new()
	console.set_input_source(source, adapter)
	_pad_button(JOY_BUTTON_A, true)
	adapter.sample(source, 1.0 / 60.0)
	console.submit("get input.fire; get input.keyboard_masked; get input.main_right; state input")
	var text: String = _log(console)
	assert_string_contains(text, "input.fire = true")
	assert_string_contains(text, "input.keyboard_masked = false")
	assert_string_contains(text, "input.main_right = 0.00")
	assert_string_contains(text, "input.pads = [{id: 0, name: Fake Pad, guid: fakepad0")
	source = null
	adapter = null
	assert_false(console.registry.has_provider(&"input"), "the provider goes when the source is freed")


func test_logger_routes_engine_errors_into_the_log() -> void:
	var console: DebugConsoleScript = _make_console()
	push_error("console logger probe 4711")
	assert_push_error("console logger probe 4711")
	await wait_process_frames(2)
	assert_string_contains(_log(console), "ERROR: console logger probe 4711")


func test_console_logger_queue() -> void:
	var logger := ConsoleLogger.new()
	var no_backtrace: Array[ScriptBacktrace] = []
	logger._log_error("fn", "core/thing.cpp", 12, "Condition failed", "", false, Logger.ERROR_TYPE_ERROR, no_backtrace)
	logger._log_error("fn", "core/thing.cpp", 13, "code", "careful", false, Logger.ERROR_TYPE_WARNING, no_backtrace)
	var drained: Array[Dictionary] = logger.drain()
	assert_eq(drained.size(), 2)
	assert_eq(drained[0], {"text": "ERROR: Condition failed (core/thing.cpp:12)", "warning": false})
	assert_eq(drained[1], {"text": "WARNING: careful (core/thing.cpp:13)", "warning": true})
	assert_eq(logger.drain().size(), 0, "drained")
	for i: int in ConsoleLogger.MAX_QUEUED + 5:
		logger._log_error("", "", 0, "flood %d" % i, "", false, Logger.ERROR_TYPE_ERROR, no_backtrace)
	drained = logger.drain()
	assert_eq(drained.size(), ConsoleLogger.MAX_QUEUED + 1)
	assert_eq(drained[0]["text"], "(5 older engine messages dropped)")
	assert_eq(drained[drained.size() - 1]["text"], "ERROR: flood %d" % (ConsoleLogger.MAX_QUEUED + 4))


# --- keyboard rules on the real autoload (AC20) ------------------------------------------------------------------


func test_autoload_is_registered_after_sim_clock_and_always_processes() -> void:
	var names := PackedStringArray()
	for child: Node in get_tree().root.get_children():
		names.append(child.name)
	assert_lt(names.find("SimClock"), names.find("DebugConsole"))
	assert_lt(names.find("Settings"), names.find("SimClock"))
	assert_eq(DebugConsole.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(DebugConsole.ui.layer, 100)
	assert_eq(DebugConsole.fps_counter.layer, 99)
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				assert_ne((event as InputEventKey).physical_keycode, KEY_QUOTELEFT, "` is bound to %s" % action)


func test_backquote_toggles_and_never_types() -> void:
	assert_false(DebugConsole.is_open())
	_key(KEY_QUOTELEFT, true, 96)
	assert_true(DebugConsole.is_open())
	assert_true(DebugConsole.captures_keyboard())
	assert_true(DebugConsole.ui.visible)
	_key(KEY_QUOTELEFT, false, 96)
	assert_eq(DebugConsole.ui.prompt.text, "", "the ` never reaches the prompt")
	_key(KEY_QUOTELEFT, true, 96)
	assert_false(DebugConsole.is_open())
	assert_false(DebugConsole.ui.visible)
	_key(KEY_QUOTELEFT, false, 96)


func test_escape_closes() -> void:
	_key(KEY_QUOTELEFT, true, 96)
	_key(KEY_QUOTELEFT, false, 96)
	assert_true(DebugConsole.is_open())
	_key(KEY_ESCAPE, true)
	assert_false(DebugConsole.is_open())
	_key(KEY_ESCAPE, false)


func test_console_enabled_false_ignores_the_key() -> void:
	Settings.set_value(&"console_enabled", false)
	_key(KEY_QUOTELEFT, true, 96)
	_key(KEY_QUOTELEFT, false, 96)
	assert_false(DebugConsole.is_open())


func test_open_console_masks_keyboard_but_not_pad() -> void:
	var source := OnePadSource.new()
	var adapter := InputAdapter.new()
	DebugConsole.set_input_source(source, adapter)
	_key(KEY_E, true)  # main_right
	_pad_button(JOY_BUTTON_A, true)  # fire
	var cmd: PilotCommand = adapter.sample(source, 1.0 / 60.0)
	assert_eq(cmd.flight.main_right, 1.0, "keyboard flies while the console is closed")
	assert_true(cmd.combat.fire)

	_key(KEY_QUOTELEFT, true, 96)
	assert_false(source.keyboard_mouse_enabled, "the console clears the mask flag")
	cmd = adapter.sample(source, 1.0 / 60.0)
	assert_eq(cmd.flight.main_right, 0.0, "key-bound action reads 0 while the console is open")
	assert_true(cmd.combat.fire, "pad-bound action still works")
	_pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.525)
	cmd = adapter.sample(source, 1.0 / 60.0)
	assert_almost_eq(cmd.flight.main_left, 0.5, 1e-5, "the pad keeps flying")
	assert_eq(DebugConsole.registry.format_path("input.keyboard_masked"), "input.keyboard_masked = true")

	_key(KEY_QUOTELEFT, true, 96)
	assert_true(source.keyboard_mouse_enabled)
	cmd = adapter.sample(source, 1.0 / 60.0)
	assert_eq(cmd.flight.main_right, 1.0, "keyboard back after closing")


func test_pad_events_are_swallowed_only_while_open() -> void:
	var probe := PadEventProbe.new()
	add_child_autofree(probe)
	_pad_button(JOY_BUTTON_X, true)
	_pad_button(JOY_BUTTON_X, false)
	var seen_closed: int = probe.seen
	assert_gt(seen_closed, 0, "pad events reach the game while the console is closed")
	DebugConsole.open()
	_pad_button(JOY_BUTTON_X, true)
	assert_eq(probe.seen, seen_closed, "the console UI swallows pad events")
	assert_true(Input.is_joy_button_pressed(0, JOY_BUTTON_X), "device polling is unaffected")
	_pad_button(JOY_BUTTON_X, false)


func test_opening_and_closing_with_a_key_held_fires_no_edge() -> void:
	var source := OnePadSource.new()
	var adapter := InputAdapter.new()
	DebugConsole.set_input_source(source, adapter)
	_key(KEY_V, true)  # toggle_camera
	assert_true(adapter.sample(source, 1.0 / 60.0).ui.toggle_camera, "a fresh press is an edge")
	assert_false(adapter.sample(source, 1.0 / 60.0).ui.toggle_camera, "held is not")

	_key(KEY_QUOTELEFT, true, 96)
	assert_false(adapter.sample(source, 1.0 / 60.0).ui.toggle_camera, "opening with V held")
	_key(KEY_T, true)  # target_next, pressed while typing
	assert_false(adapter.sample(source, 1.0 / 60.0).combat.target_next, "typing never fires")
	_key(KEY_QUOTELEFT, true, 96)
	var after_close: PilotCommand = adapter.sample(source, 1.0 / 60.0)
	assert_false(after_close.ui.toggle_camera, "closing with V still held fires no edge")
	assert_false(after_close.combat.target_next, "closing with T still held fires no edge")

	_key(KEY_T, false)
	adapter.sample(source, 1.0 / 60.0)
	_key(KEY_T, true)
	assert_true(adapter.sample(source, 1.0 / 60.0).combat.target_next, "a real press after closing still works")


func test_pause_on_open() -> void:
	Settings.set_value(&"console_pause_on_open", false)
	DebugConsole.open()
	assert_false(get_tree().paused, "off by default: sim time keeps running")
	DebugConsole.close()
	Settings.set_value(&"console_pause_on_open", true)
	DebugConsole.open()
	assert_true(get_tree().paused, "console_pause_on_open pauses the tree")
	DebugConsole.close()
	assert_false(get_tree().paused, "closing resumes")


func test_prompt_tab_history_and_enter() -> void:
	_key(KEY_QUOTELEFT, true, 96)
	_key(KEY_QUOTELEFT, false, 96)
	var prompt: LineEdit = DebugConsole.ui.prompt
	assert_true(prompt.has_focus(), "the prompt has the keyboard")
	prompt.text = "hel"
	prompt.caret_column = 3
	_key(KEY_TAB, true)
	_key(KEY_TAB, false)
	assert_eq(prompt.text, "help ", "Tab completes")
	prompt.text = "get settings.invert_"
	_key(KEY_TAB, true)
	_key(KEY_TAB, false)
	assert_eq(prompt.text, "get settings.invert_y ")
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	assert_eq(prompt.text, "", "Enter runs and clears the line")
	assert_string_contains("\n".join(DebugConsole.log_lines()), "> get settings.invert_y\nsettings.invert_y = ")
	assert_eq(DebugConsole.history.entries()[DebugConsole.history.size() - 1], "get settings.invert_y")
	assert_true(FileAccess.file_exists(HISTORY_PATH), "history is persisted")
	_key(KEY_UP, true)
	_key(KEY_UP, false)
	assert_eq(prompt.text, "get settings.invert_y", "Up recalls history")
	_key(KEY_DOWN, true)
	_key(KEY_DOWN, false)
	assert_eq(prompt.text, "", "Down returns to the draft")


# --- helpers -----------------------------------------------------------------------------------------------------


func _key(keycode: Key, pressed: bool, unicode: int = 0) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	e.keycode = keycode
	e.unicode = unicode
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _pad_button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _pad_axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _release_inputs() -> void:
	for key: Key in [KEY_E, KEY_V, KEY_T, KEY_QUOTELEFT, KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_UP, KEY_DOWN]:
		if Input.is_physical_key_pressed(key):
			_key(key, false)
	for button: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_X]:
		_pad_button(button, false)
	_pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _delete_scratch_files() -> void:
	for path: String in SCRATCH_FILES:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_screenshot_refuses_politely_when_headless() -> void:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute("screenshot user://never.png")
	assert_eq(results.size(), 1)
	assert_false(results[0].ok)
	assert_string_contains(results[0].error, "headless")
	assert_false(FileAccess.file_exists("user://never.png"))
