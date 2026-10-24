class_name AiProfile
extends Resource
## A pilot's character for `AiPilot` (architecture §16 D34): how much each behaviour's score counts, how readily it
## changes its mind, when it runs, how fast it cruises, how well it aims, and the attack's tactics. One resource per kind
## of pilot in `assets/ai/` (`ally_starfury`, `raider`, `instructor`; `PATHS`); the defaults below are the plan's selection
## numbers. Tune in (H).
##
## Selection (see `AiPilot`): each behaviour's score (0..1) times `weight(id)`; a challenger replaces the current behaviour
## when it beats the current's weighted score by more than `stickiness`, or, within `min_dwell_s` of the last switch, by
## more than `emergency_margin`.

const PATHS: Dictionary[StringName, String] = {
	&"ally_starfury": "res://assets/ai/ally_starfury.tres",
	&"raider": "res://assets/ai/raider.tres",
	&"instructor": "res://assets/ai/instructor.tres",
}
const STARFURY_TACTICS_PATH: String = "res://assets/ai/starfury_tactics.tres"

## Behaviour id -> weight 0..1. A behaviour the profile does not name weighs 1 (`weight`), so behaviours added later
## work in every profile until a profile opts out with 0.
@export var weights: Dictionary[StringName, float] = {}
## Score units: the current behaviour's bonus against challengers, and the lead a challenger needs inside the dwell.
@export var stickiness: float = 0.15
@export var emergency_margin: float = 0.4
## Seconds a behaviour keeps control after it took over, unless a challenger wins by `emergency_margin`.
@export var min_dwell_s: float = 1.0
## Retreat below this hull fraction (0 = fights to the death).
@export var retreat_below: float = 0.25
## m/s: the pilot's travelling speed (retreat flies at this plus `BehaviourRetreat.EXTRA_MPS`).
@export var cruise_mps: float = 100.0
## Degrees: the amplitude of the seeded, slowly wandering offset on the attack's lead (0 = a perfect shot).
@export var aim_error_deg: float = 0.0
## The attack's gun-run numbers (`AttackBrain`).
@export var tactics: RaiderTactics = null
## False: the trigger is never pulled, whatever the behaviour (the instructor).
@export var fires: bool = true
## Idle: true holds position with the brake, false coasts.
@export var idle_hold: bool = false


## The profile `PATHS[profile_name]`, or null for a name it does not list.
static func load_named(profile_name: StringName) -> AiProfile:
	if not PATHS.has(profile_name):
		return null
	return load(PATHS[profile_name]) as AiProfile


func weight(id: StringName) -> float:
	return weights.get(id, 1.0)


## "" when every field is in range, else the first bad field and why.
func validate() -> String:
	for id: StringName in weights:
		var w: float = weights[id]
		if not (w >= 0.0 and w <= 1.0):
			return "weights.%s must be 0..1, got %s" % [id, w]
	if stickiness < 0.0:
		return "stickiness must be 0 or more, got %s" % stickiness
	if emergency_margin < 0.0:
		return "emergency_margin must be 0 or more, got %s" % emergency_margin
	if min_dwell_s < 0.0:
		return "min_dwell_s must be 0 or more, got %s" % min_dwell_s
	if not (retreat_below >= 0.0 and retreat_below <= 1.0):
		return "retreat_below must be 0..1, got %s" % retreat_below
	if cruise_mps <= 0.0:
		return "cruise_mps must be above 0, got %s" % cruise_mps
	if aim_error_deg < 0.0:
		return "aim_error_deg must be 0 or more, got %s" % aim_error_deg
	if tactics == null:
		return "tactics must be a RaiderTactics resource"
	return ""
