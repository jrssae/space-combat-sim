class_name MineLayers
extends Node
## The capitals that lay mines in battle (M10-T15, Q20): the G'Quan's energy-mine launchers and the Vorchan's guided-mine drops.
## A ship's `mine` mounts (its hardpoints' `weapons[]` of kind `mine`, whose weapon id names the kind in `loadouts.json`) become
## layers of the battle's `MineField`; the core decides when and what each lays (`mine_layers.rs`: a hostile the ship perceives
## in range and cone, a cycle, a cap of mines in play) and lays it as a mine in flight or dormant. This node only joins a ship's
## mounts to the rows and pushes whether each still works (a lost section, a hulk, a wreck). A child of `World`, made when the
## first ship with a mine mount joins.

const NODE_NAME: StringName = &"MineLayers"

var _field: MineField = null
var _ships: Array[CapitalShip] = []
var _layers: Dictionary = {}  # ship -> Array[Dictionary]: {"index": the rows' layer, "name": the mount's}
var _links: Dictionary = {}


## Every `mine` mount of `hardpoints` for hull `type_id`: `{name, weapon, kind (an index of `MineKinds`), section, position,
## forward}` in the file's order. A mount whose weapon is not a laid kind is left out with a warning.
static func of_hardpoints(hardpoints: Dictionary, type_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var weapons: Variant = hardpoints.get("weapons", [])
	if not (weapons is Array):
		return out
	for raw: Variant in weapons:
		var entry: Dictionary = raw if raw is Dictionary else {}
		if str(entry.get("kind", "")) != "mine":
			continue
		var weapon: String = str(entry.get("weapon", ""))
		if weapon.is_empty():
			continue  # a mount no weapon is assigned to yet (a framework hull's)
		var kind: int = MineKinds.index_of(StringName(CapitalData.weapon_kind(weapon)))
		if kind <= MineKinds.PROX or MineKinds.laying(kind).is_empty():
			push_warning("MineLayers: %s's mount %s names %s, which is not a mine laid in battle" % [type_id, entry.get("name", ""), weapon])
			continue
		out.append({"name": str(entry.get("name", "")), "weapon": weapon, "kind": kind, "section": str(entry.get("section", "")),
				"position": _vec3(entry.get("position"), Vector3.ZERO), "forward": _vec3(entry.get("forward"), Vector3.FORWARD)})
	return out


## Joins `ship`'s mine mounts to its world's battle field; nothing for a hull without any.
static func join_ship(ship: CapitalShip, world: WorldFrame) -> void:
	if ship == null or world == null:
		return
	var mounts: Array[Dictionary] = of_hardpoints(ship.hardpoints(), ship.type_id)
	if mounts.is_empty():
		return
	var layers: MineLayers = world.get_node_or_null(NodePath(NODE_NAME)) as MineLayers
	if layers == null:
		layers = MineLayers.new()
		layers.name = NODE_NAME
		world.add_child(layers)
	layers._join(ship, mounts, world)


static func of(world: Node) -> MineLayers:
	return world.get_node_or_null(NodePath(NODE_NAME)) as MineLayers if world != null and is_instance_valid(world) else null


## Takes `ship`'s mounts out of the rows (it left the tree).
func leave(ship: CapitalShip) -> void:
	if not _ships.has(ship):
		return
	_ships.erase(ship)
	if _field != null and is_instance_valid(_field) and _field.rows != null:
		_field.rows.remove_owner(ship.get_instance_id())
	_layers.erase(ship)
	for link: Array in _links.get(ship, []):
		if (link[0] as Signal).is_connected(link[1]):
			(link[0] as Signal).disconnect(link[1])
	_links.erase(ship)


## Pushes whether each of `ship`'s mine mounts still works: its hull, its section and its mount alive.
func refresh(ship: CapitalShip) -> void:
	if not is_instance_valid(ship) or not _layers.has(ship) or _field == null or _field.rows == null:
		return
	var alive: bool = not ship.damageable.hull.destroyed
	for layer: Dictionary in _layers[ship]:
		_field.rows.set_layer_works(int(layer["index"]), alive and ship.mount_works(str(layer["name"])))


## How many layers the battle's rows hold.
func layer_count() -> int:
	return int(_field.rows.layer_count()) if _field != null and _field.rows != null else 0


func _join(ship: CapitalShip, mounts: Array[Dictionary], world: WorldFrame) -> void:
	if _field == null or not is_instance_valid(_field):
		_field = MineField.battle(world)
	if _field.rows == null:
		return
	if _ships.has(ship):
		leave(ship)
	var made: Array[Dictionary] = []
	for m: Dictionary in mounts:
		var index: int = _field.add_layer(ship.get_instance_id(), m["position"], m["forward"], int(m["kind"]), MineKinds.laying(int(m["kind"])))
		if index >= 0:
			made.append({"index": index, "name": m["name"]})
	if made.is_empty():
		return
	_ships.append(ship)
	_layers[ship] = made
	var changed: Callable = refresh.bind(ship)
	var links: Array = [[ship.mount_lost, changed.unbind(1)], [ship.section_changed, changed.unbind(2)],
			[ship.ship_disabled, changed], [ship.damageable.restored, changed], [ship.damageable.destroyed, changed.unbind(1)]]
	for link: Array in links:
		(link[0] as Signal).connect(link[1])
	_links[ship] = links
	refresh(ship)


static func _vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Array and (raw as Array).size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback
