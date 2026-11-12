class_name JumpArrivalPool
extends Node3D
## A fixed set of `JumpArrival`s (architecture §18 D51): built once at load, reused for every arrival, so no node enters the
## tree during play. With every point open, the oldest is reopened (a new arrival matters more than one fading out). Missions
## and (T17) encounters open them through `open_at`. Sits under `World/Effects` at the identity; its points are shiftable.

const DEFAULT_COUNT: int = 4
## An arrival this close to a point opened in the last `SHARE_S` comes out of that one (a group jumps in through one point).
const SHARE_M: float = 600.0
const SHARE_S: float = 1.0

var world: WorldFrame = null
## Points opened so far (tests, console).
var opened: int = 0

var _points: Array[JumpArrival] = []


## Builds `count` jump points (hidden). Call once, at load.
func prepare(count: int = DEFAULT_COUNT) -> void:
	for i: int in count:
		var point := JumpArrival.new()
		point.name = "JumpArrival%d" % i
		add_child(point)
		_points.append(point)


## Opens a point at universe `at` (or reuses one just opened close by) and returns it; null without points.
func open_at(at: UniversePos, radius_m: float = 40.0) -> JumpArrival:
	if world == null or _points.is_empty():
		return null
	var local: Vector3 = world.universe_to_local(at)
	var oldest: JumpArrival = _points[0]
	for point: JumpArrival in _points:
		if point.is_open() and point.age_s() < SHARE_S and point.position.distance_to(local) < SHARE_M:
			return point
	for point: JumpArrival in _points:
		if not point.is_open():
			oldest = point
			break
		if point.age_s() > oldest.age_s():
			oldest = point
	oldest.open(local, radius_m)
	opened += 1
	return oldest


## Points showing now.
func open_count() -> int:
	var n: int = 0
	for point: JumpArrival in _points:
		n += 1 if point.is_open() else 0
	return n


func size() -> int:
	return _points.size()
