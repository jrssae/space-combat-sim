extends GutTest
## `MotionBlurGate`: the blur strength the effect gets each rendered frame. A rebase moves the camera and every hull by
## kilometres in one tick, so the frames that straddle it must not be smeared.


var gate: MotionBlurGate


func before_each() -> void:
	gate = MotionBlurGate.new()


func test_passes_the_strength_through_when_nothing_happened() -> void:
	assert_almost_eq(gate.take(0.5), 0.5, 0.0001)
	assert_almost_eq(gate.take(0.5), 0.5, 0.0001, "and again next frame")


func test_strength_is_clamped_to_the_unit_range() -> void:
	assert_almost_eq(gate.take(3.0), 1.0, 0.0001)
	assert_almost_eq(gate.take(-1.0), 0.0, 0.0001)


func test_a_rebase_blanks_the_next_frames_then_the_blur_returns() -> void:
	gate.note_rebase()
	for i: int in MotionBlurGate.SKIP_FRAMES_AFTER_REBASE:
		assert_eq(gate.take(0.5), 0.0, "frame %d after the rebase is not blurred" % i)
	assert_almost_eq(gate.take(0.5), 0.5, 0.0001, "then it is back")


func test_the_skip_is_counted_in_frames_not_taken_as_a_flag() -> void:
	assert_gt(MotionBlurGate.SKIP_FRAMES_AFTER_REBASE, 0)
	gate.note_rebase()
	assert_eq(gate.skipping(), MotionBlurGate.SKIP_FRAMES_AFTER_REBASE)
	gate.take(0.5)
	assert_eq(gate.skipping(), MotionBlurGate.SKIP_FRAMES_AFTER_REBASE - 1)


func test_a_second_rebase_restarts_the_skip() -> void:
	gate.note_rebase()
	gate.take(0.5)
	gate.note_rebase()
	assert_eq(gate.skipping(), MotionBlurGate.SKIP_FRAMES_AFTER_REBASE)


func test_a_frame_with_blur_off_still_ages_the_skip() -> void:
	# The skip must run out in rendered frames even while the blur is switched off, or turning it on later
	# would find stale frames still counted.
	gate.note_rebase()
	for i: int in MotionBlurGate.SKIP_FRAMES_AFTER_REBASE:
		gate.take(0.0)
	assert_eq(gate.skipping(), 0)
