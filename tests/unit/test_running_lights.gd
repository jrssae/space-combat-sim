extends GutTest
## Running lights and own lights, the pure parts (M3-T27, AC36, AC37): the fork's per-instance light records and the shader's
## sums mirrored on the CPU, the sign of the instance frame on real generated hulls, which lights a ship carries when lit or dark,
## the hardpoints, the dark rule's data and the buoys' slow fade.

const STARFURY_HARDPOINTS: String = "res://assets/generated/starfury_aurora/hardpoints.json"
const RAIDER_HARDPOINTS: String = "res://assets/generated/raider_fighter/hardpoints.json"
const WHITE: Color = Color(1.0, 1.0, 1.0)
const RED: Color = Color(1.0, 0.0, 0.0)


func _hardpoints(path: String) -> Hardpoints:
	var hp: Hardpoints = Hardpoints.load_file(path)
	assert_true(hp.valid, hp.error)
	return hp


# --- the fork's records ----------------------------------------------------------------------------------------------


func test_a_surface_light_packs_position_inverse_range_tint_and_no_view_range() -> void:
	var light: PackedFloat32Array = GaussianOwnLights.surface(Vector3(1.0, 2.0, 3.0), Color(0.5, 1.0, 0.25), 4.0, 8.0)
	assert_eq(light.size(), GaussianOwnLights.FLOATS_PER_LIGHT)
	assert_eq(Array(light), [1.0, 2.0, 3.0, 0.125, 2.0, 4.0, 1.0, 0.0])


func test_a_glow_packs_its_view_range_where_a_surface_light_has_none() -> void:
	var light: PackedFloat32Array = GaussianOwnLights.glow(Vector3.ZERO, RED, 0.5, 2.0, 150.0)
	assert_eq(Array(light), [0.0, 0.0, 0.0, 0.5, 0.5, 0.0, 0.0, 150.0])


func test_a_splat_facing_the_light_within_range_gains_and_one_facing_away_gains_none() -> void:
	# The test shape of AC37: a lamp 2 m above two splats at the origin, one facing it, one facing away.
	var lamp: PackedFloat32Array = GaussianOwnLights.surface(Vector3(0.0, 2.0, 0.0), WHITE, 2.0, 6.0)
	var facing: Dictionary = GaussianOwnLights.evaluate(lamp, Vector3.ZERO, Vector3.UP, 10.0)
	var away: Dictionary = GaussianOwnLights.evaluate(lamp, Vector3.ZERO, Vector3.DOWN, 10.0)
	assert_gt((facing["direct"] as Vector3).x, 0.5, "faces the lamp, in range")
	assert_eq(away["direct"], Vector3.ZERO, "faces away: nothing")
	assert_eq(facing["glow"], Vector3.ZERO, "a surface light adds no glow")


func test_a_surface_light_stops_at_its_range_and_follows_the_shaders_falloff() -> void:
	var lamp: PackedFloat32Array = GaussianOwnLights.surface(Vector3(0.0, 2.0, 0.0), WHITE, 1.0, 4.0)
	assert_eq(GaussianOwnLights.evaluate(lamp, Vector3(0.0, -3.0, 0.0), Vector3.UP, 0.0)["direct"], Vector3.ZERO, "past its range")
	# At 2 m of 4 m: (1 - 0.5^4)^2 / 2, Godot's omni falloff with decay 1.
	var expected: float = pow(1.0 - pow(0.5, 4.0), 2.0) / 2.0
	assert_almost_eq((GaussianOwnLights.evaluate(lamp, Vector3.ZERO, Vector3.UP, 0.0)["direct"] as Vector3).x, expected, 1e-5)


func test_a_glow_ignores_the_surface_and_fades_with_the_viewers_distance() -> void:
	var glow: PackedFloat32Array = GaussianOwnLights.glow(Vector3.ZERO, RED, 0.4, 2.0, 150.0)
	var up: Dictionary = GaussianOwnLights.evaluate(glow, Vector3(0.0, 0.5, 0.0), Vector3.UP, 10.0)
	var down: Dictionary = GaussianOwnLights.evaluate(glow, Vector3(0.0, 0.5, 0.0), Vector3.DOWN, 10.0)
	assert_gt((up["glow"] as Vector3).x, 0.1, "seen through glass: any splat near it glows")
	assert_eq(up["glow"], down["glow"], "whichever way it faces")
	assert_eq(up["direct"], Vector3.ZERO, "and it is not surface light")
	var at: Vector3 = Vector3(0.0, 0.5, 0.0)
	assert_eq(GaussianOwnLights.evaluate(glow, at, Vector3.UP, 151.0)["glow"], Vector3.ZERO, "out of view past 150 m")
	assert_lt((GaussianOwnLights.evaluate(glow, at, Vector3.UP, 140.0)["glow"] as Vector3).x, (up["glow"] as Vector3).x, "fading")
	assert_eq(GaussianOwnLights.evaluate(glow, Vector3(0.0, 2.5, 0.0), Vector3.UP, 10.0)["glow"], Vector3.ZERO, "past its range")


func test_a_glow_shows_in_dark_paint_but_not_on_the_hull() -> void:
	var term := Vector3(0.3, 0.05, 0.03)
	assert_eq(GaussianOwnLights.glow_on_paint(term, Vector3(0.01, 0.01, 0.01)), term, "a dark canopy panel takes all of it")
	assert_eq(GaussianOwnLights.glow_on_paint(term, Vector3(0.01, 0.06, 0.03)), term, "and so does tinted glass")
	assert_eq(GaussianOwnLights.glow_on_paint(term, Vector3(0.6, 0.6, 0.63)), Vector3.ZERO, "a light hull takes none")


func test_two_lights_add_up_and_a_third_is_past_the_record() -> void:
	var lamp: PackedFloat32Array = GaussianOwnLights.surface(Vector3(0.0, 2.0, 0.0), WHITE, 2.0, 6.0)
	var both: PackedFloat32Array = lamp + lamp
	var one: Vector3 = GaussianOwnLights.evaluate(lamp, Vector3.ZERO, Vector3.UP, 0.0)["direct"]
	assert_almost_eq((GaussianOwnLights.evaluate(both, Vector3.ZERO, Vector3.UP, 0.0)["direct"] as Vector3).x, 2.0 * one.x, 1e-5)
	assert_eq(GaussianOwnLights.MAX_OWN_LIGHTS, 2)
	var node := GaussianSplatNode.new()
	autofree(node)
	node.set_own_lights(lamp + lamp + lamp)
	assert_eq(node.own_light_count(), GaussianOwnLights.MAX_OWN_LIGHTS, "the third is dropped")
	assert_eq(node.get_own_lights().size(), 2 * GaussianOwnLights.FLOATS_PER_LIGHT)
	assert_push_warning("own lights")


func test_the_instance_frame_undoes_the_nodes_rotation() -> void:
	# GDGS turns a splat node 180 degrees about Z, so the ship's +Y and +X are the instance's -Y and -X.
	var p: Vector3 = GaussianOwnLights.to_instance_frame(Vector3(1.0, 2.0, 3.0), GaussianSplatNode.get_model_orientation_correction())
	assert_almost_eq(p.x, -1.0, 1e-5)
	assert_almost_eq(p.y, -2.0, 1e-5)
	assert_almost_eq(p.z, 3.0, 1e-5)


# --- the sign, on real hulls --------------------------------------------------------------------------------------------


# The top lamp's light on one hull's real splats and records, by which side of the ship they are on. A wrong frame lights the belly.
func _top_lamp_on_real_splats(asset: String, path: String) -> Dictionary:
	var resource := load("res://assets/generated/%s/%s_lod3.ply" % [asset, asset]) as GaussianResource
	var records: FileAccess = FileAccess.open("res://assets/generated/%s/%s_lod3.light" % [asset, asset], FileAccess.READ)
	assert_not_null(resource, "run scripts/gen_assets.sh")
	var bytes: PackedByteArray = records.get_buffer(records.get_length())
	var floats: PackedFloat32Array = resource.point_data_byte.to_float32_array()
	var hp: Hardpoints = _hardpoints(path)
	var lights: PackedFloat32Array = NavLights.own_lights(hp.nav_lights, true, 2.5, 0.0, 150.0,
			GaussianSplatNode.get_model_orientation_correction())
	var top_sum := 0.0
	var belly_sum := 0.0
	var pose: Transform3D = GaussianSplatNode.get_model_orientation_correction()
	for i: int in resource.point_count:
		var at := Vector3(floats[i * 60], floats[i * 60 + 1], floats[i * 60 + 2])
		var encoded := Vector2(bytes[i * 4], bytes[i * 4 + 1]) / 255.0 * 2.0 - Vector2.ONE
		var normal: Vector3 = GaussianLightingResource.oct_decode(encoded)
		var gain: float = (GaussianOwnLights.evaluate(lights, at, normal, 0.0)["direct"] as Vector3).x
		if (pose * normal).y > 0.5:
			top_sum += gain
		elif (pose * normal).y < -0.5:
			belly_sum += gain
	return {"top": top_sum, "belly": belly_sum}


func test_the_top_lamp_lights_the_top_of_the_starfury_and_not_its_belly() -> void:
	var sums: Dictionary = _top_lamp_on_real_splats("starfury_aurora", STARFURY_HARDPOINTS)
	assert_gt(float(sums["top"]), 1.0, "splats on top take the light")
	assert_lt(float(sums["belly"]), 0.02 * float(sums["top"]), "the belly takes next to none (its slanted faces a little)")


func test_the_top_lamp_lights_the_top_of_the_raider_and_not_its_belly() -> void:
	var sums: Dictionary = _top_lamp_on_real_splats("raider_fighter", RAIDER_HARDPOINTS)
	assert_gt(float(sums["top"]), 1.0, "splats on top take the light")
	assert_lt(float(sums["belly"]), 0.02 * float(sums["top"]), "the belly takes next to none (its slanted faces a little)")


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


func test_a_lit_ship_carries_the_top_light_and_the_glow_and_a_dark_one_only_the_glow() -> void:
	var nav: Dictionary = _hardpoints(STARFURY_HARDPOINTS).nav_lights
	var pose: Transform3D = GaussianSplatNode.get_model_orientation_correction()
	var lit: PackedFloat32Array = NavLights.own_lights(nav, true, 2.5, 0.3, 150.0, pose)
	assert_eq(lit.size(), 2 * GaussianOwnLights.FLOATS_PER_LIGHT, "the white top light and the red glow")
	var dark: PackedFloat32Array = NavLights.own_lights(nav, false, 2.5, 0.3, 150.0, pose)
	assert_eq(dark.size(), GaussianOwnLights.FLOATS_PER_LIGHT, "a dark ship keeps its cockpit glow")
	assert_eq(dark[GaussianOwnLights.FLOATS_PER_LIGHT - 1], 150.0, "and that one is the glow")
	assert_gt(dark[4], 5.0 * dark[5], "red")


func test_own_light_positions_go_into_the_instance_frame() -> void:
	var nav: Dictionary = _hardpoints(STARFURY_HARDPOINTS).nav_lights
	var lit: PackedFloat32Array = NavLights.own_lights(nav, true, 2.5, 0.3, 150.0, GaussianSplatNode.get_model_orientation_correction())
	var lamp: Vector3 = nav["top_lamp"]
	assert_almost_eq(lit[1], -lamp.y, 1e-4, "the top of the ship is the instance's -Y")
	assert_almost_eq(lit[2], lamp.z, 1e-4)


func test_no_hardpoints_no_own_lights_and_no_markers() -> void:
	assert_true(NavLights.own_lights({}, true, 2.5, 0.3, 150.0, Transform3D.IDENTITY).is_empty())
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
	var bad: Dictionary = BrainFactory.from_behaviour({"type": "idle", "running_lights": "maybe"}, UniversePos.new(), 1)
	assert_false(bad["ok"])
	assert_string_contains(bad["error"], "behaviour.running_lights")


func test_only_an_attack_counts_as_attacking() -> void:
	assert_false(_brain({"type": "patrol", "waypoints": WAYPOINTS}).is_attacking())
	assert_false(_brain({"type": "idle"}).is_attacking())
	assert_true(_brain({"type": "attack"}).is_attacking())
	var aggro := _brain({"type": "aggro", "waypoints": WAYPOINTS}) as AggroBrain
	assert_false(aggro.is_attacking(), "still patrolling")
	aggro.aggroed = true
	assert_true(aggro.is_attacking())
	var pilot := _brain({"type": "ai", "profile": "raider"}) as AiPilot
	assert_false(pilot.is_attacking(), "no behaviour in control yet")
	pilot.current = pilot.behaviour(&"idle")
	assert_false(pilot.is_attacking())
	pilot.current = pilot.behaviour(&"attack")
	assert_true(pilot.is_attacking())
	pilot.current = pilot.behaviour(&"ram")
	assert_true(pilot.is_attacking())


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
