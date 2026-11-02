@tool
extends RefCounted
class_name GaussianSplatBudget

## [space-combat-sim patch] How much GPU memory a visible-splat budget costs, and how much of it a frame dispatches over.
## Pure: no GPU calls, so the tests can call it. See PATCHES.md, patch 5.

## The default budget, in visible splats.
const DEFAULT_SPLATS := 2000000
## Sort slots reserved per visible splat. A splat takes one per screen tile it touches.
const MAX_SORT_ELEMENTS_PER_SPLAT := 32
## Projected data per visible splat. Must match RasterizeData in gsplat_projection.glsl.
const CULLED_BYTES_PER_SPLAT := 64
## One uint per element, double-buffered for the radix sort's in and out halves. Keys and values each.
const SORT_BYTES_PER_ELEMENT := 8
## 64 B of projected data and 32 slots in both sort buffers. The histogram adds about 8 B on top.
const BYTES_PER_BUDGET_SPLAT := CULLED_BYTES_PER_SPLAT + MAX_SORT_ELEMENTS_PER_SPLAT * SORT_BYTES_PER_ELEMENT * 2
## Must match the radix sort shaders.
const RADIX := 256
const WORKGROUP_SIZE := 512
const PARTITION_DIVISION := 8
const PARTITION_SIZE := PARTITION_DIVISION * WORKGROUP_SIZE
## Must match gsplat_boundaries.glsl and gsplat_projection.glsl.
const BOUNDARY_GROUP_SIZE := 256
const PROJECTION_GROUP_SIZE := 256
## Sort elements a frame can always use, per screen tile. Few visible splats can still touch many tiles each (the nebula), so the
## elements cannot follow the visible total alone. See PATCHES.md, patch 5, for the measurement behind it.
const MIN_ELEMENTS_PER_TILE := 1024


## The sort elements a budget holds.
static func sort_capacity(budget_splats: int) -> int:
	return maxi(budget_splats, 1) * MAX_SORT_ELEMENTS_PER_SPLAT


## Bytes of each buffer that follows the budget, and their total.
static func sizes(budget_splats: int) -> Dictionary:
	var splats: int = maxi(budget_splats, 1)
	var capacity: int = sort_capacity(splats)
	var culled: int = splats * CULLED_BYTES_PER_SPLAT
	var sort_buffer: int = capacity * SORT_BYTES_PER_ELEMENT
	var partitions: int = (capacity + PARTITION_SIZE - 1) / PARTITION_SIZE
	var histogram: int = 4 + (1 + 4 * RADIX + partitions * RADIX) * 4
	return {
		"culled": culled,
		"sort_keys": sort_buffer,
		"sort_values": sort_buffer,
		"histogram": histogram,
		"total": culled + sort_buffer * 2 + histogram,
	}


## The sort elements this frame dispatches over and keeps: enough for the visible splats' slots, never under the floor for the
## screen's tiles, never past the buffers.
static func frame_elements(visible_splats: int, budget_splats: int, tile_count: int) -> int:
	var wanted: int = maxi(visible_splats * MAX_SORT_ELEMENTS_PER_SPLAT, tile_count * MIN_ELEMENTS_PER_TILE)
	return mini(wanted, sort_capacity(budget_splats))


## Indirect dispatch sizes for `elements`: the upsweep and downsweep's partitions, then the boundary pass's groups.
static func dispatch_dims(elements: int) -> PackedInt32Array:
	var partitions: int = maxi((elements + PARTITION_SIZE - 1) / PARTITION_SIZE, 1)
	var boundary_groups: int = maxi((elements + BOUNDARY_GROUP_SIZE - 1) / BOUNDARY_GROUP_SIZE, 1)
	return PackedInt32Array([partitions, 1, 1, boundary_groups, 1, 1])


## Workgroups the projection pass needs for `visible_splats`. Never zero: a zero dispatch is an error in the RenderingDevice.
static func projection_groups(visible_splats: int) -> int:
	return maxi((visible_splats + PROJECTION_GROUP_SIZE - 1) / PROJECTION_GROUP_SIZE, 1)
