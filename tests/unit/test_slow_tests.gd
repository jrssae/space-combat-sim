extends GutTest
## The slow test switch (M4-T36, Q58): the named slow files skip themselves unless `GUT_SLOW=1`, and the full run sets it.

const SLOW_FILES: Array[String] = [
	"res://tests/integration/test_dogfight.gd",
	"res://tests/integration/test_m3_sandbox.gd",
	"res://tests/integration/test_brain_tolerance.gd",
	"res://tests/integration/test_flight_parity_fight.gd",
	"res://tests/integration/test_weapon_rows_battle.gd",
]

var _saved: String = ""


func before_each() -> void:
	_saved = OS.get_environment(SlowTests.ENV)


func after_each() -> void:
	OS.set_environment(SlowTests.ENV, _saved)


func test_the_switch_reads_the_environment() -> void:
	OS.set_environment(SlowTests.ENV, "")
	assert_false(SlowTests.enabled())
	assert_typeof(SlowTests.skip_reason(), TYPE_STRING, "off: skipped, with a reason (GUT skips on any String)")
	OS.set_environment(SlowTests.ENV, "1")
	assert_true(SlowTests.enabled())
	assert_eq(SlowTests.skip_reason(), false, "on: runs (a String, even empty, would skip it)")


func test_every_named_slow_file_skips_itself_when_the_switch_is_off() -> void:
	for path: String in SLOW_FILES:
		var script := load(path) as GDScript
		assert_not_null(script, path)
		var instance: Object = script.new()
		assert_true(instance.has_method("should_skip_script"), "%s asks the switch" % path)
		OS.set_environment(SlowTests.ENV, "")
		assert_typeof(instance.call("should_skip_script"), TYPE_STRING, "%s is left out of a focused run" % path)
		OS.set_environment(SlowTests.ENV, "1")
		assert_eq(instance.call("should_skip_script"), false, "%s runs with GUT_SLOW=1" % path)
		instance.free()


func test_the_full_run_and_ci_set_the_switch() -> void:
	var runner: String = FileAccess.get_file_as_string("res://scripts/run_tests.sh")
	assert_true(runner.contains("export GUT_SLOW=\"${GUT_SLOW:-1}\""), "run_tests.sh turns it on unless told otherwise")
	var ci: String = FileAccess.get_file_as_string("res://.github/workflows/ci.yml")
	assert_true(ci.contains("GUT_SLOW: \"1\""), "CI's shards set it")
