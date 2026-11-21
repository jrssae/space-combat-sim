class_name CarrierCradles
extends RefCounted
## A carrier's docking cradles and who is on each (M12-T19, Q27): read from the hull's `hardpoints.cradles[]`, in the
## carrier's frame. Pure bookkeeping: `CarrierDock` moves the ships.
##
## A cradle is FREE, DOCKED (a fighter sits on it) or BUSY (kept for a fighter launching from it or coming back to it).

enum State { FREE, DOCKED, BUSY }

## How far out a returning fighter is handed to its cradle when the hardpoint gives no `approach_from`, m.
const DEFAULT_APPROACH_M: float = 60.0

var names: PackedStringArray = PackedStringArray()
## Where a docked fighter rests (on the pad) and how it sits: its nose along -Z, its back along +Y.
var positions: PackedVector3Array = PackedVector3Array()
var bases: Array[Basis] = []
## How far out along the cradle's +Y a returning fighter is taken, m.
var approach_m: PackedFloat32Array = PackedFloat32Array()
var states: PackedInt32Array = PackedInt32Array()


## The cradles of a hull's hardpoints (`cradles[]`: `name`, `position`, `forward`, `up`, `approach_from`); entries without a
## position are skipped.
static func from_hardpoints(entries: Array) -> CarrierCradles:
	var out := CarrierCradles.new()
	for raw: Variant in entries:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var at: Variant = _vec3(entry.get("position"))
		if at == null:
			continue
		var up: Variant = _vec3(entry.get("up"))
		var forward: Variant = _vec3(entry.get("forward"))
		var basis: Basis = Hardpoints.look_basis(forward if forward != null else Vector3.FORWARD, up if up != null else Vector3.UP)
		var from: Variant = _vec3(entry.get("approach_from"))
		out.names.append(String(entry.get("name", "cradle_%d" % out.names.size())))
		out.positions.append(at)
		out.bases.append(basis)
		out.approach_m.append((from as Vector3).distance_to(at) if from != null else DEFAULT_APPROACH_M)
		out.states.append(State.FREE)
	return out


func count() -> int:
	return names.size()


func count_in(state: State) -> int:
	var n: int = 0
	for s: int in states:
		n += 1 if s == state else 0
	return n


## The first cradle in `state`, -1 when there is none.
func first_in(state: State) -> int:
	return states.find(state)


## The free cradle whose approach point is nearest `local` (the carrier's frame), -1 when none is free.
func nearest_free(local: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in count():
		if states[i] != State.FREE:
			continue
		var d: float = approach_point(i).distance_squared_to(local)
		if d < best_d:
			best = i
			best_d = d
	return best


func set_state(index: int, state: State) -> void:
	if index >= 0 and index < count():
		states[index] = state


## Where a returning fighter is handed to cradle `index`, the carrier's frame.
func approach_point(index: int) -> Vector3:
	return positions[index] + bases[index].y * approach_m[index]


## Where a fighter whose resting point is `rest` (its own frame) sits on cradle `index`, the carrier's frame.
func docked_transform(index: int, rest: Vector3) -> Transform3D:
	return Transform3D(bases[index], positions[index] - bases[index] * rest)


## The point of a fighter with the box `bounds` that meets the pad: under its box's centre, `gap_m` below its belly.
static func rest_point(bounds: AABB, gap_m: float) -> Vector3:
	var centre: Vector3 = bounds.get_center()
	return Vector3(centre.x, bounds.position.y - gap_m, centre.z)


static func _vec3(value: Variant) -> Variant:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null
