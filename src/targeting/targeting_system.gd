class_name TargetingSystem
extends RefCounted
## Target selection and the target readout (architecture §6.3), pure: no scene tree, no Input, no clock. The
## `TargetingController` node feeds it a fresh candidate list every physics tick and calls the selectors on the
## `target_next` / `target_ahead` edges; an AI pilot can drive one the same way.
##
## Rules:
## - Only candidates within `sensor_range_m` (25 km) of the ship can be selected.
## - `select_next`: candidates in range, hostile ones to `own_faction` first (`Factions.is_hostile`), then the rest,
##   each group sorted by range (ties by id); picks the one after the current selection, wrapping to the first; with
##   no selection, the first. With no hostile in range this is plain nearest-first, as in M1.
## - `select_prev`: the same order walked backwards.
## - `select_ahead`: the smallest angle between the ship's forward axis and the line of sight, forward hemisphere
##   only (< 90 deg); ties go to the nearer. If no candidate is ahead, the selection is unchanged.
## - The selection clears when its target leaves the candidate list or sensor range (`update`).
## - Readout: `range_m`, `closing_mps = -(v_t - v_s) . (p_t - p_s) / range` (positive = closing), `angle_off_deg`.
##
## Positions are `World`-local `Vector3`s (float32), but every difference is taken in 64-bit script floats, so the
## readout keeps sub-millimetre precision anywhere inside sensor range.

const SENSOR_RANGE_M: float = 25000.0
## Strict upper bound for `select_ahead`: the forward hemisphere.
const AHEAD_MAX_ANGLE_DEG: float = 90.0
## Two lines of sight closer than this (radians) count as the same bearing; the nearer target wins.
const ANGLE_TIE_RAD: float = 1e-6
## Selected id when nothing is selected (instance ids are never 0).
const NO_TARGET: int = 0

var sensor_range_m: float = SENSOR_RANGE_M
## The faction of the ship this system serves; `select_next` puts targets hostile to it first (M2-T02).
var own_faction: StringName = Factions.NEUTRAL

var _candidates: Array[TargetInfo] = []
var _selected_id: int = NO_TARGET


## Replaces the candidate list (call once per physics tick) and clears the selection if its target is gone or
## beyond sensor range. Returns true when that cleared the selection.
func update(candidates: Array[TargetInfo], ship_pos: Vector3) -> bool:
	_candidates = candidates.duplicate()
	if _selected_id == NO_TARGET:
		return false
	var current: TargetInfo = _find(_selected_id)
	if current == null or range_between(ship_pos, current.position) > sensor_range_m:
		return clear()
	return false


## Every candidate of the last `update`, in the order given, in range or not.
func all_candidates() -> Array[TargetInfo]:
	return _candidates.duplicate()


## The selectable candidates: within sensor range of `ship_pos`, nearest first (ties by id, so the order is stable).
func in_range(ship_pos: Vector3) -> Array[TargetInfo]:
	var ranges: Dictionary = {}
	var out: Array[TargetInfo] = []
	for info: TargetInfo in _candidates:
		var r: float = range_between(ship_pos, info.position)
		if r <= sensor_range_m:
			ranges[info.id] = r
			out.append(info)
	out.sort_custom(func(a: TargetInfo, b: TargetInfo) -> bool:
		var ra: float = ranges[a.id]
		var rb: float = ranges[b.id]
		return ra < rb or (ra == rb and a.id < b.id))
	return out


func selected_id() -> int:
	return _selected_id


func has_selection() -> bool:
	return _selected_id != NO_TARGET


## The selected candidate as of the last `update`, or null.
func selected() -> TargetInfo:
	return _find(_selected_id) if has_selection() else null


## The order `select_next` walks: hostile targets first, then the others, each nearest first (stable: the in-range
## order is already nearest first, ties by id).
func cycle_order(ship_pos: Vector3) -> Array[TargetInfo]:
	var hostile: Array[TargetInfo] = []
	var others: Array[TargetInfo] = []
	for info: TargetInfo in in_range(ship_pos):
		if Factions.is_hostile(own_faction, info.faction):
			hostile.append(info)
		else:
			others.append(info)
	return hostile + others


## `target_next`. Returns true if the selection changed.
func select_next(ship_pos: Vector3) -> bool:
	var ordered: Array[TargetInfo] = cycle_order(ship_pos)
	if ordered.is_empty():
		return false
	var index: int = -1
	for i: int in ordered.size():
		if ordered[i].id == _selected_id:
			index = i
			break
	# index -1 (no selection, or it is not selectable) gives 0: the first. The last one wraps to the first.
	return _select(ordered[(index + 1) % ordered.size()].id)


## `target_prev`: the same walk backwards (the mouse wheel). With no selection it picks the last one. Returns true if the
## selection changed.
func select_prev(ship_pos: Vector3) -> bool:
	var ordered: Array[TargetInfo] = cycle_order(ship_pos)
	if ordered.is_empty():
		return false
	var index: int = 0
	for i: int in ordered.size():
		if ordered[i].id == _selected_id:
			index = i
			break
	# Not selected (index stays 0) wraps to the last; otherwise one step back, the first wraps to the last.
	return _select(ordered[(index - 1 + ordered.size()) % ordered.size()].id)


## `target_ahead`. Returns true if the selection changed; with nothing in the forward hemisphere it does not.
func select_ahead(ship_pos: Vector3, forward: Vector3) -> bool:
	if forward.is_zero_approx():
		return false
	var limit: float = deg_to_rad(AHEAD_MAX_ANGLE_DEG)
	var best: TargetInfo = null
	var best_angle: float = INF
	var best_range: float = INF
	for info: TargetInfo in in_range(ship_pos):
		var r: float = range_between(ship_pos, info.position)
		if r == 0.0:
			continue  # no line of sight to a target at the ship's own position
		var d: PackedFloat64Array = _offset64(ship_pos, info.position)
		# Forward hemisphere: a positive dot product, tested exactly rather than through a rounded 90 degrees.
		if forward.x * d[0] + forward.y * d[1] + forward.z * d[2] <= 0.0:
			continue
		var angle: float = angle_between(forward, d)
		if angle >= limit:
			continue
		# in_range() is nearest first, so on a tie the earlier (nearer) candidate stays.
		if angle < best_angle - ANGLE_TIE_RAD or (absf(angle - best_angle) <= ANGLE_TIE_RAD and r < best_range):
			best = info
			best_angle = angle
			best_range = r
	if best == null:
		return false
	return _select(best.id)


## Selects a candidate by id if it is in sensor range. Returns true if the selection changed.
func select_id(target_id: int, ship_pos: Vector3) -> bool:
	for info: TargetInfo in in_range(ship_pos):
		if info.id == target_id:
			return _select(target_id)
	return false


## The in-range candidate whose display name matches `display_name` (case-insensitive), nearest first; or null.
func find_by_name(display_name: String, ship_pos: Vector3) -> TargetInfo:
	var wanted: String = display_name.strip_edges().to_lower()
	for info: TargetInfo in in_range(ship_pos):
		if info.display_name.to_lower() == wanted:
			return info
	return null


## Returns true if there was a selection.
func clear() -> bool:
	return _select(NO_TARGET)


## Readout of the current selection, or null when nothing is selected.
func readout(ship_pos: Vector3, ship_vel: Vector3, forward: Vector3 = Vector3.FORWARD) -> TargetReadout:
	var target: TargetInfo = selected()
	if target == null:
		return null
	return compute_readout(target, ship_pos, ship_vel, forward)


## Range, closing speed and angle off boresight of `target` seen from a ship at `ship_pos` moving at `ship_vel`
## with its nose along `forward`. At zero range the closing speed and the angle are 0.
static func compute_readout(target: TargetInfo, ship_pos: Vector3, ship_vel: Vector3,
		forward: Vector3 = Vector3.FORWARD) -> TargetReadout:
	var out := TargetReadout.new()
	out.id = target.id
	out.display_name = target.display_name
	out.faction = target.faction
	out.position = target.position
	out.velocity = target.velocity
	out.hull_fraction = target.hull_fraction
	out.bounding_radius = target.bounding_radius
	var d: PackedFloat64Array = _offset64(ship_pos, target.position)
	var r: float = sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
	out.range_m = r
	if r > 0.0:
		var vx: float = float(target.velocity.x) - float(ship_vel.x)
		var vy: float = float(target.velocity.y) - float(ship_vel.y)
		var vz: float = float(target.velocity.z) - float(ship_vel.z)
		out.closing_mps = -(vx * d[0] + vy * d[1] + vz * d[2]) / r
		out.angle_off_deg = rad_to_deg(angle_between(forward, d)) if not forward.is_zero_approx() else 0.0
	return out


## Distance in metres, with the difference taken in 64-bit.
static func range_between(from: Vector3, to: Vector3) -> float:
	var d: PackedFloat64Array = _offset64(from, to)
	return sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])


## Angle in radians between `axis` and the 64-bit vector `d` (atan2 of |cross| and dot: accurate near 0 and 180).
static func angle_between(axis: Vector3, d: PackedFloat64Array) -> float:
	var ax: float = axis.x
	var ay: float = axis.y
	var az: float = axis.z
	var cx: float = ay * d[2] - az * d[1]
	var cy: float = az * d[0] - ax * d[2]
	var cz: float = ax * d[1] - ay * d[0]
	return atan2(sqrt(cx * cx + cy * cy + cz * cz), ax * d[0] + ay * d[1] + az * d[2])


static func _offset64(from: Vector3, to: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([float(to.x) - float(from.x), float(to.y) - float(from.y), float(to.z) - float(from.z)])


func _find(target_id: int) -> TargetInfo:
	for info: TargetInfo in _candidates:
		if info.id == target_id:
			return info
	return null


func _select(target_id: int) -> bool:
	if target_id == _selected_id:
		return false
	_selected_id = target_id
	return true
