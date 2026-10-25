class_name ContactScan
extends RefCounted
## What every AI ship can see this tick (architecture §16 D33, §16.3): one list of `Contact`s built from the active
## `Targetable`s and `Damageable`s in the tree, and the bolts in flight. The first `AiPilotDriver` of a physics tick builds
## it (`shared`, a process-wide cache keyed by `Engine.get_physics_frames()`); the others reuse it. The drivers run at
## priority -10, before any ship, bolt or rebase moves anything, so one snapshot is right for all of them.
##
## A body with both a `Targetable` and a `Damageable` (every ship, every buoy) is one contact; it counts while either is
## active, so a parked pool ship (hidden, not processing) is never one. `contacts_for` gives one ship the contacts within
## `SENSOR_RANGE_M` but itself, stamped with its relation to them: the scan keeps each body's data in packed arrays and
## builds the `Contact`s of a faction from them once, the first time a ship of that faction asks, shared by every ship of
## that faction (read-only). When every two bodies are within sensor range of each other (a fight), a ship's list is that
## faction list without itself, copied in one go. `incoming_fire` counts the hostile bolts about to pass close by.
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

# Per body, in scan order (packed: the scan runs every tick, AC13's budget).
var _body_ids: PackedInt64Array = PackedInt64Array()
var _ids: PackedInt64Array = PackedInt64Array()
var _names: PackedStringArray = PackedStringArray()
var _factions: Array[StringName] = []
var _positions: PackedVector3Array = PackedVector3Array()
var _velocities: PackedVector3Array = PackedVector3Array()
var _forwards: PackedVector3Array = PackedVector3Array()
var _ups: PackedVector3Array = PackedVector3Array()
var _radii: PackedFloat64Array = PackedFloat64Array()
var _is_ship: PackedByteArray = PackedByteArray()
var _hulls: PackedFloat64Array = PackedFloat64Array()
var _target_ids: PackedInt64Array = PackedInt64Array()
var _stamped: Dictionary = {}  # faction StringName -> Array[Contact] with the relation set
var _extent_m: float = -1.0  # the diagonal of the box round every body, computed on first use
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
	# Each body's hull, as `Damageable.of` finds it (its first one), from the group once instead of a walk over every body's
	# children (AC13's budget).
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
			scan._add(body, targetable, hulls.get(body.get_instance_id()) as Damageable)
	for node: Node in damageable_nodes:
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
	var own_index: int = _body_ids.find(own_body_id)
	# Every body within `range_m` of this ship for sure (the box round them all, plus how far the ship moved since the scan,
	# with a margin for rounding): the faction list without the ship itself, the same list the loop below would build.
	if own_index >= 0 and _extent() + own_position.distance_to(_positions[own_index]) < range_m * 0.999:
		var all: Array[Contact] = stamped.duplicate()
		all.remove_at(own_index)
		return all
	var range_sq: float = range_m * range_m
	var out: Array[Contact] = []
	for i: int in stamped.size():
		if _body_ids[i] != own_body_id and _positions[i].distance_squared_to(own_position) <= range_sq:
			out.append(stamped[i])
	return out


## How many bolts hostile to `own_faction` (and not this ship's own) pass within `INCOMING_MISS_M` of the ship in the next
## `INCOMING_HORIZON_S`, both flying straight on.
func incoming_fire(own_body_id: int, own_position: Vector3, own_velocity: Vector3, own_faction: StringName) -> int:
	var count: int = 0
	for i: int in _hostile_bolts_for(own_faction):
		if _bolt_shooters[i] == own_body_id:
			continue
		var rel_pos: Vector3 = _bolt_positions[i] - own_position
		var rel_vel: Vector3 = _bolt_velocities[i] - own_velocity
		# Farther than it can close in the horizon plus the miss distance (and a metre for rounding): it cannot pass close.
		var reach: float = rel_vel.length() * INCOMING_HORIZON_S + INCOMING_MISS_M + 1.0
		if rel_pos.length_squared() > reach * reach:
			continue
		if AvoidanceMath.closest_approach(rel_pos, rel_vel, INCOMING_HORIZON_S) < INCOMING_MISS_M:
			count += 1
	return count


func _add(body: Node3D, targetable: Targetable, damageable: Damageable) -> void:
	_body_ids.append(body.get_instance_id())
	_ids.append(targetable.get_instance_id() if targetable != null else body.get_instance_id())
	_names.append(targetable.display_name if targetable != null else "")
	if targetable != null:
		_factions.append(targetable.faction)
	elif damageable != null:
		_factions.append(damageable.faction)
	else:
		_factions.append(Factions.NEUTRAL)
	_positions.append(body.global_position)
	var rigid := body as RigidBody3D
	if rigid != null:
		_velocities.append(rigid.linear_velocity)
	elif targetable != null:
		_velocities.append(targetable.velocity)
	else:
		_velocities.append(Vector3.ZERO)
	var basis: Basis = body.global_basis
	_forwards.append(-basis.z.normalized())
	_ups.append(basis.y.normalized())
	_radii.append(damageable.bounding_radius if damageable != null else 0.0)
	_is_ship.append(1 if rigid != null else 0)
	_hulls.append(damageable.hull.fraction() if damageable != null else -1.0)
	var ship := body as Ship
	if ship != null and ship.targeting != null and ship.targeting.system.has_selection():
		_target_ids.append(ship.targeting.system.selected_id())
	else:
		_target_ids.append(-1)


# The contacts as a ship of `faction` sees them, built once per faction from the packed arrays.
func _stamped_for(faction: StringName) -> Array[Contact]:
	if _stamped.has(faction):
		return _stamped[faction]
	var list: Array[Contact] = []
	var relations: Dictionary = {}  # contact faction -> relation, looked up once per faction pair
	for i: int in _body_ids.size():
		var c := Contact.new()
		c.id = _ids[i]
		c.name = _names[i]
		var other: StringName = _factions[i]
		c.faction = other
		if not relations.has(other):
			relations[other] = Factions.relation(faction, other)
		c.relation = relations[other]
		c.position = _positions[i]
		c.velocity = _velocities[i]
		c.forward = _forwards[i]
		c.up = _ups[i]
		c.bounding_radius = _radii[i]
		c.is_ship = _is_ship[i] == 1
		c.hull_fraction = _hulls[i]
		c.target_id = _target_ids[i]
		list.append(c)
	_stamped[faction] = list
	return list


# The diagonal of the box round every body (an upper bound on the distance between any two of them).
func _extent() -> float:
	if _extent_m < 0.0:
		var lo: Vector3 = Vector3.INF
		var hi: Vector3 = -Vector3.INF
		for at: Vector3 in _positions:
			lo = lo.min(at)
			hi = hi.max(at)
		_extent_m = (hi - lo).length() if not _positions.is_empty() else 0.0
	return _extent_m


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
