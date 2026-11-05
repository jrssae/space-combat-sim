class_name SlowTests
extends RefCounted
## The slow test switch (M4-T36, Q58): the long seeded parity fights and the pending balance files run only when `GUT_SLOW=1`
## (`scripts/run_tests.sh` sets it, so CI's shards and the milestone's full run take them; a focused run leaves them out). Such a
## file returns `SlowTests.skip_reason()` from GUT's `should_skip_script()`.

const ENV: String = "GUT_SLOW"


## Whether the slow files run in this process.
static func enabled() -> bool:
	return OS.get_environment(ENV) == "1"


## GUT's skip verdict for a slow file: empty (run it) when the switch is on, else why it was left out.
static func skip_reason() -> String:
	return "" if enabled() else "slow file, left out of focused runs (set %s=1 to run it)" % ENV
