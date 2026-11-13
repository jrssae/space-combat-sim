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
##
## Who may open one (M6-T23, `JumpCapability`): a point is opened by a jump-capable ship (`open_for`'s `opener`), which holds it
## while it stays within its hold range of the mouth. Each tick the pool checks its held points (a hundred at most, cheap): one
## whose opener is out of range, destroyed or disabled collapses at once in its closing flash, and every ship in its funnel is
## destroyed (`HitInfo.CAUSE_VORTEX_COLLAPSE`, no kill credit); an opener gone through its own point holds it
## `JumpCapability.OWN_DEPARTURE_HOLD_S` more, then the same. A point with no opener is a debug tool's (the console) or a test's.

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
## Points collapsed so far, the ships they destroyed, and why the last one went (`JumpCapability`'s reasons).
var collapses: int = 0
var collapse_kills: int = 0
var last_collapse: StringName = &""
## Openings refused because the opener cannot open a point.
var refused: int = 0

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
## the rest of the group to it). `opener` is the jump-capable ship that opens and holds it (M6-T23); a ship that cannot open a
## point is refused (null). With no opener the point is a debug tool's, held by nothing.
func open_for(at: UniversePos, forward: Vector3, ship_radius_m: float,
		direction: JumpVortex.Direction = JumpVortex.Direction.ARRIVAL, share: bool = true, opener: Node3D = null) -> JumpVortex:
	if world == null or _points.is_empty():
		return null
	if opener != null and not JumpCapability.can_open(opener):
		refused += 1
		push_warning("JumpPointPool: %s cannot open a jump point; it must use a gate or a capable ship's point" % opener.name)
		return null
	var ahead: Vector3 = forward.normalized() if forward.length() > 1e-3 else Vector3.FORWARD
	var local: Vector3 = world.universe_to_local(at)
	if share:
		for point: JumpVortex in _points:
			if point.is_active() and point.direction == direction and point.age_s < SHARE_S \
					and point.position.distance_to(local) < SHARE_M and (opener == null or point.held):
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
	if opener != null:
		point.hold_by(opener, JumpCapability.hold_range_of(opener))
	return point


# Collapses each held point whose opener has lost it.
func _physics_process(_delta: float) -> void:
	for point: JumpVortex in _points:
		if point.held and point.is_active():
			var why: StringName = hold_verdict(point)
			if why != JumpCapability.HOLDS:
				collapse(point, why)


## Whether `point` still holds, and if not, why (`JumpCapability`'s reasons).
static func hold_verdict(point: JumpVortex) -> StringName:
	var opener: Node3D = point.opener
	var through_s: float = SimClock.now() - point.opener_through_at_s if point.opener_through_at_s >= 0.0 else -1.0
	var alive: bool = opener != null and is_instance_valid(opener)
	if alive and through_s < 0.0 and JumpCapability.is_destroyed(opener):
		return JumpCapability.DESTROYED  # its wreck is taken out of play in the same tick
	var valid: bool = alive and opener.is_inside_tree() \
			and (opener.is_visible_in_tree() or opener.has_meta(TierDirector.TIER_META))  # parked in its pool: gone
	if not valid or through_s >= 0.0:
		return JumpCapability.verdict(valid, false, false, 0.0, 0.0, through_s)
	var at: Vector3 = TierDirector.flying_position(opener)  # a capital parked in the tier still flies its row
	return JumpCapability.verdict(true, JumpCapability.is_destroyed(opener), JumpCapability.is_disabled(opener),
			at.distance_to(point.true_frame().origin), point.hold_range_m)


## Collapses `point` now for `reason`: its closing flash at once, and every ship in its funnel destroyed. Returns the ships killed.
func collapse(point: JumpVortex, reason: StringName) -> int:
	if point == null or not point.is_active():
		return 0
	point.collapse(reason)
	collapses += 1
	last_collapse = reason
	var transits: VortexTransits = VortexTransits.of(world)
	var killed: int = transits.kill_in(point) if transits != null else 0
	collapse_kills += killed
	return killed


## The distance from `point`'s opener to its mouth, m (-1 with no opener in play).
static func opener_distance_m(point: JumpVortex) -> float:
	if point == null or point.opener == null or not is_instance_valid(point.opener) or not point.opener.is_inside_tree():
		return -1.0
	return TierDirector.flying_position(point.opener).distance_to(point.true_frame().origin)


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
## is taken back when all are open. Null without points. `opener` as in `open_for` (none: a debug tool's point).
func open_with(xform: Transform3D, p_fit: VortexFit, direction: JumpVortex.Direction,
		hold_s: float = VortexTiming.DEFAULT_HOLD_S, opener: Node3D = null) -> JumpVortex:
	if _points.is_empty():
		return null
	if opener != null and not JumpCapability.can_open(opener):
		refused += 1
		push_warning("JumpPointPool: %s cannot open a jump point; it must use a gate or a capable ship's point" % opener.name)
		return null
	var chosen: JumpVortex = _take()
	chosen.fit.mouth_radius_m = p_fit.mouth_radius_m
	chosen.fit.mouth_half_width_m = p_fit.mouth_half_width_m
	chosen.fit.depth_m = p_fit.depth_m
	chosen.fit.mouth_z_m = p_fit.mouth_z_m
	_open(chosen, xform, direction, hold_s)
	if opener != null:
		chosen.hold_by(opener, JumpCapability.hold_range_of(opener))
	return chosen


# A point to open: the next free one after the last taken, else the oldest open one, taken back.
func _take() -> JumpVortex:
	var n: int = _points.size()
	for k: int in n:
		var i: int = (_cursor + k) % n
		if not _points[i].is_active():
			_cursor = (i + 1) % n
			return _points[i]
	var oldest: JumpVortex = null  # one that no ship is still flying through, when there is one
	for point: JumpVortex in _points:
		if oldest == null or (point.passing == 0 and oldest.passing > 0) \
				or ((point.passing == 0) == (oldest.passing == 0) and point.age_s > oldest.age_s):
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


## Ends every opening at once, with no close and no collapse, and lets the ships in their funnels go whole (a run's end).
func stop_all() -> void:
	var transits: VortexTransits = VortexTransits.of(world) if world != null else null
	for point: JumpVortex in _points:
		if not point.is_active():
			continue
		if transits != null:
			for body: RigidBody3D in transits.bodies_in(point):
				transits.cancel(body)
		point.stop()


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
