class_name Boot
extends Node
## The project's main scene (architecture §18, D50). It shows nothing: at start it hands the command line to `Game`,
## which replaces it with the front end or, for a scripted run, with Main.

const GameScript := preload("res://src/autoload/game.gd")

# What the routing reads, once. Tests set them before the node enters the tree.
var engine_args: PackedStringArray = OS.get_cmdline_args()
var user_args: PackedStringArray = OS.get_cmdline_user_args()
var headless: bool = DisplayServer.get_name() == "headless"
var game: GameScript = null  ## null: /root/Game


func _ready() -> void:
	if game == null:
		game = get_node_or_null(^"/root/Game") as GameScript
	if game == null:
		push_error("Boot: no Game autoload; nothing to start")
		return
	game.boot(engine_args, user_args, headless)
