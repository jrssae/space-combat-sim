class_name WallClockBudget
extends RefCounted
## Test fixture (M3-T12): wall-clock budgets (AI think time, the resolvers, a rebase) mean something on the maintainer's machine,
## not on a shared CI runner. There (`CI=true`, as GitHub Actions sets it) they are recorded with a line saying so, not asserted.


## Whether this run is on CI.
static func on_ci() -> bool:
	return OS.get_environment("CI") == "true"


## Asserts `measured` is under `budget` (same unit); on CI prints both and says the budget was not asserted.
static func assert_under(test: GutTest, measured: float, budget: float, what: String) -> void:
	if on_ci():
		test.gut.p("[CI] %s: %.1f against a budget of %.1f, recorded, not asserted (a shared runner's wall clock)" % [what,
				measured, budget])
		test.pass_test("recorded on CI: %s" % what)
		return
	test.assert_lt(measured, budget, what)
