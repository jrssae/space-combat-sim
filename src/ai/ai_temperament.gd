class_name AiTemperament
extends RefCounted
## A pilot's skill and aggressiveness (M3-T13, maintainer Q12), pure: named ranks or a number 0..1, and how they scale an
## `AiProfile`'s tuned numbers. `regular` skill and `balanced` aggression leave the profile as is (every factor is 1).
##
## Skill (`rookie` 0.2, `regular` 0.45, `veteran` 0.7, `ace` 0.95):
## - aim error: times `aim_factor` (rookie 2.5x, ace 0.4x);
## - `reaction_s` before a hit or new threat is acted on (rookie 0.6 s, regular 0.25 s, ace 0.1 s);
## - fire discipline: the attack's miss gate times `miss_factor` (rookie 1.6x, ace 0.6x, fewer wasted bolts);
## - evade quality: jinks `jink_factor` as long (rookie 1.3x, ace 0.7x), reversals up to `reversal_spread_deg`
##   (rookie 20, ace 80 degrees: less regular).
## Aggression (`passive` 0, `cautious` 0.25, `balanced` 0.5, `aggressive` 0.75, `reckless` 1):
## - weights: attack up, evade and retreat down, kept within 0..1;
## - retreat threshold times `retreat_threshold_factor` (passive 2.5x, aggressive 0.5x, reckless never);
## - engage and break-off ranges times `press_factor` (passive 1.4x to reckless 0.6x: closer with aggression);
## - slashing pass (M3-T18, maintainer 2026-11-01): `slash_chance` is the share of attack runs flown as `AttackSlash`
##   (unless `AiProfile.slashing` is off): a rookie always, falling with skill to 0.5 for an ace, the rest standard gun runs.
##   `close_pass_chance` is the share flown at `AttackSlash.CLOSE_PASS_OFFSET_M` (100 m) instead of 200 m: 0 up to
##   `balanced`, 0.25 at `aggressive`, 1 at `reckless`, whatever the skill;
## - `awareness` (M3-T18) scales evade's score for threats other than the ship it is attacking: a rookie notices them
##   less (0.4), an ace more (1.2);
## - `passive` never starts an attack (`never_starts`) but fires back at a ship that hit it in the last `PROVOKED_S`. Only
##   `reckless` may ram (`may_ram`, `BehaviourRam`).

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
const _SLASH: Array = [[0.2, 1.0], [0.45, 0.8], [0.7, 0.65], [0.95, 0.5]]
const _AWARE: Array = [[0.2, 0.4], [0.45, 0.75], [0.7, 1.0], [0.95, 1.2]]
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


## The share of attack runs flown as slashing passes (M3-T18): 1 for a rookie, falling with skill to 0.5 for an ace.
func slash_chance() -> float:
	return _lerp_table(_SLASH, skill)


## The share of slashing passes flown at 100 m instead of 200 m: 0 up to balanced, rising to 1 at reckless.
func close_pass_chance() -> float:
	var t: float = clampf((aggression - BALANCED) / (1.0 - BALANCED), 0.0, 1.0)
	return t * t


## How much a threat other than the attack's own target counts for evade (rookie 0.4 .. ace 1.2).
func awareness() -> float:
	return _lerp_table(_AWARE, skill)


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
