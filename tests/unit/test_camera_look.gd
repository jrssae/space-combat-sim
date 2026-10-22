extends GutTest
## CameraLook: the stick sets an absolute look direction, the mouse turns the view by its travel, release returns to centre.

const DT: float = 1.0 / 60.0

var look: CameraLook


func before_each() -> void:
	look = CameraLook.new()


func _run(seconds: float, active: bool, stick: Vector2, mouse_px: Vector2 = Vector2.ZERO) -> void:
	for i: int in int(seconds / DT):
		look.step(DT, active, stick, mouse_px, 0.1)


func test_a_full_stick_reaches_the_limits_and_no_further() -> void:
	_run(2.0, true, Vector2(1.0, 0.0))
	assert_almost_eq(look.yaw_deg, look.max_yaw_deg, 1e-6)
	assert_eq(look.pitch_deg, 0.0)
	_run(2.0, true, Vector2(0.0, 1.0))
	assert_almost_eq(look.pitch_deg, look.max_pitch_deg, 1e-6)


func test_a_half_stick_looks_half_way() -> void:
	_run(2.0, true, Vector2(-0.5, 0.0))
	assert_almost_eq(look.yaw_deg, -0.5 * look.max_yaw_deg, 1e-6)


func test_releasing_returns_to_centre() -> void:
	_run(1.0, true, Vector2(1.0, 0.5))
	assert_false(look.is_centred())
	_run(2.0, false, Vector2.ZERO)
	assert_true(look.is_centred(), "the view is back on the nose")
	assert_eq(look.look_basis(), Basis.IDENTITY)


func test_a_stick_back_at_centre_returns_the_view_while_still_held() -> void:
	_run(1.0, true, Vector2(1.0, 0.0))
	_run(2.0, true, Vector2.ZERO)
	assert_true(look.is_centred())


func test_the_mouse_turns_by_its_travel_and_holds_where_it_stops() -> void:
	look.step(DT, true, Vector2.ZERO, Vector2(100.0, 50.0), 0.1)
	assert_almost_eq(look.yaw_deg, 10.0, 1e-9)
	assert_almost_eq(look.pitch_deg, 5.0, 1e-9)
	_run(1.0, true, Vector2.ZERO)
	assert_almost_eq(look.yaw_deg, 10.0, 1e-9, "still looking there")


func test_the_mouse_is_clamped() -> void:
	look.step(DT, true, Vector2.ZERO, Vector2(1.0e6, -1.0e6), 0.1)
	assert_eq(look.yaw_deg, look.max_yaw_deg)
	assert_eq(look.pitch_deg, -look.max_pitch_deg)


func test_chase_orbits_further_than_the_cockpit_turns() -> void:
	look.set_mode(true)
	var cockpit_limit: float = look.max_yaw_deg
	look.set_mode(false)
	assert_gt(look.max_yaw_deg, cockpit_limit)


func test_look_right_points_the_camera_right() -> void:
	look.yaw_deg = 90.0
	var forward: Vector3 = look.look_basis() * Vector3.FORWARD
	assert_almost_eq(forward.x, 1.0, 1e-6, "yaw right turns toward +X")
	look.reset()
	look.pitch_deg = 90.0
	forward = look.look_basis() * Vector3.FORWARD
	assert_almost_eq(forward.y, 1.0, 1e-6, "pitch up turns toward +Y")
