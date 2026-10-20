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
