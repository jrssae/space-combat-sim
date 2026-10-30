class_name Silhouette
extends RefCounted
## Drawings of the main components for the HUD's damage indicators (pure data), each part tagged with its damage zone
## (`DamageZones`), in the unit square -0.5..0.5 (x right, y down, as on the screen), to be scaled into a rect.
## The X fighter (Starfury) is a low-poly wireframe seen from behind and above (`wireframe`): the fuselage, and per arm the
## strut, the pod and the claw. The delta (raider) is outline polygons seen from above (`polygons`): the central hump and the
## two wings, nose up.

## The wireframe's view: the ship turned by this yaw about +Y, then this pitch about +X (radians), so the camera sits behind
## and above it, a little to its left, and the pods' length shows. The ship's right stays on the right, its top up.
const WIRE_YAW: float = -0.25
const WIRE_PITCH: float = 0.5
## Share of the rect the wireframe fills along its tighter axis.
const WIRE_FILL: float = 0.94

# The Starfury's low-poly model, ship frame (+X right, +Y up, -Z forward), metres, after the hull that
# tools/procgen/assets/starfury_aurora.py builds (centred frame). Fuselage rings: [z, top, top half-width,
# shoulder half-width, shoulder y, keel half-width, keel], nose first.
const _FUSELAGE_RINGS: Array = [
	[-4.36, 0.93, 0.67, 0.76, 0.80, 0.49, -0.02],
	[-3.01, 1.12, 0.88, 1.32, 0.15, 0.64, -0.80],
	[0.04, 1.14, 0.78, 1.10, 0.25, 0.32, -1.20],
	[0.84, 1.04, 0.70, 1.00, 0.25, 0.28, -1.10],
]
## Gun barrels: x, y, from z, to z (mirrored in x).
const _GUN: Array = [0.45, -0.75, -2.6, -5.0]
## Upper-right pod centre (mirrored to the other corners) and its hexagonal rings: [z from the centre, radius], front first.
const _POD_CENTRE := Vector3(5.5, 2.5, 0.79)
const _POD_RINGS: Array = [[-2.8, 0.5], [-0.9, 0.86], [1.3, 0.62], [2.8, 0.55]]
## Upper-right strut: root leading / trailing edge (inside the fuselage) and tip leading / trailing edge (at the pod).
const _STRUT: Array = [Vector3(0.6, 0.6, -3.16), Vector3(0.6, 0.6, 0.64), Vector3(4.93, 2.28, -0.41), Vector3(4.93, 2.28, 1.84)]
## Upper-right claw blades, pod frame: [roll (degrees from +X towards +Y), sideways offset, root radius, root z, tip radius,
## tip z]: the outboard pair, then the inboard blade.
const _CLAW: Array = [[12.0, 0.2, 0.75, 1.2, 1.72, 4.55], [12.0, -0.2, 0.75, 1.2, 1.72, 4.55], [205.0, 0.0, 0.7, 1.3, 1.54, 3.54]]


## `[{zone: int, segments: PackedVector2Array}, ...]`: line pairs (a0, b0, a1, b1, ...) for `draw_multiline`, in the unit
## square and undistorted once scaled into a rect whose width / height is `aspect`. Empty for a layout drawn as `polygons`.
static func wireframe(layout: DamageZones.Layout, aspect: float = 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if layout != DamageZones.Layout.X_FIGHTER:
		return out
	var edges: Array = []  # [zone, Vector3, Vector3]
	_fuselage_edges(edges)
	_arm_edges(edges, DamageZones.UPPER_RIGHT, 1.0, 1.0)
	_arm_edges(edges, DamageZones.UPPER_LEFT, -1.0, 1.0)
	_arm_edges(edges, DamageZones.LOWER_RIGHT, 1.0, -1.0)
	_arm_edges(edges, DamageZones.LOWER_LEFT, -1.0, -1.0)
	# Project (y up), then fit the drawing's bounds into the unit square at one scale for x and y on screen.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var projected: Array = []
	for e: Array in edges:
		var a: Vector2 = _project(e[1])
		var b: Vector2 = _project(e[2])
		projected.append([e[0], a, b])
		lo = lo.min(a).min(b)
		hi = hi.max(a).max(b)
	var centre: Vector2 = (lo + hi) * 0.5
	var size: Vector2 = (hi - lo).max(Vector2(1e-6, 1e-6))
	var safe_aspect: float = maxf(aspect, 1e-3)
	var k: float = WIRE_FILL * minf(1.0 / size.x, 1.0 / (size.y * safe_aspect))
	var by_zone: Dictionary = {}
	for e: Array in projected:
		var zone: int = e[0]
		# Packed arrays are values: append to a local and store it back.
		var segments: PackedVector2Array = by_zone.get(zone, PackedVector2Array())
		for p: Vector2 in [e[1], e[2]]:
			var d: Vector2 = p - centre
			segments.append(Vector2(d.x * k, -d.y * k * safe_aspect))
		by_zone[zone] = segments
	for zone: int in by_zone:
		out.append({"zone": zone, "segments": by_zone[zone]})
	return out


## `[{zone: int, points: PackedVector2Array}, ...]` for a layout drawn as outline polygons; empty for `Layout.NONE` and for
## a layout drawn as a `wireframe`.
static func polygons(layout: DamageZones.Layout) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match layout:
		DamageZones.Layout.DELTA:
			out.append({"zone": DamageZones.DELTA_CENTRE, "points": PackedVector2Array([Vector2(0.0, -0.4), Vector2(0.1, -0.05),
					Vector2(0.1, 0.34), Vector2(-0.1, 0.34), Vector2(-0.1, -0.05)])})
			out.append({"zone": DamageZones.DELTA_LEFT, "points": PackedVector2Array([Vector2(-0.1, -0.05), Vector2(-0.5, 0.3),
					Vector2(-0.5, 0.4), Vector2(-0.1, 0.34)])})
			out.append({"zone": DamageZones.DELTA_RIGHT, "points": PackedVector2Array([Vector2(0.1, -0.05), Vector2(0.5, 0.3),
					Vector2(0.5, 0.4), Vector2(0.1, 0.34)])})
	return out


# The view: yaw about +Y, then pitch about +X; returns screen-plane x right, y up.
static func _project(p: Vector3) -> Vector2:
	var cy: float = cos(WIRE_YAW)
	var sy: float = sin(WIRE_YAW)
	var x: float = cy * p.x - sy * p.z
	var z: float = sy * p.x + cy * p.z
	return Vector2(x, cos(WIRE_PITCH) * p.y - sin(WIRE_PITCH) * z)


# The fuselage's hexagonal rings, joined corner to corner, and the gun barrels.
static func _fuselage_edges(edges: Array) -> void:
	var rings: Array = []
	for r: Array in _FUSELAGE_RINGS:
		var z: float = r[0]
		rings.append([Vector3(r[2], r[1], z), Vector3(r[3], r[4], z), Vector3(r[5], r[6], z), Vector3(-r[5], r[6], z),
				Vector3(-r[3], r[4], z), Vector3(-r[2], r[1], z)])
	_rings_and_rails(edges, DamageZones.CABIN, rings)
	for sx: float in [-1.0, 1.0]:
		edges.append([DamageZones.CABIN, Vector3(sx * _GUN[0], _GUN[1], _GUN[2]), Vector3(sx * _GUN[0], _GUN[1], _GUN[3])])


# One arm (strut, pod, claw), mirrored from the upper right by `sx` / `sy` (-1 or +1).
static func _arm_edges(edges: Array, zone: int, sx: float, sy: float) -> void:
	var m := Vector3(sx, sy, 1.0)
	var centre: Vector3 = _POD_CENTRE * m
	var rings: Array = []
	for r: Array in _POD_RINGS:
		var ring: Array = []
		for k: int in range(6):
			var a: float = TAU * k / 6.0
			ring.append(centre + Vector3(r[1] * cos(a), r[1] * sin(a), r[0]))
		rings.append(ring)
	_rings_and_rails(edges, zone, rings)
	var s: Array = []
	for p: Vector3 in _STRUT:
		s.append(p * m)
	edges.append([zone, s[0], s[2]])  # leading edge
	edges.append([zone, s[1], s[3]])  # trailing edge
	edges.append([zone, s[2], s[3]])  # tip
	for c: Array in _CLAW:
		var roll: float = deg_to_rad(c[0])
		var radial := Vector3(cos(roll), sin(roll), 0.0)
		var side := Vector3(-sin(roll), cos(roll), 0.0)
		var root: Vector3 = _POD_CENTRE + radial * c[2] + side * c[1] + Vector3(0.0, 0.0, c[3])
		var tip: Vector3 = _POD_CENTRE + radial * c[4] + side * c[1] + Vector3(0.0, 0.0, c[5])
		edges.append([zone, root * m, tip * m])


# Closed rings plus the rails joining matching corners of consecutive rings.
static func _rings_and_rails(edges: Array, zone: int, rings: Array) -> void:
	for i: int in range(rings.size()):
		var ring: Array = rings[i]
		var n: int = ring.size()
		for k: int in range(n):
			edges.append([zone, ring[k], ring[(k + 1) % n]])
			if i > 0:
				edges.append([zone, rings[i - 1][k], ring[k]])
