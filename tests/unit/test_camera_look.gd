extends GutTest
## CameraLook: the stick turns the view at a rate and a centred stick holds it, the mouse turns it by its travel, only
## releasing the look button returns it to centre (M3-T15).

const DT: float = 1.0 / 60.0

var look: CameraLook


func before_each() -> void:
	look = CameraLook.new()


func _run(seconds: float, active: bool, stick: Vector2, mouse_px: Vector2 = Vector2.ZERO) -> void:
	for i: int in int(seconds / DT):
		look.step(DT, active, stick, mouse_px, 0.1)


func test_a_full_stick_turns_at_the_look_rate_and_stops_at_the_limits() -> void:
	_run(0.5, true, Vector2(1.0, 0.0))
	assert_almost_eq(look.yaw_deg, 0.5 * CameraLook.STICK_LOOK_RATE_DEG_S, 0.5, "180 deg/s at full deflection")
	assert_eq(look.pitch_deg, 0.0)
	_run(2.0, true, Vector2(1.0, 0.0))
	assert_eq(look.yaw_deg, look.max_yaw_deg, "clamped at the limit")
	_run(2.0, true, Vector2(0.0, -1.0))
	assert_eq(look.pitch_deg, -look.max_pitch_deg)


func test_a_half_stick_turns_at_half_the_rate() -> void:
	_run(0.5, true, Vector2(-0.5, 0.0))
	assert_almost_eq(look.yaw_deg, -0.25 * CameraLook.STICK_LOOK_RATE_DEG_S, 0.5)


func test_a_centred_stick_holds_the_view_while_the_button_is_held() -> void:
	_run(0.25, true, Vector2(1.0, 0.5))
	var yaw: float = look.yaw_deg
	var pitch: float = look.pitch_deg
	assert_gt(yaw, 30.0)
	_run(3.0, true, Vector2.ZERO)
	assert_eq(look.yaw_deg, yaw, "still looking there after 3 s")
	assert_eq(look.pitch_deg, pitch)


func test_releasing_the_button_eases_back_to_centre() -> void:
	_run(0.5, true, Vector2(1.0, 0.5))
	assert_false(look.is_centred())
	_run(0.1, false, Vector2.ZERO)
	assert_false(look.is_centred(), "eases, does not snap")
	_run(2.0, false, Vector2.ZERO)
	assert_true(look.is_centred(), "the view is back on the nose")
	assert_eq(look.look_basis(), Basis.IDENTITY)


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
