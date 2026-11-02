extends GutTest
## WallClockBudget (M3-T12): a wall-clock budget is asserted on the maintainer's machine and only recorded on CI, where a shared
## runner's clock says nothing about the game (`CI=true`, as GitHub Actions sets it).

var _ci_backup: String = ""


func before_each() -> void:
	_ci_backup = OS.get_environment("CI")


func after_each() -> void:
	OS.set_environment("CI", _ci_backup)


func test_ci_is_read_from_the_environment() -> void:
	OS.set_environment("CI", "true")
	assert_true(WallClockBudget.on_ci())
	OS.set_environment("CI", "")
	assert_false(WallClockBudget.on_ci())


func test_on_ci_a_budget_overrun_is_recorded_not_failed() -> void:
	OS.set_environment("CI", "true")
	var fails: int = get_fail_count()
	var passes: int = get_pass_count()
	WallClockBudget.assert_under(self, 900.0, 500.0, "a slow tick")
	var fails_after: int = get_fail_count()
	var passes_after: int = get_pass_count()
	assert_eq(fails_after, fails, "nothing failed")
	assert_eq(passes_after, passes + 1, "the check is counted, as recorded")


func test_locally_a_budget_kept_is_a_passing_assert() -> void:
	OS.set_environment("CI", "")
	var passes: int = get_pass_count()
	WallClockBudget.assert_under(self, 100.0, 500.0, "a quick tick")
	assert_eq(get_pass_count(), passes + 1)
