# Changes in this fork of GDGS

`addons/gdgs_scs/` is the project's own fork of GDGS, forked on 2026-11-01 from upstream tag v3.3.0
(commit 70996511607a886dac9fdd5fc59a0445308eb3db, https://github.com/ReconWorldLab/godot-gaussian-splatting).
It stays under upstream's MIT licence (`LICENSE`, unchanged, copyright ReconWorldLab). Edit it freely, and record every
change below with how to revert it. Each changed line carries a `[space-combat-sim patch]` comment, so a later rebase
onto a newer upstream can find them. Patches 1-4 were made while the addon was still vendored as `addons/gdgs/`.

The game loads the imported copy of a shader, so run `.tools/godot/godot --headless --path . --import` after editing one,
before looking at the result. The project setting keys (`gdgs/rendering/backend`) and the log prefix `[gdgs]` keep upstream's
names.

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

## 5. Resident splat budget (hidden and off-screen splats cost no sort memory)

Upstream sizes the culled, sort and histogram buffers by every instanced splat in the scene, hidden ones included, and the projection
pass visits them all, to skip the hidden ones one by one. A ship carrying its whole LOD chain pays for all of it: 100 ships are about
5.4 M resident splats, measured at 3.2 GB of video memory, however few are drawn.

The real cost of a splat in those buffers is 576 B, not the "about 330 B" first planned: 64 B of projected data, and 32 sort slots at
8 B in each of two double-buffered sort buffers (512 B). The histogram adds about 8 B, and the instance ids this patch removes were 8 B.

What changed:

- `gaussian_splat_budget.gd` (new, pure) owns `MAX_SORT_ELEMENTS_PER_SPLAT` and sizes the culled, sort and histogram buffers from a
  budget of visible splats. They do not change when visibility does; a changed budget reallocates once. Splats, lighting, transforms
  and the table keep their own sizes.
- `gaussian_visible_table.gd` (new, pure) builds, each frame at render time, a table with one row per drawn instance: first visible
  splat (a running sum), count, resource base, instance index. Hidden instances take no row, and neither do instances whose bounding
  sphere is outside the frustum. An instance past the budget is truncated and the rest dropped.
- `gsplat_projection.glsl`: binding 6 is that table instead of the per-splat ids, `id` counts visible splats, and a binary search finds the
  row. `point_count` carries the visible total, and the uniform block grew by the row count. Visibility no longer rides in the matrix.
- `gaussian_gpu_state_cache.gd`, `gaussian_renderer.gd`: the indirect dispatch sizes and the projection pass's size follow the visible
  total, set on the CPU and only when it changes, so a big budget does not dispatch tens of thousands of no-op workgroups.
- `gaussian_rendering_device_context.gd`: `create_scratch_buffer`, for buffers the GPU fills before it reads, instead of building a zero-filled
  copy on the CPU and uploading it.
- `gaussian_scene_registry.gd`, `gaussian_render_manager.gd`: registrations and resource changes coalesce into one merge, deferred, before
  the next render, and the per-splat GDScript loop is gone (the merge was quadratic at load). A moved node patches its own matrix and
  sphere, where each moved node used to rebuild every instance's bytes; a hidden node writes nothing until it is shown; the bytes are
  produced at render time, once, because Godot delivers `NOTIFICATION_TRANSFORM_CHANGED` after `_process` and an earlier snapshot would
  lag a frame.
- `gaussian_splat_node.gd`, `gaussian_compute_backend.gd`: relight knobs have setters that patch their own entry, where the manager used
  to read five properties of every node every frame. The light rig is still compared each frame. The Raster backend has no such hook
  and reads the knobs itself, as before.
- `gaussian_render_manager.gd`: `set_splat_budget`, `get_stats` (counters on `rebuild_gpu_state` and `upload_splats`, the last frame's visible total).

The culling is conservative against the shader's own per-splat test, which keeps a centre out to 1.2x the view bounds: the planes are
at those bounds, and the sphere comes from the resource's `aabb` (splat centres), scaled by the node's transform, with 25 % plus 1 m for
the splats' own extent. A sphere that holds the camera, as the sky's does, always passes. Near and far planes are left out: they
depend on the depth convention and save almost nothing.

**One decision against the plan.** The plan was to dispatch over `min(visible * 32, capacity)` elements and clamp the sort to the whole
capacity. Measured, the sky alone writes more keys than that: 983 332 at 1080p from 16 000 visible splats, whose limit would be 512 000,
because each big nebula splat touches hundreds of tiles. Tried that way, the keys past the dispatch are lost and the nebula dims (mean
per-channel difference 1.57, max 124, where the noise between two runs is 0.04). So `frame_elements` keeps a floor of 1024 elements per
screen tile (8.4 M at 1080p, 8.5 times what the sky needs), and the upsweep, spine, downsweep and boundary passes all clamp to that same
per-frame limit, which needed a push constant on the boundary pass. Patch 1's clamps stay as the overflow guard: if a frame ever writes past
the limit, the keys past it are dropped cleanly.

Measured on an RX 6950 XT (RADV) at 1080p, before / after: 13 ships load in 6.8 / 0.67 s, frame 3.92 / 3.33 ms, GPU 2.89 / 2.23 ms, VRAM
added 927 / 1539 MB. 100 ships load in 53 / 0.74 s, GPU 4.29 / 2.68 ms, VRAM added 3217 / 1515 MB, and with every ship moving a frame goes from
289 to 98.5 ms at one physics tick per frame. The fixed test scene differs by no more than two runs of the same code do. The numbers are in
`docs/milestones/m3-ai-pilots-and-wingmen.md`, M3-T20.

Not changed: the Raster backend; `MAX_RENDER_STATES` is still 4, so resizing the window through four sizes holds four sets of budget
buffers until the oldest is evicted.

To revert: `git revert` the commit `M3-T20: resident splat budget in the GDGS fork`, then run `--import` (a shader changed). The game's
side goes with it (`settings.splat_budget`, the `LodSwitcher` step-down, the `render` fields); nothing else depends on it.

Upstream candidate, like patches 1 and 2, apart from the deferred merge, which assumes nodes register on the main thread.
