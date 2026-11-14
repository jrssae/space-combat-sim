class_name BotRoute
extends RefCounted
## An open, smooth path a ferry bot flies once from end to end (M7-T11): a Catmull-Rom curve through its control points (the first
## and last held as the curve's ends), kept as a polyline whose arc length is how far along the route a bot is. Pure: the same
## numbers in the station's frame, so a rebase or the station's drift changes nothing.

var samples := PackedVector3Array()
var along := PackedFloat64Array()
var length_m: float = 0.0


## The route through `control` (two points or more).
static func from_points(control: PackedVector3Array) -> BotRoute:
	var route := BotRoute.new()
	var n: int = control.size()
	if n < 2:
		return route
	for i: int in n - 1:
		var p0: Vector3 = control[maxi(i - 1, 0)]
		var p1: Vector3 = control[i]
		var p2: Vector3 = control[i + 1]
		var p3: Vector3 = control[mini(i + 2, n - 1)]
		var steps: int = maxi(BotLoop.MIN_STEPS, ceili(p1.distance_to(p2) / BotLoop.CHORD_M))
		for j: int in steps:
			route.samples.append(BotLoop.spline(p0, p1, p2, p3, float(j) / float(steps)))
	route.samples.append(control[n - 1])
	var total: float = 0.0
	for i: int in route.samples.size():
		route.along.append(total)
		if i + 1 < route.samples.size():
			total += route.samples[i].distance_to(route.samples[i + 1])
	route.length_m = total
	return route


func valid() -> bool:
	return length_m > 0.0


## The point `s` metres along the route (held at the ends).
func point_at(s: float) -> Vector3:
	var at: float = clampf(s, 0.0, length_m)
	var n: int = samples.size()
	var i: int = clampi(along.bsearch(at, false) - 1, 0, n - 2)
	var span: float = along[i + 1] - along[i]
	return samples[i].lerp(samples[i + 1], 0.0 if span <= 0.0 else (at - along[i]) / span)


## Which way the route runs at `s`, a unit vector.
func direction_at(s: float) -> Vector3:
	var a: float = clampf(s - BotLoop.HEADING_SPAN_M, 0.0, length_m)
	var b: float = clampf(s + BotLoop.HEADING_SPAN_M, 0.0, length_m)
	return (point_at(b) - point_at(a)).normalized()


func sample_points() -> PackedVector3Array:
	return samples


## The same route flown the other way.
func reversed() -> BotRoute:
	var route := BotRoute.new()
	for i: int in range(samples.size() - 1, -1, -1):
		route.samples.append(samples[i])
		route.along.append(length_m - along[i])
	route.length_m = length_m
	return route


## A route along straight legs through `corners`, each corner rounded over up to `radius_m` (a third of the shorter leg at most),
## so it never swings wide of the legs the way a spline does.
static func from_corners(corners: PackedVector3Array, radius_m: float) -> BotRoute:
	var points := PackedVector3Array()
	var n: int = corners.size()
	if n < 2:
		return BotRoute.new()
	points.append(corners[0])
	for i: int in range(1, n - 1):
		var a: Vector3 = corners[i - 1]
		var b: Vector3 = corners[i]
		var c: Vector3 = corners[i + 1]
		var r: float = minf(radius_m, minf(a.distance_to(b), b.distance_to(c)) / 3.0)
		var p0: Vector3 = b + (a - b).normalized() * r
		var p2: Vector3 = b + (c - b).normalized() * r
		for j: int in BotLoop.MIN_STEPS + 1:
			var t: float = float(j) / float(BotLoop.MIN_STEPS)
			points.append(p0.lerp(b, t).lerp(b.lerp(p2, t), t))
	points.append(corners[n - 1])
	return _of_samples(points)


## Routes flown one after the other (each starts where the one before ends).
static func joined(parts: Array[BotRoute]) -> BotRoute:
	var points := PackedVector3Array()
	for part: BotRoute in parts:
		for i: int in part.samples.size():
			if points.is_empty() or points[points.size() - 1].distance_to(part.samples[i]) > 1e-4:
				points.append(part.samples[i])
	return _of_samples(points)


static func _of_samples(points: PackedVector3Array) -> BotRoute:
	var route := BotRoute.new()
	var total: float = 0.0
	for i: int in points.size():
		if i > 0 and points[i].distance_to(points[i - 1]) <= 1e-4:
			continue
		if not route.samples.is_empty():
			total += route.samples[route.samples.size() - 1].distance_to(points[i])
		route.samples.append(points[i])
		route.along.append(total)
	route.length_m = total
	return route
