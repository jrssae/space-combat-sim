class_name ConvexSweep
extends RefCounted
## Whether two convex hit volumes meet while one moves in a straight line (architecture §16 D32, M3-T04), pure. GJK on
## the Minkowski difference between the moving volume swept along its displacement and the other volume, with support functions
## for boxes and capsules: exact (an edge is round to a moving sphere, never a grown square corner) and the same cost at any
## speed (a 10 m move through a 0.6 m plate is one test). Both volumes are given in one frame, the other body's at the start of
## the tick; the mover's rotation during the move is ignored, as in the hit resolver.
##
## The ram resolver shrinks one side by the overlap that counts as a ram (`Convex.of(..., shrink)`: the points at least that
## deep inside the volume), so "they meet" means "a point of one is at least that deep inside the other".

## GJK iterations before giving up (and calling it no meeting); boxes and capsules converge in a handful.
const MAX_ITERATIONS: int = 32


## A box or a capsule placed in some frame.
class Convex extends RefCounted:
	var is_box: bool = true
	## True when shrinking left nothing (a part thinner than twice the shrink).
	var empty: bool = false
	var centre: Vector3 = Vector3.ZERO
	## Box: its axes (orthonormal columns) and half extents.
	var axes: Basis = Basis.IDENTITY
	var half: Vector3 = Vector3.ZERO
	## Capsule: the ends of its axis and its radius.
	var p0: Vector3 = Vector3.ZERO
	var p1: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	## Radius of a sphere round `centre` that holds the volume.
	var reach: float = 0.0
	## The axis-aligned box that holds the volume, in its frame.
	var bounds: AABB = AABB()

	## `shape` (a body's hit volume) placed by `body_to_frame`, keeping only its points at least `shrink` deep inside it.
	static func of(shape: HitShape, body_to_frame: Transform3D, shrink: float = 0.0) -> Convex:
		var convex := Convex.new()
		var xform: Transform3D = body_to_frame * shape.transform
		convex.centre = xform.origin
		if shape.kind == HitShape.Kind.BOX:
			convex.axes = xform.basis.orthonormalized()
			convex.half = shape.half_extents - Vector3.ONE * shrink
			convex.empty = convex.half.x < 0.0 or convex.half.y < 0.0 or convex.half.z < 0.0
			convex.reach = convex.half.length()
		else:
			convex.is_box = false
			convex.p0 = xform * Vector3(0.0, -shape.half_segment, 0.0)
			convex.p1 = xform * Vector3(0.0, shape.half_segment, 0.0)
			convex.radius = shape.radius - shrink
			convex.empty = convex.radius < 0.0
			convex.reach = shape.half_segment + convex.radius
		convex.bounds = convex._bound()
		return convex

	## This volume moved by `xform` (a rigid motion: a pose in another frame).
	func placed(xform: Transform3D) -> Convex:
		var convex := Convex.new()
		convex.is_box = is_box
		convex.empty = empty
		convex.centre = xform * centre
		convex.axes = xform.basis * axes
		convex.half = half
		convex.p0 = xform * p0
		convex.p1 = xform * p1
		convex.radius = radius
		convex.reach = reach
		convex.bounds = convex._bound()
		return convex

	## `bounds` swept along `move`.
	func swept_bounds(move: Vector3) -> AABB:
		return bounds.merge(AABB(bounds.position + move, bounds.size))

	func _bound() -> AABB:
		var low := Vector3(support(Vector3.LEFT).x, support(Vector3.DOWN).y, support(Vector3.FORWARD).z)
		var high := Vector3(support(Vector3.RIGHT).x, support(Vector3.UP).y, support(Vector3.BACK).z)
		return AABB(low, high - low)

	## The point of the volume farthest along `n`.
	func support(n: Vector3) -> Vector3:
		if is_box:
			return (centre + axes.x * (half.x if axes.x.dot(n) >= 0.0 else -half.x)
					+ axes.y * (half.y if axes.y.dot(n) >= 0.0 else -half.y)
					+ axes.z * (half.z if axes.z.dot(n) >= 0.0 else -half.z))
		var end: Vector3 = p1 if (p1 - p0).dot(n) >= 0.0 else p0
		var length: float = n.length()
		return end + n * (radius / length) if length > 0.0 else end


## Cheap first test: the fraction of `move` (0..1) at which `a`'s bounding sphere first reaches `b`'s, or -1 when they never
## come that near. Never later than the volumes' own first touch.
static func spheres_meet(a: Convex, move: Vector3, b: Convex) -> float:
	return SweepMath.segment_sphere(a.centre, a.centre + move, b.centre, a.reach + b.reach)


## Whether `a`, moved in a straight line by `move`, overlaps `b` (fixed) at some point of the move. Touching counts.
static func overlaps(a: Convex, move: Vector3, b: Convex) -> bool:
	if a.empty or b.empty:
		return false
	var direction: Vector3 = b.centre - a.centre - move * 0.5
	if direction.length_squared() < 1e-12:
		direction = Vector3.RIGHT
	var simplex: Array[Vector3] = [_support(a, move, b, direction)]
	direction = -simplex[0]
	for i: int in MAX_ITERATIONS:
		if direction.length_squared() < 1e-14:
			return true  # the origin is on the simplex: touching
		var point: Vector3 = _support(a, move, b, direction)
		if point.dot(direction) < 0.0:
			return false  # nothing of the difference reaches the origin: they never meet
		simplex.append(point)
		direction = _evolve(simplex)
		if direction == Vector3.ZERO:
			return true  # the simplex holds the origin
	return false


# Support of the Minkowski difference (a swept along move) - b.
static func _support(a: Convex, move: Vector3, b: Convex, n: Vector3) -> Vector3:
	var p: Vector3 = a.support(n)
	if move.dot(n) > 0.0:
		p += move
	return p - b.support(-n)


# One GJK step on `simplex` (newest point last): keeps the part nearest the origin and returns the next search direction, or
# zero when the simplex holds the origin.
static func _evolve(simplex: Array[Vector3]) -> Vector3:
	match simplex.size():
		2:
			return _line(simplex)
		3:
			return _triangle(simplex)
	return _tetrahedron(simplex)


static func _line(simplex: Array[Vector3]) -> Vector3:
	var a: Vector3 = simplex[1]
	var b: Vector3 = simplex[0]
	var ab: Vector3 = b - a
	var ao: Vector3 = -a
	if ab.dot(ao) > 0.0:
		return ab.cross(ao).cross(ab)  # zero when the origin is on the segment
	simplex.assign([a])
	return ao


static func _triangle(simplex: Array[Vector3]) -> Vector3:
	var a: Vector3 = simplex[2]
	var b: Vector3 = simplex[1]
	var c: Vector3 = simplex[0]
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var ao: Vector3 = -a
	var abc: Vector3 = ab.cross(ac)
	if abc.cross(ac).dot(ao) > 0.0:
		if ac.dot(ao) > 0.0:
			simplex.assign([c, a])
			return ac.cross(ao).cross(ac)
		simplex.assign([b, a])
		return _line(simplex)
	if ab.cross(abc).dot(ao) > 0.0:
		simplex.assign([b, a])
		return _line(simplex)
	var side: float = abc.dot(ao)
	if side > 0.0:
		return abc
	if side < 0.0:
		simplex.assign([b, c, a])  # wound so that the normal faces the origin
		return -abc
	return Vector3.ZERO  # the origin is in the triangle


static func _tetrahedron(simplex: Array[Vector3]) -> Vector3:
	var a: Vector3 = simplex[3]
	var b: Vector3 = simplex[2]
	var c: Vector3 = simplex[1]
	var d: Vector3 = simplex[0]
	var ao: Vector3 = -a
	if (b - a).cross(c - a).dot(ao) > 0.0:
		simplex.assign([c, b, a])
		return _triangle(simplex)
	if (c - a).cross(d - a).dot(ao) > 0.0:
		simplex.assign([d, c, a])
		return _triangle(simplex)
	if (d - a).cross(b - a).dot(ao) > 0.0:
		simplex.assign([b, d, a])
		return _triangle(simplex)
	return Vector3.ZERO
