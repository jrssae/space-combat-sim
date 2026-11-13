class_name EclipseMath
extends RefCounted
## How much of the star's disc a body leaves showing from a point (M6-T10, AC7): the key light's factor in a planet's shadow,
## from positions alone, so no shadow map has to span a planet. Pure, 64-bit.


## The part of the star's disc still seen, 0 to 1. `to_star` and `to_body` are three numbers each, m, from the viewer.
static func lit_fraction(to_star: PackedFloat64Array, star_radius_m: float, to_body: PackedFloat64Array,
		body_radius_m: float) -> float:
	if to_star.size() < 3 or to_body.size() < 3:
		return 1.0
	var star_distance: float = _length(to_star)
	var body_distance: float = _length(to_body)
	if star_distance <= 0.0 or body_distance <= 0.0 or body_distance >= star_distance:
		return 1.0
	var star: float = asin(minf(star_radius_m / star_distance, 1.0))
	var body: float = asin(minf(body_radius_m / body_distance, 1.0))
	return 1.0 - covered_part(star, body, _angle(to_star, to_body))


## The part of a disc of angular radius `star` under a disc of radius `body` whose centre is `apart` away (small angles, rad).
static func covered_part(star: float, body: float, apart: float) -> float:
	if star <= 0.0 or apart >= star + body:
		return 0.0
	if apart <= body - star:
		return 1.0
	if apart <= star - body:
		return (body * body) / (star * star)
	# The lens two crossing circles share.
	var a: float = acos(clampf((apart * apart + star * star - body * body) / (2.0 * apart * star), -1.0, 1.0))
	var b: float = acos(clampf((apart * apart + body * body - star * star) / (2.0 * apart * body), -1.0, 1.0))
	var kite: float = 0.5 * sqrt(maxf((-apart + star + body) * (apart + star - body) * (apart - star + body) * (apart + star + body), 0.0))
	return clampf((star * star * a + body * body * b - kite) / (PI * star * star), 0.0, 1.0)


static func _length(v: PackedFloat64Array) -> float:
	return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


# The angle between two vectors, exact for small angles too (an arc cosine loses them).
static func _angle(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var cx: float = a[1] * b[2] - a[2] * b[1]
	var cy: float = a[2] * b[0] - a[0] * b[2]
	var cz: float = a[0] * b[1] - a[1] * b[0]
	return atan2(sqrt(cx * cx + cy * cy + cz * cz), a[0] * b[0] + a[1] * b[1] + a[2] * b[2])
