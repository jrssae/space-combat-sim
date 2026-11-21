extends Node
## Joypads autoload (M8-T22, D88): tells the player and the log which gamepads the game sees, so a pad that is missing
## (off, asleep, in the wrong mode) is noticed at once instead of looking like dead controls. It logs the pads at launch
## and on every hotplug, shows a toast when one connects or disconnects, gives the front end its "no gamepad" notice and
## answers the console (`joypads`, provider `joypads`). Diagnostics only: flight reads pads through `InputSource`.

const SettingsScript := preload("res://src/autoload/settings.gd")
const DebugConsoleScript := preload("res://src/autoload/debug_console.gd")
const LOG_PREFIX: String = "Joypads: "
## Log lines kept for tests and `joypads`' callers.
const MAX_LOGGED: int = 32

## A pad connected or disconnected; the front end redraws its notice.
signal changed

var report: JoypadReport = JoypadReport.new()

# Injection points, read when the node enters the tree (as `Game` has them).
## null: the real pads. In a test run those are left out, so a pad on the desk changes no test.
var devices: JoypadDevices = null
var registry: ConsoleRegistry = null  ## null: the registry of /root/DebugConsole

var _elapsed_s: float = 0.0
var _start_logged: bool = false
var _logged: PackedStringArray = PackedStringArray()
var _toast: JoypadToast = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if registry == null:
		var console: DebugConsoleScript = get_node_or_null(^"/root/DebugConsole") as DebugConsoleScript
		if console != null:
			registry = console.registry
	_toast = JoypadToast.new()
	add_child(_toast)
	var settings: SettingsScript = get_node_or_null(^"/root/Settings") as SettingsScript
	if devices == null and not (settings != null and settings.test_run):
		devices = JoypadDevices.new()
		Input.joy_connection_changed.connect(on_joy_connection_changed)
	if devices != null:
		for id: int in devices.ids():
			on_joy_connection_changed(id, true)
	_register_console()


func _exit_tree() -> void:
	if registry != null:
		registry.unregister_owner(self)


func _process(delta: float) -> void:
	_elapsed_s += delta
	if not _start_logged and _elapsed_s >= JoypadReport.STARTUP_WINDOW_S:
		_start_logged = true
		for line: String in report.start_lines():
			_log(line)


## Godot's hotplug signal; tests call it after changing their `devices`.
func on_joy_connection_changed(device: int, connected: bool) -> void:
	var event: Dictionary = {}
	if connected and devices != null:
		event = report.note_connected(device, devices.pad_name(device), devices.guid(device), devices.known(device), _elapsed_s)
	elif not connected:
		event = report.note_disconnected(device, _elapsed_s)
	if event.is_empty():
		return
	if event["kind"] != JoypadReport.START:
		_log("%s %s" % [event["kind"], JoypadReport.pad_line(event)])
	_toast.show_text(JoypadReport.toast_text(event))
	changed.emit()


## What the front end shows while no pad is connected; "" when one is.
func none_notice() -> String:
	return report.none_notice()


func toast() -> JoypadToast:
	return _toast


## The lines logged so far (without the prefix), oldest first.
func logged() -> PackedStringArray:
	return _logged


func _log(line: String) -> void:
	_logged.append(line)
	if _logged.size() > MAX_LOGGED:
		_logged.remove_at(0)
	print(LOG_PREFIX + line)


func _register_console() -> void:
	if registry == null:
		return
	registry.register_command(ConsoleCommand.new(&"joypads",
			"List the gamepads the game sees (name, GUID, button mapping) and the last connect and disconnect events"),
			func(_args: Dictionary) -> ConsoleResult: return ConsoleResult.success(report.summary_lines()), self)
	registry.register_provider(&"joypads", ConsoleVars.new({
		&"count": {"get": report.count, "doc": "Gamepads connected"},
		&"names": {"get": func() -> String: return _joined("name"), "doc": "Their names, by device id"},
		&"guids": {"get": func() -> String: return _joined("guid"), "doc": "Their SDL GUIDs, by device id"},
		&"unmapped": {"get": report.unmapped_count, "doc": "Connected pads with no known button mapping"},
		&"events": {"get": report.events_seen, "doc": "Connect and disconnect events since launch"},
		&"last_event": {"get": func() -> String: return JoypadReport.event_line(report.last_event()),
				"doc": "The last event: its time since launch, kind and pad"},
		&"notice": {"get": report.none_notice, "doc": "The front end's notice while no pad is connected"},
	}), self)


func _joined(key: String) -> String:
	var parts := PackedStringArray()
	for pad: Dictionary in report.pads():
		parts.append(String(pad[key]))
	return ", ".join(parts)
