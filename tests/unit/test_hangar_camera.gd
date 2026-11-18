extends GutTest
## The front end's camera in the Cobra-bay hangar (M7-T09, M7-T20; D77): a slow dolly beside the racks that keeps them in view,
## stays in the hall and clear of the fighters, and the look sheets' fixed views as the manifest gives them.

const DOOR_Z: Array[float] = [-57.5, -34.5, -11.5, 11.5, 34.5, 57.5]
const RACK := Vector3(0.0, 9.0, 0.0)
const STAGE := Vector3(28.0, 25.0, 0.0)
const FIGHTER_HALF_SPAN_M: float = 7.7
const UPPER_HALF_W: float = 20.0
const END_Z: float = 75.0


func _manifest() -> Dictionary:
	var fighters: Array = []
	for z: float in DOOR_Z:
		fighters.append({"wave": 1, "position": [RACK.x, RACK.y, z]})
		fighters.append({"wave": 2, "position": [STAGE.x, STAGE.y, z]})
	return {
		"camera": {
			"rail": {"x": -12.65, "y": 7.5, "z_from": -43.5, "z_to": 69.0, "look_x": -6.325, "look_dir": -1.0},
			"views": {"wide": {"at": [-30.0, 26.0, 71.0], "look": [14.0, 10.0, 0.0]},
					"close": {"at": [-10.65, 10.5, -0.5], "look": [0.0, 9.0, -11.5]}},
		},
		"fighters": fighters,
	}


func test_it_reads_the_rail_and_the_views_from_the_manifest() -> void:
	var camera: HangarCamera = HangarCamera.from_manifest(_manifest())
	assert_eq(camera.rail_x, -12.65)
	assert_eq(camera.look_dir, -1.0)
	assert_eq(camera.rack_y, 9.0)
	assert_true(camera.views.has("wide"))


func test_the_move_is_slow_and_smooth() -> void:
	var camera: HangarCamera = HangarCamera.from_manifest(_manifest())
	var fastest_m_s: float = 0.0
	var fastest_deg_s: float = 0.0
	var last: Transform3D = camera.pose(0.0)
	for step: int in range(1, 481):
		var now: Transform3D = camera.pose(step * 0.5)
		fastest_m_s = maxf(fastest_m_s, last.origin.distance_to(now.origin) / 0.5)
		fastest_deg_s = maxf(fastest_deg_s, rad_to_deg(last.basis.get_rotation_quaternion().angle_to(now.basis.get_rotation_quaternion())) / 0.5)
		last = now
	assert_lt(fastest_m_s, 3.5, "a gentle dolly")
	assert_lt(fastest_deg_s, 1.0, "it barely turns")
	assert_gt(fastest_m_s, 1.0, "but it does move")


func test_it_stays_beside_the_racks_and_keeps_them_in_view() -> void:
	var camera: HangarCamera = HangarCamera.from_manifest(_manifest())
	for step: int in range(0, 241):
		var pose: Transform3D = camera.pose(float(step))
		var at: Vector3 = pose.origin
		assert_between(at.z, -43.51, 69.01)
		assert_lt(absf(at.x), UPPER_HALF_W, "in the upper hall")
		assert_gt(absf(at.x - RACK.x), FIGHTER_HALF_SPAN_M + 2.0, "clear of the racked fighters")
		var forward: Vector3 = -pose.basis.z
		assert_lt(forward.z, 0.0, "looking toward the arm's head")
		var seen: int = 0
		for z: float in DOOR_Z:
			if rad_to_deg(forward.angle_to(Vector3(RACK.x, RACK.y, z) - at)) < 32.0:
				seen += 1
		assert_gt(seen, 0, "a rack in view at %d s" % step)


func test_the_move_starts_at_the_root_end_and_turns_at_the_head_end() -> void:
	var camera: HangarCamera = HangarCamera.from_manifest(_manifest())
	assert_almost_eq(camera.pose(0.0).origin.z, 69.0, 0.01)
	assert_almost_eq(camera.pose(HangarCamera.PERIOD_S * 0.5).origin.z, -43.5, 0.01)
	assert_almost_eq(camera.pose(HangarCamera.PERIOD_S).origin.z, 69.0, 0.01)


func test_the_fixed_views_are_the_manifests_and_hold_still() -> void:
	var camera: HangarCamera = HangarCamera.from_manifest(_manifest())
	var wide: Transform3D = camera.pose(0.0, HangarCamera.View.WIDE)
	assert_eq(wide.origin, Vector3(-30.0, 26.0, 71.0))
	assert_almost_eq(rad_to_deg((-wide.basis.z).angle_to(Vector3(14.0, 10.0, 0.0) - wide.origin)), 0.0, 0.01)
	assert_eq(camera.pose(12.0, HangarCamera.View.WIDE), camera.pose(40.0, HangarCamera.View.WIDE), "the fixed views hold still")
	assert_eq(camera.pose(5.0, HangarCamera.View.RACK), camera.pose(5.0), "a view the manifest lacks falls back to the move")
