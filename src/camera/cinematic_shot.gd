class_name CinematicShot
extends RefCounted
## One camera shot of a mission (architecture §18 D55, M5-T08), read from the scenario's `cinematics: {<shot_id>: {keys: [...]}}`.
##
## A key is `{t, position, look_at, fov?}`: `t` is seconds from the start of the shot (increasing), `fov` degrees (default
## `DEFAULT_FOV_DEG`), `roll` degrees about the view axis (default 0, positive turns the picture clockwise). `position` and `look_at` are points: `{actor: <name>, offset?: [x, y, z]}` is an offset in that actor's own
## frame (Godot axes: -z is its nose, +y its top), `{origin: [x, y, z]}` is a universe offset from the scenario's origin, kept in
## 64-bit. `up` (optional) is the picture's up as `{actor: <name>, direction: [x, y, z]}` in that actor's frame, so a shot of something
## turning or tilted stays upright against it (M7-T08: a Cobra arm on the turning drum); without it the world's up. The shot lasts
## until its last key.
##
## Pure: `pose_at` is handed the actors' poses and the origin's local position by the caller, every frame, and keeps nothing
## between calls, so a shot is rebase-proof by construction: shift every pose and the pose moves by the same shift. The camera
## position runs on a Catmull-Rom curve through the keys (with their times, so uneven spacing does not kink it); the look-at
## point and the field of view ease from key to key (smoothstep), so the aim starts and settles gently.

const DEFAULT_FOV_DEG: float = 70.0
const MIN_FOV_DEG: float = 1.0
const MAX_FOV_DEG: float = 179.0


## Where a key puts the camera or its aim: an actor and an offset in its frame, or a universe offset from the scenario origin.
class Point:
	extends RefCounted
	## Empty for an origin point.
	var actor: String = ""
	## Metres in the actor's frame.
	var offset: Vector3 = Vector3.ZERO
	## Metres from the scenario origin (64-bit), for an origin point.
	var universe: PackedFloat64Array = PackedFloat64Array()


class Frame:
	extends RefCounted
	var t: float = 0.0
	var position: Point = null
	var look_at: Point = null
	var fov: float = DEFAULT_FOV_DEG
	var roll: float = 0.0
	## The picture's up: a direction in `up_actor`'s frame; empty actor for the world's up.
	var up_actor: String = ""
	var up_direction: Vector3 = Vector3.UP


## The camera for one instant: a World-local transform (-z looks at the aim point) and the field of view in degrees.
class Pose:
	extends RefCounted
	var transform: Transform3D = Transform3D.IDENTITY
	var fov: float = DEFAULT_FOV_DEG


var id: StringName = &""
var keys: Array[Frame] = []
## Seconds from the start to the last key.
var duration_s: float = 0.0


## Reads a shot from its scenario dictionary: `{ok: true, shot}` or `{ok: false, error}`.
static func from_dict(shot_id: StringName, data: Variant) -> Dictionary:
	var where: String = "cinematics.%s" % shot_id
	if not (data is Dictionary):
		return _failure("%s must be an object with keys" % where)
	var raw_keys: Variant = (data as Dictionary).get("keys")
	if not (raw_keys is Array):
		return _failure("%s.keys must be an array" % where)
	if (raw_keys as Array).is_empty():
		return _failure("%s needs at least one key" % where)
	var shot := CinematicShot.new()
	shot.id = shot_id
	var last_t: float = -INF
	for i: int in (raw_keys as Array).size():
		var key_where: String = "%s.keys[%d]" % [where, i]
		var raw: Variant = (raw_keys as Array)[i]
		if not (raw is Dictionary):
			return _failure("%s must be an object" % key_where)
		var entry: Dictionary = raw
		var t: Variant = entry.get("t")
		if not _is_number(t) or float(t) < 0.0 or float(t) <= last_t:
			return _failure("%s.t must be a number of seconds, 0 or more and after the key before" % key_where)
		var key := Frame.new()
		key.t = float(t)
		last_t = key.t
		for field: String in ["position", "look_at"]:
			var parsed: Variant = _parse_point(entry.get(field), "%s.%s" % [key_where, field])
			if parsed is String:
				return _failure(parsed as String)
			key.set(field, parsed)
		var fov: Variant = entry.get("fov", DEFAULT_FOV_DEG)
		if not _is_number(fov) or float(fov) < MIN_FOV_DEG or float(fov) > MAX_FOV_DEG:
			return _failure("%s.fov must be degrees between %.0f and %.0f" % [key_where, MIN_FOV_DEG, MAX_FOV_DEG])
		key.fov = float(fov)
		var roll: Variant = entry.get("roll", 0.0)
		if not _is_number(roll) or absf(float(roll)) > 180.0:
			return _failure("%s.roll must be degrees between -180 and 180" % key_where)
		key.roll = float(roll)
		if entry.has("up"):
			var up: Variant = entry["up"]
			var direction: Variant = _triple((up as Dictionary).get("direction")) if up is Dictionary else null
			if not (up is Dictionary) or not ((up as Dictionary).get("actor") is String) \
					or ((up as Dictionary)["actor"] as String).strip_edges().is_empty() or direction == null \
					or Vector3(direction[0], direction[1], direction[2]).is_zero_approx():
				return _failure("%s.up must be {actor: <name>, direction: [x, y, z]} (not zero)" % key_where)
			key.up_actor = ((up as Dictionary)["actor"] as String).strip_edges()
			key.up_direction = Vector3(direction[0], direction[1], direction[2]).normalized()
		shot.keys.append(key)
	shot.duration_s = shot.keys[-1].t
	return {"ok": true, "shot": shot}


## Every actor the shot frames or aims at, once each, in order of first use.
func actors() -> PackedStringArray:
	var out := PackedStringArray()
	for key: Frame in keys:
		for point: Point in [key.position, key.look_at]:
			if not point.actor.is_empty() and not out.has(point.actor):
				out.append(point.actor)
		if not key.up_actor.is_empty() and not out.has(key.up_actor):
			out.append(key.up_actor)
	return out


## The camera at `t` seconds into the shot. `actor_pose(name) -> Transform3D or null` gives an actor's World-local pose (null
## when it is not in play); `origin_to_local(offset: PackedFloat64Array) -> Vector3` gives the World-local position of a point
## that far from the scenario origin. Null when the keys either side of `t` cannot be placed (an actor is gone).
func pose_at(t: float, actor_pose: Callable, origin_to_local: Callable) -> Pose:
	var i: int = _segment(t)
	var a: Frame = keys[i]
	var b: Frame = keys[mini(i + 1, keys.size() - 1)]
	var p1: Variant = _place(a.position, actor_pose, origin_to_local)
	var p2: Variant = _place(b.position, actor_pose, origin_to_local)
	var l1: Variant = _place(a.look_at, actor_pose, origin_to_local)
	var l2: Variant = _place(b.look_at, actor_pose, origin_to_local)
	if p1 == null or p2 == null or l1 == null or l2 == null:
		return null
	var span: float = b.t - a.t
	var u: float = clampf((t - a.t) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var position: Vector3 = _curve(i, u, p1 as Vector3, p2 as Vector3, actor_pose, origin_to_local)
	var eased: float = smoothstep(0.0, 1.0, u)
	var pose := Pose.new()
	var up: Vector3 = _up_of(a, actor_pose).lerp(_up_of(b, actor_pose), eased)
	pose.transform = _looking(position, (l1 as Vector3).lerp(l2 as Vector3, eased), up if not up.is_zero_approx() else _up_of(a, actor_pose))
	var roll: float = lerpf(a.roll, b.roll, eased)
	if roll != 0.0:
		# The camera turns the other way about its view axis, so the picture turns clockwise.
		pose.transform.basis = pose.transform.basis * Basis(Vector3.BACK, deg_to_rad(roll))
	pose.fov = lerpf(a.fov, b.fov, eased)
	return pose


# The key that starts the segment holding `t` (the last key once past the end).
func _segment(t: float) -> int:
	for i: int in range(keys.size() - 1):
		if t < keys[i + 1].t:
			return i
	return maxi(keys.size() - 2, 0)


# Catmull-Rom through the segment's two keys, shaped by the keys either side. At the ends, or where a neighbour cannot be placed,
# the missing neighbour mirrors the segment so the curve still runs smoothly.
func _curve(i: int, u: float, p1: Vector3, p2: Vector3, actor_pose: Callable, origin_to_local: Callable) -> Vector3:
	if keys.size() == 1:
		return p1
	var t1: float = keys[i].t
	var t2: float = keys[i + 1].t
	var p0: Variant = _place(keys[i - 1].position, actor_pose, origin_to_local) if i > 0 else null
	var t0: float = keys[i - 1].t if p0 != null else t1 - (t2 - t1)
	if p0 == null:
		p0 = p1 * 2.0 - p2
	var p3: Variant = _place(keys[i + 2].position, actor_pose, origin_to_local) if i + 2 < keys.size() else null
	var t3: float = keys[i + 2].t if p3 != null else t2 + (t2 - t1)
	if p3 == null:
		p3 = p2 * 2.0 - p1
	return p1.cubic_interpolate_in_time(p2, p0 as Vector3, p3 as Vector3, u, t2 - t1, t0 - t1, t3 - t1)


# A key's up in the World: its actor's direction, or the world's up (also when the actor is gone).
static func _up_of(key: Frame, actor_pose: Callable) -> Vector3:
	if key.up_actor.is_empty():
		return Vector3.UP
	var pose: Variant = actor_pose.call(key.up_actor)
	if pose == null:
		return Vector3.UP
	return ((pose as Transform3D).basis * key.up_direction).normalized()


# A camera at `from` aiming at `at`, kept level with `up` unless it looks straight along it.
static func _looking(from: Vector3, at: Vector3, up: Vector3 = Vector3.UP) -> Transform3D:
	var direction: Vector3 = at - from
	if direction.length_squared() < 1e-8:
		return Transform3D(Basis.IDENTITY, from)
	var level: Vector3 = up.normalized()
	if absf(direction.normalized().dot(level)) >= 0.999:
		level = Vector3.BACK if absf(direction.normalized().dot(Vector3.BACK)) < 0.999 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(direction, level), from)


static func _place(point: Point, actor_pose: Callable, origin_to_local: Callable) -> Variant:
	if point.actor.is_empty():
		return origin_to_local.call(point.universe) as Vector3
	var pose: Variant = actor_pose.call(point.actor)
	if pose == null:
		return null
	return (pose as Transform3D) * point.offset


# A point, or why it is not one.
static func _parse_point(raw: Variant, where: String) -> Variant:
	if not (raw is Dictionary):
		return "%s must be an object with an actor or origin" % where
	var d: Dictionary = raw
	if d.has("actor") == d.has("origin"):
		return "%s needs either an actor or origin, not both" % where
	var point := Point.new()
	if d.has("origin"):
		if d.has("offset"):
			return "%s: offset goes with an actor; an origin point is its own offset" % where
		var universe: Variant = _triple(d["origin"])
		if universe == null:
			return "%s.origin must be [x, y, z] metres" % where
		point.universe = universe
		return point
	if not (d["actor"] is String) or (d["actor"] as String).strip_edges().is_empty():
		return "%s.actor must be an actor's name" % where
	point.actor = (d["actor"] as String).strip_edges()
	if d.has("offset"):
		var offset: Variant = _triple(d["offset"])
		if offset == null:
			return "%s.offset must be [x, y, z] metres" % where
		var o: PackedFloat64Array = offset
		point.offset = Vector3(o[0], o[1], o[2])
	return point


static func _triple(raw: Variant) -> Variant:
	if not (raw is Array) or (raw as Array).size() != 3:
		return null
	var out := PackedFloat64Array()
	for v: Variant in raw as Array:
		if not _is_number(v):
			return null
		out.append(float(v))
	return out


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
