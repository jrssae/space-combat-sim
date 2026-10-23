class_name ContactScan
extends RefCounted
## What every AI ship can see this tick (architecture §16 D33, §16.3): one list of `Contact`s built from the active
## `Targetable`s and `Damageable`s in the tree, and the bolts in flight. The first `AiPilotDriver` of a physics tick builds
## it (`shared`, a process-wide cache keyed by `Engine.get_physics_frames()`); the others reuse it. The drivers run at
## priority -10, before any ship, bolt or rebase moves anything, so one snapshot is right for all of them.
##
## A body with both a `Targetable` and a `Damageable` (every ship, every buoy) is one contact; it counts while either is
## active, so a parked pool ship (hidden, not processing) is never one. `contacts_for` gives one ship the contacts within
## `SENSOR_RANGE_M` but itself, stamped with its relation to them: the stamped copies are made once per faction and shared
## by every ship of that faction (read-only). `incoming_fire` counts the hostile bolts about to pass close by.
##
## Within a frame the cache is rebuilt when a body it saw has been freed (a test that tears its world down mid-frame); a
## body added later in the same frame appears from the next one. Tests that need a fresh scan call `invalidate()`.

const SENSOR_RANGE_M: float = 5000.0
## A hostile bolt is incoming when its closest approach is under this distance within this time.
const INCOMING_MISS_M: float = 15.0
const INCOMING_HORIZON_S: float = 2.0

static var _shared: ContactScan = null

## The physics frame this scan is of (-1 for one built by hand).
var physics_frame: int = -1

var _contacts: Array[Contact] = []
var _body_ids: PackedInt64Array = PackedInt64Array()
var _stamped: Dictionary = {}  # faction StringName -> Array[Contact] with the relation set
var _bolt_positions: PackedVector3Array = PackedVector3Array()
var _bolt_velocities: PackedVector3Array = PackedVector3Array()
var _bolt_factions: Array[StringName] = []
var _bolt_shooters: PackedInt64Array = PackedInt64Array()
var _hostile_bolts: Dictionary = {}  # faction StringName -> PackedInt32Array of the bolts hostile to it


## The scan of the current physics frame, built on the first call of the frame.
static func shared(tree: SceneTree) -> ContactScan:
	var frame: int = Engine.get_physics_frames()
	if _shared == null or _shared.physics_frame != frame or not _shared._bodies_alive():
		_shared = from_tree(tree)
		_shared.physics_frame = frame
	return _shared


## Drops the shared scan; the next `shared` call builds a new one.
static func invalidate() -> void:
	_shared = null


## A scan of the tree as it is now (no cache).
static func from_tree(tree: SceneTree) -> ContactScan:
	var scan := ContactScan.new()
	var seen: Dictionary = {}
	for node: Node in tree.get_nodes_in_group(Targetable.GROUP):
		var targetable := node as Targetable
		if targetable == null or not targetable.is_active():
			continue
		var body := targetable.get_parent() as Node3D
		if body != null and not seen.has(body.get_instance_id()):
			seen[body.get_instance_id()] = true
			scan._add(body, targetable, Damageable.of(body))
	for node: Node in tree.get_nodes_in_group(Damageable.GROUP):
		var damageable := node as Damageable
		if damageable == null or not damageable.is_active():
			continue
		var body: Node3D = damageable.body()
		if body != null and not seen.has(body.get_instance_id()):
			seen[body.get_instance_id()] = true
			scan._add(body, null, damageable)
	for node: Node in tree.get_nodes_in_group(Projectile.GROUP):
		var bolt := node as Projectile
		if bolt == null or bolt.is_spent() or not bolt.is_inside_tree():
			continue
		scan._bolt_positions.append(bolt.global_position)
		scan._bolt_velocities.append(bolt.velocity)
		scan._bolt_factions.append(bolt.faction)
		scan._bolt_shooters.append(bolt.shooter_id)
	return scan


## The contacts a ship of `own_faction` at `own_position` sees: within `range_m`, never its own body.
func contacts_for(own_body_id: int, own_position: Vector3, own_faction: StringName,
		range_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	var stamped: Array[Contact] = _stamped_for(own_faction)
	var range_sq: float = range_m * range_m
	var out: Array[Contact] = []
	for i: int in stamped.size():
		if _body_ids[i] != own_body_id and stamped[i].position.distance_squared_to(own_position) <= range_sq:
			out.append(stamped[i])
	return out


## How many bolts hostile to `own_faction` (and not this ship's own) pass within `INCOMING_MISS_M` of the ship in the next
## `INCOMING_HORIZON_S`, both flying straight on.
func incoming_fire(own_body_id: int, own_position: Vector3, own_velocity: Vector3, own_faction: StringName) -> int:
	var count: int = 0
	for i: int in _hostile_bolts_for(own_faction):
		if _bolt_shooters[i] == own_body_id:
			continue
		var miss: float = AvoidanceMath.closest_approach(_bolt_positions[i] - own_position, _bolt_velocities[i] - own_velocity,
				INCOMING_HORIZON_S)
		if miss < INCOMING_MISS_M:
			count += 1
	return count


func _add(body: Node3D, targetable: Targetable, damageable: Damageable) -> void:
	var c := Contact.new()
	c.id = targetable.get_instance_id() if targetable != null else body.get_instance_id()
	c.name = targetable.display_name if targetable != null else ""
	if targetable != null:
		c.faction = targetable.faction
	elif damageable != null:
		c.faction = damageable.faction
	c.position = body.global_position
	var rigid := body as RigidBody3D
	if rigid != null:
		c.velocity = rigid.linear_velocity
	elif targetable != null:
		c.velocity = targetable.velocity
	c.forward = -body.global_basis.z.normalized()
	c.bounding_radius = damageable.bounding_radius if damageable != null else 0.0
	c.is_ship = rigid != null
	c.hull_fraction = damageable.hull.fraction() if damageable != null else -1.0
	var ship := body as Ship
	if ship != null and ship.targeting != null and ship.targeting.system.has_selection():
		c.target_id = ship.targeting.system.selected_id()
	_contacts.append(c)
	_body_ids.append(body.get_instance_id())


func _stamped_for(faction: StringName) -> Array[Contact]:
	if _stamped.has(faction):
		return _stamped[faction]
	var list: Array[Contact] = []
	for c: Contact in _contacts:
		list.append(c.with_relation(Factions.relation(faction, c.faction)))
	_stamped[faction] = list
	return list


# The bolts hostile to `faction`, resolved once per faction per scan (the relation lookup is the costly part per bolt).
func _hostile_bolts_for(faction: StringName) -> PackedInt32Array:
	if _hostile_bolts.has(faction):
		return _hostile_bolts[faction]
	var hostile: Dictionary = {}  # bolt faction -> bool
	var list := PackedInt32Array()
	for i: int in _bolt_factions.size():
		var bolt_faction: StringName = _bolt_factions[i]
		if not hostile.has(bolt_faction):
			hostile[bolt_faction] = Factions.is_hostile(faction, bolt_faction)
		if hostile[bolt_faction]:
			list.append(i)
	_hostile_bolts[faction] = list
	return list


func _bodies_alive() -> bool:
	for id: int in _body_ids:
		if not is_instance_id_valid(id):
			return false
	return true
