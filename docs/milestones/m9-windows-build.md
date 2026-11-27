# Milestone 9: Windows build

> "A second platform." (`docs/roadmap.md`)

**Status:** **in progress** (2026-11-27). Branch `m9` was first cut from `m10` at `af5492c9`; on 2026-11-27 the maintainer
rebased it onto `main` (`02aeec99`, M8 accepted) and dropped M10's work (Q7, revised): M9's purpose is a Windows build of `main`,
and M10's changes are out of scope. M9 merges to `main` when accepted; `m10` picks up M9 from `main` afterwards. Planned from two read-only reviews of `af5492c9`: a Windows
portability review and a parity and `libm` study (the controller's scratchpad, not in the repo; their findings are cited below
by file and line, checked against `af5492c9`). The maintainer answered their questions on 2026-11-25 and 2026-11-26 (Q1 to Q8).

**Windows session (2026-11-27, maintainer):** work continues on the RTX 3060 PC (Windows 11, Ryzen 9 5900X), which overrides
D9.3 for this session: agents build and verify the Windows side locally, with CI as the later confirmation (T09, T10). Rust
(MSVC), the VS Build Tools, Godot 4.7.2 and `gh` may be installed there; assets are generated on that PC for local use only (D9.1
stands for CI). The Linux-side tasks (T04, T05, T13) wait for the Linux machine. Agents commit on `m9` and ask before every push.

Read `CLAUDE.md` first, then only the files a task names. Grep the big docs (`docs/architecture.md`, the M4 and M10 milestone
files); never read them whole. No agent machine runs Windows: everything Windows-only is proven on GitHub's Windows runner
(D9.3), so those tasks say so. Each task is one PR-sized unit and names a recommended agent model.

## Goal

The game runs on Windows x86_64 as it does on Linux: the native library built for Windows, the tutorial playable from a
release zip with the gamepad and the keyboard, Forward+ on Vulkan, `user://` under `%APPDATA%`. CI proves it on every push.
Linux stays the main platform and does not change: its CI, its release and its recordings stay green, and every later
milestone keeps both builds green.

The hard part is parity. The fixtures in `tests/fixtures/parity/` are bit for bit and many are SHA-256 digests of whole
seeded battles (`ParityFixture.digest`). Rust's `f64::sin` and its kin call the platform C runtime (glibc on Linux, the
UCRT under MSVC), which differ in the last bit, and the engine's own trig and Jolt do the same on their side. Q1 settles it:
the native maths moves to the pure-Rust `libm` crate, and the tests that also depend on engine maths get a Windows mode.

## Planning questions (asked 2026-11-25, answered 2026-11-25 and 2026-11-26)

| Q | Question | Proposed answer (the reviews' recommendation) | Answer |
|---|---|---|---|
| Q1 | Parity on Windows: gate the bit-exact tests to Linux, switch the kernels to `libm`, or keep a second recording? | `libm` for the native half, a Windows mode for the rest | Maintainer: **the native kernels' transcendentals move to `libm` `=0.2.16` (MIT)**, bit-identical on Linux and Windows; the moved fixtures are re-recorded once on Linux. The six live comparisons of native against GDScript (`test_flight_step`, `test_flight_batch`, `test_brain_parity` (two tests), `test_brain_think_parity`, `test_turret_kernel`'s aim check) get a tight ULP tolerance instead. The 12 fixture files that depend on Jolt or engine maths stay bit-exact on Linux and get a Windows mode (1 against 6 threads and threaded against delayed in one run, run to run, the existing tolerances); the 3 fixable ones (`capital_helm`, `ram_sweep_cull`, `body_registry`) get trig-free or stored inputs; a `maths_golden` cargo test checks the DLL's maths on Windows without Godot. The finding that Godot 4.7.2's Jolt is not built with `JPH_CROSS_PLATFORM_DETERMINISTIC` is recorded |
| Q2 | Rust toolchain for Windows | MSVC on the Windows runner, or MinGW cross-compiled on Linux | Maintainer: **MSVC** (`x86_64-pc-windows-msvc`) on the GitHub Windows runner, static C runtime (`+crt-static`) so players need no VC++ redistributable. No MinGW |
| Q3 | Packaging | Embedded pack as on Linux, or `.exe` + `.pck` + DLL | Maintainer: **a zip folder** with the game `.exe`, the console wrapper `.exe`, the `.pck` and `scs_native.dll` (pack not embedded); an icon and version info; no code signing |
| Q4 | How much runs on Windows CI per push | All six GUT shards with `GUT_SLOW=1`, or a subset with the full run less often | Maintainer: **every push** runs Python, Rust, the import, the fast GUT files, the Windows export and a smoke run; **the full GUT run** (`GUT_SLOW=1`) runs on the milestone branch on manual trigger (`workflow_dispatch`) or nightly. Linux CI unchanged |
| Q5 | Renderer policy | Pin Vulkan, or allow Godot's D3D12 fallback | Maintainer: **Forward+ on Vulkan by default**; the D3D12 fallback stays allowed but is never silent: `state render` and the log name the driver in use |
| Q6 | The (H) play-test machine | | Maintainer: **another PC with an NVIDIA RTX 3060** (not the RX 6950 XT reference machine); results are labelled with that machine; the (H) checks are the tutorial with the gamepad and with the keyboard |
| Q7 | Base branch | `m9` from `main` once M10 merges | Maintainer: **`m9` from `m10`** (`af5492c9`). **Revised 2026-11-27: `m9` rebased onto `main` (`02aeec99`), M10's work dropped; see the status line** |
| Q8 | Where the plan is committed | | Maintainer: on `m9`, not pushed |

## Decisions

Labelled D9.x until T11 (docs) carries them into `docs/architecture.md`.

- **D9.1 Assets are built once, on Linux.** The `assets` job builds `assets/generated/` as today and hands it to the Windows
  job as a CI artifact; the generator never runs on Windows. The asset cache key's `${{ runner.os }}`
  (`.github/workflows/ci.yml:75,109,187`) becomes the literal `Linux`, so no other OS ever looks up or fills its own asset
  cache (the key string on Linux is unchanged, so its cache keeps hitting).
- **D9.2 The Windows runner builds the Windows release.** It builds `scs_native.dll` with MSVC and exports with the Windows
  editor and the Windows templates; there is no cross-export from Linux.
- **D9.3 Windows is verified on CI.** No agent machine runs Windows, so a task's Windows half is proven on the runner; CI only
  runs after a push, which the maintainer does or authorises (`CLAUDE.md`: agents do not push).
- **D9.4 Linux does not change.** The Linux jobs, the "Linux release" preset (embedded pack) and `scripts/build_release.sh`'s
  Linux output stay as they are; per-OS code exists only where a path or a name differs, each behind one helper.
- **D9.5 Jolt is not cross-platform deterministic.** Godot 4.7.2's `modules/jolt_physics/SCsub` defines `JPH_ENABLE_ASSERTS`,
  `JPH_DEBUG_RENDERER` and `JPH_DOUBLE_PRECISION`, never `JPH_CROSS_PLATFORM_DETERMINISTIC`; the repo already claims only
  same-machine determinism (`docs/milestones/m4-performance-and-scale.md:1264`, architecture §17.9). A recording that passes
  through Jolt is therefore Linux-only bit-exact.

## Scope

- **Plumbing:** the `.gdextension`'s Windows entries, one per-OS library-name helper, `.gitignore`, reserved Windows file
  names refused as profile names.
- **Tools:** the Windows editor and templates pinned by hash; the DLL built with MSVC and a static CRT.
- **Parity:** `libm` in the kernels with a guard, `maths_golden`, the re-record on Linux; the Windows mode for the mixed tests.
- **Scripts:** the test and build scripts under Git Bash on the runner.
- **Release:** the "Windows release" preset and the zip folder; the renderer driver named in `state render` and the log.
- **CI:** a Windows job per Q4; the confirmation run.
- **Docs, the (H) play-test, the close-out.**

## Out of scope

- Generating assets on Windows (D9.1): the generator's CRLF writers (`core/panorama.py:158`, `core/manifest.py:328`,
  `assets/asteroids.py:314`) and its `/proc/meminfo` budget stay as they are.
- Linux-only tools: the bench, capture, sheet and VRAM scripts (`bench.sh`, `bench_quick.sh`, `capture*.sh`, `*_sheet.sh`,
  `scratch_project.sh`, ...). T11 marks them Linux only.
- Card-wide VRAM and the load average on Windows (`src/rendering/vram_reading.gd:10`, `src/perf/bench_report.gd:362,367,406`):
  they degrade cleanly ("total unknown"); documented, not ported.
- A Windows `performance_cores()` (`native/src/threads.rs:352`): on Windows it falls back to logical cores; results do not
  change (1 against 6 threads), only the default thread count. Documented, not ported.
- Code signing, an installer, Windows on ARM, macOS.

## Design: parity after the switch

The 22 fixture files under `tests/fixtures/parity/` (the portability review counts 23 `ParityFixture` users; T04 recounts)
fall into four classes:

| Class | Files | Linux | Windows |
|---|---|---|---|
| Exact everywhere already (no transcendental on the path) | `contact_field`, `sweep_cells`, `damage_rules_parity`, `bolt_sync`, `hit_broad_phase`, `hit_scale` | bit-exact, unchanged | bit-exact (`hit_scale`, `bolt_sync` rest on engine arithmetic under `/fp:strict`: T10 confirms) |
| Pure native, exact with `libm` | `pilot_kernels` | re-recorded (T04) | bit-exact |
| Native path exact, inputs built with engine trig | `capital_helm_parity`, `ram_sweep_cull`, `body_registry` | stored or trig-free inputs (T05) | bit-exact (`body_registry` makes a Jolt round trip: T10 confirms) |
| Jolt, GDScript gameplay or engine trig in the run | `bolt_rows`, `core_state`, `driver_step`, `row_commands`, `sim_core`, `turret_kernel`, `beam_landing_parity`, `brain_tolerance`, `flight_parity_fight`, `pilot_kernels_in_play`, `targeting_on_read`, `weapon_rows_battle` | bit-exact against the recording | Windows mode (T05): no recording read; 1 against 6 threads and threaded against delayed live in one run, two runs equal, the existing tolerances (hits within 10 to 20 %, behaviour mix within 5 points) and the structural counts |

Digests stay comparable across platforms once the bits are: `JSON.stringify(..., full_precision)` formats with Godot's own
`grisu2::to_chars`, and native digests are FNV-1a over `to_bits`. One switch decides the mode (`ParityFixture`, by
`OS.get_name()`); on Linux it can never take the Windows mode (a test holds that).

## Acceptance criteria

| # | Criterion | Kind | Done |
|---|---|---|---|
| AC1 | Windows CI per push: Python, Rust (with `maths_golden`), import, the fast GUT files, the Windows export and its smoke, all green on `m9` | A | |
| AC2 | Windows full run: the whole GUT suite with `GUT_SLOW=1` green once on the runner (manual trigger), its duration recorded | A | |
| AC3 | Release zip: the Windows export as a zip folder (game `.exe`, console `.exe`, `.pck`, `scs_native.dll`, icon and version info, no VC++ redistributable needed) runs the tutorial's opening headless on the runner, exit 0, no `ERROR:` line | A | |
| AC4 | Linux unchanged: the Linux CI jobs green, the Linux release built and smoked as at M8, its preset unchanged | A | |
| AC5 | Parity per Q1: the native maths never reach the C runtime (a guard test); `maths_golden` equal on Linux and Windows; the cross-platform classes bit-exact on both; the Linux-only class bit-exact on Linux and green in its Windows mode; the six live comparisons within their ULP tolerance | A | |
| AC6 | Cost of `libm`: `battle` 500 and 1 000 on the reference machine within 2 % (or the run-to-run noise) of the same commit without it; M4's line (median at most 8.0 ms, p99 at most 12.0 ms at 500; 7.42 ms and 9.22 ms after M4-T44) quoted beside the numbers | A | |
| AC7 | Renderer: `state render` names the driver (`vulkan` or `d3d12`) and the log warns when the fallback is in use (tests); Vulkan in use on the RTX 3060 PC | A | |
| AC8 | Docs: `CLAUDE.md`, `docs/architecture.md`, `docs/research-notes.md`, `docs/playtest.md` "M9 acceptance checklist", `docs/third-party.md`, `info.md` and the roadmap row as built | A | |
| AC9 | (H) On the RTX 3060 PC from the release zip: the tutorial start to finish with the gamepad and again with the keyboard; Vulkan in use; settings persist in `%APPDATA%`; no error in the log; fps noted | H | |

## Verified fine

The planning review found nothing to port here (details and evidence in `docs/research/m9-windows-review.md` §6; the parity
study behind Q1 is `docs/research/m9-parity-libm.md`):

- No per-OS branches in `src/`; `res://` and `user://` paths use `path_join` or `/`, and timestamps in file names strip `:`.
- No `res://` path whose case differs from the file on disk, no names differing only by case, no names illegal on Windows, no
  symlinks; the longest path is 59 characters.
- No CRLF files, and `.gitattributes` forces LF; the console tokenizer, the joypad mappings, JSON loading and `run_tests.sh`'s
  shard paths already tolerate `\r`.
- The native core has no `cfg(unix)`, `libc`, `std::os`, SIMD, `asm` or `build.rs`; threads are rayon and `std::thread`; the
  sysfs and `/proc` reads fall back quietly (the VRAM overlay shows "total unknown").
- 1 vs 6 threads and threaded vs delayed hold nothing platform-specific (no float reductions across threads; default-hasher maps
  are lookups only).
- Keyboard bindings use physical keys; `display_server/driver.linuxbsd` only affects Linux; `addons/scs_export` and the GLSL
  compute shaders are platform-neutral.
- Wall-clock limits in tests are reported on CI, not asserted, so a slower Windows runner does not fail them.

## Risks and open checks

Only a Windows machine settles these; T10 (confirm on the runner) or T12 (the play-test) records each answer.

- **CRLF in Godot's redirected output** on Windows, which every `expect_line` (`grep -qxF`) and the parse in
  `test_flight_parity_fight.gd:47` depend on (T06 strips `\r` either way).
- **A PE file without `.exe` under Git Bash** (`.tools/godot/godot`); T02 installs `godot.exe` so it does not matter.
- **`timeout` and the console wrapper:** killing the wrapper may leave the game running (`release_smoke.sh:14`).
- **The pad under SDL3 on Windows:** name, GUID vendor bytes, trigger rest values, the guide button (`PadLayout.detect`).
- **Vulkan or D3D12 on the RTX 3060**, and whether the D3D12 fallback needs files in the zip (the Agility SDK) to work at all.
- **GUT duration on the runner** (about 75 runner-minutes on Linux in six shards; Windows is usually slower: Defender, NTFS,
  process start) and the import of several GB of assets.
- **Engine arithmetic equality** for `hit_scale`, `bolt_sync` and `body_registry` (Godot builds with `/fp:strict` and
  `-ffp-contract=off`, `platform/windows/detect.py:408,739`, so they should match; unproven).
- **gdext 0.5.5 on MSVC** and the DLL's load in the editor and the export; a 5 s hang at quit from `Threads::drop`
  (`native/src/threads.rs:130-158`) would show in the smoke.
- **Nightly runs use `main`'s workflow and code:** GitHub schedules run on the default branch, so until M9 merges the full run on
  `m9` is the manual trigger.
- **M10 after M9:** new kernels on `m10` written with std trig will fail T04's guard once `m10` takes M9 from `main`, and fixtures
  re-recorded on `m10` collide with T04's re-record; `m10` resolves both when it merges `main` after M9.
- **The plan's counts were taken on `af5492c9` (M10):** T04's call-site list and the Design table name M10-only files
  (`capital_helm_parity`, `beam_landing_parity`, the capital, beam and mine kernels). T04 and T05 recount them on `main` first.

## Play-test results

None yet. Results from the RTX 3060 PC are labelled with that machine (Q6).

## Working rules for M9

- **Order.** The table's order is the priority. T01 to T08 are built and verified on Linux (Linux green, the Windows paths
  written and read through); what only Windows can prove is T10's to confirm, and a Windows failure found there is fixed in T10
  (or a new task added to the table), not by reopening an earlier row. T09 may start once T03 lands, so a first build-only run
  gives early feedback.
- **Windows needs a push (D9.3).** A task that needs the runner says so and stops for the maintainer to push `m9` or authorise a
  push. Doc-only commits skip CI (`ci.yml:9-14`).
- **Linux does not change (D9.4).** Every Linux script keeps its output and exit codes; a per-OS branch is one helper, tested on
  Linux.
- **Native changes** keep the parity recordings green on Linux; T04's re-record is the only one, with its README section. No
  GDScript fallback, no switch back to the C runtime's maths.
- **Merges (Q7, revised).** `m9` is based on `main`; no `m10` merges. M9 merges to `main` once accepted.
- **Models.** Sonnet for mechanical script and doc work; Opus for the `libm` and parity work (T04, T05), the CI job and the
  Windows diagnosis. High effort, never max.
- **One working copy** on branch `m9` in its worktree (`/media/bonnet/Code/space-combat-sim-m9`), no task branches; locks as
  `CLAUDE.md` and `scripts/godot_lock.sh` say, with `SCS_LOCK_LABEL=<task id>`.
- **Tests.** Each task runs the files it touched and its new tests; the standard suite runs on Linux once, in T13, and the full
  Windows run once, in T10.
- **Done notes** stay under ten lines; what a task learned about Windows goes into `docs/research-notes.md`.

## Task breakdown (ordered)

| Task | Title | Depends on | Model | Verified on | Done when | Status |
|---|---|---|---|---|---|---|
| T01 | Repo plumbing: the `.gdextension`'s Windows entries, `.gitignore`, one per-OS library-name helper, reserved Windows names refused as profile names | - | Sonnet | Linux | Linux green; no `libscs_native.so` literal outside the helper and its tests | in progress |
| T02 | Godot editor and export templates on Windows: the win64 editor pinned by SHA-256, the Windows templates kept, self-contained mode for exports | - | Sonnet | Linux (Windows in T09) | Linux release byte-identical in layout; hashes in `docs/research-notes.md` | in progress |
| T03 | The native DLL with MSVC: `+crt-static`, `build_native.sh` and `lib_tests.sh` on Windows, cargo tests | T01 | Sonnet | Linux (Windows in T09) | Linux build unchanged; the Windows path written per Q2 | in progress |
| T04 | `libm` in the native kernels, on Linux: the dependency, the call sites, the guard, `maths_golden`, the ULP tolerances, the re-record, the benchmark (Q1) | - | Opus | Linux | Suite green twice; AC6 numbers; README section | not started |
| T05 | Windows mode for the mixed parity tests: the 3 fixable files, the 12 Linux-exact ones, the Jolt finding (Q1, D9.5) | T04 | Opus | Linux (Windows in T10) | Linux bit-exact as before; the Windows mode runs on Linux by a test switch and passes | not started |
| T06 | The scripts under Git Bash: no `flock`, Python's name and venv, CRLF, the settings path, the `fork` test, the smoke's kill | T01 | Sonnet | Linux (Windows in T09) | Linux output and exit codes unchanged | in progress |
| T07 | Windows export preset and release zip: "Windows release" preset, `build_release.sh` Windows mode, the icon and version info, `release_smoke.sh` on Windows (Q3) | T02, T03, T06 | Sonnet | Linux (Windows in T09) | Linux preset unchanged; the Windows preset reviewed against Godot 4.7.2's options | in progress |
| T08 | Renderer driver reporting: `state render` names the driver, the log warns on the D3D12 fallback, the setting explicit (Q5) | - | Sonnet | Linux | Tests green; `info.md` current | in progress |
| T09 | Windows CI job: `shell: bash`, assets as an artifact, the MSVC build, the per-push subset and the full-run triggers, the zip as an artifact (Q4, D9.1) | T01 to T03, T06, T07 | Opus | Windows runner | AC1 green on a pushed `m9`; Linux jobs untouched | not started |
| T10 | Confirm on the Windows runner: `maths_golden`, the exact classes, the Windows mode, the full GUT run once | T04, T05, T09 | Opus | Windows runner | AC2, AC3, AC5; the open checks answered in `docs/research-notes.md` | not started |
| T11 | Docs: `CLAUDE.md`, architecture, research notes, the playtest checklist, third-party, `info.md` | T10 | Sonnet | - | AC8 except the roadmap row | not started |
| T12 | (H) Play-test on the RTX 3060 PC: the tutorial with the gamepad and the keyboard (Q6) | T10, T11 | maintainer | RTX 3060 PC | AC9 | not started |
| T13 | Close-out: the standard suite on Linux, the roadmap row, status lines, acceptance asked, the merge per Q7 | all | controller | Linux | AC4; the maintainer accepts | not started |

### M9-T01 Repo plumbing

- **`bin/scs_native.gdextension:9-10`** lists only `linux.*.x86_64`: add `windows.debug.x86_64` and `windows.release.x86_64` =
  `res://bin/scs_native.dll` (cargo names the DLL without a `lib` prefix). Without them no `Scs*` class registers on Windows and
  `NativeLib.refusal` stops the game.
- **`.gitignore:19`** ignores `/bin/*.so` only: add `/bin/*.dll` and `/bin/*.pdb`.
- **One library-name helper** for the scripts (for example `native_lib_name` in `scripts/lib_tests.sh`, `scs_native.dll` under
  `uname -s` `MINGW*`/`MSYS*`, else `libscs_native.so`), used by `scripts/build_native.sh:12,41`, `scripts/lib_tests.sh:46`,
  `scripts/build_release.sh:38` and `scripts/scratch_project.sh:63,76,89`. In GDScript the refusal (`src/perf/native_lib.gd:34`)
  names the file per `OS.get_name()`; `tests/unit/test_native_required.gd:22` asserts on that name.
- **Reserved names:** `ControlProfile.is_valid_name` (`src/input/control_profile.gd:78`) refuses `con`, `nul`, `aux`, `prn`,
  `com1` to `com9` and `lpt1` to `lpt9` on every OS (`controls save con` would write a device on Windows); a unit test.
- **Done when:** Linux green; no `libscs_native.so` literal left outside the helper, the refusal and their tests.

### M9-T02 Godot editor and templates on Windows

- **`scripts/setup_godot.sh:7,9,14,26,40`** pins only `Godot_v4.7.2-stable_linux.x86_64.zip`. On Windows it fetches
  `Godot_v4.7.2-stable_win64.exe.zip`, checks its SHA-256 (taken once and written into the script and
  `docs/research-notes.md`), and copies `Godot_v4.7.2-stable_win64_console.exe` to `.tools/godot/godot.exe` (no symlink, so Git
  Bash never runs a PE file without `.exe`). `GODOT` in `scripts/lib_tests.sh:5` and `build_release.sh` defaults per OS.
- **`scripts/setup_export_templates.sh:33`** keeps only the Linux templates: on Windows `KEEP` holds
  `windows_release_x86_64.exe`, `windows_debug_x86_64.exe` and their `_console.exe` wrappers. The same `.tpz` and its SHA-512
  cover them; no new archive hash.
- **`scripts/build_release.sh:24-27`** finds templates through `XDG_DATA_HOME`, which Godot ignores on Windows, and links them
  with `ln -sf`. Both OSes move to Godot's self-contained mode (`._sc_` beside the editor, templates under
  `editor_data/export_templates/4.7.2.stable/`, copied, not linked); the Linux export's output must not change.
- **Done when:** the Linux release builds and smokes as before; the Windows editor hash and template names in
  `docs/research-notes.md`. The Windows half runs in T09.

### M9-T03 The native DLL with MSVC

- **`native/.cargo/config.toml`** (new): `[target.x86_64-pc-windows-msvc] rustflags = ["-C", "target-feature=+crt-static"]`, so
  the DLL does not need `vcruntime140.dll`. Target-specific, so the Linux build's flags do not change. `rust-toolchain.toml` needs
  no `targets` entry (the runner builds natively).
- **`scripts/build_native.sh:41-46`:** cargo writes `release/scs_native.dll`; the `cp` then `mv -f` swap fails on Windows while
  any Godot has the DLL loaded (Windows locks mapped DLLs). On Windows the script checks for that and fails with a message naming
  the running Godot, instead of a half-written swap.
- **`scripts/lib_tests.sh`** runs `cargo test --release --lib` (`:82`) on Windows as on Linux; the Rust tests use no file system or
  Unix API (the review checked).
- **Done when:** the Linux build and its Rust tests unchanged; the Windows path written; T09's first run builds the DLL and
  `dumpbin /dependents` (or an equivalent) shows no VC++ runtime DLL.

### M9-T04 `libm` in the native kernels (Linux)

- **Dependency:** `libm = "=0.2.16"` in `native/Cargo.toml`, default features (no `unstable-intrinsics`, no
  `force-soft-floats`); `docs/third-party.md` row `| libm | 0.2.16 | MIT | Linked: the native kernels' transcendental maths, the
  same bits on every platform |`.
- **Call sites:** 97 calls on 82 production lines in 21 files (`v3.rs:184,188`, `kernels.rs:1259,1335`, `brain_maths.rs`,
  `brain_behaviours.rs`, the turret, intercept, grid, capital, beam, mine, tier, surface, ephemeris and radar kernels) become
  fully qualified `libm::` calls with no `use` line, so the engine-free guard's allow-lists do not change. Mind the six f32 sites
  (`libm::cosf`, `sinf`, `atan2f`: `v3.rs:184,188`, `weapon_kernels.rs:400,441,445`, `capital_brain/attitude.rs:143`) and
  `y.atan2(x)` becoming `libm::atan2(y, x)`. This also removes the build host's libm from LLVM's constant folding
  (`radar_kernel.rs:67-68`, `brain_behaviours.rs:2379,2566,3805,4050`).
- **Guard:** `test_the_native_maths_never_reach_the_c_runtime` beside `test_the_kernels_hold_no_engine_type` in
  `tests/unit/test_sim_core.gd`: every `res://native/src/**/*.rs` except `tests.rs` and `*/tests.rs`, comment lines skipped,
  refuses the std transcendental methods and their `f32::`/`f64::` path forms, `.mul_add(`, and the trig builtins of gdext and
  glam (`from_euler(`, `from_axis_angle(`, `.angle_to(`, `.signed_angle_to(`, `.slerp(`, `.rotated(`, `Quaternion`,
  `.get_euler(`). The free `v3::rotated(` passes. glam's `libm` feature is not needed while the guard holds.
- **`maths_golden`:** a cargo test with about 1 000 seeded inputs per function used, plus the constants the kernels pass,
  FNV-hashing the result bits against hashes recorded on Linux.
- **The six live comparisons** (`tests/unit/test_flight_step.gd`, its `TOLERATED`/`REL_TOL` hooks at `:15-17`;
  `tests/integration/test_flight_batch.gd:146-147`; `tests/unit/test_brain_parity.gd:145,327`;
  `tests/unit/test_brain_think_parity.gd`; `tests/unit/test_turret_kernel.gd:64-69`) get a tolerance in ULP on the fields
  downstream of a transcendental, measured and written in the test; everything else stays exact. A comparison that integrates
  over many ticks is compared per step from the same state rather than loosened, and the Done notes say so.
- **Re-record:** run the suite once and list the parity failures; add `ParityFixture.rerecorded` hooks where a moved entry is read
  with `stored` only (`test_pilot_kernels` 3, `test_pilot_kernels_in_play` 2, `test_sim_core`'s `flight_step_from_the_server`,
  `test_core_state` 2, `test_targeting_on_read` if it moves); re-record with `tests/fixtures/parity/README.md`'s command, its
  list extended; run the suite twice; a README section "M9-T04 re-recorded" with old and new counts, and the entries whose
  GDScript provenance ends (`pilot_kernels`, `capital_helm`, `beam_landing`, `pilot_kernels_in_play`, `core_state`'s old paths,
  `sim_core.flight_step_from_the_server`): native self-recordings from here on.
- **Docs:** architecture §17.9 (`docs/architecture.md:2464`) and the brains section say both paths call "the host's libm";
  restate them.
- **Benchmark (AC6):** `scripts/bench.sh` for `battle` 500 and 1 000 on the reference machine, on this commit with and without the
  switch (the M10 work on `m9` has moved the numbers since M4-T44's 7.42 ms and 9.22 ms, so those are quoted, not compared).
  The study's estimate is at most 0.15 ms a tick at 500.
- **Done when:** the guard and `maths_golden` green; the suite green twice on Linux; AC6's numbers in the Done notes.

### M9-T05 Windows mode for the mixed parity tests

- **The switch:** `ParityFixture` answers whether this platform reads the recordings bit for bit (`OS.get_name() == "Linux"`); an
  environment variable forces the Windows mode so it is exercised on Linux; a test holds that Linux without it is exact.
- **The 3 fixable files:** `test_capital_helm_parity` (`Basis(axis.normalized(), angle)` at `:67`, `Basis.from_euler` at `:110`),
  `test_ram_sweep_cull` (`Basis.from_euler` at `:17,85,87`) and `test_body_registry` (`Basis.from_euler` at `:34`). Stored
  inputs (the Linux-built bases written into the fixture) keep the recorded outputs and their provenance; trig-free inputs (rng
  quaternions, `Basis(Quaternion)`) where the recording is native anyway. Whichever is chosen, no output re-record beyond T04's.
- **The 12 Linux-exact files** (Design table): in the Windows mode each compares what it can live in one run (1 against 6
  threads, threaded against delayed, two equal runs) and keeps its existing tolerances and counts, never the Linux digest.
  `test_weapon_rows_battle` already has a 10 % tolerance and may need nothing. Slow files stay slow (`GUT_SLOW`).
- **Docs:** the classes in `tests/fixtures/parity/README.md`; D9.5 in `docs/research-notes.md`.
- **Done when:** Linux bit-exact as before; every file passes its Windows mode on Linux when forced.

### M9-T06 The scripts under Git Bash

- **Locks:** `scripts/godot_lock.sh` needs `flock`, `/proc` and `lslocks` (`:15,115,160`); the Windows CI job sets
  `SCS_NO_LOCK=1`, and the wrapper falls back to no lock when `flock` is missing.
- **Python:** `scripts/lib_tests.sh:34-38` and `scripts/gen_assets.sh` look for `.venv/bin/python` then `python3`; one helper
  tries `.venv/Scripts/python.exe`, `.venv/bin/python`, `python3`, `python`.
- **CRLF:** strip `\r` in `run_logged`, `console_run` and `main_run`'s logs (so `expect_line`, `lib_tests.sh:119`, keeps its
  exact match), in every `mapfile` and `$(...)` over Python output in `scripts/run_tests.sh` and the CI shard steps (only
  `test_paths`, `:53`, strips it today), and in `tests/integration/test_flight_parity_fight.gd:47` (`strip_edges` before the
  regex).
- **Settings path:** `SETTINGS_CFG` (`lib_tests.sh:89`) is built from `XDG_DATA_HOME`; on Windows use
  `${APPDATA}/Godot/app_userdata/space-combat-sim/settings.cfg`, or the smoke "`set` must not write settings.cfg" passes
  vacuously.
- **`fork`:** `tools/procgen/tests/test_parallel_build.py:65` skips its class unless `"fork"` is in
  `multiprocessing.get_all_start_methods()`.
- **Smoke:** `scripts/release_smoke.sh:14` kills the game process (`taskkill //F //IM space-combat-sim.exe`) after a timeout on
  Windows, since `timeout` stops only the console wrapper.
- **`performance_cores()`:** the logical-core fallback documented in `docs/architecture.md` §17 (no code).
- **Done when:** Linux output and exit codes unchanged; the Windows paths run in T09.

### M9-T07 Windows export preset and release zip

- **Preset** `preset.1` "Windows release" in `export_presets.cfg`, `platform="Windows Desktop"`: the Linux preset's include and
  exclude filters (with `reports/*`) plus `build/*`; `export_path="build/windows/space-combat-sim.exe"`; x86_64; `s3tc_bptc`;
  `embed_pck=false`; `debug/export_console_wrapper=1` (gives `space-combat-sim.console.exe`); `codesign/enable=false`;
  `application/modify_resources=true` with the icon and version info (product name, description, version from a new
  `application/config/version`, GPL-3.0 copyright). **Check:** whether Godot 4.7.2 edits the PE resources itself or still needs
  `rcedit` set in the editor settings; write the answer in `docs/research-notes.md`.
- **Icon:** the repo has none. An original icon generated by code (a `tools/procgen` item writing a multi-size `.ico` and a
  `.png`), no franchise logo; the maintainer sees it before it ships.
- **`scripts/build_release.sh`, Windows mode:** templates via T02's self-contained mode, `--export-release "Windows release"`,
  checks the four files, writes `build/windows/space-combat-sim-<version>-windows-x86_64.zip`; the Linux mode unchanged.
- **Smoke:** `scripts/release_smoke.sh build/windows/space-combat-sim.console.exe`: the tutorial's opening, exit 0, no `ERROR:`.
- **Check:** what the D3D12 fallback (Q5) needs in the zip, if anything; ship it only if the fallback cannot work without it.
- **Done when:** the Linux preset and release unchanged; the Windows preset complete; the zip and smoke run in T09.

### M9-T08 Renderer driver reporting

- **`src/rendering/render_status.gd:25-28`** reports only the rendering method: add `render.driver`
  (`RenderingServer.get_current_rendering_driver_name()`) to the whitelisted provider, with its doc string.
- **The log:** at start, one line naming the method and the driver, and a warning when the driver is not the one configured
  (Vulkan configured, D3D12 in use). A pure function decides the warning, unit-tested.
- **`project.godot`:** `rendering/rendering_device/driver.windows="vulkan"` and `rendering/rendering_device/fallback_to_d3d12=true`
  written explicitly.
- **Done when:** tests green on Linux (`render.driver = vulkan`); `info.md` current if `state render`'s listing changes.

### M9-T09 Windows CI job

- **Job** `windows` in `.github/workflows/ci.yml`, `runs-on: windows-2025` (pinned), `defaults: run: shell: bash`,
  `SCS_NO_LOCK=1`, the MSVC toolchain, caches for the Godot editor, the templates and cargo keyed on `runner.os`.
- **Assets (D9.1):** the `assets` job uploads `assets/generated/` as an artifact (from its cache on a hit) and the Windows job
  downloads it; the asset cache key's `runner.os` becomes `Linux`. If the artifact's transfer costs too much, a fixed key with
  `enableCrossOsArchive: true` on both sides is the fallback.
- **Per push (Q4):** `tests/quick_python.txt`'s Python tests (the whole-asset builds need the Linux job's 12 GB budget and are
  not run on Windows), `cargo test` with `maths_golden`, the import, `run_tests.sh --quick`'s GUT files, the Windows export and
  its smoke; the zip uploaded as an artifact.
- **Full run (Q4):** on `workflow_dispatch` and a nightly `schedule`, the GUT suite with `GUT_SLOW=1`, sharded like Linux.
- **Linux jobs** unchanged but for the key literal and the artifact upload.
- **Needs a push (D9.3).** **Done when:** AC1 on a pushed `m9`; one full run started.

### M9-T10 Confirm on the Windows runner

- `maths_golden` equal to Linux; the exact classes (Design) bit-exact; the 12 green in their Windows mode; the six live comparisons
  within tolerance; the full GUT run green once (AC2) with its duration; the zip's smoke (AC3).
- Answer each open check above that the runner can (CRLF, `.exe`, `timeout`, gdext on MSVC, the quit, `hit_scale`, `bolt_sync`,
  `body_registry`, `JSON.stringify`'s text against Linux's) in `docs/research-notes.md`; what differed, and why.
- A Windows failure is fixed here (or as a new task in the table), never by loosening a Linux check.
- **Needs a push (D9.3).** **Done when:** AC2, AC3, AC5.

### M9-T11 Docs

- **`CLAUDE.md`:** the platform line ("Linux x86_64 + Vulkan ... Windows ... not planned"), the Windows commands, the GPU-check
  and `/tmp/x.png` examples marked Linux.
- **`docs/architecture.md`:** D13 (`:44`, "Linux x86_64 + Vulkan is the only target"), §17.5 (the library name), §21.6 (the
  release build), the baseline-x86-64 maths line, D9.1 to D9.5.
- **`docs/research-notes.md`:** the Windows editor hash, the template names, the runner's answers (T10), D9.5.
- **`docs/playtest.md`:** "M9 acceptance checklist" with a Windows section (the zip, `%APPDATA%`, `platform:Windows` lines in
  `user://gamecontrollerdb.txt`, `user://` screenshot paths, the driver in `state render`); the Linux-only tools marked.
- **`docs/third-party.md`:** `libm` (T04), the Windows templates (`:45` says Linux only). **`info.md`:** `state render`.
- **Done when:** AC8 but the roadmap row (T13).

### M9-T12 (H) Play-test on the RTX 3060 PC

- **The maintainer**, from the release zip of a green run: the tutorial start to finish with the gamepad, then with the keyboard;
  `state render` shows `forward_plus` and `vulkan`; a changed setting survives a restart (`%APPDATA%\Godot\app_userdata\
  space-combat-sim\settings.cfg`); no `ERROR:` in the log; fps noted. Results labelled "RTX 3060 PC" in "Play-test results".
- **Done when:** AC9.

### M9-T13 Close-out

- **Steps:** the standard suite on Linux once (AC4) and the Linux release built and smoked; the roadmap row as built; this file's
  status line and every row; acceptance asked of the maintainer; then, per Q7 (revised), `m9` merges to `main`.
- **Done when:** AC4; the maintainer accepts.
