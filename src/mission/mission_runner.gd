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
## While the script's opening runs with the controls held (`MissionApi.opening_skippable`), X (or its keys) splits into a tap and
## a hold, as on a target that offers an interaction, and a completed hold skips the opening (M7-T54); a `SkipPrompt` says so.
## The ships the script names with `show_hull` get a hull bar on the HUD.
##
## Control checks (M8 D80): the checks of `data/checks/controls.json` are loaded into the API's `check_book`; while one is open
## the runner measures the player's ship each tick (`ControlCheckProbe`) and a `ControlHint` shows what to press.
##
## Console (`MissionConsole`): provider `mission`, `mission [status|skip|goto <step>|objectives|journal]`; (`ControlCheckConsole`)
## provider `checks`, `checks [status|list|pass|start|stop] [id]`.

## The mission ended (success or not); `result` as `MissionApi.result` plus the player's counters.
signal mission_ended(result: Dictionary)

## After `HitResolver` (200), `RamResolver` (210), `WingDirector` (290) and `WaveDirector` (300).
const PRIORITY: int = 400
const JUMP_POINTS: int = JumpPointPool.DEFAULT_COUNT
## Carriers a mission's raids may bring in at once: each brings a whole wave and jumps back within half a minute, and a skipped
## run brings the civilian escort's three waves in at once.
const CARRIERS: int = 3
## Sim seconds between the end of the mission and the debrief: long enough to read the result line and watch the last
## explosion, short enough not to feel stuck. Sim time, so a pause holds it and leaving the scene drops it.
const DEBRIEF_DELAY_S: float = 3.0

var main: Main = null
var api: MissionApi = null
var stage: MissionStage = null
var jumps: JumpPointPool = null
## The subtitles and squelches of the lines the script says (D53).
var comms: CommsPanel = null
## The opening's `HOLD X: SKIP` and its bar (M7-T54).
var skip_prompt: SkipPrompt = null
## The open control check's hint with the live bindings (M8 D80).
var hint: ControlHint = null
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
	jumps = JumpPointPool.new()
	jumps.name = "JumpPoints"
	jumps.world = main.world
	main.effects.add_child(jumps)
	jumps.prepare(JUMP_POINTS)
	CarrierJumps.attach(main.world).prepare(CARRIERS)  # raids behind a carrier (M6-T23), built at load (D22)
	CarrierJumps.attach(main.world).prepare(CARRIERS, CapitalStandin.STRIKE_CARRIER)  # the raiders' own (M12-T19)
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
	api.placeholders = _scenario.get("placeholders", {})
	_load_dialog(String(block.get("dialog", "")))
	api.closing_lines = block.get("closing_lines", {})
	var shots_problem: String = api.load_cinematics(_scenario.get("cinematics", {}))
	if not shots_problem.is_empty() and error.is_empty():
		error = shots_problem
	comms = CommsPanel.new()
	add_child(comms)
	comms.bind(api.dialog, api.dialog_book, main.audio)
	comms.device_source = func() -> InputSource.Device: return main.input_source.device if main.input_source != null \
			else InputSource.Device.PAD
	skip_prompt = SkipPrompt.new()
	add_child(skip_prompt)
	_load_checks()
	hint = ControlHint.new()
	add_child(hint)
	api.ended.connect(_on_ended)
	main.director.player_destroyed.connect(_on_player_destroyed)
	main.director.station_destroyed.connect(_on_station_destroyed)
	recorder = DebriefRecorder.new()
	recorder.main = main
	add_child(recorder)
	main.hud.extra_input = fill_hud_input
	MissionConsole.register(DebugConsole.registry, self)
	ControlCheckConsole.register(DebugConsole.registry, self)
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
		api.check_sample = ControlCheckProbe.sample(main) if api.checks.is_active() else null
		api.tick(delta, PlayerActions.from_command(main.adapter.last))
	_show_skip_prompt()
	_show_hint()
	if _debrief_in_s < INF:
		_debrief_in_s -= delta
		if _debrief_in_s <= 0.0:
			_debrief_in_s = INF
			_open_debrief()


## Whether a hold of X would skip the opening now (`Main` asks before it samples the pad, so X splits into tap and hold).
func opening_skip_offered() -> bool:
	return api != null and api.opening_skippable()


## This tick's X (`ui`, sampled while the skip was offered): a completed hold skips the opening; the prompt shows the hold.
func take_opening_hold(ui: UiCommand) -> void:
	if skip_prompt != null:
		skip_prompt.progress = ui.interact_progress
	if ui.interact:
		api.skip_opening()


## Every objective of the running mission (`ObjectiveBook.snapshot`): the pause menu's right panel and the debrief.
func objectives() -> Array[Dictionary]:
	return api.book.snapshot() if api != null else ([] as Array[Dictionary])


## The mission's part of this frame's HUD: the active objectives, its waypoint (unless a route already marks one) and, once
## over, the result as the status line.
func fill_hud_input(input: HudInput) -> void:
	if api == null:
		return
	input.objectives = api.book.active()
	for ship_name: String in api.hull_bars:
		input.escorts.append({"name": ship_name, "hull": stage.hull_fraction(ship_name)})
	if not input.has_waypoint:
		input.waypoint_key = "mission:%d" % api.waypoint_serial if api.waypoint_serial > 0 else ""
		var at: Variant = stage.local_position(api.waypoint_name) if not api.waypoint_name.is_empty() else null
		if at != null:
			input.has_waypoint = true
			input.waypoint_position = at as Vector3
			input.waypoint_label = api.waypoint_name.to_upper()
			input.waypoint_id = stage.target_id(api.waypoint_name)
	if api.has_ended():
		input.status_line = result_line(api.result)


# The skip prompt while the opening can be skipped, naming the live bindings; hidden otherwise.
func _show_skip_prompt() -> void:
	if skip_prompt == null:
		return
	var offered: bool = opening_skip_offered()
	skip_prompt.text = SkipPrompt.prompt_text(BindingNames.of_action(InputAdapter.AUTOTRACK)) if offered else ""
	if not offered:
		skip_prompt.progress = 0.0


# The open check's hint, naming the live bindings; hidden with none open, and under a cinematic.
func _show_hint() -> void:
	if hint == null or api == null:
		return
	var open: ControlCheck = api.checks.current
	hint.label = open.label if open != null else ""
	hint.buttons = ControlHintText.bindings(open) if open != null else ""
	if hint.buttons.is_empty() and open != null:
		hint.buttons = ControlHintText.UNBOUND
	hint.progress = open.progress if open != null else 0.0
	hint.suppressed = main.camera_rig.is_playing_shot()


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
		_resume_checkpoint()
	if not error.is_empty():
		push_error("Mission %s: %s" % [api.scenario_id, error])


# A restart from a lost run's checkpoint (M8 D79): the notes it held, then every step before it skipped on this fresh world.
func _resume_checkpoint() -> void:
	var checkpoint: Dictionary = main.mission_checkpoint
	var step := StringName(str(checkpoint.get("step", "")))
	if step == &"" or not error.is_empty():
		return
	api.notes = (checkpoint.get("notes", {}) as Dictionary).duplicate(true)
	var problem: String = api.goto(step)
	if not problem.is_empty():
		push_error("Mission %s: checkpoint %s: %s" % [api.scenario_id, step, problem])
	print("[mission] restarted from checkpoint %s" % step)


## The pause menu's skip of the script's block (`MissionScript.skip_block`): its label while it is offered, else "".
func skip_label() -> String:
	return String(api.skip_block.get("label", "")) if api != null and api.skip_offered() else ""


func take_skip() -> String:
	return api.take_skip() if api != null else "no mission"


# The mission's dialog file, if it names one: a file that does not validate is the mission's start error.
func _load_dialog(path: String) -> void:
	if path.is_empty():
		return
	var made: Dictionary = DialogBook.load_file(path)
	if bool(made["ok"]):
		api.dialog_book = made["book"]
		api.dialog_book.fill(api.placeholders)
		api.dialog_book.fill(_callsigns(api.dialog_book))
	else:
		error = "dialog: %s" % made["error"]


# `{<speaker id>}` -> that speaker's callsign as spoken ("{instructor}" -> "Sextant"), so a renamed voice needs one data entry.
static func _callsigns(book: DialogBook) -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in book.speaker_ids():
		out["{%s}" % id] = book.speaker(id).callsign.capitalize()
	return out


# The control checks every mission may run. A file that does not validate leaves the mission without checks, and says so.
func _load_checks() -> void:
	var made: Dictionary = ControlCheckBook.load_file()
	if bool(made["ok"]):
		api.check_book = made["book"]
	else:
		push_error("Mission: control checks: %s" % made["error"])


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


# Babylon 5 is always destructible (M10-T65, Q72): a mission that needs it is lost with it.
func _on_station_destroyed(_station: Station) -> void:
	if api != null:
		api.station_destroyed()


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
