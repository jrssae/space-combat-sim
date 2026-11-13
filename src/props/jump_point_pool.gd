class_name JumpPointPool
extends Node3D
## Open jump points away from any gate (M6-T19, Q12 revised; it replaces M5's `JumpArrival` flash): a fixed set of stand-alone
## `JumpVortex`es, built once at load and reused, so no node enters the tree during play (D22). Missions and encounters open one
## where a ship comes out of hyperspace; it is sized for that ship (`VortexFit.for_ship`) and faces the way it flies, and the ship
## appears in its centre flash, then the funnel unfolds behind it. A ship of the same group arriving close by in the same second
## comes out of the same point, which widens to hold it. With every point open, the oldest is taken back (a new arrival matters
## more than one closing). Sits under `World/Effects` at the identity; its points are shiftable.
##
## Mass arrivals (M6-T20): up to `MAX_POINTS` points, every one sharing the mesh and its colours' materials, reused with nothing
## made while they open and close (their fit and timing are filled in place). The pool draws its points itself, once per frame
## for one camera, and caps their lights to the nearest few (`VortexLod.LIT_POINTS`) and their sounds to a few a second, so a
## wave of a hundred neither floods the light rig nor the mixer.

const DEFAULT_COUNT: int = 4
## The most points one pool holds: the 1 000-ship battle's arrival waves open this many at once.
const MAX_POINTS: int = 100
## At most this many points start their arrival sound in any one second; the rest arrive silently.
const SOUND_VOICES: int = 4
## An arrival this close to a point opened in the last `SHARE_S` comes out of that one (a group jumps in through one point).
const SHARE_M: float = 600.0
const SHARE_S: float = 1.0

var world: WorldFrame = null
## Points opened so far (tests, console).
var opened: int = 0

var _points: Array[JumpVortex] = []
var _cursor: int = 0  # where the search for a free point starts: points free up in the order they opened
var _distances := PackedFloat32Array()
var _drawn: Array[JumpVortex] = []
var _sound_window_s: float = -INF
var _sounds: int = 0


## Builds jump points (hidden) until there are `count`, at most `MAX_POINTS`. Call at load.
func prepare(count: int = DEFAULT_COUNT) -> void:
	for i: int in range(_points.size(), mini(count, MAX_POINTS)):
		var point: JumpVortex = JumpVortex.create()
		point.name = "JumpPoint%d" % i
		point.driven = true
		point.lit = false
		add_child(point)
		_points.append(point)


# Draws the open points for the viewport's camera, and lights the nearest few.
func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var at: Vector3 = camera.global_position if camera != null else Vector3.ZERO
	var px: float = 0.0
	if camera != null:
		px = camera.get_camera_projection().y.y * 0.5 * get_viewport().get_visible_rect().size.y
	_distances.resize(0)
	_drawn.clear()
	for point: JumpVortex in _points:
		if not point.is_active():
			continue
		point.update_visuals_for(at, px)
		_distances.append(at.distance_to(point.global_position))
		_drawn.append(point)
	var lit: PackedInt32Array = VortexLod.lit(_distances)
	for i: int in _drawn.size():
		_drawn[i].lit = lit.has(i)


## Opens a point (or joins one just opened close by) for a ship of `ship_radius_m` coming out at universe `at`, flying along
## `forward` (World frame), and returns it; null without points. The mouth sits just behind the ship, so it comes out of it.
## `share` false always opens a new point (a caller that has grouped its ships already, as the battle's arrivals, then `join`s
## the rest of the group to it).
func open_for(at: UniversePos, forward: Vector3, ship_radius_m: float,
		direction: JumpVortex.Direction = JumpVortex.Direction.ARRIVAL, share: bool = true) -> JumpVortex:
	if world == null or _points.is_empty():
		return null
	var ahead: Vector3 = forward.normalized() if forward.length() > 1e-3 else Vector3.FORWARD
	var local: Vector3 = world.universe_to_local(at)
	if share:
		for point: JumpVortex in _points:
			if point.is_active() and point.direction == direction and point.age_s < SHARE_S \
					and point.position.distance_to(local) < SHARE_M:
				_widen(point, local, ship_radius_m)
				return point
	var up: Vector3 = Vector3.UP if absf(ahead.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var mouth: Vector3 = local - ahead * maxf(ship_radius_m, 0.0)
	var point: JumpVortex = _take()
	var r: float = maxf(VortexFit.POINT_RADII_PER_SHIP * maxf(ship_radius_m, 0.0), VortexFit.MIN_POINT_RADIUS_M)
	point.fit.mouth_radius_m = r
	point.fit.mouth_half_width_m = r
	point.fit.depth_m = r * VortexFit.POINT_DEPTH_RATIO
	point.fit.mouth_z_m = 0.0
	_open(point, Transform3D(Basis.looking_at(ahead, up), mouth), direction, VortexTiming.DEFAULT_HOLD_S)
	return point


## Brings another ship of `point`'s group out of it: a ship of `ship_radius_m` coming out at universe `at`; the mouth widens to
## hold its whole point.
func join(point: JumpVortex, at: UniversePos, ship_radius_m: float) -> void:
	if world != null and point != null:
		_widen(point, world.universe_to_local(at), ship_radius_m)


func _widen(point: JumpVortex, local: Vector3, ship_radius_m: float) -> void:
	var axis: Vector3 = -point.basis.z.normalized()
	var off: Vector3 = local - point.position
	point.fit.widen_for((off - axis * off.dot(axis)).length(), ship_radius_m)


## Opens a point at World-local `xform` (the origin the mouth's centre, -Z the way out) with the size `p_fit`; the oldest point
## is taken back when all are open. Null without points.
func open_with(xform: Transform3D, p_fit: VortexFit, direction: JumpVortex.Direction,
		hold_s: float = VortexTiming.DEFAULT_HOLD_S) -> JumpVortex:
	if _points.is_empty():
		return null
	var chosen: JumpVortex = _take()
	chosen.fit.mouth_radius_m = p_fit.mouth_radius_m
	chosen.fit.mouth_half_width_m = p_fit.mouth_half_width_m
	chosen.fit.depth_m = p_fit.depth_m
	chosen.fit.mouth_z_m = p_fit.mouth_z_m
	_open(chosen, xform, direction, hold_s)
	return chosen


# A point to open: the next free one after the last taken, else the oldest open one, taken back.
func _take() -> JumpVortex:
	var n: int = _points.size()
	for k: int in n:
		var i: int = (_cursor + k) % n
		if not _points[i].is_active():
			_cursor = (i + 1) % n
			return _points[i]
	var oldest: JumpVortex = _points[0]
	for point: JumpVortex in _points:
		if point.age_s > oldest.age_s:
			oldest = point
	oldest.stop()
	return oldest


# Opens `point` (its fit already filled in) at `xform`, sounding only while the second's few voices last.
func _open(point: JumpVortex, xform: Transform3D, direction: JumpVortex.Direction, hold_s: float) -> void:
	var now: float = SimClock.now()
	if now - _sound_window_s >= 1.0:
		_sound_window_s = now
		_sounds = 0
	point.muted = _sounds >= SOUND_VOICES
	_sounds += 0 if point.muted else 1
	point.open_at(xform, point.fit, direction, hold_s)
	opened += 1


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
