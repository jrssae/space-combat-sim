class_name BotMeshField
extends RefCounted
## Test helper (M7-T11): how far a point is from a piece's drawn triangles. A grid of cells holds each triangle's index so a query
## only measures the triangles near it (the station's pieces have 25 000 to 30 000).

const CELL_M: float = 128.0

var _a := PackedVector3Array()
var _b := PackedVector3Array()
var _c := PackedVector3Array()
var _low := PackedVector3Array()
var _high := PackedVector3Array()
var _cells: Dictionary[Vector3i, PackedInt32Array] = {}


## The field of a triangle soup (`faces`: three points a triangle, as `Mesh.get_faces` gives).
static func of_faces(faces: PackedVector3Array) -> BotMeshField:
	var field := BotMeshField.new()
	for i: int in range(0, faces.size() - 2, 3):
		field._add(faces[i], faces[i + 1], faces[i + 2])
	return field


## The faces of every mesh in a glb of the station's assets, in the glb's own frame.
static func faces_of_glb(path: String) -> PackedVector3Array:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var out := PackedVector3Array()
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var inst := node as MeshInstance3D
		var xf: Transform3D = inst.transform
		var parent: Node = inst.get_parent()
		while parent != null and parent != scene:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		for p: Vector3 in inst.mesh.get_faces():
			out.append(xf * p)
	scene.free()
	return out


## The faces of collision `entries` (`Hardpoints.load_collision_only`: boxes, and capsules as their bounding boxes) moved by `xf`.
static func faces_of_collision(entries: Array[Dictionary], xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for entry: Dictionary in entries:
		var size := Vector3.ZERO
		if entry["shape"] is BoxShape3D:
			size = (entry["shape"] as BoxShape3D).size
		elif entry["shape"] is CapsuleShape3D:
			var capsule := entry["shape"] as CapsuleShape3D
			size = Vector3(2.0 * capsule.radius, capsule.height, 2.0 * capsule.radius)
		else:
			continue
		var local: Transform3D = xf * (entry["transform"] as Transform3D)
		var c: Array[Vector3] = []
		for i: int in 8:
			c.append(local * (Vector3(size.x if i & 1 else -size.x, size.y if i & 2 else -size.y, size.z if i & 4 else -size.z) * 0.5))
		for quad: Array in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
			out.append_array([c[quad[0]], c[quad[1]], c[quad[2]], c[quad[0]], c[quad[2]], c[quad[3]]])
	return out


func triangle_count() -> int:
	return _a.size()


## The least distance of `point` to any triangle, up to `reach_m` (farther reads as `reach_m`).
func distance(point: Vector3, reach_m: float) -> float:
	var best: float = reach_m
	var lo: Vector3i = _cell(point - Vector3.ONE * reach_m)
	var hi: Vector3i = _cell(point + Vector3.ONE * reach_m)
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var list: PackedInt32Array = _cells.get(Vector3i(x, y, z), PackedInt32Array())
				for t: int in list:
					var margin: float = best
					var l: Vector3 = _low[t]
					var h: Vector3 = _high[t]
					if point.x < l.x - margin or point.x > h.x + margin or point.y < l.y - margin or point.y > h.y + margin \
							or point.z < l.z - margin or point.z > h.z + margin:
						continue
					best = minf(best, point.distance_to(closest_point(point, _a[t], _b[t], _c[t])))
	return best


## The point of triangle `a b c` nearest `p` (Ericson, Real-Time Collision Detection).
static func closest_point(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var ap: Vector3 = p - a
	var d1: float = ab.dot(ap)
	var d2: float = ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp: Vector3 = p - b
	var d3: float = ab.dot(bp)
	var d4: float = ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc: float = d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp: Vector3 = p - c
	var d5: float = ab.dot(cp)
	var d6: float = ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb: float = d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va: float = d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom: float = 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


func _add(a: Vector3, b: Vector3, c: Vector3) -> void:
	var index: int = _a.size()
	_a.append(a)
	_b.append(b)
	_c.append(c)
	var lo: Vector3 = a.min(b).min(c)
	var hi: Vector3 = a.max(b).max(c)
	_low.append(lo)
	_high.append(hi)
	var cell_lo: Vector3i = _cell(lo)
	var cell_hi: Vector3i = _cell(hi)
	for x: int in range(cell_lo.x, cell_hi.x + 1):
		for y: int in range(cell_lo.y, cell_hi.y + 1):
			for z: int in range(cell_lo.z, cell_hi.z + 1):
				var key := Vector3i(x, y, z)
				var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
				list.append(index)
				_cells[key] = list


func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL_M), floori(p.y / CELL_M), floori(p.z / CELL_M))
