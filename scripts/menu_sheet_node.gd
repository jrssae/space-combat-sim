extends Node
## Photographs the start menu's pages (the start screen, New game, Free flight, Settings) and the pause menu's (the list, the quit
## confirm when it exists, Settings) on the real renderer for the maintainer's before/after sheet (M7-T31). Pages are reached with
## the pad's `ui_*` actions, as a player would. Arguments after `--`: out=<dir> tag=<before|after> settle=<frames>.

const FRONT_END: String = "res://src/frontend/front_end.tscn"
const MAIN: String = "res://src/game/main.tscn"

## The window sizes the start screen, New game and the pause list are also photographed at: 16:10, 4K and a narrow one.
const EXTRA_SIZES: Array[Vector2i] = [Vector2i(1920, 1200), Vector2i(3840, 2160), Vector2i(1100, 700)]

var options: Dictionary = {"out": ".", "tag": "after", "settle": "20"}
var _front: FrontEnd = null
var _main: Main = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	await _front_end_pages()
	await _pause_pages()
	get_tree().quit()


func _front_end_pages() -> void:
	_front = (load(FRONT_END) as PackedScene).instantiate() as FrontEnd
	_front.quit_game = func() -> void: pass
	get_tree().root.add_child(_front)
	await _settle()
	await _shot("start")
	await _sized("start")
	await _pad(&"ui_accept")
	await _shot("new_game")
	await _sized("new_game")
	_push_long_description()
	await _settle()
	await _shot("new_game_long")
	await _sized("new_game_long")
	await _pad(&"ui_cancel")  # the made-up page, then New game itself
	await _pad(&"ui_cancel")
	await _pad(&"ui_down")  # the greyed Load game is skipped
	await _pad(&"ui_accept")
	await _shot("free_flight")
	await _pad(&"ui_cancel")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	await _shot("settings")
	_front.queue_free()
	await _settle()


# A made-up New game page whose description is longer than the window, for the box that caps and scrolls.
func _push_long_description() -> void:
	var lines: Array[String] = []
	for i: int in 30:
		lines.append("Briefing line %d: the convoy leaves the station at first light and the wing is to cover it to the gate." % (i + 1))
	var page := ChoiceListScreen.new()
	page.setup("New game", [
		{"id": &"long", "text": "A very long briefing", "info": ObjectivesModel.briefing("A very long briefing", "\n".join(lines))},
		{"id": &"other", "text": "Another mission", "info": ObjectivesModel.briefing("Another mission", "A short one.")},
	])
	page.compact = true
	page.show_pad = false
	_front.frame().push_screen(page)


func _pause_pages() -> void:
	_main = (load(MAIN) as PackedScene).instantiate() as Main
	_main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	_main.waves_auto_start = false
	get_tree().root.add_child(_main)
	await _settle()
	_main.pause_menu.frame().request_source = func() -> Dictionary:
		return GameFlow.make_request(&"free_flight", &"free_flight", true, 1)
	_main.pause_menu.open()
	await _settle()
	await _shot("pause")
	await _sized("pause")
	var page: ChoiceListScreen = _main.pause_menu.frame().current_page() as ChoiceListScreen
	if page.button_of(&"quit_game") != null:
		page.button_of(&"quit_game").grab_focus()
		await _pad(&"ui_accept")
		await _shot("pause_quit_confirm")
		await _pad(&"ui_cancel")
	page.button_of(&"settings").grab_focus()
	await _pad(&"ui_accept")
	await _shot("pause_settings")


# The page on screen again at the other window sizes, then back at the first.
func _sized(page_name: String) -> void:
	var first: Vector2i = get_window().size
	for size: Vector2i in EXTRA_SIZES:
		get_window().size = size
		await _settle()
		await _settle()
		await _shot("%s_%dx%d" % [page_name, size.x, size.y])
	get_window().size = first
	await _settle()


func _pad(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame
	await _settle()


func _settle() -> void:
	for i: int in int(options["settle"]):
		await get_tree().process_frame


func _shot(page_name: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s_%s.png" % [options["out"], options["tag"], page_name]
	image.save_png(path)
	print("[menu_sheet] ", path, " ", image.get_size())
