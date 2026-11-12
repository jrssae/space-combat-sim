extends GutTest
## The balance test switch (M6-T17): balance tests skip themselves unless `GUT_BALANCE=1`, and only `--balance` and `--full` set it.

var _saved: String = ""


func before_each() -> void:
	_saved = OS.get_environment(BalanceTests.ENV)


func after_each() -> void:
	OS.set_environment(BalanceTests.ENV, _saved)


func test_the_switch_reads_the_environment() -> void:
	OS.set_environment(BalanceTests.ENV, "")
	assert_false(BalanceTests.enabled())
	assert_typeof(BalanceTests.skip_reason(), TYPE_STRING, "off: skipped, with a reason (GUT skips on any String)")
	OS.set_environment(BalanceTests.ENV, "1")
	assert_true(BalanceTests.enabled())
	assert_eq(BalanceTests.skip_reason(), false, "on: runs (a String, even empty, would skip it)")


func test_the_per_test_gate_lets_the_test_go_on_when_on() -> void:
	OS.set_environment(BalanceTests.ENV, "1")
	assert_false(BalanceTests.skip(self), "on: the test goes on (off marks it pending, which the gated fights show)")


func test_every_listed_balance_file_exists_and_asks_the_switch() -> void:
	var paths: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string("res://tests/balance_suite.txt").split("\n"):
		if not line.strip_edges().is_empty() and not line.begins_with("#"):
			paths.append(line.strip_edges())
	assert_gt(paths.size(), 0, "the list is not empty")
	for path: String in paths:
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		assert_true(FileAccess.get_file_as_string(path).contains("BalanceTests."), "%s uses the gate" % path)


func test_the_balance_run_and_the_full_run_set_the_switch() -> void:
	var runner: String = FileAccess.get_file_as_string("res://scripts/run_tests.sh")
	assert_true(runner.contains("GUT_SLOW=1 GUT_BALANCE=1"), "--balance turns it on")
	assert_true(runner.contains("export GUT_BALANCE=1"), "--full turns it on")
	assert_true(runner.contains("export GUT_BALANCE=\"${GUT_BALANCE:-0}\""), "--standard leaves it off")
