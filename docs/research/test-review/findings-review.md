# Test review findings and objections

Reviewed 2026-11-09 after pulling `origin/m5` to `5d81686`. The review notes are also appended to the source documents in this
directory. The removal and quick-suite recommendations were reviewed against the test bodies, fixture payloads, current runner,
and recorded timings. This was a static review; tests were not run.

## Review of existing findings

### L14: test and script duplication

- **Keep, with a scope correction:** `tests/unit/test_core_state.gd` runs `_battle({}, 1)` once, then compares that same digest
  against three `OLD_PATH_CASES` fixture entries. If the three fixture payloads are byte-identical, two comparisons and two
  redundant fixture entries can be removed safely after verifying the payloads. This does not avoid the expensive battle, since
  it is simulated only once; describe it as assertion/fixture cleanup, not a meaningful test-runtime reduction.
- **Keep as a manual or opt-in balance check, not a deletion finding:** `test_m3_sandbox.gd` and `test_dogfight.gd` call
  `pending()` when the balance goal is missed. The checks still run long simulations and retain useful diagnostic output, while
  `pending()` merely avoids failing the suite for the unsettled balance target. Moving the long balance loops out of default CI
  is a reasonable runtime proposal, provided the manual command remains discoverable and cheap setup/determinism checks stay in
  routine coverage. Verify current balance status before calling these "always pending"; the source condition is conditional.
- **No objection to the helper note:** repeated `_ticks`, `_exec`, and `_console` helpers are maintenance duplication, but do not
  establish duplicate assertions. Centralization should be a separate refactor and must retain distinct test behavior.
- **No basis for broad parity-test deletion:** parity fixture tests compare current behavior to stored baselines rather than
  running a removed implementation. Their descriptions should make that clear. Retain any fixture that protects a supported
  output/behavior contract; prune only after confirming its covered contract is obsolete or covered elsewhere.

### F9: explosion LOD test coverage

- **Agree with the test-quality concern:** expectations derived from the same implementation constants can move with a regression;
  a few literal boundary expectations improve the test's ability to catch accidental tuning changes.
- **Agree that the scaled `picture_lines` branch is not covered by the cited headless tests.** A pure helper accepting window
  lines, scale, and headless state is a reasonable way to exercise it without depending on a live display. This is missing coverage,
  not a candidate for removing existing tests.

### F10: CI timeout and `info.md`

- **Objection: the finding is stale in the current tree.** `tests/integration/test_info_md.gd` exists and checks registered commands
  and state providers against `info.md`. `scripts/run_tests.sh` sets a 2,400-second GUT timeout for CI shards and 3,600 seconds
  for an unsharded run; CI's job timeout is 60 minutes. The original missing-test claim should be closed, and timeout wording
  should be based on the actual invocation path (sharded CI versus local unsharded). Do not add a duplicate `info.md` test.

### Additional objections after reviewing the pulled findings

- **A1-A6 need assertion-level comparison before being called duplicates.** The replacement `test_core_threads` currently compares
  per-tick row digests and think counts; `test_core_state` additionally compares hit digests. `test_bolt_rows` checks bolt,
  hit, and row digests; `test_row_commands` checks command rows, core rows, and event counts; `test_driver_step` also checks
  hosted/processing counts and recorded pilot/held data in its baseline cases. The candidate table correctly calls out some of
  these gaps, but its safe-removal conclusion must require all unique observables to be moved to a surviving test. Identical
  digest fragments alone do not establish equivalent coverage.
- **B1 is conditional, not a confirmed whole-file removal as written.** `test_core_state` asserts `contact_path() == native`,
  while `test_ram_contact_columns` also asserts the resolver source matches the fixture (`source: core`) and compares the
  column-path run with that historical fixture. If deleting `test_ram_contact_columns.gd` and its fixture, first move that
  source assertion to the kept test and verify its ram/pose serialization covers the same contract. The `test_ram_tracker_columns`
  unit test is a separate 400-tick sample-vs-columns comparison and should not be conflated with this melee replay.
- **D6 is not an exact execution-path duplicate.** `test_damage.gd` calls `DebugConsole.registry.execute()` in-process and checks
  formatted output; the `run_tests.sh` smoke starts a separate Godot process through `--console-exec`, checks its stdout and exit
  status, and therefore covers argument parsing and process wiring. Removing the GUT test may be acceptable if equivalent in-process
  output checks remain elsewhere, but it does not replace the CLI smoke or vice versa.
- **C6 wording should distinguish gameplay from tooling.** `native_boundary_bench.gd` is a real caller of `NativeProbe.in_range`;
  the function is outside the game runtime but is used by the benchmark. Keep that distinction in the finding so “no production
  calls” is not read as “no project caller.”
- **F3 tolerance checks still have a distinct role when a golden is intentionally refreshed.** Exact native fixtures catch any
  drift until re-recorded; the old-path tolerance check can constrain the size of an intentional re-recorded behavior change.
  These long tests should be retained if that tolerance remains a gameplay acceptance rule, even though an unchanged exact fixture
  will usually fail first.
- **H1 should prefer wiring Rust tests into the full gate.** GUT counterparts exercise public Godot/native integration, but do not
  necessarily cover internal Rust edge cases. A quick-only `cargo test` leaves those cases out of the merge gate; do not drop the
  Rust tests solely because superficially similar GUT tests exist.

The other entries are plausible cleanup leads rather than blanket delete instructions. In particular, D5's facade tests are cheap
and assert behavior at the `Factions` API actually used by callers; remove only repeated rule examples after retaining at least a
focused facade delegation/installation test.

## Removal candidates

No whole test file is confirmed safe to delete from this review. Proposed checks before removing assertions or moving tests:

1. Byte-compare the three old-path fixture payloads in `tests/fixtures/parity/core_state.json`. If identical, retain one named
   case and one comparison in `test_core_state.gd`; expected runtime savings are negligible because `_battle` runs once.
2. Check recent results for the AC12 tests. If they remain expensive and pending, put only the multi-minute balance loops behind
   an explicit/manual invocation. Retain the tests and diagnostics, and preserve routine coverage for scenario setup and seeded
   determinism.
3. Review golden parity fixtures one by one against current requirements. A removed reference path does not by itself make its
   recorded output useless; it can still serve as a regression oracle.
4. Avoid consolidating same-seed tests across unrelated subsystems. Similar test structure is not behavioral duplication.

## Proposed quick suite for implementation

Use [quick-test-suite.md](quick-test-suite.md) as the primary implementation proposal: it names a 99-file GUT selection and 20
Python modules, and reports a roughly 3.5-minute trial run versus a much longer full gate. I prefer that measured list to the
smaller tentative list from my first pass, with the amendments in this review applied: validate Godot import cache on clean
checkouts, explicitly validate Python dependencies, and either add quick turret/civilian integration coverage or disclose those
omissions. Keep `scripts/run_tests.sh` as the full merge gate; run Rust unit tests in that full gate as proposed in this review,
not only in the quick command.

Treat the recorded runtime as specific to the trial environment. The timings document reports a full GUT run ending in timeout,
not a completed full run, and the cold Rust build adds over a minute. The implementing agent should remeasure after the final list
and runner are implemented; do not infer clean-checkout or cold-build timing from the warm trial.
