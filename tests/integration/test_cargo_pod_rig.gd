extends GutTest
## The cargo pod's model with movable arms (M7-T33): the generated glb imports skinned, with the rig's nine joints, as one surface
## (the arms cost no draw call of their own), and posing it moves the bones and the grip points.


func test_the_rig_builds_skinned_in_one_surface() -> void:
	var rig := CargoPodRig.new()
	add_child_autofree(rig)
	assert_true(rig.build(), "run scripts/gen_assets.sh, then import")
	var skeleton: Skeleton3D = rig.skeleton()
	assert_not_null(skeleton)
	if skeleton == null:
		return
	assert_eq(skeleton.get_bone_count(), 9)
	for bone: String in ["root", "reach_r", "wrist_r", "jaw_up_r", "jaw_lo_r", "reach_l", "wrist_l", "jaw_up_l", "jaw_lo_l"]:
		assert_gt(skeleton.find_bone(bone), -1, bone)
	var mesh: Mesh = MeshAssets.for_asset(CargoPodRig.ASSET_ID)
	assert_eq(mesh.get_surface_count(), 1, "one draw call: hull and arms in one surface")


func test_posing_moves_the_bones_and_the_grips() -> void:
	var rig := CargoPodRig.new()
	add_child_autofree(rig)
	if not rig.build():
		fail_test("no cargo_pod_craft asset")
		return
	var rest_r: Vector3 = rig.grip_point("r")
	var rest_l: Vector3 = rig.grip_point("l")
	assert_almost_eq(rest_l, rest_r * Vector3(-1, 1, 1), Vector3.ONE * 1e-4)
	var skeleton: Skeleton3D = rig.skeleton()
	var reach: int = skeleton.find_bone("reach_r")
	var rest_position: Vector3 = skeleton.get_bone_pose_position(reach)
	rig.set_pose(1.0, 20.0, 0.0)
	assert_almost_eq(skeleton.get_bone_pose_position(reach), rest_position + Vector3(0, 0, -1.0), Vector3.ONE * 1e-4)
	var reached: Vector3 = rig.grip_point("r")
	assert_lt(reached.z, rest_r.z - 0.9, "the hand reaches forward")
	assert_gt(reached.y, rest_r.y, "and pitches up")
	assert_false(skeleton.get_bone_pose_rotation(skeleton.find_bone("jaw_up_r")).is_equal_approx(Quaternion.IDENTITY), "the jaws shut")
