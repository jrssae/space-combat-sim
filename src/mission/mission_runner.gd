class_name MissionRunner
extends Node
## Runs the mission of a scenario with a `mission` block (architecture §18 D51, D52): `Main` creates it after the pools, the
## props and the scenario's ships are in place. It loads the script, builds the `MissionApi` over a `MissionWorld`, an
## `ObjectiveBook` and a `MissionStage` on Main's nodes, and ticks it once per physics tick after the world moved (priority
## `PRIORITY`: after the hit and ram resolvers, the wings and the waves).
##
## The player does not respawn in a mission: on the player's death the runner cancels the pending respawn and the mission is
## lost. The result, with the player's counters (`DebriefRecorder`), goes to `Game` (`last_result`, the `DEBRIEF` state). Main
## stays in space for `DEBRIEF_DELAY_S` of sim time, with the result on the HUD, and then `Game` shows the debrief (D56).
## It hands the HUD the active objectives, the mission's waypoint and the result line (`Hud.extra_input`), and the pause menu
## the whole book (`objectives()`). The mission's dialog file is loaded into the API's `dialog_book` and a `CommsPanel` shows the
## lines the script says (D53); a dialog file that does not validate stops the mission from starting, and so does a camera shot in
## the scenario's `cinematics` that does not (D55).
##
## Console (`MissionConsole`): provider `mission`, `mission [status|skip|goto <step>|objectives|journal]`.

## The mission ended (success or not); `result` as `MissionApi.result` plus the player's counters.
signal mission_ended(result: Dictionary)

## After `HitResolver` (200), `RamResolver` (210), `WingDirector` (290) and `WaveDirector` (300).
const PRIORITY: int = 400
const JUMP_POINTS: int = JumpArrivalPool.DEFAULT_COUNT
## Sim seconds between the end of the mission and the debrief: long enough to read the result line and watch the last
## explosion, short enough not to feel stuck. Sim time, so a pause holds it and leaving the scene drops it.
const DEBRIEF_DELAY_S: float = 3.0

var main: Main = null
var api: MissionApi = null
var stage: MissionStage = null
var jumps: JumpArrivalPool = null
## The subtitles and squelches of the lines the script says (D53).
var comms: CommsPanel = null
## Counts the player's shots, hits, kills and wing losses for the debrief.
var recorder: DebriefRecorder = null
## `DEBRIEF_DELAY_S`; tests shorten it.
var debrief_delay_s: float = DEBRIEF_DELAY_S
## Why the mission could not start ("" when it runs).
var error: String = ""

var _scenario: Dictionary = {}
# Sim seconds left before the debrief; INF while none is due.
var _debrief_in_s: float = INF


## A runner for `scenario` (a `ScenarioLoader` result with a `mission` block), added under `p_main`.
static func create(p_main: Main, scenario: Dictionary) -> MissionRunner:
	var runner := MissionRunner.new()
	runner.main = p_main
	runner._scenario = scenario
	p_main.add_child(runner)
	return runner


func _init() -> void:
	name = "MissionRunner"
	process_physics_priority = PRIORITY
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	var block: Dictionary = _scenario.get("mission", {})
	var system: StringName = _scenario.get("system_id", &"local")
	jumps = JumpArrivalPool.new()
	jumps.name = "JumpPoints"
	jumps.world = main.world
	main.effects.add_child(jumps)
	jumps.prepare(JUMP_POINTS)
	stage = MissionStage.new()
	stage.setup(main, jumps)
	var world := MissionWorld.new()
	world.system_id = system
	var book := ObjectiveBook.new()
	var problem: String = book.declare(block.get("objectives", []), system)
	if not problem.is_empty():
		push_error("Mission: %s" % problem)  # the loader checked them; only a hand-built scenario gets here
	api = MissionApi.new(world, book, stage)
	api.scenario_id = _scenario.get("scenario_id", &"")
	api.title = String(block.get("title", ""))
	_load_dialog(String(block.get("dialog", "")))
	api.closing_lines = block.get("closing_lines", {})
	var shots_problem: String = api.load_cinematics(_scenario.get("cinematics", {}))
	if not shots_problem.is_empty() and error.is_empty():
		error = shots_problem
	comms = CommsPanel.new()
	add_child(comms)
	comms.bind(api.dialog, api.dialog_book, main.audio)
	api.ended.connect(_on_ended)
	main.director.player_destroyed.connect(_on_player_destroyed)
	recorder = DebriefRecorder.new()
	recorder.main = main
	add_child(recorder)
	main.hud.extra_input = fill_hud_input
	MissionConsole.register(DebugConsole.registry, self)
	# The first step starts once Main is ready (deferred), before the first tick and before any console startup script.
	_begin.call_deferred(String(block.get("script", "")))


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if main != null and is_instance_valid(main.hud) and main.hud.extra_input == Callable(self, &"fill_hud_input"):
		main.hud.extra_input = Callable()
	if api != null:
		api.release()
	if stage != null:
		stage.teardown()


func _physics_process(delta: float) -> void:
	if api != null:
		api.tick(delta, PlayerActions.from_command(main.adapter.last))
	if _debrief_in_s < INF:
		_debrief_in_s -= delta
		if _debrief_in_s <= 0.0:
			_debrief_in_s = INF
			_open_debrief()


## Every objective of the running mission (`ObjectiveBook.snapshot`): the pause menu's right panel and the debrief.
func objectives() -> Array[Dictionary]:
	return api.book.snapshot() if api != null else ([] as Array[Dictionary])


## The mission's part of this frame's HUD: the active objectives, its waypoint (unless a route already marks one) and, once
## over, the result as the status line.
func fill_hud_input(input: HudInput) -> void:
	if api == null:
		return
	input.objectives = api.book.active()
	if not input.has_waypoint and not api.waypoint_name.is_empty():
		var at: Variant = stage.local_position(api.waypoint_name)
		if at != null:
			input.has_waypoint = true
			input.waypoint_position = at as Vector3
			input.waypoint_label = api.waypoint_name.to_upper()
	if api.has_ended():
		input.status_line = result_line(api.result)


## The HUD's line for a result: `MISSION COMPLETE`, or `MISSION FAILED - PLAYER DESTROYED`.
static func result_line(result: Dictionary) -> String:
	if bool(result.get("success", false)):
		return "MISSION COMPLETE"
	var reason: String = str(result.get("reason", ""))
	return "MISSION FAILED" + (" - " + reason.to_upper() if not reason.is_empty() else "")


## running, success, failure, or error (it could not start).
func state_name() -> String:
	if api == null or not error.is_empty():
		return "error"
	if api.has_ended():
		return "success" if bool(api.result.get("success", false)) else "failure"
	return "running"


func _begin(script_path: String) -> void:
	if api == null or not is_inside_tree():
		return
	if not error.is_empty():
		push_error("Mission %s: %s" % [api.scenario_id, error])
		return
	var script: MissionScript = _load_script(script_path)
	if script != null:
		print("[mission] %s: %s, %d steps" % [api.scenario_id, api.title, script.steps().size()])
		error = api.begin(script)
	if not error.is_empty():
		push_error("Mission %s: %s" % [api.scenario_id, error])


# The mission's dialog file, if it names one: a file that does not validate is the mission's start error.
func _load_dialog(path: String) -> void:
	if path.is_empty():
		return
	var made: Dictionary = DialogBook.load_file(path)
	if bool(made["ok"]):
		api.dialog_book = made["book"]
	else:
		error = "dialog: %s" % made["error"]


func _load_script(path: String) -> MissionScript:
	if path.is_empty():
		error = "the mission block names no script"
		return null
	if not ResourceLoader.exists(path):
		error = "no mission script at %s" % path
		return null
	var source := load(path) as GDScript
	var instance: Object = source.new() if source != null and source.can_instantiate() else null
	if not (instance is MissionScript):
		error = "%s does not extend MissionScript" % path
		return null
	return instance as MissionScript


func _on_player_destroyed(_info: HitInfo) -> void:
	main.director.cancel_respawn()  # no respawn in a mission (D51)
	if api != null:
		api.player_destroyed()


func _on_ended(result: Dictionary) -> void:
	var report: Dictionary = recorder.report(result) if recorder != null else result
	var game: Node = get_node_or_null(^"/root/Game")
	if game != null and game.has_method(&"end_mission") and bool(game.call(&"end_mission", report)):
		_debrief_in_s = maxf(debrief_delay_s, api.dialog.remaining_s())  # the closing line is heard out
	mission_ended.emit(report)


# The beat is over: `Game` replaces Main with the debrief, or says why it will not.
func _open_debrief() -> void:
	var game: Node = get_node_or_null(^"/root/Game")
	var problem: String = str(game.call(&"show_debrief")) if game != null and game.has_method(&"show_debrief") else "no Game"
	if not problem.is_empty():
		push_warning("Mission: no debrief: %s" % problem)
