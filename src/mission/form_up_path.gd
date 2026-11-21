class_name FormUpPath
extends RefCounted
## A squadron Starfury's way from its hand-off to its slot in the squadron launch (M8-T03, D81): out from the drum, flipping to
## the formation's heading with its engines lit, and settling on its slot at rest against the station.
##
## It lives in the station's frame and runs in radius, angle about the drum's axis and length along it, so the way never cuts
## back inside the drum whatever the arm's angle at the release, and it goes round the side away from the stationary frame's
## spine (`avoid_deg`). Pure: given the seconds since the release it says the pose, velocity, turn rate and which engines burn: all four
## mains light together as the flip ends (the show's launch, M8-T30), the retros before the slot.

## Seconds from the release to the slot, for the flip (nose out to the formation's heading), and the engines' burns: the mains
## from the flip's end, the retros before the slot.
var duration_s: float = 7.0
var flip_s: float = 2.5
var main_s: float = 3.0
var retro_s: float = 2.0

var _pivot: Vector2 = Vector2.ZERO  # the drum's axis in the station's frame (x, y)
var _r: Vector3 = Vector3.ZERO  # radius: start, start rate (m/s), end
var _a: Vector3 = Vector3.ZERO  # angle about the axis (radians): start, start rate, end (unwrapped)
var _z: Vector3 = Vector3.ZERO  # length along the axis: start, start rate, end
var _q0: Quaternion = Quaternion.IDENTITY
var _q1: Quaternion = Quaternion.IDENTITY


## A way from `start` (a station-frame `{transform, velocity}`, the hand-off) to the slot `goal` (station-frame transform), around
## the drum's axis through `pivot` (station frame, along +Z), never across the angle `avoid_deg` (the spine's sector).
static func create(start: Dictionary, goal: Transform3D, pivot: Vector3, avoid_deg: float, p_duration_s: float = 7.0,
		p_flip_s: float = 2.5, p_main_s: float = 3.0, p_retro_s: float = 2.0) -> FormUpPath:
	var made := FormUpPath.new()
	made.duration_s = maxf(p_duration_s, 0.1)
	made.flip_s = clampf(p_flip_s, 0.0, made.duration_s)
	made.main_s = clampf(p_main_s, 0.0, made.duration_s)
	made.retro_s = clampf(p_retro_s, 0.0, made.duration_s - made.main_s)
	made._pivot = Vector2(pivot.x, pivot.y)
	var from: Transform3D = start["transform"]
	var v: Vector3 = start["velocity"]
	var p0 := Vector2(from.origin.x, from.origin.y) - made._pivot
	var p1 := Vector2(goal.origin.x, goal.origin.y) - made._pivot
	var r0: float = maxf(p0.length(), 1e-3)
	var a0: float = p0.angle()
	var radial := Vector2(cos(a0), sin(a0))
	var tangent := Vector2(-sin(a0), cos(a0))
	var vxy := Vector2(v.x, v.y)
	# The end angle on the side that keeps the way off the spine: both ends measured from it, the way runs between them.
	var avoid: float = deg_to_rad(avoid_deg)
	var a1: float = a0 + (fposmod(p1.angle() - avoid, TAU) - fposmod(a0 - avoid, TAU))
	made._r = Vector3(r0, vxy.dot(radial), p1.length())
	made._a = Vector3(a0, vxy.dot(tangent) / r0, a1)
	made._z = Vector3(from.origin.z, v.z, goal.origin.z)
	made._q0 = from.basis.orthonormalized().get_rotation_quaternion()
	made._q1 = goal.basis.orthonormalized().get_rotation_quaternion()
	return made


## The station-frame state `t` seconds after the release: `transform`, `velocity`, `angular` (rad/s), `main` and `retro` (engines
## lit, 0 or 1). From `duration_s` on it holds the slot at rest.
func state_at(t: float) -> Dictionary:
	var s: float = clampf(t / duration_s, 0.0, 1.0)
	var r: Vector2 = _hermite(_r, s)
	var a: Vector2 = _hermite(_a, s)
	var z: Vector2 = _hermite(_z, s)
	var radial := Vector3(cos(a.x), sin(a.x), 0.0)
	var tangent := Vector3(-sin(a.x), cos(a.x), 0.0)
	var point := Vector3(_pivot.x, _pivot.y, 0.0) + radial * r.x + Vector3(0.0, 0.0, z.x)
	var velocity: Vector3 = Vector3.ZERO
	if t < duration_s:
		velocity = radial * r.y + tangent * (r.x * a.y) + Vector3(0.0, 0.0, z.y)
	return {"transform": Transform3D(Basis(_turn(t)), point), "velocity": velocity, "angular": _turn_rate(t),
			"main": 1.0 if t >= flip_s and t < flip_s + main_s and t < duration_s - retro_s else 0.0, "retro": 1.0 if t >= duration_s - retro_s and t < duration_s else 0.0}


## Whether the ship is on its slot.
func done(t: float) -> bool:
	return t >= duration_s


# Value and rate (per second) of a cubic from `h.x` (rate `h.y` per second) to `h.z` at rest, at share `s` of the way.
func _hermite(h: Vector3, s: float) -> Vector2:
	var s2: float = s * s
	var s3: float = s2 * s
	var m0: float = h.y * duration_s
	var value: float = (2.0 * s3 - 3.0 * s2 + 1.0) * h.x + (s3 - 2.0 * s2 + s) * m0 + (-2.0 * s3 + 3.0 * s2) * h.z
	var rate: float = (6.0 * s2 - 6.0 * s) * h.x + (3.0 * s2 - 4.0 * s + 1.0) * m0 + (-6.0 * s2 + 6.0 * s) * h.z
	return Vector2(value, rate / duration_s)


func _turn(t: float) -> Quaternion:
	var w: float = 1.0 if flip_s <= 0.0 else smoothstep(0.0, 1.0, clampf(t / flip_s, 0.0, 1.0))
	return _q0.slerp(_q1, w).normalized()


func _turn_rate(t: float) -> Vector3:
	if t >= flip_s or flip_s <= 0.0 or t < 0.0:
		return Vector3.ZERO
	# The slerp turns about one fixed axis: the whole turn's, at the rate the eased share moves.
	var turn: Quaternion = _q1 * _q0.inverse()
	if turn.w < 0.0:
		turn = -turn
	var angle: float = turn.get_angle()
	if angle < 1e-6:
		return Vector3.ZERO
	var u: float = t / flip_s
	return turn.get_axis().normalized() * angle * (6.0 * u * (1.0 - u) / flip_s)
