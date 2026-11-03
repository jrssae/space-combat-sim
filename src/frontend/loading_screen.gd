class_name LoadingScreen
extends Control
## Loading screen (architecture §18, D50): shown while Main's scene loads on a worker thread, then hands the loaded
## scene to `Game`, which builds Main behind this screen.

const GameScript := preload("res://src/autoload/game.gd")

## Frames this screen is drawn before loading starts, so everything that follows happens behind it.
const FRAMES_BEFORE_LOADING: int = 2

var game: GameScript = null  ## null: /root/Game

var _path: String = ""
var _frames_shown: int = 0
var _loading: bool = false
var _collected: bool = false  # the threaded request has been taken (or has failed and been collected)
var _progress: Array = []
## The scene's own scripts, held so they stay compiled while the worker thread loads the rest.
var _scripts: Array[Resource] = []

@onready var _scenario_label: Label = %Scenario
@onready var _bar: ProgressBar = %Progress


func _ready() -> void:
	if game == null:
		game = get_node_or_null(^"/root/Game") as GameScript
	if game == null:
		push_error("LoadingScreen: no Game autoload")
		set_process(false)
		return
	_scenario_label.text = String(game.flow.request.get("scenario_id", "")).replace("_", " ").to_upper()
	_path = game.main_scene_path


func _exit_tree() -> void:
	# Leaving mid-load: a request nobody takes keeps its resource (and its thread) alive to the end of the run.
	if _loading and not _collected:
		_collect()


func _process(_delta: float) -> void:
	_frames_shown += 1
	if not _loading:
		if _frames_shown >= FRAMES_BEFORE_LOADING:
			_start_loading()
		return
	match ResourceLoader.load_threaded_get_status(_path, _progress):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_bar.value = float(_progress[0]) if not _progress.is_empty() else 0.0
		ResourceLoader.THREAD_LOAD_LOADED:
			_bar.value = 1.0
			set_process(false)
			game.finish_loading(_collect() as PackedScene)
		ResourceLoader.THREAD_LOAD_FAILED:
			set_process(false)
			_collect()
			game.fail_loading("could not load %s" % _path)
		_:
			set_process(false)
			game.fail_loading("could not load %s" % _path)


# Takes the loaded resource, which also ends the request.
func _collect() -> Resource:
	_collected = true
	return ResourceLoader.load_threaded_get(_path)


# Scripts compile here on the main thread before the worker starts: preloads resolved while a script compiles on a
# worker thread leave engine objects behind (Godot 4.7.2, "ObjectDB instances leaked at exit").
func _start_loading() -> void:
	for dependency: String in ResourceLoader.get_dependencies(_path):
		for part: String in dependency.split("::"):
			if part.begins_with("res://") and part.get_extension() == "gd":
				_scripts.append(load(part))
	var err: Error = ResourceLoader.load_threaded_request(_path, "PackedScene")
	if err != OK:
		set_process(false)
		game.fail_loading("could not start loading %s (%s)" % [_path, error_string(err)])
		return
	_loading = true
