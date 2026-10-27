extends GutTest
## ScenarioLoader (architecture §14.6, §14.9): the free-flight file parses into typed spawn entries with 64-bit
## universe positions, and broken files come back as errors (returned, never pushed).

const ONE_AU_M: float = 1.5e11

## The five buoys the milestone specifies (M1-T14 notes), as [name, position, velocity].
const EXPECTED_BUOYS: Array = [
	["NAV ALPHA", [0.0, 0.0, -500.0], [0.0, 0.0, 0.0]],
	["NAV BRAVO", [300.0, 50.0, -1200.0], [0.0, 0.0, 0.0]],
	["NAV CHARLIE", [-800.0, -200.0, -2000.0], [0.0, 0.0, 0.0]],
	["NAV DELTA", [1500.0, 400.0, 800.0], [0.0, 0.0, -3.0]],
	["NAV ECHO", [-200.0, 900.0, -4800.0], [0.0, 0.0, 0.0]],
]


func _minimal(props: Array = []) -> Dictionary:
	return {"scenario_id": "test", "system_id": "local",
			"player": {"position": [0, 0, 0], "forward": [0, 0, -1]}, "props": props}


func _buoy(buoy_name: String, position: Array = [0, 0, -100]) -> Dictionary:
	return {"type": "nav_buoy", "name": buoy_name, "position": position}


func _assert_fails(data: Variant, fragment: String) -> void:
	var result: Dictionary = ScenarioLoader.from_data(data, "case")
	assert_false(result["ok"], "rejected: %s" % fragment)
	assert_string_contains(result["error"], fragment)
	assert_true((result["error"] as String).begins_with("case"), "the error names its source")
	assert_eq((result["props"] as Array).size(), 0, "a failed load spawns nothing")


# --- the shipped scenario ----------------------------------------------------------------------------------------


func test_free_flight_has_exactly_the_five_buoys() -> void:
	var result: Dictionary = ScenarioLoader.load(ScenarioLoader.FREE_FLIGHT_PATH)
	assert_true(result["ok"], result["error"])
	assert_eq(result["error"], "")
	assert_eq(result["scenario_id"], &"free_flight")
	assert_eq(result["system_id"], &"local")
	var props: Array[Dictionary] = result["props"]
	assert_eq(props.size(), EXPECTED_BUOYS.size())
	for i: int in EXPECTED_BUOYS.size():
		var expected: Array = EXPECTED_BUOYS[i]
		var entry: Dictionary = props[i]
		assert_eq(entry["type"], &"nav_buoy")
		assert_eq(entry["name"], expected[0])
		var pos: UniversePos = entry["position"]
		var want: Array = expected[1]
		assert_eq([pos.x, pos.y, pos.z], want, "%s position" % expected[0])
		assert_eq(pos.system_id, &"local")
		var vel: Array = expected[2]
		assert_eq(entry["velocity"], Vector3(vel[0], vel[1], vel[2]), "%s velocity" % expected[0])


func test_free_flight_buoys_are_half_a_kilometre_to_five_kilometres_out() -> void:
	var result: Dictionary = ScenarioLoader.load(ScenarioLoader.FREE_FLIGHT_PATH)
	var player_pos: UniversePos = result["player"]["position"]
	for entry: Dictionary in result["props"]:
		var d: float = player_pos.distance_to(entry["position"])
		assert_between(d, 500.0, 5000.0, "%s at %.0f m (architecture §6.3)" % [entry["name"], d])


func test_free_flight_player_starts_at_the_origin_facing_minus_z() -> void:
	var result: Dictionary = ScenarioLoader.load(ScenarioLoader.FREE_FLIGHT_PATH)
	var player: Dictionary = result["player"]
	var pos: UniversePos = player["position"]
	assert_eq([pos.x, pos.y, pos.z], [0.0, 0.0, 0.0])
	assert_eq(player["forward"], Vector3.FORWARD)
	var basis: Basis = player["basis"]
	assert_almost_eq(-basis.z, Vector3.FORWARD, Vector3.ONE * 1e-6, "the basis faces forward (-Z)")
	assert_almost_eq(basis.y, Vector3.UP, Vector3.ONE * 1e-6)


# --- parsing -----------------------------------------------------------------------------------------------------


func test_positions_are_parsed_as_64_bit_universe_coordinates() -> void:
	var text: String = JSON.stringify(_minimal([_buoy("FAR", [ONE_AU_M + 0.123, -ONE_AU_M, 7.25])]), "", false, true)
	var result: Dictionary = ScenarioLoader.parse(text, "far.json")
	assert_true(result["ok"], result["error"])
	var pos: UniversePos = result["props"][0]["position"]
	assert_almost_eq(pos.x, ONE_AU_M + 0.123, 1e-4, "a float32 would be off by kilometres here")
	assert_eq(pos.y, -ONE_AU_M)
	assert_eq(pos.z, 7.25)


func test_system_id_is_applied_to_every_position() -> void:
	var data: Dictionary = _minimal([_buoy("A")])
	data["system_id"] = "epsilon"
	var result: Dictionary = ScenarioLoader.from_data(data)
	assert_true(result["ok"], result["error"])
	assert_eq(result["system_id"], &"epsilon")
	assert_eq((result["player"]["position"] as UniversePos).system_id, &"epsilon")
	assert_eq((result["props"][0]["position"] as UniversePos).system_id, &"epsilon")


func test_optional_fields_default() -> void:
	var data: Dictionary = {"scenario_id": "bare", "player": {"position": [1, 2, 3]}}
	var result: Dictionary = ScenarioLoader.from_data(data)
	assert_true(result["ok"], result["error"])
	assert_eq(result["system_id"], &"local")
	assert_eq(result["player"]["forward"], Vector3.FORWARD)
	assert_eq((result["props"] as Array).size(), 0)
	var with_buoy: Dictionary = ScenarioLoader.from_data(_minimal([_buoy("STILL")]))
	assert_eq(with_buoy["props"][0]["velocity"], Vector3.ZERO, "velocity defaults to zero")


func test_forward_is_normalised_and_the_basis_follows_it() -> void:
	var data: Dictionary = _minimal()
	data["player"]["forward"] = [10, 0, 0]
	var result: Dictionary = ScenarioLoader.from_data(data)
	assert_eq(result["player"]["forward"], Vector3.RIGHT)
	var basis: Basis = result["player"]["basis"]
	assert_almost_eq(-basis.z, Vector3.RIGHT, Vector3.ONE * 1e-6)
	var straight_up: Basis = ScenarioLoader.basis_facing(Vector3.UP)
	assert_almost_eq(-straight_up.z, Vector3.UP, Vector3.ONE * 1e-6, "facing straight up needs another up vector")
	assert_almost_eq(straight_up.determinant(), 1.0, 1e-6)


# --- errors ------------------------------------------------------------------------------------------------------


func test_missing_file_and_bad_json_are_errors() -> void:
	var missing: Dictionary = ScenarioLoader.load("res://data/scenarios/does_not_exist.json")
	assert_false(missing["ok"])
	assert_string_contains(missing["error"], "does_not_exist.json")
	var broken: Dictionary = ScenarioLoader.parse("{\"scenario_id\": ", "broken.json")
	assert_false(broken["ok"])
	assert_string_contains(broken["error"], "broken.json: invalid JSON")


func test_structural_errors() -> void:
	_assert_fails([1, 2, 3], "root must be an object")
	_assert_fails({"player": {"position": [0, 0, 0]}}, "scenario_id")
	_assert_fails({"scenario_id": "x"}, "player must be an object")
	_assert_fails({"scenario_id": "x", "player": {"position": [0, 0]}}, "player.position")
	_assert_fails({"scenario_id": "x", "player": {"position": [0, 0, "a"]}}, "player.position")
	_assert_fails({"scenario_id": "x", "player": {"position": [0, 0, 0], "forward": [0, 0, 0]}}, "player.forward")
	var bad_system: Dictionary = _minimal()
	bad_system["system_id"] = 3
	_assert_fails(bad_system, "system_id")
	var bad_props: Dictionary = _minimal()
	bad_props["props"] = {"type": "nav_buoy"}
	_assert_fails(bad_props, "props must be an array")


func test_prop_errors_name_the_entry() -> void:
	_assert_fails(_minimal([_buoy("A"), "nope"]), "props[1] must be an object")
	_assert_fails(_minimal([{"type": "space_whale", "name": "W", "position": [0, 0, 0]}]), "props[0]: type must be one of")
	_assert_fails(_minimal([{"type": "nav_buoy", "position": [0, 0, 0]}]), "props[0]: name")
	_assert_fails(_minimal([_buoy("  ")]), "props[0]: name")
	_assert_fails(_minimal([_buoy("A", [0, 0])]), "props[0]: position")
	var bad_velocity: Dictionary = _buoy("A")
	bad_velocity["velocity"] = [0, "fast", 0]
	_assert_fails(_minimal([bad_velocity]), "props[0]: velocity")
	_assert_fails(_minimal([_buoy("NAV ALPHA"), _buoy("nav alpha")]), "props[1]: duplicate name")


# --- the combat sandbox, pools, waves and loop (M2-T09) ------------------------------------------------------------


func _sandbox_with(extra: Dictionary) -> Dictionary:
	var data: Dictionary = _minimal()
	data["pools"] = {"raider_fighter": 4}
	data.merge(extra, true)
	return data


func _wave_data(spawn: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {"type": "raider_fighter", "anchor": "player", "offset": [0, 0, -1000], "behaviour": {"type": "idle"}}
	base.merge(spawn, true)
	return {"name": "WAVE", "delay_s": 3, "spawns": [base]}


func test_the_combat_sandbox_file_validates() -> void:
	var result: Dictionary = ScenarioLoader.load(ScenarioLoader.SANDBOX_PATH)
	assert_true(result["ok"], result["error"])
	assert_eq(result["scenario_id"], &"combat_sandbox")
	assert_eq((result["props"] as Array).size(), 5, "the buoys stay as scenery")
	assert_eq(result["pools"], {&"raider_fighter": 6, &"starfury_ally": 4}, "six raiders and four allied Starfuries (M3-T08)")
	assert_eq(result["loop"], {"from_wave": 3, "add_per_loop": 1})
	var waves: Array[Dictionary] = result["waves"]
	assert_eq(waves.size(), 3)
	assert_eq([waves[0]["name"], waves[1]["name"], waves[2]["name"]], ["TARGET PRACTICE", "PATROL", "STRIKE"])
	assert_eq([waves[0]["delay_s"], waves[1]["delay_s"], waves[2]["delay_s"]], [5.0, 8.0, 8.0])
	assert_eq([(waves[0]["spawns"] as Array).size(), (waves[1]["spawns"] as Array).size(), (waves[2]["spawns"] as Array).size()], [3, 3, 4])
	var strike_times: Array[float] = []
	for spawn: Dictionary in waves[2]["spawns"]:
		strike_times.append(spawn["at_s"])
		assert_eq(spawn["behaviour"]["type"], "attack")
	assert_eq(strike_times, [0.0, 2.0, 4.0, 6.0], "two seconds apart")
	for spawn: Dictionary in waves[0]["spawns"]:
		assert_eq(spawn["behaviour"]["type"], "idle")
		assert_gt((spawn["velocity"] as Vector3).length(), 4.9)
		assert_lt((spawn["velocity"] as Vector3).length(), 20.1, "drifting at 5-20 m/s")
		assert_true(absf((spawn["offset"] as Vector3).z) >= 1200.0 and absf((spawn["offset"] as Vector3).z) <= 2000.0, "1.2-2 km ahead")
	for spawn: Dictionary in waves[1]["spawns"]:
		assert_eq(spawn["behaviour"]["type"], "aggro")
		assert_eq(spawn["behaviour"]["cruise_mps"], 80.0)
		assert_eq(spawn["behaviour"]["aggro_range_m"], 1500.0)
		assert_eq((spawn["behaviour"]["waypoints"] as Array).size(), 3)


func test_pools_take_the_allied_starfury_beside_the_raider() -> void:
	var result: Dictionary = ScenarioLoader.from_data(_sandbox_with({"pools": {"raider_fighter": 4, "starfury_ally": 3}}))
	assert_true(result["ok"], result["error"])
	assert_eq(result["pools"], {&"raider_fighter": 4, &"starfury_ally": 3})
	var allies_only: Dictionary = ScenarioLoader.from_data(_sandbox_with({"pools": {"starfury_ally": 2}}))
	assert_true(allies_only["ok"], allies_only["error"])
	var bad: Dictionary = ScenarioLoader.from_data(_sandbox_with({"pools": {"starfury_ally": -1}}))
	assert_string_contains(bad["error"], "pools.starfury_ally must be a whole number")


func test_a_scenario_without_waves_has_empty_pools_waves_and_no_loop() -> void:
	var result: Dictionary = ScenarioLoader.load(ScenarioLoader.FREE_FLIGHT_PATH)
	assert_true(result["ok"])
	assert_eq((result["pools"] as Dictionary).size(), 0)
	assert_eq((result["waves"] as Array).size(), 0)
	assert_eq(result["loop"]["from_wave"], 0)


func test_spawn_fields_are_typed() -> void:
	var data: Dictionary = _sandbox_with({"waves": [_wave_data({"velocity": [1, 2, 3], "at_s": 2.5, "anchor": "origin", "name": "BANDIT"})]})
	var result: Dictionary = ScenarioLoader.from_data(data, "case")
	assert_true(result["ok"], result["error"])
	var spawn: Dictionary = (result["waves"] as Array)[0]["spawns"][0]
	assert_eq(spawn["type"], &"raider_fighter")
	assert_eq(spawn["anchor"], &"origin")
	assert_eq(spawn["offset"], Vector3(0.0, 0.0, -1000.0))
	assert_eq(spawn["velocity"], Vector3(1.0, 2.0, 3.0))
	assert_eq(spawn["at_s"], 2.5)
	assert_eq(spawn["name"], "BANDIT")


func test_wave_errors_name_the_json_path() -> void:
	var cases: Array[Array] = [
		[_sandbox_with({"pools": []}), "pools must be an object"],
		[_sandbox_with({"pools": {"battleship": 2}}), "pools.battleship: unknown ship type"],
		[_sandbox_with({"pools": {"raider_fighter": -1}}), "pools.raider_fighter must be a whole number"],
		[_sandbox_with({"pools": {"raider_fighter": 2.5}}), "pools.raider_fighter must be a whole number"],
		[_sandbox_with({"loop": {"from_wave": -2}}), "loop.from_wave"],
		[_sandbox_with({"loop": {"add_per_loop": "x"}}), "loop.add_per_loop"],
		[_sandbox_with({"waves": "no"}), "waves must be an array"],
		[_sandbox_with({"waves": [5]}), "waves[0] must be an object"],
		[_sandbox_with({"waves": [{"delay_s": 1, "spawns": [{}]}]}), "waves[0]: name must be a non-empty string"],
		[_sandbox_with({"waves": [{"name": "W", "delay_s": -1, "spawns": [{}]}]}), "waves[0]: delay_s"],
		[_sandbox_with({"waves": [{"name": "W", "spawns": []}]}), "waves[0]: spawns must be a non-empty array"],
		[_sandbox_with({"waves": [_wave_data({"type": "dreadnought"})]}), "waves[0].spawns[0]: type must be one of"],
		[_sandbox_with({"waves": [_wave_data({"anchor": "moon"})]}), "waves[0].spawns[0]: anchor must be one of"],
		[_sandbox_with({"waves": [_wave_data({"offset": [1, 2]})]}), "waves[0].spawns[0]: offset must be [x, y, z]"],
		[_sandbox_with({"waves": [_wave_data({"velocity": "fast"})]}), "waves[0].spawns[0]: velocity must be [x, y, z]"],
		[_sandbox_with({"waves": [_wave_data({"at_s": -1})]}), "waves[0].spawns[0]: at_s"],
		[_sandbox_with({"waves": [_wave_data({"behaviour": {"type": "dance"}})]}), "waves[0].spawns[0]: behaviour.type must be one of"],
		[_sandbox_with({"waves": [_wave_data({"behaviour": {"type": "patrol", "waypoints": [[0, 0, 0]]}})]}), "waves[0].spawns[0]: behaviour.waypoints"],
		[_sandbox_with({"waves": [_wave_data(), _wave_data()], "loop": {"from_wave": 5}}), "loop.from_wave 5 is beyond the 2 waves"],
	]
	for case: Array in cases:
		var result: Dictionary = ScenarioLoader.from_data(case[0], "case")
		assert_false(result["ok"], "should be rejected: %s" % case[1])
		assert_string_contains(String(result["error"]), String(case[1]))
		assert_eq((result["waves"] as Array).size(), 0, "a failed load returns no waves")


func test_a_wave_cannot_spawn_more_than_its_pool_holds() -> void:
	var spawns: Array = []
	for i: int in 5:
		spawns.append(_wave_data()["spawns"][0])
	var data: Dictionary = _sandbox_with({"waves": [{"name": "TOO MANY", "delay_s": 1, "spawns": spawns}]})
	var result: Dictionary = ScenarioLoader.from_data(data, "case")
	assert_false(result["ok"])
	assert_string_contains(result["error"], "waves[0]: 5 spawns of raider_fighter but pools.raider_fighter holds 4")


# --- routes and ships at load (M3-T09) -----------------------------------------------------------------------------


const INSTRUCTOR_ROUTE_PATH: String = "res://data/scenarios/instructor_route.json"


func _route_data(extra: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {"name": "LESSON", "waypoints": [{"position": [0, 0, -500]}, {"position": [100, 0, -1500], "demo": "roll"}]}
	base.merge(extra, true)
	return base


func _lesson_with(extra: Dictionary) -> Dictionary:
	var data: Dictionary = _minimal()
	data["pools"] = {"starfury_ally": 1}
	data["routes"] = [_route_data()]
	data.merge(extra, true)
	return data


func _ship_data(extra: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {"type": "starfury_ally", "name": "INSTRUCTOR", "offset": [0, 0, -200], "invulnerable": true,
			"route": "LESSON", "behaviour": {"type": "ai", "profile": "instructor"}}
	base.merge(extra, true)
	return base


func test_the_instructor_route_file_validates() -> void:
	var result: Dictionary = ScenarioLoader.load(INSTRUCTOR_ROUTE_PATH)
	assert_true(result["ok"], result["error"])
	assert_eq(result["scenario_id"], &"instructor_route")
	var props: Array[Dictionary] = result["props"]
	assert_eq(props.size(), EXPECTED_BUOYS.size(), "the five buoys")
	for i: int in EXPECTED_BUOYS.size():
		assert_eq(props[i]["name"], EXPECTED_BUOYS[i][0])
	assert_eq((result["waves"] as Array).size(), 0, "no waves")
	assert_eq(result["pools"], {&"starfury_ally": 1}, "one allied Starfury: the instructor")
	var routes: Array[Route] = result["routes"]
	assert_eq(routes.size(), 1)
	var route: Route = routes[0]
	assert_eq(route.cruise_mps, 60.0)
	assert_eq(route.pace, Route.PACE_PLAYER)
	assert_false(route.loop)
	var demos: Array[StringName] = []
	for w: Route.Waypoint in route.waypoints:
		if w.demo != &"":
			demos.append(w.demo)
	assert_eq(route.count(), 6)
	assert_eq(route.waypoint(0).demo, &"", "a first leg to settle in")
	assert_eq(demos.size(), Manoeuvres.NAMES.size(), "one demo each ...")
	for demo: StringName in Manoeuvres.NAMES:
		assert_true(demos.has(demo), "... including %s" % demo)
	var player_pos: UniversePos = result["player"]["position"]
	for i: int in route.count():
		var w: Route.Waypoint = route.waypoint(i)
		for prop: Dictionary in props:
			assert_gt(w.position.distance_to(prop["position"]), 140.0, "NAV %d keeps clear of %s" % [i + 1, prop["name"]])
		assert_lt(player_pos.distance_to(w.position), 5000.0, "NAV %d within sensor range of the start" % [i + 1])
	var spawns: Array[Dictionary] = result["spawns"]
	assert_eq(spawns.size(), 1)
	var instructor: Dictionary = spawns[0]
	assert_eq(instructor["type"], &"starfury_ally")
	assert_eq(instructor["name"], "INSTRUCTOR")
	assert_true(instructor["invulnerable"])
	assert_eq(instructor["route"], route.name)
	assert_eq(instructor["anchor"], &"player")
	assert_eq(instructor["offset"], Vector3(0.0, 0.0, -200.0), "200 m ahead of the player")
	assert_eq(instructor["behaviour"], {"type": "ai", "profile": "instructor"})


func test_routes_parse_into_universe_waypoints_with_defaults() -> void:
	var data: Dictionary = _lesson_with({"system_id": "epsilon"})
	(data["routes"][0]["waypoints"] as Array).append({"position": [0, 0, -2500], "hold_s": 2})
	var result: Dictionary = ScenarioLoader.from_data(data, "case")
	assert_true(result["ok"], result["error"])
	var route: Route = (result["routes"] as Array)[0]
	assert_eq(route.name, "LESSON")
	assert_eq(route.cruise_mps, Route.DEFAULT_CRUISE_MPS)
	assert_eq(route.pace, Route.PACE_PLAYER)
	assert_false(route.loop)
	assert_eq(route.pace_id, 0, "the spawner sets the pace ship")
	assert_eq(route.count(), 3)
	var w: Route.Waypoint = route.waypoint(1)
	assert_eq([w.position.x, w.position.y, w.position.z], [100.0, 0.0, -1500.0])
	assert_eq(w.position.system_id, &"epsilon")
	assert_eq(w.demo, &"roll")
	assert_eq(route.waypoint(0).demo, &"")
	assert_eq(route.waypoint(2).hold_s, 2.0)
	var custom: Dictionary = _lesson_with({"routes": [_route_data({"cruise_mps": 80, "pace": "none", "loop": true})]})
	var custom_route: Route = (ScenarioLoader.from_data(custom)["routes"] as Array)[0]
	assert_eq(custom_route.cruise_mps, 80.0)
	assert_eq(custom_route.pace, Route.PACE_NONE)
	assert_true(custom_route.loop)


func test_ships_at_load_take_the_spawn_fields_plus_invulnerable_and_route() -> void:
	var result: Dictionary = ScenarioLoader.from_data(_lesson_with({"spawns": [_ship_data(), _ship_data({"name": "SPARE",
			"invulnerable": false, "route": null, "behaviour": {"type": "idle"}})], "pools": {"starfury_ally": 2}}), "case")
	assert_true(result["ok"], result["error"])
	var spawns: Array[Dictionary] = result["spawns"]
	assert_eq(spawns[0]["route"], "LESSON")
	assert_true(spawns[0]["invulnerable"])
	assert_eq(spawns[1]["route"], "", "no route")
	assert_false(spawns[1]["invulnerable"])
	var plain: Dictionary = ScenarioLoader.load(ScenarioLoader.SANDBOX_PATH)
	assert_eq((plain["spawns"] as Array).size(), 0, "a scenario without ships at load")
	assert_eq((plain["routes"] as Array).size(), 0)


func test_route_and_ship_errors_name_the_json_path() -> void:
	var cases: Array[Array] = [
		[_lesson_with({"routes": {}}), "case: routes must be an array"],
		[_lesson_with({"routes": [3]}), "case: routes[0] must be an object"],
		[_lesson_with({"routes": [_route_data({"name": ""})]}), "routes[0].name must be a non-empty string"],
		[_lesson_with({"routes": [_route_data(), _route_data()]}), "routes[1].name: duplicate route 'LESSON'"],
		[_lesson_with({"routes": [_route_data({"cruise_mps": 0})]}), "routes[0].cruise_mps must be a number above 0"],
		[_lesson_with({"routes": [_route_data({"pace": "wingman"})]}), "routes[0].pace must be one of"],
		[_lesson_with({"routes": [_route_data({"loop": "yes"})]}), "routes[0].loop must be true or false"],
		[_lesson_with({"routes": [_route_data({"waypoints": []})]}), "routes[0].waypoints must be a non-empty array"],
		[_lesson_with({"routes": [_route_data({"waypoints": [{"position": [0, 0, 0]}, 7]})]}), "routes[0].waypoints[1] must be an object"],
		[_lesson_with({"routes": [_route_data({"waypoints": [{"position": [0, 0]}]})]}), "routes[0].waypoints[0].position must be [x, y, z]"],
		[_lesson_with({"routes": [_route_data({"waypoints": [{"position": [0, 0, 0], "demo": "barrel_roll"}]})]}),
				"routes[0].waypoints[0].demo must be one of roll, flip_and_burn, strafe_box, pod_turn, all_stop"],
		[_lesson_with({"routes": [_route_data({"waypoints": [{"position": [0, 0, 0], "hold_s": -1}]})]}),
				"routes[0].waypoints[0].hold_s must be a number, 0 or more"],
		[_lesson_with({"spawns": {}}), "case: spawns must be an array"],
		[_lesson_with({"spawns": [_ship_data({"type": "battleship"})]}), "spawns[0]: type must be one of"],
		[_lesson_with({"spawns": [_ship_data({"behaviour": {"type": "ai"}})]}), "spawns[0]: behaviour.profile"],
		[_lesson_with({"spawns": [_ship_data({"invulnerable": 1})]}), "spawns[0].invulnerable must be true or false"],
		[_lesson_with({"spawns": [_ship_data({"route": "NOWHERE"})]}), "spawns[0].route 'NOWHERE' is not a route of this scenario (LESSON)"],
		[_lesson_with({"spawns": [_ship_data({"behaviour": {"type": "idle"}})]}), "spawns[0].route needs an \"ai\" behaviour"],
		[_lesson_with({"spawns": [_ship_data(), _ship_data({"name": "TWO"})]}), "spawns: 2 ships of starfury_ally but pools.starfury_ally holds 1"],
	]
	for case: Array in cases:
		var result: Dictionary = ScenarioLoader.from_data(case[0], "case")
		assert_false(result["ok"], "should be rejected: %s" % case[1])
		assert_string_contains(String(result["error"]), String(case[1]))
		assert_eq((result["spawns"] as Array).size(), 0, "a failed load spawns nothing")
		assert_eq((result["routes"] as Array).size(), 0)


func test_ships_at_load_and_a_wave_share_the_pool() -> void:
	var data: Dictionary = _sandbox_with({"spawns": [{"type": "raider_fighter", "offset": [0, 0, -900]}],
			"waves": [{"name": "FULL", "delay_s": 1, "spawns": [_wave_data()["spawns"][0], _wave_data()["spawns"][0],
				_wave_data()["spawns"][0], _wave_data()["spawns"][0]]}]})
	var result: Dictionary = ScenarioLoader.from_data(data, "case")
	assert_false(result["ok"])
	assert_string_contains(result["error"], "waves[0]: 4 spawns of raider_fighter and 1 ship at load but pools.raider_fighter holds 4")
