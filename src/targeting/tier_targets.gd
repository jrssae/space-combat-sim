class_name TierTargets
extends RefCounted
## The low-attention tier's ships as targets (M4-T23, architecture §17.14). A tier ship's node is parked (hidden, not
## processing), so its `Targetable` is not active and its pose is where it was demoted; its row in the native core flies on.
## The player's candidates, the radar and every selection read a tier ship from its row, by its marker's id, so a selection
## names the same `Targetable` before, during and after the tier and survives promotion and demotion.

var ids := PackedInt64Array()
## World-local, as `TargetInfo.position`.
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var factions: Array[StringName] = []
## Each row's broadcast range, m (`Targetable.broadcast_range_m`).
var reach := PackedFloat64Array()
var names := PackedStringArray()
var radii := PackedFloat64Array()
## Hull 0..1.
var hulls := PackedFloat64Array()


func size() -> int:
	return ids.size()


## The tier rows a ship at `own_position` could select: not body `own_body_id`, within `sensor_range_m` or their own
## broadcast range. Empty with no core or no tier rows.
static func gather(tree: SceneTree, own_position: Vector3, own_body_id: int, sensor_range_m: float) -> TierTargets:
	var sim: SimCore = SimCore.for_tree(tree) if tree != null else null
	if sim == null or sim.core == null or int(sim.core.tier_count()) == 0:
		return TierTargets.new()
	return _from_columns(sim.core.tier_targets(own_position, own_body_id, sensor_range_m))


## The tier row whose marker is `target_id` as a target, or null when that marker's ship is not in the tier.
static func info_of(tree: SceneTree, target_id: int) -> TargetInfo:
	var sim: SimCore = SimCore.for_tree(tree) if tree != null else null
	if sim == null or sim.core == null or int(sim.core.tier_count()) == 0:
		return null
	var found: TierTargets = _from_columns(sim.core.tier_target(target_id))
	return found.info(0) if found.size() > 0 else null


## Row `k` as a `TargetInfo` (no damage zones: a row keeps only its hull's fraction).
func info(k: int) -> TargetInfo:
	var out := TargetInfo.new(ids[k], names[k], factions[k], positions[k], velocities[k], hulls[k], radii[k])
	out.broadcast_range_m = reach[k]
	return out


static func _from_columns(columns: Array) -> TierTargets:
	var out := TierTargets.new()
	out.ids = columns[0]
	out.positions = columns[1]
	out.velocities = columns[2]
	out.factions.assign(columns[3])
	out.reach = columns[4]
	out.names = columns[5]
	out.radii = columns[6]
	out.hulls = columns[7]
	return out
