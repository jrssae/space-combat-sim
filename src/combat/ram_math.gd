class_name RamMath
extends RefCounted
## Ram damage maths (architecture §16 D32, M3-T04), pure statics. A ram hurts a hull by the velocity change it gives that
## hull's own body, not by the closing speed: a head-on between equal masses at 30 m/s closing changes each ship's velocity
## by about 15 m/s, a 2 t buoy hit at 40 m/s changes a 48 t Starfury's by 1.6 m/s and its own by 38.4 m/s.
##
##     damage = hull_max × clamp((Δv - safe) / (lethal - safe), 0, 1)²
##
## Δv comes from Jolt at ordinary speeds (`contact_dv`: the velocity change a contact caused). When the swept test
## (`ConvexSweep`, shape by shape) finds the hit instead, Δv is the momentum split of a perfectly inelastic hit (`split_dv`): at
## tunnelling speeds (`is_tunnelling`), where Jolt cannot be trusted to see it, and whenever the other body is a prop without a
## physics body. Between two ships the swept test counts only an overlap of at least `RAM_DEPTH_M`.

## One tick of relative motion beyond this share of the smaller core radius is a tunnelling speed (§16 D32).
const TUNNEL_FRACTION: float = 0.5
## m: at tunnelling speed two ships ram when a point of one comes at least this deep inside the other (controller ruling,
## M3-T04). A pass this far clear is never a ram; a shallower clip is left to Jolt.
const RAM_DEPTH_M: float = 0.3


## 0..1, the share of the hull a velocity change of `dv_mps` takes: nothing up to `safe_dv_mps`, all of it from
## `lethal_dv_mps`, quadratic in between. A `lethal_dv_mps` at or below the safe value is a step at the safe value.
static func severity(dv_mps: float, safe_dv_mps: float, lethal_dv_mps: float) -> float:
	if dv_mps <= safe_dv_mps:
		return 0.0
	if lethal_dv_mps <= safe_dv_mps:
		return 1.0
	var x: float = clampf((dv_mps - safe_dv_mps) / (lethal_dv_mps - safe_dv_mps), 0.0, 1.0)
	return x * x


## Hull points a velocity change of `dv_mps` takes from a hull of `hull_max` points.
static func damage(dv_mps: float, safe_dv_mps: float, lethal_dv_mps: float, hull_max: float) -> float:
	return hull_max * severity(dv_mps, safe_dv_mps, lethal_dv_mps)


## The velocity change a contact gave a body: the change from `v_before` (before the contact began) to `v_now` that its own
## forces do not explain. `own_dv` is what those forces (thrust, the environment) added in between: Σ force / mass × dt.
static func contact_dv(v_now: Vector3, v_before: Vector3, own_dv: Vector3) -> float:
	return (v_now - v_before - own_dv).length()


## The velocity change of a body of `m_self` kg when it meets one of `m_other` kg at `relative_speed` and they move on
## together (zero restitution): `relative_speed × m_other / (m_self + m_other)`. The lighter body changes more.
static func split_dv(relative_speed: float, m_self: float, m_other: float) -> float:
	var total: float = m_self + m_other
	if total <= 0.0 or m_other <= 0.0:
		return 0.0
	return relative_speed * m_other / total


## Whether a pair moving at `relative_speed` needs the swept test: one tick of relative motion is more than
## `TUNNEL_FRACTION` of the smaller core radius, so Jolt's discrete step could push one through the other or miss it.
static func is_tunnelling(relative_speed: float, dt: float, core_a: float, core_b: float) -> bool:
	return relative_speed * dt > TUNNEL_FRACTION * minf(core_a, core_b)


## Radius of the largest sphere that fits inside one of `shapes`, wherever it sits: a box's smallest half extent, a capsule's
## radius. How thick the body's solid core is, for the tunnelling threshold (`Damageable.core_radius`); 0 without shapes.
static func core_radius(shapes: Array[HitShape]) -> float:
	var best: float = 0.0
	for shape: HitShape in shapes:
		var inner: float = shape.radius
		if shape.kind == HitShape.Kind.BOX:
			inner = minf(shape.half_extents.x, minf(shape.half_extents.y, shape.half_extents.z))
		best = maxf(best, inner)
	return best
