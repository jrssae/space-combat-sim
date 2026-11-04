extends GutTest
## AC7 on the real main scene (architecture §18 D54, M5-T07): D-pad Right (the `comms_menu` action, as the input source reports
## it) opens the menu, the four directions give the four wing orders through `WingDirector`, B or 4 s of game time close it, and
## while it is open assist, next weapon, lights and the target button do nothing. The pause menu stops its timer.

const DT: float = 1.0 / 60.0

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


func test_dpad_right_opens_the_menu_with_the_wing_orders_page() -> void:
	await _press(InputAdapter.COMMS_MENU)
	assert_true(main.comms_menu.is_open())
	assert_eq(main.comms_menu.page_title(), "WING ORDERS")
	assert_true(_read("comms_menu.open"))
	assert_true(main.adapter.comms_open)


func test_the_four_directions_give_the_four_orders_through_the_wing_director() -> void:
	var expected: Array[int] = [AiContext.Order.ATTACK_MY_TARGET, AiContext.Order.FORM_ON_ME, AiContext.Order.ENGAGE_AT_WILL,
			AiContext.Order.COVER_ME]
	# Up, right, down, left: assist, comms, next weapon, lights.
	var pads: Array[StringName] = [InputAdapter.TOGGLE_ASSIST, InputAdapter.COMMS_MENU, InputAdapter.WEAPON_NEXT,
			InputAdapter.TOGGLE_RUNNING_LIGHTS]
	var wing: Wing = main.wings.player_wing()
	for i: int in 4:
		await _press(InputAdapter.COMMS_MENU)  # open
		assert_true(main.comms_menu.is_open(), "open %d" % i)
		wing.order = AiContext.Order.COVER_ME if i != 3 else AiContext.Order.FORM_ON_ME
		var lines: Array[String] = []
		var record := func(line: String) -> void: lines.append(line)
		main.wings.acknowledged.connect(record)
		await _press(pads[i])
		main.wings.acknowledged.disconnect(record)
		assert_eq(lines.size(), 1, "slot %d: one line, an order or its refusal" % i)
		if i > 0:  # ATTACK MY TARGET is refused with no hostile selected, as on key 1
			assert_eq(wing.order, expected[i], "slot %d" % i)
		else:
			assert_eq(wing.order, AiContext.Order.COVER_ME, "slot 0: refused, the order is unchanged")
		assert_false(main.comms_menu.is_open(), "a pick closes the menu")
		assert_eq(main.comms_menu.closed_by, &"pick")


func test_b_closes_it_without_cycling_targets_or_giving_an_order() -> void:
	await _press(InputAdapter.COMMS_MENU)
	assert_true(main.comms_menu.is_open())
	var order_before: int = main.wings.player_wing().order
	await _press(InputAdapter.TARGET_CYCLE)
	assert_false(main.comms_menu.is_open(), "B closes it")
	assert_eq(main.comms_menu.closed_by, &"close")
	assert_eq(main.comms_menu.picks, 0)
	assert_eq(main.wings.player_wing().order, order_before)
	assert_false(main.ship.targeting.system.has_selection(), "the tap did not select a target")


func test_assist_and_next_weapon_are_picks_not_toggles_while_it_is_open() -> void:
	var assist: bool = main.ship.assist_on
	var weapon: Variant = main.combatant.cannon.mode if "mode" in main.combatant.cannon else null
	await _press(InputAdapter.COMMS_MENU)
	await _press(InputAdapter.TOGGLE_ASSIST)
	assert_eq(main.ship.assist_on, assist, "D-pad Up picked ATTACK MY TARGET instead")
	await _press(InputAdapter.COMMS_MENU)
	await _press(InputAdapter.WEAPON_NEXT)
	assert_eq(main.comms_menu.picks, 2)
	await _press(InputAdapter.TOGGLE_ASSIST)  # closed again: it toggles
	assert_ne(main.ship.assist_on, assist, "closed: D-pad Up toggles assist")
	if weapon != null:
		assert_eq(main.combatant.cannon.mode, weapon)


func test_it_closes_itself_after_four_seconds_of_game_time() -> void:
	await _press(InputAdapter.COMMS_MENU)
	assert_true(main.comms_menu.is_open())
	await _ticks(60 * 3)
	assert_true(main.comms_menu.is_open(), "still open at about 3 s")
	await _ticks(60 * 2)
	assert_false(main.comms_menu.is_open())
	assert_eq(main.comms_menu.closed_by, &"timeout")


func test_the_pause_menu_stops_the_timer() -> void:
	await _press(InputAdapter.COMMS_MENU)
	await _ticks(60)
	var left: float = main.comms_menu.remaining_s()
	assert_lt(left, CommsMenu.CLOSE_S)
	main.pause_menu.on_pause_action()
	await _ticks(60 * 6)
	assert_true(main.pause_menu.is_open())
	assert_almost_eq(main.comms_menu.remaining_s(), left, 1e-6, "no time passes behind the pause menu")


func test_lights_toggle_when_the_menu_is_closed_and_not_when_it_is_open() -> void:
	var lit: bool = main.ship.running_lights
	await _press(InputAdapter.TOGGLE_RUNNING_LIGHTS)
	assert_ne(main.ship.running_lights, lit, "closed: D-pad Left toggles the lights")
	await _press(InputAdapter.COMMS_MENU)
	var lit_now: bool = main.ship.running_lights
	await _press(InputAdapter.TOGGLE_RUNNING_LIGHTS)  # open: picks "cover me", does not toggle
	assert_eq(main.ship.running_lights, lit_now, "open: the lights are untouched")


func _press(action: StringName) -> void:
	source.hold(action, 1.0)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


func _ticks(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _read(path: String) -> Variant:
	var read: Dictionary = DebugConsole.registry.read(path)
	assert_true(read["ok"], "%s: %s" % [path, read["error"]])
	return read["value"]
