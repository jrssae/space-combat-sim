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

## Our fork (`addons/`)

| Component | Forked from | Location | Licence | Upstream |
|---|---|---|---|---|
| GDGS (Godot Gaussian Splatting plugin), by ReconWorldLab | v3.3.0, commit `d9de8db` | `addons/gdgs_scs/` (+ `addons/gdgs_scs/LICENSE`); fork: https://github.com/jrssae/godot-gaussian-splatting, branch `space-combat-sim` | MIT, unchanged (copyright ReconWorldLab) | https://github.com/ReconWorldLab/godot-gaussian-splatting |

The project owns this fork (maintainer, 2026-11-01) because the game needs renderer changes upstream may never take. Edit it in
this repo, where the game needs it, then run `scripts/sync_gdgs_fork.sh "<subject>"`, which commits the same tree to the fork, pushes
it and updates the pin in `scripts/vendor_addons.sh`. `addons/gdgs_scs/PATCHES.md` lists every change and how to revert it; the general fixes
are still upstream candidates. The fork keeps upstream's licence, so the rest of the project stays GPL-3.0 and this directory
stays MIT. The fork's description says it is vibe coded for this project and not intended or optimized for anyone else's use, though
everyone is welcome to it.

## Used but not vendored

| Component | Version | Licence | Role |
|---|---|---|---|
| Godot Engine | 4.7.2-stable | MIT | Engine (installed locally by `scripts/setup_godot.sh`, never committed) |
| Godot export templates (Linux x86_64 release and debug only) | 4.7.2-stable | MIT | Release-build measurements only (installed locally by the opt-in `scripts/setup_export_templates.sh`, SHA-512 checked, never committed or shipped) |
| Jolt Physics | bundled in Godot 4.7 | MIT | 3D physics backend |
| SDL3 | bundled in Godot 4.7 | Zlib | Gamepad input backend |
| Python | 3.11+ | PSF-2.0 | Asset generators in `tools/` |
| NumPy | 2.x | BSD-3-Clause | Asset generators |
| Pillow | 10+ (optional) | MIT-CMU | Only for the fallback panorama sky PNG |

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

MPL-2.0 combines with GPL-3.0 as a "Secondary License" (MPL-2.0 section 3.3) unless a file carries the "Incompatible With
Secondary Licenses" notice. None of the 325 files in the eight MPL-2.0 crates above carries it (checked with grep on 2026-11-03).
Re-check this table against `cargo metadata` whenever `Cargo.lock` changes.

## Candidates evaluated and not adopted (yet)

| Component | Licence | Why not now |
|---|---|---|
| Brush (splat trainer) | Apache-2.0 | Needs a GPU; optional M2+ polish path |
| OpenSplat | AGPL-3.0 | CPU path too slow for CI; AGPL is fine for an external tool but adds nothing over sampling |
| gdUnit4 | MIT | Fine framework; GUT chosen for its simpler headless CLI |
| Piper TTS (`OHF-Voice/piper1-gpl`; the original `rhasspy/piper` was MIT and is archived) | GPL-3.0 (voice models: per-voice `MODEL_CARD` licence) | Candidate for voiced dialog (roadmap M15), run offline on the user's machine; adopt only voices whose licence permits it |
| Kokoro TTS | Apache-2.0 (code and weights) | Alternative TTS candidate for M15 |
| espeak-ng | GPL-3.0 | Phonemizer used by Piper/Kokoro; also usable alone for synthetic radio voices |

## Content

No official Babylon 5 assets, or data derived from them, are used. Franchise names are used openly (fan
project); the ship is an original parametric model based on the Starfury silhouette. See `DISCLAIMER.md`.
