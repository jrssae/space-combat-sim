class_name HitShape
extends RefCounted
## One hit volume of a ship (architecture §15.4, §15.5): a box or a capsule placed in the ship's body frame. Built
## from one `Hardpoints.collision` entry, so the volumes that stop a bolt are the ones Jolt collides with. Pure: no
## scene tree. `Damageable` keeps an array of these; `HitResolver` calls `sweep` with the bolt's segment already
## expressed in the target's body frame.
##
## The shape's own frame is the one `SweepMath` expects: a box is centred on the origin and axis-aligned, a capsule
## has its axis along local Y. `transform` places that frame in the body frame (for a capsule it already holds the
## turn that lays the axis along the named x, y or z, see `Hardpoints.capsule_axis_basis`).

enum Kind { BOX, CAPSULE }

var kind: Kind = Kind.BOX
## Name from `hardpoints.json` ("fuselage", "pod_ur"), for logs and tests.
var shape_name: String = ""
## Body frame <- shape frame. Setting it refreshes the cached inverse used by `sweep`.
var transform: Transform3D = Transform3D.IDENTITY:
	set(value):
		transform = value
		_inverse = value.affine_inverse()
## Box: half the size on each local axis.
var half_extents: Vector3 = Vector3.ZERO
## Capsule: radius of the axis cylinder and of the end spheres.
var radius: float = 0.0
## Capsule: the axis runs from -`half_segment` to +`half_segment` on local Y (height / 2 - radius).
var half_segment: float = 0.0

var _inverse: Transform3D = Transform3D.IDENTITY


## A box of full `size` (BoxShape3D.size) placed at `xform`.
static func make_box(xform: Transform3D, size: Vector3, p_name: String = "") -> HitShape:
	var shape := HitShape.new()
	shape.kind = Kind.BOX
	shape.shape_name = p_name
	shape.transform = xform
	shape.half_extents = (size * 0.5).abs()
	return shape


## A capsule of `p_radius` and full `height` (CapsuleShape3D.height, caps included) with its axis on local Y,
## placed at `xform`. A height below 2 * radius is a sphere.
static func make_capsule(xform: Transform3D, p_radius: float, height: float, p_name: String = "") -> HitShape:
	var shape := HitShape.new()
	shape.kind = Kind.CAPSULE
	shape.shape_name = p_name
	shape.transform = xform
	shape.radius = maxf(p_radius, 0.0)
	shape.half_segment = maxf(height * 0.5 - shape.radius, 0.0)
	return shape


## From one `Hardpoints.collision` entry (`name`, `shape`, `transform`). Returns null when the entry holds anything
## but a `BoxShape3D` or a `CapsuleShape3D`.
static func from_collision(entry: Dictionary) -> HitShape:
	var xform: Transform3D = entry.get("transform", Transform3D.IDENTITY)
	var p_name: String = str(entry.get("name", ""))
	var source: Variant = entry.get("shape")
	if source is BoxShape3D:
		return make_box(xform, (source as BoxShape3D).size, p_name)
	if source is CapsuleShape3D:
		var capsule: CapsuleShape3D = source
		return make_capsule(xform, capsule.radius, capsule.height, p_name)
	return null


## Entry fraction (0 when `a_body` is inside, -1 for no hit; see `SweepMath`) of the segment `a_body` -> `b_body`,
## given in the ship's body frame, against this shape grown by `inflate` (the bolt's hit radius). A box grows by
## `inflate` on each half extent (conservative at edges and corners); a capsule grows exactly.
func sweep(a_body: Vector3, b_body: Vector3, inflate: float = 0.0) -> float:
	var a_local: Vector3 = _inverse * a_body
	var b_local: Vector3 = _inverse * b_body
	if kind == Kind.BOX:
		return SweepMath.segment_box(a_local, b_local, half_extents, inflate)
	return SweepMath.segment_capsule(a_local, b_local, half_segment, radius + inflate)


## Distance from the body origin to the farthest point of the shape: a sphere of this radius around the origin
## holds the whole volume (the broad-phase bounding radius).
func extent_radius() -> float:
	if kind == Kind.BOX:
		var farthest: float = 0.0
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var corner: Vector3 = transform * Vector3(half_extents.x * sx, half_extents.y * sy,
							half_extents.z * sz)
					farthest = maxf(farthest, corner.length())
		return farthest
	var top: Vector3 = transform * Vector3(0.0, half_segment, 0.0)
	var bottom: Vector3 = transform * Vector3(0.0, -half_segment, 0.0)
	return maxf(top.length(), bottom.length()) + radius


## True when the body-frame point `p_body` is inside the shape grown by `inflate` (surface counts as inside).
func contains(p_body: Vector3, inflate: float = 0.0) -> bool:
	var p: Vector3 = _inverse * p_body
	if kind == Kind.BOX:
		return (absf(p.x) <= half_extents.x + inflate and absf(p.y) <= half_extents.y + inflate
				and absf(p.z) <= half_extents.z + inflate)
	var nearest_y: float = clampf(p.y, -half_segment, half_segment)
	var limit: float = maxf(radius + inflate, 0.0)
	return p.x * p.x + p.z * p.z + (p.y - nearest_y) * (p.y - nearest_y) <= limit * limit
