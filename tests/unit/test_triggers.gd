extends GutTest
## Mission triggers (architecture §18 D52, M5-T05): every kind's test and its force (D51's skip makes an awaited trigger true),
## `TriggerSpec.from_dict` and its refusals, the player's action set from one tick's `PilotCommand`, and the per-tick work of 20
## live triggers, counted rather than timed.

var world: MissionWorld


func before_each() -> void:
	world = MissionWorld.new()
	world.set_actor("PLAYER", UniversePos.new(0.0, 0.0, 0.0))
	world.set_actor("NAV ALPHA", UniversePos.new(0.0, 0.0, -2000.0))


func _at(x: float, y: float, z: float) -> UniversePos:
	return UniversePos.new(x, y, z)


# --- proximity ---------------------------------------------------------------------------------------------------------


func test_proximity_to_an_actor_holds_inside_the_radius_only() -> void:
	var t: Trigger = TriggerSpec.proximity("player", "NAV ALPHA", 300.0)
	assert_false(t.check(world), "2 km apart")
	world.set_actor("PLAYER", _at(0.0, 0.0, -1750.0))
	assert_true(t.check(world), "250 m apart")
	assert_eq(t.actors(), PackedStringArray(["player", "NAV ALPHA"]))


func test_proximity_to_a_point_and_names_ignore_case() -> void:
	var t: Trigger = TriggerSpec.near_point("Player", _at(100.0, 0.0, 0.0), 150.0)
	assert_true(t.check(world))
	world.set_actor("PLAYER", _at(400.0, 0.0, 0.0))
	assert_false(t.check(world))


func test_proximity_is_false_while_either_actor_is_unknown_or_dead() -> void:
	var t: Trigger = TriggerSpec.proximity("player", "RAIDER 9", 1.0e9)
	assert_false(t.check(world), "never seen")
	world.set_alive("NAV ALPHA", false)
	assert_false(TriggerSpec.proximity("player", "NAV ALPHA", 1.0e9).check(world), "destroyed")


func test_forced_proximity_places_the_actor_beside_the_goal() -> void:
	var t: Trigger = TriggerSpec.proximity("player", "NAV ALPHA", 300.0)
	t.make_true(world)
	var p: UniversePos = world.position_of("player")
	var d: float = p.distance_to(world.position_of("NAV ALPHA"))
	assert_lt(d, 300.0, "inside the radius")
	assert_gt(d, 1.0, "beside the buoy, not inside it")
	assert_lt(p.z, 0.0, "on the side it came from")
	assert_true(t.test(world), "true on its own merits, not just latched")


# --- area --------------------------------------------------------------------------------------------------------------


func test_area_holds_inside_its_sphere() -> void:
	var t: Trigger = TriggerSpec.area("player", _at(0.0, 500.0, 0.0), 400.0)
	assert_false(t.check(world))
	world.set_actor("PLAYER", _at(0.0, 300.0, 0.0))
	assert_true(t.check(world))


func test_forced_area_places_the_actor_at_its_centre() -> void:
	var t: Trigger = TriggerSpec.area("player", _at(5000.0, 0.0, 0.0), 400.0)
	t.make_true(world)
	assert_almost_eq(world.position_of("player").distance_to(_at(5000.0, 0.0, 0.0)), 0.0, 1e-6)
	assert_true(t.test(world))


# --- timer -------------------------------------------------------------------------------------------------------------


func test_timer_counts_sim_time_from_when_it_was_armed() -> void:
	world.time_s = 10.0
	var t: Trigger = TriggerSpec.timer(5.0)
	t.arm(world)
	world.time_s = 14.9
	assert_false(t.check(world))
	world.time_s = 15.0
	assert_true(t.check(world))


func test_an_unarmed_timer_arms_on_its_first_check() -> void:
	world.time_s = 3.0
	var t: Trigger = TriggerSpec.timer(1.0)
	assert_false(t.check(world))
	world.time_s = 4.0
	assert_true(t.check(world))


func test_forced_timer_resolves_without_moving_time() -> void:
	var t: Trigger = TriggerSpec.timer(600.0)
	t.arm(world)
	t.make_true(world)
	assert_true(t.check(world))
	assert_eq(world.time_s, 0.0)


# --- destroyed ---------------------------------------------------------------------------------------------------------


func test_destroyed_all_needs_every_name_gone() -> void:
	world.set_actor("RAIDER 1", _at(0.0, 0.0, -5000.0))
	world.set_actor("RAIDER 2", _at(0.0, 0.0, -5100.0))
	var t: Trigger = TriggerSpec.destroyed(["RAIDER 1", "RAIDER 2"])
	assert_false(t.check(world))
	world.set_alive("RAIDER 1", false)
	assert_false(t.check(world), "one left")
	world.set_alive("RAIDER 2", false)
	assert_true(t.check(world))


func test_destroyed_any_needs_one_name_gone() -> void:
	world.set_actor("RAIDER 1", _at(0.0, 0.0, -5000.0))
	world.set_actor("RAIDER 2", _at(0.0, 0.0, -5100.0))
	var t: Trigger = TriggerSpec.destroyed(["RAIDER 1", "RAIDER 2"], false)
	assert_false(t.check(world))
	world.set_alive("RAIDER 2", false)
	assert_true(t.check(world))


func test_forced_destroyed_releases_the_named_ships() -> void:
	world.set_actor("RAIDER 1", _at(0.0, 0.0, -5000.0))
	world.set_actor("RAIDER 2", _at(0.0, 0.0, -5100.0))
	TriggerSpec.destroyed(["RAIDER 1", "RAIDER 2"]).make_true(world)
	assert_false(world.is_alive("RAIDER 1"))
	assert_false(world.is_alive("RAIDER 2"))
	assert_eq(world.released, PackedStringArray(["raider 1", "raider 2"]))


func test_forced_destroyed_any_releases_only_the_first_alive() -> void:
	world.set_actor("RAIDER 1", _at(0.0, 0.0, -5000.0))
	world.set_actor("RAIDER 2", _at(0.0, 0.0, -5100.0))
	TriggerSpec.destroyed(["RAIDER 1", "RAIDER 2"], false).make_true(world)
	assert_false(world.is_alive("RAIDER 1"))
	assert_true(world.is_alive("RAIDER 2"), "the step would have ended at the first kill")


# --- dialog_finished, input_performed ------------------------------------------------------------------------------------


func test_dialog_finished_waits_for_its_line() -> void:
	var t: Trigger = TriggerSpec.dialog_finished(&"intro_2")
	world.finish_line(&"intro_1")
	assert_false(t.check(world))
	world.finish_line(&"intro_2")
	assert_true(t.check(world))


func test_forced_dialog_finished_marks_the_line_done() -> void:
	TriggerSpec.dialog_finished(&"intro_1").make_true(world)
	assert_true(world.line_finished(&"intro_1"))


func test_input_performed_reads_only_this_ticks_actions() -> void:
	var t: Trigger = TriggerSpec.input_performed(&"roll_right")
	world.set_actions({&"roll_left": true})
	assert_false(t.check(world))
	world.set_actions({&"roll_right": true})
	assert_true(t.check(world))
	world.set_actions({})
	assert_false(t.check(world), "an edge lasts one tick")


func test_forced_input_performed_simply_resolves() -> void:
	var t: Trigger = TriggerSpec.input_performed(&"fire")
	t.make_true(world)
	assert_true(t.check(world))
	assert_false(t.test(world), "the world did not change")


# --- arrived -----------------------------------------------------------------------------------------------------------


func test_arrived_at_a_point() -> void:
	world.set_actor("ALPHA 2", _at(0.0, 0.0, -900.0))
	var t: Trigger = TriggerSpec.arrived("ALPHA 2", _at(0.0, 0.0, -1000.0), 150.0)
	assert_true(t.check(world))
	world.set_actor("ALPHA 2", _at(0.0, 0.0, -600.0))
	assert_false(t.check(world))


func test_arrived_at_the_end_of_its_route() -> void:
	world.set_actor("ALPHA 2", _at(0.0, 0.0, 0.0))
	world.set_route("ALPHA 2", _at(0.0, 0.0, -8000.0), false)
	var t: Trigger = TriggerSpec.arrived("ALPHA 2")
	assert_false(t.check(world))
	world.set_route("ALPHA 2", _at(0.0, 0.0, -8000.0), true)
	assert_true(t.check(world))


func test_forced_arrived_places_the_actor_at_its_route_end_and_finishes_the_route() -> void:
	world.set_actor("ALPHA 2", _at(0.0, 0.0, 0.0))
	world.set_route("ALPHA 2", _at(0.0, 0.0, -8000.0), false)
	TriggerSpec.arrived("ALPHA 2").make_true(world)
	assert_almost_eq(world.position_of("ALPHA 2").distance_to(_at(0.0, 0.0, -8000.0)), 0.0, 1e-6)
	assert_true(world.route_done("ALPHA 2"))


func test_forced_arrived_at_a_point_places_the_actor_there() -> void:
	world.set_actor("ALPHA 2", _at(0.0, 0.0, 0.0))
	var t: Trigger = TriggerSpec.arrived("ALPHA 2", _at(3000.0, 0.0, 0.0), 150.0)
	t.make_true(world)
	assert_true(t.test(world))


# --- TriggerSpec -------------------------------------------------------------------------------------------------------


func test_from_dict_builds_every_kind() -> void:
	var specs: Array[Dictionary] = [
		{"kind": "proximity", "actor": "player", "to": "NAV ALPHA", "radius_m": 300},
		{"kind": "proximity", "actor": "player", "to": [0, 0, -100], "radius_m": 50},
		{"kind": "area", "actor": "player", "centre": [0, 0, 0], "radius_m": 500},
		{"kind": "timer", "seconds": 30},
		{"kind": "destroyed", "names": ["RAIDER 1", "RAIDER 2"], "all": false},
		{"kind": "destroyed", "name": "NAV ALPHA"},
		{"kind": "dialog_finished", "line": "intro_1"},
		{"kind": "input_performed", "action": "roll_right"},
		{"kind": "arrived", "actor": "ALPHA 2"},
		{"kind": "arrived", "actor": "ALPHA 2", "at": [0, 0, -500], "radius_m": 100},
	]
	var kinds: Array[StringName] = []
	for spec: Dictionary in specs:
		var made: Dictionary = TriggerSpec.from_dict(spec)
		assert_true(bool(made["ok"]), str(made["error"]))
		kinds.append((made["trigger"] as Trigger).kind)
	assert_eq(kinds, [&"proximity", &"proximity", &"area", &"timer", &"destroyed", &"destroyed", &"dialog_finished",
			&"input_performed", &"arrived", &"arrived"] as Array[StringName])


func test_from_dict_points_are_universe_positions_in_the_scenario_system() -> void:
	var made: Dictionary = TriggerSpec.from_dict({"kind": "area", "actor": "player", "centre": [1.0e9, 0, 0], "radius_m": 10},
			&"sol")
	var t := made["trigger"] as TriggerArea
	assert_eq(t.centre.system_id, &"sol")
	assert_eq(t.centre.x, 1.0e9, "64-bit, never through a Vector3")


func test_from_dict_refuses_bad_specs_and_says_why() -> void:
	var bad: Dictionary = {
		"must be an object": "timer",
		"unknown kind": {"kind": "teleport"},
		"needs an actor": {"kind": "proximity", "to": "NAV ALPHA", "radius_m": 10},
		"radius_m must be a number above 0": {"kind": "proximity", "actor": "player", "to": "NAV ALPHA", "radius_m": 0},
		"to must be a name or [x, y, z]": {"kind": "proximity", "actor": "player", "to": 5, "radius_m": 10},
		"centre must be [x, y, z]": {"kind": "area", "actor": "player", "centre": [0, 0], "radius_m": 10},
		"seconds must be a number, 0 or more": {"kind": "timer", "seconds": -1},
		"names must be a non-empty list of ship names": {"kind": "destroyed", "names": []},
		"line must be a dialog line id": {"kind": "dialog_finished", "line": ""},
		"action must be one of": {"kind": "input_performed", "action": "dance"},
		"at must be [x, y, z]": {"kind": "arrived", "actor": "ALPHA 2", "at": "home"},
	}
	for expected: String in bad:
		var made: Dictionary = TriggerSpec.from_dict(bad[expected])
		assert_false(bool(made["ok"]), expected)
		assert_string_contains(String(made["error"]), expected)


func test_describe_names_the_kind_and_its_subject() -> void:
	assert_string_contains(TriggerSpec.destroyed(["RAIDER 1"]).describe(), "destroyed")
	assert_string_contains(TriggerSpec.destroyed(["RAIDER 1"]).describe(), "RAIDER 1")
	assert_string_contains(TriggerSpec.input_performed(&"fire").describe(), "fire")


# --- the player's actions ----------------------------------------------------------------------------------------------


func test_player_actions_come_from_the_ticks_command() -> void:
	var pc := PilotCommand.new()
	pc.flight.rot = Vector3(0.0, -0.9, 0.8)
	pc.flight.main_left = 1.0
	pc.flight.toggle_assist = true
	pc.combat.fire = true
	pc.ui.wing_form = true
	var actions: Dictionary = PlayerActions.from_command(pc)
	for name: StringName in [&"yaw_left", &"roll_right", &"main_left", &"toggle_flight_assist", &"fire", &"wing_form"]:
		assert_true(actions.has(name), String(name))
	for name: StringName in [&"yaw_right", &"pitch_up", &"main_right", &"brake", &"pause"]:
		assert_false(actions.has(name), String(name))


func test_a_light_touch_is_not_an_action() -> void:
	var pc := PilotCommand.new()
	pc.flight.rot = Vector3(0.2, 0.0, 0.0)
	pc.flight.strafe = Vector2(0.3, 0.0)
	assert_true(PlayerActions.from_command(pc).is_empty())


func test_every_reported_action_is_a_known_name() -> void:
	var pc := PilotCommand.new()
	pc.flight.rot = Vector3.ONE
	pc.flight.strafe = Vector2.ONE
	pc.flight.main_left = 1.0
	pc.flight.main_right = 1.0
	pc.flight.retro_left = 1.0
	pc.flight.retro_right = 1.0
	pc.flight.brake = true
	for action: StringName in PlayerActions.from_command(pc):
		assert_has(PlayerActions.NAMES, action)


# --- cost (D52: counted work, not milliseconds) ---------------------------------------------------------------------------


func test_twenty_live_triggers_cost_a_bounded_count_whatever_the_world_holds() -> void:
	world.set_actor("SHIP 1", _at(10.0, 0.0, 0.0))
	world.set_actor("SHIP 2", _at(20.0, 0.0, 0.0))
	var small: int = _work_of_twenty(world)
	var crowded := MissionWorld.new()
	crowded.set_actor("PLAYER", UniversePos.new())
	crowded.set_actor("NAV ALPHA", _at(0.0, 0.0, -2000.0))
	for i: int in 500:
		crowded.set_actor("SHIP %d" % i, _at(float(i) * 10.0, 0.0, 0.0))
	var big: int = _work_of_twenty(crowded)
	gut.p("20 triggers: %d units of work with 4 actors, %d with 502" % [small, big])
	assert_eq(small, big, "the work does not grow with the number of ships")
	assert_lte(big, 20 * 3, "a check and at most two lookups per trigger (none names more than two actors)")


func _work_of_twenty(w: MissionWorld) -> int:
	var triggers: Array[Trigger] = []
	for i: int in 4:
		triggers.append(TriggerSpec.proximity("player", "NAV ALPHA", 300.0))
		triggers.append(TriggerSpec.area("player", _at(0.0, 0.0, 0.0), 100.0))
		triggers.append(TriggerSpec.timer(10.0))
		triggers.append(TriggerSpec.destroyed(["SHIP 1", "SHIP 2"]))
		triggers.append(TriggerSpec.input_performed(&"fire"))
	assert_eq(triggers.size(), 20)
	w.work = 0
	for t: Trigger in triggers:
		t.check(w)
	return w.work
