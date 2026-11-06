extends GutTest
## Running lights, the pure parts (M3-T27, AC36): the hardpoints, the markers' colours, the dark rule's data and the buoys' slow fade.

const STARFURY_HARDPOINTS: String = "res://assets/generated/starfury_aurora/hardpoints.json"
const RAIDER_HARDPOINTS: String = "res://assets/generated/raider_fighter/hardpoints.json"


func _hardpoints(path: String) -> Hardpoints:
	var hp: Hardpoints = Hardpoints.load_file(path)
	assert_true(hp.valid, hp.error)
	return hp


# --- the hardpoints ------------------------------------------------------------------------------------------------------


func test_every_ship_type_names_its_lights_in_its_hardpoints() -> void:
	for path: String in [STARFURY_HARDPOINTS, RAIDER_HARDPOINTS]:
		var nav: Dictionary = _hardpoints(path).nav_lights
		for key: String in ["port", "starboard", "top", "top_lamp", "cabin"]:
			assert_true(nav.get(key) is Vector3, "%s: %s" % [path, key])
		assert_gt(float(nav["top_lamp_range_m"]), 0.0)
		assert_gt(float(nav["cabin_range_m"]), 0.0)
		assert_lt((nav["port"] as Vector3).x, 0.0, "%s: port on the ship's left" % path)
		assert_gt((nav["starboard"] as Vector3).x, 0.0, "%s: starboard on its right" % path)


func test_hardpoints_without_lights_are_still_valid_and_broken_lights_are_not() -> void:
	var text: String = FileAccess.get_file_as_string(RAIDER_HARDPOINTS)
	var data: Dictionary = JSON.parse_string(text)
	data.erase("nav_lights")
	var none: Hardpoints = Hardpoints.from_dict(data)
	assert_true(none.valid, none.error)
	assert_true(none.nav_lights.is_empty())
	data["nav_lights"] = {"port": [1.0, 2.0]}
	var broken: Hardpoints = Hardpoints.from_dict(data)
	assert_false(broken.valid)
	assert_string_contains(broken.error, "nav_lights")


# --- what a ship carries ---------------------------------------------------------------------------------------------------


func test_red_is_port_green_is_starboard_white_is_top() -> void:
	var nav: Dictionary = _hardpoints(STARFURY_HARDPOINTS).nav_lights
	var markers: Array[Dictionary] = NavLights.markers(nav)
	assert_eq(markers.size(), 3)
	for marker: Dictionary in markers:
		var color: Color = marker["color"]
		var at: Vector3 = marker["position"]
		if at.x < -1.0:
			assert_gt(color.r, 3.0 * color.g, "the marker on the ship's left is red")
		elif at.x > 1.0:
			assert_gt(color.g, 3.0 * color.r, "the marker on its right is green")
		else:
			assert_almost_eq(color.r, color.g, 0.5, "the one on the centre line is white")


func test_no_hardpoints_no_markers() -> void:
	assert_true(NavLights.markers({}).is_empty())


# --- the dark rule's data --------------------------------------------------------------------------------------------------


func _brain(spec: Dictionary) -> PilotBrain:
	var made: Dictionary = BrainFactory.from_behaviour(spec, UniversePos.new(), 1)
	assert_true(made["ok"], made["error"])
	return made["brain"]


const WAYPOINTS: Array = [[0, 0, -500], [500, 0, -900]]


func test_who_starts_dark_by_default() -> void:
	assert_true(_brain({"type": "patrol", "waypoints": WAYPOINTS}).flies_dark, "a patrol hides")
	assert_true(_brain({"type": "aggro", "waypoints": WAYPOINTS}).flies_dark, "an aggro brain starts out patrolling")
	assert_true(_brain({"type": "ai", "profile": "raider", "patrol": {"waypoints": WAYPOINTS}}).flies_dark, "an AI patrol too")
	assert_false(_brain({"type": "attack"}).flies_dark, "an attack-wave raider is lit")
	assert_false(_brain({"type": "ai", "profile": "raider"}).flies_dark)
	assert_false(_brain({"type": "idle"}).flies_dark, "an idle target is lit")


func test_a_spawn_can_set_it_either_way() -> void:
	assert_true(_brain({"type": "ai", "profile": "raider", "running_lights": "off"}).flies_dark)
	assert_false(_brain({"type": "patrol", "waypoints": WAYPOINTS, "running_lights": "on"}).flies_dark)
	assert_true(_brain({"type": "idle", "running_lights": "off"}).flies_dark)
	for wrong: Variant in ["maybe", true, 1]:
		var refused: Dictionary = BrainFactory.from_behaviour({"type": "idle", "running_lights": wrong}, UniversePos.new(), 1)
		assert_false(refused["ok"], "running_lights %s" % str(wrong))
	var bad: Dictionary = BrainFactory.from_behaviour({"type": "idle", "running_lights": "maybe"}, UniversePos.new(), 1)
	assert_false(bad["ok"])
	assert_string_contains(bad["error"], "behaviour.running_lights")


func test_the_sandboxs_patrol_wave_starts_dark_and_its_strike_wave_lit() -> void:
	var scenario: Dictionary = ScenarioLoader.load(ScenarioLoader.SANDBOX_PATH)
	assert_true(scenario["ok"], scenario["error"])
	for wave: Dictionary in scenario["waves"]:
		var dark_wanted: bool = wave["name"] == "PATROL"
		for spawn: Dictionary in wave["spawns"]:
			assert_eq(_brain(spawn["behaviour"]).flies_dark, dark_wanted, "wave %s" % wave["name"])


# --- the toggle --------------------------------------------------------------------------------------------------------------


func test_the_toggle_is_a_press_edge_in_the_ui_command() -> void:
	var source := FakeInputSource.new()
	var adapter := InputAdapter.new()
	assert_true(InputAdapter.ACTIONS.has(InputAdapter.TOGGLE_RUNNING_LIGHTS))
	source.hold(InputAdapter.TOGGLE_RUNNING_LIGHTS)
	assert_true(adapter.sample(source, 1.0 / 60.0).ui.toggle_running_lights, "the press")
	assert_false(adapter.sample(source, 1.0 / 60.0).ui.toggle_running_lights, "held: once")


func _text_without_the_toggle(default: ControlProfile, edit: Callable = Callable()) -> String:
	var old: ControlProfile = default.duplicate_profile()
	old.bindings.erase(InputAdapter.TOGGLE_RUNNING_LIGHTS)
	old.deadzones.erase(InputAdapter.TOGGLE_RUNNING_LIGHTS)
	if edit.is_valid():
		edit.call(old)
	return old.to_config_text()


func test_a_profile_saved_before_the_toggle_gets_it() -> void:
	var default: ControlProfile = ControlProfiles.store.default_profile()
	var parsed: Dictionary = ControlProfile.from_config_text(_text_without_the_toggle(default), "mine", default)
	assert_true(parsed["ok"], str(parsed["errors"]))
	assert_true(PackedStringArray(parsed["filled"]).has("toggle_running_lights"))
	var mine: ControlProfile = parsed["profile"]
	assert_eq(mine.descriptors_for(InputAdapter.TOGGLE_RUNNING_LIGHTS), PackedStringArray(["pad:button:13", "key:5"]))


func test_a_saved_layout_that_uses_dpad_left_keeps_it_and_the_lights_keep_their_key() -> void:
	var default: ControlProfile = ControlProfiles.store.default_profile()
	var rolls_on_the_dpad := func(old: ControlProfile) -> void: old.bindings[&"roll_left"] = ["pad:button:13", "key:CapsLock"]
	var parsed: Dictionary = ControlProfile.from_config_text(_text_without_the_toggle(default, rolls_on_the_dpad), "mine", default)
	assert_true(parsed["ok"], str(parsed["errors"]))
	var mine: ControlProfile = parsed["profile"]
	assert_eq(mine.descriptors_for(&"roll_left"), PackedStringArray(["pad:button:13", "key:CapsLock"]), "its roll stays")
	assert_eq(mine.descriptors_for(InputAdapter.TOGGLE_RUNNING_LIGHTS), PackedStringArray(["key:5"]), "the lights are the key alone")
	assert_push_warning("toggle_running_lights")


# --- the buoys' fade ----------------------------------------------------------------------------------------------------------


func test_the_buoy_fade_breathes_over_six_seconds() -> void:
	assert_eq(NavBuoy.FADE_PERIOD_S, 6.0)
	assert_almost_eq(NavBuoy.fade_level(0.0, 0.0), 0.0, 1e-6, "out")
	assert_almost_eq(NavBuoy.fade_level(1.5, 0.0), 0.5, 1e-6, "half way in")
	assert_almost_eq(NavBuoy.fade_level(3.0, 0.0), 1.0, 1e-6, "in")
	assert_almost_eq(NavBuoy.fade_level(4.5, 0.0), 0.5, 1e-6, "half way out")
	assert_almost_eq(NavBuoy.fade_level(6.0, 0.0), 0.0, 1e-6, "out again")
	assert_almost_eq(NavBuoy.fade_level(1.0, 2.0), 1.0, 1e-6, "the phase shifts it")


func test_each_buoy_has_its_own_phase_every_run() -> void:
	var alpha: float = NavBuoy.fade_phase_of("NAV ALPHA")
	assert_eq(NavBuoy.fade_phase_of("NAV ALPHA"), alpha, "the same buoy, the same phase")
	assert_ne(NavBuoy.fade_phase_of("NAV BRAVO"), alpha, "another buoy, another")
	assert_true(alpha >= 0.0 and alpha < NavBuoy.FADE_PERIOD_S)
