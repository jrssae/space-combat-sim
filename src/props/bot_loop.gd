class_name BotLoop
extends RefCounted
## A closed, smooth path a maintenance bot flies slowly round a patch of hull (M7-T11, Q11, D78): a Catmull-Rom curve through
## its control points, kept as a polyline whose arc length is how far along the loop a bot is. Pure: the same numbers in the
## station's frame or the drum's, whichever body the loop belongs to.

## Spacing of the polyline's samples on the curve, metres (a bot crawls at 3 to 4 m/s, so a sample is under half a second).
const CHORD_M: float = 1.5
const MIN_STEPS: int = 8
## How far either side of a point its heading is read, so the nose turns smoothly through the polyline's corners.
const HEADING_SPAN_M: float = 3.0

## The curve's samples, and the arc length at each (`along[i]` is where sample `i` starts; the last one runs back to the first).
var samples := PackedVector3Array()
var along := PackedFloat64Array()
## The arc length at each control point, in the order given.
var control_s := PackedFloat64Array()
var length_m: float = 0.0


## The loop through `control` (three points or more), or an empty one (`valid()` false) when there are fewer.
static func from_points(control: PackedVector3Array) -> BotLoop:
	var loop := BotLoop.new()
	var n: int = control.size()
	if n < 3:
		return loop
	var control_index := PackedInt32Array()
	for i: int in n:
		var p0: Vector3 = control[(i + n - 1) % n]
		var p1: Vector3 = control[i]
		var p2: Vector3 = control[(i + 1) % n]
		var p3: Vector3 = control[(i + 2) % n]
		var steps: int = maxi(MIN_STEPS, ceili(p1.distance_to(p2) / CHORD_M))
		control_index.append(loop.samples.size())
		for j: int in steps:
			var t: float = float(j) / float(steps)
			loop.samples.append(spline(p0, p1, p2, p3, t))
	var total: float = 0.0
	for i: int in loop.samples.size():
		loop.along.append(total)
		total += loop.samples[i].distance_to(loop.samples[(i + 1) % loop.samples.size()])
	loop.length_m = total
	for index: int in control_index:
		loop.control_s.append(loop.along[index])
	return loop


func valid() -> bool:
	return length_m > 0.0


## The point `s` metres along the loop (any number: it wraps).
func point_at(s: float) -> Vector3:
	var n: int = samples.size()
	var at: float = fposmod(s, length_m)
	var i: int = clampi(along.bsearch(at, false) - 1, 0, n - 1)
	var end: float = length_m if i == n - 1 else along[i + 1]
	var span: float = end - along[i]
	var k: float = 0.0 if span <= 0.0 else (at - along[i]) / span
	return samples[i].lerp(samples[(i + 1) % n], k)


## Which way the loop runs at `s`, a unit vector.
func direction_at(s: float) -> Vector3:
	return (point_at(s + HEADING_SPAN_M) - point_at(s - HEADING_SPAN_M)).normalized()


## The metres ahead from `from_s` to `to_s`, going the way the loop runs: 0 to `length_m`.
func ahead(from_s: float, to_s: float) -> float:
	return fposmod(to_s - from_s, length_m)


## Every sample, for the clearance tests.
func sample_points() -> PackedVector3Array:
	return samples


## The uniform Catmull-Rom point between `p1` and `p2` at `t` (0 to 1), `p0` and `p3` the neighbours.
static func spline(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)
