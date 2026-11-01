class_name AiTemperament
extends RefCounted
## A pilot's skill and aggressiveness (M3-T13, maintainer Q12), pure: the named ranks or a number 0..1, and how they scale an
## `AiProfile`'s tuned numbers. The profile's own values are what `regular` skill and `balanced` aggression give, so every
## factor below is 1 there; each one moves monotonically with its dial.
##
## Skill (`rookie` 0.2, `regular` 0.45, `veteran` 0.7, `ace` 0.95):
## - aim error: the profile's `aim_error_deg` times `aim_factor` (rookie 2.5x, ace 0.4x);
## - reaction: `reaction_s` before a hit or a new threat is acted on (rookie 0.6 s, regular 0.25 s, ace 0.1 s);
## - fire discipline: the attack's miss gate (`RaiderTactics.fire_miss_m`) times `miss_factor` (rookie 1.6x, ace 0.6x: fewer
##   wasted bolts);
## - evade quality: jinks `jink_factor` as long (rookie 1.3x, ace 0.7x) and reversals turned by up to `reversal_spread_deg`
##   (rookie 20, regular 45, ace 80 degrees: less regular).
## Aggression (`passive` 0, `cautious` 0.25, `balanced` 0.5, `aggressive` 0.75, `reckless` 1):
## - weights: attack times `attack_weight_factor` (up), evade and retreat times `evade_weight_factor` /
##   `retreat_weight_factor` (down); weights stay 0..1;
## - retreat threshold: the profile's `retreat_below` times `retreat_threshold_factor` (passive 2.5x, cautious 2x, aggressive
##   0.5x, reckless never);
## - engage and break-off: the attack's `near_range_m` and `break_range_m` times `press_factor` (passive 1.4x down to reckless
##   0.6x: closer with aggression);
## - `passive` never starts an attack (`never_starts`); it fires back at a ship that hit it in the last `PROVOKED_S`, unless the
##   profile never fires. `reckless` alone may ram (`may_ram`, `BehaviourRam`).

const SKILL_RANKS: Dictionary[StringName, float] = {&"rookie": 0.2, &"regular": 0.45, &"veteran": 0.7, &"ace": 0.95}
const AGGRESSION_LEVELS: Dictionary[StringName, float] = {&"passive": 0.0, &"cautious": 0.25, &"balanced": 0.5,
		&"aggressive": 0.75, &"reckless": 1.0}
const REGULAR: float = 0.45
const BALANCED: float = 0.5
## s: a passive pilot fires back at whoever hit it this recently.
const PROVOKED_S: float = 10.0

# Piecewise-linear anchors (dial value, factor), the dial's ranks in order.
const _AIM: Array = [[0.2, 2.5], [0.45, 1.0], [0.7, 0.65], [0.95, 0.4]]
const _REACTION: Array = [[0.2, 0.6], [0.45, 0.25], [0.7, 0.17], [0.95, 0.1]]
const _MISS: Array = [[0.2, 1.6], [0.45, 1.0], [0.7, 0.8], [0.95, 0.6]]
const _JINK: Array = [[0.2, 1.3], [0.45, 1.0], [0.7, 0.85], [0.95, 0.7]]
const _SPREAD: Array = [[0.2, 20.0], [0.45, 45.0], [0.7, 62.0], [0.95, 80.0]]
const _ATTACK_W: Array = [[0.0, 0.6], [0.25, 0.85], [0.5, 1.0], [0.75, 1.15], [1.0, 1.3]]
const _EVADE_W: Array = [[0.0, 1.3], [0.25, 1.15], [0.5, 1.0], [0.75, 0.8], [1.0, 0.5]]
const _RETREAT_W: Array = [[0.0, 1.3], [0.25, 1.15], [0.5, 1.0], [0.75, 0.8], [1.0, 0.0]]
const _RETREAT_AT: Array = [[0.0, 2.5], [0.25, 2.0], [0.5, 1.0], [0.75, 0.5], [1.0, 0.0]]
const _PRESS: Array = [[0.0, 1.2], [0.25, 1.1], [0.5, 1.0], [0.75, 0.9], [1.0, 0.8]]

var skill: float = REGULAR
var aggression: float = BALANCED


func _init(p_skill: float = REGULAR, p_aggression: float = BALANCED) -> void:
	skill = clampf(p_skill, 0.0, 1.0)
	aggression = clampf(p_aggression, 0.0, 1.0)


## A skill rank's value, or a number 0..1 (a numeric string too); -1 when it is neither.
static func parse_skill(value: Variant) -> float:
	return _parse(value, SKILL_RANKS)


## An aggression level's value, or a number 0..1; -1 when it is neither.
static func parse_aggression(value: Variant) -> float:
	return _parse(value, AGGRESSION_LEVELS)


## The nearest rank's name (`regular`), for the console.
static func skill_name(value: float) -> StringName:
	return _nearest(value, SKILL_RANKS)


static func aggression_name(value: float) -> StringName:
	return _nearest(value, AGGRESSION_LEVELS)


func aim_factor() -> float:
	return _lerp_table(_AIM, skill)


func reaction_s() -> float:
	return _lerp_table(_REACTION, skill)


func miss_factor() -> float:
	return _lerp_table(_MISS, skill)


func jink_factor() -> float:
	return _lerp_table(_JINK, skill)


func reversal_spread_deg() -> float:
	return _lerp_table(_SPREAD, skill)


func attack_weight_factor() -> float:
	return _lerp_table(_ATTACK_W, aggression)


func evade_weight_factor() -> float:
	return _lerp_table(_EVADE_W, aggression)


func retreat_weight_factor() -> float:
	return _lerp_table(_RETREAT_W, aggression)


func retreat_threshold_factor() -> float:
	return _lerp_table(_RETREAT_AT, aggression)


func press_factor() -> float:
	return _lerp_table(_PRESS, aggression)


func never_starts() -> bool:
	return aggression <= 0.0


func may_ram() -> bool:
	return aggression >= 1.0


## The profile this temperament flies: a copy of `base` (its tactics copied too) with the weights, the retreat threshold, the
## aim error and the attack's miss gate, engage and break-off ranges scaled. `base` itself is never changed.
func apply(base: AiProfile) -> AiProfile:
	var out := base.duplicate() as AiProfile
	out.weights = base.weights.duplicate()
	for id: StringName in [&"attack", &"evade", &"retreat"]:
		var w: float = base.weight(id)
		var f: float = attack_weight_factor() if id == &"attack" else (evade_weight_factor() if id == &"evade" else retreat_weight_factor())
		out.weights[id] = clampf(w * f, 0.0, 1.0)
	out.retreat_below = clampf(base.retreat_below * retreat_threshold_factor(), 0.0, 1.0)
	out.aim_error_deg = base.aim_error_deg * aim_factor()
	if base.tactics != null:
		var t := base.tactics.duplicate() as RaiderTactics
		t.fire_miss_m = base.tactics.fire_miss_m * miss_factor()
		t.near_range_m = base.tactics.near_range_m * press_factor()
		t.break_range_m = base.tactics.break_range_m * press_factor()
		out.tactics = t
	return out


func _to_string() -> String:
	return "%s (%.2f) / %s (%.2f)" % [skill_name(skill), skill, aggression_name(aggression), aggression]


static func _parse(value: Variant, names: Dictionary) -> float:
	if value is float or value is int:
		var f: float = float(value)
		return f if f >= 0.0 and f <= 1.0 else -1.0
	if value is String or value is StringName:
		var word := StringName(String(value).strip_edges().to_lower())
		if names.has(word):
			return float(names[word])
		if String(word).is_valid_float():
			return _parse(String(word).to_float(), names)
	return -1.0


static func _nearest(value: float, names: Dictionary) -> StringName:
	var best: StringName = &""
	var best_d: float = INF
	for key: StringName in names:
		var d: float = absf(float(names[key]) - value)
		if d < best_d:
			best_d = d
			best = key
	return best


# Piecewise-linear through the anchors, held flat beyond the first and last.
static func _lerp_table(table: Array, x: float) -> float:
	if x <= float(table[0][0]):
		return float(table[0][1])
	for i: int in range(1, table.size()):
		var x1: float = float(table[i][0])
		if x <= x1:
			var x0: float = float(table[i - 1][0])
			var t: float = (x - x0) / (x1 - x0)
			return lerpf(float(table[i - 1][1]), float(table[i][1]), t)
	return float(table[table.size() - 1][1])
