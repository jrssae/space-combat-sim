extends GutTest
## The cargo pod's arm pose (M7-T33): rest leaves every joint as it is, the reach slides forward and stops at its travel, the wrist
## pitches the hand within its limit, the jaws close toward each other, and a grip point follows its hand; both arms alike.

const RIG: Dictionary = {
	"bones": [
		{"name": "root", "parent": -1, "position": [0.0, 0.0, 0.0]},
		{"name": "reach_r", "parent": 0, "position": [1.32, -0.4, -0.06]},
		{"name": "wrist_r", "parent": 1, "position": [1.32, -0.38, -1.31]},
		{"name": "jaw_up_r", "parent": 2, "position": [1.32, -0.17, -2.4]},
		{"name": "jaw_lo_r", "parent": 2, "position": [1.32, -0.63, -2.4]},
		{"name": "reach_l", "parent": 0, "position": [-1.32, -0.4, -0.06]},
		{"name": "wrist_l", "parent": 5, "position": [-1.32, -0.38, -1.31]},
		{"name": "jaw_up_l", "parent": 6, "position": [-1.32, -0.17, -2.4]},
		{"name": "jaw_lo_l", "parent": 6, "position": [-1.32, -0.63, -2.4]},
	],
	"extend_m": 1.0, "wrist_limit_deg": 45.0, "jaw_close_deg": 15.5,
}
const GRIP_R := Vector3(1.32, -0.4, -2.7)
const JAW_TIP_UP_R := Vector3(1.32, -0.24, -3.0)


func _pose() -> CargoPodPose:
	return CargoPodPose.from_rig(RIG)


func test_rest_changes_nothing() -> void:
	var pose: CargoPodPose = _pose()
	var deltas: Dictionary = pose.bone_deltas(0.0, 0.0, 1.0)
	assert_eq(deltas.size(), 8, "four moving joints an arm")
	for bone: String in deltas:
		assert_true((deltas[bone] as Transform3D).is_equal_approx(Transform3D.IDENTITY), bone)
	assert_almost_eq(pose.point_on("wrist_r", GRIP_R, deltas), GRIP_R, Vector3.ONE * 1e-5)


func test_the_reach_slides_forward_and_stops_at_its_travel() -> void:
	var pose: CargoPodPose = _pose()
	assert_almost_eq(pose.point_on("wrist_r", GRIP_R, pose.bone_deltas(0.5, 0.0, 1.0)), GRIP_R + Vector3(0, 0, -0.5), Vector3.ONE * 1e-5)
	assert_almost_eq(pose.point_on("wrist_r", GRIP_R, pose.bone_deltas(3.0, 0.0, 1.0)), GRIP_R + Vector3(0, 0, -1.0), Vector3.ONE * 1e-5)
	assert_almost_eq(pose.point_on("wrist_r", GRIP_R, pose.bone_deltas(-1.0, 0.0, 1.0)), GRIP_R, Vector3.ONE * 1e-5)


func test_the_wrist_pitches_the_hand_up_within_its_limit() -> void:
	var pose: CargoPodPose = _pose()
	var up: Vector3 = pose.point_on("wrist_r", GRIP_R, pose.bone_deltas(0.0, 30.0, 1.0))
	assert_gt(up.y, GRIP_R.y + 0.5, "a positive angle lifts the hand")
	var pivot: Vector3 = pose.rest_positions["wrist_r"]
	assert_almost_eq(up.distance_to(pivot), GRIP_R.distance_to(pivot), 1e-5, "the hand swings round the pivot")
	var limited: Vector3 = pose.point_on("wrist_r", GRIP_R, pose.bone_deltas(0.0, 90.0, 1.0))
	var at_limit: Vector3 = pose.point_on("wrist_r", GRIP_R, pose.bone_deltas(0.0, 45.0, 1.0))
	assert_almost_eq(limited, at_limit, Vector3.ONE * 1e-5)


func test_the_jaws_close_toward_each_other() -> void:
	var pose: CargoPodPose = _pose()
	var tip_low := Vector3(JAW_TIP_UP_R.x, -0.56, JAW_TIP_UP_R.z)
	var open_gap: float = JAW_TIP_UP_R.y - tip_low.y
	var shut: Dictionary = pose.bone_deltas(0.0, 0.0, 0.0)
	var gap: float = pose.point_on("jaw_up_r", JAW_TIP_UP_R, shut).y - pose.point_on("jaw_lo_r", tip_low, shut).y
	assert_lt(gap, open_gap - 0.25, "the tips meet")
	var half: Dictionary = pose.bone_deltas(0.0, 0.0, 0.5)
	var half_gap: float = pose.point_on("jaw_up_r", JAW_TIP_UP_R, half).y - pose.point_on("jaw_lo_r", tip_low, half).y
	assert_between(half_gap, gap, open_gap)


func test_both_arms_move_alike_mirrored() -> void:
	var pose: CargoPodPose = _pose()
	var deltas: Dictionary = pose.bone_deltas(0.7, -20.0, 0.3)
	var right: Vector3 = pose.point_on("jaw_up_r", JAW_TIP_UP_R, deltas)
	var left: Vector3 = pose.point_on("jaw_up_l", JAW_TIP_UP_R * Vector3(-1, 1, 1), deltas)
	assert_almost_eq(left, right * Vector3(-1, 1, 1), Vector3.ONE * 1e-5)


func test_an_empty_rig_poses_nothing() -> void:
	var pose: CargoPodPose = CargoPodPose.from_rig({})
	assert_eq(pose.bone_deltas(1.0, 10.0, 0.0).size(), 0)
