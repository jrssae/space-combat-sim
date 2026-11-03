class_name PauseMenu
extends CanvasLayer
## The pause menu (architecture §18, D57, Q15): Start (the `pause` action) in flight opens a `MenuFrame` over the game with
## Resume, Restart, Settings, Controls and Quit to menu. The world pauses while it is open; the menu itself keeps running.
##
## `Main` hands it the pause action's edge (`on_pause_action`): it opens the menu, goes back one page, or at the root resumes.
## Esc is that same action, so the pages ignore the key themselves and one press never counts twice.

const GameScript := preload("res://src/autoload/game.gd")

signal opened
signal resumed

const ENTRIES: Array[Dictionary] = [
	{"id": &"resume", "text": "Resume"},
	{"id": &"restart", "text": "Restart"},
	{"id": &"settings", "text": "Settings"},
	{"id": &"controls", "text": "Controls"},
	{"id": &"quit", "text": "Quit to menu"},
]

var game: GameScript = null  ## null: /root/Game
## Plays the menu sounds. Set by `Main` to its `AudioDirector`.
var audio: AudioDirector = null
## A Callable returning the running mission's objectives (`ObjectivesModel`); the mission core plugs its book in here.
var objectives_source: Callable = Callable()

var _open: bool = false

@onready var _frame: MenuFrame = %Frame


func _ready() -> void:
	visible = false
	if game == null:
		game = get_node_or_null(^"/root/Game") as GameScript
	_frame.closed.connect(close)
	_frame.request_source = func() -> Dictionary: return game.flow.request if game != null else {}
	DebugConsole.registry.register_provider(&"pause_menu", ConsoleVars.new({
		&"open": {"get": func() -> bool: return _open, "doc": "The pause menu is showing"},
		&"page": {"get": func() -> String: return _frame.current_page().title if _open and _frame.current_page() != null else "",
				"doc": "The title of the page on top: PAUSED, Settings or Controls"},
		&"depth": {"get": func() -> int: return _frame.depth() if _open else 0, "doc": "Pages open (1 is the pause list)"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _open and get_tree() != null:
		get_tree().paused = false


func is_open() -> bool:
	return _open


func frame() -> MenuFrame:
	return _frame


func open() -> void:
	if _open:
		return
	_open = true
	_frame.audio = audio
	_frame.objectives_source = objectives_source
	_frame.set_root(_list_page())
	visible = true
	get_tree().paused = true
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	resumed.emit()


## The pause action's edge: open the menu, or step back out of it (a page, then the menu).
func on_pause_action() -> void:
	if _open:
		_frame.go_back()
	else:
		open()


func _list_page() -> MenuScreen:
	var page := ChoiceListScreen.new()
	page.setup("PAUSED", ENTRIES)
	page.cancel_ignores_keys = true
	page.chosen.connect(_on_chosen)
	return page


func _on_chosen(id: StringName) -> void:
	match id:
		&"resume":
			close()
		&"restart":
			_ask_game(func() -> String: return game.restart())
		&"settings":
			_push(MenuScreens.settings())
		&"controls":
			_push(MenuScreens.controls())
		&"quit":
			if game != null:
				game.show_front_end()


func _push(page: MenuScreen) -> void:
	page.cancel_ignores_keys = true
	_frame.push_screen(page)


# Runs a Game call that answers with why it was refused, and shows that.
func _ask_game(call: Callable) -> void:
	if game == null:
		_frame.show_message("There is no Game to restart with.")
		return
	var problem: String = call.call()
	if not problem.is_empty():
		_frame.show_message(problem)
