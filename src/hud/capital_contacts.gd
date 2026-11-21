class_name CapitalContacts
extends RefCounted
## The capital ships the HUD may mark this frame (M8-T08): every capital targetable in play, a tier-parked one where its row flies,
## as `{id, position, radius_m, label, faction}` (World-local; `id` is the targetable's, as the selection's). Capitals are few, so
## a walk of their own group is cheap; `CapitalMarksLayout` decides which get a marker.


## The capitals of `tree` within `max_range_m` of `own_body`, not its own.
static func gather(tree: SceneTree, own_body: Node3D, max_range_m: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if tree == null or own_body == null or not own_body.is_inside_tree():
		return out
	var own: Vector3 = own_body.global_position
	for node: Node in tree.get_nodes_in_group(Targetable.CAPITAL_GROUP):
		var t := node as Targetable
		var body := t.get_parent() as Node3D if t != null else null
		if body == null or not t.is_inside_tree() or own_body.is_ancestor_of(t):
			continue
		var tiered: bool = body.has_meta(TierDirector.TIER_META)
		if not tiered and not t.is_active():
			continue  # parked in its pool, docked or destroyed
		var at: Vector3 = TierDirector.flying_position(body) if tiered else body.global_position
		if at.distance_to(own) > max_range_m:
			continue
		var hull: Damageable = Damageable.of(body)
		out.append({"id": t.get_instance_id(), "position": at, "radius_m": hull.bounding_radius if hull != null else 0.0,
				"label": t.class_label if not t.class_label.is_empty() else t.display_name, "faction": t.faction})
	return out
