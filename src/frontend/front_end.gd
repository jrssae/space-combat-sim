class_name FrontEnd
extends Control
## The front end (architecture §18, D57): the Cobra-bay hangar (M7-T09, D77: `HangarBackdrop`, its own lights and a slow dolly
## along the racks; M5's sky with a slow camera drift when the interior is not generated) behind a `MenuFrame` whose root page is the main
## menu (M5-T45: New game, Load game (greyed out until saves exist), Free flight, Settings, Quit). New game (the missions, then
## the sandbox scenes) and Free flight start a run through `Game.play` (the loading screen); Settings opens the shared pages in
## the frame; Quit leaves. Everything is reachable and usable with the pad alone.

const GameScript := preload("res://src/autoload/game.gd")

## The sky's drift (without the hangar): the camera sways about the view that has the nebula in it, never turning to the empty side.
const DRIFT_YAW_DEG: float = 30.0
const DRIFT_YAW_RATE: float = 0.035  # rad/s: one sway in about three minutes
const DRIFT_PITCH_DEG: float = 6.0
const DRIFT_PITCH_RATE: float = 0.021

const MAIN_ENTRIES: Array[Dictionary] = [
	{"id": &"new_game", "text": "New game"},
	{"id": &"load_game", "text": "Load game", "enabled": false},  # until saves exist (M5-T45)
	{"id": &"free_flight", "text": "Free flight"},
	{"id": &"settings", "text": "Settings"},
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
@onready var _backdrop: HangarBackdrop = %Backdrop


func _ready() -> void:
	if game == null:
		game = get_node_or_null(^"/root/Game") as GameScript
	_frame.audio = _audio
	_frame.set_root(_main_menu())
	if game == null:
		push_error("FrontEnd: no Game autoload; nothing can be started")
		_frame.show_message("The game cannot start a run: no Game autoload.")
	_backdrop.environment = $Sky/SpaceEnvironment as SpaceEnvironment
	if _backdrop.load_interior():
		_camera.transform = _backdrop.camera_pose()
	else:
		_camera.basis = drift_basis(0.0)


func _process(delta: float) -> void:
	_elapsed_s += delta
	if _backdrop.is_loaded():
		_camera.transform = _backdrop.advance(delta)
	else:
		_camera.basis = drift_basis(_elapsed_s)


## The hangar behind the menu (M7-T09).
func backdrop() -> HangarBackdrop:
	return _backdrop


## The camera's orientation `elapsed_s` into the drift. Pure, so the sway is tested without a sky.
static func drift_basis(elapsed_s: float) -> Basis:
	var yaw: float = deg_to_rad(DRIFT_YAW_DEG) * sin(elapsed_s * DRIFT_YAW_RATE)
	var pitch: float = deg_to_rad(DRIFT_PITCH_DEG) * sin(elapsed_s * DRIFT_PITCH_RATE)
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func frame() -> MenuFrame:
	return _frame


## A fresh seed for each free flight or mission the menu starts, so its encounters (M5-T17) or its civilian (T30) differ;
## a restart keeps the run's request, and with it the seed.
static func session_seed() -> int:
	return randi_range(1, 2147483647)  # the console's `play` seed range


func _main_menu() -> MenuScreen:
	var page := ChoiceListScreen.new()
	page.setup("SPACE COMBAT SIM", MAIN_ENTRIES)
	page.button_of(&"load_game").tooltip_text = "No saved games yet."
	page.show_pad = false  # only the options on the start screen
	page.show_right = false
	page.chosen.connect(_on_main_chosen)
	return page


func _on_main_chosen(id: StringName) -> void:
	match id:
		&"new_game":
			var entries: Array[Dictionary] = []
			entries.assign(mission_entries.call() if mission_entries.is_valid() else MissionCatalog.entries())
			var page := NewGameSelect.new()
			page.setup_new_game(entries)
			page.chosen.connect(func(picked: StringName) -> void:
				if page.is_mission(picked):
					_start(GameFlow.make_request(&"mission", picked, false, session_seed()))
				else:
					_start(GameFlow.make_request(&"sandbox", picked)))
			_frame.push_screen(page)
		&"free_flight":
			var page := FreeFlightSelect.new()
			page.setup_free_flight()
			page.show_pad = false
			page.show_right = false
			page.start_requested.connect(func(encounters: bool) -> void:
				_start(GameFlow.make_request(&"free_flight", &"free_flight", encounters, session_seed())))
			_frame.push_screen(page)
		&"settings":
			_frame.push_screen(MenuScreens.settings())
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
