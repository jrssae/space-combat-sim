class_name AiPilot
extends PilotBrain
## The utility brain (architecture §16 D34): a set of `AiBehaviour`s that score themselves every tick, weighted by the
## pilot's `AiProfile`; the winner flies the ship. Behind the same `PilotBrain` interface as M2's brains, so the
## `AiPilotDriver`, its avoidance filter and the pool do not change.
##
## Selection, each tick: every behaviour's `score(ctx)` (clamped to 0..1) times `profile.weight(id)`. The best weighted
## score wins; ties go to the behaviour earlier in `TIE_ORDER`. A challenger replaces the behaviour in control only when
## its weighted score beats the current one's by more than `profile.stickiness`, or, within `profile.min_dwell_s` of the
## last switch, by more than `profile.emergency_margin`. A current behaviour that scores 0 has nothing to do (its target
## is gone) and hands over at once. The behaviour that takes over gets `enter()`. No randomness and no clock in the
## selection itself: the same scores give the same choices; the behaviours' own randomness comes from seeds derived from
## the pilot's seed.
##
## The context (`context`) carries the orders and the wing (`AiContext`); the pilot refreshes its perception every tick.
## `wanted_target_id` follows the behaviour in control (the attack's target), so the ship's targeting computer, and with it
## what other ships see as this ship's target, shows what it is really attacking. With `profile.fires` false the trigger is
## never pulled.
##
## Later tasks add behaviours with `add_behaviour` (formation T07, follow path T09, guard T10) and their fields to
## `AiContext`; the selection does not change.

const TIE_ORDER: Array[StringName] = [&"retreat", &"evade", &"attack", &"guard", &"formation", &"follow_path", &"idle"]

var profile: AiProfile = null
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


## `p_behaviours` empty: the standard set (retreat, evade, attack, idle) built from the profile, seeded from `p_seed`.
func _init(p_profile: AiProfile = null, p_seed: int = 0, p_behaviours: Array[AiBehaviour] = []) -> void:
	profile = p_profile if p_profile != null else AiProfile.new()
	context.profile = profile
	var list: Array[AiBehaviour] = p_behaviours
	if list.is_empty():
		list = [BehaviourRetreat.new(profile), BehaviourEvade.new(hash([p_seed, "evade"])),
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
	_weights.insert(at, profile.weight(b.id))
	_raw.insert(at, 0.0)
	_weighted.insert(at, 0.0)
	_current_index = behaviours.find(current)


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
		return PilotCommand.new()
	current.has_desired_velocity = false
	var cmd: PilotCommand = current.think(context, dt)
	desired_velocity = current.desired_velocity
	has_desired_velocity = current.has_desired_velocity
	wanted_target_id = current.target_id()
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
	var best_score: float = -INF
	for i: int in behaviours.size():
		var raw: float = clampf(behaviours[i].score(context), 0.0, 1.0)
		var weighted: float = raw * _weights[i]
		_raw[i] = raw
		_weighted[i] = weighted
		if weighted > best_score:
			best_score = weighted
			best = i
	if best < 0 or best == _current_index:
		return current
	if _current_index < 0:
		_switch(best)
		return current
	var current_score: float = _weighted[_current_index]
	var lead_needed: float = profile.emergency_margin if dwell_s < profile.min_dwell_s else profile.stickiness
	if (current_score <= 0.0 and best_score > 0.0) or best_score > current_score + lead_needed:
		_switch(best)
	return current


## `behaviour`, `state` (the current behaviour's), `for_s` (seconds in control), `scores` (weighted, by id in tie order),
## and the current behaviour's other fields (attack: `target`, `range_m`, `firing`).
func describe() -> Dictionary:
	var out: Dictionary = {"behaviour": String(current.id) if current != null else "none", "state": "none",
			"for_s": snappedf(dwell_s, 0.1) if current != null else 0.0}
	if current != null:
		var inner: Dictionary = current.describe()
		for key: Variant in inner:
			out[key] = inner[key]
	var by_id: Dictionary = {}
	for i: int in behaviours.size():
		by_id[String(behaviours[i].id)] = snappedf(_weighted[i], 0.01)
	out["scores"] = by_id
	return out


func reset() -> void:
	current = null
	dwell_s = 0.0
	switches = 0
	_current_index = -1
	_raw.fill(0.0)
	_weighted.fill(0.0)
	wanted_target_id = 0
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
