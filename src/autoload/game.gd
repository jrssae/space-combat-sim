extends Node
## Game autoload (architecture §18, D50): takes the player from the front end through the loading screen into Main, and
## carries the request (what to play, encounters, seed) across those scene changes. The pure `GameFlow` says which move
## is allowed; this node only changes scenes and answers the console (`menu`, `play`, provider `game`). It never reads
## Input.
##
## Boot (`src/frontend/boot.tscn`, the project's main scene) calls `boot` once. A scripted run (headless, a console
## script, `--scenario=<id>`, `skip_front_end`) goes straight to Main exactly as before the front end existed, so tools,
## benchmarks and tests start as they always did.

const SettingsScript := preload("res://src/autoload/settings.gd")
const DebugConsoleScript := preload("res://src/autoload/debug_console.gd")

const FRONT_END_SCENE: String = "res://src/frontend/front_end.tscn"
const LOADING_SCENE: String = "res://src/frontend/loading_screen.tscn"
const MAIN_SCENE: String = "res://src/game/main.tscn"
const SEED_MAX: int = 2147483647

var flow: GameFlow = GameFlow.new()

# Injection points, read when the node enters the tree. The defaults are what the autoload uses; tests point them
# at a scratch Settings, a registry of their own, a light stand-in for Main and a node to hold the scenes.
var settings: SettingsScript = null  ## null: /root/Settings
var registry: ConsoleRegistry = null  ## null: the registry of /root/DebugConsole
var main_scene_path: String = MAIN_SCENE
## Where scenes go. null: the tree's root, as its current scene.
var scene_parent: Node = null


func _ready() -> void:
	if settings == null:
		settings = get_node_or_null(^"/root/Settings") as SettingsScript
	if registry == null:
		var console: DebugConsoleScript = get_node_or_null(^"/root/DebugConsole") as DebugConsoleScript
		if console != null:
			registry = console.registry
	_register_console()


func _exit_tree() -> void:
	if registry != null:
		registry.unregister_owner(self)


## Boot's one decision: the front end for a normal launch, straight to Main for every scripted run.
func boot(engine_args: PackedStringArray, user_args: PackedStringArray, headless: bool) -> void:
	var skip: bool = settings != null and bool(settings.get_value(&"skip_front_end"))
	var route: Dictionary = GameFlow.boot_route(engine_args, user_args, headless, skip)
	if not route["straight"]:
		show_front_end()
		return
	var wanted: String = route["scenario"]
	if not wanted.is_empty() and settings != null and settings.set_value(&"scenario", StringName(wanted)) != OK:
		push_error("Game: --scenario=%s: %s" % [wanted, settings.get_last_error()])
	var scenario_id := StringName(settings.get_value(&"scenario") if settings != null \
			else SettingsSchema.new().get_default(&"scenario"))
	if not flow.enter_directly(GameFlow.make_request(GameFlow.kind_for(scenario_id), scenario_id)):
		push_error("Game: %s" % flow.error)
		return
	# Main reads Settings.scenario itself, as it always has.
	_show_scene.call_deferred(main_scene_path)


## Back to the front end from anywhere: the `menu` command, and later the pause menu and the debrief.
func show_front_end() -> void:
	flow.open_menu()
	_show_scene.call_deferred(FRONT_END_SCENE)


## Starts `request` through the loading screen, as the menu does. Returns why it was refused, or "" when it was not.
func play(request: Dictionary) -> String:
	var problem: String = GameFlow.validate_request(request)
	if problem.is_empty() and not FileAccess.file_exists(GameFlow.scenario_path(request["scenario_id"])):
		problem = "no scenario '%s' in %s" % [request["scenario_id"], GameFlow.SCENARIO_DIR]
	if problem.is_empty() and not flow.start_loading(request):
		problem = flow.error
	if not problem.is_empty():
		return problem
	_show_scene.call_deferred(LOADING_SCENE)
	return ""


## The loading screen has Main's scene: build it for the request and put it in place. Building it here, while the
## loading screen is still the last frame drawn, keeps the pool-filling hitch behind that screen.
func finish_loading(packed: PackedScene) -> void:
	if flow.state != GameFlow.State.LOADING:
		return  # the player left the loading screen meanwhile
	if packed == null:
		fail_loading("could not load %s" % main_scene_path)
		return
	var main: Node = packed.instantiate()
	# Set by name, so this autoload does not compile Main and everything it uses at start-up.
	main.set(&"scenario_path", GameFlow.scenario_path(flow.request["scenario_id"]))
	main.set(&"scenario_seed", int(flow.request["seed"]))
	flow.finish_loading()
	_show.call_deferred(main)


## Loading went wrong: say so and go back to the front end.
func fail_loading(reason: String) -> void:
	push_error("Game: %s; back to the front end" % reason)
	show_front_end()


## A mission is over (M5-T05): its result is kept for the debrief and the flow moves to `DEBRIEF` (T09 shows it; Main stays
## in space meanwhile). A Main built outside the flow (a test, the `scenario` command) still leaves the result here.
func end_mission(result: Dictionary) -> void:
	if not flow.end_run(result):
		flow.last_result = result.duplicate()


## Every scenario file `play` can start, by id.
func scenario_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for file: String in DirAccess.get_files_at(GameFlow.SCENARIO_DIR):
		if file.get_extension() == "json":
			ids.append(file.get_basename())
	ids.sort()
	return ids


func _show_scene(path: String) -> void:
	var node: Node = (load(path) as PackedScene).instantiate()
	if &"game" in node:
		node.set(&"game", self)
	_show(node)


# Replaces the current scene with `next`. The tree's pause and the mouse capture belong to the scene being left.
func _show(next: Node) -> void:
	var tree: SceneTree = get_tree()
	var leaving: Array[Node] = []
	if scene_parent != null:
		leaving.assign(scene_parent.get_children())
	elif tree.current_scene != null:
		leaving.append(tree.current_scene)
	for node: Node in leaving:
		node.get_parent().remove_child(node)
		node.queue_free()
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if scene_parent != null:
		scene_parent.add_child(next)
	else:
		tree.root.add_child(next)
		tree.current_scene = next


# --- Console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	if registry == null:
		return
	registry.register_command(ConsoleCommand.new(&"menu", "Back to the front end", [] as Array[ConsoleArg]),
			_cmd_menu, self)
	registry.register_command(ConsoleCommand.new(&"play",
			"Play a scenario through the loading screen, as the menu does; the same seed plays the same run",
			[ConsoleArg.enum_required(&"scenario_id", scenario_ids), ConsoleArg.int_optional(&"seed", 0, 0, SEED_MAX)]),
			_cmd_play, self)
	registry.register_provider(&"game", ConsoleVars.new({
		&"state": {"get": func() -> String: return GameFlow.state_name(flow.state),
				"doc": "front_end, loading, in_space or debrief"},
		&"request": {"get": func() -> String: return GameFlow.describe_request(flow.request),
				"doc": "What is being played: scenario (kind), encounters, seed; none before anything was asked for"},
		&"last_result": {"get": func() -> String: return GameFlow.describe_result(flow.last_result),
				"doc": "How the last run ended (success or failure and why); none until one ends"},
	}), self)


func _cmd_menu(_args: Dictionary) -> String:
	show_front_end()
	return "front end"


func _cmd_play(args: Dictionary) -> ConsoleResult:
	var scenario_id := StringName(args[&"scenario_id"])
	var problem: String = play(GameFlow.make_request(GameFlow.kind_for(scenario_id), scenario_id, false,
			int(args[&"seed"])))
	if not problem.is_empty():
		return ConsoleResult.failure(problem)
	return ConsoleResult.line("loading %s" % GameFlow.describe_request(flow.request))
