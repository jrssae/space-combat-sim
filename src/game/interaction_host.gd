class_name InteractionHost
extends Node
## The long-hold interaction in play (M7-T27): which interaction the selected target offers the player now, running it when the
## hold of X completes, and the HUD's prompt (`HOLD X / SHIFT / MOUSE 4: REQUEST JUMP`, the live bindings) and answer (`BABYLON 5 DOCKING BAY: NOT AVAILABLE`). Main's
## child, a thin adapter: the hold is `HoldInteract`'s, the action the target's own `TargetInteraction`.
##
## Console: provider and command `interact`.

const NODE_NAME: String = "Interactions"
const PROVIDER: StringName = &"interact"
const ACTIONS: Array[StringName] = [&"status", &"run", &"hold"]
## How long an answer stays on the HUD's prompt line, s.
const NOTICE_S: float = 3.0

## The scene that knows the player.
var main: Main = null
## Interactions run (from a hold or the console), and the last one's kind and answer ("" = it ran).
var runs: int = 0
var last_kind: StringName = &""
var last_result: String = ""

var _notice: String = ""
var _notice_left_s: float = 0.0


## The prompt for an offered interaction; `buttons` names what to hold (`BindingNames.of_action(InputAdapter.AUTOTRACK)`).
static func prompt_text(interaction: TargetInteraction, buttons: String = "X") -> String:
	return "HOLD %s: %s" % [buttons, interaction.label]


## The status for one out of reach: no button, only how far it is and how close to come (`JUMPGATE: 3.4 km — CLOSE TO 2.0 km
## TO JUMP`).
static func status_text(target_name: String, distance_m: float, interaction: TargetInteraction) -> String:
	return "%s: %s — CLOSE TO %s TO %s" % [target_name, range_text(distance_m), range_text(interaction.range_m), interaction.label]


## A distance as the status reads it: metres under 1 km, else km with one decimal.
static func range_text(metres: float) -> String:
	return "%.0f m" % metres if metres < 1000.0 else "%.1f km" % (metres / 1000.0)


## The answer shown when an interaction did not run.
static func notice_text(target_name: String, result: String) -> String:
	return "%s: %s" % [target_name, result.to_upper()]


func _ready() -> void:
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	_notice_left_s = maxf(_notice_left_s - delta, 0.0)


## The selected target's marker, or null.
func selected() -> Targetable:
	if main == null or main.ship == null or not is_instance_valid(main.ship):
		return null
	var id: int = main.ship.targeting.selected_id()
	if id == 0 or not is_instance_id_valid(id):
		return null
	return instance_from_id(id) as Targetable


## What a hold of X would do now: the selected target's interaction while it offers it, the ship is within its reach and the pilot
## has the controls; else null. Out of reach the hold does nothing and X is auto-track alone.
func offer() -> TargetInteraction:
	var interaction: TargetInteraction = _offered_anywhere()
	if interaction == null or not interaction.in_reach(_distance_to_selected()):
		return null
	return interaction


# The selected target's interaction as offered, its reach aside.
func _offered_anywhere() -> TargetInteraction:
	if main == null or not main.player_alive or main.controls_locked():
		return null
	var target: Targetable = selected()
	if target == null or target.interaction == null or not target.interaction.is_offered():
		return null
	return target.interaction


# From the player's ship to the selected target's marker, m (INF with none).
func _distance_to_selected() -> float:
	var target: Targetable = selected()
	if target == null or main == null or main.ship == null:
		return INF
	return main.ship.global_position.distance_to(target.global_position)


## Runs what the hold asked for. Returns "" or why it did not run, which the HUD shows for a few seconds.
func run_offered() -> String:
	var interaction: TargetInteraction = offer()
	if interaction == null:
		return "nothing to interact with"
	var result: String = interaction.run()
	runs += 1
	last_kind = interaction.kind
	last_result = result
	if not result.is_empty():
		var target: Targetable = selected()
		_notice = notice_text(target.display_name if target != null else "", result)
		_notice_left_s = NOTICE_S
	return result


## The HUD's prompt line: an answer while it shows, else the button prompt within reach, else a plain status saying how close to
## come (no button: the maintainer's rule), else "".
func prompt_line() -> String:
	if _notice_left_s > 0.0:
		return _notice
	var interaction: TargetInteraction = _offered_anywhere()
	if interaction == null:
		return ""
	var distance: float = _distance_to_selected()
	if interaction.in_reach(distance):
		return prompt_text(interaction, BindingNames.of_action(InputAdapter.AUTOTRACK))
	return status_text(selected().display_name, distance, interaction)


# --- console -----------------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"offered": {"get": func() -> String: return String(offer().kind) if offer() != null else "none",
				"doc": "What a hold of X runs now (jump, dock, cargo), or none"},
		&"available": {"get": func() -> bool: return offer() != null and offer().is_available(),
				"doc": "The offered interaction does something yet (the bays' placeholders do not)"},
		&"progress": {"get": func() -> float: return main.adapter.last.ui.interact_progress if main != null else 0.0,
				"doc": "How far the hold has run, 0..1 (the bar across the top)"},
		&"hold_s": {"get": func() -> float: return main.adapter.interact_hold_s if main != null else 0.0, "unit": "s",
				"doc": "How long the hold takes (settings.interact_hold_s)"},
		&"prompt": {"get": prompt_line, "doc": "The HUD's prompt or answer line"},
		&"runs": {"get": func() -> int: return runs, "doc": "Interactions run"},
		&"last": {"get": func() -> String: return "%s: %s" % [last_kind, last_result if not last_result.is_empty() else "ran"] \
				if runs > 0 else "none", "doc": "The last interaction run and its answer"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"The hold-X interaction (M7-T27): status, run (as a completed hold), hold [s] (hold X that long, default the hold time)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"), ConsoleArg.float_optional(&"seconds", null, 0.0, 30.0)] \
					as Array[ConsoleArg]), _cmd_interact, self)


func _cmd_interact(args: Dictionary) -> ConsoleResult:
	var action: StringName = StringName(args[&"action"])
	var interaction: TargetInteraction = offer()
	match action:
		&"run":
			if interaction == null:
				return ConsoleResult.failure("nothing within reach (target the gate or a station bay and close to 2 km)")
			var result: String = run_offered()
			return ConsoleResult.line("%s ran" % interaction.kind if result.is_empty() else "%s: %s" % [interaction.kind, result])
		&"hold":
			var seconds: float = float(args[&"seconds"]) if args[&"seconds"] != null else main.adapter.interact_hold_s + 0.1
			main.adapter.console_hold_s = seconds
			return ConsoleResult.line("holding X for %.2f s (%s)" % [seconds,
					"offers %s" % interaction.kind if interaction != null else "nothing offered: a tap"])
	if interaction == null:
		return ConsoleResult.line("nothing offered")
	return ConsoleResult.line("%s offers %s (%s); hold %.2f s" % [selected().display_name, interaction.kind,
			"available" if interaction.is_available() else TargetInteraction.NOT_AVAILABLE, main.adapter.interact_hold_s])
