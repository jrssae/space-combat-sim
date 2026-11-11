class_name JumpPointPool
extends Node3D
## Open jump points away from any gate (M6-T19, Q12 revised; it replaces M5's `JumpArrival` flash): a fixed set of stand-alone
## `JumpVortex`es, built once at load and reused, so no node enters the tree during play (D22). Missions and encounters open one
## where a ship comes out of hyperspace; it is sized for that ship (`VortexFit.for_ship`) and faces the way it flies, and the ship
## appears in its centre flash, then the funnel unfolds behind it. A ship of the same group arriving close by in the same second
## comes out of the same point, which widens to hold it. With every point open, the oldest is taken back (a new arrival matters
## more than one closing). Sits under `World/Effects` at the identity; its points are shiftable.

const DEFAULT_COUNT: int = 4
## An arrival this close to a point opened in the last `SHARE_S` comes out of that one (a group jumps in through one point).
const SHARE_M: float = 600.0
const SHARE_S: float = 1.0

var world: WorldFrame = null
## Points opened so far (tests, console).
var opened: int = 0

var _points: Array[JumpVortex] = []


## Builds `count` jump points (hidden). Call once, at load.
func prepare(count: int = DEFAULT_COUNT) -> void:
	for i: int in count:
		var point: JumpVortex = JumpVortex.create()
		point.name = "JumpPoint%d" % i
		add_child(point)
		_points.append(point)


## Opens a point (or joins one just opened close by) for a ship of `ship_radius_m` coming out at universe `at`, flying along
## `forward` (World frame), and returns it; null without points. The mouth sits just behind the ship, so it comes out of it.
func open_for(at: UniversePos, forward: Vector3, ship_radius_m: float,
		direction: JumpVortex.Direction = JumpVortex.Direction.ARRIVAL) -> JumpVortex:
	if world == null or _points.is_empty():
		return null
	var ahead: Vector3 = forward.normalized() if forward.length() > 1e-3 else Vector3.FORWARD
	var local: Vector3 = world.universe_to_local(at)
	for point: JumpVortex in _points:
		if point.is_active() and point.direction == direction and point.age_s < SHARE_S \
				and point.position.distance_to(local) < SHARE_M:
			var axis: Vector3 = -point.basis.z.normalized()
			var off: Vector3 = local - point.position
			point.fit.widen_for((off - axis * off.dot(axis)).length(), ship_radius_m)
			return point
	var up: Vector3 = Vector3.UP if absf(ahead.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var mouth: Vector3 = local - ahead * maxf(ship_radius_m, 0.0)
	return open_with(Transform3D(Basis.looking_at(ahead, up), mouth), VortexFit.for_ship(ship_radius_m), direction)


## Opens a point at World-local `xform` (the origin the mouth's centre, -Z the way out) with the size `p_fit`; the oldest point
## is taken back when all are open. Null without points.
func open_with(xform: Transform3D, p_fit: VortexFit, direction: JumpVortex.Direction,
		hold_s: float = VortexTiming.DEFAULT_HOLD_S) -> JumpVortex:
	if _points.is_empty():
		return null
	var chosen: JumpVortex = _points[0]
	for point: JumpVortex in _points:
		if not point.is_active():
			chosen = point
			break
		if point.age_s > chosen.age_s:
			chosen = point
	chosen.stop()
	chosen.open_at(xform, p_fit, direction, hold_s)
	opened += 1
	return chosen


## Points showing now.
func open_count() -> int:
	var n: int = 0
	for point: JumpVortex in _points:
		n += 1 if point.is_active() else 0
	return n


func size() -> int:
	return _points.size()


func points() -> Array[JumpVortex]:
	return _points
