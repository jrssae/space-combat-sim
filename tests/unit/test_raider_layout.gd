extends GutTest
## The raider's thruster layout from a static copy of its generated hardpoints (`hardpoints_raider_nominal.json`), so the
## layout rules hold without running the generator: two pods on opposite sides, each with a main and a retro, on the
## centre of mass's height, symmetric about x.

const FIXTURE: String = "res://tests/fixtures/hardpoints_raider_nominal.json"

var layout: ThrusterLayout
var hardpoints: Hardpoints


func before_each() -> void:
	layout = ThrusterLayout.load_file(FIXTURE)
	hardpoints = Hardpoints.load_file(FIXTURE)


func test_the_fixture_parses() -> void:
	assert_true(layout.valid, layout.error)
	assert_true(hardpoints.valid, hardpoints.error)
	assert_eq(layout.pod_names, PackedStringArray(["l", "r"]))
	assert_eq(layout.nozzle_count(), 4)
	assert_eq(hardpoints.muzzles.size(), 4)
	assert_gt(hardpoints.collision.size(), 10)


func test_nozzles_sit_at_the_centre_of_mass_height_and_are_symmetric() -> void:
	for i: int in layout.nozzle_count():
		assert_almost_eq(layout.nozzle_positions[i].y, layout.center_of_mass.y, 1e-6, layout.nozzle_names[i])
	var left: int = layout.nozzle_names.find("l_main")
	var right: int = layout.nozzle_names.find("r_main")
	assert_almost_eq(layout.nozzle_positions[left], layout.nozzle_positions[right] * Vector3(-1.0, 1.0, 1.0), Vector3.ONE * 1e-6)
	assert_eq(layout.nozzle_exhausts[left], Vector3(0.0, 0.0, 1.0))
	assert_eq(layout.nozzle_exhausts[layout.nozzle_names.find("l_retro")], Vector3(0.0, 0.0, -1.0))


func test_pod_groups_make_no_pitch_or_roll_torque_and_yaw_by_their_side() -> void:
	for group: int in ThrusterLayout.GROUP_COUNT:
		var axis: Vector3 = layout.torque_axis(group)
		assert_lt(absf(axis.x), 1e-6)
		assert_lt(absf(axis.z), 1e-6)
	assert_gt(layout.torque_axis(ThrusterLayout.Group.R_MAIN).y, 0.0, "right main: nose left")
	assert_lt(layout.torque_axis(ThrusterLayout.Group.L_MAIN).y, 0.0, "left main: nose right")
	assert_almost_eq(layout.torque_axis(ThrusterLayout.Group.R_MAIN).y, -layout.torque_axis(ThrusterLayout.Group.L_MAIN).y, 1e-9)


func test_chunk_entries_name_every_group() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in data["chunks"]:
		names.append(String(entry["name"]))
	assert_eq(names, PackedStringArray(["wing_l", "wing_r", "hump", "nacelle_l", "nacelle_r"]))
