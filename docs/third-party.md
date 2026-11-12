# Third-party software and licences

This project is GPL-3.0 (see `LICENSE`). Everything listed here is GPL-3.0-compatible. When you add a
dependency, add a row here in the same PR and keep its licence file next to the vendored code.

## Vendored in this repository (`addons/`)

| Component | Version | Location | Licence | Upstream |
|---|---|---|---|---|
| GUT (Godot Unit Test) | v9.7.1 | `addons/gut/` (+ `addons/gut/LICENSE.md`) | MIT | https://github.com/bitwes/Gut |
| Compositor Lens Effects (lens flare and god rays) | commit `0ce061271f672f05fbb9aed08a61e019a875c1ad` (2026-07-05; the repo has no tags) | `addons/lens_effects/` (+ `addons/lens_effects/LICENSE`) | MIT (copyright 2025 ARez) | https://github.com/ARez2/compositor-effect-lens-effects |

`scripts/vendor_addons.sh` pins an add-on by tag, or by full commit when the repo has no tags (the lens effects). The `.uid` and `.import` files next to vendored code are written by the engine, not upstream, so run `--import` after re-vendoring. The add-on's files are unedited; `SceneLensFlareEffect` patches a few lines of its shader in memory, so the flare takes the star's colour (Q30) and shows no haze or god rays (Q31). The lens
effects add-on is used as vendored: only its `LensFlareEffect` class and shader are used (not its `plugin.gd`, which is not
enabled, nor `world_environment.gd`, whose job `src/rendering/post_effects.gd` does). `src/rendering/lens_flare_effect.gd` is a
thin subclass of ours that compiles the add-on's shader when the game starts: a headless import has no renderer, so it cannot
resolve the shader's `#include "godot/scene_data_inc.glsl"` and caches an empty shader (see `docs/research-notes.md`).

Vendored addons are upstream code: do not edit them in place. If a patch is unavoidable, put it in
`addons/<name>/PATCHES.md`, keep it minimal, and upstream it.

## Removed (history)

| Component | Removed | Why |
|---|---|---|
| GDGS (Godot Gaussian Splatting plugin, MIT, by ReconWorldLab), the project's fork `addons/gdgs_scs/` (from v3.3.0) | 2026-11-04, M4-T31 | Q29: every hull is a textured polygon mesh now. The GitHub fork `jrssae/godot-gaussian-splatting` was archived on 2026-11-04 (Q30) and the maintainer deletes it; `scripts/sync_gdgs_fork.sh` went with it |
| Pillow | 2026-11-04, M4-T31 (unused since M4-T30c) | `tools/procgen/core/image.py` writes every PNG; CI no longer installs it. M5's `tools/refview` still uses it (below) |

## Used but not vendored

| Component | Version | Licence | Role |
|---|---|---|---|
| Godot Engine | 4.7.2-stable | MIT | Engine (installed locally by `scripts/setup_godot.sh`, never committed) |
| Godot export templates (Linux x86_64 release and debug only) | 4.7.2-stable | MIT | Release-build measurements only (installed locally by the opt-in `scripts/setup_export_templates.sh`, SHA-512 checked, never committed or shipped) |
| Jolt Physics | bundled in Godot 4.7 | MIT | 3D physics backend |
| SDL3 | bundled in Godot 4.7 | Zlib | Gamepad input backend |
| Python | 3.11+ | PSF-2.0 | Asset generators in `tools/` |
| NumPy | 2.x | BSD-3-Clause | Asset generators |
| Pillow | 10+ (optional) | MIT-CMU | `tools/refview` only (development only: renders the untracked reference models into the gitignored `reports/refs/`); the game's PNGs come from `tools/procgen/core/image.py` |

## Built from source, not vendored (`native/`, M4-T05)

Cargo downloads these crates from crates.io at the exact versions in `native/Cargo.lock` and builds them into
`bin/libscs_native.so` (`scripts/build_native.sh`; never committed). "Linked" crates end up in the library; "build" crates only
run while it compiles (procedural macros, code generation, build scripts).

| Component | Version | Licence | Role |
|---|---|---|---|
| godot-rust gdext: `godot`, `godot-core`, `godot-ffi`, `godot-cell` | 0.5.5 | MPL-2.0 | Linked: the Rust bindings to Godot's GDExtension API |
| godot-rust gdext: `godot-macros`, `godot-codegen`, `godot-bindings` | 0.5.5 | MPL-2.0 | Build: the class macros and the generated API |
| `gdextension-api` (godot-rust) | 0.5.1 | MPL-2.0 | Build: Godot's prebuilt API description for gdext |
| glam | 0.32.1 | MIT OR Apache-2.0 | Linked: vector maths inside gdext |
| libc | 0.2.191 | MIT OR Apache-2.0 | Linked: C types for the FFI |
| Rust toolchain and standard library | 1.99.1 (`native/rust-toolchain.toml`) | MIT OR Apache-2.0 | Compiler (the user's own rustup); std is linked into the library |
| proc-macro2, quote | 1.0.107, 1.0.47 | MIT OR Apache-2.0 | Build: procedural macro support |
| unicode-ident | 1.0.27 | (MIT OR Apache-2.0) AND Unicode-3.0 | Build: identifier tables for proc-macro2 |
| venial | 0.6.1 | MIT | Build: parses Rust items for gdext's macros |
| heck | 0.5.0 | MIT OR Apache-2.0 | Build: name case conversion in the code generator |
| nanoserde, nanoserde-derive | 0.2.1 | MIT OR Apache-2.0; MIT | Build: reads the API description |
| rayon, rayon-core (M4-T18) | 1.12.0, 1.13.0 | MIT OR Apache-2.0 | Linked: the worker threads that run the native core's per-ship passes |
| crossbeam-deque, crossbeam-epoch, crossbeam-utils (M4-T18, through rayon-core) | 0.8.8, 0.9.21, 0.8.23 | MIT OR Apache-2.0 | Linked: rayon's work-stealing queues |
| either (M4-T18, through rayon) | 1.19.0 | MIT OR Apache-2.0 | Linked: a two-way enum rayon's iterators use |

MPL-2.0 combines with GPL-3.0 as a "Secondary License" (MPL-2.0 section 3.3) unless a file carries the "Incompatible With
Secondary Licenses" notice. None of the 325 files in the eight MPL-2.0 crates above carries it (checked with grep on 2026-11-03).
Re-check this table against `cargo metadata` whenever `Cargo.lock` changes.

## Candidates evaluated and not adopted (yet)

| Component | Licence | Why not now |
|---|---|---|
| gdUnit4 | MIT | Fine framework; GUT chosen for its simpler headless CLI |
| Piper TTS (`OHF-Voice/piper1-gpl`; the original `rhasspy/piper` was MIT and is archived) | GPL-3.0 (voice models: per-voice `MODEL_CARD` licence) | Candidate for voiced dialog (roadmap M15), run offline on the user's machine; adopt only voices whose licence permits it |
| Kokoro TTS | Apache-2.0 (code and weights) | Alternative TTS candidate for M15 |
| espeak-ng | GPL-3.0 | Phonemizer used by Piper/Kokoro; also usable alone for synthetic radio voices |

## Content

No official Babylon 5 assets, or data derived from them, are used. Franchise names are used openly (fan
project); the ship is an original parametric model based on the Starfury silhouette. See `DISCLAIMER.md`.
