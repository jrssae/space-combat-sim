# Local patches to GDGS v3.3.0

Vendored upstream code is not edited except for the fixes below. Each changed line carries a
`[space-combat-sim patch]` comment. Re-apply after re-vendoring until upstream fixes them. The game loads the imported copy of a
shader, so run `.tools/godot/godot --headless --path . --import` after editing one, before looking at the result.

## 1. Sort-buffer overflow (checkerboard tiles on GPUs, heap corruption on CPU Vulkan)

`gsplat_projection.glsl` reserves `num_tiles_touched` sort slots per splat with an unguarded `atomicAdd`,
but the sort buffers only hold `point_count * MAX_SORT_ELEMENTS_PER_SPLAT` (was 10) keys. Large on-screen
splats (close-up hulls, big nebula Gaussians) exceed that, and the projection, radix sort and tile-boundary
passes then read and write past the end of the buffers. On GPUs this shows up as blocky or checkerboarded tiles;
on llvmpipe (CPU Vulkan) it corrupts the process heap.

Fix:
- `MAX_SORT_ELEMENTS_PER_SPLAT` 10 -> 32 in `gaussian_renderer.gd` and `gaussian_gpu_state_cache.gd`.
- The projection stops writing at the buffer's capacity (`sort_keys.length() / 2`).
- The upsweep, spine and downsweep passes clamp `element_count` to the capacity, passed in the formerly unused
  fourth push-constant slot.
- The boundary pass clamps its count to `sort_buffer.length() / 2`.

## 2. Narrow subgroups (memory corruption in the radix sort)

The radix sort sizes shared memory for at least 32-wide subgroups (16 subgroups per 512-thread workgroup).
Devices that run compute narrower (llvmpipe: 8, many Intel GPUs: 8-16) index past those arrays.
`gaussian_compute_backend.gd` now measures the subgroup size with a one-workgroup probe on a local
RenderingDevice and declines the Compute backend below 32, so the selector falls back to Raster.

Both are candidates for upstream issues at https://github.com/ReconWorldLab/godot-gaussian-splatting.

## 3. Depth sort key resolution (flicker in the nebula and on distant hulls)

`gsplat_projection.glsl` sorts splats within a tile by a 16-bit depth key, `uint(65535 * d / (1 + d))`. That curve is flat
beyond a few hundred metres: its step is 1.5 m at 1 km and about 6 km at the 20 km sky, so every nebula splat and the parts
of a far hull share a few key values. Equal keys keep the order the projection pass happened to write them in, which changes
from frame to frame, so overlapping translucent splats blend in a different order each frame and flicker.

Fix: `uint(65535 * clamp(log2(1 + d) / 17, 0, 1))`, a constant relative step of about 0.018 % (2 mm at 10 m, 0.3 m at 1.5 km,
4 m at 20 km, range to 131 km). Still monotonic, so the order of anything that was already resolved is unchanged. To revert,
restore the two original lines (`depth01 = view_depth / (1.0 + view_depth)` and `depth = uint(depth01 * 65535.0) & 0xFFFF`).
Not verifiable without a GPU: the maintainer's play test (AC13) decides.

## 4. Tile-aligned blocks around faint splats (nebula)

The projection pass sizes each splat's screen rectangle with `pow(opacity, 0.2) * 2.5 * sigma`, so a faint splat covers fewer tiles
(upstream's choice, for speed). For the nebula's opacities of 0.02-0.08 that is a cut at 1.15 to 1.5 sigma, where the Gaussian
is still at 30-50 % of its peak, and the cut follows the 16 px tile grid, so soft clouds end in staircase blocks (seen on the
maintainer's GPU in the 2026-10-21 play test).

Fix: the opacity factor is floored at 0.9 (`max(pow(opacity, 0.2), 0.9)`): a cut at 2.25 sigma, under 8 % of the splat's own opacity.
Opaque splats (hulls, stars) are unaffected; faint large ones touch about four times as many tiles. To revert, restore
`pow(splat_opacity, 0.2) * 2.5*sqrt(max(eigenvalues.x, eigenvalues.y))`. Not verifiable without a GPU: AC13 decides.
