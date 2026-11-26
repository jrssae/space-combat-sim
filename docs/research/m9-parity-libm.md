# Cross-platform parity: switching the native kernels to the `libm` crate

Read-only analysis of `m10` at `af5492c9` (2026-11-25) for the M9 plan (`docs/milestones/m9-windows-build.md`), behind its Q1. Paths
are relative to the repository root unless they start with `~` or `/`. The `libm` measurements came from a scratch Rust crate
(not kept) built with the repo's toolchain 1.99.1, comparing `libm` 0.2.16 against Rust std (glibc on Linux).

## Bottom line

- The switch does what it promises for the **native maths**: `libm` 0.2.16 is pure Rust (FreeBSD msun ports). Its x86_64
  `arch` code is only `sqrtss`/`sqrtsd` and a runtime-selected FMA, and both are correctly rounded, so a Linux .so and a
  Windows MSVC DLL get the same bits. It also removes a hidden hazard: LLVM constant-folds `f64::sin` and similar on
  constant inputs using the **build host's** C library (see 1.5).
- It is **not enough on its own**. Only **1 of the 22 fixture test files** (`test_pilot_kernels`) is pure native *and*
  touched by transcendentals, so the switch alone makes it cross-platform exact. **6 more** never touch a transcendental
  and are already cross-platform exact (with or without libm). The other **15** also depend on engine maths: the engine's C
  runtime `sin`/`cos`/`pow`/`exp` in GDScript and in `Basis(axis, angle)`/`from_euler`, Jolt, or GDScript gameplay. **3**
  of those 15 can be fixed cheaply by making their inputs trig-free or recording the inputs. **12** must stay bit-exact on
  Linux only.
- It **costs** something on Linux too. `libm` differs from glibc by 1 ULP on 1 % to 18 % of inputs, depending on the
  function (measured, 3.2). Every recording whose path reaches a transcendental moves and must be re-recorded. Several of
  those entries are still GDScript-provenance recordings, which cannot be taken again, so their "bit for bit with the
  GDScript" claim ends. **Six live GDScript-against-native bit-for-bit tests** (not fixtures) will fail on Linux after the
  switch. Their GDScript side still calls glibc through Godot's `Math::sin` → `std::sin`, so each needs a tolerance or a
  native maths bridge.
- Performance: roughly neutral per call (some functions faster, `exp` about +20 ns, `pow` about +170 ns). Estimated at
  ≤ 0.15 ms a tick at `battle` 500 (≤ 2 % of 7.42 ms), probably within noise. This still has to be measured.

---

## 1. Inventory of transcendental and C-runtime maths in `native/`

The crate is 103 `.rs` files, 49 195 lines. Dependencies (`native/Cargo.lock`): godot 0.5.5 (pulls glam 0.32.1), rayon
1.12.0, crossbeam, either, nanoserde (build only), libc. There is no `libm` today.

### 1.1 Totals

Production code, excluding `tests.rs` and `*/tests.rs`: **97 transcendental calls on 82 lines in 21 files**. With tests
it is 106 lines.

| function | prod calls | lowers to today (Linux / Windows MSVC) |
|---|---|---|
| `.cos()` | 17 | glibc `cos`/`cosf` / UCRT |
| `.sin()` | 16 | glibc / UCRT |
| `.atan2()` | 14 | glibc / UCRT |
| `.hypot()` | 12 | glibc `hypot` / UCRT `_hypot` |
| `.sin_cos()` | 9 | `sin` + `cos` (or `sincos`) |
| `.acos()` | 7 | C runtime |
| `.asin()` | 6 | C runtime |
| `.tan()` | 5 | C runtime |
| `.atan()` | 5 | C runtime |
| `.exp()` | 2 | C runtime |
| `.ln()` | 2 | C runtime `log` |
| `.powf()` | 2 | C runtime `pow` |

About 91 of the calls are f64 and **6 are f32** (`cosf`/`sinf`/`atan2f`): `v3.rs:184,188`, `weapon_kernels.rs:400,441,445`
and `capital_brain/attitude.rs:143`. These mirror the engine's 32-bit `Vector3.rotated`/`angle_to`.

### 1.2 By module (production call sites)

- **Vector helpers** `v3.rs:184,188` (`rotated`: f32 cos/sin). Called by `kernels.rs:2005` (pilot avoidance tie),
  `weapon_kernels.rs:395`, `capital_brain/attitude.rs:141,144` and `brain_behaviours.rs:2581,2585,4180`.
- **Flight kernel** `kernels.rs:1259` (`exp`, pod-yaw smoothing, `update_pod_yaw`) and `kernels.rs:1335` (`atan2`,
  `face_error_vector`). These run every tick for every flying ship.
- **Brain maths** `brain_maths.rs:180,191,237,279,301(acos+atan2),309,310,902`.
- **Behaviours** `brain_behaviours.rs:1714` (hypot), `2379, 2566, 3805, 4050` (cos of a constant), `3091-3092` (sin
  weave), `3154-3155` (tan), `3327, 3498, 4089` (atan), `4170` (atan2).
- **Turrets** `turret_kernels.rs:564,626(atan2+asin),631-632(sin_cos×2),707(acos),729(sin,tan),749-750`; `grid_kernels.rs:254`
  (asin); `intercept_kernels.rs:246-247,283,285,290,295-297`; `capital_gun_kernels.rs:736` (asin).
- **Weapons** `weapon_kernels.rs:400` (angle_to, atan2f), `441,445` (rotated, cosf/sinf).
- **Beams** `beam_kernels.rs:94,528,530,536,549`. **Mines** `mine_kernels.rs:640,644,646,647`, `mine_rows.rs:327` (config).
- **Capitals** `capital_helm.rs:120` (atan2), `capital_brain/attitude.rs:143` (atan2f),
  `capital_brain/targets.rs:64` (powf×2), `capital_brain_rows.rs:231` (config).
- **Low-attention tier** `tier.rs:444` (rotate_basis cos/sin per tier row per tick), `tier_fire.rs:94,153,154,159,194`
  (tan, acos, atan, tan, exp).
- **Surfaces** `surface.rs:97,107,118,146,178,195,220,789` (hypot).
- **Ephemeris** `ephemeris.rs:119,126-128` (sin_cos), `146` (Kepler: sin, cos).
- **Radar** `radar_kernel.rs:60` (ln×2), `67-68` (cos/sin of a const).

### 1.3 Exact everywhere (no change needed)

- `sqrt` (78 production calls) lowers to `sqrtss`/`sqrtsd`, which IEEE requires to be correctly rounded. `abs`, `min`, `max`,
  `clamp`, `signum`, `copysign`, `to_radians`/`to_degrees` (a multiply by a constant) and `as` casts are inline and exact.
- **`mul_add`/FMA: 0 uses** in `native/src` (grep). Rust never contracts `a*b+c` by itself, and with baseline x86-64 (no
  `+fma`, `Cargo.toml` comment line 20) an explicit `mul_add` would become a *libcall* to the C runtime's `fma`, so it
  should be forbidden or routed to `libm::fma` (which is correctly rounded on both paths).
- `floor` (14), `ceil` (2), `round` (2) and `rem_euclid`/`div_euclid` on floats (via `%`, which is `frem` → `fmod`). On
  baseline x86-64 without SSE4.1 these are **libcalls to the C runtime**, but each one has exactly one correct answer and
  both glibc and UCRT give it. They can be routed through `libm` for a "no C maths" rule; it is not needed for the bits.
- `powi`: `sweep_cells.rs:334` (`4.0.powi(level)`) is exact (a power of two), and `__powidf2` comes from Rust's own
  `compiler_builtins`.

### 1.4 Dependencies' own maths

- **godot-core 0.5.5 builtins** used in production (`mine_rows.rs:319` `.length()`/`.normalized()`,
  `damage_store/capital.rs:309` `distance_to`, `native_probe.rs:42` `distance_squared_to`, `dock_kernels.rs:236,310` `Basis
  * Basis`, `Basis::from_cols/from_rows`) are sqrt and mul/add only. See
  `~/.cargo/registry/src/*/godot-core-0.5.5/src/builtin/vectors/vector_macros.rs:453-456,742-744` and
  `matrices/basis.rs:570-601` (via glam `Mat3`, `glam-0.32.1/src/f32/mat3.rs:677-682`: no FMA).
- godot-core methods with trig exist (`Vector3::angle_to` uses `atan2`, `vector3.rs:197`; `math/float.rs:100` uses `sin_cos`;
  `Basis::from_euler` and `from_axis_angle`). They appear **only in Rust unit tests** (`kernels/tests.rs:169,430`,
  `capital_helm/tests.rs`, `surface/tests.rs`, ...). The guard should keep them out of production kernels.
- **glam 0.32.1** routes its maths to std unless its `libm` feature is on (`glam-0.32.1/src/f32/math.rs:35` vs `164`;
  `Cargo.toml:51`). That is not needed today, since nothing in production reaches glam trig. Adding `glam = { version =
  "=0.32.1", features = ["libm"] }` to `native/Cargo.toml` would unify it as a belt and braces.
- rayon, crossbeam and either do no float maths.

### 1.5 A hazard the switch removes

Several call sites take constants: `radar_kernel.rs:67-68` `TILT_RAD.cos()`, and `brain_behaviours.rs:2379,2566,3805,4050`
`deg_to_rad(CONST).cos()`. LLVM folds `llvm.cos` on constants using the **host compiler's** libm. A DLL built on the
Windows runner could therefore embed different constants from a Linux build even before run time. `libm` calls are plain
Rust and fold deterministically.

---

## 2. What the fixtures capture

There are 22 fixture files in `tests/fixtures/parity/` (plus a README) and 22 GUT files that read them through
`ParityFixture` (`tests/fixtures/parity_fixture.gd`). No Rust test reads them.

Engine facts that decide the classes (fetched from Godot `4.7.2-stable` sources):

- GDScript `sin`/`cos`/`atan2`/`exp`/`pow`, `Basis(axis, angle)` and `Basis.from_euler` call the platform C runtime
  (`core/math/math_funcs.h:120-125` `std::atan2`, `:213-215` `std::exp`). On Windows that is the template's CRT
  (MinGW-w64 or UCRT), not glibc.
- **Jolt is not built cross-platform deterministic.** `modules/jolt_physics/SCsub` defines only `JPH_ENABLE_ASSERTS`
  (dev), `JPH_DEBUG_RENDERER` (editor) and `JPH_DOUBLE_PRECISION`, never `JPH_CROSS_PLATFORM_DETERMINISTIC`. The repo
  already records only same-machine determinism (`docs/milestones/m4-performance-and-scale.md:1264`; architecture §17.9:
  "Jolt rounds the torque of a force at a point against the body's world position"). Nothing in `docs/research-notes.md`
  covers Windows or Jolt determinism.
- Godot compiles its own C++ with `/fp:strict` (MSVC) and `-ffp-contract=off` (MinGW) (`platform/windows/detect.py:408,
  739`). Plain engine arithmetic (Node3D transform composition, `normalized()`, `looking_at`) should therefore match
  across platforms, but this is not proven.
- `JSON.stringify(..., full_precision=true)` (used by `ParityFixture.digest`/`encode`) formats with Godot's own
  `grisu2::to_chars` (`core/io/json.cpp:98-104`, `core/string/ustring.cpp:1619-1626`), not `printf`. **Digests of text
  are platform-independent** once the bits are. Native digests (`sim_core.rs:813`, `Digest` FNV-1a over `to_bits`,
  `:2198-2212`) are too.

### 2.1 Classification (22 files)

**(a) Cross-platform exact already, unaffected by libm (6).** There is no transcendental on the recorded path and the
inputs come from `RandomNumberGenerator` (PCG plus `ldexp`, exact) with sqrt or plain engine arithmetic.
- `test_contact_field` (`contact_field.json`): scans filled by hand. Native contact queries are sqrt only.
- `test_sweep_cells` (`sweep_cells.json`): rng mids and reaches; `powi(4.0)` is exact.
- `test_damage_rules_parity` (`damage_rules.json`): AABBs, points and damage from rng; the damage store has no trig.
- `test_bolt_sync` (`bolt_sync.json`): Projectile nodes placed by rng and flown by hand (`test_bolt_sync.gd:38-58`).
- `test_hit_broad_phase` (`hit_broad_phase.json`): the recorded cases are rng only. The `exp`/`log` at
  `test_hit_broad_phase.gd:219` is in a non-fixture test.
- `test_hit_scale` (`hit_scale.json`): hand-stepped drones and bolts; `InterceptMath` has no trig. Verify on the runner,
  because the drones are RigidBody3D.

**(a′) Pure native, made cross-platform exact by libm (1).**
- `test_pilot_kernels` (`pilot_kernels.json`): rng inputs. The `ties` case goes through `v3::rotated` (f32 sin/cos,
  `kernels.rs:2005`), so it moves on Linux and must be re-recorded. It is a GDScript-provenance recording and is read with
  `stored` only, so a `rerecorded` hook has to be added.

**(b-in) Native path fine, inputs built with engine trig (3).** These can be fixed by building the inputs without trig
(rng quaternions, then `Basis(Quaternion)`, which is arithmetic only) or by storing the inputs in the fixture.
- `test_capital_helm_parity`: `Basis(axis.normalized(), angle)` (`:67`) and `Basis.from_euler` (`:110`). The native helm
  uses `atan2` (`capital_helm.rs:120`), so it also moves with libm. Its recorder is `expected`, so it can be re-recorded.
- `test_ram_sweep_cull`: `Basis.from_euler` inputs (`:17,85,87`). The ram kernel has no trig, so it is unchanged on Linux.
- `test_body_registry`: `Basis.from_euler` (`:34`) on frozen RigidBody3D, one physics frame (a Jolt round trip). Native
  has no trig, so it is unchanged on Linux.

**(b) Jolt, GDScript gameplay or engine trig in the simulation itself (12).** These stay Linux-only bit-exact.
`test_bolt_rows`, `test_core_state`, `test_driver_step`, `test_row_commands` (SeededBattle: Jolt; `BenchLayout` places
ships with `pow`, `bench_layout.gd:423,602`). `test_sim_core` (crowds with `from_euler` at `:56`, Jolt; the
`flight_step_from_the_server` case goes through flight `exp`/`atan2`). `test_turret_kernel` (WeaponRowsScene: GDScript
`cos`/`sin` orbits, `from_euler`, `rotated` at `weapon_rows_scene.gd:68,103,151,160-161`). `test_beam_landing_parity`
(SeededBattle, `Basis(UP, PI)`, beam acos). `test_brain_tolerance` and `test_flight_parity_fight` (Jolt fights, the second
in subprocesses). `test_pilot_kernels_in_play` (Jolt fight, `looking_at`). `test_targeting_on_read` (player ship on
GDScript FlightModel, physics frames). `test_weapon_rows_battle` (main scene; already a 10 % tolerance, so it probably
passes on Windows as written).

**(c) Unclear: 0**, with the two "verify" notes above.

### 2.2 What moves on Linux with the switch (needs re-record)

Expected to move:
- `pilot_kernels` (ties)
- `capital_helm`
- `sim_core.flight_step_from_the_server`
- every seeded-battle digest: `bolt_rows`, `core_state.battle_on_the_old_paths` and probably `melee_rams`, `driver_step`,
  `row_commands`
- `brain_tolerance` native, `flight_parity_fight` native, `weapon_rows_battle` counts
- `turret_kernel`, `beam_landing`, `pilot_kernels_in_play` (`fight_without_kernels`, and perhaps `facades`)
- possibly `targeting_on_read`

Unchanged: the 6 in (a), plus `ram_sweep_cull` and `body_registry`.

GDScript provenance is lost for:
- `pilot_kernels`
- `capital_helm` (GDScript helm at `d3e09c70`)
- `beam_landing` (GDScript landing, M10-T75)
- `pilot_kernels_in_play`
- `core_state`'s old-path entries
- `sim_core.flight_step_from_the_server`
- `targeting_on_read`, if it moves

From then on these are native self-recordings. Say so in the README.

Tests that read moved entries with **`stored` only** need a `ParityFixture.rerecorded(...)` hook added before re-recording:
`test_pilot_kernels` (3), `test_pilot_kernels_in_play` (2), `test_sim_core` (`flight_step_from_the_server`), `test_core_state`
(2 stored entries), and `test_targeting_on_read` if it moves.

### 2.3 Live GDScript-against-native tests that break on Linux (not fixtures)

These compare the native kernel with GDScript that still exists, live, bit for bit. Their GDScript side keeps calling
glibc through the engine, so the libm switch breaks them on Linux. They are already at risk on Windows today, where
Godot's CRT and Rust's UCRT differ.
- `tests/unit/test_flight_step.gd` (10 000 samples × 2 ship types). `exp` is at `kernels.rs:1259` against
  `src/ship/flight_assist.gd:55`, and `atan2` at `kernels.rs:1335` against `flight_assist.gd:138`. The file already has
  `TOLERATED`/`REL_TOL` hooks (`:15-17`).
- `tests/integration/test_flight_batch.gd:146-147`: velocity and spin, batched against the GDScript twin.
- `tests/unit/test_brain_parity.gd`: `test_pilot_steering_gives_the_same_bits` (`:145`) and
  `test_the_five_manoeuvres_fly_the_same_bits` (`:327`).
- `tests/unit/test_brain_think_parity.gd`: native brains against the GDScript `AiPilot`.
- `tests/unit/test_turret_kernel.gd:64-69`: `TurretStandin.turned_toward` (engine `rotated`) and `Vector3.angle_to`
  (engine `atan2f`) against the native versions, 4 000 samples.

(`test_missile_kernel`, `test_ram_tracker` and `test_damage_store` are live bit-for-bit too, but their paths have no
transcendental, so they are safe.)

---

## 3. The libm crate

- **Version 0.2.16**, the latest on crates.io (`cargo search libm`; crates.io is reachable from this machine), now
  maintained in `rust-lang/compiler-builtins`. `rust-version` 1.63, so it builds on the repo's 1.99.1.
- **Licence: MIT** (`Cargo.toml license = "MIT"`; `LICENSE.txt`: "available for use under the MIT license"; contributions
  are also under Apache-2.0). It is GPL-3.0 compatible. Row for `docs/third-party.md`: `| libm | 0.2.16 | MIT | Linked: the
  native kernels' transcendental maths, the same bits on every platform |`.
- **Bit-identical on x86_64 Linux and Windows**: yes by construction. The algorithms are FreeBSD msun ports (`sin.rs:1`,
  `exp.rs:1`, `atan2.rs:1`, `pow.rs:1`, `sinf.rs:1`, ...).
  - With the default `arch` feature, x86_64 swaps in only `sqrtf`/`sqrt` (inline `sqrtss`/`sqrtsd`, `arch/x86.rs`) and
    `fma`/`fmaf`, which choose hardware FMA, FMA4 or a software fallback at run time (`arch/x86/fma.rs:10-40`). All of
    these are correctly rounded, so the choice cannot change bits. Nothing depends on `target_os`.
  - `force-soft-floats` is not needed: it would only swap those correctly rounded routines for soft ones.
  - Do not enable `unstable-intrinsics`. Use default features and pin `libm = "=0.2.16"`, as the repo pins every crate.
- **Measured against glibc** (Linux, 10⁶ seeded inputs each, the scratch crate). Differences are always 1 ULP, on this
  share of inputs:

| function | range | differ | std ns | libm ns |
|---|---|---|---|---|
| sin | [-3.2, 3.2] | 3.1 % | 31.5 | 26.7 |
| cos | [-3.2, 3.2] | 3.1 % | 53.5 | 62.0 |
| tan | [-1.5, 1.5] | 3.8 % | 73.6 | 73.5 |
| asin | [-1, 1] | 6.0 % | 30.7 | 42.8 |
| acos | [-1, 1] | 7.6 % | 66.3 | 50.5 |
| atan | [-10, 10] | 6.1 % | 74.2 | 42.6 |
| exp | [-10, 0] | 9.7 % | 19.1 | 39.2 |
| ln | [0.001, 1000] | 2.0 % | 40.5 | 43.2 |
| atan2 | [-10, 10]² | 17.7 % | 82.4 | 75.8 |
| hypot | ±1e4 | 13.4 % | 60.7 | 39.2 |
| pow | [0.01, 5] | 9.7 % | 58.2 | 226.7 |
| sinf / cosf | [-3.2, 3.2] | 1.2 % | 19.7 | 20.0 |
| atan2f | [-10, 10]² | 16.1 % | n/a | n/a |

  The timings are microbenchmarks that include the RNG, so they are indicative only.
- **Cost per tick (estimate).** The flight kernel makes ≤ 2 calls per flying ship per tick (`exp` and `atan2`): about
  1 000 at 500 ships. Brains make roughly 10 to 30 per think. The tier makes 2 per tier row per tick. Turrets make about 5
  per mount per tick. That is about 5 000 to 15 000 calls a tick. At a mean |Δ| ≤ 10 ns this is ≤ 0.15 ms, against
  `battle` 500's 7.42 ms (M4 AC5, `docs/milestones/m4-performance-and-scale.md:187`). `pow` (+170 ns) appears only in capital
  target scoring (`capital_brain/targets.rs:64`). To re-run: `scripts/bench.sh <label>` for the AC5 headline (`battle` 500;
  the full sweep takes 30 min or more), or at least `scripts/bench_quick.sh <label> battle` (under 10 min). Compare the
  median against 7.42 ms and 1 000 ships against 9.22 ms.

---

## 4. Implementation shape

**Calls.** The least churn is to replace each call site with a fully qualified `libm::` call, with no `use` line:
`x.sin()` → `libm::sin(x)`, f32 `a.cos()` → `libm::cosf(a)`, `x.sin_cos()` → `libm::sincos(x)`, `hypot` → `libm::hypot`,
`ln` → `libm::log`, `powf` → `libm::pow`, `atan2` → `libm::atan2(y, x)`. Watch the argument order: `y.atan2(x)` becomes
`libm::atan2(y, x)`. That is 82 lines in 21 files.
- Rust does not widen f32 to f64 implicitly, so passing f32 to `libm::sin` fails to compile. The 6 f32 sites cannot be
  silently changed to f64.
- Why no wrapper module: the engine-free guard (`tests/unit/test_sim_core.gd:661-697`, `_engine_free_violations`) flags
  any `use` line outside each file's allow-list and any `crate::`/`super::`/`godot::` path outside a `use` line.
  `libm::` matches none of these, so no allow-list changes.
- A `crate::maths` module would instead need a new `use crate::maths::` entry in about 15 allow-lists. Two of them are
  exact strings: `EPHEMERIS_USE_ALLOWED = ["use std::"]` and `RADAR_KERNEL_USE_ALLOWED = ["use crate::v3::{length_squared,
  xform_inv};"]`.
- If named helpers are wanted, put them in `v3.rs`: most kernels already import `use crate::v3::`, and v3's own guard
  (`BRAIN_FILES`, `:611`) allows the inline `libm::` call.

**How the existing guard is built.** It is GDScript. `FileAccess.get_file_as_string` reads each listed Rust file, which is
split into lines; lines starting with `//` are skipped. Each line is checked for forbidden tokens (`KERNEL_FORBIDDEN`,
`:622-624`, with `/*` refused outright) and for `use` lines outside a per-file allow-list. `test_the_kernels_hold_no_engine_type`
(`:748`) accumulates violations over every kernel file list and asserts zero.

**New guard.** In the same style, add `test_the_native_maths_never_reach_the_c_runtime` beside it. It walks every
`res://native/src/**/*.rs` except `tests.rs` and `*/tests.rs`, skips comment lines, and refuses:
- the std methods: `.sin(`, `.cos(`, `.tan(`, `.asin(`, `.acos(`, `.atan(`, `.atan2(`, `.sin_cos(`, `.sinh(`, `.cosh(`,
  `.tanh(`, `.asinh(`, `.acosh(`, `.atanh(`, `.exp(`, `.exp2(`, `.exp_m1(`, `.ln(`, `.log(`, `.log2(`, `.log10(`, `.ln_1p(`,
  `.powf(`, `.cbrt(`, `.hypot(`, `.mul_add(`
- their path forms: `f32::sin`, `f64::exp` and so on
- engine and glam builtins with trig: `from_euler(`, `from_axis_angle(`, `.angle_to(`, `.signed_angle_to(`, `.slerp(`,
  `.rotated(`, `Quaternion`, `.get_euler(`

The free function `v3::rotated(` has no dot and passes. Optionally make `floor`/`ceil`/`round`/float `%` go through libm
too; they are exact already, so this is not required. Clippy `disallowed-methods` would also work, but CI does not run
clippy (`scripts/lib_tests.sh:82` runs only `cargo test --release --lib`), so the grep guard is the repo's idiom.

**Also add.**
- A cargo test `maths_golden`: about 1 000 seeded inputs per used function, the result bits FNV-hashed, the hashes recorded
  on Linux. `cargo test` runs on the Windows runner, so this proves the DLL's maths in seconds without Godot.
- Update architecture §17.9 (`docs/architecture.md:2464`) and the brains section (`:2895`). Both say native and GDScript
  share "the host's libm", which will no longer be true.

**How re-recording works today.** `ParityFixture.expected(file, case, recorder)` and `ParityFixture.rerecorded(file, case,
value[, key])` write the case when `SCS_RECORD_FIXTURES=1`, and refuse when `CI=true` (`parity_fixture.gd:25-55`). The
command is in `tests/fixtures/parity/README.md` (M7-T16's):
```
SCS_RECORD_FIXTURES=1 GUT_SLOW=1 .tools/godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit \
    -gtest=res://tests/integration/test_brain_tolerance.gd,res://tests/integration/test_flight_parity_fight.gd,res://tests/integration/test_weapon_rows_battle.gd,res://tests/unit/test_bolt_rows.gd,res://tests/unit/test_core_state.gd,res://tests/unit/test_driver_step.gd,res://tests/unit/test_row_commands.gd
```
For the libm switch:
1. Run the full suite once and list the parity failures.
2. Add `rerecorded` hooks to the `stored`-only tests that failed (2.2).
3. Re-record with the list extended (`test_pilot_kernels`, `test_capital_helm_parity`, `test_sim_core`, `test_turret_kernel`,
   `test_beam_landing_parity`, `test_pilot_kernels_in_play`, `test_targeting_on_read` if needed).
4. Run the full suite twice.
5. Add a README section "M9-Tx re-recorded …" with old → new counts, as earlier re-records did.

---

## 5. Thread-count and threaded/delayed identity

Nothing here is platform-specific.
- There is no float reduction across threads. `threads.rs:210` is `par_chunks_mut(...).for_each` with per-item writes and a
  scratch per worker. `threads.rs:126` sums integer counters. The float `.fold(0.0, f64::max)` and `.sum()` calls
  (`contact_field.rs:139,180`, `capital_brain.rs:226,241`, `capital_run.rs:259,267`, ...) are sequential iterators.
- Default `RandomState` `HashMap`/`HashSet` exist: `intercept_kernels.rs:348,388,390`, `capital_intercepts.rs:106-109`,
  `ram_tracker.rs:90-105`, `turret_kernels.rs:804`, `rows.rs:80,170` and `sim_core.rs:192,267-298`. They are used for
  lookup and `retain` (`capital_intercepts.rs:413-414`, `intercept_kernels.rs:412`, `ram_tracker.rs:302`), which is
  order-independent. `RandomState` is seeded randomly per process on Linux too, so any order dependence would already
  show as run-to-run flakiness there; it is not a Windows risk.
- The ID and cell maps use fixed hashers (`row_commands.rs:28-33`, `sweep_cells.rs:48` `BuildHasherDefault`).
- One platform difference outside the bits: `threads::performance_cores()` reads Linux sysfs (`threads.rs:350-371`), and on
  Windows it falls back to `available_parallelism()` (logical cores). The default thread count differs, but the results
  do not. A 4-vCPU GitHub runner still runs the "6 threads" tests with 6 pool threads unless the setting is capped.
- The MXCSR (FTZ/DAZ) default is the same on both OSes.

---

## 6. Conclusion and proposed tasks

**Bit-exact on both platforms after the switch:** 7 of 22 fixture files. These are the 6 in (a): contact_field, sweep_cells,
damage_rules, bolt_sync, hit_broad_phase, hit_scale (verify). Plus `test_pilot_kernels`.
- **3 more** once their inputs are made trig-free or stored: capital_helm, ram_sweep_cull, body_registry (the last
  depends on a Jolt round trip; verify).
- Add the new `maths_golden` cargo test.

**Linux-only bit-exact (12):** bolt_rows, core_state, driver_step, row_commands, sim_core, turret_kernel, beam_landing,
brain_tolerance, flight_parity_fight, pilot_kernels_in_play, targeting_on_read, weapon_rows_battle. Gate the exact
comparison on `OS.get_name() == "Linux"`. On Windows, check the platform-agnostic invariants instead:
- the same digests with 1 and 6 threads, and threaded against delayed, **live in one run**, not against the Linux recording
- run-to-run determinism (two runs give the same digest)
- the Q16/Q22 tolerances already used: hits within 10-20 %, behaviour mix within 5 points
- the structural counts

The live GDScript-against-native tests (2.3) need either `REL_TOL`/ULP tolerances on the fields downstream of a
transcendental, or (better for the player's ship) a native maths bridge: an `ScsMaths` class with static `#[func]` libm
`sin`/`cos`/`atan2`/`exp`/`acos`/`rotated`/`angle_to`, which `FlightAssist`, the GDScript `AiPilot` maths and
`TurretStandin` call. Then GDScript and native share bits on both platforms again.

**Task split:**
1. **M9-Tα: libm in the kernels.** Pin `libm = "=0.2.16"` and add the third-party row. Replace the 82 call lines with
   `libm::` calls. Add the GUT guard against C-runtime maths and the `maths_golden` cargo test. Fix the 6 live
   GDScript-parity tests, by tolerance or the `ScsMaths` bridge (decide first). Add `rerecorded` hooks and re-record the
   moved fixtures on Linux, with a README section. Update architecture §17.9 and the brains section. Re-run
   `scripts/bench.sh` (`battle` 500 against 7.42 ms). This is one PR, Linux only.
2. **M9-Tβ: Windows mode for the mixed tests.** Make capital_helm, ram_sweep_cull and body_registry inputs trig-free, or
   store their inputs. Add a platform gate to the 12 (b) tests, with live 1-vs-6 and threaded-vs-delayed comparisons and
   tolerances on Windows. Document the classes in `tests/fixtures/parity/README.md` and record "Jolt is not
   `JPH_CROSS_PLATFORM_DETERMINISTIC` in 4.7.2" in `docs/research-notes.md`.
3. **M9-Tγ: confirm on the Windows runner.** Run `cargo test` (`maths_golden` must match Linux), then the GUT suite. Check
   that the 7 (or 10) cross-platform fixtures pass exactly and the 12 pass their Windows mode. Watch hit_scale,
   bolt_sync and body_registry, which rest on engine arithmetic under `/fp:strict` and `-ffp-contract=off`. Record what
   differed.
