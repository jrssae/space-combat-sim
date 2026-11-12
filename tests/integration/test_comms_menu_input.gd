extends GutTest
## AC28 on the real main scene (architecture §18.22, M5-T46): D-pad Right opens the comms menu on the radial framework and
## pauses the game; the right stick points, A sends the order through `WingDirector` once the game runs again, B backs out,
## D-pad Right closes it; while it is open the D-pad's flight actions and the target button do nothing, and nothing that was
## held fires on the tick it closes.

const UP := 0.0
const RIGHT := 90.0
const DOWN := 180.0
const LEFT := 270.0

var main: Main
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 1  # a hostile to select, so ATTACK MY TARGET is not refused
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func test_dpad_right_opens_the_menu_with_the_wing_orders_and_pauses_the_game() -> void:
	await _press(InputAdapter.COMMS_MENU)
	assert_true(main.comms.is_open())
	assert_true(get_tree().paused, "the game is paused while it is open")
	assert_eq(main.comms.menu.page_title(), "WING ORDERS")
	assert_true(_read("comms_menu.open"))
	assert_eq(_read("comms_menu.entries"), PackedStringArray(["attack", "form on me", "engage", "cover me"]))
	assert_true(main.comms.view.visible)


func test_the_stick_points_and_a_sends_each_of_the_four_orders_through_the_wing_director() -> void:
	var expected: Array[int] = [AiContext.Order.ATTACK_MY_TARGET, AiContext.Order.FORM_ON_ME, AiContext.Order.ENGAGE_AT_WILL,
			AiContext.Order.COVER_ME]
	var slices: Array[float] = [UP, RIGHT, DOWN, LEFT]
	var wing: Wing = main.wings.player_wing()
	main.wings.give_order(AiContext.Order.COVER_ME)
	for i: int in 4:
		await _press(InputAdapter.COMMS_MENU)
		assert_true(main.comms.is_open(), "open %d" % i)
		wing.order = AiContext.Order.COVER_ME if i != 3 else AiContext.Order.FORM_ON_ME
		var lines: Array[String] = []
		var record := func(line: String) -> void: lines.append(line)
		main.wings.acknowledged.connect(record)
		await _point(slices[i])
		assert_eq(main.comms.menu.radial.highlight(), i, "the stick lit slice %d" % i)
		assert_true(get_tree().paused, "nothing is sent while it is only pointed at")
		await _press(InputAdapter.RADIAL_SELECT)
		main.wings.acknowledged.disconnect(record)
		assert_false(main.comms.is_open(), "a pick closes it")
		assert_false(get_tree().paused, "and the game resumes")
		assert_eq(lines.size(), 1, "slot %d: one line, an order or its refusal" % i)
		if i > 0:  # ATTACK MY TARGET is refused with no hostile selected, as on key 1
			assert_eq(wing.order, expected[i], "slot %d" % i)
		else:
			assert_eq(wing.order, AiContext.Order.COVER_ME, "slot 0: refused, the order is unchanged")
		assert_eq(main.comms.menu.closed_by(), &"pick")


func test_b_closes_it_without_giving_an_order_or_targeting() -> void:
	await _press(InputAdapter.COMMS_MENU)
	var order_before: int = main.wings.player_wing().order
	await _press(InputAdapter.RADIAL_BACK)
	assert_false(main.comms.is_open())
	assert_false(get_tree().paused)
	assert_eq(main.comms.menu.closed_by(), &"back")
	assert_eq(main.comms.menu.picks(), 0)
	assert_eq(main.wings.player_wing().order, order_before)


func test_the_pad_b_that_closes_it_taps_no_target() -> void:
	await _press(InputAdapter.COMMS_MENU)
	source.hold(InputAdapter.RADIAL_BACK)
	source.hold(InputAdapter.TARGET_CYCLE)  # pad B is both buttons
	await _ticks(3)
	source.release(InputAdapter.TARGET_CYCLE)
	source.release(InputAdapter.RADIAL_BACK)
	await _ticks(3)
	assert_false(main.comms.is_open())
	assert_false(main.ship.targeting.system.has_selection(), "the closing press did not select a target")


func test_dpad_right_again_closes_it_and_the_opening_press_does_not() -> void:
	source.hold(InputAdapter.COMMS_MENU)
	await _ticks(10)
	assert_true(main.comms.is_open(), "held through the open: still open")
	source.release(InputAdapter.COMMS_MENU)
	await _ticks(2)
	assert_true(main.comms.is_open())
	await _press(InputAdapter.COMMS_MENU)
	assert_false(main.comms.is_open(), "a second press closes it")
	assert_eq(main.comms.menu.closed_by(), &"close")
	assert_false(get_tree().paused)


func test_it_has_no_timeout() -> void:
	await _press(InputAdapter.COMMS_MENU)
	await _ticks(60 * 6)
	assert_true(main.comms.is_open(), "the game is paused, so there is nothing to time out")


func test_the_dpad_and_flight_buttons_do_nothing_while_it_is_open() -> void:
	var assist: bool = main.ship.assist_on
	var lit: bool = main.ship.running_lights
	await _press(InputAdapter.COMMS_MENU)
	for action: StringName in [InputAdapter.TOGGLE_ASSIST, InputAdapter.WEAPON_NEXT, InputAdapter.TOGGLE_RUNNING_LIGHTS,
			InputAdapter.TARGET_CYCLE, InputAdapter.TARGET_NEXT]:
		await _press(action)
	assert_true(main.comms.is_open(), "none of them picks or closes")
	assert_eq(main.comms.menu.picks(), 0)
	assert_eq(main.ship.assist_on, assist)
	assert_eq(main.ship.running_lights, lit)
	assert_false(main.ship.targeting.system.has_selection())


func test_a_button_held_as_it_closes_fires_nothing_afterwards() -> void:
	var assist: bool = main.ship.assist_on
	await _press(InputAdapter.COMMS_MENU)
	source.hold(InputAdapter.TOGGLE_ASSIST)
	source.hold(InputAdapter.RADIAL_SELECT)
	await _ticks(2)
	source.release(InputAdapter.RADIAL_SELECT)
	await _ticks(3)
	assert_false(main.comms.is_open())
	source.release(InputAdapter.TOGGLE_ASSIST)
	await _ticks(3)
	assert_eq(main.ship.assist_on, assist, "D-pad Up held through the close toggles nothing")


func test_lights_toggle_when_the_menu_is_closed() -> void:
	var lit: bool = main.ship.running_lights
	await _press(InputAdapter.TOGGLE_RUNNING_LIGHTS)
	assert_ne(main.ship.running_lights, lit, "closed: D-pad Left toggles the lights")


func test_start_hands_over_to_the_pause_menu() -> void:
	await _press(InputAdapter.COMMS_MENU)
	await _press(InputAdapter.PAUSE)
	assert_false(main.comms.is_open())
	assert_eq(main.comms.menu.closed_by(), &"pause")
	assert_true(main.pause_menu.is_open())
	main.pause_menu.close()
	assert_false(get_tree().paused)


func test_the_console_drives_it() -> void:
	assert_true(_run("commsmenu open").ok)
	assert_true(main.comms.is_open())
	assert_false(_run("commsmenu open").ok, "not twice")
	assert_true(_run("commsmenu highlight \"cover me\"").ok)
	assert_eq(_read("comms_menu.highlight"), "COVER ME")
	var wing: Wing = main.wings.player_wing()
	assert_true(_run("commsmenu pick 1").ok)
	await _ticks(2)
	assert_eq(wing.order, AiContext.Order.FORM_ON_ME)
	assert_eq(_read("comms_menu.last_pick"), "FORM ON ME")
	assert_false(main.comms.is_open())
	assert_false(_run("commsmenu back").ok, "closed: nothing to go back from")


func test_the_pause_command_refuses_while_it_is_open() -> void:
	assert_true(_run("commsmenu open").ok)
	assert_false(_run("pause").ok)
	assert_true(_run("commsmenu close").ok)


func test_the_ring_is_the_target_menus_size_and_side_and_the_highlight_follows_the_stick() -> void:
	await _press(InputAdapter.COMMS_MENU)
	await _point(RIGHT)
	await wait_process_frames(3)
	var view: RadialMenuView = main.comms.view
	var target_view: RadialMenuView = main.target_menu.view
	var size: Vector2 = get_viewport().get_visible_rect().size
	assert_gt(view.draws, 0)
	assert_eq(view.layer, target_view.layer, "the same layer as the target menu")
	assert_eq(view.drawn_labels, ["ATTACK", "FORM ON ME", "ENGAGE", "COVER ME"] as Array[String], "the entries sit on the ring")
	assert_eq(view.drawn_heading, "WING ORDERS")
	assert_almost_eq(view.drawn_radius, RadialLayout.outer_radius(size), 0.5, "as big as the target menu")
	assert_almost_eq(view.drawn_centre.y, size.y * 0.5, 1.0, "vertically centred")
	assert_eq(view.drawn_centre, RadialLayout.centre(size, false), "at the target menu's side")
	assert_eq(main.comms.menu.radial.highlight(), 1, "the stick lit FORM ON ME")
	assert_gt(view.focus_amount(), 0.0, "the focus pull is on")
	await _point(LEFT)
	assert_eq(main.comms.menu.radial.highlight(), 3)


func _press(action: StringName) -> void:
	source.hold(action, 1.0)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


# Points the menu's stick `deg` clockwise from straight up for two ticks, then lets it centre.
func _point(deg: float) -> void:
	var v := Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg)))
	source.hold(InputAdapter.RADIAL_RIGHT, maxf(v.x, 0.0))
	source.hold(InputAdapter.RADIAL_LEFT, maxf(-v.x, 0.0))
	source.hold(InputAdapter.RADIAL_UP, maxf(v.y, 0.0))
	source.hold(InputAdapter.RADIAL_DOWN, maxf(-v.y, 0.0))
	await _ticks(2)
	for action: StringName in [InputAdapter.RADIAL_RIGHT, InputAdapter.RADIAL_LEFT, InputAdapter.RADIAL_UP, InputAdapter.RADIAL_DOWN]:
		source.release(action)
	await _ticks(1)


func _ticks(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _read(path: String) -> Variant:
	var read: Dictionary = DebugConsole.registry.read(path)
	assert_true(read["ok"], "%s: %s" % [path, read["error"]])
	return read["value"]


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]
