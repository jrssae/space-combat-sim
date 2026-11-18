class_name BoltShape
extends RefCounted
## The bolts' teardrop mesh (M7-T52): a dim envelope round a short bright core, each a round head at the bolt's own place with a
## tail tapering to a point behind it, so a bolt reads as a shot in flight rather than a rod and its head burns whiter. The head
## points down -Y, which `projectile.tscn`'s turn of the bolt puts along the flight (`BoltMesh.flight_axis`).
##
## The bolt materials cull front faces, so a pixel shows the far walls, and inside the envelope the core's is the nearer one. Drawn
## additive (SMAA), a core pixel adds the core, weighted by its vertex alpha, to the envelope; drawn opaque for TAA's motion vectors
## (`BoltMesh`), alpha is ignored and it shows the core alone. The core's colour is that sum, so the core shows in both draws.
## Vertex colours stop at 1, so the bolt materials' albedo is `PEAK` times the bolt's colour.
##
## A bolt is drawn shortened along its flight until it has flown its tail's length, so the tail never reaches back behind its
## muzzle (M7-T52 fix round): the core scales the multimesh instances (`bolt_transforms`), `Projectile` its own node.

## Sides round the drop; a bolt is small on screen, so few are needed.
const SIDES: int = 10
## Rings over the head's front half and along the tail.
const HEAD_RINGS: int = 4
const TAIL_RINGS: int = 8
## The head's radius against the look's bolt radius, and the whole drop's length against the look's bolt length.
const HEAD_SCALE: float = 2.0
const LENGTH_SCALE: float = 1.4
## How fast the tail narrows (1 a straight cone, more a thinner comet tail), and how fast its glow fades toward the tip.
const TAPER: float = 1.6
const FADE: float = 1.5
## The core against the envelope (radius and tail length).
const CORE_RADIUS: float = 0.5
const CORE_LENGTH: float = 0.45
## The head's brightness against the bolt's colour (the bolt materials' albedo over their emission), and the envelope's.
const PEAK: float = 1.4
const ENVELOPE_BRIGHTNESS: float = 0.4


## The teardrop for a look of `length_m` and `radius_m` (a weapon's `bolt_length_m` and `bolt_radius_m`).
static func mesh(length_m: float, radius_m: float) -> ArrayMesh:
	var head: float = head_radius(radius_m)
	var tail: float = tail_length(length_m, radius_m)
	var arrays: Array = _empty()
	_drop(arrays, head, tail, false)
	_drop(arrays, head * CORE_RADIUS, tail * CORE_LENGTH, true)
	_point_down(arrays)
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## The envelope's head radius for a look of `radius_m`.
static func head_radius(radius_m: float) -> float:
	return radius_m * HEAD_SCALE


## The drop's length, nose to tail tip, for a look of `length_m` and `radius_m`.
static func total_length(length_m: float, radius_m: float) -> float:
	return maxf(length_m * LENGTH_SCALE, 2.0 * head_radius(radius_m))


## How far the drop reaches behind the bolt's place (its head's centre) for a look of `length_m` and `radius_m`.
static func tail_length(length_m: float, radius_m: float) -> float:
	return total_length(length_m, radius_m) - head_radius(radius_m)


## The radius of a drop `y` along its axis (head centre at 0, tip at -`tail`): a sphere in front, a tapering tail behind.
static func radius_at(y: float, head: float, tail: float) -> float:
	if y >= 0.0:
		return sqrt(maxf(head * head - y * y, 0.0))
	var u: float = clampf(-y / tail, 0.0, 1.0)
	return head * pow(1.0 - u, TAPER)


## How much of the head's glow is left `y` along a drop's axis (head centre at 0, tip at -`tail`).
static func fade_at(y: float, tail: float) -> float:
	if y >= 0.0:
		return 1.0
	return pow(1.0 - clampf(-y / tail, 0.0, 1.0), FADE)


## The vertex colour `y` along the envelope (of tail `tail`) or along the core (`core`, of tail `tail` × `CORE_LENGTH`): the
## envelope's own, or what a core pixel shows, with the share the core adds over the envelope when drawn additive as its alpha.
static func color_at(y: float, tail: float, core: bool) -> Color:
	var share: float = ENVELOPE_BRIGHTNESS / PEAK
	var envelope: float = share * fade_at(y, tail)
	if not core:
		return Color(envelope, envelope, envelope, 1.0)
	var sum: float = envelope + (1.0 - share) * fade_at(y, tail * CORE_LENGTH)
	if sum <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color(sum, sum, sum, 1.0 - envelope / sum)


# Built head up, then mirrored so the head leads along -Y; the mirror also turns the faces outward (Godot's front faces wind
# clockwise).
static func _point_down(arrays: Array) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in verts.size():
		verts[i].y = -verts[i].y
		normals[i].y = -normals[i].y
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals


static func _empty() -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array()
	return arrays


# Appends one drop: the envelope (`tail` its own) or the core (`tail` the envelope's, shortened here).
static func _drop(arrays: Array, head: float, tail: float, core: bool) -> void:
	var envelope_tail: float = tail / CORE_LENGTH if core else tail
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var first: int = verts.size()
	var ys: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(1, HEAD_RINGS + 1):
		ys.append(head * cos(0.5 * PI * float(i) / float(HEAD_RINGS)))  # the front half of a sphere, nose excluded
	for i: int in range(1, TAIL_RINGS):
		ys.append(-tail * float(i) / float(TAIL_RINGS))
	# The nose and the tip are single points.
	verts.append(Vector3(0, head, 0))
	normals.append(Vector3.UP)
	colors.append(color_at(head, envelope_tail, core))
	for y: float in ys:
		var r: float = radius_at(y, head, tail)
		var color: Color = color_at(y, envelope_tail, core)
		for s: int in SIDES:
			var a: float = TAU * float(s) / float(SIDES)
			var dir := Vector3(cos(a), 0.0, sin(a))
			verts.append(Vector3(dir.x * r, y, dir.z * r))
			normals.append(Vector3(dir.x * r, maxf(y, 0.0), dir.z * r).normalized())
			colors.append(color)
	verts.append(Vector3(0, -tail, 0))
	normals.append(Vector3.DOWN)
	colors.append(color_at(-tail, envelope_tail, core))
	var rings: int = ys.size()
	var nose: int = first
	var tip: int = first + 1 + rings * SIDES
	for s: int in SIDES:
		var n: int = (s + 1) % SIDES
		indices.append_array(PackedInt32Array([nose, first + 1 + n, first + 1 + s]))
	for ring: int in rings - 1:
		var a0: int = first + 1 + ring * SIDES
		var b0: int = a0 + SIDES
		for s: int in SIDES:
			var n: int = (s + 1) % SIDES
			indices.append_array(PackedInt32Array([a0 + s, a0 + n, b0 + s, a0 + n, b0 + n, b0 + s]))
	var last: int = first + 1 + (rings - 1) * SIDES
	for s: int in SIDES:
		var n: int = (s + 1) % SIDES
		indices.append_array(PackedInt32Array([last + s, last + n, tip]))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
