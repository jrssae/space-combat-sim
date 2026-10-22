# Third-party software and licences

This project is GPL-3.0 (see `LICENSE`). Everything listed here is GPL-3.0-compatible. When you add a
dependency, add a row here in the same PR and keep its licence file next to the vendored code.

## Vendored in this repository (`addons/`)

| Component | Version | Location | Licence | Upstream |
|---|---|---|---|---|
| GDGS (Godot Gaussian Splatting plugin) | v3.3.0 | `addons/gdgs/` (+ `addons/gdgs/LICENSE`) | MIT | https://github.com/ReconWorldLab/godot-gaussian-splatting |
| GUT (Godot Unit Test) | v9.7.1 | `addons/gut/` (+ `addons/gut/LICENSE.md`) | MIT | https://github.com/bitwes/Gut |

Vendored addons are upstream code: do not edit them in place. GDGS carries two documented local fixes (sort-buffer
overflow, narrow-subgroup fallback): see `addons/gdgs/PATCHES.md`. If a patch is unavoidable, put it in
`addons/<name>/PATCHES.md`, keep it minimal, and upstream it.

## Used but not vendored

| Component | Version | Licence | Role |
|---|---|---|---|
| Godot Engine | 4.7.2-stable | MIT | Engine (installed locally by `scripts/setup_godot.sh`, never committed) |
| Jolt Physics | bundled in Godot 4.7 | MIT | 3D physics backend |
| SDL3 | bundled in Godot 4.7 | Zlib | Gamepad input backend |
| Python | 3.11+ | PSF-2.0 | Asset generators in `tools/` |
| NumPy | 2.x | BSD-3-Clause | Asset generators |
| Pillow | 10+ (optional) | MIT-CMU | Only for the fallback panorama sky PNG |

## Candidates evaluated and not adopted (yet)

| Component | Licence | Why not now |
|---|---|---|
| Brush (splat trainer) | Apache-2.0 | Needs a GPU; optional M2+ polish path |
| OpenSplat | AGPL-3.0 | CPU path too slow for CI; AGPL is fine for an external tool but adds nothing over sampling |
| gdUnit4 | MIT | Fine framework; GUT chosen for its simpler headless CLI |
| Piper TTS (`OHF-Voice/piper1-gpl`; the original `rhasspy/piper` was MIT and is archived) | GPL-3.0 (voice models: per-voice `MODEL_CARD` licence) | Candidate for voiced dialog (roadmap M14), run offline on the user's machine; adopt only voices whose licence permits it |
| Kokoro TTS | Apache-2.0 (code and weights) | Alternative TTS candidate for M14 |
| espeak-ng | GPL-3.0 | Phonemizer used by Piper/Kokoro; also usable alone for synthetic radio voices |

## Content

No official Babylon 5 assets, or data derived from them, are used. Franchise names are used openly (fan
project); the ship is an original parametric model based on the Starfury silhouette. See `DISCLAIMER.md`.
