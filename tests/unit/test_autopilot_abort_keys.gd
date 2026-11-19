extends GutTest
## Keyboard parity for the autopilot's abort (M8-T32): Shift and Mouse 4, the keyboard's and mouse's X, hold to abort exactly as the
## pad's X does (the data's 1 s), half a hold does nothing, and a tap toggles no auto-track while the controls are held.

const DT: float = 1.0 / 60.0

var _source: GodotInputSource = null


func before_all() -> void:
	ControlProfiles.store.default_profile().apply_to_input_map()


func after_each() -> void:
	_key(false)
	_mouse4(false)
	_source = null


func _adapter() -> InputAdapter:
	_source = GodotInputSource.new()
	var adapter := InputAdapter.new()
	adapter.interaction_offered = true  # an autopilot flies: X is its abort's hold
	adapter.hold.hold_s = AutopilotAbort.hold_s()
	adapter.taps_blocked = true
	return adapter


func _key(pressed: bool) -> void:
	if not pressed and not Input.is_physical_key_pressed(KEY_SHIFT):
		return
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SHIFT
	event.keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mouse4(pressed: bool) -> void:
	if not pressed and not Input.is_mouse_button_pressed(MOUSE_BUTTON_XBUTTON1):
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_XBUTTON1
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# Holds the button for `ticks` samples, then lets go for one: how often the hold fired.
func _press(adapter: InputAdapter, press: Callable, ticks: int) -> int:
	var fired: int = 0
	press.call(true)
	for i: int in ticks:
		fired += int(adapter.sample(_source, DT).ui.interact)
	press.call(false)
	fired += int(adapter.sample(_source, DT).ui.interact)
	return fired


func test_the_hold_time_is_data() -> void:
	assert_almost_eq(AutopilotAbort.hold_s(), 1.0, 1e-6, "data/controls/autopilot_abort.json: the maintainer's 1 s")


func test_shift_and_mouse_4_abort_on_a_full_hold_only() -> void:
	for button: Array in [["Shift", _key], ["Mouse 4", _mouse4]]:
		var adapter: InputAdapter = _adapter()
		assert_eq(_press(adapter, button[1], roundi(0.5 / DT)), 0, "%s held half a second: nothing" % button[0])
		assert_eq(_press(adapter, button[1], roundi(1.05 / DT)), 1, "%s held a second: the abort, once" % button[0])
		assert_eq(_press(adapter, button[1], 3), 0, "%s tapped: nothing" % button[0])
		assert_false(adapter.autotrack_on, "%s: no auto-track toggled while the controls are held" % button[0])


func test_the_prompt_names_the_keys() -> void:
	assert_eq(AutopilotAbort.prompt_text(BindingNames.of_action(InputAdapter.AUTOTRACK)), "HOLD X / SHIFT / MOUSE 4: ABORT")
