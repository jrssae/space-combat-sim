extends TestSteps
## The pause menu's Quit to desktop (M7-T31): a yes/no page first, reachable with the pad alone, and only Yes leaves the game.
## `quit_game` is injected, so the test never quits.

var main: Main
var game: RecordingGame
var quits: int = 0


func before_each() -> void:
	get_tree().paused = false
	game = RecordingGame.new()
	autofree(game)
	quits = 0
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.waves_auto_start = false
	main.raider_pool_size = 1
	add_child_autofree(main)
	main.pause_menu.game = game
	main.pause_menu.quit_game = func() -> void: quits += 1
	await _ticks(2)


func after_each() -> void:
	get_tree().paused = false


func _pad(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame


func _frame() -> MenuFrame:
	return main.pause_menu.frame()


func _focused_text() -> String:
	var focused: Control = _frame().current_page().focused_option()
	return (focused as Button).text if focused is Button else ""


# The pad alone: open the menu, walk to Quit to desktop and press A.
func _open_the_question() -> void:
	main.pause_menu.open()
	await get_tree().process_frame
	for i: int in 4:
		await _pad(&"ui_down")
	assert_eq(_focused_text(), "Quit to desktop")
	await _pad(&"ui_accept")


func test_quit_to_desktop_asks_first() -> void:
	await _open_the_question()
	assert_eq(quits, 0, "nothing quits on the first press")
	assert_true(_frame().current_page() is ConfirmScreen)
	assert_eq(_frame().current_page().title, "Quit to desktop?")
	assert_eq(_frame().depth(), 2)
	assert_true(main.pause_menu.is_open())


func test_the_question_starts_on_no() -> void:
	await _open_the_question()
	assert_eq(_focused_text(), "No", "a second press of A must not quit")
	await _pad(&"ui_accept")
	assert_eq(quits, 0)
	assert_eq(_frame().depth(), 1, "No goes back to the list")


func test_yes_quits() -> void:
	await _open_the_question()
	await _pad(&"ui_down")
	assert_eq(_focused_text(), "Yes")
	await _pad(&"ui_accept")
	assert_eq(quits, 1)


func test_b_cancels_the_question() -> void:
	await _open_the_question()
	await _pad(&"ui_cancel")
	assert_eq(quits, 0)
	assert_eq(_frame().depth(), 1)
	assert_eq(_focused_text(), "Quit to desktop", "the list keeps the focus where it was")
	assert_true(main.pause_menu.is_open())


func test_the_question_hides_the_pad_and_objectives() -> void:
	await _open_the_question()
	assert_false(_frame().pad_diagram().is_visible_in_tree())
	assert_false(_frame().objectives_panel().is_visible_in_tree())
