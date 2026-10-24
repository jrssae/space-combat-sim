extends GutTest
## AiProfile (M3-T06, architecture §16 D34): the shipped profiles in `assets/ai/` load and validate, carry the plan's
## selection numbers, and give allies, raiders and the instructor their characters; the Starfury's tactics fit its gun.

const SELECTION_IDS: Array[StringName] = [&"attack", &"evade", &"retreat", &"idle"]


func _weapon(ship_path: String) -> WeaponSpec:
	return (load(ship_path) as ShipSpec).weapon


func test_every_shipped_profile_loads_and_validates() -> void:
	assert_eq(AiProfile.PATHS.keys(), [&"ally_starfury", &"raider", &"instructor"])
	for profile_name: StringName in AiProfile.PATHS:
		var profile: AiProfile = AiProfile.load_named(profile_name)
		assert_not_null(profile, String(profile_name))
		assert_eq(profile.validate(), "", String(profile_name))
		for id: StringName in SELECTION_IDS:
			assert_true(profile.weights.has(id), "%s names a weight for %s" % [profile_name, id])
		assert_not_null(profile.tactics, String(profile_name))


func test_the_selection_numbers_are_the_plans() -> void:
	for profile_name: StringName in AiProfile.PATHS:
		var profile: AiProfile = AiProfile.load_named(profile_name)
		assert_eq(profile.stickiness, 0.15, String(profile_name))
		assert_eq(profile.min_dwell_s, 1.0, String(profile_name))
		assert_eq(profile.emergency_margin, 0.4, String(profile_name))


func test_allies_retreat_below_a_quarter_hull_and_raiders_fight_to_the_death() -> void:
	var ally: AiProfile = AiProfile.load_named(&"ally_starfury")
	assert_eq(ally.retreat_below, 0.25)
	assert_gt(ally.weight(&"retreat"), 0.0)
	assert_true(ally.fires)
	assert_eq(AiProfile.load_named(&"raider").retreat_below, 0.0)


func test_the_instructor_never_attacks_retreats_or_fires() -> void:
	var instructor: AiProfile = AiProfile.load_named(&"instructor")
	assert_eq(instructor.weight(&"attack"), 0.0)
	assert_eq(instructor.retreat_below, 0.0)
	assert_false(instructor.fires)


func test_the_starfury_tactics_fit_its_gun_and_differ_from_the_raiders() -> void:
	var ally: RaiderTactics = AiProfile.load_named(&"ally_starfury").tactics
	var raider: RaiderTactics = AiProfile.load_named(&"raider").tactics
	assert_eq(raider.resource_path, BrainFactory.DEFAULT_TACTICS_PATH, "raiders keep the M2 tactics")
	assert_eq(ally.resource_path, AiProfile.STARFURY_TACTICS_PATH)
	var starfury_gun: WeaponSpec = _weapon("res://assets/ships/starfury_aurora.tres")
	var raider_gun: WeaponSpec = _weapon("res://assets/ships/raider_delta_v.tres")
	assert_lt(ally.fire_range_m, starfury_gun.muzzle_speed_mps * starfury_gun.lifetime_s, "inside the bolt's reach")
	assert_lt(raider.fire_range_m, raider_gun.muzzle_speed_mps * raider_gun.lifetime_s)
	assert_gt(ally.fire_range_m, raider.fire_range_m, "1 000 m/s bolts reach further")
	assert_gt(ally.break_range_m, 0.0)
	assert_lt(ally.break_range_m, ally.fire_range_m)


func test_a_weight_the_profile_does_not_name_is_one() -> void:
	var profile := AiProfile.new()
	assert_eq(profile.weight(&"formation"), 1.0, "behaviours added later work in every profile until one opts out")
	profile.weights[&"formation"] = 0.25
	assert_eq(profile.weight(&"formation"), 0.25)


func test_validate_names_the_bad_field() -> void:
	var cases: Array[Array] = [
		[func(p: AiProfile) -> void: p.weights[&"attack"] = -0.1, "weights.attack"],
		[func(p: AiProfile) -> void: p.weights[&"evade"] = 1.5, "weights.evade"],
		[func(p: AiProfile) -> void: p.stickiness = -0.1, "stickiness"],
		[func(p: AiProfile) -> void: p.min_dwell_s = -1.0, "min_dwell_s"],
		[func(p: AiProfile) -> void: p.emergency_margin = -0.5, "emergency_margin"],
		[func(p: AiProfile) -> void: p.retreat_below = 1.5, "retreat_below"],
		[func(p: AiProfile) -> void: p.cruise_mps = 0.0, "cruise_mps"],
		[func(p: AiProfile) -> void: p.aim_error_deg = -1.0, "aim_error_deg"],
		[func(p: AiProfile) -> void: p.tactics = null, "tactics"],
	]
	assert_eq(_valid_profile().validate(), "")
	for case: Array in cases:
		var profile: AiProfile = _valid_profile()
		(case[0] as Callable).call(profile)
		assert_string_contains(profile.validate(), String(case[1]))


# A fresh profile that validates (the loaded ones are cached resources: tests must not edit them).
func _valid_profile() -> AiProfile:
	var profile := AiProfile.new()
	profile.weights = {&"attack": 1.0, &"evade": 1.0, &"retreat": 1.0, &"idle": 1.0}
	profile.tactics = load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	return profile


func test_an_unknown_profile_name_loads_nothing() -> void:
	assert_null(AiProfile.load_named(&"pirate"))
