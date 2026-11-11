extends GutTest
## The quick tier's list (M6-T17): every file in `tests/quick_suite.txt` exists, is a unit or integration test listed once, and is
## fast and headless (no slow gate, no balance gate, no GPU file), so `scripts/run_tests.sh --quick` stays a few minutes.

const LIST: String = "res://tests/quick_suite.txt"
const BALANCE_LIST: String = "res://tests/balance_suite.txt"


func _paths(list: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line: String in FileAccess.get_file_as_string(list).split("\n"):
		var path: String = line.strip_edges()
		if not path.is_empty() and not path.begins_with("#"):
			out.append(path)
	return out


func test_every_listed_path_exists_and_is_a_test_file() -> void:
	var paths: PackedStringArray = _paths(LIST)
	assert_gt(paths.size(), 50, "the list is not empty")
	for path: String in paths:
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		assert_true(path.get_file().begins_with("test_") and path.get_file().ends_with(".gd"), "%s is a test_*.gd" % path)


func test_no_path_is_listed_twice() -> void:
	var seen: Dictionary = {}
	for path: String in _paths(LIST):
		assert_false(seen.has(path), "%s is listed once" % path)
		seen[path] = true


func test_no_listed_file_is_slow_balance_or_gpu() -> void:
	var balance: PackedStringArray = _paths(BALANCE_LIST)
	var saved: String = OS.get_environment(SlowTests.ENV)
	OS.set_environment(SlowTests.ENV, "")
	for path: String in _paths(LIST):
		assert_false(path.ends_with("_gpu.gd"), "%s is a GPU file" % path)
		assert_false(balance.has(path), "%s is a balance file" % path)
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			continue
		var instance: Object = script.new()
		if instance.has_method("should_skip_script"):
			assert_eq(instance.call("should_skip_script"), false, "%s skips itself without GUT_SLOW, so it is a slow file" % path)
		if instance is Node:
			(instance as Node).free()
	OS.set_environment(SlowTests.ENV, saved)
