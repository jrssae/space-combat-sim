# Windows portability review (M9 "Windows build")

Snapshot: `m10` at `af5492c9` (2026-11-25), reviewed read-only for the M9 plan (`docs/milestones/m9-windows-build.md`). Some line
numbers here were corrected in the milestone file (`build_native.sh`, `setup_export_templates.sh`); trust the milestone file's citations.
The questions in §8 were answered as M9's Q1 to Q8.
Severity: **blocker** (Windows cannot build/run/pass until fixed), **likely-bug** (probably breaks or silently weakens a check),
**check** (needs verifying on Windows), **doc-only**.

## 0. Current setup (facts)

- **Native core:** `native/` is one crate `scs_native`, `crate-type = ["cdylib"]`, edition 2024, `godot = "=0.5.5"` with
  feature `api-4-7` (prebuilt bindings, so no bindgen/LLVM), `rayon = "=1.12.0"`. Toolchain pinned to Rust `1.99.1`
  (`rust-toolchain.toml`, profile minimal, no `targets` list). `[profile.release] codegen-units = 1`; no `build.rs`, no
  `.cargo/config.toml`, no `target-cpu`/`target-feature` flags anywhere (baseline x86-64).
- **`bin/scs_native.gdextension`:** entry `gdext_rust_init`, `compatibility_minimum = 4.7`, `reloadable = false`; libraries
  list only `linux.debug.x86_64` and `linux.release.x86_64` = `res://bin/libscs_native.so`. `bin/` holds only the
  `.gdextension` and its `.uid`; `.gitignore` ignores `/bin/*.so` only.
- **CI (`.github/workflows/ci.yml`, workflow "CI"):** three jobs, all `ubuntu-latest`:
  `assets` ("generated assets": plans shards, fills the `assets-${runner.os}-py3.12-<hash of tools/procgen>` cache),
  `python` ("python tests (shard k)", matrix from `scripts/python_shards.py`),
  `test` ("test (GUT shard k of n)": Godot cached on `godot-${runner.os}-<ver>`, cargo cached on
  `native-${runner.os}-<Cargo.lock+toolchain>`, `scripts/build_native.sh`, `scripts/run_tests.sh` with `PYTHON_TESTS=0`,
  `GUT_SHARD=k/n`, `GUT_SLOW=1`; shard 1 also runs the Rust tests and the console smokes). Env `PROCGEN_MEM_MB=12000`.
  No release/export job exists: CI never builds an export today. `SCS_NO_LOCK` is not set in CI (locks run via `flock`).
- **`export_presets.cfg`:** one preset, `preset.0` "Linux release", platform `Linux`, `export_filter="all_resources"`,
  `include_filter="*.json,*.f32,*.txt,*.cfg,*.obj,*.mtl"`, `exclude_filter="reports/*, tests/*, docs/*, tools/*, scripts/*,
  addons/gut/*, references/*, native/*, .tools/*, *.md"`, `export_path="build/release/space-combat-sim.x86_64"`,
  `script_export_mode=2`, `embed_pck=true`, `s3tc_bptc=true`, `etc2_astc=false`, `export_console_wrapper=1`, arch x86_64.
- **Linux release (M8-T15):** `scripts/build_release.sh` → `setup_export_templates.sh` (1.28 GB `.tpz`, **SHA-512**, keeps
  only `linux_release.x86_64`/`linux_debug.x86_64` in `.tools/godot/templates/`), symlinks them under
  `XDG_DATA_HOME=.tools/xdg/godot/export_templates/4.7.2.stable/`, then `build_native.sh`, `gen_assets.sh`, `--import`,
  `--export-release "Linux release" build/release/space-combat-sim.x86_64`, checks the binary and `libscs_native.so` exist,
  then `scripts/release_smoke.sh`: `timeout 300 <bin> --headless -- --console-strict --console-exec="wait 60; play tutorial;
  wait 600; state ship; quit"`, fails on non-zero exit or any `ERROR:` line. Run by hand, not in CI (15 min, mostly assets).
  At M8 the binary with embedded pack was 1.7 GB plus a 7 MB `.so`.
- **Godot editor pin:** `scripts/setup_godot.sh` downloads `Godot_v4.7.2-stable_linux.x86_64.zip`, SHA-256
  `cadd3204...29e4`, symlinks `.tools/godot/godot`.
- **Project settings:** no `[rendering]` section (renderer and RD driver are Godot defaults: Forward+, Vulkan on Windows with
  Godot's D3D12 fallback setting at its default), `display_server/driver.linuxbsd="wayland"` (Linux only), Jolt physics,
  `config/name="space-combat-sim"` (so `user://` on Windows is `%APPDATA%\Godot\app_userdata\space-combat-sim`).
  GUT 9.7.1 vendored.

## 1. Blockers

| # | Where | What breaks on Windows | Fix |
|---|---|---|---|
| B1 | `bin/scs_native.gdextension:9-10` | Only Linux entries: on Windows Godot finds no library for `windows.x86_64`, no `Scs*` class registers, `NativeLib.refusal` and `Main` refuse to start; every GUT test that touches the core fails. | Add `windows.debug.x86_64 = "res://bin/scs_native.dll"` and `windows.release.x86_64 = "res://bin/scs_native.dll"` (cargo names it `scs_native.dll`, no `lib` prefix, on both msvc and gnu). |
| B2 | `scripts/build_native.sh:119,148-153` | Hard-codes `libscs_native.so` for both the cargo output and `bin/`; on Windows cargo writes `release/scs_native.dll` (cross-compile: `<target>/release/scs_native.dll`), so the script fails "cargo did not produce". The `cp`+`mv -f` swap also fails on Windows while any Godot has the DLL loaded (Windows locks mapped DLLs). | Pick name/extension per OS (`uname -s` MINGW*/MSYS* → `scs_native.dll`) and an optional `--target`; on Windows just fail clearly if the DLL is locked. |
| B3 | `scripts/lib_tests.sh:46` and `scripts/build_release.sh:38` | Both assert `bin/libscs_native.so` / `${OUT}/libscs_native.so` exist. | Same per-OS library name helper (one place, e.g. `lib_tests.sh` exports `NATIVE_LIB`). |
| B4 | `scripts/setup_godot.sh:7-14,26,40` | Downloads and pins only the Linux editor; `BIN` is the Linux binary; the "link" is `ln -sfn` to a file without `.exe`. | Per-OS branch: `Godot_v4.7.2-stable_win64.exe.zip` with its own SHA-256 (record in `docs/research-notes.md`), extract, use `Godot_v4.7.2-stable_win64_console.exe` as `.tools/godot/godot.exe` (copy, not symlink). Make `GODOT` in `lib_tests.sh:5` / `build_release.sh:10` / the CI version step OS-aware or rely on `GODOT_BIN`. |
| B5 | `scripts/setup_export_templates.sh:75,101-106` | Extracts only `linux_release.x86_64`/`linux_debug.x86_64`. | Add `windows_release_x86_64.exe`, `windows_debug_x86_64.exe` (and the `*_console.exe` wrappers) to `KEEP` per target; the same `.tpz` and its SHA-512 cover them, so no new archive hash is needed. Cache the extracted templates in CI instead of downloading 1.28 GB per run. |
| B6 | `scripts/build_release.sh:24-28` | Templates are found through `XDG_DATA_HOME`, which Godot ignores on Windows (it uses `%APPDATA%\Godot\export_templates\4.7.2.stable\`). Also `ln -sf` (MSYS copies or fails). | Use Godot's self-contained mode on both OSes (`._sc_` next to the editor → `editor_data/export_templates/`) or set `custom_template/release`/`debug` in the preset at export time; copy instead of symlink. |
| B7 | `export_presets.cfg` | No Windows preset. | Add `preset.1` "Windows release", `platform="Windows Desktop"`, same include/exclude filters (add `build/*`), `export_path="build/windows/space-combat-sim.exe"`, `binary_format/architecture="x86_64"`, `texture_format/s3tc_bptc=true`, `debug/export_console_wrapper=1` (gives `space-combat-sim.console.exe` for the smoke), `codesign/enable=false`, `application/modify_resources=false` (no rcedit; icon/version metadata later), D3D12 Agility SDK export only if D3D12 fallback is to be shipped, `binary_format/embed_pck` = see Q4. |
| B8 | `scripts/godot_lock.sh:21-24,38,174,191-205` (used by every Godot call in `run_tests.sh`/`lib_tests.sh`) | Needs `flock` (not shipped with Git for Windows' bash), `/tmp` lock files, `/proc/<pid>/cmdline`, `lslocks`. Every test/smoke run fails at the lock. | Set `SCS_NO_LOCK=1` in the Windows CI job (the bypass at line 115 already `exec`s the command); also have the wrapper fall back to no-lock when `flock` is missing. |
| B9 | `tools/procgen/tests/test_parallel_build.py:65` | `multiprocessing.get_context("fork")` raises `ValueError` on Windows (no fork). | `@unittest.skipUnless("fork" in multiprocessing.get_all_start_methods(), ...)` on that class, or run the Python suite on Linux only. |
| B10 | `.github/workflows/ci.yml:75,109,187` | The assets cache key includes `runner.os`, so a Windows job looks up `assets-Windows-...` and misses the Linux-built assets; `actions/cache` also refuses cross-OS restores unless `enableCrossOsArchive: true` is set on both save and restore. A miss means generating ~GBs of assets on Windows (`gen_assets.sh`, which then hits the issues in §4). | Hand assets to Windows with `actions/upload-artifact`/`download-artifact` from the `assets` job, or a fixed `assets-Linux-...` key with `enableCrossOsArchive: true` on both sides. |
| B11 | `.github/workflows/ci.yml` | No Windows job; GitHub Windows runners default to `pwsh`, and every script is bash. | New job `runs-on: windows-latest` (or a pinned `windows-2025`), `defaults: run: shell: bash`, `SCS_NO_LOCK=1`, MSVC or GNU Rust target (Q1), Godot Windows editor cache, templates cache, assets from Linux, `run_tests.sh` (sharded or a subset, Q5), export + smoke. |

## 2. Likely bugs, by area

### 2.1 Native core (Rust)

| Where | What differs | Severity | Fix |
|---|---|---|---|
| Float determinism, `native/src/**` (31 `sin`, 31 `cos`, 12 `sin_cos`, 14 `atan2`, 12 `acos`, 6 `asin`, 6 `tan`, 5 `atan`, 14 `hypot`, 2 `exp`, 2 `ln`, 2 `powf`; 107 `sqrt`, 2 `powi`) against `tests/fixtures/parity/*.json` | Rust's `f32/f64::sin` etc. call the platform libm: glibc on Linux, the UCRT (msvc target) or mingw-w64/msvcrt (gnu target) on Windows. These differ in the last ulp for some inputs; `sqrt` (IEEE, exact) and `powi` (compiler-rt) do not. The Godot side has the same issue: GDScript `sin`/`cos`, Basis/Quaternion maths in the engine and gdext's builtin maths all go through the C runtime, and the official Windows templates are built with a different compiler and CRT. The fixtures are **bit-for-bit** (`ParityFixture`, header line 13) and the big ones are **SHA-256 digests of whole seeded battles** (`ParityFixture.digest`, line 85), so one flipped bit in a chaotic fight changes every later tick. Expect `test_core_state`, `test_driver_step`, `test_row_commands`, `test_bolt_rows`, `test_weapon_rows_battle`, `test_brain_tolerance`, `test_flight_parity_fight`, `test_turret_kernel` and the other 23 `ParityFixture` users to fail on Windows even when the code is right. Same-process comparisons (1 vs 6 threads, threaded vs `delayed`) stay valid. | likely-bug (cannot confirm without Windows) | Q2. Options: (a) gate the digest/bit-exact cases to the platform that recorded them (a `ParityFixture.exact_platform()` like `WallClockBudget.on_ci()`), keep counts/tolerances and 1-vs-6 on Windows; (b) switch the kernels to the pure-Rust `libm` crate (bit-identical everywhere for the native half, needs a re-record on Linux and does not fix the engine half); (c) record a second Windows set (doubles the fixtures' upkeep). |
| `ParityFixture.digest` → `JSON.stringify(..., full_precision)` | If Godot's Windows build formats doubles differently (exponent digits, shortest-repr), every digest changes even with identical numbers. Godot has MinGW-specific exponent handling, so probably fine. | check | Run one digest test on Windows first and compare the stringified text, not just the hash. |
| `native/src/threads.rs:352-371` `performance_cores()` | Reads `/sys/devices/cpu_core/cpus`, `/sys/devices/system/cpu/online` and `.../topology/core_id`; on Windows all fail, so it returns `available_parallelism()` = **logical** CPUs (SMT threads counted, about twice Linux's physical count). `perf_threads = 0` then runs about twice the threads. Results stay identical (1 vs 6 rule), but speed and bench numbers differ between platforms. Note that a process using more than 64 logical CPUs on Windows sees only its own processor group. | likely-bug (perf only) | `#[cfg(windows)]` branch using `GetLogicalProcessorInformationEx` (`RelationProcessorCore`, `EfficiencyClass` for P-cores) via `windows-sys`, or halve when SMT is detected; record it in `docs/third-party.md` if a crate is added. |
| CRT dependency of an MSVC-built DLL | `x86_64-pc-windows-msvc` links `vcruntime140.dll` dynamically by default. Godot's templates do not need the VC++ redistributable, so a player without it gets "cannot load scs_native.dll" and the refusal screen. | likely-bug (msvc only) | Build with `-C target-feature=+crt-static` (a `native/.cargo/config.toml` `[target.x86_64-pc-windows-msvc] rustflags`), or use the GNU target. |
| `rust-toolchain.toml` | No `targets`; cross-compiling from Linux needs `x86_64-pc-windows-gnu` (plus `mingw-w64` on the runner). | check | Add `targets = ["x86_64-pc-windows-gnu"]` (or `-msvc`) once Q1 is settled. |
| `native/src/threads.rs:130-158` `Threads::drop` waits on worker exit | If a `Threads` were dropped during DLL unload (`DLL_PROCESS_DETACH`), Windows has already stopped the other threads, so the wait spins to `JOIN_TIMEOUT` (5 s) and prints. Today the pools are owned by Godot objects freed before exit, and there are no statics, so it should not happen. | check | Watch the Windows smoke for a 5 s hang at quit or the "worker(s) still running" line. |
| gdext 0.5.5 on Windows | gdext supports both Windows toolchains; `api-4-7` prebuilt bindings need no clang. Not verified for this crate. | check | First Windows CI run. |

### 2.2 Build scripts and CI

| Where | What breaks | Severity | Fix |
|---|---|---|---|
| `scripts/lib_tests.sh:34-40`, `scripts/gen_assets.sh:12,16,26`, `scripts/build_release.sh:17` | Call `python3` and look for `.venv/bin/python`. On Windows, `setup-python` provides `python`; a bare `python3` may be missing or hit the Microsoft Store stub; a venv has `.venv/Scripts/python.exe`. | likely-bug | One `python_bin` helper trying `.venv/Scripts/python.exe`, `.venv/bin/python`, `python3`, `python`; use it in `gen_assets.sh` too. |
| `scripts/run_tests.sh:69,74,97,120-123` and CI `ci.yml:118` | `mapfile`/`$(...)` over Python output: Python on Windows prints `\r\n`, so each module or `res://` path ends with `\r` (GUT's `-gtest=` gets `...gd\r`, unittest gets `test_x\r`). `test_paths` already strips `\r`; the shard calls do not. | likely-bug | Pipe through `tr -d '\r'` (or set `PYTHONIOENCODING`/`newline` in the shard scripts' `print`). |
| `scripts/lib_tests.sh:117-125` `expect_line` (`grep -qxF`) and every `expect_*` in `run_tests.sh` | Godot on Windows writes its log in text mode, so redirected output likely has `\r\n` line ends; `grep -x` exact-line matches then all fail. | likely-bug (verify) | Strip `\r` in `run_logged`/`console_run`/`main_run` (`… 2>&1 | tr -d '\r' > log`). |
| `tests/integration/test_flight_parity_fight.gd:44-50` (regex `^\[console\] (\w+\.\w+) = (.*)$` over `OS.execute` output split on `\n`) | Same CRLF risk: captured values end in `\r`, so string compares with fixtures fail. | likely-bug (verify) | `line.strip_edges()` before matching (cheap, harmless on Linux). |
| `scripts/lib_tests.sh:89` `SETTINGS_CFG` | Built from `XDG_DATA_HOME`/`~/.local/share`; on Windows the real file is under `%APPDATA%\Godot\app_userdata\...`, so the fingerprint is always "absent" before and after and the "`set` must not write settings.cfg" smoke passes vacuously. | likely-bug (silent) | Ask Godot (`--headless --console-exec` printing `OS.get_user_data_dir()`), or use `${APPDATA}/Godot/app_userdata/space-combat-sim` on MINGW. |
| `scripts/release_smoke.sh:50,52,56` | Default binary is `build/release/space-combat-sim.x86_64`; `timeout` kills only the console wrapper, which can leave the real `.exe` running. | likely-bug | Take the binary as argument (already supported); on Windows pass `space-combat-sim.console.exe`; after a timeout `taskkill //F //IM space-combat-sim.exe`. |
| `.gitignore:19` | Ignores `/bin/*.so` only; a Windows build leaves `bin/scs_native.dll` (and `.pdb`, `.lib`, `.exp` if copied) as untracked files someone may commit. | likely-bug | Add `/bin/*.dll`, `/bin/*.pdb`, `/bin/*.dylib`. |
| `scripts/gen_assets.sh:22` `nproc` | Exists in Git Bash; fine. Memory budget comes from `/proc/meminfo` (`tools/procgen/__main__.py:137`), absent on Windows → no limit unless `PROCGEN_MEM_MB` is set (CI sets it). | check | Only matters if assets are generated on Windows (they should not be). |
| `scripts/setup_godot.sh:37-38`, `setup_export_templates.sh:100-102` | `sha256sum`, `sha512sum`, `unzip`, `curl`, `mktemp` all exist in Git Bash on GitHub runners. | check | Confirm on the runner image; keep. |
| `export_presets.cfg:10` | `exclude_filter` lacks `build/*` and `.github/*`; harmless today (no resources there) but the Windows preset should exclude `build/*` so an earlier export is never scanned. | check | Add `build/*` to both presets; consider a `build/.gdignore`. |
| Embedded pack size (`embed_pck=true`, 1.7 GB at M8, bigger after M10's ships) | A Windows `.exe` with a near-2 GB+ appended pack is close to PE/tooling limits, is rescanned by Defender on every launch, and cannot be code-signed later without care. | check | Q4: prefer `embed_pck=false` on Windows (`.exe` + `.pck` + `scs_native.dll`), keep Linux as is. |
| Bench/visual scripts (`bench.sh`, `bench_quick.sh`, `measure_m3.sh`: `/proc`, `taskset`; `capture*.sh`: `xvfb-run`, llvmpipe; `*_sheet.sh`, `flicker_probe.sh`, `interior_sheet.sh`: `DISPLAY`, `/sys` VRAM; `scratch_project.sh`: symlinks, reflinks; `hull_sheet.sh`: `flock`) | Linux-only tooling. Not needed for Windows CI. | doc-only | Say "Linux only" in their headers / `docs/playtest.md`; no port needed for M9. |

### 2.3 GDScript

| Where | What differs | Severity | Fix |
|---|---|---|---|
| `src/perf/native_lib.gd:34` and `tests/unit/test_native_required.gd:22` | The refusal names `bin/libscs_native.so`; on Windows the file is `scs_native.dll`. The test stays green on Windows, but the message is wrong there. | likely-bug (message) | Name the library per `OS.get_name()` (or name the `.gdextension` file instead), and assert on that in the test. |
| `src/rendering/vram_reading.gd:10` (`/sys/class/drm`), `src/perf/bench_report.gd:362,367,406` (`/proc/self/status`, `/proc/loadavg`) | Degrade cleanly (`dir_exists_absolute` / null checks): the overlay reads `VRAM  GAME x GB   total unknown`; bench reports have empty `cpus_allowed` and `load_average`. No errors. | check (feature gap) | Accept for M9; document that card-wide VRAM and load average are Linux only. |
| `src/rendering/render_status.gd:28,45` (`state render`) | Reports only the rendering method (`forward_plus`), not the driver; with Godot's D3D12 fallback a Windows machine whose Vulkan fails runs D3D12 silently and the check "Forward+ on Vulkan" cannot be read. | likely-bug (observability) | Add `render.driver` = `RenderingServer.get_current_rendering_driver_name()` to the provider and to the H checklist; consider pinning `rendering/rendering_device/driver.windows="vulkan"` and deciding Q6 on the fallback. |
| `src/input/control_profile.gd:78` (names: lowercase letters, digits, `_`, 1-32) | Allows `con`, `nul`, `aux`, `prn`, `com1`..`com9`, `lpt1`..`lpt9`; `controls save con` writes `user://controls/con.cfg`, a reserved device name on Windows (fails or writes to the device). | likely-bug (minor) | Reject the reserved device names in `is_valid_name`. |
| `user://gamecontrollerdb.txt` (`src/autoload/settings.gd:229-238`) | Parsing is CRLF-safe (`strip_edges`), but SDL mapping lines carry `platform:Linux`; a Linux user's file does nothing on Windows. | doc-only | Say in `docs/playtest.md` that Windows needs `platform:Windows` lines. |
| `src/autoload/debug_console.gd:651-668` `screenshot [path]`; CLAUDE.md/`docs/playtest.md` examples use `/tmp/x.png` | `/tmp/x.png` on Windows resolves to `\tmp\x.png` on the current drive, which usually does not exist; the default `user://screenshots/` (colons already replaced) is fine. | doc-only | Use `user://` paths in the Windows docs. |
| `scripts/measure_fight_node.gd:448,465`, `scripts/*_sheet_node.gd` `SYSFS_VRAM`, `scripts/look_sheet_node.gd:20`, `scripts/livery_concepts_node.gd:22` (`/tmp`) | Linux-only measurement tools (`OS.execute("sh", ...)`, sysfs, `/tmp`). Not used by tests except `test_measure_exec.gd`, which only preloads the node and tests settings parsing. | doc-only | Leave; mark Linux only. |

### 2.4 Python procgen (only if run on Windows)

- `tools/procgen/__main__.py:137` `/proc/meminfo`: falls back to "no limit" (check).
- `core/panorama.py:158`, `core/manifest.py:328`, `assets/asteroids.py:314` write text without `newline="\n"`: on Windows
  they write CRLF, so those sidecars/manifests (and any hashes over them) differ from a Linux build (likely-bug only if
  generated on Windows). Other writers already pass `newline="\n"`.
- `multiprocessing` uses `spawn` on Windows; `__main__.py` has the `if __name__ == "__main__"` guard, so `--jobs` works.
- NumPy's SIMD transcendental kernels can differ by CPU and OS, so a Windows-generated asset is not guaranteed
  byte-identical anyway.
- **Feasibility of "built on Linux, packed":** yes. The `assets` job already builds `assets/generated` once. Either
  (a) the Linux job also exports the Windows build (Godot cross-exports with the Linux editor + Windows templates + a
  Windows-built or cross-compiled `scs_native.dll`), and the Windows job only runs it, or (b) the Windows job downloads
  `assets/generated` as an artifact and imports/exports itself (needed anyway if GUT runs on Windows, since the tests load
  the assets). The cache as configured cannot do it (B10).

## 3. Repo hygiene (checked)

- `.gitattributes`: `* text=auto eol=lf` plus explicit `eol=lf` for `.gd .gdshader .glsl .tscn .tres .godot .cfg .import
  .uid .py .sh .md .yml .yaml .json .toml .obj .mtl` and `binary` for `.glb .f32 .png .jpg .ogg .wav .ttf`. Because `eol`
  is set, Windows checkouts get LF even with GitHub runners' `core.autocrlf=true`; bash scripts keep working. Not listed
  but covered by `* text=auto eol=lf`: `.rs`, `.lock`, `.gdextension`, `.gdshaderinc`, `.svg`, `.txt`, `.cfg`. `.fnt`
  (GUT's font) is auto-detected binary. **Fine.** Suggest adding `*.fnt binary`, `*.dll/*.so/*.exe/*.pck binary`, and
  `*.ps1/*.bat/*.cmd text eol=crlf` if Windows scripts are ever added.
- No files in the tree contain `\r` (grep over 3 376 files).
- No two paths differ only by case; no names with `: * ? " < > | \`, trailing dots or spaces; no reserved device names;
  no symlinks; longest path 59 characters (`tests/integration/test_capital_subsystem_targeting.gd.uid`), far below 260
  even under `D:\a\space-combat-sim\space-combat-sim\`. `assets/generated/` and cargo's target paths were not in the
  snapshot (not measured; cargo's `build/<crate>-<hash>/out` paths are the usual long ones, still well under 260).
- Every `res://` string literal in `.gd/.tscn/.tres/.json/.cfg/.godot/.gdextension/.import/.py/.sh` was checked against
  the tree with exact case: **no case mismatches**. The 136 unresolved references are deliberate (missing-file tests,
  GUT's own fixtures, `.godot/imported/*` paths, `bin/libscs_native.so`, `assets/generated/*` not checked). Paths built
  at run time from ids (`path_join(hull_id)`) could not be checked statically; ids are lowercase by convention.

## 4. Tests

| Test / area | Windows behaviour | Severity |
|---|---|---|
| Parity tests (23 files using `ParityFixture`, digests and bit-exact values) | Likely fail on Windows (§2.1, libm). | likely-bug, Q2 |
| `test_parallel_build.py` (fork) | Errors on Windows. | blocker for the Python suite on Windows (B9) |
| `test_flight_parity_fight.gd`, `test_native_required.gd` (`OS.execute(OS.get_executable_path(), ...)`) | Work if `OS.execute` captures the child's stdout from the editor `.exe` (it creates pipes, so it should); CRLF in the captured text (above). | check / likely-bug |
| `test_core_threads.gd:41-48` (`performance_cores` vs `perf_threads = 0`) | Still passes (compares the core with itself). | fine |
| `test_bench_paths.gd:58,76-83` (`"/tmp/bench/x"` passed through; a dir under a file must fail with "Could not create directory") | `/tmp/...` is only a string here: fine. The second depends on Windows' `CreateDirectory` error path; Godot's message is the same core text. | check |
| `test_vram_reading.gd`, `test_vram_overlay.gd` | Use a fake DRM tree under `user://`: fine. | fine |
| `WallClockBudget` (`CI=true`) | GitHub sets `CI=true` on Windows too: timing budgets are recorded, not asserted. | fine |
| `GUT_SLOW` / `GUT_BALANCE` / `SCS_TEST_SETTINGS` | Plain env vars read with `OS.get_environment`: fine. | fine |
| `test_sim_core.gd:748` (`test_the_kernels_hold_no_engine_type`) and the other source-reading tests (`res://native/src/*.rs`, `info.md`) | Read LF files (gitattributes); they use `contains`, so CRLF would not matter anyway. | fine |
| Runtime: GUT is about 75 runner-minutes on Linux in six shards; Windows runners are usually slower (Defender, NTFS, process start). | Q5. | check |
| Rust `cargo test --release --lib` | No fs, no `/tmp`, no unix APIs in tests; timing only in a 40 ms injected sleep. Should pass; bit-exact Rust tests (`tier_fire/tests.rs:15,19`) compare two computations in the same process, so libm differences do not matter there. | fine |

## 5. Docs that say Linux only (doc-only)

- `docs/architecture.md:44` (D13 "Linux x86_64 + Vulkan is the only target ... No per-OS code is written"): amend for M9.
  Line 12 already says Windows from M9.
- `docs/architecture.md` §17.5 (`bin/scs_native.gdextension ... points Godot at bin/libscs_native.so`), §21.6 (the Linux
  release build), the "library is built for baseline x86-64 ... same maths on every machine" line (true per CPU, not per
  OS/libm: needs a note).
- `CLAUDE.md` lines 8 and 99 (GPU check via `/sys/class/drm/card1/...`; `/tmp/x.png` screenshot example), the
  "Commands" block (`.tools/godot/godot`).
- `docs/playtest.md:3,8` (requirements: Linux, `unzip`, `python3`), line 137 (VRAM total only on AMD/Linux), lines
  1496-1499 (release binary name).
- `docs/third-party.md:45` ("Godot export templates (Linux x86_64 release and debug only)").
- `docs/research-notes.md:12,72,156` (Linux editor hash; VRAM sysfs; templates): add the Windows editor zip SHA-256 and the
  template file names.
- `docs/roadmap.md:31` says the Windows template is "pinned and verified by SHA-256 like the Linux one"; the Linux
  templates are actually verified by the `.tpz`'s **SHA-512** (`setup_export_templates.sh:74`), and the same archive holds
  the Windows templates.
- `CONTRIBUTING.md` workflow assumes bash scripts; say "Git Bash on Windows".
- `scripts/setup_export_templates.sh:17` (`~/.local/share/godot/app_userdata/...` link step).

## 6. Verified fine

- No `OS.get_name()`/per-OS branches anywhere in `src/` (so no per-OS code to port, and nothing hides a Linux path).
- `user://` and `res://` paths are built with `path_join` or literal `/`, which Godot normalises on Windows; screenshot and
  bench label timestamps strip `:`.
- The console tokenizer treats `\r` as whitespace (`console_tokenizer.gd:108-109`), so a CRLF `autoexec.cfg` or
  `--console-file` works; joy mappings use `strip_edges`; `run_tests.sh` `test_paths` strips `\r`.
- JSON data loading (`JSON.parse_string`) is CRLF-tolerant.
- Keyboard bindings use `physical_keycode` (layout-independent on Windows); joypad bindings use Godot's SDL-style
  indices; `PadLayout.detect` falls back on names (`xinput`, `xbox 360`) when the GUID has no vendor ids.
- `display_server/driver.linuxbsd="wayland"` only affects Linux.
- `addons/scs_export` (adds the vendored lens flare GLSL to the pack) is platform-neutral.
- Runtime GLSL compute shaders compile through `RenderingDevice` (SPIR-V), which Godot also supports on D3D12 (check if
  the fallback is ever used).
- Native core: no `cfg(unix)`, no `libc`, no `std::os`, no SIMD/`target_feature`/`asm`, no `build.rs`, no file I/O
  besides the sysfs reads with a fallback, threads only via rayon/`std::thread` (portable), no large stack arrays,
  `Instant` only for timing readouts, randomness is Godot's PCG/murmur repeated in Rust (integer, portable).
- `scripts/gut_shards.py` builds `res://` paths with `as_posix()`.
- `tools/procgen/__main__.py` has the `__main__` guard needed by `spawn`.
- GUT 9.7.1 has no known Windows-only problems for headless `gut_cmdln.gd` runs.

## 7. Could not determine without a Windows machine

1. Whether the parity digests and bit-exact recordings hold on Windows (most likely not; see Q2).
2. Whether Godot's redirected stdout on Windows has `\r\n` line ends (affects every `expect_line` and the regex parse).
3. Whether Git Bash runs a PE file without `.exe` (`.tools/godot/godot`) and how `timeout` treats the console wrapper's
   child.
4. gdext 0.5.5 + this crate building on `x86_64-pc-windows-msvc` and `-gnu`; DLL load in the editor and the export.
5. The pad under SDL3 on Windows (name, GUID vendor bytes, trigger rest, guide button) (H).
6. Vulkan on the Windows test machine, whether Godot falls back to D3D12, and the compositor/compute effects on D3D12 (H).
7. Windows embedded-pack limits at the current pack size, and Defender scan cost at start-up.
8. Windows runner time for GUT and the import of the generated assets.
9. Windows high-DPI behaviour of the 1920×1080 window on a scaled desktop (H).

## 8. Questions for the maintainer

- **Q1** Rust target on Windows: MSVC on the Windows runner (`+crt-static`) or GNU cross-compiled on the Linux runner
  (`mingw-w64`)? It decides where the DLL is built, which CRT (and libm) it uses, and the toolchain file.
- **Q2** Parity fixtures on Windows: gate the bit-exact digests on the recording platform only (counts and 1-vs-6 still
  checked on Windows), move the kernels to the `libm` crate (re-record), or keep a second Windows recording?
- **Q3** Who exports: the Linux runner (cross-export, assets already there) or the Windows runner (download assets,
  import, export)? The roadmap says the Windows runner builds the export.
- **Q4** Windows packaging: embedded pack (as Linux) or `.exe` + `.pck` + DLL in a zip? Icon/version resources (rcedit)
  now or later? Code signing stays off (SmartScreen warning for testers)?
- **Q5** How much GUT on Windows per push: all shards with `GUT_SLOW=1` (doubles CI minutes), or `--quick` + the parity and
  thread tests + smokes, with the full set nightly or on the milestone branch?
- **Q6** Renderer policy: pin `driver.windows="vulkan"` and fail loudly, or allow Godot's D3D12 fallback (and export the
  Agility SDK)? Either way add the driver name to `state render`.
- **Q7** Which Windows machine and GPU will run the (H) play-test, so the H checklist can name it?
