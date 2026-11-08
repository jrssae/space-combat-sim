extends GutTest
## The parity recordings' guard (M4-T37 fix round 1): recording mode rewrites the stored references from the code that runs,
## so it refuses on CI, where nobody reviews what it would write.

var _saved: Dictionary = {}


func before_each() -> void:
	for key: String in [ParityFixture.ENV, "CI"]:
		_saved[key] = OS.get_environment(key)


func after_each() -> void:
	for key: String in _saved.keys():
		OS.set_environment(key, _saved[key])


func test_recording_runs_when_asked_off_ci() -> void:
	OS.set_environment(ParityFixture.ENV, "1")
	OS.set_environment("CI", "")
	assert_true(ParityFixture.recording(), "asked for, not on CI: records")


func test_recording_refuses_on_ci() -> void:
	OS.set_environment(ParityFixture.ENV, "1")
	OS.set_environment("CI", "true")
	assert_false(ParityFixture.recording(), "on CI the recordings are only read")
	assert_push_error("refuses", "and says why")


func test_no_recording_unless_asked() -> void:
	OS.set_environment(ParityFixture.ENV, "")
	OS.set_environment("CI", "true")
	assert_false(ParityFixture.recording())
