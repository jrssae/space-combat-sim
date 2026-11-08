class_name TreeRows
extends RefCounted
## The oracle the core's rows are checked against (M4-T42): a scan built by reading the tree's bodies node by node, as
## the game read them before every world attached the core. Tests only; the game reads the core's rows. It fills
## `ContactScan`'s private columns, so a change to the scan's layout changes this file too.


## The active bodies of `tree` (one row per body with an active marker or hull, markers first), the node-less static rows
## after them, and the live bolts, as a hand-built `ContactScan` that reads each contact's hull and selection when handed out.
static func scan(tree: SceneTree) -> ContactScan:
	var s := ContactScan.new()
	s._live = true
	var seen: Dictionary = {}
	var damageable_nodes: Array[Node] = tree.get_nodes_in_group(Damageable.GROUP)
	var hulls: Dictionary = {}  # body instance id -> Damageable
	for node: Node in damageable_nodes:
		var damageable := node as Damageable
		var owner: Node = damageable.get_parent() if damageable != null else null
		if owner != null and not hulls.has(owner.get_instance_id()):
			hulls[owner.get_instance_id()] = damageable
	for node: Node in tree.get_nodes_in_group(Targetable.GROUP):
		var targetable := node as Targetable
		if targetable == null or not targetable.is_active():
			continue
		var body := targetable.get_parent() as Node3D
		if body != null and not seen.has(body.get_instance_id()):
			seen[body.get_instance_id()] = true
			_add(s, body, targetable, hulls.get(body.get_instance_id()) as Damageable)
	for node: Node in damageable_nodes:
		var damageable := node as Damageable
		if damageable == null or not damageable.is_active():
			continue
		var body: Node3D = damageable.body()
		if body != null and not seen.has(body.get_instance_id()):
			seen[body.get_instance_id()] = true
			_add(s, body, null, damageable)
	s._node_count = s._body_ids.size()
	_append_static_rows(s)
	for node: Node in tree.get_nodes_in_group(Projectile.GROUP):
		var bolt := node as Projectile
		if bolt == null or bolt.is_spent() or not bolt.is_inside_tree():
			continue
		s._bolt_positions.append(bolt.global_position)
		s._bolt_velocities.append(bolt.velocity)
		s._bolt_factions.append(bolt.faction)
		s._bolt_shooters.append(bolt.shooter_id)
	return s


static func _add(s: ContactScan, body: Node3D, targetable: Targetable, damageable: Damageable) -> void:
	s._body_ids.append(body.get_instance_id())
	s._ids.append(targetable.get_instance_id() if targetable != null else body.get_instance_id())
	s._names.append(targetable.display_name if targetable != null else "")
	if targetable != null:
		s._factions.append(targetable.faction)
	elif damageable != null:
		s._factions.append(damageable.faction)
	else:
		s._factions.append(Factions.NEUTRAL)
	s._positions.append(body.global_position)
	var rigid := body as RigidBody3D
	if rigid != null:
		s._velocities.append(rigid.linear_velocity)
	elif targetable != null:
		s._velocities.append(targetable.velocity)
	else:
		s._velocities.append(Vector3.ZERO)
	var basis: Basis = body.global_basis
	s._forwards.append(-basis.z.normalized())
	s._ups.append(basis.y.normalized())
	s._radii.append(damageable.bounding_radius if damageable != null else 0.0)
	s._is_ship.append(1 if rigid != null else 0)
	s._hull_ids.append(damageable.get_instance_id() if damageable != null else 0)
	s._kinds.append(BodyKind.of(targetable))


static func _append_static_rows(s: ContactScan) -> void:
	var columns: Dictionary = StaticRows.scan_columns()
	s._body_ids.append_array(StaticRows.ids)
	s._ids.append_array(StaticRows.ids)
	s._names.append_array(columns["names"])
	s._factions.append_array(StaticRows.factions)
	s._positions.append_array(StaticRows.positions)
	s._velocities.append_array(columns["zeros"])
	s._forwards.append_array(columns["forwards"])
	s._ups.append_array(columns["ups"])
	s._radii.append_array(StaticRows.radii)
	s._is_ship.append_array(columns["not_ship"])
	s._hull_ids.append_array(columns["no_hull"])
	s._kinds.append_array(StaticRows.kinds)


## The core's scan of `tree` as its bodies stand now: read again first, since a test moves bodies by hand between ticks.
## Null when the tree has no world (so no core).
static func core_scan(tree: SceneTree) -> ContactScan:
	var sim: SimCore = SimCore.for_tree(tree)
	if sim == null or not sim.sync_now():
		return null
	return ContactScan.from_core(tree)


## The active broadcasters of `list`, in that order, each with its broadcast range: the broadcast scan's oracle.
static func broadcasts(list: Array[Targetable]) -> ContactScan:
	var s := ContactScan.new()
	s._live = true
	for targetable: Targetable in list:
		if not targetable.is_active():
			continue
		var body := targetable.get_parent() as Node3D
		if body == null:
			continue
		_add(s, body, targetable, Damageable.of(body))
		s._reach.append(targetable.broadcast_range_m)
	return s
