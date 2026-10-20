class_name SweepMath
extends RefCounted
## Swept segment tests against a sphere, an axis-aligned box and a capsule (architecture §15.5), pure statics.
## The hit resolver moves a bolt into its target's frame, so a bolt that travelled 23 m in one tick is a straight
## segment `a` -> `b` and these functions give the first point of that segment inside the volume.
##
## Every function returns the entry fraction `t` in [0, 1] (the entry point is `a + t * (b - a)`): 0 when `a` is
## already inside the volume, -1 for no hit. A segment that only touches the surface counts as a hit. NaN inputs
## give -1.
##
## Vector3 components are float32; the intermediate maths here uses the components one by one as 64-bit script
## floats, so nothing is lost to float32 products of values near 1e4. The quadratics use the cancellation-free root
## `2C / (-B + sqrt(B² - 4AC))` for the entry (the textbook `(-B - sqrt(disc)) / 2A` for B < 0, rewritten): it
## stays exact for short segments, where A is tiny.


## First contact of the segment `a` -> `b` with the sphere at `c` of radius `r`.
static func segment_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> float:
	var r_pos: float = maxf(r, 0.0)
	var mx: float = a.x - c.x
	var my: float = a.y - c.y
	var mz: float = a.z - c.z
	var cc: float = mx * mx + my * my + mz * mz - r_pos * r_pos
	if cc <= 0.0:
		return 0.0
	var dx: float = b.x - a.x
	var dy: float = b.y - a.y
	var dz: float = b.z - a.z
	var qa: float = dx * dx + dy * dy + dz * dz
	if qa <= 0.0:
		return -1.0
	var qb: float = 2.0 * (mx * dx + my * dy + mz * dz)
	return _entry_root(qa, qb, cc)


## First contact of the segment `a` -> `b` with the axis-aligned box centred on the origin with half extents
## `half_extents + inflate` (a slab test in the box's own frame). A negative total extent on any axis is an empty
## box. Inflating by the bolt's radius is conservative at edges and corners (§15.5).
static func segment_box(a: Vector3, b: Vector3, half_extents: Vector3, inflate: float = 0.0) -> float:
	var t_enter: float = 0.0
	var t_exit: float = 1.0
	for axis: int in 3:
		var half: float = half_extents[axis] + inflate
		if not (half >= 0.0):
			return -1.0
		var start: float = a[axis]
		var delta: float = float(b[axis]) - start
		if delta == 0.0:
			if absf(start) > half:
				return -1.0  # parallel to this slab and outside it
			continue
		var t_near: float = (-half - start) / delta
		var t_far: float = (half - start) / delta
		if t_near > t_far:
			var swap: float = t_near
			t_near = t_far
			t_far = swap
		t_enter = maxf(t_enter, t_near)
		t_exit = minf(t_exit, t_far)
		if t_enter > t_exit:
			return -1.0
	if is_nan(t_enter) or is_nan(t_exit):
		return -1.0
	return t_enter


## First contact of the segment `a` -> `b` with the capsule whose axis is the local Y segment from -`half_segment`
## to +`half_segment` (Godot's `CapsuleShape3D` convention; `half_segment` = height / 2 - radius) and whose
## surface is `radius` from that axis.
##
## The capsule is a finite cylinder plus two end spheres. The cylinder's side is entered where the segment crosses
## the infinite cylinder, if that point lies within the axis range. A segment that reaches the cylinder through a
## cap plane has already crossed the end sphere (the cap disc is the sphere's equator), so the two sphere tests
## cover it.
static func segment_capsule(a: Vector3, b: Vector3, half_segment: float, radius: float) -> float:
	var h: float = maxf(half_segment, 0.0)
	var r: float = maxf(radius, 0.0)
	var ax: float = a.x
	var ay: float = a.y
	var az: float = a.z
	var nearest_y: float = clampf(ay, -h, h)
	var from_axis_sq: float = ax * ax + az * az + (ay - nearest_y) * (ay - nearest_y)
	if from_axis_sq <= r * r:
		return 0.0

	var best: float = -1.0
	var dx: float = float(b.x) - ax
	var dy: float = float(b.y) - ay
	var dz: float = float(b.z) - az
	var side_a: float = dx * dx + dz * dz
	if side_a > 0.0:
		var side_c: float = ax * ax + az * az - r * r
		if side_c > 0.0:  # starting inside the infinite cylinder means the caps/spheres decide
			var side_t: float = _entry_root(side_a, 2.0 * (ax * dx + az * dz), side_c)
			if side_t >= 0.0 and absf(ay + side_t * dy) <= h:
				best = side_t
	for end_y: float in [-h, h]:
		var cap_t: float = segment_sphere(a, b, Vector3(0.0, end_y, 0.0), r)
		if cap_t >= 0.0 and (best < 0.0 or cap_t < best):
			best = cap_t
	return best


# Smallest root in [0, 1] of A t² + B t + C = 0 for a start outside the volume (C > 0): the entry of a segment
# moving towards it. Roots share a sign (their product C / A is positive), so none exists unless B < 0 and the
# discriminant is non-negative. The comparisons are written so that NaN falls through to "no hit".
static func _entry_root(qa: float, qb: float, qc: float) -> float:
	if not (qb < 0.0):
		return -1.0
	var disc: float = qb * qb - 4.0 * qa * qc
	if not (disc >= 0.0):
		return -1.0
	var t: float = 2.0 * qc / (-qb + sqrt(disc))
	if t >= 0.0 and t <= 1.0:
		return t
	return -1.0
