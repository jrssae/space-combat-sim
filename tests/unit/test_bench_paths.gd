extends GutTest
## BenchPaths (M8-T14, roadmap L15): the bench's reports stay in the project's `reports/` while it takes files and move to
## the user's folder when it does not (an exported build). The answer to "does it take files" is passed in here.

const USER_DIR: String = "user://test_bench_paths"
const PROJECT_DIR: String = "res://reports/test_bench_paths"

var _asked: int = 0


func before_each() -> void:
	_asked = 0


func after_each() -> void:
	for dir: String in [USER_DIR, PROJECT_DIR, "user://reports/test_bench_paths"]:
		_remove(ProjectSettings.globalize_path(dir))


func _remove(absolute: String) -> void:
	var listing := DirAccess.open(absolute)
	if listing == null:
		return
	for name: String in listing.get_files():
		listing.remove(name)
	for name: String in listing.get_directories():
		_remove(absolute.path_join(name))
	DirAccess.remove_absolute(absolute)


func _yes() -> bool:
	_asked += 1
	return true


func _no() -> bool:
	_asked += 1
	return false


func test_a_writable_project_keeps_its_reports_folder() -> void:
	assert_eq(BenchPaths.resolve("res://reports/perf/sweep/runs/furball_25_s1", _yes), "res://reports/perf/sweep/runs/furball_25_s1")
	assert_eq(BenchPaths.resolve("res://reports", _yes), "res://reports")


func test_a_read_only_project_sends_reports_to_the_user_folder() -> void:
	assert_eq(BenchPaths.resolve("res://reports/perf/sweep/runs/furball_25_s1", _no), "user://reports/perf/sweep/runs/furball_25_s1")
	assert_eq(BenchPaths.resolve("res://reports", _no), "user://reports")
	assert_eq(BenchPaths.resolve("res://reports/", _no), "user://reports/")


func test_the_bench_default_root_follows_the_project() -> void:
	assert_eq(BenchPaths.resolve(BenchRunner.DEFAULT_ROOT, _yes), "res://reports/perf")
	assert_eq(BenchPaths.resolve(BenchRunner.DEFAULT_ROOT, _no), "user://reports/perf")


func test_paths_outside_the_reports_folder_are_left_alone() -> void:
	for path: String in ["user://test_bench/x", "/tmp/bench/x", "res://reports_old/x", "res://data/x", ""]:
		assert_eq(BenchPaths.resolve(path, _no), path, path)
	assert_eq(_asked, 0, "the project is not probed for a path that is not in it")


func test_a_moved_path_stays_where_it_is() -> void:
	var moved: String = BenchPaths.resolve("res://reports/perf/a", _no)
	assert_eq(BenchPaths.resolve(moved, _no), moved)
	assert_eq(BenchPaths.resolve(moved, _yes), moved)


func test_a_folder_that_takes_files_is_writable_and_made() -> void:
	var absolute: String = ProjectSettings.globalize_path(USER_DIR.path_join("deep/er"))
	assert_true(BenchPaths.folder_writable(absolute))
	assert_true(DirAccess.dir_exists_absolute(absolute), "made on the way")
	assert_eq(DirAccess.get_files_at(absolute).size(), 0, "the probe leaves nothing behind")


func test_no_folder_behind_the_path_is_not_writable() -> void:
	assert_false(BenchPaths.folder_writable(""), "an export: res:// has no folder")
	assert_false(BenchPaths.folder_writable("reports"), "an export: res://reports comes out relative")
	var root: String = ProjectSettings.globalize_path(USER_DIR)
	DirAccess.make_dir_recursive_absolute(root)
	FileAccess.open(root.path_join("a_file"), FileAccess.WRITE).close()
	assert_false(BenchPaths.folder_writable(root.path_join("a_file/below")), "nothing can be made there")
	assert_engine_error("Could not create directory", "the engine says so once")


func test_this_project_folder_is_writable() -> void:
	assert_true(BenchPaths.project_reports_writable(), "the tests run from a project folder")


func test_a_report_written_to_a_read_only_project_lands_in_the_user_folder() -> void:
	var problem: String = BenchReport.write(PROJECT_DIR.path_join("run"), {"n": 3}, "# page", _no)
	assert_eq(problem, "")
	var moved: String = "user://reports/test_bench_paths/run"
	assert_eq((JSON.parse_string(FileAccess.get_file_as_string(moved.path_join("summary.json"))) as Dictionary).get("n"), 3.0)
	assert_eq(FileAccess.get_file_as_string(moved.path_join("summary.md")), "# page")
	assert_false(FileAccess.file_exists(PROJECT_DIR.path_join("run/summary.json")), "nothing in the project")


func test_a_report_written_to_a_writable_project_stays_in_it() -> void:
	var problem: String = BenchReport.write(PROJECT_DIR.path_join("run"), {"n": 4}, "# page", _yes)
	assert_eq(problem, "")
	assert_true(FileAccess.file_exists(PROJECT_DIR.path_join("run/summary.json")), "in the project's reports")
	assert_false(FileAccess.file_exists("user://reports/test_bench_paths/run/summary.json"), "nothing in the user folder")
