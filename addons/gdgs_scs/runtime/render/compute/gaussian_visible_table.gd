@tool
extends RefCounted
class_name GaussianVisibleTable

## [space-combat-sim patch] The per-frame list of instances the projection pass draws, so hidden and off-screen instances cost
## no sort memory and no shader time. Pure: no GPU calls, so the tests can call it. See PATCHES.md, patch 5.

const BYTES_PER_ROW := 16
const PLANE_COUNT := 5
## The per-splat test in gsplat_projection.glsl keeps a centre out to 1.2x the view bounds. Must match it.
const VIEW_BOUNDS_MARGIN := 1.2


## World-space planes (a, b, c, d per plane, inside when a x + b y + c z + d >= 0) that hold everything the shader's own test can
## draw: the four sides at its 1.2x bounds and the plane through the camera. The near and far planes are left out on purpose:
## they depend on the depth convention and would only save the odd instance past 50 km.
static func frustum_planes(view: Projection, projection: Projection) -> PackedFloat32Array:
	var m: Projection = projection * view
	var rows: Array[Vector4] = [
		Vector4(m.x.x, m.y.x, m.z.x, m.w.x),
		Vector4(m.x.y, m.y.y, m.z.y, m.w.y),
		Vector4(m.x.w, m.y.w, m.z.w, m.w.w),
	]
	var side: Vector4 = rows[2] * VIEW_BOUNDS_MARGIN
	var raw: Array[Vector4] = [side + rows[0], side - rows[0], side + rows[1], side - rows[1], rows[2]]
	var out := PackedFloat32Array()
	out.resize(PLANE_COUNT * 4)
	for i: int in PLANE_COUNT:
		var plane: Vector4 = raw[i]
		var length: float = Vector3(plane.x, plane.y, plane.z).length()
		# An orthographic camera's w row has no direction: a plane that holds everything.
		if length < 1e-9:
			out[i * 4 + 3] = 1.0
			continue
		out[i * 4] = plane.x / length
		out[i * 4 + 1] = plane.y / length
		out[i * 4 + 2] = plane.z / length
		out[i * 4 + 3] = plane.w / length
	return out


## Whether a sphere can hold anything inside `planes`. Conservative: it never says no to a sphere that reaches inside.
static func sphere_visible(planes: PackedFloat32Array, x: float, y: float, z: float, radius: float) -> bool:
	for p: int in range(0, PLANE_COUNT * 4, 4):
		if planes[p] * x + planes[p + 1] * y + planes[p + 2] * z + planes[p + 3] < -radius:
			return false
	return true


## The table for one frame. Arrays are per instance: splat count, base in the merged splat data, instance index, visible flag and
## world sphere (x, y, z, r). Returns "bytes" (one uvec4 per drawn instance: first visible splat, count, resource base, instance
## index), "rows", "visible" (the visible total) and "clipped" (the budget cut something: an instance past it is truncated, the
## rest dropped).
static func build(
	counts: PackedInt32Array,
	bases: PackedInt32Array,
	indices: PackedInt32Array,
	visible: PackedByteArray,
	spheres: PackedFloat32Array,
	planes: PackedFloat32Array,
	budget_splats: int
) -> Dictionary:
	var rows := PackedInt32Array()
	var total := 0
	var clipped := false
	for i: int in counts.size():
		if visible[i] == 0:
			continue
		var s := i * 4
		if not sphere_visible(planes, spheres[s], spheres[s + 1], spheres[s + 2], spheres[s + 3]):
			continue
		var count: int = counts[i]
		if total + count > budget_splats:
			clipped = true
			count = budget_splats - total
			if count <= 0:
				break
		rows.append(total)
		rows.append(count)
		rows.append(bases[i])
		rows.append(indices[i])
		total += count
		if clipped:
			break
	return {
		"bytes": rows.to_byte_array(),
		"rows": rows.size() / 4,
		"visible": total,
		"clipped": clipped,
	}
