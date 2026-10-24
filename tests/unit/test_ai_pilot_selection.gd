extends GutTest
## AiPilot selection (M3-T06, AC8, architecture §16 D34) on scripted `AiContext`s: no ship, no physics. Scripted behaviours
## with set scores test the selection rule (weighted score, stickiness, minimum dwell, emergency margin, tie order); the
## real behaviours test order gating, `describe()`, the scores of evade, retreat and idle, attack's target choice and aim
## wander, and that the same seed makes the same choices.

const DT: float = 1.0 / 60.0

var profile: AiProfile


## A behaviour whose score the test sets.
class Scripted extends AiBehaviour:
	var value: float = 0.0
	var entered: int = 0
	var thought: int = 0

	func _init(p_id: StringName, p_value: float = 0.0) -> void:
		id = p_id
		value = p_value

	func score(_ctx: AiContext) -> float:
		return value

	func think(_ctx: AiContext, _dt: float) -> PilotCommand:
		thought += 1
		return PilotCommand.new()

	func enter() -> void:
		entered += 1

	func describe() -> Dictionary:
		return {"state": "scripted"}


## Counts how often it was asked for a score.
class CountingScore extends AiBehaviour:
	var asked: int = 0

	func _init(p_id: StringName) -> void:
		id = p_id

	func score(_ctx: AiContext) -> float:
		asked += 1
		return 0.1


func before_each() -> void:
	profile = _profile({&"attack": 1.0, &"evade": 1.0, &"retreat": 1.0, &"idle": 1.0})


func _profile(weights: Dictionary) -> AiProfile:
	var pr := AiProfile.new()
	for key: Variant in weights:
		pr.weights[StringName(key)] = float(weights[key])
	pr.tactics = load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	pr.retreat_below = 0.25
	pr.cruise_mps = 100.0
	return pr


func _capability() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 15.0
	cap.a_rcs = Vector2(10.0, 10.0)
	cap.rate_max_rad = Vector3(1.0, 1.0, 1.5)
	return cap


## A perception of a ship at the origin, nose -Z, at rest, with these contacts.
func _p(contacts: Array[Contact] = [], hull: float = 1.0) -> Perception:
	var p := Perception.new()
	p.faction = Factions.EARTH_ALLIANCE
	p.capability = _capability()
	p.muzzle_speed_mps = 1000.0
	p.hull_fraction = hull
	p.contacts = contacts
	p.self_id = 1
	return p


func _contact(id: int, contact_name: String, relation: Factions.Relation, at: Vector3, forward: Vector3 = Vector3.FORWARD,
		velocity: Vector3 = Vector3.ZERO, target_id: int = -1, hull: float = 1.0) -> Contact:
	var c := Contact.new()
	c.id = id
	c.name = contact_name
	c.relation = relation
	c.faction = Factions.RAIDERS if relation == Factions.Relation.HOSTILE else Factions.EARTH_ALLIANCE
	c.position = at
	c.velocity = velocity
	c.forward = forward.normalized()
	c.bounding_radius = 8.0
	c.is_ship = true
	c.hull_fraction = hull
	c.target_id = target_id
	return c


func _scripted_pilot(behaviours: Array[AiBehaviour]) -> AiPilot:
	return AiPilot.new(profile, 1, behaviours)


func _tick(pilot: AiPilot, p: Perception, seconds: float = DT) -> PilotCommand:
	var cmd: PilotCommand = null
	for i: int in maxi(1, roundi(seconds / DT)):
		cmd = pilot.think(p, DT)
	return cmd


# --- the selection rule ------------------------------------------------------------------------------------------


func test_the_highest_weighted_score_wins() -> void:
	var a := Scripted.new(&"attack", 0.5)
	var b := Scripted.new(&"evade", 0.8)
	var pilot := _scripted_pilot([a, b])
	_tick(pilot, _p())
	assert_eq(pilot.current, b)
	assert_eq(b.thought, 1, "only the current behaviour thinks")
	assert_eq(a.thought, 0)
	profile.weights[&"evade"] = 0.5  # 0.8 x 0.5 = 0.4 < 0.5
	var again := _scripted_pilot([Scripted.new(&"attack", 0.5), Scripted.new(&"evade", 0.8)])
	_tick(again, _p())
	assert_eq(again.current.id, &"attack", "the weight multiplies the score")
	assert_almost_eq(again.score_of(&"evade"), 0.4, 1e-6)
	assert_almost_eq(again.raw_score_of(&"evade"), 0.8, 1e-6)


func test_the_current_behaviour_keeps_a_stickiness_bonus() -> void:
	var a := Scripted.new(&"attack", 0.5)
	var b := Scripted.new(&"evade", 0.0)
	var pilot := _scripted_pilot([a, b])
	_tick(pilot, _p(), 2.0)  # long past the dwell
	b.value = 0.5 + profile.stickiness - 0.01
	_tick(pilot, _p(), 0.5)
	assert_eq(pilot.current, a, "a challenger inside the stickiness bonus does not take over")
	b.value = 0.5 + profile.stickiness + 0.01
	_tick(pilot, _p())
	assert_eq(pilot.current, b, "one that beats it does")
	assert_eq(b.entered, 1, "enter() on the switch")


func test_the_current_behaviour_keeps_control_for_the_minimum_dwell() -> void:
	var a := Scripted.new(&"attack", 0.9)
	var b := Scripted.new(&"evade", 0.2)
	var pilot := _scripted_pilot([a, b])
	_tick(pilot, _p())
	assert_eq(pilot.current, a)
	# Beats stickiness (0.15) but not the emergency margin (0.4): it must wait out the dwell.
	a.value = 0.2
	b.value = 0.2 + profile.stickiness + 0.1
	_tick(pilot, _p(), profile.min_dwell_s - 0.1)
	assert_eq(pilot.current, a, "inside the dwell")
	_tick(pilot, _p(), 0.2)
	assert_eq(pilot.current, b, "after the dwell")


func test_an_emergency_challenger_takes_over_inside_the_dwell() -> void:
	var a := Scripted.new(&"attack", 0.9)
	var b := Scripted.new(&"evade", 0.0)
	var pilot := _scripted_pilot([a, b])
	_tick(pilot, _p())
	a.value = 0.3
	b.value = 0.3 + profile.emergency_margin - 0.01
	_tick(pilot, _p())
	assert_eq(pilot.current, a, "just short of the emergency margin")
	b.value = 0.3 + profile.emergency_margin + 0.01
	_tick(pilot, _p())
	assert_eq(pilot.current, b, "past it: at once")


func test_ties_break_by_the_fixed_behaviour_order_not_by_insertion() -> void:
	var pilot := _scripted_pilot([Scripted.new(&"idle", 0.5), Scripted.new(&"attack", 0.5), Scripted.new(&"evade", 0.5),
			Scripted.new(&"retreat", 0.5)])
	_tick(pilot, _p())
	assert_eq(pilot.current.id, &"retreat")
	var ids: Array[StringName] = []
	for b: AiBehaviour in pilot.behaviours:
		ids.append(b.id)
	assert_eq(ids, [&"retreat", &"evade", &"attack", &"idle"] as Array[StringName], "kept in AiPilot.TIE_ORDER")


func test_a_behaviour_that_scores_nothing_gives_up_control_at_once() -> void:
	var a := Scripted.new(&"attack", 0.9)
	var idle := Scripted.new(&"idle", 0.05)
	var pilot := _scripted_pilot([a, idle])
	_tick(pilot, _p())
	a.value = 0.0  # its target is gone: nothing to do, dwell or not
	_tick(pilot, _p())
	assert_eq(pilot.current, idle)


func test_the_selection_is_deterministic() -> void:
	var values: Array[float] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in 600:
		values.append(rng.randf())
	var runs: Array = []
	for run: int in 2:
		var a := Scripted.new(&"attack")
		var b := Scripted.new(&"evade")
		var pilot := _scripted_pilot([a, b])
		var picks: Array[StringName] = []
		for i: int in values.size():
			a.value = values[i]
			b.value = 1.0 - values[i]
			_tick(pilot, _p())
			picks.append(pilot.current.id)
		runs.append(picks)
	assert_eq(runs[0], runs[1])


# --- the real behaviours -----------------------------------------------------------------------------------------


func test_a_default_pilot_has_retreat_evade_attack_and_idle() -> void:
	var pilot := AiPilot.new(profile, 3)
	var ids: Array[StringName] = []
	for b: AiBehaviour in pilot.behaviours:
		ids.append(b.id)
	assert_eq(ids, [&"retreat", &"evade", &"attack", &"idle"] as Array[StringName])
	_tick(pilot, _p())
	assert_eq(pilot.current.id, &"idle", "nothing around: the 0.05 fallback")
	assert_almost_eq(pilot.score_of(&"idle"), BehaviourIdle.SCORE, 1e-6)


func test_with_a_hostile_in_sight_it_attacks_and_wants_it_selected() -> void:
	var raider := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -1500.0), Vector3.BACK)
	var pilot := AiPilot.new(profile, 3)
	_tick(pilot, _p([raider]))
	assert_eq(pilot.current.id, &"attack")
	assert_eq(pilot.wanted_target_id, 20, "the driver selects the attack's target")


func test_describe_names_the_behaviour_its_state_and_every_score() -> void:
	var raider := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -1500.0), Vector3.BACK)
	var pilot := AiPilot.new(profile, 3)
	assert_eq(pilot.describe()["behaviour"], "none", "before the first tick")
	_tick(pilot, _p([raider]))
	var d: Dictionary = pilot.describe()
	assert_eq(d["behaviour"], "attack")
	assert_eq(d["state"], "approach")
	assert_eq(d["target"], "RAIDER 1")
	var scores: Dictionary = d["scores"]
	assert_eq(scores.keys(), ["retreat", "evade", "attack", "idle"])
	assert_gt(float(scores["attack"]), float(scores["idle"]))


func test_form_on_me_never_attacks() -> void:
	var raider := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -300.0), Vector3.BACK, Vector3.ZERO, 1)
	var pilot := AiPilot.new(profile, 3)
	pilot.context.order = AiContext.Order.FORM_ON_ME
	for i: int in 120:
		_tick(pilot, _p([raider]))
		assert_ne(pilot.current.id, &"attack")
		assert_eq(pilot.score_of(&"attack"), 0.0)


func test_attack_my_target_attacks_only_the_leaders_target() -> void:
	var near := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -400.0), Vector3.BACK, Vector3.ZERO, 1)
	var leaders := _contact(21, "RAIDER 2", Factions.Relation.HOSTILE, Vector3(2500.0, 0.0, -2500.0))
	var pilot := AiPilot.new(profile, 3)
	pilot.context.order = AiContext.Order.ATTACK_MY_TARGET
	pilot.context.leader_target_id = 21
	_tick(pilot, _p([near, leaders]))
	assert_eq(pilot.current.id, &"attack")
	assert_eq(pilot.wanted_target_id, 21, "the leader's target, not the nearer one attacking us")
	pilot.context.leader_target_id = 0
	_tick(pilot, _p([near, leaders]))
	assert_eq(pilot.score_of(&"attack"), 0.0, "no leader's target: no attack")


func test_cover_me_attacks_only_near_the_leader_or_at_whoever_attacks_it() -> void:
	var leader := _contact(30, "ALPHA 1", Factions.Relation.FRIENDLY, Vector3(0.0, 0.0, 100.0))
	var far := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -3000.0))
	var pilot := AiPilot.new(profile, 3)
	pilot.context.order = AiContext.Order.COVER_ME
	pilot.context.leader_id = 30
	_tick(pilot, _p([leader, far]))
	assert_eq(pilot.score_of(&"attack"), 0.0, "3 km from the leader, attacking nobody")
	var attacker := _contact(22, "RAIDER 3", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -3500.0), Vector3.BACK,
			Vector3.ZERO, 30)
	_tick(pilot, _p([leader, far, attacker]))
	assert_eq(pilot.wanted_target_id, 22, "the one attacking the leader")
	var close := _contact(23, "RAIDER 4", Factions.Relation.HOSTILE, Vector3(500.0, 0.0, 600.0))
	assert_true(pilot.context.may_attack(close), "within engage_radius_m of the leader")
	assert_false(pilot.context.may_attack(far))


func test_engage_at_will_is_the_default_order() -> void:
	assert_eq(AiPilot.new(profile, 3).context.order, AiContext.Order.ENGAGE_AT_WILL)
	assert_eq(AiContext.order_from_word("cover"), AiContext.Order.COVER_ME)
	assert_eq(AiContext.order_from_word("attack"), AiContext.Order.ATTACK_MY_TARGET)
	assert_eq(AiContext.order_from_word("dance"), -1)


func test_attack_prefers_a_hostile_attacking_a_friend_then_the_nearer_and_the_damaged() -> void:
	var ally := _contact(40, "ALPHA 3", Factions.Relation.FRIENDLY, Vector3(800.0, 0.0, 0.0))
	var near := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -900.0))
	var on_ally := _contact(21, "RAIDER 2", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -1600.0), Vector3.FORWARD,
			Vector3.ZERO, 40)
	var attack := BehaviourAttack.new(profile, 1)
	var ctx := AiContext.new()
	ctx.profile = profile
	ctx.refresh(_p([ally, near, on_ally]))
	attack.score(ctx)
	assert_eq(attack.target_id(), 21, "attacking a friend outweighs a few hundred metres")
	ctx.refresh(_p([ally, near]))
	attack.score(ctx)
	assert_eq(attack.target_id(), 20)
	var damaged := _contact(22, "RAIDER 3", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -950.0), Vector3.FORWARD,
			Vector3.ZERO, -1, 0.2)
	var fresh := BehaviourAttack.new(profile, 1)
	ctx.refresh(_p([near, damaged]))
	fresh.score(ctx)
	assert_eq(fresh.target_id(), 22, "the damaged one at about the same range")


func test_aim_error_is_a_slow_seeded_wander_within_the_profiles_bound() -> void:
	profile.aim_error_deg = 0.5
	var a := BehaviourAttack.new(profile, 11)
	var b := BehaviourAttack.new(profile, 11)
	var c := BehaviourAttack.new(profile, 12)
	var bound: float = deg_to_rad(profile.aim_error_deg) * sqrt(2.0) + 1e-9
	var biggest_step: float = 0.0
	var differs: bool = false
	var previous: Vector2 = a.aim_offset_at(0.0)
	for i: int in 1200:
		var t: float = float(i) * DT
		var offset: Vector2 = a.aim_offset_at(t)
		assert_eq(offset, b.aim_offset_at(t), "same seed, same offset")
		differs = differs or offset != c.aim_offset_at(t)
		assert_lt(offset.length(), bound)
		biggest_step = maxf(biggest_step, offset.distance_to(previous))
		previous = offset
	assert_true(differs, "another seed wanders elsewhere")
	assert_lt(biggest_step, deg_to_rad(profile.aim_error_deg) * 0.05, "under 5 % of the bound per tick: not per-tick noise")
	profile.aim_error_deg = 0.0
	assert_eq(BehaviourAttack.new(profile, 11).aim_offset_at(3.0), Vector2.ZERO)


func test_evade_scores_a_hostile_on_our_tail_pointing_at_us() -> void:
	var evade := BehaviourEvade.new(1)
	var ctx := AiContext.new()
	ctx.profile = profile
	# Behind us (the nose is -Z, so +Z is behind) at 800 m, its nose on us.
	ctx.refresh(_p([_contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, 800.0), Vector3.FORWARD)]))
	assert_gt(evade.score(ctx), 0.0, "on our tail")
	assert_eq(evade.threat_name(), "RAIDER 1")
	var off: Vector3 = Basis(Vector3.UP, deg_to_rad(BehaviourEvade.NOSE_CONE_DEG + 3.0)) * Vector3.FORWARD
	ctx.refresh(_p([_contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, 800.0), off)]))
	assert_eq(evade.score(ctx), 0.0, "its nose 18 degrees off us")
	ctx.refresh(_p([_contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -800.0), Vector3.BACK)]))
	assert_eq(evade.score(ctx), 0.0, "ahead of us: not the rear hemisphere")
	ctx.refresh(_p([_contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, BehaviourEvade.RANGE_M + 50.0),
			Vector3.FORWARD)]))
	assert_eq(evade.score(ctx), 0.0, "beyond 1.2 km")
	ctx.refresh(_p([_contact(20, "ALPHA 2", Factions.Relation.FRIENDLY, Vector3(0.0, 0.0, 300.0), Vector3.FORWARD)]))
	assert_eq(evade.score(ctx), 0.0, "a friend on our tail is no threat")


func test_evade_scores_incoming_fire_and_a_recent_hit() -> void:
	var evade := BehaviourEvade.new(1)
	var ctx := AiContext.new()
	ctx.profile = profile
	var p := _p([_contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -1500.0), Vector3.BACK)])
	ctx.refresh(p)
	assert_eq(evade.score(ctx), 0.0, "nothing yet")
	p.incoming_fire = 2
	ctx.refresh(p)
	assert_gt(evade.score(ctx), 0.0, "bolts about to pass close")
	assert_eq(evade.threat_name(), "RAIDER 1", "the shooter: the hostile pointing at us")
	p.incoming_fire = 0
	p.now_s = 100.0
	p.last_hit_s = 98.5
	ctx.refresh(p)
	assert_gt(evade.score(ctx), 0.0, "hit 1.5 s ago")
	p.last_hit_s = 97.5
	ctx.refresh(p)
	assert_eq(evade.score(ctx), 0.0, "hit 2.5 s ago")


func test_an_evading_pilot_jinks_across_the_line_of_fire_and_reverses() -> void:
	var tail := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, 600.0), Vector3.FORWARD)
	var pilot := AiPilot.new(profile, 9)
	var p := _p([tail])
	_tick(pilot, p)
	assert_eq(pilot.current.id, &"evade", "a tail threat outranks attacking it")
	var evade := pilot.current as BehaviourEvade
	var first: Vector3 = evade.side
	assert_almost_eq(first.dot(Vector3.BACK), 0.0, 1e-4, "across the line of fire (the threat is straight behind)")
	assert_true(pilot.has_desired_velocity)
	assert_almost_eq((pilot.desired_velocity - p.velocity).normalized().dot(first), 1.0, 1e-3, "it seeks toward the side")
	assert_between(evade.jink_left_s, BehaviourEvade.JINK_MIN_S - DT, BehaviourEvade.JINK_MAX_S)
	_tick(pilot, p, evade.jink_left_s + DT)
	assert_eq(evade.jinks, 2, "a reversal")
	assert_lt(evade.side.dot(first), 0.0, "the other way")
	assert_eq(pilot.describe()["behaviour"], "evade")
	assert_string_contains(String(pilot.describe()["state"]), "jink")


func test_retreat_scores_below_the_profiles_threshold_with_a_hostile_around() -> void:
	var retreat := BehaviourRetreat.new(profile)
	var ctx := AiContext.new()
	ctx.profile = profile
	var raider := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -1000.0))
	ctx.refresh(_p([raider], 0.2))
	assert_gt(retreat.score(ctx), 0.0)
	ctx.refresh(_p([raider], 0.3))
	assert_eq(retreat.score(ctx), 0.0, "above 25 %")
	ctx.refresh(_p([], 0.2))
	assert_eq(retreat.score(ctx), 0.0, "nothing to retreat from")
	profile.retreat_below = 0.0
	ctx.refresh(_p([raider], 0.01))
	assert_eq(BehaviourRetreat.new(profile).score(ctx), 0.0, "a profile that fights to the death")


func test_a_retreating_pilot_flies_away_at_cruise_plus_50() -> void:
	var raider := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -800.0), Vector3.RIGHT)
	var pilot := AiPilot.new(profile, 3)
	_tick(pilot, _p([raider], 0.1))
	assert_eq(pilot.current.id, &"retreat", "retreat outranks attack")
	assert_true(pilot.has_desired_velocity)
	assert_almost_eq(pilot.desired_velocity, Vector3.BACK * (profile.cruise_mps + BehaviourRetreat.EXTRA_MPS),
			Vector3.ONE * 1e-3)
	assert_false(_tick(pilot, _p([raider], 0.1)).combat.fire, "no fire while retreating")


func test_idle_holds_or_coasts_by_profile() -> void:
	profile.idle_hold = true
	var pilot := AiPilot.new(profile, 3)
	assert_true(_tick(pilot, _p()).flight.brake, "hold position")
	assert_eq(pilot.describe()["state"], "hold")
	profile.idle_hold = false
	var coasting := AiPilot.new(profile, 3)
	var cmd: PilotCommand = _tick(coasting, _p())
	assert_false(cmd.flight.brake)
	assert_false(coasting.has_desired_velocity, "coasting: the current velocity is the wish")


func test_a_profile_that_never_fires_holds_the_trigger_whatever_the_behaviour() -> void:
	profile.fires = false
	profile.tactics = load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	var raider := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -600.0), Vector3.BACK)
	var pilot := AiPilot.new(profile, 3)
	var p := _p([raider])
	p.muzzle_speed_mps = 350.0
	for i: int in 120:
		assert_false(_tick(pilot, p).combat.fire)
	var attack := pilot.behaviour(&"attack") as BehaviourAttack
	assert_eq(pilot.current, attack)
	assert_true(attack.brain.firing, "the attack would have fired: nose on the lead, in range")


func test_the_same_seed_makes_the_same_choices_and_commands() -> void:
	var runs: Array = []
	for run: int in 2:
		var pilot := AiPilot.new(profile, 77)
		var picks: Array[String] = []
		for i: int in 900:
			# A raider swinging round from ahead to our tail and away again, firing now and then.
			var angle: float = float(i) / 900.0 * TAU
			var at := Vector3(sin(angle) * 900.0, 0.0, -cos(angle) * 900.0)
			var p := _p([_contact(20, "RAIDER 1", Factions.Relation.HOSTILE, at, -at.normalized())], 1.0 if i < 600 else 0.2)
			p.now_s = float(i) * DT
			p.incoming_fire = 1 if i % 200 < 20 else 0
			var cmd: PilotCommand = pilot.think(p, DT)
			picks.append("%s %s %s %s" % [pilot.current.id, cmd.flight.rot, cmd.flight.strafe, cmd.combat.fire])
		runs.append(picks)
	assert_eq(runs[0], runs[1])
	var behaviours: Dictionary = {}
	for line: String in runs[0] as Array[String]:
		behaviours[line.get_slice(" ", 0)] = true
	assert_true(behaviours.has("attack") and behaviours.has("evade") and behaviours.has("retreat"),
			"the run went through attack, evade and retreat: %s" % str(behaviours.keys()))


func test_reset_starts_over() -> void:
	var raider := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -1500.0), Vector3.BACK)
	var pilot := AiPilot.new(profile, 3)
	_tick(pilot, _p([raider]), 0.5)
	pilot.reset()
	assert_null(pilot.current)
	assert_eq(pilot.wanted_target_id, PilotBrain.TARGET_NONE)
	assert_eq(pilot.describe()["behaviour"], "none")


func test_when_nothing_scores_it_falls_back_to_idle_never_to_a_zero_score() -> void:
	var a := Scripted.new(&"attack", 0.0)
	var b := Scripted.new(&"evade", 0.0)
	var idle := Scripted.new(&"idle", 0.0)
	var pilot := _scripted_pilot([a, b, idle])
	_tick(pilot, _p())
	assert_eq(pilot.current, idle, "the first pick with nothing scoring is idle, not the first in the tie order")
	b.value = 0.6
	_tick(pilot, _p())
	assert_eq(pilot.current, b)
	b.value = 0.0
	_tick(pilot, _p())
	assert_eq(pilot.current, idle, "evade has nothing to do: idle, not attack at 0")
	assert_eq(a.entered, 0, "a behaviour at 0 never got control")
	var without_idle := _scripted_pilot([Scripted.new(&"attack", 0.0)])
	_tick(without_idle, _p())
	assert_null(without_idle.current, "no idle: nobody flies")
	assert_eq(without_idle.wanted_target_id, PilotBrain.TARGET_NONE)


func test_a_behaviour_weighted_zero_is_not_scored() -> void:
	var a := Scripted.new(&"attack", 0.9)
	var b := Scripted.new(&"evade", 0.5)
	profile.weights[&"attack"] = 0.0
	var pilot := _scripted_pilot([a, b])
	var counting := CountingScore.new(&"retreat")
	pilot.add_behaviour(counting)
	profile.weights[&"retreat"] = 0.0  # read when added: this one is still weighted 1
	_tick(pilot, _p(), 0.5)
	assert_eq(pilot.current, b)
	assert_eq(pilot.raw_score_of(&"attack"), 0.0, "weighted 0: not asked")
	assert_gt(counting.asked, 0, "the weight is read when the behaviour is added")
	var zero := CountingScore.new(&"retreat")
	var other := _scripted_pilot([Scripted.new(&"evade", 0.5), zero])
	_tick(other, _p(), 0.5)
	assert_eq(zero.asked, 0, "a behaviour weighted 0 never has score() called")


func test_only_the_attack_advertises_a_target() -> void:
	var raider := _contact(20, "RAIDER 1", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -1500.0), Vector3.BACK)
	var pilot := AiPilot.new(profile, 3)
	assert_eq(pilot.wanted_target_id, PilotBrain.TARGET_NONE, "before the first tick")
	_tick(pilot, _p([raider]))
	assert_eq(pilot.wanted_target_id, 20, "attacking it")
	_tick(pilot, _p([raider], 0.1), 1.2)
	assert_eq(pilot.current.id, &"retreat")
	assert_eq(pilot.wanted_target_id, PilotBrain.TARGET_NONE, "retreating: no target, not the driver's nearest hostile")
	var tail := _contact(21, "RAIDER 2", Factions.Relation.HOSTILE, Vector3(0.0, 0.0, 600.0), Vector3.FORWARD)
	var evading := AiPilot.new(profile, 3)
	_tick(evading, _p([tail]))
	assert_eq(evading.current.id, &"evade")
	assert_eq(evading.wanted_target_id, PilotBrain.TARGET_NONE, "evading: no target")
