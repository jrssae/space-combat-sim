# Parity recordings (M4-T37)

M4-T37 removed the GDScript paths that the native code was paired against (Q67). Before each path went, its parity test
recorded what the GDScript reference gave on the test's seeds into a JSON file here, and the test now compares the native
path with that recording. A test fails when the native result moves, as it did when both paths ran side by side.

- One file per test file, one entry per case. `ParityFixture` (`tests/fixtures/parity_fixture.gd`) reads and writes them.
- Values are plain JSON at full precision: vectors as `[x, y, z]`, integers past 2^53 as strings. Bulky outputs (a battle's
  rows every tick, a long log) are kept as a SHA-256 digest beside the counts a reader can check (hits, rams, ticks).
- The recorders are the tests themselves: each `ParityFixture.expected(file, case, recorder)` call runs its recorder when
  the run sets `SCS_RECORD_FIXTURES=1` (never on CI: with `CI=true` it refuses and reads the recordings).
- **Provenance.** Every recording was taken at `0586e3e`, the commit that added this file, where every GDScript path and
  switch still existed (`weapon_rows_battle.json` is the exception, below). The game and native code of `0586e3e` is the
  tag `m4-gdscript-reference` (`095c73d`, on `main`) plus only the start-up refusal (`src/game/main.gd`, `src/perf/native_lib.gd`), which no recorded path reads.
  After T37 the switches are gone, so a recorder run on a later commit records the native path; re-record only on purpose
  and say so in the commit.

**`weapon_rows_battle.json` is a native recording (M6-T07).** Its GDScript recording (918 hits, 446 by capitals, 174 beam
shots, 150 launches, 26 missiles shot down, 0 mines set off; taken at `0586e3e` and committed in `7987de4`) was made under
M4's moon stand-in, with the tier off (its default then) and the sim clock not reset. M6-T07 removed the moon, so the
battle was compared again with no gravity on either side, tier off, clock reset, seed 1: the GDScript stand-ins at
`0586e3e` give 920, 431, 185, 151, 24, 0 and the native rows at `c4e4d785` give the same 920 hits one for one (tick,
shooter, damage, relative speed); seed 2 likewise (728 hits), seed 3 too (717) but for the last digits of one missile's
relative speed. The stored case is that native battle in the bench's orbit of Epsilon III, tier off: 933, 420, 174, 151,
25, 1. For reference, at `0586e3e` under the moon with the clock reset both paths give 955, 470, 180, 151, 26, 0; with
the tier on (the default since M4-T23) the native battle's resolver lands 822 and 362 with no gravity and 802 and 359 in
orbit, since far ships' fire is then rolled by the tier and never reaches the resolver.

To record again from the GDScript paths, check out `0586e3e` (the tag has the paths but not the recorders) in a separate
worktree, build the library (`scripts/build_native.sh`), and run the test file with the variable set, for example:

```
SCS_RECORD_FIXTURES=1 GUT_SLOW=1 .tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd \
    -gtest=res://tests/unit/test_core_state.gd -gexit
```

The Q16 fights (`brain_tolerance.json`, `flight_parity_fight.json`) hold two references each: the GDScript fight on the
single-thread step (Q16's reference, which the native code matched bit for bit on that step when recorded) and the native
fight on the delayed step (the threaded step's bit-for-bit reference). See each test's header for what is gated.
