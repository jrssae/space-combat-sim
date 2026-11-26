class_name CarrierCradles
extends RefCounted
## A carrier's docking cradles and who is on each (M12-T19, Q27): read from the hull's `hardpoints.cradles[]`, in the
## carrier's frame. Pure bookkeeping: `CarrierDock` moves the ships.
##
## A cradle is FREE, DOCKED (a fighter sits on it) or BUSY (kept for a fighter launching from it or coming back to it).
##
## M10-T17: a capital carrier's bays are cradles too (`BayBerths` makes them): each a place on a hall's floor with its own way
## out (`out_axes`, the bay's mouth), how far its launch runs (`launch_m`), how far a lift starts below the floor (`lift_m`), the
## bay it belongs to, the lane of the bay it uses and the craft it takes. A cradle carrier leaves these empty.

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
## Bay cradles only (empty for a cradle carrier): the way out and in, the launch's run and the lift's drop, m, and per cradle its
## bay, its lane in that bay and the craft types it takes.
var out_axes: PackedVector3Array = PackedVector3Array()
var launch_m: PackedFloat32Array = PackedFloat32Array()
var lift_m: PackedFloat32Array = PackedFloat32Array()
var bays: PackedStringArray = PackedStringArray()
var lanes: PackedInt32Array = PackedInt32Array()
var crafts: Array[PackedStringArray] = []


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


## Whether these are a capital's bays (M10-T17) rather than a raider carrier's pads.
func is_bays() -> bool:
	return not out_axes.is_empty()


## Whether cradle `index` takes a craft of `type` (a pad takes anything).
func takes(index: int, type: StringName) -> bool:
	return not is_bays() or crafts[index].has(String(type))


func count_in(state: State) -> int:
	var n: int = 0
	for s: int in states:
		n += 1 if s == state else 0
	return n


## The first cradle in `state`, -1 when there is none.
func first_in(state: State) -> int:
	return states.find(state)


## The free cradle whose approach point is nearest `local` (the carrier's frame), -1 when none is free. With `type`, only a
## cradle that takes that craft; with `usable`, only one it says yes to (a bay that still works).
func nearest_free(local: Vector3, type: StringName = &"", usable: Callable = Callable()) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in count():
		if states[i] != State.FREE or (type != &"" and not takes(i, type)) or (usable.is_valid() and not bool(usable.call(i))):
			continue
		var d: float = approach_point(i).distance_squared_to(local)
		if d < best_d:
			best = i
			best_d = d
	return best


## The cradle taking `type` (and that `usable` allows) whose approach point is nearest `local`, free or not: a bay's lanes,
## where returning craft wait their turn. -1 when none takes it.
func nearest_taking(local: Vector3, type: StringName = &"", usable: Callable = Callable()) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in count():
		if (type != &"" and not takes(i, type)) or (usable.is_valid() and not bool(usable.call(i))):
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
	return positions[index] + out_axis(index) * approach_m[index]


## The way out of cradle `index`: off a pad its up, out of a bay its mouth.
func out_axis(index: int) -> Vector3:
	return out_axes[index] if is_bays() else bases[index].y


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
