# Local patches to GDGS v3.3.0

Vendored upstream code is not edited except for the fixes below. Each changed line carries a
`[space-combat-sim patch]` comment. Re-apply after re-vendoring until upstream fixes them.

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
