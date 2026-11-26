class_name ShipDockPorts
extends RefCounted
## A hull's docking collars (M10-T53, Q84) and where a craft lies when its own lock is mated with one. Pure: read from the
## hull's `hardpoints.json` `docking_ports` (`position`, `out`, `up`, in its body frame) and the craft's own port (the crew
## shuttle's stern hatch). A craft without a port cannot mate (the Kestrel only lands in bays, Q93).

var names: PackedStringArray = PackedStringArray()
var positions: PackedVector3Array = PackedVector3Array()
var outs: PackedVector3Array = PackedVector3Array()
var ups: PackedVector3Array = PackedVector3Array()


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
	return found


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


## The collar called `port_name`, -1 when there is none.
func index_of(port_name: String) -> int:
	return names.find(port_name)


## The craft's pose in the hull's frame when its lock `craft` faces collar `index` with `gap_m` between them: the two `out`s
## opposed, the craft's up along the collar's.
func mate(index: int, craft: Dictionary, gap_m: float = 0.0) -> Transform3D:
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
