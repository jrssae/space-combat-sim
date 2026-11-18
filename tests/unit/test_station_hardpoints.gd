extends GutTest
## `StationHardpoints` (M7-T05): the station manifest's hardpoints read into Godot types, each in its piece's frame.


func _section() -> Dictionary:
	return {"hardpoints": {
		"spin_rad_s": 0.148,
		"cobra_bays": [{"name": "cobra_bay_alpha_1", "wing": "alpha", "arm": "top", "door_number": 1, "body": "drum", "door": [0.0, 239.0, -1960.0],
				"door_half_m": [10.0, 7.0], "normal": [0.0, 1.0, 0.0], "rail_start": [18.0, 230.0, -1960.0],
				"rail_end": [0.0, 239.0, -1960.0], "release": [0.0, 247.0, -1960.0], "release_direction": [0.0, 1.0, 0.0],
				"surface_velocity": [-36.556, 0.0, 0.0], "forward": [0.0, 0.0, -1.0], "up": [0.0, -1.0, 0.0],
				"leaves": [{"leaf": "r", "point": [27.6, 239.0, -1960.0], "axis": [0.0, 0.0, 1.0]}],
				"staging": [-4.0, 230.0, -1960.0], "staging_path": [[-4.0, 230.0, -1960.0], [-4.0, 227.0, -1960.0], [18.0, 227.0, -1960.0],
						[18.0, 230.0, -1960.0]]}],
		"main_docking_bay": {"name": "main_docking_bay", "body": "drum", "main_docking_bay_mouth": [0.0, 0.0, -2550.0],
				"main_docking_bay_airlock": [0.0, 0.0, -2360.0], "axis": [0.0, 0.0, 1.0], "up": [0.0, 1.0, 0.0],
				"main_docking_bay_approach": [[0.0, 0.0, -4050.0], [0.0, 0.0, -2850.0]], "main_docking_bay_clear_half_m": [47.0, 17.0],
				"spin_axis": [0.0, 0.0, 1.0], "spin_rad_s": 0.148, "pivot": [0.0, 0.0, -1000.0]},
		"cargo_bay": {"name": "cargo_bay", "body": "frame", "cargo_bay_hold": [0.0, 346.0, -4700.0],
				"cargo_bay_release": [0.0, 346.0, -4640.0], "cargo_bay_entry": [0.0, 346.0, -3535.0],
				"cargo_bay_path": [[0.0, 346.0, -4640.0], [0.0, 346.0, -3580.0], [0.0, 346.0, -3535.0]]},
		"launch_clearance": {"blocked_sectors_deg": [[58.5, 126.5]], "clear_distance_m": 250.0, "margin_deg": 10.0},
		"grid_mounts": [{"name": "H1", "kind": "heavy_cannon", "body": "frame", "position": [-45.0, 375.0, -3485.0],
				"up": [0.0, 0.9915, -0.1302]}],
		"lights": [{"name": "beacon_bow_port", "kind": "beacon", "body": "frame", "position": [-53.5, 329.0, -3999.5],
				"colour": "#FF2A1A", "blink": true},
			{"name": "ring_fwd_band_fore", "kind": "ring", "body": "drum", "position": [0.0, 417.5, -1200.0], "colour": "#FFF4E0",
				"radius": 417.5, "axis": [0.0, 0.0, 1.0], "dashes": 48}],
		"tour_points": [{"name": "bow", "body": "frame", "position": [260.0, 520.0, -4700.0], "look_at": [0.0, 250.0, -3550.0],
				"direction": [-0.21, -0.22, 0.95]}],
		"damage_sections": [{"name": "command", "body": "frame", "sections": ["bow", "bow_ring"], "aabb_min": [-185.0, 0.0, -4000.0],
				"aabb_max": [185.0, 470.0, -3300.0]}],
	}}


func test_reads_every_kind_in_its_bodys_frame() -> void:
	var hp: StationHardpoints = StationHardpoints.from_manifest(_section())
	assert_true(hp.valid, hp.error)
	assert_almost_eq(hp.spin_rad_s, 0.148, 1e-6)
	var bay: Dictionary = hp.bay("cobra_bay_alpha_1")
	assert_eq(bay["body"], StationHardpoints.DRUM)
	assert_eq(bay["release"], Vector3(0.0, 247.0, -1960.0))
	assert_eq(bay["door_half_m"], Vector2(10.0, 7.0))
	assert_eq((bay["leaves"] as Array)[0]["point"], Vector3(27.6, 239.0, -1960.0))
	assert_eq(bay["wing"], "alpha")
	assert_eq(hp.bays_of("alpha").size(), 1)
	assert_true(hp.bays_of("zeta").is_empty())
	assert_eq(bay["staging"], Vector3(-4.0, 230.0, -1960.0))
	assert_eq((bay["staging_path"] as Array).size(), 4)
	assert_eq((hp.main_docking_bay["main_docking_bay_approach"] as Array).size(), 2)
	assert_eq(hp.main_docking_bay["main_docking_bay_clear_half_m"], Vector2(47.0, 17.0))
	assert_eq(hp.main_docking_bay["spin_axis"], Vector3.BACK)
	assert_almost_eq(float(hp.main_docking_bay["spin_rad_s"]), 0.148, 1e-6)
	assert_eq(hp.cargo_bay["body"], StationHardpoints.FRAME)
	assert_eq(hp.cargo_bay["cargo_bay_entry"], Vector3(0.0, 346.0, -3535.0))
	assert_eq((hp.cargo_bay["cargo_bay_path"] as Array).size(), 3)
	assert_eq(hp.mount("H1")["kind"], "heavy_cannon")
	assert_true(hp.mount("H1")["position"] is Vector3)
	assert_eq(hp.lights_of("beacon").size(), 1)
	assert_true(hp.lights_of("beacon")[0]["blink"])
	assert_true((hp.lights_of("ring")[0]["colour"] as Color).is_equal_approx(Color.html("#FFF4E0")))
	assert_eq(hp.tour("bow")["look_at"], Vector3(0.0, 250.0, -3550.0))
	assert_eq(hp.damage_sections[0]["sections"], PackedStringArray(["bow", "bow_ring"]))
	assert_eq((hp.damage_sections[0]["aabb"] as AABB).size, Vector3(370.0, 470.0, 700.0))
	assert_eq(hp.bay("nowhere"), {})


func test_a_launch_waits_while_its_arm_points_at_the_frame() -> void:
	var hp: StationHardpoints = StationHardpoints.from_manifest(_section())
	assert_true(hp.launch_blocked(90.0), "the top arm at rest, under the spine")
	assert_true(hp.launch_blocked(90.0 + 360.0))
	assert_false(hp.launch_blocked(0.0))
	assert_false(hp.launch_blocked(270.0))
	hp.launch_clearance = {"blocked_sectors_deg": [[350.0, 10.0]]}
	assert_true(hp.launch_blocked(-5.0), "a sector across 0 degrees")
	assert_false(hp.launch_blocked(20.0))


func test_a_drum_point_turns_with_the_drum() -> void:
	var pivot := Vector3(0.0, 0.0, -1000.0)
	var p := Vector3(0.0, 251.0, -1960.0)
	assert_eq(StationHardpoints.to_station(p, StationHardpoints.FRAME, pivot, 1.0), p, "the frame stands still")
	var turned: Vector3 = StationHardpoints.to_station(p, StationHardpoints.DRUM, pivot, PI / 2.0)
	assert_almost_eq(turned.x, -251.0, 1e-3, "a quarter turn about +Z carries the top arm to port")
	assert_almost_eq(turned.y, 0.0, 1e-3)
	assert_almost_eq(turned.z, -2960.0, 1e-3)


func test_a_broken_section_is_refused() -> void:
	assert_false(StationHardpoints.from_manifest({}).valid)
	var bad: Dictionary = _section()
	bad["hardpoints"]["grid_mounts"][0]["body"] = "hull"
	var hp: StationHardpoints = StationHardpoints.from_manifest(bad)
	assert_false(hp.valid)
	assert_string_contains(hp.error, "grid_mounts")
	bad = _section()
	bad["hardpoints"]["cobra_bays"][0]["release"] = [1.0, 2.0]
	assert_string_contains(StationHardpoints.from_manifest(bad).error, "release")


## The generated station's hardpoints read whole (skipped before the assets are generated).
func test_the_generated_station_reads() -> void:
	var manifest: Dictionary = MeshAssets.read_manifest("babylon5_station")
	if manifest.is_empty() or not manifest.has("hardpoints"):
		pass_test("the station is not generated with hardpoints here")
		return
	var hp: StationHardpoints = StationHardpoints.from_manifest(manifest)
	assert_true(hp.valid, hp.error)
	assert_eq(hp.cobra_bays.size(), 24)
	for wing: String in ["alpha", "beta", "delta", "zeta"]:
		assert_eq(hp.bays_of(wing).size(), 6, wing)
	assert_eq(hp.grid_mounts.size(), 23)
	assert_false(hp.tour("cobra_arm").is_empty())
	assert_false(hp.main_docking_bay.is_empty())
	assert_false(hp.cargo_bay.is_empty())
