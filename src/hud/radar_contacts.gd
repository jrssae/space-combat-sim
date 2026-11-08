class_name RadarContacts
extends RefCounted
## What the radar shows this frame (M4-T36, architecture §17.21): every targetable the player's `TargetingController.candidates()`
## would list (in play, not the ship's own, within its reach), as packed arrays read straight from the targetables. The radar
## needs only a position, a faction and a broadcast range per contact, so building a `TargetInfo` for each and sorting them by
## range, as the candidate list does, was most of the HUD's frame at 500 ships. Since M4-T23 the contacts come from the core's
## rows, ships in the low-attention tier among them.

var ids := PackedInt64Array()
## World-local, as `TargetInfo.position`.
var positions := PackedVector3Array()
## Each contact's faction, as an index into `faction_names` (the core's faction order, M4-T23).
var faction_ix := PackedInt32Array()
var faction_names: Array[StringName] = []
## Each contact's faction, built when read (tests).
var factions: Array[StringName]:
	get:
		var out: Array[StringName] = []
		for k: int in faction_ix:
			out.append(faction_names[k])
		return out
## Each contact's broadcast range (`Targetable.broadcast_range_m`), m: 0 for none, `INF` for everywhere.
var reach := PackedFloat64Array()


func size() -> int:
	return ids.size()


## The contacts a ship's `candidates()` would list, without building the list: the targetables of `tree` in play and not
## under `own_body`, within `sensor_range_m` of it or their own broadcast range, and the low-attention tier's ships, read in
## one pass over the native core's rows (M4-T23: the radar reads rows, not nodes; a frame's walk of the targetables cost more
## than the tier's few hundred extra contacts). Empty in a tree with no core.
static func gather(tree: SceneTree, own_body: Node3D, sensor_range_m: float) -> RadarContacts:
	var out := RadarContacts.new()
	if tree == null or own_body == null or not own_body.is_inside_tree():
		return out
	var sim: SimCore = SimCore.for_tree(tree)
	if sim == null or sim.core == null:
		return out
	var rows: Array = sim.core.radar_contacts(own_body.global_position, own_body.get_instance_id(), sensor_range_m)
	out.ids = rows[0]
	out.positions = rows[1]
	out.faction_ix = rows[2]
	out.reach = rows[3]
	out.faction_names.assign(sim.core.factions())
	return out


## The same contacts from a list of `TargetInfo`s (tests, and a `HudInput` filled by hand).
static func from_infos(infos: Array[TargetInfo]) -> RadarContacts:
	var out := RadarContacts.new()
	for info: TargetInfo in infos:
		out.ids.append(info.id)
		out.positions.append(info.position)
		var k: int = out.faction_names.find(info.faction)
		if k < 0:
			k = out.faction_names.size()
			out.faction_names.append(info.faction)
		out.faction_ix.append(k)
		out.reach.append(info.broadcast_range_m)
	return out
