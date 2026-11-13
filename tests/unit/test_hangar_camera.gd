extends GutTest
## The front end's camera in the Cobra-bay hangar (M7-T09, D77): a slow dolly along the racks that keeps them in view, stays in
## the hall and clear of the fighters, and the look sheets' fixed views.

const RACK_Z: Array[float] = [-115.71, -77.14, -38.57, 0.0, 38.57, 77.14, 115.71]
const SLOT_X: Array[float] = [-20.0, 0.0, 20.0]
const FIGHTER_HALF_SPAN_M: float = 7.7


func _camera() -> HangarCamera:
	var manifest: Dictionary = {
		"camera": {"rail": {"x": 31.0, "y": 7.5, "z_from": -112.0, "z_to": 96.0}},
		"hall": {"half_width_m": 42.0, "height_m": 30.0, "end_z_m": 135.0},
		"racks": [],
	}
	for z: float in RACK_Z:
		for x: float in SLOT_X:
			(manifest["racks"] as Array).append({"position": [x, 9.0, z]})
	return HangarCamera.from_manifest(manifest)


func test_it_reads_the_rail_and_the_racks_from_the_manifest() -> void:
	var camera: HangarCamera = _camera()
	assert_eq(camera.rail_x, 31.0)
	assert_eq(camera.z_to, 96.0)
	assert_eq(camera.rack_z.size(), 21)
	assert_eq(camera.end_z, 135.0)


func test_the_move_is_slow_and_smooth() -> void:
	var camera: HangarCamera = _camera()
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


func test_it_stays_in_the_hall_beside_the_racks_and_keeps_them_in_view() -> void:
	var camera: HangarCamera = _camera()
	for step: int in range(0, 241):
		var pose: Transform3D = camera.pose(float(step))
		var at: Vector3 = pose.origin
		assert_between(at.z, -112.0 - 0.01, 96.0 + 0.01)
		assert_lt(absf(at.x), 42.0)
		assert_between(at.y, 1.0, 29.0)
		for x: float in SLOT_X:
			assert_gt(absf(at.x - x), FIGHTER_HALF_SPAN_M + 2.0, "clear of the held fighters")
		assert_lt(at.x, 33.5, "short of the crane columns")
		var forward: Vector3 = -pose.basis.z
		var seen: int = 0
		for z: float in RACK_Z:
			for x: float in SLOT_X:
				if rad_to_deg(forward.angle_to(Vector3(x, 9.0, z) - at)) < 32.0:
					seen += 1
		assert_gt(seen, 0, "a rack in view at %d s" % step)


func test_the_move_starts_at_the_head_end_and_turns_at_the_root_end() -> void:
	var camera: HangarCamera = _camera()
	assert_almost_eq(camera.pose(0.0).origin.z, -112.0, 0.01)
	assert_almost_eq(camera.pose(HangarCamera.PERIOD_S * 0.5).origin.z, 96.0, 0.01)
	assert_almost_eq(camera.pose(HangarCamera.PERIOD_S).origin.z, -112.0, 0.01)


func test_the_fixed_views_look_at_the_racks_from_inside_the_hall() -> void:
	var camera: HangarCamera = _camera()
	for view: HangarCamera.View in [HangarCamera.View.WIDE, HangarCamera.View.CLOSE, HangarCamera.View.RACK]:
		var pose: Transform3D = camera.pose(0.0, view)
		assert_lt(absf(pose.origin.x), 42.0)
		assert_lt(absf(pose.origin.z), 135.0)
		assert_between(pose.origin.y, 1.0, 29.0)
	var close: Transform3D = camera.pose(0.0, HangarCamera.View.CLOSE)
	assert_lt(close.origin.distance_to(Vector3(0.0, 9.0, 0.0)), 25.0, "close on the middle rack")
	var rack: Transform3D = camera.pose(0.0, HangarCamera.View.RACK)
	for x: float in SLOT_X:
		assert_lt(rad_to_deg((-rack.basis.z).angle_to(Vector3(x, 9.0, 0.0) - rack.origin)), 50.0, "the whole rack in view (54 degrees each side at 16:9)")
	assert_eq(camera.pose(12.0, HangarCamera.View.WIDE), camera.pose(40.0, HangarCamera.View.WIDE), "the fixed views hold still")
