class_name Silhouette
extends RefCounted
## Drawings of the main components for the HUD's damage indicators (pure data), each part tagged with its damage zone
## (`DamageZones`), in the unit square -0.5..0.5 (x right, y down, as on the screen), to be scaled into a rect.
## The X fighter (Starfury) is a low-poly wireframe seen from behind and above (`wireframe`): the fuselage, and per arm the
## strut's deck, the pod with its dome and sensor bulb, and the claw. The delta (raider) is outline polygons seen from above (`polygons`): the central hump and the
## two wings, nose up.

## The wireframe's view: the ship turned by this yaw about +Y, then this pitch about +X (radians), so the camera sits behind
## and above it, a little to its left, and the pods' length shows. The ship's right stays on the right, its top up.
const WIRE_YAW: float = -0.25
const WIRE_PITCH: float = 0.5
## Share of the rect the wireframe fills along its tighter axis.
const WIRE_FILL: float = 0.94

# The Starfury's low-poly model, ship frame (+X right, +Y up, -Z forward), metres, after the hull that
# tools/procgen/assets/starfury_aurora.py builds (its authored frame). Fuselage rings: [z, top, top half-width,
# shoulder half-width, shoulder y, keel half-width, keel], nose first: the canopy's tip, its full section, the body.
const _FUSELAGE_RINGS: Array = [
	[-4.93, 0.15, 0.15, 0.33, 0.0, 0.12, -0.22],
	[-4.3, 0.66, 0.36, 0.63, 0.0, 0.25, -0.98],
	[-3.5, 0.98, 0.55, 0.9, -0.04, 0.45, -1.25],
	[-0.85, 0.98, 0.5, 0.9, -0.1, 0.5, -1.25],
]
## Gun barrels: x, y, from z, to z (mirrored in x).
const _GUN: Array = [0.72, -1.38, -3.6, -4.65]
## Upper-right pod centre (mirrored to the other corners) and its hexagonal rings: [z from the centre, radius], front first.
const _POD_CENTRE := Vector3(5.53, 2.295, 0.25)
const _POD_RINGS: Array = [[-2.82, 0.41], [-1.97, 0.615], [1.17, 0.93], [2.8, 0.565]]
## Upper-right strut deck, outline from the cheek beside the canopy along the leading edge to the pod, back along its
## trailing edge.
const _DECK: Array = [
	Vector3(0.55, 1.15, -4.25), Vector3(1.85, 1.25, -2.99), Vector3(4.85, 2.47, -1.27), Vector3(4.85, 2.47, 1.42),
	Vector3(0.6, 1.15, 0.2),
]
## Upper-right claw, pod frame: polylines of the outboard pincer (upper prong, lower prong, the split) and the inboard
## blade's two prongs.
const _CLAW: Array = [
	[Vector3(1.0, 1.1, 1.65), Vector3(1.21, 1.25, 3.0), Vector3(1.9, 1.12, 4.65)],
	[Vector3(1.47, -0.3, 1.65), Vector3(1.79, 0.1, 3.0), Vector3(2.12, 0.66, 4.65)],
	[Vector3(1.21, 1.25, 3.0), Vector3(1.79, 0.6, 3.0)],
	[Vector3(-1.18, -0.04, 1.6), Vector3(-1.51, -0.27, 2.85), Vector3(-1.62, -0.5, 3.45)],
	[Vector3(-0.8, -0.76, 1.6), Vector3(-1.2, -0.85, 2.85), Vector3(-1.48, -0.79, 3.45)],
]
## The pod's dorsal dome and outboard sensor bulb, pod frame: base to tip.
const _KNUCKLE: Array = [[Vector3(0.0, 0.75, -1.0), Vector3(0.0, 1.44, -1.0)], [Vector3(0.75, 0.0, -1.0), Vector3(1.46, 0.0, -1.0)]]


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


# One arm (strut deck, pod, claw), mirrored from the upper right by `sx` / `sy` (-1 or +1).
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
	for i: int in range(_DECK.size() - 1):
		edges.append([zone, (_DECK[i] as Vector3) * m, (_DECK[i + 1] as Vector3) * m])
	var lines: Array = _CLAW + _KNUCKLE
	for line: Array in lines:
		for i: int in range(line.size() - 1):
			edges.append([zone, centre + (line[i] as Vector3) * m, centre + (line[i + 1] as Vector3) * m])


# Closed rings plus the rails joining matching corners of consecutive rings.
static func _rings_and_rails(edges: Array, zone: int, rings: Array) -> void:
	for i: int in range(rings.size()):
		var ring: Array = rings[i]
		var n: int = ring.size()
		for k: int in range(n):
			edges.append([zone, ring[k], ring[(k + 1) % n]])
			if i > 0:
				edges.append([zone, rings[i - 1][k], ring[k]])
