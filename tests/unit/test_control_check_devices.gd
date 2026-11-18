extends GutTest
## Every check of `data/checks/controls.json` on the pad and on the keyboard and mouse (M8 AC3, keyboard parity): the check's
## own bindings are pressed as device events, read by the real `GodotInputSource` and `InputAdapter`, and the commands that
## come out drive a stand-in ship whose state the check measures. Nothing here reads `Input` for gameplay: the events only feed
## the input source, as a pad on the desk would.

const DT: float = 1.0 / 60.0
const MAX_TICKS: int = 420
## What the default layout gives no way to do on a device: `target_ahead` is bound to nothing, `target_prev` only to the wheel.
const NO_PAD_WAY: Array[StringName] = [&"target_prev", &"target_ahead"]
const NO_KEYS_WAY: Array[StringName] = [&"target_ahead"]
const MOUSE_BUTTONS: Array[MouseButton] = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1,
		MOUSE_BUTTON_XBUTTON2]


class OnePadSource:
	extends GodotInputSource

	## Past any id a real pad gets (Godot numbers them from 0), so a pad on the desk cannot feed the test.
	const DEVICE: int = 15

	func _pad_ids() -> Array[int]:
		var pads: Array[int] = [DEVICE]
		return pads

	func _pad_guid(_pad: int) -> String:
		return "fakepad0"

	func _pad_name(_pad: int) -> String:
		return "Fake Pad"


## A ship that does what its commands ask, just enough for a check to measure it.
class StandIn:
	extends RefCounted

	var velocity: Vector3 = Vector3.ZERO
	var spin: Vector3 = Vector3.ZERO
	var state: Dictionary = {"assist": true, "camera": "chase", "look_deg": 0.0, "lights": true, "tracking": false, "target": 100,
			"fire_mode": "alternating", "interactions": 0, "wing_order": "engage", "wing_orders": 0, "target_menus": 0}
	## The order the player picks when the comms menu opens.
	var menu_order: String = ""

	func fly(pc: PilotCommand, dt: float) -> void:
		var f: FlightCommand = pc.flight
		var push: Vector3 = Vector3.FORWARD * 30.0 * minf(f.main_left, f.main_right) \
				+ Vector3.BACK * 30.0 * minf(f.retro_left, f.retro_right) \
				+ Vector3.RIGHT * 15.0 * f.strafe.x + Vector3.UP * 15.0 * f.strafe.y
		velocity += push * dt
		if f.brake:
			velocity = velocity.move_toward(Vector3.ZERO, 20.0 * dt)
		spin = Vector3(f.rot.x, -f.rot.y, -f.rot.z) * deg_to_rad(90.0)
		if f.toggle_assist:
			state["assist"] = not bool(state["assist"])
		state["tracking"] = f.autotrack
		var c: CombatCommand = pc.combat
		if c.target_next or c.target_nearest:
			state["target"] = int(state["target"]) + 1
		if c.target_prev:
			state["target"] = int(state["target"]) - 1
		if c.weapon_next:
			state["fire_mode"] = "linked" if state["fire_mode"] == "alternating" else "alternating"
		var u: UiCommand = pc.ui
		if u.toggle_camera:
			state["camera"] = "cockpit" if state["camera"] == "chase" else "chase"
		var looking: bool = u.look_active and (u.look_stick.length() > 0.2 or u.look_mouse_px.length() > 0.0)
		state["look_deg"] = minf(float(state["look_deg"]) + 60.0 * dt, 60.0) if looking else 0.0
		if u.toggle_running_lights:
			state["lights"] = not bool(state["lights"])
		if u.interact:
			state["interactions"] = int(state["interactions"]) + 1
		if u.target_menu_open:
			state["target_menus"] = int(state["target_menus"]) + 1
			state["target"] = 55
		for order: Array in [[u.wing_form, "form"], [u.wing_attack, "attack"], [u.wing_cover, "cover"],
				[u.wing_engage, "engage"], [u.comms_open, menu_order]]:
			if bool(order[0]):
				state["wing_order"] = order[1]
				state["wing_orders"] = int(state["wing_orders"]) + 1

	func sample(pc: PilotCommand) -> ControlCheckSample:
		var out := ControlCheckSample.new()
		out.velocity = velocity
		out.angular_velocity = spin
		out.state = state.duplicate()
		out.events = ControlCheckSample.events_of(pc)
		return out


var book: ControlCheckBook
var source: OnePadSource
var _keys_down: Array[Key] = []


func before_all() -> void:
	ControlProfiles.store.default_profile().apply_to_input_map()
	var made: Dictionary = ControlCheckBook.load_file()
	assert_true(bool(made["ok"]), str(made["error"]))
	book = made["book"]


func before_each() -> void:
	source = OnePadSource.new()
	_release_everything()


func after_each() -> void:
	_release_everything()


# --- device events -----------------------------------------------------------------------------------------------------


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = OnePadSource.DEVICE
	e.axis = axis
	e.axis_value = value
	_send(e)


func _button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = OnePadSource.DEVICE
	e.button_index = button
	e.pressed = pressed
	_send(e)


func _key(key: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = pressed
	_send(e)
	if pressed and not _keys_down.has(key):
		_keys_down.append(key)


func _mouse(button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	_send(e)


func _release_everything() -> void:
	for axis: int in 6:
		_axis(axis as JoyAxis, 0.0)
	for button: int in 15:
		_button(button as JoyButton, false)
	for key: Key in _keys_down:
		_key(key, false)
	_keys_down.clear()
	for button: MouseButton in MOUSE_BUTTONS:
		_mouse(button, false)


# Presses or releases one binding as its device would.
func _set_binding(event: InputEvent, pressed: bool) -> void:
	if event is InputEventJoypadButton:
		_button((event as InputEventJoypadButton).button_index, pressed)
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		_axis(motion.axis, motion.axis_value if pressed else 0.0)
	elif event is InputEventKey:
		_key((event as InputEventKey).physical_keycode, pressed)
	elif event is InputEventMouseButton:
		_mouse((event as InputEventMouseButton).button_index, pressed)


# --- what to press for a check -------------------------------------------------------------------------------------------


static func _on_device(event: InputEvent, pad: bool) -> bool:
	if pad:
		return event is InputEventJoypadButton or event is InputEventJoypadMotion
	return event is InputEventKey or event is InputEventMouseButton


# The check's bindings on one device: for a check that needs all its actions, one per action (none when an action has no
# binding there); for one that needs any, the first action's that has one.
func _bindings(check: ControlCheck, pad: bool) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for action: StringName in check.actions:
		var found: InputEvent = null
		for event: InputEvent in InputMap.action_get_events(action):
			if _on_device(event, pad):
				found = event
				break
		if found != null:
			out.append(found)
			if not check.need_all:
				return out
		elif check.need_all:
			return []
	return out


# What the check's hint names beside its bindings (`pad_extra`, `keys_extra`), done on the device each tick.
func _do_extra(check: ControlCheck, pad: bool, first_tick: bool) -> bool:
	var extra: String = check.pad_extra if pad else check.keys_extra
	match extra:
		"R STICK DIAGONAL":
			_axis(JOY_AXIS_RIGHT_X, 0.75)
			_axis(JOY_AXIS_RIGHT_Y, 0.75)
		"R STICK":
			_axis(JOY_AXIS_RIGHT_X, 1.0)
		"MOUSE":
			source.add_mouse_motion(Vector2(30.0, 30.0))
		"MOUSE WHEEL UP":
			if first_tick:
				source.add_wheel(-1)
		"MOUSE WHEEL DOWN":
			if first_tick:
				source.add_wheel(1)
		_:
			return false
	return true


# The stand-in at the start of a check, set so that one use of the control is what passes it.
func _stand_in(check: ControlCheck) -> StandIn:
	var ship := StandIn.new()
	if check.kind == ControlCheck.BRAKE:
		ship.velocity = Vector3(0.0, 0.0, -50.0)
	for condition: Dictionary in check.when:
		if condition["op"] != &"equals":
			continue
		var value: Variant = condition["value"]
		match condition["field"] as StringName:
			&"wing_order":
				ship.menu_order = str(value)
			&"fire_mode":
				ship.state["fire_mode"] = "alternating" if str(value) == "linked" else "linked"
			_:
				if value is bool:
					ship.state[condition["field"]] = not bool(value)
	return ship


# Runs `check` on one device. Returns "passed", "open" (pressed, never passed) or "no way" (nothing on that device does it).
func _run(check: ControlCheck, pad: bool, press: bool = true) -> String:
	var bindings: Array[InputEvent] = _bindings(check, pad)
	var extra_only: bool = bindings.is_empty()
	var adapter := InputAdapter.new()
	adapter.interaction_offered = check.events.has(ControlCheckSample.INTERACT)
	var ship: StandIn = _stand_in(check)
	var tap_ticks: int = 3 if check.press == &"tap" else MAX_TICKS
	var did_something: bool = not extra_only
	check.begin(ship.sample(adapter.sample(source, DT)))  # the check opens with the hands off, as the instructor asks
	for tick: int in MAX_TICKS:
		if press:
			if tick == 0:
				for event: InputEvent in bindings:
					_set_binding(event, true)
			elif tick == tap_ticks:
				for event: InputEvent in bindings:
					_set_binding(event, false)
			if (extra_only or check.held) and _do_extra(check, pad, tick == 0):
				did_something = true
			if not did_something:
				return "no way"
		var pc: PilotCommand = adapter.sample(source, DT)
		ship.fly(pc, DT)
		if check.observe(ship.sample(pc), DT):
			return "passed"
	return "open"


# --- the table -----------------------------------------------------------------------------------------------------------


func test_every_check_passes_on_the_pad() -> void:
	for id: StringName in book.ids():
		var outcome: String = _run(book.make(id), true)
		_release_everything()
		assert_eq(outcome, "no way" if NO_PAD_WAY.has(id) else "passed", "%s on the pad" % id)


func test_every_check_passes_on_the_keyboard_and_mouse() -> void:
	for id: StringName in book.ids():
		var outcome: String = _run(book.make(id), false)
		_release_everything()
		assert_eq(outcome, "no way" if NO_KEYS_WAY.has(id) else "passed", "%s on the keyboard and mouse" % id)


func test_whatever_the_pad_can_do_the_keyboard_can() -> void:
	for id: StringName in book.ids():
		if not NO_PAD_WAY.has(id):
			assert_false(NO_KEYS_WAY.has(id), "%s: keyboard parity" % id)
	for id: StringName in NO_KEYS_WAY:
		assert_false(ControlHintText.is_bound(book.make(id)), "%s is bound to nothing, so the mission leaves it out" % id)


func test_no_check_passes_with_the_hands_off_the_controls() -> void:
	for id: StringName in book.ids():
		assert_eq(_run(book.make(id), true, false), "open", "%s with nothing pressed" % id)


func test_a_wing_order_passes_from_its_own_key_too() -> void:
	var check: ControlCheck = book.make(&"wing_form")
	var adapter := InputAdapter.new()
	var ship := StandIn.new()
	check.observe(ship.sample(adapter.sample(source, DT)), DT)
	_key(KEY_2, true)
	var pc: PilotCommand = adapter.sample(source, DT)
	ship.fly(pc, DT)
	assert_true(check.observe(ship.sample(pc), DT), "key 2 orders the wing to form up without the menu")
	_key(KEY_2, false)
	var cover: ControlCheck = book.make(&"wing_cover")
	cover.observe(ship.sample(adapter.sample(source, DT)), DT)
	_key(KEY_2, true)
	pc = adapter.sample(source, DT)
	ship.fly(pc, DT)
	assert_false(cover.observe(ship.sample(pc), DT), "the wrong order does not pass the cover check")
