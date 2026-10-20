extends GutTest
## ThrusterLayout: the pod nozzles as the flight model sees them, built from hardpoints JSON (architecture §5.2).
## Uses the static fixture, never the generated assets.

const FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const EPS: float = 1e-6

var layout: ThrusterLayout


func before_each() -> void:
	layout = ThrusterLayout.load_file(FIXTURE)


func test_fixture_loads() -> void:
	assert_true(layout.valid, layout.error)
	assert_eq(layout.error, "")
	assert_almost_eq(layout.center_of_mass, Vector3(0.0, 0.0, 0.06728), Vector3.ONE * EPS)


func test_four_pods_two_per_side_in_file_order() -> void:
	assert_eq(layout.pod_count(), 4)
	assert_eq(layout.pod_names, PackedStringArray(["ur", "lr", "ul", "ll"]))
	assert_eq(layout.pod_is_right, PackedByteArray([1, 1, 0, 0]))


func test_eight_nozzles_mains_first_then_retros() -> void:
	assert_eq(layout.nozzle_count(), 8)
	assert_eq(layout.nozzle_names, PackedStringArray([
		"ur_main", "lr_main", "ul_main", "ll_main", "ur_retro", "lr_retro", "ul_retro", "ll_retro",
	]))
	assert_eq(layout.nozzle_pods, PackedInt32Array([0, 1, 2, 3, 0, 1, 2, 3]))
	assert_eq(layout.nozzle_groups, PackedInt32Array([
		ThrusterLayout.Group.R_MAIN, ThrusterLayout.Group.R_MAIN,
		ThrusterLayout.Group.L_MAIN, ThrusterLayout.Group.L_MAIN,
		ThrusterLayout.Group.R_RETRO, ThrusterLayout.Group.R_RETRO,
		ThrusterLayout.Group.L_RETRO, ThrusterLayout.Group.L_RETRO,
	]))


func test_nozzle_positions_and_exhausts_match_the_hardpoints() -> void:
	# ur main at (+3.182, +3.182, 3.174) exhausting +Z; ll retro at (-3.182, -3.182, -0.696) exhausting -Z.
	assert_almost_eq(layout.nozzle_positions[0], Vector3(3.18198, 3.18198, 3.17428), Vector3.ONE * EPS)
	assert_eq(layout.nozzle_exhausts[0], Vector3(0.0, 0.0, 1.0))
	assert_almost_eq(layout.nozzle_positions[7], Vector3(-3.18198, -3.18198, -0.69572), Vector3.ONE * EPS)
	assert_eq(layout.nozzle_exhausts[7], Vector3(0.0, 0.0, -1.0))
	for i: int in layout.nozzle_count():
		assert_almost_eq(layout.nozzle_exhausts[i].length(), 1.0, EPS, "exhaust %d is a unit vector" % i)
		var expected_z: float = 1.0 if ThrusterLayout.is_main_group(layout.nozzle_groups[i]) else -1.0
		assert_eq(layout.nozzle_exhausts[i].z, expected_z, "main exhausts +Z, retro -Z (%s)" % layout.nozzle_names[i])
		var expected_sign: float = 1.0 if ThrusterLayout.is_right_group(layout.nozzle_groups[i]) else -1.0
		assert_eq(signf(layout.nozzle_positions[i].x), expected_sign, "right pods have x > 0 (%s)" % layout.nozzle_names[i])


func test_arms_are_positions_minus_centre_of_mass() -> void:
	for i: int in layout.nozzle_count():
		var expected: Vector3 = layout.nozzle_positions[i] - layout.center_of_mass
		assert_eq(layout.nozzle_arms[i], expected, layout.nozzle_names[i])
	assert_almost_eq(layout.nozzle_arms[0].z, 3.17428 - 0.06728, EPS)


func test_from_dict_takes_the_centre_of_mass_it_is_given() -> void:
	var text: String = FileAccess.get_file_as_string(FIXTURE)
	var data: Dictionary = JSON.parse_string(text)
	var com := Vector3(0.1, -0.2, 1.0)
	var shifted: ThrusterLayout = ThrusterLayout.from_dict(data, com)
	assert_true(shifted.valid, shifted.error)
	assert_eq(shifted.center_of_mass, com)
	for i: int in shifted.nozzle_count():
		assert_eq(shifted.nozzle_arms[i], layout.nozzle_positions[i] - com)
	# An off-axis CoM makes the mains pitch and the torque axes say so.
	assert_almost_ne(shifted.torque_axis(ThrusterLayout.Group.R_MAIN).x, 0.0, 1e-3)


func test_group_thrust_axes_sum_unit_thrust_directions() -> void:
	# Two nozzles per group; mains push -Z (forward), retros +Z.
	assert_almost_eq(layout.thrust_axis(ThrusterLayout.Group.R_MAIN), Vector3(0.0, 0.0, -2.0), Vector3.ONE * EPS)
	assert_almost_eq(layout.thrust_axis(ThrusterLayout.Group.L_MAIN), Vector3(0.0, 0.0, -2.0), Vector3.ONE * EPS)
	assert_almost_eq(layout.thrust_axis(ThrusterLayout.Group.R_RETRO), Vector3(0.0, 0.0, 2.0), Vector3.ONE * EPS)
	assert_almost_eq(layout.thrust_axis(ThrusterLayout.Group.L_RETRO), Vector3(0.0, 0.0, 2.0), Vector3.ONE * EPS)


func test_group_torque_axes_are_pure_yaw_with_the_documented_signs() -> void:
	# tau_g = Σ r_i × (-exhaust_i): right mains => +y (nose left), left mains => -y, retros the reverse (§5.2).
	var lever: float = 0.0
	for i: int in layout.nozzles_in_group(ThrusterLayout.Group.R_MAIN):
		lever += layout.nozzle_arms[i].x
	assert_almost_eq(lever, 2.0 * 3.18198, EPS, "yaw lever arm of the right mains")
	assert_almost_eq(layout.torque_axis(ThrusterLayout.Group.R_MAIN), Vector3(0.0, lever, 0.0), Vector3.ONE * EPS)
	assert_almost_eq(layout.torque_axis(ThrusterLayout.Group.L_MAIN), Vector3(0.0, -lever, 0.0), Vector3.ONE * EPS)
	assert_almost_eq(layout.torque_axis(ThrusterLayout.Group.R_RETRO), Vector3(0.0, -lever, 0.0), Vector3.ONE * EPS)
	assert_almost_eq(layout.torque_axis(ThrusterLayout.Group.L_RETRO), Vector3(0.0, lever, 0.0), Vector3.ONE * EPS)
	for group: int in ThrusterLayout.GROUP_COUNT:
		assert_eq(layout.torque_axis(group).x, 0.0, "no pitch from %s" % ThrusterLayout.group_name(group))
		assert_eq(layout.torque_axis(group).z, 0.0, "no roll from %s" % ThrusterLayout.group_name(group))


func test_torque_axes_equal_the_nozzle_cross_products() -> void:
	for group: int in ThrusterLayout.GROUP_COUNT:
		var total := Vector3.ZERO
		var members: PackedInt32Array = layout.nozzles_in_group(group)
		assert_eq(members.size(), 2, ThrusterLayout.group_name(group))
		for i: int in members:
			total += layout.nozzle_arms[i].cross(-layout.nozzle_exhausts[i])
		assert_almost_eq(layout.torque_axis(group), total, Vector3.ONE * EPS)


func test_group_helpers() -> void:
	assert_true(ThrusterLayout.is_main_group(ThrusterLayout.Group.R_MAIN))
	assert_true(ThrusterLayout.is_main_group(ThrusterLayout.Group.L_MAIN))
	assert_false(ThrusterLayout.is_main_group(ThrusterLayout.Group.R_RETRO))
	assert_false(ThrusterLayout.is_main_group(ThrusterLayout.Group.L_RETRO))
	assert_true(ThrusterLayout.is_right_group(ThrusterLayout.Group.R_MAIN))
	assert_true(ThrusterLayout.is_right_group(ThrusterLayout.Group.R_RETRO))
	assert_false(ThrusterLayout.is_right_group(ThrusterLayout.Group.L_MAIN))
	assert_false(ThrusterLayout.is_right_group(ThrusterLayout.Group.L_RETRO))
	assert_eq(ThrusterLayout.group_name(ThrusterLayout.Group.L_RETRO), "L_RETRO")


func test_cosmetic_rcs_nozzles_are_read_with_tags() -> void:
	assert_eq(layout.rcs_nozzles.size(), 16)
	var first: Dictionary = layout.rcs_nozzles[0]
	assert_eq(first["name"], "ur_px")
	assert_eq(first["pod"], "ur")
	assert_almost_eq(first["position"] as Vector3, Vector3(3.80198, 3.18198, 0.86828), Vector3.ONE * EPS)
	assert_eq(first["exhaust"], Vector3(1.0, 0.0, 0.0))
	assert_eq(first["tags"], PackedStringArray(["sway_left", "yaw_right", "roll_left"]))


func test_exhaust_directions_are_normalised() -> void:
	var text: String = FileAccess.get_file_as_string(FIXTURE)
	var data: Dictionary = JSON.parse_string(text)
	var pods: Array = data["pods"]
	var pod: Dictionary = pods[0]
	var main: Dictionary = pod["main"]
	main["exhaust"] = [0, 0, 4]
	var built: ThrusterLayout = ThrusterLayout.from_dict(data, Vector3.ZERO)
	assert_true(built.valid, built.error)
	assert_eq(built.nozzle_exhausts[0], Vector3(0.0, 0.0, 1.0))


func test_malformed_pods_are_rejected_without_nozzles() -> void:
	var cases: Dictionary = {
		"no pods": {},
		"empty pods": {"pods": []},
		"non-object pod": {"pods": [1]},
		"unnamed pod": {"pods": [{"side": "right", "main": _nozzle(1.0), "retro": _nozzle(-1.0)}]},
		"bad side": {"pods": [{"name": "a", "side": "up", "main": _nozzle(1.0), "retro": _nozzle(-1.0)}]},
		"missing retro": {"pods": [{"name": "a", "side": "right", "main": _nozzle(1.0)}]},
		"short position": {"pods": [{"name": "a", "side": "right", "main": {"position": [1, 2], "exhaust": [0, 0, 1]}, "retro": _nozzle(-1.0)}]},
		"non-numeric exhaust": {"pods": [{"name": "a", "side": "right", "main": {"position": [1, 2, 3], "exhaust": [0, "0", 1]}, "retro": _nozzle(-1.0)}]},
		"zero exhaust": {"pods": [{"name": "a", "side": "right", "main": {"position": [1, 2, 3], "exhaust": [0, 0, 0]}, "retro": _nozzle(-1.0)}]},
		"one-sided": {"pods": [
			{"name": "a", "side": "right", "main": _nozzle(1.0), "retro": _nozzle(-1.0)},
			{"name": "b", "side": "right", "main": _nozzle(1.0), "retro": _nozzle(-1.0)},
		]},
	}
	for label: String in cases:
		var built: ThrusterLayout = ThrusterLayout.from_dict(cases[label], Vector3.ZERO)
		assert_false(built.valid, "should reject: %s" % label)
		assert_ne(built.error, "", "should explain: %s" % label)
		assert_eq(built.nozzle_count(), 0, "no nozzles for: %s" % label)


func test_broken_json_and_missing_centre_of_mass_are_rejected() -> void:
	for text: String in ["", "{", "[1, 2, 3]", '{"pods": []}', '{"center_of_mass": [0, 0], "pods": []}']:
		var built: ThrusterLayout = ThrusterLayout.from_json_text(text)
		assert_false(built.valid, "should reject '%s'" % text)
		assert_ne(built.error, "", "should explain '%s'" % text)


func test_missing_file_is_reported() -> void:
	var built: ThrusterLayout = ThrusterLayout.load_file("res://tests/fixtures/does_not_exist.json")
	assert_false(built.valid)
	assert_string_contains(built.error, "does_not_exist.json")
	assert_eq(built.nozzle_count(), 0)


func test_minimal_two_pod_layout_is_accepted() -> void:
	var data: Dictionary = {"pods": [
		{"name": "r", "side": "right", "main": _nozzle(1.0, 2.0), "retro": _nozzle(-1.0, 2.0)},
		{"name": "l", "side": "left", "main": _nozzle(1.0, -2.0), "retro": _nozzle(-1.0, -2.0)},
	]}
	var built: ThrusterLayout = ThrusterLayout.from_dict(data, Vector3.ZERO)
	assert_true(built.valid, built.error)
	assert_eq(built.nozzle_count(), 4)
	assert_eq(built.rcs_nozzles.size(), 0)
	assert_almost_eq(built.torque_axis(ThrusterLayout.Group.R_MAIN), Vector3(0.0, 2.0, 0.0), Vector3.ONE * EPS)
	assert_almost_eq(built.torque_axis(ThrusterLayout.Group.L_RETRO), Vector3(0.0, 2.0, 0.0), Vector3.ONE * EPS)


func _nozzle(exhaust_z: float, x: float = 1.0) -> Dictionary:
	return {"position": [x, 0.0, 1.0], "exhaust": [0.0, 0.0, exhaust_z]}
