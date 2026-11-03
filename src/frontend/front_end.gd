class_name FrontEnd
extends Control
## The front end (architecture §18, D57): the sky with a slow camera drift behind a `MenuFrame` whose root page is the main
## menu. Missions, Free flight and Sandbox start a run through `Game.play` (the loading screen); Settings and Controls open
## the shared pages in the frame; Quit leaves. Everything is reachable and usable with the pad alone.

const GameScript := preload("res://src/autoload/game.gd")

## The drift: the camera sways about the view that has the nebula in it, never turning to the empty side of the sky.
const DRIFT_YAW_DEG: float = 30.0
const DRIFT_YAW_RATE: float = 0.035  # rad/s: one sway in about three minutes
const DRIFT_PITCH_DEG: float = 6.0
const DRIFT_PITCH_RATE: float = 0.021

const MAIN_ENTRIES: Array[Dictionary] = [
	{"id": &"missions", "text": "Missions"},
	{"id": &"free_flight", "text": "Free flight"},
	{"id": &"sandbox", "text": "Sandbox"},
	{"id": &"settings", "text": "Settings"},
	{"id": &"controls", "text": "Controls"},
	{"id": &"quit", "text": "Quit"},
]

var game: GameScript = null  ## null: /root/Game
## A Callable returning the missions to list (`MissionCatalog.entries`). Unset: the scenarios in `data/scenarios/`.
var mission_entries: Callable = Callable()
## Called by Quit. Unset: quits the game.
var quit_game: Callable = Callable()

var _elapsed_s: float = 0.0

@onready var _frame: MenuFrame = %Frame
@onready var _camera: Camera3D = %Camera
@onready var _audio: AudioDirector = %Audio


func _ready() -> void:
	if game == null:
		game = get_node_or_null(^"/root/Game") as GameScript
	_frame.audio = _audio
	_frame.set_root(_main_menu())
	if game == null:
		push_error("FrontEnd: no Game autoload; nothing can be started")
		_frame.show_message("The game cannot start a run: no Game autoload.")
	_camera.basis = drift_basis(0.0)


func _process(delta: float) -> void:
	_elapsed_s += delta
	_camera.basis = drift_basis(_elapsed_s)


## The camera's orientation `elapsed_s` into the drift. Pure, so the sway is tested without a sky.
static func drift_basis(elapsed_s: float) -> Basis:
	var yaw: float = deg_to_rad(DRIFT_YAW_DEG) * sin(elapsed_s * DRIFT_YAW_RATE)
	var pitch: float = deg_to_rad(DRIFT_PITCH_DEG) * sin(elapsed_s * DRIFT_PITCH_RATE)
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func frame() -> MenuFrame:
	return _frame


func _main_menu() -> MenuScreen:
	var page := ChoiceListScreen.new()
	page.setup("SPACE COMBAT SIM", MAIN_ENTRIES)
	page.chosen.connect(_on_main_chosen)
	return page


func _on_main_chosen(id: StringName) -> void:
	match id:
		&"missions":
			var entries: Array[Dictionary] = []
			entries.assign(mission_entries.call() if mission_entries.is_valid() else MissionCatalog.entries())
			var page := MissionSelect.new()
			page.setup_missions(entries)
			page.chosen.connect(func(mission_id: StringName) -> void: _start(GameFlow.make_request(&"mission", mission_id)))
			_frame.push_screen(page)
		&"free_flight":
			var page := FreeFlightSelect.new()
			page.setup_free_flight()
			page.start_requested.connect(func(encounters: bool) -> void:
				_start(GameFlow.make_request(&"free_flight", &"free_flight", encounters)))
			_frame.push_screen(page)
		&"sandbox":
			var page := SandboxSelect.new()
			page.setup_sandbox()
			page.chosen.connect(func(scenario_id: StringName) -> void: _start(GameFlow.make_request(&"sandbox", scenario_id)))
			_frame.push_screen(page)
		&"settings":
			_frame.push_screen(MenuScreens.settings())
		&"controls":
			_frame.push_screen(MenuScreens.controls())
		&"quit":
			if quit_game.is_valid():
				quit_game.call()
			else:
				get_tree().quit()


func _start(request: Dictionary) -> void:
	if game == null:
		return
	var problem: String = game.play(request)
	if not problem.is_empty():
		_frame.show_message(problem)
