extends GutTest
## The station's exterior lights as data (M7-T18): the drawn points grouped by piece and blink, the floods, the beacons' blink by
## sim time, which floods reach a hull section (on its own piece by cone and throw, from the other piece by the band the drum's turn
## sweeps), and the floods packed into a section's frame as the drum turns.

const DRUM_ORIGIN := Vector3(0.0, 0.0, -1000.0)


func _hardpoints() -> StationHardpoints:
	var red: Dictionary = {"radius_m": 4.5, "rgb": [1.0, 0.165, 0.102]}
	var manifest: Dictionary = {"hardpoints": {
		"cobra_bays": [], "grid_mounts": [], "tour_points": [], "damage_sections": [],
		"main_docking_bay": {"name": "main_docking_bay", "body": "drum"}, "cargo_bay": {"name": "cargo_bay", "body": "frame"},
		"lights": [
			{"name": "beacon_a", "kind": "beacon", "body": "frame", "position": [0.0, 300.0, -4000.0], "colour": "#FF2A1A",
					"blink": true, "blink_period_s": 3.0, "blink_on_s": 0.8, "marker": red},
			{"name": "nav_a", "kind": "nav", "body": "drum", "position": [305.0, 0.0, -1600.0], "colour": "#FF6A8A",
					"marker": {"radius_m": 3.6, "rgb": [1.0, 0.416, 0.541]}},
			{"name": "bay_light_alpha_1", "kind": "bay", "body": "drum", "position": [0.0, 230.0, -1900.0], "colour": "#FFA860"},
			# A frame flood 100 m ahead of z -3500 on the axis, aimed aft, 10 degrees wide, 300 m throw.
			{"name": "flood_f", "kind": "flood", "body": "frame", "position": [0.0, 0.0, -3600.0], "direction": [0.0, 0.0, 1.0],
					"outer_deg": 10.0, "inner_deg": 5.0, "range_m": 300.0, "rgb": [1.0, 0.5, 0.25], "energy": 2.0},
			# A drum flood at radius 200 (drum frame z -1700), aimed outward along +x.
			{"name": "flood_d", "kind": "flood", "body": "drum", "position": [200.0, 0.0, -1700.0], "direction": [1.0, 0.0, 0.0],
					"outer_deg": 30.0, "inner_deg": 15.0, "range_m": 150.0, "rgb": [1.0, 1.0, 1.0], "energy": 1.0},
		]}}
	var hp := StationHardpoints.from_manifest(manifest)
	assert_true(hp.valid, hp.error)
	return hp


func test_the_points_are_grouped_by_piece_and_blink() -> void:
	var plan := StationLightPlan.from_hardpoints(_hardpoints())
	assert_eq(plan.point_count(), 2, "a beacon and a nav light; the bay light has no marker")
	assert_eq((plan.points[StationLightPlan.FRAME_BLINK] as Array).size(), 1, "the beacon blinks on the frame")
	assert_eq((plan.points[StationLightPlan.DRUM_STEADY] as Array).size(), 1, "the nav light is steady on the drum")
	var nav: Dictionary = (plan.points[StationLightPlan.DRUM_STEADY] as Array)[0]
	assert_almost_eq(float(nav["radius_m"]), 3.6, 1e-6)
	assert_true((nav["colour"] as Color).is_equal_approx(Color(1.0, 0.416, 0.541)))
	assert_almost_eq(plan.blink_period_s, 3.0, 1e-6)
	assert_almost_eq(plan.blink_on_s, 0.8, 1e-6)


func test_the_floods_are_read_with_their_cone_and_light() -> void:
	var plan := StationLightPlan.from_hardpoints(_hardpoints())
	assert_eq(plan.floods.size(), 2)
	var f: Dictionary = plan.floods[0]
	assert_almost_eq(float(f["cos_outer"]), cos(deg_to_rad(10.0)), 1e-6)
	assert_almost_eq(float(f["cos_inner"]), cos(deg_to_rad(5.0)), 1e-6)
	assert_lt(float(f["cos_outer"]), float(f["cos_inner"]), "the outer edge is wider than the inner")
	assert_true((f["light"] as Color).is_equal_approx(Color(2.0, 1.0, 0.5)), "colour times energy")


func test_beacons_blink_by_sim_time() -> void:
	assert_true(StationLightPlan.blink_on(0.0, 3.0, 0.8), "lit at the start of a cycle")
	assert_true(StationLightPlan.blink_on(0.79, 3.0, 0.8))
	assert_false(StationLightPlan.blink_on(0.81, 3.0, 0.8), "dark after the lit part")
	assert_false(StationLightPlan.blink_on(2.99, 3.0, 0.8))
	assert_true(StationLightPlan.blink_on(3.0, 3.0, 0.8), "lit again a period later")
	assert_true(StationLightPlan.blink_on(-2.5, 3.0, 0.8), "before the epoch it keeps the same rhythm")
	assert_true(StationLightPlan.blink_on(3.0e8 + 0.2, 3.0, 0.8), "a system time far from zero keeps its phase")
	assert_false(StationLightPlan.blink_on(3.0e8 + 1.9, 3.0, 0.8))
	assert_true(StationLightPlan.blink_on(12.34, 0.0, 0.0), "no period: steady")


func test_a_flood_reaches_only_what_its_cone_and_throw_cover() -> void:
	var plan := StationLightPlan.from_hardpoints(_hardpoints())
	var ahead := AABB(Vector3(-20.0, -20.0, -3520.0), Vector3(40.0, 40.0, 40.0))
	var behind := AABB(Vector3(-20.0, -20.0, -3800.0), Vector3(40.0, 40.0, 40.0))
	var far := AABB(Vector3(-20.0, -20.0, -3200.0), Vector3(40.0, 40.0, 40.0))
	var aside := AABB(Vector3(150.0, -20.0, -3520.0), Vector3(40.0, 40.0, 40.0))
	assert_eq(Array(plan.section_floods("frame", ahead, DRUM_ORIGIN)["fixed"]), [0], "in its cone, within its throw")
	assert_eq(Array(plan.section_floods("frame", behind, DRUM_ORIGIN)["fixed"]), [], "behind the fixture")
	assert_eq(Array(plan.section_floods("frame", far, DRUM_ORIGIN)["fixed"]), [], "beyond its throw")
	assert_eq(Array(plan.section_floods("frame", aside, DRUM_ORIGIN)["fixed"]), [], "outside its cone")


func test_a_flood_on_the_other_piece_counts_where_the_drum_can_carry_it() -> void:
	var plan := StationLightPlan.from_hardpoints(_hardpoints())
	# The drum flood sits at frame z -2700 (drum z -1700 plus the pivot), radius 200, throw 150: it sweeps radii 50 to 350.
	var band := AABB(Vector3(-300.0, -300.0, -2750.0), Vector3(600.0, 600.0, 100.0))
	var other_depth := AABB(Vector3(-300.0, -300.0, -2000.0), Vector3(600.0, 600.0, 100.0))
	var out_beyond := AABB(Vector3(400.0, -50.0, -2750.0), Vector3(100.0, 100.0, 100.0))
	assert_eq(Array(plan.section_floods("frame", band, DRUM_ORIGIN)["turning"]), [1], "the band it sweeps at its depth")
	assert_eq(Array(plan.section_floods("frame", other_depth, DRUM_ORIGIN)["turning"]), [], "another depth")
	assert_eq(Array(plan.section_floods("frame", out_beyond, DRUM_ORIGIN)["turning"]), [], "beyond the radii it sweeps")


func test_floods_from_the_other_piece_turn_with_the_drum() -> void:
	var plan := StationLightPlan.from_hardpoints(_hardpoints())
	var turned := Transform3D(Basis(Vector3.BACK, PI / 2.0), DRUM_ORIGIN)
	var into_frame: Array[PackedVector4Array] = plan.pack("frame", PackedInt32Array([0, 1]), turned)
	var fixed: Vector4 = into_frame[0][0]
	assert_almost_eq(Vector3(fixed.x, fixed.y, fixed.z), Vector3(0.0, 0.0, -3600.0), Vector3.ONE * 1e-4, "a frame flood stays put")
	var carried: Vector4 = into_frame[0][1]
	assert_almost_eq(Vector3(carried.x, carried.y, carried.z), Vector3(0.0, 200.0, -2700.0), Vector3.ONE * 1e-3,
			"the drum flood turned a quarter about the axis and placed at the pivot")
	var dir: Vector4 = into_frame[1][1]
	assert_almost_eq(Vector3(dir.x, dir.y, dir.z), Vector3(0.0, 1.0, 0.0), Vector3.ONE * 1e-4, "and its beam turned with it")
	assert_almost_eq(carried.w, 150.0, 1e-6, "the throw rides in w")
	var into_drum: Array[PackedVector4Array] = plan.pack("drum", PackedInt32Array([0]), turned)
	var back: Vector4 = into_drum[0][0]
	assert_almost_eq(Vector3(back.x, back.y, back.z), Vector3(0.0, 0.0, -2600.0), Vector3.ONE * 1e-3,
			"a frame flood seen from the turned drum (on the axis, so only the pivot moves it)")
	assert_almost_eq(into_drum[2][0].w, cos(deg_to_rad(5.0)), 1e-6, "the inner cosine rides in the colour's w")
