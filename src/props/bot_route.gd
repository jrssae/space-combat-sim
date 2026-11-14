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
