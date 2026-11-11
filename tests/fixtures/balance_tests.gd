class_name BalanceTests
extends RefCounted
## The balance test switch (M6-T17): tests that judge how the game plays (a six-minute dogfight, three waves, the turrets' win rate)
## run only when `GUT_BALANCE=1`, which `scripts/run_tests.sh --balance` and `--full` set. The merge gate (`--standard`) and a
## focused run leave them out. A balance test starts with `if BalanceTests.skip(self): return`, before it flies anything; a
## file made only of balance tests returns `BalanceTests.skip_reason()` from GUT's `should_skip_script()` instead.

const ENV: String = "GUT_BALANCE"


## Whether the balance tests run in this process.
static func enabled() -> bool:
	return OS.get_environment(ENV) == "1"


## GUT's skip verdict for a balance-only file: false (run it) when the switch is on, else why it was left out.
static func skip_reason() -> Variant:
	return false if enabled() else "balance test, left out of the gate (set %s=1 or run scripts/run_tests.sh --balance)" % ENV


## Marks the running test pending and returns true when the switch is off, so the test can return before flying anything.
static func skip(test: GutTest) -> bool:
	if enabled():
		return false
	test.pending(str(skip_reason()))
	return true
