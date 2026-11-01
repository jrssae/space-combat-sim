class_name AiPilot
extends PilotBrain
## The utility brain (architecture §16 D34): a set of `AiBehaviour`s that score themselves every tick, weighted by the
## pilot's `AiProfile`; the winner flies the ship. Behind the same `PilotBrain` interface as M2's brains, so the
## `AiPilotDriver`, its avoidance filter and the pool do not change.
##
## Selection, each tick: every behaviour's `score(ctx)` (clamped to 0..1) times `profile.weight(id)` (a behaviour weighted
## 0 is not scored). The best weighted score above 0 wins; ties go to the behaviour earlier in `TIE_ORDER`. A challenger
## replaces the behaviour in control only when its weighted score beats the current one's by more than
## `profile.stickiness`, or, within `profile.min_dwell_s` of the last switch, by more than `profile.emergency_margin`. A
## current behaviour that scores 0 has nothing to do (its target is gone) and hands over at once. When nothing scores above
## 0 the pilot falls back to idle (`AiProfile.validate` requires idle a weight above 0); it never hands control to a
## behaviour that scored 0. The behaviour that takes over gets `enter()`. No randomness and no clock in the
## selection itself: the same scores give the same choices; the behaviours' own randomness comes from seeds derived from
## the pilot's seed.
##
## The context (`context`) carries the orders and the wing (`AiContext`); the pilot refreshes its perception every tick.
## Temperament (M3-T13, Q12): the pilot flies `profile`, its `base_profile` scaled by `temperament` (skill and aggression,
## `AiTemperament.apply`); `set_temperament` changes them live and retunes every behaviour.
##
## Hit reaction (M3-T10, Q11): a fresh bolt hit (`Perception.last_bolt_hit_s` later than the last one reacted to) hands control
## to the evade behaviour after the pilot's reaction time (`AiTemperament.reaction_s`: an ace 0.1 s, a regular 0.25 s, a
## rookie 0.6 s), whatever the scores, the stickiness and the minimum dwell, and the evasion keeps control
## while `BehaviourEvade.locked()` (one full jink after the latest hit). A pilot without evade, or weighting it 0 (the
## instructor), never reacts.
##
## `wanted_target_id` follows the behaviour in control: the attack's target, `TARGET_NONE` for anything else, so the ship's
## targeting computer, and with it what other ships see as this ship's target, shows what it is really attacking. With
## `profile.fires` false the trigger is never pulled.
##
## Later tasks add behaviours with `add_behaviour` (formation T07, follow path T09, guard T10: `BehaviourGuard.attach`) and their fields to
## `AiContext`; the selection does not change.

const TIE_ORDER: Array[StringName] = [&"ram", &"retreat", &"evade", &"attack", &"guard", &"formation", &"rally", &"follow_path",
		&"idle"]

## The numbers it flies (the base profile scaled by the temperament), the profile it was given, and its skill and aggression.
var profile: AiProfile = null
var base_profile: AiProfile = null
var temperament: AiTemperament = null
var context: AiContext = AiContext.new()
## In `TIE_ORDER` (ids it does not list go after the listed ones, in the order added).
var behaviours: Array[AiBehaviour] = []
## The behaviour in control (null before the first tick), and seconds since it took over.
var current: AiBehaviour = null
var dwell_s: float = 0.0
## How many times control changed hands.
var switches: int = 0

# By behaviour index: the profile's weight (read when the behaviour is added), and this tick's score as the behaviour gave
# it (0..1) and weighted. Packed arrays: the selection runs for every AI ship every tick (AC13's budget).
var _weights: PackedFloat64Array = PackedFloat64Array()
var _raw: PackedFloat64Array = PackedFloat64Array()
var _weighted: PackedFloat64Array = PackedFloat64Array()
var _current_index: int = -1
var _idle_index: int = -1
var _evade_index: int = -1
## The latest bolt hit reacted to (sim time), so each hit interrupts once.
var _reacted_hit_s: float = -INF


## `p_behaviours` empty: the standard set (ram, retreat, evade, attack, idle) built from the profile, seeded from `p_seed`.
## `p_temperament` null: the profile's own skill and aggression.
func _init(p_profile: AiProfile = null, p_seed: int = 0, p_behaviours: Array[AiBehaviour] = [],
		p_temperament: AiTemperament = null) -> void:
	base_profile = p_profile if p_profile != null else AiProfile.new()
	temperament = p_temperament if p_temperament != null else AiTemperament.new(base_profile.skill, base_profile.aggression)
	profile = temperament.apply(base_profile)
	context.profile = profile
	wanted_target_id = TARGET_NONE
	var list: Array[AiBehaviour] = p_behaviours
	if list.is_empty():
		list = [BehaviourRam.new(hash([p_seed, "ram"])), BehaviourRetreat.new(profile), BehaviourEvade.new(hash([p_seed, "evade"])),
				BehaviourAttack.new(profile, hash([p_seed, "attack"])), BehaviourIdle.new(profile.idle_hold)]
	for b: AiBehaviour in list:
		add_behaviour(b)


## Adds a behaviour at its `TIE_ORDER` place, weighted by the profile's weight for its id as of now.
func add_behaviour(b: AiBehaviour) -> void:
	var rank: int = _rank(b.id)
	var at: int = behaviours.size()
	for i: int in behaviours.size():
		if _rank(behaviours[i].id) > rank:
			at = i
			break
	behaviours.insert(at, b)
	b.retune(profile, temperament)
	_weights.insert(at, profile.weight(b.id))
	_raw.insert(at, 0.0)
	_weighted.insert(at, 0.0)
	_current_index = behaviours.find(current)
	_idle_index = _index_of(&"idle")
	_evade_index = _index_of(&"evade")


## New skill and aggression: the effective profile is rebuilt from the base one, every behaviour retuned and reweighted.
func set_temperament(t: AiTemperament) -> void:
	temperament = t
	profile = t.apply(base_profile)
	context.profile = profile
	for i: int in behaviours.size():
		behaviours[i].retune(profile, t)
		_weights[i] = profile.weight(behaviours[i].id)


## The behaviour with this id, or null.
func behaviour(behaviour_id: StringName) -> AiBehaviour:
	for b: AiBehaviour in behaviours:
		if b.id == behaviour_id:
			return b
	return null


## This tick's weighted score of a behaviour (0 for an id it does not have).
func score_of(behaviour_id: StringName) -> float:
	var i: int = _index_of(behaviour_id)
	return _weighted[i] if i >= 0 else 0.0


## This tick's score of a behaviour as the behaviour gave it, before the weight.
func raw_score_of(behaviour_id: StringName) -> float:
	var i: int = _index_of(behaviour_id)
	return _raw[i] if i >= 0 else 0.0


func think(p: Perception, dt: float) -> PilotCommand:
	context.refresh(p)
	select(dt)
	if current == null:
		wanted_target_id = TARGET_NONE
		return PilotCommand.new()
	current.has_desired_velocity = false
	var cmd: PilotCommand = current.think(context, dt)
	desired_velocity = current.desired_velocity
	has_desired_velocity = current.has_desired_velocity
	desired_all_axes = current.desired_all_axes
	wanted_target_id = current.target_id()
	context.current_target_id = maxi(wanted_target_id, 0)
	var ram := current as BehaviourRam
	avoid_exempt_id = ram.target_id_value if ram != null and ram.committed else 0
	if not profile.fires:
		cmd.combat.fire = false
	return cmd


## No: the behaviours choose targets from the contacts.
func reads_target() -> bool:
	return false


## Scores every behaviour against `context` (already refreshed) and hands control over by the rule above. Returns the
## behaviour in control.
func select(dt: float) -> AiBehaviour:
	dwell_s += dt
	var best: int = -1
	var best_score: float = 0.0
	for i: int in behaviours.size():
		var weight: float = _weights[i]
		var raw: float = clampf(behaviours[i].score(context), 0.0, 1.0) if weight > 0.0 else 0.0
		var weighted: float = raw * weight
		_raw[i] = raw
		_weighted[i] = weighted
		if weighted > best_score:
			best_score = weighted
			best = i
	if _evade_index >= 0 and _weights[_evade_index] > 0.0:
		var evade := behaviours[_evade_index] as BehaviourEvade
		var hit_s: float = context.perception.last_bolt_hit_s
		var committed: bool = current != null and current.id == &"ram" and (current as BehaviourRam).committed
		if hit_s > _reacted_hit_s and not committed \
				and context.perception.now_s + dt - hit_s >= temperament.reaction_s() - 1e-6:  # by the end of this tick
			_reacted_hit_s = hit_s
			if _current_index != _evade_index:
				_switch(_evade_index)
			if evade != null:
				evade.on_hit()
			return current
		if _current_index == _evade_index and evade != null and evade.locked():
			return current
	if best < 0:
		# Nothing scores: idle, the fallback (no idle: the current behaviour keeps flying, or none does).
		if _idle_index >= 0 and _idle_index != _current_index:
			_switch(_idle_index)
		return current
	if best == _current_index:
		return current
	if _current_index < 0:
		_switch(best)
		return current
	var current_score: float = _weighted[_current_index]
	var lead_needed: float = profile.emergency_margin if dwell_s < profile.min_dwell_s else profile.stickiness
	if current_score <= 0.0 or best_score > current_score + lead_needed:
		_switch(best)
	return current


## `behaviour`, `state` (the current behaviour's), `for_s` (seconds in control), `scores` (weighted, by id in tie order),
## `objective` (when it has one, M3-T17), and the current behaviour's other fields (attack: `target`, `range_m`, `firing`).
func describe() -> Dictionary:
	var out: Dictionary = {"behaviour": String(current.id) if current != null else "none", "state": "none",
			"for_s": snappedf(dwell_s, 0.1) if current != null else 0.0}
	if current != null:
		var inner: Dictionary = current.describe()
		for key: Variant in inner:
			out[key] = inner[key]
	if not context.objective_name.is_empty():
		out["objective"] = context.objective_name
	var by_id: Dictionary = {}
	for i: int in behaviours.size():
		by_id[String(behaviours[i].id)] = snappedf(_weighted[i], 0.01)
	out["scores"] = by_id
	out["skill"] = "%s %.2f" % [AiTemperament.skill_name(temperament.skill), temperament.skill]
	out["aggression"] = "%s %.2f" % [AiTemperament.aggression_name(temperament.aggression), temperament.aggression]
	return out


func reset() -> void:
	current = null
	dwell_s = 0.0
	switches = 0
	_current_index = -1
	_reacted_hit_s = -INF
	avoid_exempt_id = 0
	_raw.fill(0.0)
	_weighted.fill(0.0)
	wanted_target_id = TARGET_NONE
	for b: AiBehaviour in behaviours:
		b.reset()


func _switch(index: int) -> void:
	_current_index = index
	current = behaviours[index]
	dwell_s = 0.0
	switches += 1
	current.enter()


func _index_of(behaviour_id: StringName) -> int:
	for i: int in behaviours.size():
		if behaviours[i].id == behaviour_id:
			return i
	return -1


static func _rank(behaviour_id: StringName) -> int:
	var i: int = TIE_ORDER.find(behaviour_id)
	return i if i >= 0 else TIE_ORDER.size()
