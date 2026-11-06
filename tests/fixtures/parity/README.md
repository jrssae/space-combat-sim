# Parity recordings (M4-T37)

M4-T37 removed the GDScript paths that the native code was paired against (Q67). Before each path went, its parity test
recorded what the GDScript reference gave on the test's seeds into a JSON file here, and the test now compares the native
path with that recording. A test fails when the native result moves, as it did when both paths ran side by side.

- One file per test file, one entry per case. `ParityFixture` (`tests/fixtures/parity_fixture.gd`) reads and writes them.
- Values are plain JSON at full precision: vectors as `[x, y, z]`, integers past 2^53 as strings. Bulky outputs (a battle's
  rows every tick, a long log) are kept as a SHA-256 digest beside the counts a reader can check (hits, rams, ticks).
- The recorders are the tests themselves: each `ParityFixture.expected(file, case, recorder)` call runs its recorder when
  the run sets `SCS_RECORD_FIXTURES=1`. They were run on the commit that added this file, where every GDScript path and
  switch still existed (the tag `m4-gdscript-reference` on `main` has the same paths). After T37 the switches are gone, so a
  recorder run on a later commit records the native path; re-record only on purpose and say so in the commit.

To record again from the GDScript paths, check out the commit that added this file in a separate worktree, build the
library (`scripts/build_native.sh`), and run the test file with the variable set, for example:

```
SCS_RECORD_FIXTURES=1 GUT_SLOW=1 .tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd \
    -gtest=res://tests/unit/test_core_state.gd -gexit
```

The Q16 fights (`brain_tolerance.json`, `flight_parity_fight.json`) hold two references each: the GDScript fight on the
single-thread step (Q16's reference, which the native code matched bit for bit on that step when recorded) and the native
fight on the delayed step (the threaded step's bit-for-bit reference). See each test's header for what is gated.
