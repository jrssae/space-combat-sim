class_name GridMountHealth
extends RefCounted
## The station grid's mounts' own health (M7-T07 fix, maintainer): a hit on the station within a mount's radius, on the same body,
## wears that mount down (the nearest one only, and the hull half as much, `StationDamage`), and at zero the mount is knocked out until a
## mission or the console repairs it. Pure: `StationGrid` feeds it the station's hits and turns a loss into a mount that stops.

## Health and the radius around the pivot a hit counts within, per kind (`StationGrid.Kind`: 1 light, 2 heavy, 3 interceptor).
## The heavy cannons are armoured to outlast a cruiser's beams for a whole fight (the balance rule needs them to the end).
const MAX_HEALTH: Dictionary[int, float] = {1: 300.0, 2: 4000.0, 3: 200.0}
const RADIUS_M: Dictionary[int, float] = {1: 30.0, 2: 45.0, 3: 25.0}

var names := PackedStringArray()
var kinds := PackedInt32Array()
## `StationHardpoints.DRUM` or `FRAME`: the body whose frame `positions` are in.
var bodies := PackedStringArray()
var positions := PackedVector3Array()
var health := PackedFloat64Array()
var max_health := PackedFloat64Array()


## One entry per mount from the hardpoints' `grid_mounts` (name, kind name, body, position).
static func from_mounts(entries: Array[Dictionary], kind_of: Callable) -> GridMountHealth:
	var made := GridMountHealth.new()
	for e: Dictionary in entries:
		var kind: int = int(kind_of.call(String(e.get("kind", ""))))
		made.names.append(String(e["name"]))
		made.kinds.append(kind)
		made.bodies.append(String(e["body"]))
		made.positions.append(e["position"])
		made.max_health.append(MAX_HEALTH.get(kind, 300.0))
		made.health.append(MAX_HEALTH.get(kind, 300.0))
	return made


func count() -> int:
	return names.size()


func index_of(mount_name: String) -> int:
	return Array(names).find(mount_name)


func is_out(index: int) -> bool:
	return health[index] <= 0.0


## The live mount on `body` whose radius holds `point` (in that body's frame), the nearest of them; -1 when none does.
func nearest(body: String, point: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in names.size():
		if bodies[i] != body or health[i] <= 0.0:
			continue
		var r: float = RADIUS_M.get(kinds[i], 30.0)
		var d: float = positions[i].distance_squared_to(point)
		if d <= r * r and d < best_d:
			best_d = d
			best = i
	return best


## A hit of `amount` at `point` in `body`'s frame: only the nearest live mount whose radius holds it takes it (M10-T65, Q72).
## Returns the mounts this hit knocked out.
func hit(body: String, point: Vector3, amount: float) -> PackedInt32Array:
	var lost := PackedInt32Array()
	var i: int = nearest(body, point)
	if i >= 0 and wear(i, amount):
		lost.append(i)
	return lost


## Whole again; true when it was knocked out.
func repair(index: int) -> bool:
	var was_out: bool = is_out(index)
	health[index] = max_health[index]
	return was_out


## Adds `amount` to mount `index` (never above its full health); true when this brought a knocked-out mount back (M7-T35).
func heal(index: int, amount: float) -> bool:
	if index < 0 or index >= health.size() or amount <= 0.0:
		return false
	var was_out: bool = is_out(index)
	health[index] = minf(health[index] + amount, max_health[index])
	return was_out and health[index] > 0.0


## Takes `amount` off mount `index` alone; true when that knocked it out (the console's staged damage, M7-T35).
func wear(index: int, amount: float) -> bool:
	if index < 0 or index >= health.size() or amount <= 0.0 or is_out(index):
		return false
	health[index] = maxf(health[index] - amount, 0.0)
	return is_out(index)


func is_whole(index: int) -> bool:
	return health[index] >= max_health[index]


## How many mounts are knocked out.
func out_count() -> int:
	var n: int = 0
	for i: int in names.size():
		n += 1 if health[i] <= 0.0 else 0
	return n
