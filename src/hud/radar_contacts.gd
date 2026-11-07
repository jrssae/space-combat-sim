class_name RadarContacts
extends RefCounted
## What the radar shows this frame (M4-T36, architecture §17.21): every targetable the player's `TargetingController.candidates()`
## would list (in play, not the ship's own, within its reach), as packed arrays read straight from the targetables. The radar
## needs only a position, a faction and a broadcast range per contact, so building a `TargetInfo` for each and sorting them by
## range, as the candidate list does, was most of the HUD's frame at 500 ships. Ships in the low-attention tier come from
## their rows in the core (`TierTargets`, M4-T23).

var ids := PackedInt64Array()
## World-local, as `TargetInfo.position`.
var positions := PackedVector3Array()
var factions: Array[StringName] = []
## Each contact's broadcast range (`Targetable.broadcast_range_m`), m: 0 for none, `INF` for everywhere.
var reach := PackedFloat64Array()


func size() -> int:
	return ids.size()


## The contacts a ship's `candidates()` would list, without building the list: the targetables of `tree` in play and not
## under `own_body`, within `sensor_range_m` of it or their own broadcast range.
static func gather(tree: SceneTree, own_body: Node3D, sensor_range_m: float) -> RadarContacts:
	var out := RadarContacts.new()
	if tree == null or own_body == null or not own_body.is_inside_tree():
		return out
	var own: Vector3 = own_body.global_position
	for node: Node in tree.get_nodes_in_group(Targetable.GROUP):
		var targetable := node as Targetable
		if targetable == null or own_body.is_ancestor_of(targetable) or not targetable.is_active():
			continue
		var at: Vector3 = targetable.global_position
		if TargetingSystem.range_between(own, at) > maxf(sensor_range_m, targetable.broadcast_range_m):
			continue
		out.ids.append(targetable.get_instance_id())
		out.positions.append(at)
		out.factions.append(targetable.faction)
		out.reach.append(targetable.broadcast_range_m)
	# Ships in the low-attention tier have parked nodes: their rows stand in for them (M4-T23).
	var rows: TierTargets = TierTargets.gather(tree, own, own_body.get_instance_id(), sensor_range_m)
	out.ids.append_array(rows.ids)
	out.positions.append_array(rows.positions)
	out.factions.append_array(rows.factions)
	out.reach.append_array(rows.reach)
	return out


## The same contacts from a list of `TargetInfo`s (tests, and a `HudInput` filled by hand).
static func from_infos(infos: Array[TargetInfo]) -> RadarContacts:
	var out := RadarContacts.new()
	for info: TargetInfo in infos:
		out.ids.append(info.id)
		out.positions.append(info.position)
		out.factions.append(info.faction)
		out.reach.append(info.broadcast_range_m)
	return out
