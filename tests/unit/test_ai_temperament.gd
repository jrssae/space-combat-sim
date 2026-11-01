extends GutTest
## AiTemperament (M3-T13, Q12, AC20): ranks and numbers parse, `regular` + `balanced` leave a profile as tuned, and every
## factor moves monotonically with its dial: skill scales the aim error, the reaction time, the fire discipline and the evade
## quality; aggression the attack / evade / retreat weights, the retreat threshold and the engage and break-off ranges.

const SKILLS: Array[float] = [0.0, 0.2, 0.3, 0.45, 0.6, 0.7, 0.85, 0.95, 1.0]
const AGGRESSIONS: Array[float] = [0.0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 1.0]


func _profile() -> AiProfile:
	var p := AiProfile.new()
	p.weights = {&"attack": 0.8, &"evade": 0.8, &"retreat": 0.8, &"idle": 1.0}
	p.retreat_below = 0.25
	p.aim_error_deg = 0.2
	p.tactics = load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	return p


func test_ranks_and_numbers_parse() -> void:
	assert_eq(AiTemperament.parse_skill("rookie"), 0.2)
	assert_eq(AiTemperament.parse_skill("ACE"), 0.95)
	assert_eq(AiTemperament.parse_skill(0.6), 0.6)
	assert_eq(AiTemperament.parse_skill("0.3"), 0.3)
	assert_eq(AiTemperament.parse_skill("godlike"), -1.0)
	assert_eq(AiTemperament.parse_skill(1.5), -1.0)
	assert_eq(AiTemperament.parse_aggression("reckless"), 1.0)
	assert_eq(AiTemperament.parse_aggression("passive"), 0.0)
	assert_eq(AiTemperament.parse_aggression("berserk"), -1.0)
	assert_eq(AiTemperament.skill_name(0.68), &"veteran")
	assert_eq(AiTemperament.aggression_name(0.3), &"cautious")


func test_regular_and_balanced_leave_the_profile_as_tuned() -> void:
	var base: AiProfile = _profile()
	var out: AiProfile = AiTemperament.new().apply(base)
	assert_ne(out, base, "a copy")
	assert_ne(out.tactics, base.tactics, "its tactics copied too")
	for id: StringName in [&"attack", &"evade", &"retreat", &"idle"]:
		assert_almost_eq(out.weight(id), base.weight(id), 1e-9, String(id))
	assert_almost_eq(out.retreat_below, base.retreat_below, 1e-9)
	assert_almost_eq(out.aim_error_deg, base.aim_error_deg, 1e-9)
	assert_almost_eq(out.tactics.fire_miss_m, base.tactics.fire_miss_m, 1e-9)
	assert_almost_eq(out.tactics.near_range_m, base.tactics.near_range_m, 1e-9)
	assert_almost_eq(out.tactics.break_range_m, base.tactics.break_range_m, 1e-9)
	assert_almost_eq(AiTemperament.new().reaction_s(), 0.25, 1e-9)
	assert_eq(base.weights[&"attack"], 0.8, "the base profile is never changed")


func _monotonic(values: Array[float], rising: bool, what: String) -> void:
	for i: int in range(1, values.size()):
		if rising:
			assert_true(values[i] >= values[i - 1] - 1e-9, "%s rises: %s" % [what, str(values)])
		else:
			assert_true(values[i] <= values[i - 1] + 1e-9, "%s falls: %s" % [what, str(values)])
	assert_ne(values[0], values[values.size() - 1], "%s changes over the dial" % what)


func test_skill_scales_aim_reaction_discipline_and_evasion_monotonically() -> void:
	var base: AiProfile = _profile()
	var aim: Array[float] = []
	var reaction: Array[float] = []
	var miss: Array[float] = []
	var jink: Array[float] = []
	var spread: Array[float] = []
	for s: float in SKILLS:
		var t := AiTemperament.new(s, 0.5)
		var out: AiProfile = t.apply(base)
		aim.append(out.aim_error_deg)
		reaction.append(t.reaction_s())
		miss.append(out.tactics.fire_miss_m)
		jink.append(t.jink_factor())
		spread.append(t.reversal_spread_deg())
	_monotonic(aim, false, "aim error")
	_monotonic(reaction, false, "reaction time")
	_monotonic(miss, false, "the miss gate (fewer wasted bolts)")
	_monotonic(jink, false, "jink length")
	_monotonic(spread, true, "reversal spread (less regular)")
	assert_almost_eq(AiTemperament.new(0.95).aim_factor(), 0.4, 1e-9, "ace about 0.4x")
	assert_almost_eq(AiTemperament.new(0.2).aim_factor(), 2.5, 1e-9, "rookie about 2.5x")
	assert_almost_eq(AiTemperament.new(0.95).reaction_s(), 0.1, 1e-9)
	assert_almost_eq(AiTemperament.new(0.2).reaction_s(), 0.6, 1e-9)


func test_aggression_scales_weights_retreat_and_ranges_monotonically() -> void:
	var base: AiProfile = _profile()
	var attack: Array[float] = []
	var evade: Array[float] = []
	var retreat: Array[float] = []
	var threshold: Array[float] = []
	var near: Array[float] = []
	var breaks: Array[float] = []
	for a: float in AGGRESSIONS:
		var out: AiProfile = AiTemperament.new(0.45, a).apply(base)
		attack.append(out.weight(&"attack"))
		evade.append(out.weight(&"evade"))
		retreat.append(out.weight(&"retreat"))
		threshold.append(out.retreat_below)
		near.append(out.tactics.near_range_m)
		breaks.append(out.tactics.break_range_m)
	_monotonic(attack, true, "attack weight")
	_monotonic(evade, false, "evade weight")
	_monotonic(retreat, false, "retreat weight")
	_monotonic(threshold, false, "retreat threshold")
	_monotonic(near, false, "engage range")
	_monotonic(breaks, false, "break-off distance")
	assert_almost_eq(AiTemperament.new(0.45, 0.25).apply(base).retreat_below, 0.5, 1e-9, "cautious about 2x")
	assert_almost_eq(AiTemperament.new(0.45, 0.75).apply(base).retreat_below, 0.125, 1e-9, "aggressive half")
	assert_eq(AiTemperament.new(0.45, 1.0).apply(base).retreat_below, 0.0, "reckless never retreats")
	assert_true(AiTemperament.new(0.45, 0.0).never_starts())
	assert_false(AiTemperament.new(0.45, 0.1).never_starts())
	assert_true(AiTemperament.new(0.45, 1.0).may_ram())
	assert_false(AiTemperament.new(0.45, 0.99).may_ram())


func test_profiles_carry_their_default_temperaments() -> void:
	var expect: Dictionary = {&"ally_starfury": [&"veteran", &"balanced"], &"raider": [&"regular", &"aggressive"],
			&"instructor": [&"ace", &"passive"], &"civilian": [&"rookie", &"passive"]}
	for profile_name: StringName in expect:
		var p: AiProfile = AiProfile.load_named(profile_name)
		assert_eq(p.validate(), "", String(profile_name))
		assert_eq(AiTemperament.skill_name(p.skill), expect[profile_name][0], String(profile_name))
		assert_eq(AiTemperament.aggression_name(p.aggression), expect[profile_name][1], String(profile_name))
	var civilian: AiProfile = AiProfile.load_named(&"civilian")
	assert_eq(civilian.weight(&"attack"), 0.0)
	assert_false(civilian.fires)
	assert_eq(civilian.retreat_within_m, 3000.0)
	assert_gt(civilian.weight(&"evade"), 0.0)


func test_slashing_runs_awareness_and_close_passes_follow_the_dials() -> void:
	var chance: Array[float] = []
	var aware: Array[float] = []
	for s: float in SKILLS:
		chance.append(AiTemperament.new(s, 0.5).slash_chance())
		aware.append(AiTemperament.new(s, 0.5).awareness())
	_monotonic(chance, false, "slash chance (a rookie always, higher skill not every time)")
	_monotonic(aware, true, "awareness of other ships")
	assert_eq(AiTemperament.new(0.2).slash_chance(), 1.0)
	assert_almost_eq(AiTemperament.new(0.95).slash_chance(), 0.5, 1e-9)
	var close: Array[float] = []
	for a: float in AGGRESSIONS:
		close.append(AiTemperament.new(0.45, a).close_pass_chance())
	_monotonic(close, true, "close-pass chance")
	assert_eq(AiTemperament.new(0.45, 0.5).close_pass_chance(), 0.0, "balanced: never")
	assert_almost_eq(AiTemperament.new(0.45, 0.75).close_pass_chance(), 0.25, 1e-9)
	assert_eq(AiTemperament.new(0.2, 1.0).close_pass_chance(), 1.0, "reckless of any skill: always")
