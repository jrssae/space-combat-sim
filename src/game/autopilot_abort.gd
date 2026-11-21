class_name AutopilotAbort
extends Node
## The one rule for leaving an autopilot (M8-T32, maintainer 2026-11-19): while the gate jump lines up and runs in, or docking
## approaches and flies the lane, holding X (pad X, Shift, Mouse 4) for `hold_s` (data) aborts it: the shots stop, the cinematic
## cuts, the ship keeps its velocity and the controls come back. Past the point of no return (the ship in the gate's funnel, the
## docking ship through the inner doors) the prompt and the bar go away and nothing aborts. Main's child: `Main` asks `offered`
## before sampling X, sets the hold time from it, and calls `take` with the tick's UI command.
##
## Console: command and provider `autopilot`.

const NODE_NAME: String = "AutopilotAbort"
const PATH: String = "res://data/controls/autopilot_abort.json"
const DEFAULT_HOLD_S: float = 1.0
const GATE: StringName = &"gate"
const DOCK: StringName = &"dock"
const ACTIONS: Array[StringName] = [&"status", &"abort"]
## What the prompt asks for, after the buttons to hold.
const LABEL: String = "ABORT"

## The scene that knows the player.
var main: Main = null
## Autopilots aborted so far, and the last one's kind ("" for none).
var aborts: int = 0
var last: StringName = &""

var _prompt: SkipPrompt = null
static var _hold_s: float = -1.0  # the data's hold time once read


## How long X is held to abort, s (data, read once: `Main` asks every tick an abort is on offer).
static func hold_s() -> float:
	if _hold_s < 0.0:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		var value: Variant = (parsed as Dictionary).get("hold_s") if parsed is Dictionary else null
		_hold_s = float(value) if (value is float or value is int) and float(value) > 0.0 else DEFAULT_HOLD_S
	return _hold_s


## The prompt for the buttons `buttons` (`BindingNames.of_action(InputAdapter.AUTOTRACK)`).
static func prompt_text(buttons: String) -> String:
	return "HOLD %s: %s" % [buttons, LABEL]


func _ready() -> void:
	_prompt = SkipPrompt.new()
	add_child(_prompt)
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Which autopilot may be aborted now: `GATE`, `DOCK`, or &"" (none flies the ship, or it is past its point of no return).
func offered() -> StringName:
	if main == null or not main.player_alive:
		return &""
	if main.gates != null and main.gates.abort_offered():
		return GATE
	if main.docking != null and main.docking.abort_offered():
		return DOCK
	return &""


## This tick's X (sampled while `offered`): the prompt and its bar shown, and a completed hold aborts. Returns whether it did.
func take(ui: UiCommand, was_offered: StringName) -> bool:
	if _prompt != null:
		_prompt.text = prompt_text(BindingNames.of_action(InputAdapter.AUTOTRACK)) if offered() != &"" else ""
		_prompt.progress = ui.interact_progress if not _prompt.text.is_empty() else 0.0
	if not ui.interact or was_offered == &"":
		return false
	return abort().is_empty()


## The prompt on screen now ("" for none), for tests and the console.
func prompt_line() -> String:
	return _prompt.text if _prompt != null else ""


## How far the abort's hold has run, 0..1 (its bar).
func progress() -> float:
	return _prompt.progress if _prompt != null else 0.0


## Aborts the autopilot flying the ship now. "" or why not.
func abort() -> String:
	var kind: StringName = offered()
	var why: String = "no autopilot to abort (or past its point of no return)"
	match kind:
		GATE:
			why = main.gates.abort()
		DOCK:
			why = main.docking.abort()
	if why.is_empty():
		aborts += 1
		last = kind
		if _prompt != null:
			_prompt.text = ""
			_prompt.progress = 0.0
	return why


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"autopilot", ConsoleVars.new({
		&"offered": {"get": func() -> String: return String(offered()) if offered() != &"" else "none",
				"doc": "Which autopilot a hold of X aborts now: gate, dock, or none (none flies, or it is past its point of no return)"},
		&"hold_s": {"get": hold_s, "unit": "s", "doc": "How long X is held to abort (data/controls/autopilot_abort.json)"},
		&"prompt": {"get": prompt_line, "doc": "The abort prompt on screen"},
		&"progress": {"get": progress, "doc": "How far the abort's hold has run, 0..1 (the bar)"},
		&"aborts": {"get": func() -> int: return aborts, "doc": "Autopilots aborted so far"},
		&"last": {"get": func() -> String: return String(last) if last != &"" else "none", "doc": "The last autopilot aborted"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"autopilot",
			"The autopilots (M8-T32): status (which one a hold of X aborts now), abort (as a completed hold: the gate jump or the docking, until its point of no return)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status")] as Array[ConsoleArg]), _cmd_autopilot, self)


func _cmd_autopilot(args: Dictionary) -> ConsoleResult:
	if StringName(args[&"action"]) == &"abort":
		var why: String = abort()
		return ConsoleResult.failure(why) if not why.is_empty() else ConsoleResult.line("%s autopilot aborted" % last)
	var kind: StringName = offered()
	return ConsoleResult.line("abort offered: %s (hold %.1f s)" % [String(kind) if kind != &"" else "none", hold_s()])
