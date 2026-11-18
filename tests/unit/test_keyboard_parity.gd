extends GutTest
## Keyboard parity (maintainer, M7-T27): anything the pad can do, the keyboard and mouse can do too. Every action with a pad
## binding has a key or mouse binding in each built-in layout; the auto-track key splits into tap and hold exactly as the pad's
## X does; and the HUD names both (`HOLD X / SHIFT / MOUSE 4`).

const DT: float = 1.0 / 60.0
## Pad bindings the mouse stands in for: the right stick turns the ship, the mouse's motion does the same (`InputAdapter`).
const MOUSE_MOTION: Array[StringName] = [InputAdapter.PITCH_DOWN, InputAdapter.PITCH_UP, InputAdapter.YAW_LEFT,
		InputAdapter.YAW_RIGHT]
const BUILTIN: Array[String] = ["default", "m1_classic"]
## Pad actions whose keyboard side is a twin action with the same behaviour: pad B's target button and keyboard B / Mouse 2 are
## separate actions on one tap-or-hold rule (`InputAdapter.TAP_HOLD`), each on its own timer.
const KEYBOARD_TWIN: Dictionary = {InputAdapter.TARGET_CYCLE: InputAdapter.TARGET_NEXT}

var _source: GodotInputSource = null


func before_all() -> void:
	ControlProfiles.store.default_profile().apply_to_input_map()


func after_each() -> void:
	_release_shift()
	_source = null


func _profile(profile_name: String) -> ControlProfile:
	var loaded: Dictionary = ControlProfiles.store.load_profile(profile_name)
	assert_true(bool(loaded.get("ok", false)), "%s loads: %s" % [profile_name, loaded.get("errors", [])])
	return loaded.get("profile") as ControlProfile


func test_every_pad_action_has_a_key_or_mouse_binding_in_each_layout() -> void:
	for profile_name: String in BUILTIN:
		var profile: ControlProfile = _profile(profile_name)
		if profile == null:
			continue
		for action: StringName in InputAdapter.ACTIONS:
			var descriptors: PackedStringArray = profile.descriptors_for(action)
			var on_pad: bool = false
			var off_pad: bool = false
			for d: String in descriptors:
				on_pad = on_pad or d.begins_with("pad:")
				off_pad = off_pad or d.begins_with("key:") or d.begins_with("mouse:")
			if on_pad and KEYBOARD_TWIN.has(action):
				var twin: StringName = KEYBOARD_TWIN[action]
				assert_true(InputAdapter.TAP_HOLD.has(action) and InputAdapter.TAP_HOLD.has(twin), "%s and %s share one rule" % [action, twin])
				off_pad = false
				for d: String in profile.descriptors_for(twin):
					off_pad = off_pad or d.begins_with("key:") or d.begins_with("mouse:")
				assert_true(off_pad, "%s: %s's keyboard twin %s has a key or mouse button" % [profile_name, action, twin])
			elif on_pad and not MOUSE_MOTION.has(action):
				assert_true(off_pad, "%s: %s is on the pad (%s) but has no key or mouse button" % [profile_name, action,
						", ".join(descriptors)])


func test_the_radial_menus_are_driven_from_the_keyboard_too() -> void:
	for action: StringName in InputAdapter.RADIAL_ACTIONS:
		var key: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			key = key or event is InputEventKey
		assert_true(key, "%s has a key (arrows, Enter, Backspace)" % action)


func test_binding_names_name_the_pad_the_key_and_the_mouse() -> void:
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SHIFT
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_XBUTTON1
	var events: Array[InputEvent] = [pad, key, mouse]
	assert_eq(BindingNames.short(events), "X / SHIFT / MOUSE 4")
	var keys_only: Array[InputEvent] = [key]
	assert_eq(BindingNames.short(keys_only), "SHIFT", "a layout with no pad button names only its key")
	assert_eq(BindingNames.of_action(InputAdapter.AUTOTRACK), "X / SHIFT / MOUSE 4", "the default layout")


# --- the auto-track key through the real input source -----------------------------------------------------------------


func _shift(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SHIFT
	event.keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release_shift() -> void:
	if Input.is_physical_key_pressed(KEY_SHIFT):
		_shift(false)


# Holds Shift for `ticks` samples, then lets go for one; returns how often the interaction fired and the bar's peak.
func _press_shift(adapter: InputAdapter, ticks: int) -> Dictionary:
	var fired: int = 0
	var peak: float = 0.0
	_shift(true)
	for i: int in ticks:
		var cmd: PilotCommand = adapter.sample(_source, DT)
		fired += int(cmd.ui.interact)
		peak = maxf(peak, cmd.ui.interact_progress)
	_shift(false)
	var last: PilotCommand = adapter.sample(_source, DT)
	fired += int(last.ui.interact)
	return {"fired": fired, "peak": peak, "after": last.ui.interact_progress}


func test_the_keyboard_taps_and_holds_like_the_pads_x() -> void:
	_source = GodotInputSource.new()
	_source.keyboard_mouse_enabled = true
	var adapter := InputAdapter.new()
	_shift(true)
	assert_true(_source.is_pressed(InputAdapter.AUTOTRACK), "Shift is the auto-track key")
	_shift(false)
	adapter.interaction_offered = true
	var tap: Dictionary = _press_shift(adapter, 5)
	assert_true(adapter.autotrack_on, "a tap of Shift toggles auto-track, on the release")
	assert_eq(tap["fired"], 0)
	assert_eq(tap["peak"], 0.0, "a tap never shows the bar")
	var hold: Dictionary = _press_shift(adapter, 125)
	assert_eq(hold["fired"], 1, "a 2 s hold of Shift runs the interaction once")
	assert_true(adapter.autotrack_on, "and leaves auto-track as it was")
	assert_gt(hold["peak"], 0.9, "the bar filled")
	var half: Dictionary = _press_shift(adapter, 60)
	assert_eq(half["fired"], 0, "let go halfway, it is cancelled")
	assert_eq(half["after"], 0.0, "and the bar empties")
	adapter.interaction_offered = false
	_press_shift(adapter, 3)
	assert_false(adapter.autotrack_on, "with nothing offered Shift toggles at once, as before")
