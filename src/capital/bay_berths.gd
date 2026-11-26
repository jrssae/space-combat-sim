class_name BayBerths
extends RefCounted
## Where a capital carrier's craft sit in its bays (M10-T17, Q58, Q71, Q73): the places a launch starts from and a recovery
## ends on, as `CarrierCradles` the dock can fly. Pure: read from the hull's `hardpoints.json` `bays` and the hangar's options.
##
## A bay is a hall behind a mouth (`exit`, `forward`, `up`, `mouth_m`, `depth_m`); its floor lies a third of the mouth's height
## under the exit point (as `InteriorZones` reads the hall). Each bay gives one cradle per lane, every craft nose out of the
## mouth: a bay with a lift (`elevator`, `elevator_travel_m`: the Nova) has `elevator_abreast` lanes side by side in `elevator_rows`
## rows on the lift (round its point, `elevator_row_gap_m` apart along the hall); a
## big hall without one (the Omega) has `lanes` lanes at the back of the hall; a bay with `berths` (the Hyperion's shuttle bay)
## that many mid-hall; any other bay one, mid-hall (the Hyperion's single-fury bays).

## Lanes side by side are at most this far apart, m (a Starfury is 15.4 m across).
const LANE_SPACING_M: float = 20.0
## A big hall's lanes start this far in front of its back wall, m.
const BACK_GAP_M: float = 15.0


## The cradles of every bay in `hardpoints` that takes craft, by `options` (`HangarRules.options`).
static func of(hardpoints: Dictionary, options: Dictionary) -> CarrierCradles:
	var out := CarrierCradles.new()
	for raw: Variant in hardpoints.get("bays", []) if hardpoints.get("bays") is Array else []:
		var bay: Dictionary = raw if raw is Dictionary else {}
		if str(bay.get("kind", "")) != "bay" or not bay.has("exit") or str(bay.get("craft", "")).is_empty():
			continue
		for lane: Dictionary in lanes_of(bay, options):
			_add(out, bay, lane, options)
	return out


## The craft types a bay takes: its `craft` and any its `poses` name (the Hyperion's shuttle bay takes the Kestrel too).
static func crafts_of(bay: Dictionary) -> PackedStringArray:
	var out := PackedStringArray([str(bay.get("craft", ""))])
	if bay.get("poses") is Dictionary:
		for key: Variant in bay["poses"]:
			if not out.has(str(key)):
				out.append(str(key))
	return out


## A bay's lanes in the hull's frame: `{at, lift_m, run_in_m}` each (the floor point, the lift's drop, the way from it to
## the mouth along `forward`).
static func lanes_of(bay: Dictionary, options: Dictionary) -> Array[Dictionary]:
	var forward: Vector3 = _vec(bay.get("forward"), Vector3.FORWARD).normalized()
	var up: Vector3 = _vec(bay.get("up"), Vector3.UP).normalized()
	var right: Vector3 = forward.cross(up).normalized()
	var mouth: Array = bay.get("mouth_m", [20.0, 10.0]) as Array
	var depth: float = float(bay.get("depth_m", 20.0))
	var floor_at: Vector3 = _vec(bay.get("exit"), Vector3.ZERO) - up * (float(mouth[1]) / 3.0)
	var capacity: int = maxi(int(bay.get("capacity", 1)), 1)
	var lift_m: float = float(bay.get("elevator_travel_m", 0.0)) if bay.has("elevator") else 0.0
	var count: int = 1
	var rows: int = 1
	var row_gap: float = 0.0
	var run_in: float = 0.5 * depth
	if lift_m > 0.0:
		count = mini(maxi(int(options.get("elevator_abreast", 3)), 1), capacity)
		rows = clampi(int(options.get("elevator_rows", 1)), 1, maxi(capacity / count, 1))
		row_gap = float(options.get("elevator_row_gap_m", 14.0))
		run_in = (_vec(bay.get("exit"), Vector3.ZERO) - _vec(bay.get("elevator"), Vector3.ZERO)).dot(forward)
	elif bay.has("berths"):
		count = mini(maxi(int(bay["berths"]), 1), capacity)
	elif capacity > 1:
		count = mini(maxi(int(options.get("lanes", 3)), 1), capacity)
		run_in = maxf(depth - BACK_GAP_M, 0.5 * depth)
	var spacing: float = minf(LANE_SPACING_M, float(mouth[0]) / float(count))
	var out: Array[Dictionary] = []
	for r: int in rows:
		var back: float = (float(r) - 0.5 * float(rows - 1)) * row_gap  # the rows round the lift's point, front row first
		for k: int in count:
			var across: float = (float(k) - 0.5 * float(count - 1)) * spacing
			out.append({"at": floor_at - forward * (run_in + back) + right * across, "lift_m": lift_m, "run_in_m": run_in + back})
	return out


static func _add(out: CarrierCradles, bay: Dictionary, lane: Dictionary, options: Dictionary) -> void:
	var forward: Vector3 = _vec(bay.get("forward"), Vector3.FORWARD).normalized()
	var up: Vector3 = _vec(bay.get("up"), Vector3.UP).normalized()
	var bay_name: String = str(bay.get("name", "bay"))
	var lane_index: int = out.bays.count(bay_name)
	var run_in: float = float(lane["run_in_m"])
	out.names.append("%s_%d" % [bay_name, lane_index])
	out.positions.append(lane["at"])
	out.bases.append(Hardpoints.look_basis(forward, up))
	out.approach_m.append(run_in + float(options.get("approach_m", HangarRules.DEFAULTS["approach_m"])))
	out.states.append(CarrierCradles.State.FREE)
	out.out_axes.append(forward)
	out.launch_m.append(run_in + float(options.get("clear_m", HangarRules.DEFAULTS["clear_m"])))
	out.lift_m.append(float(lane["lift_m"]))
	out.bays.append(bay_name)
	out.lanes.append(lane_index)
	out.crafts.append(crafts_of(bay))


static func _vec(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
