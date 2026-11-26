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

**M7-T16 re-recorded the native entries** (the raider rebuilt to its reference model: a new hull, hit volumes and muzzles move
every seeded battle with raiders in it). `ParityFixture.rerecorded(file, case, value[, key])` writes what the test just flew
when the run sets `SCS_RECORD_FIXTURES=1`; the Q16 fights record their `native` references from the delayed step, which the
threaded fight then matched bit for bit. Run, at the M7-T16 commit:

```
SCS_RECORD_FIXTURES=1 GUT_SLOW=1 .tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit \
    -gtest=res://tests/integration/test_brain_tolerance.gd,res://tests/integration/test_flight_parity_fight.gd,res://tests/integration/test_weapon_rows_battle.gd,res://tests/unit/test_bolt_rows.gd,res://tests/unit/test_core_state.gd,res://tests/unit/test_driver_step.gd,res://tests/unit/test_row_commands.gd
```

The GDScript entries (`gdscript`, `gdscript_*`) stay as recorded at `0586e3e` on the old raider: `brain_tolerance` still holds
Q16's hits and mix against them; `flight_parity_fight` prints its mix against them (12 points on the new hull) and gates the hits.
What moved (old → new): `weapon_rows_battle` 933, 420, 174, 151, 25, 1 → 779, 380, 144, 145, 25, 1; the 100-ship battle of
`bolt_rows`, `core_state`, `driver_step` and `row_commands` 62 → 67 hits (thinks 12 033 → 12 034 near and far, 8 238 → 8 239 far
rate; the row, command, hit and pilot digests new); `brain_tolerance` native hits furball 264, 315, 256 → 268, 248, 285, spread
355, 301, 298 → 330, 324, 293; `flight_parity_fight` 127 → 144 hits over 30 s, mix attack 18 evade 7 → attack 20 evade 5.


**M7-T48 re-recorded `weapon_rows_battle` alone**: the bench's 1 000 rocks became the generated asteroids (a shape and turn per
rock, one to three collision spheres each, in place of one sphere of the rock's radius), so the seeded battle flies among other
obstacles. HEAD before the change still gave 780, 380, 144, 145, 25, 1 against the stored 779, 380, 144, 145, 25, 1; with the
generated rocks the battle gives 704, 321, 132, 146, 25, 1 (capitals' hits 15 % down, outside the 10 % gate), the same on a
second run. No other recording holds rocks: the other battles are fighters only (`SeededBattle`) or furballs.


**M7-T64 re-recorded `mine_kernel` (`edge_of_a_trigger`, `belt_seed_23`)**: a blast sets off neighbouring mines and a touch sets one
off whoever's it is; trigger arithmetic unchanged. (`edge_of_a_trigger`: two mines go off from another's blast at tick 1;
`belt_seed_23`: blasts carry on from tick 0 and a fighter touches a mine at tick 801.)


**M7-T65 re-recorded `weapon_rows_battle` (`battle_100_seed_1`)**: the bench's mines are laid as groups in the fights, so the
100-ship battle sets off 36 mines instead of 1; hits, beams and missiles unchanged (704, 321, 132, 146, 25, 1 → 704, 321, 132,
146, 25, 36).


**M7-T64 also re-recorded `turret_kernel` (`seed_7`, `rebase_at_90`, `relation_changed_at_120`)**, found by the full check after
the commit: the miniature battle flies through a mine belt, and a blast now sets off its neighbours, so a few mines go off a few
ticks early. Only the mine fields of those ticks moved (mines set off, the mines' hits, the mines left to check: `seed_7` ticks
26-38, `rebase_at_90` 3-18, `relation_changed_at_120` 18-24); every turret's pick, aim and shot, every projectile made, every
kill and the end counts are byte for byte the old recording's (compared against the log of the commit before M7-T64, which still
gave the stored digests).


**M10-T14's follow-up re-recorded the native entries of every fight with Starfuries in it** (Q76: the Starfury fires both cannons
together, a pair every 0.25 s from a capacitor of 200 at +50/s, twice M5's bolts; a bolt still does 10). Run as M7-T16's command
above. What moved (old → new): `weapon_rows_battle` 704, 321, 132, 146, 25, 36 → 1 156, 340, 133, 145, 24, 36; the 100-ship
battle of `bolt_rows`, `core_state`, `driver_step` and `row_commands` 67 → 119 hits, 1 → 4 kills (thinks 8 239 → 8 242 far rate,
12 034 → 12 037; the digests new); `flight_parity_fight` 43 → 95 hits over 10 s and 144 → 247 over 30 s, mix attack 20 evade 5 →
attack 16 evade 9; `brain_tolerance` native hits furball 268, 248, 285 → 485, 537, 457, spread 330, 324, 293 → 568, 561, 515.
The GDScript entries cannot be flown again with two cannons, so both Q16 files print their hits against them, no longer gate
them; `brain_tolerance` still gates the mix (within 5 points on every seed) and both gate the native step bit for bit.

**Q79 re-recorded the same native entries**: the Starfury starts in alternating fire (one bolt every 0.125 s, the same bolt rate
as Q76's linked pairs). Run as M7-T16's command above. What moved (old → new): `weapon_rows_battle` 1 156, 340, 133, 145, 24, 36 →
1 315, 355, 147, 144, 25, 56; the 100-ship battle 119 → 89 hits, 4 → 3 kills (thinks 8 242 → 8 250 far rate, 12 037 → 12 042);
`flight_parity_fight` 95 → 98 hits over 10 s and 247 → 371 over 30 s, mix attack 16 evade 9 → attack 18 evade 7;
`brain_tolerance` native hits furball 485, 537, 457 → 680, 710, 644, spread 568, 561, 515 → 618, 888, 513. Its mix gate against
the GDScript fight fails on spread seed 1 (evade 5.5 points against the 5 allowed); left for the maintainer, not widened.

**Q80 re-recorded the same native entries**: a bolt hit's reaction counts from the first hit the pilot has not yet answered,
not the latest (under alternating fire a hit every 0.125 s kept resetting a 0.25 s reaction, so raiders evaded only once a burst
stopped). Run as M7-T16's command above. What moved (old → new): `weapon_rows_battle` 1 315, 355, 147, 144, 25, 56 → 966, 339,
127, 138, 24, 36; the 100-ship battle 89 → 93 hits (thinks 8 250 → 8 251 far rate; the player's battle 89 → 88 hits);
`flight_parity_fight` 98 → 54 hits over 10 s and 371 → 201 over 30 s, mix attack 18 evade 7 → attack 15 evade 10;
`brain_tolerance` native hits furball 680, 710, 644 → 368, 446, 394, spread 618, 888, 513 → 460, 427, 378. Its mix gate against
the GDScript fight passes again: worst furball 3.6, 2.2, 0.4 points, spread 1.4, 0.6, 0.3.

**M10-T15 re-recorded `turret_kernel.json`** (the seeded scene's 90 mines are `MineField`s now: they blast with the table's falloff, cause `blast`,
instead of a flat 200, and the log no longer carries `checked`; `weapon_rows_battle.json` and its counts are unchanged). Recorded from the
native path with `SCS_RECORD_FIXTURES=1 GUT_SLOW=1 ... -gtest=res://tests/unit/test_turret_kernel.gd`. `mine_kernel.json` is gone with
its test: the mine kernels' own cargo tests and `test_mine_field` replace it.

**M10-T76 recorded `blast_landing.json` from the GDScript landing** (`BlastResolver._land`, before the native batch), in the real
main scene (free flight, Babylon 5 in play): a fighter group with low hulls blowing in turn, an Omega with its sections nearly
spent taking torpedoes and energy-mine blasts and its death blast, Babylon 5's sections and grid, and an Omega dying beside a
100-mine line with raiders at its far end (133 blasts, 80 hits, 126 events). Recorded with
`SCS_RECORD_FIXTURES=1 ... -gselect=test_blast_landing_parity.gd -gunit_test_name=test_blasts_and`; the file's 1-thread and
`delayed` cases read the same entry.
