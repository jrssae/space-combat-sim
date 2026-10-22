extends GutTest
## BrainFactory (M2-T07): scenario behaviour dictionaries -> brains, with path-qualified errors.

var anchor := UniversePos.new(1000.0, 200.0, -3000.0)


func _make(data: Variant) -> Dictionary:
	return BrainFactory.from_behaviour(data, anchor, 7)


func test_idle_and_hold() -> void:
	var made: Dictionary = _make({"type": "idle"})
	assert_true(made["ok"])
	assert_true(made["brain"] is IdleBrain)
	assert_false((made["brain"] as IdleBrain).hold)
	assert_true(((_make({"type": "idle", "hold": true})["brain"]) as IdleBrain).hold)


func test_attack_gets_the_default_tactics_and_the_seed() -> void:
	var made: Dictionary = _make({"type": "attack"})
	assert_true(made["brain"] is AttackBrain)
	var brain: AttackBrain = made["brain"]
	assert_eq(brain.tactics.closing_far_mps, 120.0)
	var again: AttackBrain = _make({"type": "attack"})["brain"]
	assert_eq(brain._side, again._side, "same seed, same side")


func test_patrol_waypoints_are_offsets_from_the_anchor() -> void:
	var made: Dictionary = _make({"type": "patrol", "waypoints": [[0, 0, -500], [300, 50, -900]], "cruise_mps": 60})
	assert_true(made["ok"], made["error"])
	var brain: PatrolBrain = made["brain"]
	assert_eq(brain.cruise_mps, 60.0)
	assert_eq(brain.waypoints.size(), 2)
	assert_eq(brain.waypoints[0].z, -3500.0)
	assert_eq(brain.waypoints[1].x, 1300.0)
	assert_eq(brain.waypoints[1].y, 250.0)
	assert_eq(brain.waypoints[0].system_id, anchor.system_id)


func test_aggro_wraps_patrol_and_attack() -> void:
	var made: Dictionary = _make({"type": "aggro", "waypoints": [[0, 0, -100], [100, 0, -100]], "aggro_range_m": 900})
	assert_true(made["ok"], made["error"])
	var brain: AggroBrain = made["brain"]
	assert_eq(brain.aggro_range_m, 900.0)
	assert_not_null(brain.patrol)
	assert_not_null(brain.attack)


func test_defaults_for_cruise_and_aggro_range() -> void:
	var patrol: PatrolBrain = _make({"type": "patrol", "waypoints": [[0, 0, -1], [0, 0, -2]]})["brain"]
	assert_eq(patrol.cruise_mps, BrainFactory.DEFAULT_CRUISE_MPS)
	var aggro: AggroBrain = _make({"type": "aggro", "waypoints": [[0, 0, -1], [0, 0, -2]]})["brain"]
	assert_eq(aggro.aggro_range_m, BrainFactory.DEFAULT_AGGRO_RANGE_M)


func test_errors_name_the_offending_key() -> void:
	var cases: Array[Array] = [
		["x", "behaviour must be an object"],
		[{"type": "dance"}, "behaviour.type must be one of"],
		[{}, "behaviour.type"],
		[{"type": "patrol"}, "behaviour.waypoints must be an array of at least two"],
		[{"type": "patrol", "waypoints": [[0, 0, 0]]}, "behaviour.waypoints must be an array of at least two"],
		[{"type": "patrol", "waypoints": [[0, 0, 0], [1, 2]]}, "behaviour.waypoints[1] must be [x, y, z]"],
		[{"type": "patrol", "waypoints": [[0, 0, 0], [1, "a", 3]]}, "behaviour.waypoints[1] must hold numbers"],
		[{"type": "patrol", "waypoints": [[0, 0, 0], [1, 2, 3]], "cruise_mps": 0}, "behaviour.cruise_mps"],
		[{"type": "aggro", "waypoints": [[0, 0, 0], [1, 2, 3]], "aggro_range_m": -5}, "behaviour.aggro_range_m"],
	]
	for case: Array in cases:
		var made: Dictionary = _make(case[0])
		assert_false(made["ok"], "case %s should fail" % str(case[0]))
		assert_string_contains(String(made["error"]), String(case[1]))
		assert_null(made["brain"])


func test_every_behaviour_name_builds() -> void:
	for behaviour: StringName in BrainFactory.BEHAVIOURS:
		var data: Dictionary = {"type": String(behaviour), "waypoints": [[0, 0, -1], [0, 0, -2]]}
		assert_true(_make(data)["ok"], String(behaviour))
