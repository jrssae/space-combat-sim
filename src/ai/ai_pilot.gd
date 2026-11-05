class_name AiPilot
extends PilotBrain
## The utility brain (architecture §16 D34): behaviours score themselves every tick, weighted by the pilot's `AiProfile`,
## and the winner flies the ship. Same `PilotBrain` interface as M2's brains, so the driver, avoidance and pool are unchanged.
##
## Selection: the best weighted score above 0 wins (ties go to the earlier `TIE_ORDER`; a behaviour weighted 0 is not
## scored). A challenger replaces the one in control only if it beats it by more than `profile.stickiness`, or within
## `profile.min_dwell_s` of the last switch, by more than `profile.emergency_margin`. A current behaviour scoring 0 (its
## target is gone) hands over at once. When nothing scores, the pilot idles. No randomness or clock in the selection.
##
## Temperament (M3-T13, Q12): the pilot flies `profile`, its `base_profile` scaled by `temperament` (skill, aggression).
##
## Hit reaction (M3-T10, Q11): a fresh bolt hit hands control to evade after the pilot's reaction time (ace 0.1 s, regular
## 0.25 s, rookie 0.6 s), whatever the scores, and evade keeps it while `BehaviourEvade.locked()`. A pilot without evade, or
## weighting it 0 (the instructor), never reacts.
##
## `wanted_target_id` follows the behaviour in control, so the targeting computer shows what the ship is really attacking.
## With `profile.fires` false the trigger is never pulled.
##
## Later tasks add behaviours with `add_behaviour` and fields to `AiContext`; the selection does not change.
##
## Native brains (M4-T17, architecture §17.13): with the perception on the rows (`Perception.brains`, the driver's native
## path) `try_think_native` runs the whole think in the native host (`ScsBrains`): the contacts picked from the core's rows,
## the context, the scoring, the behaviour in control and the driver's avoidance, one native call. This object keeps a slot
## there, made at the first native think from the base profile, the temperament and the behaviours (the driver's reset and
## any retune since replayed, so the seeded rolls stand where the GDScript's do), and mirrors what the game reads back:
## `current`, the scores, `wanted_target_id`, the wish, and the behaviour in control's own state (an evade's jinks, an
## attack's run, a route's progress), so wings, orders, the console and the tests see one pilot. The GDScript behaviours stay
## the reference and fly whenever the perception is not on the rows (a pilot with a scripted behaviour never goes native).

const TIE_ORDER: Array[StringName] = [&"ram", &"retreat", &"evade", &"attack", &"guard", &"formation", &"rally", &"follow_path",
		&"idle"]
## The classes a native brain stands in for, by `TIE_ORDER` place; a subclass or a test's scripted behaviour keeps the GDScript path.
const NATIVE_CLASSES: Array[StringName] = [&"BehaviourRam", &"BehaviourRetreat", &"BehaviourEvade", &"BehaviourAttack",
		&"BehaviourGuard", &"BehaviourFormation", &"BehaviourRally", &"BehaviourFollowPath", &"BehaviourIdle"]
## The native think's output (`ScsBrains.think`): the four levels, strafe, rot, brake, fire, the wanted target in two halves,
## the dodge flags, the wish, the behaviour in control, dwell, switches, the contacts seen, the raw and weighted scores by
## `TIE_ORDER` place, and the behaviour in control's mirrored state.
const NATIVE_MAIN_LEFT: int = 0
const NATIVE_STRAFE: int = 4
const NATIVE_ROT: int = 6
const NATIVE_BRAKE: int = 9
const NATIVE_FIRE: int = 10
const NATIVE_TARGET: int = 11
const NATIVE_AVOIDING: int = 13
const NATIVE_HAS_DESIRED: int = 15
const NATIVE_ALL_AXES: int = 16
const NATIVE_DESIRED: int = 17
const NATIVE_CURRENT: int = 20
const NATIVE_DWELL: int = 21
const NATIVE_SWITCHES: int = 22
const NATIVE_CONTACTS: int = 23
const NATIVE_RAW: int = 24
const NATIVE_WEIGHTED: int = 33
const NATIVE_MIRROR: int = 42
const NATIVE_OUT_LEN: int = 54

## `profile` is what it flies: `base_profile` scaled by `temperament`.
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

# Scores by behaviour index, in packed arrays: selection runs for every AI ship every tick (AC13's budget).
var _weights: PackedFloat64Array = PackedFloat64Array()
var _raw: PackedFloat64Array = PackedFloat64Array()
var _weighted: PackedFloat64Array = PackedFloat64Array()
var _current_index: int = -1
var _idle_index: int = -1
var _evade_index: int = -1
## The latest bolt hit reacted to (sim time), so each hit interrupts once.
var _reacted_hit_s: float = -INF
## The seed the behaviours roll from (M4-T17: the native slot rolls from the same).
var seed_value: int = 0
## Whether the last think ran in the native brains, and what the driver reads of it: the dodge and the contacts seen.
var native_last: bool = false
var native_avoiding: bool = false
var native_avoiding_urgent: bool = false
var native_contacts: int = 0
var _native: Object = null
var _slot: int = -1
var _native_ok: int = -1
var _bound_body: int = 0
var _out: PackedFloat64Array = PackedFloat64Array()
var _kind_index: PackedInt32Array = PackedInt32Array()
var _was_reset: bool = false
var _temperaments_since_reset: Array[Vector2] = []
var _ram_pushed: bool = false
var _had_wing: bool = false
var _pushed_wing: Array = []
var _pushed_objective: String = ""
var _pushed_guard: Array = []
var _pushed_route: Array = []
## The attack's target as the GDScript behaviour shows it on the native path: its id, nothing else.
var _mirror_target: Contact = Contact.new()


## No behaviours given: the standard set (ram, retreat, evade, attack, idle). No temperament: the profile's own.
func _init(p_profile: AiProfile = null, p_seed: int = 0, p_behaviours: Array[AiBehaviour] = [],
		p_temperament: AiTemperament = null) -> void:
	base_profile = p_profile if p_profile != null else AiProfile.new()
	seed_value = p_seed
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
	_native_ok = -1
	_kind_index.resize(TIE_ORDER.size())
	for k: int in TIE_ORDER.size():
		_kind_index[k] = _index_of(TIE_ORDER[k])
	if _slot >= 0 and is_instance_valid(_native):
		var kind: int = native_kind_of(b)
		if kind >= 0:
			_native.add_behaviour(_slot, kind)
		else:
			_native_ok = 0


## Changes skill and aggression live and retunes every behaviour.
func set_temperament(t: AiTemperament) -> void:
	temperament = t
	profile = t.apply(base_profile)
	context.profile = profile
	for i: int in behaviours.size():
		behaviours[i].retune(profile, t)
		_weights[i] = profile.weight(behaviours[i].id)
	_temperaments_since_reset.append(Vector2(t.skill, t.aggression))
	if _slot >= 0 and is_instance_valid(_native):
		_native.set_temperament(_slot, t.skill, t.aggression)


## The behaviour with this id, or null.
func behaviour(behaviour_id: StringName) -> AiBehaviour:
	for b: AiBehaviour in behaviours:
		if b.id == behaviour_id:
			return b
	return null


## This tick's weighted score of a behaviour (0 for an id it does not have).
func score_of(behaviour_id: StringName) -> float:
	if native_last:
		var k: int = TIE_ORDER.find(behaviour_id)
		return _out[NATIVE_WEIGHTED + k] if k >= 0 and _index_of(behaviour_id) >= 0 else 0.0
	var i: int = _index_of(behaviour_id)
	return _weighted[i] if i >= 0 else 0.0


## This tick's score of a behaviour as the behaviour gave it, before the weight.
func raw_score_of(behaviour_id: StringName) -> float:
	if native_last:
		var k: int = TIE_ORDER.find(behaviour_id)
		return _out[NATIVE_RAW + k] if k >= 0 and _index_of(behaviour_id) >= 0 else 0.0
	var i: int = _index_of(behaviour_id)
	return _raw[i] if i >= 0 else 0.0


func think(p: Perception, dt: float) -> PilotCommand:
	if p.brains != null:
		var native: PilotCommand = try_think_native(p, dt)
		if native != null:
			return native
	native_last = false
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
	if current.id == &"attack" and wanted_target_id > 0:
		context.attack_target_id = wanted_target_id
	var ram := current as BehaviourRam
	avoid_exempt_id = ram.target_id_value if ram != null and ram.committed else 0
	if not profile.fires:
		cmd.combat.fire = false
	return cmd


## No: the behaviours choose targets from the contacts.
func reads_target() -> bool:
	return false


## Its wing, leader, targets and route pace ship stay in its contacts beyond the nearest k (`AiContext.keep_ids`).
func keep_ids() -> PackedInt64Array:
	var ids: PackedInt64Array = context.keep_ids()
	if wanted_target_id > 0:
		ids.append(wanted_target_id)
	return ids


## The objective and the guarded ship, by name (`AiContext.keep_names`).
func keep_names() -> PackedStringArray:
	return context.keep_names()


## Scores the behaviours and hands control over by the rule above. Returns the behaviour in control.
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
		# Nothing scores: idle is the fallback.
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
	var out: Dictionary
	if native_last and _slot >= 0 and is_instance_valid(_native):
		out = _native.describe(_slot)
	else:
		out = {"behaviour": String(current.id) if current != null else "none", "state": "none",
				"for_s": snappedf(dwell_s, 0.1) if current != null else 0.0}
		if current != null:
			var inner: Dictionary = current.describe()
			for key: Variant in inner:
				out[key] = inner[key]
		var by_id: Dictionary = {}
		for i: int in behaviours.size():
			by_id[String(behaviours[i].id)] = snappedf(_weighted[i], 0.01)
		out["scores"] = by_id
	if not context.objective_name.is_empty():
		out["objective"] = context.objective_name
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
	native_last = false
	_was_reset = true
	_temperaments_since_reset.clear()
	_ram_pushed = false
	if _slot >= 0 and is_instance_valid(_native):
		_native.reset(_slot)


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


# --- the native brains (M4-T17) ------------------------------------------------------------------------------------------


## Whether a native brain can stand in for this pilot: every behaviour is one of the nine, unsubclassed.
func native_capable() -> bool:
	if _native_ok < 0:
		_native_ok = 1
		for b: AiBehaviour in behaviours:
			if native_kind_of(b) < 0:
				_native_ok = 0
	return _native_ok == 1


## The `TIE_ORDER` place of a behaviour a native brain stands in for, by its class, or -1 for any other.
static func native_kind_of(b: AiBehaviour) -> int:
	var script: Script = b.get_script()
	var kind: int = NATIVE_CLASSES.find(script.get_global_name()) if script != null else -1
	return kind if kind >= 0 and b.id == TIE_ORDER[kind] else -1


## The native think: the command from the host (`Perception.brains`), with this pilot's state mirrored; null when the host
## declines (no slot, no row for the ship this tick), and then nothing has changed and the GDScript think may run.
func try_think_native(p: Perception, dt: float) -> PilotCommand:
	var host: Object = p.brains
	if host == null or not native_capable():
		return null
	if host != _native:
		_native = host
		_slot = -1
	if _slot < 0:
		_slot = host.create(seed_value, native_profile(base_profile), native_tactics(base_profile.tactics), native_kinds(behaviours),
				temperament.skill, temperament.aggression)
		if _slot < 0:
			_native_ok = 0
			return null
		# The slot stands where the GDScript objects stand: the driver's reset and the retunes since, in order.
		if _was_reset:
			host.reset(_slot)
			for t: Vector2 in _temperaments_since_reset:
				host.set_temperament(_slot, t.x, t.y)
		_bound_body = 0
		_pushed_wing = []
		_pushed_objective = ""
		_pushed_guard = []
		_pushed_route = []
		_had_wing = false
		_ram_pushed = false
		context.native_host = host
		context.native_slot = _slot
		native_push_context(host, _slot, context)
	if _bound_body != p.own_body_id:
		host.bind_ship(_slot, native_capability(p.capability), p.muzzle_local, p.muzzle_speed_mps, p.weapon_lifetime_s,
				p.bounding_radius, p.tie_hash, p.own_body_id, p.self_id)
		_bound_body = p.own_body_id
	_sync_context(host)
	var ram := _behaviour_of(&"ram") as BehaviourRam
	if ram != null and ram.committed and not _ram_pushed:
		host.ram_commit(_slot, ram.target_id_value)  # committed from outside with no slot yet: the slot follows
	var out: PackedFloat64Array = host.think(_slot, p.relation_row, p.now_s, dt, p.hull_fraction, p.selected_id, p.last_hit_s,
			p.last_bolt_hit_s, p.last_attacker_id, p.friendly_fire, p.frame_origin.x, p.frame_origin.y, p.frame_origin.z)
	if out.size() != NATIVE_OUT_LEN:
		return null
	_out = out
	native_last = true
	var cmd := PilotCommand.new()
	cmd.flight.main_left = out[NATIVE_MAIN_LEFT]
	cmd.flight.main_right = out[NATIVE_MAIN_LEFT + 1]
	cmd.flight.retro_left = out[NATIVE_MAIN_LEFT + 2]
	cmd.flight.retro_right = out[NATIVE_MAIN_LEFT + 3]
	cmd.flight.strafe = Vector2(out[NATIVE_STRAFE], out[NATIVE_STRAFE + 1])
	cmd.flight.rot = Vector3(out[NATIVE_ROT], out[NATIVE_ROT + 1], out[NATIVE_ROT + 2])
	cmd.flight.brake = out[NATIVE_BRAKE] != 0.0
	cmd.combat.fire = out[NATIVE_FIRE] != 0.0
	wanted_target_id = native_target_id(out)
	context.current_target_id = maxi(wanted_target_id, 0)
	native_avoiding = out[NATIVE_AVOIDING] != 0.0
	native_avoiding_urgent = out[NATIVE_AVOIDING + 1] != 0.0
	has_desired_velocity = out[NATIVE_HAS_DESIRED] != 0.0
	desired_all_axes = out[NATIVE_ALL_AXES] != 0.0
	desired_velocity = Vector3(out[NATIVE_DESIRED], out[NATIVE_DESIRED + 1], out[NATIVE_DESIRED + 2])
	dwell_s = out[NATIVE_DWELL]
	switches = int(out[NATIVE_SWITCHES])
	native_contacts = int(out[NATIVE_CONTACTS])
	var kind: int = int(out[NATIVE_CURRENT])
	_current_index = _kind_index[kind] if kind >= 0 else -1
	current = behaviours[_current_index] if _current_index >= 0 else null
	if current != null and current.id == &"attack" and wanted_target_id > 0:
		context.attack_target_id = wanted_target_id
	_mirror(kind, out)
	return cmd


# Writes the behaviour in control's native state into its GDScript object, so what the game reads of it is current.
func _mirror(kind: int, out: PackedFloat64Array) -> void:
	var m: int = NATIVE_MIRROR
	match kind:
		3:
			var a := current as BehaviourAttack
			if wanted_target_id > 0:
				_mirror_target.id = wanted_target_id
				a._target = _mirror_target
			else:
				a._target = null
			a.uses_slash = out[m] != 0.0
			a.brain.state = int(out[m + 1]) as AttackBrain.State
			a.brain.firing = out[m + 2] != 0.0
			a.brain.on_target_s = out[m + 3]
			a.brain.state_time_s = out[m + 4]
			a.slash.state = int(out[m + 5]) as AttackSlash.State
			a.slash.firing = out[m + 6] != 0.0
			a.slash.in_gate = out[m + 7] != 0.0
			a.slash.passes = int(out[m + 8])
			a.slash.time_on_target_s = out[m + 9]
			a.slash.state_time_s = out[m + 10]
		2:
			var e := current as BehaviourEvade
			e.jinks = int(out[m])
			e.jink_left_s = out[m + 1]
			e._lock_until_jinks = int(out[m + 2])
		0:
			var r := current as BehaviourRam
			r.committed = out[m] != 0.0
			r.rolls = int(out[m + 1])
			r.max_friends_seen = int(out[m + 2])
			r.target_id_value = _join_id(out[m + 3], out[m + 4])
			_ram_pushed = r.committed
			avoid_exempt_id = r.target_id_value if r.committed else 0
		5:
			(current as BehaviourFormation).slot_error_m = out[m]
		4:
			(current as BehaviourGuard).post_error_m = out[m]
		7:
			var f := current as BehaviourFollowPath
			f.index = int(out[m])
			f.phase = int(out[m + 1]) as BehaviourFollowPath.Phase
			f.lag_m = out[m + 2]
			if int(out[m + 3]) != f.visited.size():
				f.visited = _native.path_visited(_slot)
			if int(out[m + 4]) != f.results.size():
				f.results.assign(_native.path_results(_slot))
			f._hold_left_s = out[m + 5]
	if kind != 0:
		avoid_exempt_id = 0


# Pushes the context's wing, objective, guard and route to the slot when any of them changed since the last push.
func _sync_context(host: Object) -> void:
	var c: AiContext = context
	var in_wing: bool = c.has_slot or c.leader_id != 0 or not c.wing_ids.is_empty() or c.order != AiContext.Order.ENGAGE_AT_WILL
	if in_wing or _had_wing:
		var link: UniversePos = c.leader_link_position
		var now: Array = [c.order, c.leader_id, c.leader_target_id, c.engage_radius_m, c.has_slot, c.slot_offset, c.wing_ids,
				link != null, link.x if link != null else 0.0, link.y if link != null else 0.0, link.z if link != null else 0.0,
				c.leader_link_velocity]
		if now != _pushed_wing:
			_pushed_wing = now.duplicate()
			_pushed_wing[6] = c.wing_ids.duplicate()
			host.set_wing(_slot, c.order, c.leader_id, c.leader_target_id, c.engage_radius_m, c.has_slot, c.slot_offset, c.wing_ids,
					link != null, now[8], now[9], now[10], c.leader_link_velocity)
		_had_wing = in_wing
	if c.objective_name != _pushed_objective:
		_pushed_objective = c.objective_name
		host.set_objective(_slot, c.objective_name)
	var guard: Array = [c.guard_post, c.guard_name, c.guard_offset, c.guard_radius_m]
	if guard != _pushed_guard:
		_pushed_guard = guard
		_push_guard(host, _slot, c)
	var route: Array = [c.route, c.route.count() if c.route != null else 0, c.route.pace_id if c.route != null else 0,
			c.route.cruise_mps if c.route != null else 0.0, c.route.loop if c.route != null else false,
			c.route.yield_to_attack if c.route != null else false]
	if route != _pushed_route:
		_pushed_route = route
		_push_route(host, _slot, c.route)


func _behaviour_of(behaviour_id: StringName) -> AiBehaviour:
	var i: int = _index_of(behaviour_id)
	return behaviours[i] if i >= 0 else null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _slot >= 0 and is_instance_valid(_native):
		_native.free_slot(_slot)
		_slot = -1
		if context != null:
			context.native_host = null
			context.native_slot = -1


## `AiProfile` as the host takes it: the nine weights by `TIE_ORDER`, then stickiness, emergency_margin, min_dwell_s,
## retreat_below, retreat_within_m, cruise_mps, aim_error_deg, fires, slashing, idle_hold.
static func native_profile(p: AiProfile) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for id: StringName in TIE_ORDER:
		out.append(p.weight(id))
	out.append_array([p.stickiness, p.emergency_margin, p.min_dwell_s, p.retreat_below, p.retreat_within_m, p.cruise_mps,
			p.aim_error_deg, 1.0 if p.fires else 0.0, 1.0 if p.slashing else 0.0, 1.0 if p.idle_hold else 0.0])
	return out


## `RaiderTactics` as the host takes it, in field order.
static func native_tactics(t: RaiderTactics) -> PackedFloat64Array:
	return PackedFloat64Array([t.closing_far_mps, t.closing_near_mps, t.near_range_m, t.face_lead_delta_v_mps, t.fire_range_m,
			t.fire_cone_deg, t.fire_miss_m, t.break_range_m, t.max_time_on_target_s, t.break_speed_mps, t.break_duration_s,
			t.extend_min_s, t.extend_range_m, t.max_speed_mps])


## The behaviours as kinds (`TIE_ORDER` places), in their order.
static func native_kinds(list: Array[AiBehaviour]) -> PackedByteArray:
	var out := PackedByteArray()
	for b: AiBehaviour in list:
		out.append(TIE_ORDER.find(b.id))
	return out


## `ShipCapability` as the host takes it: a_main, a_retro, a_rcs x and y, the rate maxima, the angular acceleration maxima.
static func native_capability(cap: ShipCapability) -> PackedFloat64Array:
	return PackedFloat64Array([cap.a_main, cap.a_retro, cap.a_rcs.x, cap.a_rcs.y, cap.rate_max_rad.x, cap.rate_max_rad.y,
			cap.rate_max_rad.z, cap.alpha_max_rad.x, cap.alpha_max_rad.y, cap.alpha_max_rad.z])


## The wanted target out of a native think: `TARGET_NONE`, or the id from its two halves.
static func native_target_id(out: PackedFloat64Array) -> int:
	return _join_id(out[NATIVE_TARGET], out[NATIVE_TARGET + 1])


static func _join_id(hi: float, lo: float) -> int:
	if hi < 0.0:
		return TARGET_NONE
	return (int(hi) << 32) | int(lo)


## Pushes everything of `ctx` the slot keeps: the wing, the objective, the guard post and the route.
static func native_push_context(host: Object, slot: int, ctx: AiContext) -> void:
	var link: UniversePos = ctx.leader_link_position
	host.set_wing(slot, ctx.order, ctx.leader_id, ctx.leader_target_id, ctx.engage_radius_m, ctx.has_slot, ctx.slot_offset,
			ctx.wing_ids, link != null, link.x if link != null else 0.0, link.y if link != null else 0.0,
			link.z if link != null else 0.0, ctx.leader_link_velocity)
	host.set_objective(slot, ctx.objective_name)
	_push_guard(host, slot, ctx)
	_push_route(host, slot, ctx.route)


static func _push_guard(host: Object, slot: int, ctx: AiContext) -> void:
	var post: UniversePos = ctx.guard_post
	host.set_guard(slot, post != null, post.x if post != null else 0.0, post.y if post != null else 0.0,
			post.z if post != null else 0.0, ctx.guard_name, ctx.guard_offset, ctx.guard_radius_m)


static func _push_route(host: Object, slot: int, route: Route) -> void:
	if route == null:
		host.clear_route(slot)
		return
	var points := PackedFloat64Array()
	var demos := PackedByteArray()
	for i: int in route.count():
		var w: Route.Waypoint = route.waypoint(i)
		points.append_array([w.position.x, w.position.y, w.position.z, w.hold_s])
		demos.append(Manoeuvres.NAMES.find(w.demo) + 1 if w.demo != &"" else 0)
	host.set_route(slot, points, demos, route.cruise_mps, route.pace_id, route.loop, route.yield_to_attack)
