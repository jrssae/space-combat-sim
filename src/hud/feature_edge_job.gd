class_name FeatureEdgeJob
extends RefCounted
## One hull's `FeatureEdges` being found a slice at a time (architecture §18.20, M5-T43), pure. The largest hull takes about
## 50 ms in one go, which is several frames, so the preview gives it a couple of milliseconds a frame instead and draws the
## lines when it is done. `step` with no budget finishes it at once; either way the lines are the same.

# Items between looks at the clock.
const _CHUNK: int = 256
# What an edge's entry holds once a second face has come: a smooth pair (not drawn) or a crease.
const _SMOOTH: int = -1
const _CREASE: int = -2
const _UNSEEN: int = -3

var done: bool = false
## Calls of `step` that did work, and the time they took, microseconds: measurements, never gameplay.
var steps: int = 0
var spent_usec: int = 0

var _vertices: PackedVector3Array
var _indices: PackedInt32Array
var _indexed: bool = false
var _min_dot: float = 0.0
var _inv_weld: float = 0.0
var _phase: int = 0
var _at: int = 0
var _welded := PackedInt32Array()
var _cells: Dictionary = {}
# Edge (low * vertex count + high) -> the triangle that first named it, then _SMOOTH or _CREASE once a second has.
var _edges: Dictionary = {}
var _keys: Array = []
var _normals := PackedVector3Array()
var _lines := PackedVector3Array()


## A job on a triangle list; with no `indices` every three vertices are a triangle.
func _init(vertices: PackedVector3Array = PackedVector3Array(), indices: PackedInt32Array = PackedInt32Array(),
		crease_deg: float = FeatureEdges.CREASE_DEG, weld_m: float = FeatureEdges.WELD_M) -> void:
	_vertices = vertices
	_indices = indices
	_indexed = not indices.is_empty()
	_min_dot = cos(deg_to_rad(crease_deg))
	_inv_weld = 1.0 / maxf(weld_m, 1e-9)
	_welded.resize(vertices.size())
	@warning_ignore("integer_division")
	_normals.resize(_corners() / 3)
	done = _corners() < 3


## A job on every triangle surface of `mesh` together (seams between surfaces weld too). A null mesh is done with no lines.
static func for_mesh(mesh: Mesh, crease_deg: float = FeatureEdges.CREASE_DEG, weld_m: float = FeatureEdges.WELD_M) -> FeatureEdgeJob:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for s: int in (mesh.get_surface_count() if mesh != null else 0):
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var surface: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base: int = vertices.size()
		if arrays[Mesh.ARRAY_INDEX] == null:
			for i: int in surface.size():
				indices.append(base + i)
		elif base == 0:
			indices = arrays[Mesh.ARRAY_INDEX]
		else:
			for index: int in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
				indices.append(base + index)
		vertices.append_array(surface)
	return FeatureEdgeJob.new(vertices, indices, crease_deg, weld_m)


## Works for about `budget_usec` (all of it when negative). Returns whether the job is done.
func step(budget_usec: int = -1) -> bool:
	if done:
		return true
	var started: int = Time.get_ticks_usec()
	var until: int = started + budget_usec
	steps += 1
	while not done:
		match _phase:
			0:
				_weld()
			1:
				_faces()
			_:
				_collect()
		if budget_usec >= 0 and Time.get_ticks_usec() >= until:
			break
	spent_usec += Time.get_ticks_usec() - started
	return done


## The edges as line pairs (a0, b0, a1, b1, ...), in the order the triangles first name them; empty until done.
func lines() -> PackedVector3Array:
	return _lines


## How far along it is, 0..1.
func progress() -> float:
	if done:
		return 1.0
	var total: int = maxi(_vertices.size() + _corners() / 3 + _edges.size(), 1)
	return clampf(float(_at + (0 if _phase == 0 else _vertices.size()) + (0 if _phase < 2 else _corners() / 3)) / float(total), 0.0, 1.0)


func _corners() -> int:
	return _indices.size() if _indexed else _vertices.size()


# Each vertex's welded number: the first vertex found in its cell of the weld grid.
func _weld() -> void:
	var end: int = mini(_at + _CHUNK, _vertices.size())
	for i: int in range(_at, end):
		var cell: Vector3i = Vector3i((_vertices[i] * _inv_weld).round())
		var first: int = _cells.get(cell, -1)
		if first < 0:
			_cells[cell] = i
			first = i
		_welded[i] = first
	_at = end
	if _at >= _vertices.size():
		_cells = {}
		_phase = 1
		_at = 0


# Each triangle names its three edges: the second face to name one settles whether it is a crease.
func _faces() -> void:
	var count: int = _vertices.size()
	@warning_ignore("integer_division")
	var triangles: int = _corners() / 3
	var end: int = mini(_at + _CHUNK, triangles)
	for t: int in range(_at, end):
		var base: int = t * 3
		var a: int = _welded[_indices[base] if _indexed else base]
		var b: int = _welded[_indices[base + 1] if _indexed else base + 1]
		var c: int = _welded[_indices[base + 2] if _indexed else base + 2]
		if a == b or b == c or a == c:
			continue
		var normal: Vector3 = (_vertices[b] - _vertices[a]).cross(_vertices[c] - _vertices[a])
		if normal.length_squared() <= 0.0:
			continue
		normal = normal.normalized()
		_normals[t] = normal
		for k: int in 3:
			var lo: int = a if k == 0 else (b if k == 1 else c)
			var hi: int = b if k == 0 else (c if k == 1 else a)
			var key: int = lo * count + hi if lo < hi else hi * count + lo
			var seen: int = _edges.get(key, _UNSEEN)
			if seen == _UNSEEN:
				_edges[key] = t
			elif seen >= 0:
				_edges[key] = _SMOOTH if _normals[seen].dot(normal) >= _min_dot else _CREASE
			else:
				_edges[key] = _CREASE  # a third face: a fin's root, drawn
	_at = end
	if _at >= triangles:
		_keys = _edges.keys()
		_phase = 2
		_at = 0


# The creases, the borders (one face only) and the edges of three faces or more become lines.
func _collect() -> void:
	var count: int = _vertices.size()
	var end: int = mini(_at + _CHUNK, _keys.size())
	for i: int in range(_at, end):
		var key: int = _keys[i]
		if _edges[key] == _SMOOTH:
			continue
		@warning_ignore("integer_division")
		_lines.append(_vertices[key / count])
		_lines.append(_vertices[key % count])
	_at = end
	if _at >= _keys.size():
		_edges = {}
		_keys = []
		_welded = PackedInt32Array()
		_normals = PackedVector3Array()
		done = true
