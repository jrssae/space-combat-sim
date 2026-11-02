extends Control
## Placeholder front end (architecture §18, D50): Free flight and Quit, enough to start the game from a menu.
## M5-T02 replaces it with the real menus over the sky.

const GameScript := preload("res://src/autoload/game.gd")

var game: GameScript = null  ## null: /root/Game

@onready var _free_flight: Button = %FreeFlight
@onready var _quit: Button = %Quit


func _ready() -> void:
	if game == null:
		game = get_node_or_null(^"/root/Game") as GameScript
	_free_flight.pressed.connect(_on_free_flight)
	_quit.pressed.connect(_on_quit)
	_free_flight.grab_focus.call_deferred()  # the pad's A starts free flight without pointing first


func _on_free_flight() -> void:
	var problem: String = game.play(GameFlow.make_request(&"free_flight", &"free_flight"))
	if not problem.is_empty():
		push_error("FrontEnd: %s" % problem)


func _on_quit() -> void:
	get_tree().quit()
