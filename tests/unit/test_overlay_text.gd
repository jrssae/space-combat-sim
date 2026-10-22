extends GutTest


func test_empty_snapshot_is_empty() -> void:
	assert_eq(OverlayText.format({}), "")


func test_flight_lines() -> void:
	var text: String = OverlayText.format({
		"speed_mps": 42.123, "body_velocity": Vector3(1, -2, -42), "angular_rate_dps": Vector3(0, 30, 0),
		"assist_on": true, "pod_yaw_dps": -30.0, "pod_trim": 0.59,
	})
	assert_string_contains(text, "SPD       42.1 m/s")
	assert_string_contains(text, "-42.0")
	assert_string_contains(text, "+30.0")
	assert_string_contains(text, "ASSIST ON")
	assert_string_contains(text, "POD YAW -30.0 °/s")
	assert_string_contains(text, "POD TRIM  59 %")


func test_pod_yaw_only_with_assist_on() -> void:
	var text: String = OverlayText.format({"assist_on": false, "pod_yaw_dps": 12.0, "pod_trim": 0.0})
	assert_string_contains(text, "ASSIST OFF")
	assert_false(text.contains("POD YAW"))


func test_modes_and_timescale_only_when_not_one() -> void:
	var text: String = OverlayText.format({"camera_mode": "chase", "weapon_mode": "linked", "timescale": 1.0})
	assert_string_contains(text, "CAM CHASE   GUNS LINKED")
	assert_false(text.contains("TIMESCALE"))
	assert_string_contains(OverlayText.format({"timescale": 0.25}), "TIMESCALE 0.25")


func test_target_line_format() -> void:
	assert_eq(OverlayText.target_line("NAV BRAVO", 1243.4, 12.4, false), "TGT   NAV BRAVO  1243 m  +12.4 m/s")
	assert_eq(OverlayText.target_line("", 0.0, 0.0, false), "TGT   none")
	assert_string_contains(OverlayText.target_line("NAV ALPHA", 500.0, -3.0, true), "BEHIND")


func test_render_and_pads() -> void:
	var text: String = OverlayText.format({
		"universe_position": PackedFloat64Array([1.0e11, 0.5, -2.0]), "system_id": "local",
		"splat_backend": "compute", "fps": 60, "gpu": "Test GPU",
		"pads": [{"name": "Generic Pad", "guid": "abc", "trigger_rest": -1.0, "axes": [0.0, 0.5, 0.0, 0.0, -1.0, -1.0]}],
	})
	assert_string_contains(text, "100000000000.000")
	assert_string_contains(text, "SPLATS COMPUTE   FPS 60")
	assert_string_contains(text, "GPU   Test GPU")
	assert_string_contains(text, "PAD   Generic Pad  abc  rest -1  axes +0.00 +0.50")
