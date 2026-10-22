class_name InterceptMath
extends RefCounted
## Lead solution for bolts that inherit the shooter's velocity (architecture §15.8, §15.15), pure. The HUD's lead
## reticle and the AI's aim point both call `solve`, so they cannot disagree.
##
## A bolt leaves the shooter at `bolt_speed` relative to the shooter and keeps the shooter's velocity, so in the
## shooter's frame it flies straight at `bolt_speed` and the target at the relative velocity u = v_t - v_s. With
## r = p_t - p_s the bolt meets the target at the smallest t > 0 where |r + u t| = s t:
##
##     (u·u - s²) t² + 2 (r·u) t + r·r = 0
##
## Differences are taken in 64-bit (as in `TargetingSystem`), so positions near 1e4 m keep their precision.

## |u·u - s²| below this fraction of s² is treated as a linear equation (the target runs at bolt speed).
const LINEAR_EPSILON: float = 1e-9


## Returns `{ok: bool, t: float, aim_dir: Vector3, lead_point: Vector3}`.
## - `ok`: a meeting exists at `t` in (0, `max_time`]. False when the target outruns the bolt, the bolt flies too
##   slowly or `bolt_speed` is not positive, the target sits on the shooter, or `t` exceeds `max_time` (pass the
##   bolt lifetime).
## - `t`: seconds until the meeting.
## - `aim_dir`: unit vector to fire along, in the same frame as the positions. The bolt's world velocity is then
##   `shooter_vel + aim_dir * bolt_speed`.
## - `lead_point`: `target_pos + (target_vel - shooter_vel) * t`, the point the reticle goes on: the line from the
##   shooter through it is the aim line, whatever the shooter's own velocity is.
## Without a solution `t` is -1, `lead_point` is `target_pos` and `aim_dir` the direct line of sight (zero when the
## target is on the shooter), so a caller that ignores `ok` still aims at the target.
static func solve(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3,
		bolt_speed: float, max_time: float) -> Dictionary:
	var rx: float = float(target_pos.x) - float(shooter_pos.x)
	var ry: float = float(target_pos.y) - float(shooter_pos.y)
	var rz: float = float(target_pos.z) - float(shooter_pos.z)
	var ux: float = float(target_vel.x) - float(shooter_vel.x)
	var uy: float = float(target_vel.y) - float(shooter_vel.y)
	var uz: float = float(target_vel.z) - float(shooter_vel.z)
	var rr: float = rx * rx + ry * ry + rz * rz
	var t: float = _meeting_time(rr, rx * ux + ry * uy + rz * uz, ux * ux + uy * uy + uz * uz, bolt_speed)
	if not (t > 0.0 and t <= max_time):
		return _no_solution(target_pos, rx, ry, rz, rr)

	var st: float = bolt_speed * t
	var dx: float = (rx + ux * t) / st
	var dy: float = (ry + uy * t) / st
	var dz: float = (rz + uz * t) / st
	var length: float = sqrt(dx * dx + dy * dy + dz * dz)  # 1 up to rounding; renormalised in 64-bit
	return {
		"ok": true,
		"t": t,
		"aim_dir": Vector3(dx / length, dy / length, dz / length),
		"lead_point": Vector3(float(target_pos.x) + ux * t, float(target_pos.y) + uy * t,
				float(target_pos.z) + uz * t),
	}


# Smallest positive root of (uu - s²) t² + 2 ru t + rr = 0, or -1 when there is none.
static func _meeting_time(rr: float, ru: float, uu: float, bolt_speed: float) -> float:
	if not (bolt_speed > 0.0) or not (rr > 0.0):
		return -1.0
	var qa: float = uu - bolt_speed * bolt_speed
	var qb: float = 2.0 * ru
	if absf(qa) <= LINEAR_EPSILON * bolt_speed * bolt_speed:
		# The target moves at bolt speed relative to the shooter: qb t + rr = 0, solvable only while it closes.
		return -rr / qb if qb < 0.0 else -1.0
	var disc: float = qb * qb - 4.0 * qa * rr
	if not (disc >= 0.0):
		return -1.0
	# Cancellation-free pair of roots: q / qa and rr / q.
	var root: float = sqrt(disc)
	var q: float = -0.5 * ((qb + root) if qb >= 0.0 else (qb - root))
	if q == 0.0:
		return -1.0
	var first: float = q / qa
	var second: float = rr / q
	var best: float = -1.0
	for candidate: float in [first, second]:
		if candidate > 0.0 and (best < 0.0 or candidate < best):
			best = candidate
	return best


static func _no_solution(target_pos: Vector3, rx: float, ry: float, rz: float, rr: float) -> Dictionary:
	var sight: Vector3 = Vector3.ZERO
	if rr > 0.0:
		var length: float = sqrt(rr)
		sight = Vector3(rx / length, ry / length, rz / length)
	return {"ok": false, "t": -1.0, "aim_dir": sight, "lead_point": target_pos}
