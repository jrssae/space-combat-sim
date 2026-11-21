extends GutTest
## The Joypads autoload (M8-T22, D88; AC18) with pads plugged in and out through a fake `JoypadDevices`: the log at launch
## and on hotplug, the toast, the front end's notice, and the `joypads` command and provider.

const JoypadsScript := preload("res://src/autoload/joypads.gd")
const FrontEndScene: PackedScene = preload("res://src/frontend/front_end.tscn")
const NOVA_GUID: String = "03008665373500004010000000010000"


## Pads the test plugs in and out.
class FakeDevices:
	extends JoypadDevices

	var plugged: Dictionary = {}  # id -> {"name", "guid", "known"}

	func ids() -> Array[int]:
		var out: Array[int] = []
		out.assign(plugged.keys())
		return out

	func pad_name(id: int) -> String:
		return String((plugged.get(id, {}) as Dictionary).get("name", ""))

	func guid(id: int) -> String:
		return String((plugged.get(id, {}) as Dictionary).get("guid", ""))

	func known(id: int) -> bool:
		return bool((plugged.get(id, {}) as Dictionary).get("known", false))


var devices: FakeDevices
var registry: ConsoleRegistry
var joypads: JoypadsScript


func before_each() -> void:
	devices = FakeDevices.new()
	registry = ConsoleRegistry.new()


func _boot() -> void:
	joypads = JoypadsScript.new()
	joypads.devices = devices
	joypads.registry = registry
	add_child_autofree(joypads)


func _plug(id: int, pad_name: String = "Generic X-Box pad", known: bool = true) -> void:
	devices.plugged[id] = {"name": pad_name, "guid": NOVA_GUID, "known": known}
	if joypads != null:
		joypads.on_joy_connection_changed(id, true)


# Godot clears the pad's name and GUID before the signal arrives.
func _unplug(id: int) -> void:
	devices.plugged.erase(id)
	joypads.on_joy_connection_changed(id, false)


func _past_launch() -> void:
	joypads._process(JoypadReport.STARTUP_WINDOW_S + 0.1)


func _run(line: String) -> PackedStringArray:
	var results: Array[ConsoleResult] = registry.execute(line)
	assert_eq(results.size(), 1)
	assert_true(results[0].ok, "'%s' runs" % line)
	return results[0].lines


func test_a_pad_present_at_launch_is_logged_once_and_not_announced() -> void:
	_plug(0)
	_boot()
	joypads.on_joy_connection_changed(0, true)  # Godot's own signal for the same pad, a frame later
	assert_eq(joypads.logged().size(), 0, "nothing until launch has settled")
	_past_launch()
	assert_eq(joypads.logged()[0], "1 at start")
	assert_string_contains(joypads.logged()[1], "0: Generic X-Box pad  guid %s  mapping known" % NOVA_GUID)
	_past_launch()
	assert_eq(joypads.logged().size(), 2, "the start-up lines are logged once")
	assert_eq(joypads.toast().text(), "")
	assert_eq(joypads.none_notice(), "")


func test_no_pad_at_launch_is_logged_with_the_way_out() -> void:
	_boot()
	_past_launch()
	assert_eq(joypads.logged().size(), 1)
	assert_string_contains(joypads.logged()[0], "none at start: keyboard and mouse work")
	assert_eq(joypads.none_notice(), JoypadReport.NONE_NOTICE)


func test_a_hotplug_is_logged_announced_and_signalled() -> void:
	_boot()
	_past_launch()
	watch_signals(joypads)
	_plug(0)
	assert_signal_emit_count(joypads, "changed", 1)
	assert_string_contains(joypads.logged()[joypads.logged().size() - 1], "connected 0: Generic X-Box pad")
	assert_eq(joypads.toast().text(), "Gamepad connected: Generic X-Box pad")
	assert_true(joypads.toast().visible)
	assert_eq(joypads.none_notice(), "")


func test_an_unplug_is_announced_with_the_pad_name() -> void:
	_plug(0)
	_boot()
	_past_launch()
	watch_signals(joypads)
	_unplug(0)
	assert_signal_emit_count(joypads, "changed", 1)
	assert_string_contains(joypads.logged()[joypads.logged().size() - 1], "disconnected 0: Generic X-Box pad")
	assert_eq(joypads.toast().text(), "Gamepad disconnected: Generic X-Box pad")
	assert_eq(joypads.none_notice(), JoypadReport.NONE_NOTICE)


func test_the_toast_goes_after_a_few_seconds_even_while_paused() -> void:
	_boot()
	_past_launch()
	_plug(0)
	assert_eq(joypads.toast().process_mode, Node.PROCESS_MODE_ALWAYS)
	joypads.toast()._process(JoypadToast.SHOW_S - 0.5)
	assert_true(joypads.toast().visible)
	joypads.toast()._process(1.0)
	assert_false(joypads.toast().visible)
	assert_eq(joypads.toast().text(), "")


func test_a_pad_without_a_mapping_says_so() -> void:
	_boot()
	_past_launch()
	_plug(1, "Odd Stick", false)
	assert_string_contains(joypads.toast().text(), "no known button mapping")
	assert_eq(registry.read("joypads.unmapped")["value"], 1)


func test_the_joypads_command_lists_pads_mapping_and_events() -> void:
	_boot()
	_past_launch()
	var none: PackedStringArray = _run("joypads")
	assert_eq(none[0], "joypads: none connected")
	assert_string_contains("\n".join(none), "Gamepad not detected")
	_plug(0)
	_unplug(0)
	_plug(0)
	var lines: PackedStringArray = _run("joypads")
	assert_eq(lines[0], "joypads: 1 connected")
	assert_eq(lines[1], "  0: Generic X-Box pad  guid %s  mapping known" % NOVA_GUID)
	assert_eq(lines[2], "last events: 3 of 3")
	assert_string_contains(lines[3], "connected  0: Generic X-Box pad")
	assert_string_contains(lines[4], "disconnected  0: Generic X-Box pad")


func test_the_joypads_provider() -> void:
	_boot()
	_past_launch()
	assert_eq(registry.read("joypads.count")["value"], 0)
	assert_eq(registry.read("joypads.last_event")["value"], "none")
	assert_eq(registry.read("joypads.notice")["value"], JoypadReport.NONE_NOTICE)
	_plug(0)
	_plug(2, "Second Pad")
	assert_eq(registry.read("joypads.count")["value"], 2)
	assert_eq(registry.read("joypads.names")["value"], "Generic X-Box pad, Second Pad")
	assert_eq(registry.read("joypads.guids")["value"], "%s, %s" % [NOVA_GUID, NOVA_GUID])
	assert_eq(registry.read("joypads.events")["value"], 2)
	assert_string_contains(registry.read("joypads.last_event")["value"], "connected  2: Second Pad")
	assert_eq(registry.read("joypads.notice")["value"], "")


func test_leaving_the_tree_takes_the_command_along() -> void:
	_boot()
	assert_true(registry.has_command(&"joypads"))
	remove_child(joypads)
	assert_false(registry.has_command(&"joypads"))
	assert_false(registry.has_provider(&"joypads"))
	add_child(joypads)


func test_the_real_autoload_reads_no_hardware_in_a_test_run() -> void:
	assert_true(Settings.test_run)
	assert_null(Joypads.devices, "a pad on the desk changes no test")
	assert_eq(Joypads.report.count(), 0)
	assert_true(DebugConsole.registry.has_command(&"joypads"))
	assert_true(DebugConsole.registry.has_provider(&"joypads"))


func test_the_front_end_shows_the_notice_only_while_no_pad_is_connected() -> void:
	_boot()
	var game := RecordingGame.new()
	autofree(game)
	var front: FrontEnd = FrontEndScene.instantiate() as FrontEnd
	front.game = game
	front.joypads = joypads
	add_child_autofree(front)
	await wait_process_frames(2)
	assert_eq(front.joypad_notice(), JoypadReport.NONE_NOTICE)
	var label: Label = front.get_node(^"JoypadNotice") as Label
	assert_eq(label.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the notice never takes a click from the menu")
	assert_eq(front.get_viewport().gui_get_focus_owner() == label, false, "nor the focus: the keyboard still drives the menu")
	_plug(0)
	assert_eq(front.joypad_notice(), "")
	assert_false(label.visible)
	_unplug(0)
	assert_eq(front.joypad_notice(), JoypadReport.NONE_NOTICE)
	assert_true(label.visible)


# --- Controller layout (M10-T63) ---------------------------------------------------------------------------------


func test_a_nintendo_pad_sets_the_layout_and_a_manual_pick_wins() -> void:
	var saved: StringName = PadLayout.active
	Settings.reset(&"pad_layout")
	_boot()
	assert_eq(PadLayout.active, PadLayout.XBOX_360, "no pad: the layout the game was built on")
	devices.plugged[0] = {"name": "Nintendo Switch Pro Controller", "guid": "0500d71f7e0500000920000000006803", "known": true}
	joypads.on_joy_connection_changed(0, true)
	assert_eq(joypads.detected_layout(), PadLayout.SWITCH)
	assert_eq(PadLayout.active, PadLayout.SWITCH, "Auto follows the pad")
	assert_true(_run("joypads")[-1].contains("Auto (detected: Nintendo Switch)"))
	Settings.set_value(&"pad_layout", &"playstation")
	assert_eq(PadLayout.active, PadLayout.PLAYSTATION, "a manual pick overrides the guess")
	Settings.reset(&"pad_layout")
	_unplug(0)
	assert_eq(PadLayout.active, PadLayout.XBOX_360)
	PadLayout.active = saved
