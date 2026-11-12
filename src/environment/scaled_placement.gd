class_name ScaledPlacement
extends RefCounted
## Where the scaled-space layer draws one far body (M6-T10, D68): its true direction, distance and angular size seen from the
## camera, and a small stand-in sphere along that direction that looks the same. Pure.
##
## Both places are 64-bit and measured from the World's anchor (D64), in the game's axes, so the planet beside the station
## never passes through a barycentric number of 1e11 m. Only the difference, shrunk into the layer's bounded depth, becomes a
## float32 offset from the camera: no far position reaches the GPU as a world coordinate (D68's precision rule).

## Metres of true distance per metre drawn, while the result fits the bounded depth.
const SCALE: float = 1000.0
## The farthest a body's centre is drawn from the camera, m: with its radius it must stay inside the cameras' 50 km far plane.
const MAX_DEPTH_M: float = 20_000.0
## The layer's slab of reversed depth: behind everything nearer than about 49.5 km, in front of the star points (1e-9).
const DEPTH_BACK: float = 2.0e-9
const DEPTH_FRONT: float = 1.0e-8
## The true distances the slab is spread over, by their logarithm.
const NEAREST_M: float = 1.0e4
const FARTHEST_M: float = 1.0e13

## Unit vector from the camera to the body's centre.
var direction: Vector3 = Vector3.FORWARD
## True distance to the body's centre, m.
var distance_m: float = 0.0
## Half the angle the body subtends, rad.
var angular_radius_rad: float = 0.0
## Where the stand-in's centre is drawn, from the camera, m.
var offset: Vector3 = Vector3.ZERO
## The stand-in's radius, m.
var radius: float = 0.0
## The stand-in's depth in the layer's slab, so nearer bodies hide farther ones.
var depth: float = DEPTH_BACK


## The placement of a body of `radius_m` at `body` for a camera at `camera` (three numbers each, m, from the anchor).
static func place(camera: PackedFloat64Array, body: PackedFloat64Array, radius_m: float, scale: float = SCALE,
		max_depth_m: float = MAX_DEPTH_M) -> ScaledPlacement:
	var placed := ScaledPlacement.new()
	var dx: float = body[0] - camera[0]
	var dy: float = body[1] - camera[1]
	var dz: float = body[2] - camera[2]
	var distance: float = sqrt(dx * dx + dy * dy + dz * dz)
	placed.distance_m = distance
	placed.depth = layer_depth(distance)
	if distance <= 0.0:
		placed.angular_radius_rad = PI / 2.0
		placed.radius = radius_m / scale
		return placed
	placed.direction = Vector3(dx / distance, dy / distance, dz / distance)
	placed.angular_radius_rad = asin(minf(radius_m / distance, 1.0))
	# Shrinking distance and radius by one factor keeps the angular size and the limb's perspective exactly.
	var drawn: float = minf(distance / scale, max_depth_m)
	placed.offset = placed.direction * drawn
	placed.radius = radius_m * (drawn / distance)
	return placed


## The camera's place from the anchor: the World's origin plus the camera's local position, summed in 64-bit.
static func camera_from_anchor(origin: UniversePos, local: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([origin.x + local.x, origin.y + local.y, origin.z + local.z])


## The ephemeris's axes (z north) to the game's (y up): kernel (x, y, z) = game (x, -z, y). Takes the first three numbers.
static func to_game(kernel: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([kernel[0], kernel[2], -kernel[1]])


## The reversed depth a body at `distance_m` is drawn with: nearer is larger, always inside the layer's slab.
static func layer_depth(distance_m: float) -> float:
	var span: float = log(FARTHEST_M / NEAREST_M)
	var t: float = clampf(log(maxf(distance_m, NEAREST_M) / NEAREST_M) / span, 0.0, 1.0)
	return clampf(lerpf(DEPTH_FRONT, DEPTH_BACK, t), DEPTH_BACK, DEPTH_FRONT)


func angular_size_deg() -> float:
	return rad_to_deg(2.0 * angular_radius_rad)
