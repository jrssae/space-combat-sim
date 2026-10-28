extends Node
## DebugConsole autoload: the always-on ` console (architecture §6.4). Owns the ConsoleRegistry, the ConsoleUI and
## FpsCounter canvas layers, the ConsoleLogger and the session-only DebugFlags. Runs while the tree is paused.
##
## Subsystems extend it only by registering, in `_ready`, with themselves as owner (and `unregister_owner(self)` in
## `_exit_tree`); this script imports no gameplay subsystem:
##
##     DebugConsole.registry.register_command(ConsoleCommand.new(&"assist", "Toggle or set flight assist",
##         [ConsoleArg.bool_optional(&"state")]), _cmd_assist, self)
##     DebugConsole.registry.register_provider(&"ship", ConsoleVars.new({...}), self)
##
## Every statement and its output go to the log and to stdout as `[console] > cmd` / `[console] output`; errors go to
## stderr as `[console] error: ...`. Startup scripts (user://autoexec.cfg, then `--console-file=<path>`, then
## `--console-exec="cmd; cmd"`, all after `--` on the command line) run one physics frame after the current scene is
## ready; with `--console-strict` the first error quits with exit code 1.

signal opened
signal closed
## The startup scripts have been queued and run up to their first `wait` (or to the end).
signal startup_completed

const ConsoleUIScene: PackedScene = preload("res://src/console/console_ui.tscn")
const FpsCounterScene: PackedScene = preload("res://src/console/fps_counter.tscn")
const SettingsScript := preload("res://src/autoload/settings.gd")
const SimClockScript := preload("res://src/autoload/sim_clock.gd")

## Physical key, so it is the same key on every layout. Never an InputMap action (tests/unit/test_input_map.gd).
const CONSOLE_KEY: Key = KEY_QUOTELEFT
const DEFAULT_AUTOEXEC_PATH: String = "user://autoexec.cfg"
const MAX_WATCHES: int = 8
const TIMESCALE_MIN: float = 0.05
const TIMESCALE_MAX: float = 1.0  # M1 cap: above 1 each physics tick stretches; real warp is SimClock's (M9)
const TIMESCALE_RANGE: String = "0.05..1"
const MAX_STATEMENTS_PER_PUMP: int = 10000
const ARG_EXEC: String = "--console-exec"
const ARG_FILE: String = "--console-file"
const ARG_STRICT: String = "--console-strict"
const OUTPUT_PREFIX: String = "[console] "

var registry: ConsoleRegistry = ConsoleRegistry.new()
## Session-only cheats (`debug` provider). Gameplay reads e.g. `DebugConsole.flags.invulnerable`.
var flags: DebugFlags = DebugFlags.new()
var history: ConsoleHistory = ConsoleHistory.new()
var ui: ConsoleUI = null
var fps_counter: FpsCounter = null
## Set by `--console-strict` (or a test): the first error quits with exit code 1.
var strict: bool = false

# Injection points, read when the node enters the tree. The defaults are what the autoload uses; tests point them
# at scratch instances and files.
var settings: SettingsScript = null  ## null: /root/Settings
var sim_clock: SimClockScript = null  ## null: /root/SimClock
var autoexec_path: String = DEFAULT_AUTOEXEC_PATH
var user_args: PackedStringArray = OS.get_cmdline_user_args()
var run_startup: bool = true
var mirror_stdout: bool = true
## Callable(code: int); defaults to `get_tree().quit(code)`.
var quit_handler: Callable = Callable()

var _logger: ConsoleLogger = ConsoleLogger.new()
var _logger_added: bool = false
var _open: bool = false
var _paused_by_console: bool = false
var _queue: Array[PackedStringArray] = []
var _wait_frames: int = 0
var _halted: bool = false
var _watches: PackedStringArray = PackedStringArray()
var _input_source_ref: WeakRef = null
var _input_adapter_ref: WeakRef = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _enter_tree() -> void:
	if not _logger_added:
		OS.add_logger(_logger)
		_logger_added = true


func _ready() -> void:
	if settings == null:
		settings = get_node_or_null(^"/root/Settings") as SettingsScript
	if sim_clock == null:
		sim_clock = get_node_or_null(^"/root/SimClock") as SimClockScript
	history.load_file()

	ui = ConsoleUIScene.instantiate() as ConsoleUI
	ui.history = history
	ui.completer = registry.complete
	ui.logger = _logger
	ui.submitted.connect(_on_ui_submitted)
	add_child(ui)
	fps_counter = FpsCounterScene.instantiate() as FpsCounter
	fps_counter.formatter = registry.format_path
	add_child(fps_counter)

	_register_core_commands()
	_register_providers()
	if settings != null:
		settings.changed.connect(_on_setting_changed)
		fps_counter.show_fps = bool(settings.get_value(&"show_fps"))
	if run_startup:
		_run_startup_when_ready()


func _exit_tree() -> void:
	if _logger_added:
		OS.remove_logger(_logger)
		_logger_added = false
	if _open:
		# Leaving the tree while open: hand the keyboard back and undo our pause, without touching the UI (its
		# nodes have already left the tree).
		_open = false
		_apply_input_mask()
		if _paused_by_console:
			_paused_by_console = false
			get_tree().paused = false


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if _is_console_key(key):
		if not _open and not _console_enabled():
			return  # console_enabled = false: the key does nothing (it is bound to no action either)
		get_viewport().set_input_as_handled()  # never reaches the prompt as a character
		if key.pressed and not key.echo:
			toggle()
		return
	if _open and key.pressed and not key.echo and _is_key(key, KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		close()


func _physics_process(_delta: float) -> void:
	if _wait_frames > 0:
		_wait_frames -= 1
		if _wait_frames == 0:
			_pump()


# --- Opening and input -------------------------------------------------------------------------------------------


func is_open() -> bool:
	return _open


## True while the console has the keyboard: GodotInputSource then drops key and mouse bindings (§6.1).
func captures_keyboard() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_apply_input_mask()
	ui.set_open(true)
	if settings != null and bool(settings.get_value(&"console_pause_on_open")) and not get_tree().paused:
		get_tree().paused = true
		_paused_by_console = true
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_apply_input_mask()
	ui.set_open(false)
	if _paused_by_console:
		_paused_by_console = false
		if is_inside_tree():
			get_tree().paused = false
	closed.emit()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## The gameplay input source (and the adapter that samples it) the console masks while open and exposes as the
## `input` provider. Both are held weakly: the scene that owns them keeps them alive. Pass null to detach.
func set_input_source(source: InputSource, adapter: InputAdapter = null) -> void:
	var previous: InputSource = _input_source()
	if previous != null and previous != source:
		previous.keyboard_mouse_enabled = true
	_input_source_ref = (weakref(source) as WeakRef) if source != null else null
	_input_adapter_ref = (weakref(adapter) as WeakRef) if adapter != null else null
	registry.unregister_provider(&"input")
	if source == null:
		return
	source.keyboard_mouse_enabled = not _open
	registry.register_provider(&"input", _input_vars(adapter != null), source)


## Re-seeds the input adapter's edge state from what is held now. Call it after the bindings changed under the
## adapter (a control profile was applied), so a button that now means something else cannot fire an edge.
func resync_input_edges() -> void:
	var source: InputSource = _input_source()
	var adapter: InputAdapter = _input_adapter()
	if source != null and adapter != null:
		adapter.resync_edges(source)


# --- Running commands --------------------------------------------------------------------------------------------


## Runs a line as if it had been typed at the prompt (it is not added to history).
func submit(line: String) -> void:
	var tokenizer := ConsoleTokenizer.new()
	var statements: Array[PackedStringArray] = tokenizer.split(line)
	if not tokenizer.error.is_empty():
		_output("> " + line.strip_edges(), ConsoleUI.LineKind.ECHO)
		_report_error(tokenizer.error)
		return
	enqueue(statements)


## Appends statements to the queue and runs it (up to the next `wait`).
func enqueue(statements: Array[PackedStringArray]) -> void:
	if _halted:
		return
	_queue.append_array(statements)
	_pump()


## True while a `wait` holds statements back.
func is_waiting() -> bool:
	return _wait_frames > 0


func watches() -> PackedStringArray:
	return _watches.duplicate()


## The log as plain text, oldest first.
func log_lines() -> PackedStringArray:
	return ui.lines()


## Runs the startup scripts now: user://autoexec.cfg, every `--console-file`, then every `--console-exec`.
func run_startup_scripts() -> void:
	var parsed: Dictionary = parse_user_args(user_args)
	strict = strict or bool(parsed["strict"])
	var statements: Array[PackedStringArray] = []
	if FileAccess.file_exists(autoexec_path):
		if not _collect(load_script_file(autoexec_path), statements):
			return
	for path: String in parsed["files"]:
		if not _collect(load_script_file(resolve_script_path(path)), statements):
			return
	var tokenizer := ConsoleTokenizer.new()
	for line: String in parsed["execs"]:
		var exec_statements: Array[PackedStringArray] = tokenizer.split(line)
		if not tokenizer.error.is_empty():
			_report_error("%s: %s" % [ARG_EXEC, tokenizer.error])
			if _halted:
				return
			continue
		statements.append_array(exec_statements)
	enqueue(statements)


## Splits `OS.get_cmdline_user_args()`-style arguments. Accepts `--console-exec=...` and `--console-exec ...`
## (same for `--console-file`). Returns {"strict": bool, "files": PackedStringArray, "execs": PackedStringArray}.
static func parse_user_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {"strict": false, "files": PackedStringArray(), "execs": PackedStringArray()}
	var i: int = 0
	while i < args.size():
		var arg: String = args[i]
		if arg == ARG_STRICT:
			out["strict"] = true
		for pair: Array in [[ARG_EXEC, "execs"], [ARG_FILE, "files"]]:
			var flag: String = pair[0]
			var bucket: PackedStringArray = out[pair[1]]
			if arg.begins_with(flag + "="):
				bucket.append(arg.substr(flag.length() + 1))
			elif arg == flag and i + 1 < args.size():
				i += 1
				bucket.append(args[i])
			out[pair[1]] = bucket
		i += 1
	return out


## Reads a command file: one or more statements per line, `#` comments, blank lines ignored.
## Returns {"ok": bool, "statements": Array[PackedStringArray], "error": String}.
static func load_script_file(path: String) -> Dictionary:
	var statements: Array[PackedStringArray] = []
	if not FileAccess.file_exists(path):
		return {"ok": false, "statements": statements, "error": "no such file '%s'" % path}
	var text: String = FileAccess.get_file_as_string(path)
	var tokenizer := ConsoleTokenizer.new()
	var line_number: int = 0
	for line: String in text.split("\n"):
		line_number += 1
		var found: Array[PackedStringArray] = tokenizer.split(line)
		if not tokenizer.error.is_empty():
			return {"ok": false, "statements": statements,
					"error": "%s:%d: %s" % [path, line_number, tokenizer.error]}
		statements.append_array(found)
	return {"ok": true, "statements": statements, "error": ""}


## `res://`, `user://` and absolute paths as given; a relative path is looked up in user:// first, then res://.
static func resolve_script_path(path: String) -> String:
	if path.is_absolute_path():
		return path
	var user_path: String = "user://".path_join(path)
	if FileAccess.file_exists(user_path):
		return user_path
	return "res://".path_join(path)


func _run_startup_when_ready() -> void:
	await get_tree().process_frame  # the current scene has been added and is ready
	if not is_inside_tree():
		return
	await get_tree().physics_frame  # ...and one physics frame later its deferred setup has run
	if not is_inside_tree():
		return
	run_startup_scripts()
	startup_completed.emit()


func _collect(loaded: Dictionary, into: Array[PackedStringArray]) -> bool:
	if not loaded["ok"]:
		_report_error(loaded["error"])
		return not _halted
	var found: Array[PackedStringArray] = loaded["statements"]
	into.append_array(found)
	return true


func _pump() -> void:
	var budget: int = MAX_STATEMENTS_PER_PUMP
	while not _queue.is_empty() and _wait_frames == 0 and not _halted:
		budget -= 1
		if budget < 0:
			_queue.clear()
			_report_error("too many commands in one frame (recursive exec?)")
			return
		var tokens: PackedStringArray = _queue.pop_front()
		_output("> " + ConsoleFormat.join_tokens(tokens), ConsoleUI.LineKind.ECHO)
		var result: ConsoleResult = registry.execute_tokens(tokens)
		for text: String in result.lines:
			_output(text, ConsoleUI.LineKind.OUTPUT)
		if not result.ok:
			_report_error(result.error)
			continue
		if not result.inject.is_empty():
			var merged: Array[PackedStringArray] = result.inject.duplicate()
			merged.append_array(_queue)
			_queue = merged
		if result.quit_code >= 0:
			_quit(result.quit_code)
			return
		if result.wait_frames > 0:
			_wait_frames = result.wait_frames


func _report_error(message: String) -> void:
	_output("error: " + message, ConsoleUI.LineKind.ERROR)
	if strict:
		_quit(1)


func _quit(code: int) -> void:
	_halted = true
	_queue.clear()
	_wait_frames = 0
	if quit_handler.is_valid():
		quit_handler.call(code)
	elif is_inside_tree():
		get_tree().quit(code)


func _output(text: String, kind: ConsoleUI.LineKind) -> void:
	if ui != null:
		ui.append(text, kind)
	if mirror_stdout:
		if kind == ConsoleUI.LineKind.ERROR:
			printerr(OUTPUT_PREFIX + text)
		else:
			print(OUTPUT_PREFIX + text)


func _on_ui_submitted(line: String) -> void:
	submit(line)


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"show_fps":
		fps_counter.show_fps = bool(value)


func _console_enabled() -> bool:
	return settings == null or bool(settings.get_value(&"console_enabled"))


static func _is_console_key(key: InputEventKey) -> bool:
	# Synthetic events (tests, remapping tools) may carry only the logical keycode.
	return key.physical_keycode == CONSOLE_KEY or (key.physical_keycode == KEY_NONE and key.keycode == CONSOLE_KEY)


static func _is_key(key: InputEventKey, which: Key) -> bool:
	return key.physical_keycode == which or key.keycode == which


func _apply_input_mask() -> void:
	var source: InputSource = _input_source()
	if source == null:
		return
	source.keyboard_mouse_enabled = not _open
	var adapter: InputAdapter = _input_adapter()
	if adapter != null:
		adapter.resync_edges(source)  # a key held across the transition must not fire an edge


func _input_source() -> InputSource:
	if _input_source_ref == null:
		return null
	return _input_source_ref.get_ref() as InputSource


func _input_adapter() -> InputAdapter:
	if _input_adapter_ref == null:
		return null
	return _input_adapter_ref.get_ref() as InputAdapter


# --- Core commands -----------------------------------------------------------------------------------------------


func _register_core_commands() -> void:
	var value_arg: ConsoleArg = ConsoleArg.string_rest(&"value")
	value_arg.value_of = 0
	var commands: Array[Array] = [
		[ConsoleCommand.new(&"help", "List commands, or show one command's usage",
				[ConsoleArg.string_optional(&"command").with_suggestions(_command_name_list)]), _cmd_help],
		[ConsoleCommand.new(&"clear", "Clear the console log"), _cmd_clear],
		[ConsoleCommand.new(&"state", "List state providers, or every key = value of one (* = unsaved)",
				[ConsoleArg.string_optional(&"provider").with_suggestions(_provider_name_list)]), _cmd_state],
		[ConsoleCommand.new(&"get", "Print one value, e.g. get ship.speed",
				[ConsoleArg.path_required(&"path")]), _cmd_get],
		[ConsoleCommand.new(&"set", "Type-checked write; settings.* apply now and stay session-only until save",
				[ConsoleArg.path_required(&"path", ConsoleArg.PathFilter.WRITABLE), value_arg]), _cmd_set],
		[ConsoleCommand.new(&"toggle", "Flip a writable bool",
				[ConsoleArg.path_required(&"path", ConsoleArg.PathFilter.WRITABLE_BOOL)]), _cmd_toggle],
		[ConsoleCommand.new(&"default", "Reset a setting to its default (session only until save)",
				[ConsoleArg.path_required(&"path", ConsoleArg.PathFilter.RESETTABLE)]), _cmd_default],
		[ConsoleCommand.new(&"save", "Persist all settings to user://settings.cfg"), _cmd_save],
		[ConsoleCommand.new(&"revert", "Reload settings from user://settings.cfg, dropping unsaved changes"),
				_cmd_revert],
		[ConsoleCommand.new(&"watch", "Show a live value under the FPS counter (max %d, session)" % MAX_WATCHES,
				[ConsoleArg.path_required(&"path")]), _cmd_watch],
		[ConsoleCommand.new(&"unwatch", "Stop watching a path, or all of them",
				[ConsoleArg.string_required(&"path").with_hint("path|all").with_suggestions(_unwatch_list)]),
				_cmd_unwatch],
		[ConsoleCommand.new(&"fps", "Show or hide the FPS counter (toggle settings.show_fps)",
				[ConsoleArg.bool_optional(&"state")]), _cmd_fps],
		[ConsoleCommand.new(&"god", "Toggle invulnerability (debug.invulnerable); session only, never saved",
				[ConsoleArg.bool_optional(&"state")]), _cmd_god],
		[ConsoleCommand.new(&"timescale", "Debug slow motion via Engine.time_scale, clamped to " + TIMESCALE_RANGE,
				[ConsoleArg.float_required(&"scale").with_hint(TIMESCALE_RANGE)]), _cmd_timescale],
		[ConsoleCommand.new(&"exec", "Run commands from a res:// or user:// file, one or more per line",
				[ConsoleArg.string_required(&"file")]), _cmd_exec],
		[ConsoleCommand.new(&"wait", "Delay the rest of the queue by N physics frames",
				[ConsoleArg.int_required(&"frames", 0, 1000000)]), _cmd_wait],
		[ConsoleCommand.new(&"screenshot", "Save the last rendered frame as a PNG (default user://screenshots/)",
				[ConsoleArg.string_optional(&"path")]), _cmd_screenshot],
		[ConsoleCommand.new(&"quit", "Quit with an exit code (default 0)",
				[ConsoleArg.int_optional(&"code", 0, 0, 255)]), _cmd_quit],
	]
	for pair: Array in commands:
		registry.register_command(pair[0], pair[1], self)


func _cmd_help(args: Dictionary) -> ConsoleResult:
	if args[&"command"] == null:
		return ConsoleResult.success(registry.help())
	var command_name := StringName(String(args[&"command"]).to_lower())
	if not registry.has_command(command_name):
		return ConsoleResult.failure(registry.help(command_name)[0])
	return ConsoleResult.success(registry.help(command_name))


func _cmd_clear(_args: Dictionary) -> ConsoleResult:
	ui.clear_log()
	return ConsoleResult.success()


func _cmd_state(args: Dictionary) -> ConsoleResult:
	if args[&"provider"] == null:
		return ConsoleResult.line("providers: " + ", ".join(_provider_name_list()))
	var provider_name := StringName(String(args[&"provider"]).to_lower())
	if not registry.has_provider(provider_name):
		return ConsoleResult.failure("unknown provider '%s'%s" % [provider_name,
				ConsoleFormat.did_you_mean(String(provider_name), _provider_name_list())])
	var out: PackedStringArray = registry.describe_provider(provider_name)
	if out.is_empty():
		out.append("%s has no keys" % provider_name)
	return ConsoleResult.success(out)


func _cmd_get(args: Dictionary) -> ConsoleResult:
	return ConsoleResult.line(registry.format_path(args[&"path"]))


func _cmd_set(args: Dictionary) -> ConsoleResult:
	return registry.write_text(args[&"path"], args[&"value"])


func _cmd_toggle(args: Dictionary) -> ConsoleResult:
	return registry.toggle(args[&"path"])


func _cmd_default(args: Dictionary) -> ConsoleResult:
	return registry.reset(args[&"path"])


func _cmd_save(_args: Dictionary) -> ConsoleResult:
	if settings == null:
		return ConsoleResult.failure("there is no Settings node to save")
	if settings.save() != OK:
		return ConsoleResult.failure(settings.get_last_error())
	return ConsoleResult.line("settings saved to %s" % settings.config_path)


func _cmd_revert(_args: Dictionary) -> ConsoleResult:
	if settings == null:
		return ConsoleResult.failure("there is no Settings node to revert")
	var err: Error = settings.revert()
	if err != OK:
		return ConsoleResult.failure("could not read %s (%s); using defaults" % [settings.config_path,
				error_string(err)])
	return ConsoleResult.line("settings reloaded from %s" % settings.config_path)


func _cmd_watch(args: Dictionary) -> ConsoleResult:
	var path: String = args[&"path"]
	if _watches.has(path):
		return ConsoleResult.line("already watching %s" % path)
	if _watches.size() >= MAX_WATCHES:
		return ConsoleResult.failure("the watch list is full (%d); unwatch something first" % MAX_WATCHES)
	_watches.append(path)
	fps_counter.set_watches(_watches)
	return ConsoleResult.line("watching %s" % path)


func _cmd_unwatch(args: Dictionary) -> ConsoleResult:
	var target: String = args[&"path"]
	if target == "all":
		var count: int = _watches.size()
		_watches.clear()
		fps_counter.set_watches(_watches)
		return ConsoleResult.line("unwatched %d" % count)
	if not _watches.has(target):
		return ConsoleResult.failure("not watching '%s'%s" % [target, ConsoleFormat.did_you_mean(target, _watches)])
	_watches.remove_at(_watches.find(target))
	fps_counter.set_watches(_watches)
	return ConsoleResult.line("unwatched %s" % target)


func _cmd_fps(args: Dictionary) -> ConsoleResult:
	return registry.toggle("settings.show_fps", args[&"state"])


func _cmd_god(args: Dictionary) -> ConsoleResult:
	return registry.toggle("debug.invulnerable", args[&"state"])


func _cmd_timescale(args: Dictionary) -> ConsoleResult:
	var requested: float = args[&"scale"]
	var applied: float = clampf(requested, TIMESCALE_MIN, TIMESCALE_MAX)
	Engine.time_scale = applied
	var text: String = "timescale = %s" % ConsoleFormat.number(applied)
	if applied != requested:
		text += " (clamped to %s)" % TIMESCALE_RANGE
	return ConsoleResult.line(text)


func _cmd_exec(args: Dictionary) -> ConsoleResult:
	var requested: String = args[&"file"]
	var path: String = resolve_script_path(requested)
	if not FileAccess.file_exists(path) and not requested.is_absolute_path():
		return ConsoleResult.failure("no such file '%s' in user:// or res://" % requested)
	var loaded: Dictionary = load_script_file(path)
	if not loaded["ok"]:
		return ConsoleResult.failure(loaded["error"])
	var statements: Array[PackedStringArray] = loaded["statements"]
	var result := ConsoleResult.line("exec %s: %d commands" % [path, statements.size()])
	result.inject = statements
	return result


func _cmd_wait(args: Dictionary) -> ConsoleResult:
	var result := ConsoleResult.success()
	result.wait_frames = int(args[&"frames"])
	return result


# Bug reports and software-Vulkan checks in CI-like containers both want a picture of what the renderer drew.
# The timestamp only names the file; it never feeds gameplay.
func _cmd_screenshot(args: Dictionary) -> ConsoleResult:
	if DisplayServer.get_name() == "headless":
		return ConsoleResult.failure("screenshot needs a rendering display (this run is --headless)")
	var path: String = "" if args[&"path"] == null else String(args[&"path"])
	if path.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://screenshots"))
		path = "user://screenshots/shot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return ConsoleResult.failure("no rendered frame to capture yet")
	var err: Error = image.save_png(path)
	if err != OK:
		return ConsoleResult.failure("could not write %s (%s)" % [path, error_string(err)])
	return ConsoleResult.success(PackedStringArray(["saved %s (%dx%d)" % [ProjectSettings.globalize_path(path), image.get_width(),
			image.get_height()]]))


func _cmd_quit(args: Dictionary) -> ConsoleResult:
	var result := ConsoleResult.success()
	result.quit_code = int(args[&"code"])
	return result


func _command_name_list() -> PackedStringArray:
	var out := PackedStringArray()
	for command_name: StringName in registry.command_names():
		out.append(String(command_name))
	return out


func _provider_name_list() -> PackedStringArray:
	var out := PackedStringArray()
	for provider_name: StringName in registry.provider_names():
		out.append(String(provider_name))
	return out


func _unwatch_list() -> PackedStringArray:
	var out: PackedStringArray = _watches.duplicate()
	out.append("all")
	return out


# --- Providers ---------------------------------------------------------------------------------------------------


func _register_providers() -> void:
	if settings != null:
		registry.register_provider(&"settings", settings_vars(settings), settings)
	registry.register_provider(&"debug", ConsoleVars.new({
		&"invulnerable": {
			"get": func() -> bool: return flags.invulnerable,
			"set": func(value: bool) -> void: flags.invulnerable = value,
			"type": TYPE_BOOL, "doc": "Player takes no damage (god); session only, never saved",
		},
	}), self)
	if sim_clock != null:
		var clock: SimClockScript = sim_clock
		registry.register_provider(&"time", ConsoleVars.new({
			&"sim_time_s": {"get": func() -> float: return clock.sim_time_s, "unit": "s"},
			&"warp": {"get": func() -> float: return clock.warp},
			&"timescale": {"get": func() -> float: return Engine.time_scale},
		}), clock)


## The `settings` provider: every SettingsSchema key, typed and ranged, writable and resettable, `*` when unsaved.
static func settings_vars(source: SettingsScript) -> ConsoleVars:
	var schema: SettingsSchema = source.schema
	var entries: Dictionary = {}
	for key: StringName in schema.keys():
		var entry: Dictionary = schema.get_entry(key)
		var spec: Dictionary = {
			"get": func() -> Variant: return source.get_value(key),
			"set": func(value: Variant) -> String: return "" if source.set_value(key, value) == OK else source.get_last_error(),
			"reset": func() -> String: return "" if source.reset(key) == OK else source.get_last_error(),
			"modified": func() -> bool: return source.is_unsaved(key),
			"doc": entry.get("doc", ""),
		}
		match schema.get_type(key):
			TYPE_BOOL:
				spec["type"] = TYPE_BOOL
			TYPE_FLOAT:
				spec["type"] = TYPE_FLOAT
				spec["min"] = entry["min"]
				spec["max"] = entry["max"]
			SettingsSchema.TYPE_ENUM:
				spec["type"] = TYPE_STRING_NAME
				spec["choices"] = entry["choices"]
			TYPE_STRING:
				spec["type"] = TYPE_STRING
		entries[key] = spec
	return ConsoleVars.new(entries)


func _input_vars(with_adapter: bool) -> ConsoleVars:
	var entries: Dictionary = {
		&"pads": {"get": _read_pads, "doc": "Connected pads: name, GUID, trigger rest, raw axes 0-5"},
		&"keyboard_masked": {"get": _read_keyboard_masked,
				"doc": "Key and mouse bindings are ignored (the console is open)"},
	}
	if with_adapter:
		for group: String in ["flight", "combat", "ui"]:
			for field: String in _command_fields(group):
				entries[StringName(field)] = {"get": func() -> Variant: return _last_command_field(group, field),
						"doc": "Last %s command: %s" % [group, field]}
	return ConsoleVars.new(entries)


func _read_pads() -> Array:
	var source: InputSource = _input_source()
	return source.pad_info() if source != null else []


func _read_keyboard_masked() -> bool:
	var source: InputSource = _input_source()
	return source != null and not source.keyboard_mouse_enabled


static func _command_fields(group: String) -> PackedStringArray:
	var sample := PilotCommand.new()
	var fields: Dictionary = {}
	match group:
		"flight":
			fields = sample.flight.to_dict()
		"combat":
			fields = sample.combat.to_dict()
		"ui":
			fields = sample.ui.to_dict()
	var out := PackedStringArray()
	for field: Variant in fields.keys():
		out.append(String(field))
	return out


func _last_command_field(group: String, field: String) -> Variant:
	var adapter: InputAdapter = _input_adapter()
	if adapter == null or adapter.last == null:
		return null
	match group:
		"flight":
			return adapter.last.flight.to_dict().get(field)
		"combat":
			return adapter.last.combat.to_dict().get(field)
		"ui":
			return adapter.last.ui.to_dict().get(field)
	return null
