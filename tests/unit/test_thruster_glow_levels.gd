extends GutTest
## ThrusterGlowLevels: the pure mapping from a FlightOutput to glow levels (architecture §7.1, M1-T13). Pod nozzles
## show their pod's post-trim main/retro level; RCS nozzles show the strongest of their pilot-term tags. The tag
## signs are checked against the real FlightModel, so a sign slip between the model and the glows fails here.

const FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const DT: float = 1.0 / 60.0
## Vector3 components are 32-bit floats, so levels that went through one differ from the literal by ~1e-8.
const FLOAT32_TOL: float = 1e-6

var layout: ThrusterLayout


func before_each() -> void:
	layout = ThrusterLayout.load_file(FIXTURE)
	assert_true(layout.valid, layout.error)


func _output(mains: Array[float], retros: Array[float]) -> FlightOutput:
	var output := FlightOutput.new()
	output.main_levels = PackedFloat64Array(mains)
	output.retro_levels = PackedFloat64Array(retros)
	return output


## Indices (in glow order) of the RCS nozzles carrying `tag`.
func _rcs_with_tag(tag: String) -> PackedInt32Array:
	var found := PackedInt32Array()
	for j: int in layout.rcs_nozzles.size():
		if (layout.rcs_nozzles[j]["tags"] as PackedStringArray).has(tag):
			found.append(layout.nozzle_count() + j)
	return found


# --- sizes and null -----------------------------------------------------------------------------------------


func test_one_target_per_pod_nozzle_and_per_rcs_nozzle() -> void:
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, _output([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]))
	assert_eq(layout.nozzle_count(), 8)
	assert_gt(layout.rcs_nozzles.size(), 0, "the fixture has RCS nozzles")
	assert_eq(targets.size(), layout.nozzle_count() + layout.rcs_nozzles.size())


func test_no_output_means_every_glow_is_dark() -> void:
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, null)
	assert_eq(targets.size(), layout.nozzle_count() + layout.rcs_nozzles.size())
	for i: int in targets.size():
		assert_eq(targets[i], 0.0)


# --- pod nozzles --------------------------------------------------------------------------------------------


func test_pod_nozzles_follow_their_pods_main_and_retro_levels() -> void:
	# Pod order ur, lr, ul, ll; nozzles are the four mains then the four retros.
	var output: FlightOutput = _output([1.0, 0.5, 0.0, 0.25], [0.0, 0.1, 0.75, 1.0])
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, output)
	var mains: Array[float] = [1.0, 0.5, 0.0, 0.25]
	var retros: Array[float] = [0.0, 0.1, 0.75, 1.0]
	for i: int in layout.nozzle_count():
		var pod: int = layout.nozzle_pods[i]
		var expected: float = mains[pod] if ThrusterLayout.is_main_group(layout.nozzle_groups[i]) else retros[pod]
		assert_almost_eq(targets[i], expected, 1e-12, "%s (pod %s)" % [layout.nozzle_names[i], layout.pod_names[pod]])


func test_pod_levels_are_clamped_to_0_1() -> void:
	var output: FlightOutput = _output([1.7, -0.2, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, output)
	assert_eq(targets[layout.nozzle_names.find("ur_main")], 1.0)
	assert_eq(targets[layout.nozzle_names.find("lr_main")], 0.0)


func test_short_level_arrays_read_as_dark_not_as_an_error() -> void:
	var output: FlightOutput = _output([1.0], [])
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, output)
	assert_eq(targets[layout.nozzle_names.find("ur_main")], 1.0)
	assert_eq(targets[layout.nozzle_names.find("ll_main")], 0.0)
	assert_eq(targets[layout.nozzle_names.find("ur_retro")], 0.0)


# --- tags ---------------------------------------------------------------------------------------------------


func test_each_tag_reads_one_signed_axis() -> void:
	var force := Vector3(0.4, 0.5, 0.0)
	var torque := Vector3(0.6, -0.7, 0.8)
	var expected: Dictionary = {
		"sway_right": 0.4, "sway_left": 0.0, "heave_up": 0.5, "heave_down": 0.0,
		"pitch_up": 0.6, "pitch_down": 0.0, "yaw_left": 0.0, "yaw_right": 0.7,
		"roll_left": 0.8, "roll_right": 0.0, "unknown_tag": 0.0,
	}
	for tag: String in expected:
		assert_almost_eq(ThrusterGlowLevels.tag_level(tag, force, torque), float(expected[tag]), FLOAT32_TOL, tag)
	# The opposite signs light the opposite tags.
	assert_almost_eq(ThrusterGlowLevels.tag_level("sway_left", -force, torque), 0.4, FLOAT32_TOL)
	assert_almost_eq(ThrusterGlowLevels.tag_level("heave_down", -force, torque), 0.5, FLOAT32_TOL)
	assert_almost_eq(ThrusterGlowLevels.tag_level("pitch_down", force, -torque), 0.6, FLOAT32_TOL)
	assert_almost_eq(ThrusterGlowLevels.tag_level("yaw_left", force, -torque), 0.7, FLOAT32_TOL)
	assert_almost_eq(ThrusterGlowLevels.tag_level("roll_right", force, -torque), 0.8, FLOAT32_TOL)


func test_an_rcs_nozzle_takes_the_max_over_its_tags() -> void:
	var tags := PackedStringArray(["sway_left", "yaw_right", "roll_left"])
	assert_almost_eq(ThrusterGlowLevels.rcs_level(tags, Vector3(-0.3, 0.0, 0.0), Vector3(0.0, -0.8, 0.0)), 0.8, FLOAT32_TOL)
	assert_almost_eq(ThrusterGlowLevels.rcs_level(tags, Vector3(-0.9, 0.0, 0.0), Vector3(0.0, -0.8, 0.5)), 0.9, FLOAT32_TOL)
	assert_almost_eq(ThrusterGlowLevels.rcs_level(tags, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.6)), 0.6, FLOAT32_TOL)
	assert_eq(ThrusterGlowLevels.rcs_level(tags, Vector3(0.5, 0.0, 0.0), Vector3(0.0, 0.5, -0.5)), 0.0, "all opposed")
	assert_eq(ThrusterGlowLevels.rcs_level(PackedStringArray(), Vector3.ONE, Vector3.ONE), 0.0, "no tags")


func test_rcs_levels_are_clamped_to_1() -> void:
	assert_eq(ThrusterGlowLevels.tag_level("sway_right", Vector3(3.0, 0.0, 0.0), Vector3.ZERO), 1.0)


func test_targets_light_the_rcs_nozzles_with_the_matching_tag() -> void:
	var output: FlightOutput = _output([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	output.rcs_force_level = Vector3(1.0, 0.0, 0.0)  # sway right
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, output)
	var lit: PackedInt32Array = _rcs_with_tag("sway_right")
	assert_gt(lit.size(), 0, "some nozzles push to the right")
	for i: int in lit:
		assert_eq(targets[i], 1.0, "RCS glow %d" % (i - layout.nozzle_count()))
	for i: int in _rcs_with_tag("sway_left"):
		if not lit.has(i):
			assert_eq(targets[i], 0.0)
	for i: int in layout.nozzle_count():
		assert_eq(targets[i], 0.0, "pod glows stay dark")


# --- against the real flight model --------------------------------------------------------------------------


func _fly(cmd: FlightCommand) -> FlightOutput:
	var spec: ShipSpec = load(SPEC_PATH) as ShipSpec
	assert_not_null(spec)
	return FlightModel.new(spec, layout).compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, false, DT)


func _lit_count(targets: PackedFloat64Array, indices: PackedInt32Array) -> int:
	var count: int = 0
	for i: int in indices:
		if targets[i] > 0.99:
			count += 1
	return count


func test_yaw_right_command_lights_yaw_right_nozzles_not_yaw_left() -> void:
	var cmd := FlightCommand.new()
	cmd.rot = Vector3(0.0, 1.0, 0.0)
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, _fly(cmd))
	var right: PackedInt32Array = _rcs_with_tag("yaw_right")
	var left: PackedInt32Array = _rcs_with_tag("yaw_left")
	assert_gt(right.size(), 0)
	assert_eq(_lit_count(targets, right), right.size(), "every yaw_right nozzle at full")
	for i: int in left:
		assert_eq(targets[i], 0.0, "yaw_left nozzle %d dark" % (i - layout.nozzle_count()))


func test_pitch_up_and_roll_right_and_sway_right_follow_the_model() -> void:
	var pitch := FlightCommand.new()
	pitch.rot = Vector3(1.0, 0.0, 0.0)
	var pitch_targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, _fly(pitch))
	assert_eq(_lit_count(pitch_targets, _rcs_with_tag("pitch_up")), _rcs_with_tag("pitch_up").size())
	for i: int in _rcs_with_tag("pitch_down"):
		assert_eq(pitch_targets[i], 0.0)

	var roll := FlightCommand.new()
	roll.rot = Vector3(0.0, 0.0, 1.0)
	var roll_targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, _fly(roll))
	assert_eq(_lit_count(roll_targets, _rcs_with_tag("roll_right")), _rcs_with_tag("roll_right").size())
	for i: int in _rcs_with_tag("roll_left"):
		assert_eq(roll_targets[i], 0.0)

	var sway := FlightCommand.new()
	sway.strafe = Vector2(1.0, 0.0)
	var sway_targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, _fly(sway))
	assert_eq(_lit_count(sway_targets, _rcs_with_tag("sway_right")), _rcs_with_tag("sway_right").size())
	for i: int in _rcs_with_tag("sway_left"):
		assert_eq(sway_targets[i], 0.0)


func test_right_trigger_lights_the_right_mains_only() -> void:
	var cmd := FlightCommand.new()
	cmd.main_right = 1.0
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(layout, _fly(cmd))
	for i: int in layout.nozzle_count():
		var lit: bool = layout.nozzle_groups[i] == ThrusterLayout.Group.R_MAIN
		assert_eq(targets[i], 1.0 if lit else 0.0, layout.nozzle_names[i])


# --- smoothing ----------------------------------------------------------------------------------------------


func test_smoothing_reaches_63_percent_after_one_time_constant() -> void:
	assert_almost_eq(ThrusterGlowLevels.smooth(0.0, 1.0, 0.08, 0.08), 1.0 - exp(-1.0), 1e-12)


func test_smoothing_is_independent_of_the_frame_rate() -> void:
	var coarse: float = ThrusterGlowLevels.smooth(0.0, 1.0, 0.04, 0.08)
	var fine: float = ThrusterGlowLevels.smooth(ThrusterGlowLevels.smooth(0.0, 1.0, 0.02, 0.08), 1.0, 0.02, 0.08)
	assert_almost_eq(coarse, fine, 1e-12)


func test_smoothing_goes_down_as_well_as_up_and_never_overshoots() -> void:
	var level: float = 1.0
	for i: int in 30:
		var next: float = ThrusterGlowLevels.smooth(level, 0.0, DT, 0.08)
		assert_true(next < level and next >= 0.0)
		level = next
	assert_lt(level, 0.01)


func test_zero_time_constant_snaps_to_the_target() -> void:
	assert_eq(ThrusterGlowLevels.smooth(0.2, 0.9, DT, 0.0), 0.9)
	assert_eq(ThrusterGlowLevels.smooth(0.2, 0.9, 0.0, 0.08), 0.2, "no time, no change")
