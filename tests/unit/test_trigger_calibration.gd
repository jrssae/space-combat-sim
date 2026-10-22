extends GutTest

const GUID := "03000000aaaa0000bbbb000000000000"


func test_normalize_rest_zero() -> void:
	assert_almost_eq(TriggerCalibration.normalize(0.0, 0.0), 0.0, 1e-9)
	assert_almost_eq(TriggerCalibration.normalize(0.5, 0.0), 0.5, 1e-9)
	assert_almost_eq(TriggerCalibration.normalize(1.0, 0.0), 1.0, 1e-9)
	assert_almost_eq(TriggerCalibration.normalize(-0.2, 0.0), 0.0, 1e-9, "never negative thrust")


func test_normalize_rest_minus_one() -> void:
	assert_almost_eq(TriggerCalibration.normalize(-1.0, -1.0), 0.0, 1e-9)
	assert_almost_eq(TriggerCalibration.normalize(0.0, -1.0), 0.5, 1e-9)
	assert_almost_eq(TriggerCalibration.normalize(1.0, -1.0), 1.0, 1e-9)


func test_deadzone_rescales() -> void:
	assert_eq(TriggerCalibration.apply_deadzone(0.04, 0.05), 0.0)
	assert_almost_eq(TriggerCalibration.apply_deadzone(1.0, 0.05), 1.0, 1e-9)
	assert_almost_eq(TriggerCalibration.apply_deadzone(0.525, 0.05), 0.5, 1e-9)


func test_unknown_pad_defaults_to_rest_zero() -> void:
	var cal := TriggerCalibration.new()
	assert_eq(cal.get_rest(GUID), 0.0)
	assert_eq(cal.read(GUID, 0.0, 0.05), 0.0, "a 0..1 pad at idle reads zero")
	assert_eq(cal.read(GUID, -1.0, 0.05), 0.0, "a -1..1 pad at idle also reads zero before calibration")


func test_idle_zero_pad_calibrates_to_zero() -> void:
	var cal := TriggerCalibration.new()
	for i: int in 31:
		cal.observe(GUID, 0.0, 0.0, 1.0 / 60.0)
	assert_true(cal.is_calibrated(GUID))
	assert_eq(cal.get_rest(GUID), 0.0)
	assert_almost_eq(cal.read(GUID, 1.0, 0.05), 1.0, 1e-9)


func test_idle_minus_one_pad_calibrates_to_minus_one() -> void:
	var cal := TriggerCalibration.new()
	var changed: bool = cal.observe(GUID, -1.0, -1.0, 1.0 / 60.0)
	assert_true(changed, "first idle sample proves the -1..1 range")
	assert_eq(cal.get_rest(GUID), -1.0)
	assert_eq(cal.read(GUID, -1.0, 0.05), 0.0)
	assert_almost_eq(cal.read(GUID, 1.0, 0.05), 1.0, 1e-9)
	assert_almost_eq(cal.read(GUID, 0.0, 0.0), 0.5, 1e-9)


func test_trigger_held_at_startup_on_minus_one_pad_self_corrects() -> void:
	var cal := TriggerCalibration.new()
	# Pilot half-squeezes during start-up: a -1..1 pad reads 0, indistinguishable from a 0..1 pad at rest.
	for i: int in 40:
		cal.observe(GUID, 0.0, -1.0, 1.0 / 60.0)  # left squeezed, right at rest
	assert_eq(cal.get_rest(GUID), -1.0, "the idle right trigger proves the range")
	var cal2 := TriggerCalibration.new()
	for i: int in 40:
		cal2.observe(GUID, 0.0, 0.0, 1.0 / 60.0)  # both half-squeezed
	assert_eq(cal2.get_rest(GUID), 0.0)
	cal2.observe(GUID, -1.0, -1.0, 1.0 / 60.0)  # released
	assert_eq(cal2.get_rest(GUID), -1.0)


func test_minus_one_is_sticky_and_restart_resamples() -> void:
	var cal := TriggerCalibration.new()
	cal.set_rest(GUID, -1.0)
	for i: int in 40:
		cal.observe(GUID, 1.0, 1.0, 1.0 / 60.0)
	assert_eq(cal.get_rest(GUID), -1.0)
	assert_true(cal.is_calibrated(GUID))
	cal.restart(GUID)
	assert_false(cal.is_calibrated(GUID))
	assert_eq(cal.get_rest(GUID), -1.0)
