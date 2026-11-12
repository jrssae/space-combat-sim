extends GutTest
## The pause backdrop's path (M5-T42): it closes, is smooth over the seam, keeps clear of the hull and faces the ship.

const HULLS: Array[float] = [8.0, 60.0]  # a Starfury and a Saturn 8, roughly


func _path(hull: float) -> PauseOrbitPath:
	return PauseOrbitPath.create(9.3, hull)


func test_the_loop_closes() -> void:
	var path: PauseOrbitPath = _path(8.0)
	assert_lt(path.position_at(0.0).distance_to(path.position_at(1.0)), 0.001)
	assert_lt(path.look_at_at(0.0).distance_to(path.look_at_at(1.0)), 0.001)


func test_position_and_aim_are_smooth_over_the_seam() -> void:
	var path: PauseOrbitPath = _path(8.0)
	var step: float = 0.001
	var before: Vector3 = path.position_at(1.0 - step) - path.position_at(1.0 - 2.0 * step)
	var after: Vector3 = path.position_at(step) - path.position_at(0.0)
	assert_lt(before.angle_to(after), 0.02, "the direction of travel does not kink at the seam")
	var aim_jump: float = path.look_at_at(1.0 - step).distance_to(path.look_at_at(step))
	assert_lt(aim_jump, path.radius_m * 0.02)


func test_the_camera_never_comes_inside_the_hull() -> void:
	for hull: float in HULLS:
		var path: PauseOrbitPath = _path(hull)
		for i: int in 400:
			var d: float = path.position_at(float(i) / 400.0).length()
			assert_gt(d, hull * 1.9, "hull %s phase %d" % [hull, i])


func test_it_is_a_figure_eight_that_passes_nose_and_tail() -> void:
	var path: PauseOrbitPath = _path(8.0)
	assert_gt(path.position_at(0.0).z, 0.0, "behind the ship at phase 0")
	assert_lt(path.position_at(0.5).z, 0.0, "past the nose at phase 0.5")
	assert_gt(path.position_at(0.125).y, 0.0, "over the hull")
	assert_lt(path.position_at(0.375).y, 0.0, "and under it")


func test_the_camera_faces_the_ship() -> void:
	var path: PauseOrbitPath = _path(8.0)
	for i: int in 40:
		var t: Transform3D = path.transform_at(float(i) / 40.0)
		var to_ship: Vector3 = (Vector3.ZERO - t.origin).normalized()
		assert_lt((-t.basis.z).angle_to(to_ship), deg_to_rad(30.0), "the ship stays in view, phase %d" % i)


func test_the_phase_nearest_a_point() -> void:
	var path: PauseOrbitPath = _path(8.0)
	assert_almost_eq(path.nearest_phase(path.position_at(0.3)), 0.3, 0.005)
	assert_almost_eq(path.nearest_phase(Vector3(0.0, 2.5, 9.0)), 0.0, 0.03)
