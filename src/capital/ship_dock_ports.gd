class_name ShipDockPorts
extends RefCounted
## A hull's docking collars (M10-T53, Q84) and where a craft lies when its own lock is mated with one. Pure: read from the
## hull's `hardpoints.json` `docking_ports` (`position`, `out`, `up`, in its body frame) and the craft's own port (the crew
## shuttle's stern hatch). A craft without a port cannot mate (the Kestrel only lands in bays, Q93).
##
## Stage 2's bay: the berths of a bay that takes visitors (`visitors` in its `bays` entry: the Asimov's shuttle bay) are
## places too, listed after the collars. A berth's `position` is its point on the deck, its `out` its lane out of the mouth;
## a craft rests on it nose out, on its own rest point, and needs no lock, only to be a craft the berth takes.

## The name that asks for a ship's bay rather than one berth of it.
const BAY: String = "bay"

var names: PackedStringArray = PackedStringArray()
var positions: PackedVector3Array = PackedVector3Array()
var outs: PackedVector3Array = PackedVector3Array()
var ups: PackedVector3Array = PackedVector3Array()
## Per place: the hangar's cradle a berth is (-1: a collar), the craft it takes (none: any craft with a lock) and its bay.
var cradles: PackedInt32Array = PackedInt32Array()
var crafts: Array[PackedStringArray] = []
var bays: PackedStringArray = PackedStringArray()
## The middle of the visitors' bay's mouth and the way out of it, the hull's frame (where the player targets it).
var bay_mouth: Vector3 = Vector3.ZERO
var bay_out: Vector3 = Vector3.FORWARD


## The collars of a hull's `hardpoints`; none when it has no `docking_ports`.
static func of(hardpoints: Dictionary) -> ShipDockPorts:
	var found := ShipDockPorts.new()
	var raw: Variant = hardpoints.get("docking_ports", [])
	for entry: Variant in raw if raw is Array else []:
		var port: Dictionary = port_of(entry)
		if port.is_empty():
			continue
		found.names.append(str((entry as Dictionary).get("name", "port_%d" % found.names.size())))
		found.positions.append(port["position"])
		found.outs.append(port["out"])
		found.ups.append(port["up"])
		found.cradles.append(-1)
		found.crafts.append(PackedStringArray())
		found.bays.append("")
	return found


## Adds the berths of the hull's bays that take visitors: `berths` are the hull's cradles (`BayBerths.of`, the hangar's own).
func add_berths(hardpoints: Dictionary, berths: CarrierCradles) -> void:
	var open: Dictionary = {}
	for raw: Variant in hardpoints.get("bays", []) if hardpoints.get("bays") is Array else []:
		if raw is Dictionary and bool((raw as Dictionary).get("visitors", false)):
			open[str((raw as Dictionary).get("name", ""))] = raw
	for i: int in berths.count():
		if not open.has(berths.bays[i]):
			continue
		if bay_count() == 0:
			var bay: Dictionary = open[berths.bays[i]]
			var mouth: Array = bay.get("mouth_m", [0.0, 0.0])
			bay_mouth = (_vec(bay.get("exit")) as Vector3) + (_vec(bay.get("up")) as Vector3) * (float(mouth[1]) / 6.0)
			bay_out = (_vec(bay.get("forward")) as Vector3).normalized()
		names.append(berths.names[i])
		positions.append(berths.positions[i])
		outs.append(berths.out_axes[i])
		ups.append(berths.bases[i].y)
		cradles.append(i)
		crafts.append(berths.crafts[i])
		bays.append(berths.bays[i])


## One port as `{position, out, up}` (unit directions, `up` square to `out`), empty when the entry is not one.
static func port_of(entry: Variant) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var at: Variant = _vec((entry as Dictionary).get("position"))
	var out: Variant = _vec((entry as Dictionary).get("out"))
	if at == null or out == null or (out as Vector3).is_zero_approx():
		return {}
	var out_unit: Vector3 = (out as Vector3).normalized()
	var up: Variant = _vec((entry as Dictionary).get("up"))
	var up_raw: Vector3 = up if up != null else Vector3.UP
	var up_square: Vector3 = up_raw - out_unit * up_raw.dot(out_unit)
	if up_square.length() < 1e-4:
		up_square = out_unit.cross(Vector3.RIGHT) if absf(out_unit.x) < 0.9 else out_unit.cross(Vector3.UP)
	return {"position": at, "out": out_unit, "up": up_square.normalized()}


## A craft's own lock from its `hardpoints.json` (its first `docking_ports` entry), empty when it has none.
static func craft_port(craft_hardpoints: Dictionary) -> Dictionary:
	var raw: Variant = craft_hardpoints.get("docking_ports", [])
	for entry: Variant in raw if raw is Array else []:
		var port: Dictionary = port_of(entry)
		if not port.is_empty():
			return port
	return {}


func count() -> int:
	return names.size()


func is_berth(index: int) -> bool:
	return cradles[index] >= 0


func collar_count() -> int:
	return cradles.count(-1)


func bay_count() -> int:
	return count() - collar_count()


## Whether place `index` takes a craft of `type`: a collar any craft with a lock of its own, a berth the craft it is for.
func takes(index: int, type: String, has_lock: bool) -> bool:
	return crafts[index].has(type) if is_berth(index) else has_lock


## The berth for a craft of `type` (the first), -1 when no bay here takes it.
func berth_for(type: String) -> int:
	for i: int in count():
		if is_berth(i) and crafts[i].has(type):
			return i
	return -1


## The collar called `port_name`, -1 when there is none.
func index_of(port_name: String) -> int:
	return names.find(port_name)


## The craft's pose in the hull's frame when its lock `craft` faces collar `index` with `gap_m` between them: the two `out`s
## opposed, the craft's up along the collar's. On a berth it rests nose out with its `rest` point on the deck.
func mate(index: int, craft: Dictionary, gap_m: float = 0.0) -> Transform3D:
	if is_berth(index):
		var nose_out: Basis = Hardpoints.look_basis(outs[index], ups[index])
		return Transform3D(nose_out, positions[index] - nose_out * (craft.get("rest", Vector3.ZERO) as Vector3))
	var hull_frame: Basis = _frame(-outs[index], ups[index])
	var craft_frame: Basis = _frame(craft["out"], craft["up"])
	var basis: Basis = hull_frame * craft_frame.transposed()
	return Transform3D(basis, positions[index] + outs[index] * gap_m - basis * (craft["position"] as Vector3))


## Where the craft's origin is when it stands `out_m` out of its mated place on the collar's axis (the lane it backs down).
func lane_point(index: int, craft: Dictionary, gap_m: float, out_m: float) -> Vector3:
	return mate(index, craft, gap_m).origin + outs[index] * out_m


## The free collar nearest to `local` (the hull's frame); `taken[i]` marks the ones in use. -1 when none is free.
func nearest_free(local: Vector3, taken: Array[bool]) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in count():
		if i < taken.size() and taken[i]:
			continue
		var d: float = local.distance_squared_to(positions[i])
		if d < best_d:
			best_d = d
			best = i
	return best


# A right-handed frame whose z is `along` and whose y is `up` (already square to it).
static func _frame(along: Vector3, up: Vector3) -> Basis:
	return Basis(up.cross(along).normalized(), up, along)


static func _vec(value: Variant) -> Variant:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null
