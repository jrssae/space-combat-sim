class_name DockKeepOut
extends RefCounted
## The way round the station to the docking lane for a ship flown by the docking autopilot (M8-T06). Pure, in the station's
## frame: the station's solids near the bay as boxes (`data/station/docking.json`), a goal on the lane, and for any point the
## next place to fly to so the straight line there meets no box.
##
## Built once: the corners of every box grown by `via_m` are the turning points; each knows its shortest clear way to the goal.
## Lines are tested against the boxes grown by `clear_m` (less than `via_m`, so a ship a little off its line still sees its
## next corner). A ship that drifted inside a grown box is sent straight out of it first.

## A ship this near a turning point flies on to the one after it, metres.
const ARRIVE_M: float = 20.0
const EPS: float = 0.001

var boxes: Array[AABB] = []
var clear_m: float = 35.0
var via_m: float = 60.0
var goal: Vector3 = Vector3.ZERO
## The turning points, each one's way on (an index, or -1 for the goal) and what is left from it to the goal, metres.
var nodes: PackedVector3Array = PackedVector3Array()
var _next: PackedInt32Array = PackedInt32Array()
var _cost: PackedFloat64Array = PackedFloat64Array()
var _grown: Array[AABB] = []


static func build(p_boxes: Array[AABB], p_goal: Vector3, p_clear_m: float, p_via_m: float) -> DockKeepOut:
	var out := DockKeepOut.new()
	out.boxes = p_boxes
	out.goal = p_goal
	out.clear_m = maxf(p_clear_m, 0.0)
	out.via_m = maxf(p_via_m, out.clear_m + 1.0)
	for box: AABB in p_boxes:
		out._grown.append(box.grow(out.clear_m))
	out._lay_nodes()
	out._solve()
	return out


## Boxes from data: each `{"min": [x, y, z], "max": [x, y, z]}`; entries that are not that are skipped.
static func boxes_from(raw: Variant) -> Array[AABB]:
	var out: Array[AABB] = []
	if not (raw is Array):
		return out
	for entry: Variant in raw as Array:
		if not (entry is Dictionary):
			continue
		var lo: Variant = (entry as Dictionary).get("min")
		var hi: Variant = (entry as Dictionary).get("max")
		if not (lo is Array and hi is Array and (lo as Array).size() == 3 and (hi as Array).size() == 3):
			continue
		var a := Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
		var b := Vector3(float(hi[0]), float(hi[1]), float(hi[2]))
		out.append(AABB(a, b - a).abs())
	return out


## Where a ship at `from` flies to next on its way to the goal.
func next_target(from: Vector3) -> Vector3:
	var held: int = inside(from)
	if held >= 0:
		return _way_out(from, held)
	if not blocked(from, goal):
		return goal
	var best: int = -1
	var best_cost: float = INF
	for i: int in nodes.size():
		if _cost[i] == INF or blocked(from, nodes[i]):
			continue
		var gap: float = from.distance_to(nodes[i])
		if gap < ARRIVE_M:
			return goal if _next[i] < 0 else nodes[_next[i]]
		if gap + _cost[i] < best_cost:
			best_cost = gap + _cost[i]
			best = i
	return nodes[best] if best >= 0 else goal


## Metres left to the goal along the way `next_target` flies from `from` (INF when no way is known).
func distance_left(from: Vector3) -> float:
	if not blocked(from, goal):
		return from.distance_to(goal)
	var best: float = INF
	for i: int in nodes.size():
		if _cost[i] < INF and not blocked(from, nodes[i]):
			best = minf(best, from.distance_to(nodes[i]) + _cost[i])
	return best


## The grown box `point` lies in, or -1.
func inside(point: Vector3) -> int:
	for i: int in _grown.size():
		if _grown[i].has_point(point):
			return i
	return -1


## Whether the straight line from `a` to `b` meets a grown box.
func blocked(a: Vector3, b: Vector3) -> bool:
	for box: AABB in _grown:
		if _segment_meets(a, b, box):
			return true
	return false


# The corners of the boxes grown by `via_m` that lie in the open.
func _lay_nodes() -> void:
	for box: AABB in boxes:
		var wide: AABB = box.grow(via_m)
		for k: int in 8:
			var corner: Vector3 = wide.get_endpoint(k)
			if inside(corner) < 0:
				nodes.append(corner)


# Each turning point's shortest clear way to the goal (Dijkstra from the goal over the clear lines).
func _solve() -> void:
	var n: int = nodes.size()
	_next.resize(n)
	_cost.resize(n)
	_cost.fill(INF)
	_next.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	for i: int in n:
		if not blocked(nodes[i], goal):
			_cost[i] = nodes[i].distance_to(goal)
	for _round: int in n:
		var at: int = -1
		for i: int in n:
			if done[i] == 0 and _cost[i] < INF and (at < 0 or _cost[i] < _cost[at]):
				at = i
		if at < 0:
			break
		done[at] = 1
		for j: int in n:
			if done[j] != 0:
				continue
			var through: float = _cost[at] + nodes[at].distance_to(nodes[j])
			if through < _cost[j] and not blocked(nodes[at], nodes[j]):
				_cost[j] = through
				_next[j] = at


# Straight out through the nearest face of grown box `index`, as far as the turning points stand off.
func _way_out(from: Vector3, index: int) -> Vector3:
	var box: AABB = _grown[index]
	var step: float = via_m - clear_m
	var best := from
	var least: float = INF
	for axis: int in 3:
		var low: float = from[axis] - box.position[axis]
		var high: float = box.end[axis] - from[axis]
		for side: int in 2:
			var depth: float = low if side == 0 else high
			if depth >= least:
				continue
			var out: Vector3 = from
			out[axis] = (box.position[axis] - step) if side == 0 else (box.end[axis] + step)
			# Never out of one box into another's solid.
			if _in_solid(out):
				continue
			least = depth
			best = out
	return best


func _in_solid(point: Vector3) -> bool:
	for box: AABB in boxes:
		if box.has_point(point):
			return true
	return false


# Slab test: whether the segment passes through the box's inside (touching a face does not count).
static func _segment_meets(a: Vector3, b: Vector3, box: AABB) -> bool:
	var t0: float = 0.0
	var t1: float = 1.0
	var d: Vector3 = b - a
	for axis: int in 3:
		var lo: float = box.position[axis] + EPS
		var hi: float = box.end[axis] - EPS
		if absf(d[axis]) < 1e-9:
			if a[axis] <= lo or a[axis] >= hi:
				return false
			continue
		var near: float = (lo - a[axis]) / d[axis]
		var far: float = (hi - a[axis]) / d[axis]
		if near > far:
			var swap: float = near
			near = far
			far = swap
		t0 = maxf(t0, near)
		t1 = minf(t1, far)
		if t0 > t1:
			return false
	return true
