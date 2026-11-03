class_name ContactScan
extends RefCounted
## What every AI ship can see this tick (architecture §16 D33, §16.3): one list of `Contact`s built from the active
## `Targetable`s and `Damageable`s in the tree, and the bolts in flight. The first `AiPilotDriver` of a physics tick builds it
## (`shared`, cached per physics frame) and the others reuse it. Drivers run at priority -10, before anything moves, so one
## snapshot is right for all.
##
## A body with both a `Targetable` and a `Damageable` is one contact, counted while either is active, so a parked pool ship
## is never one. `contacts_for` gives one ship the contacts within `SENSOR_RANGE_M` but itself, stamped with its relation.
## Each faction's stamped list is built once from packed arrays and shared read-only by all its ships. `incoming_fire` counts
## the hostile bolts about to pass close by.
##
## Broadcasts (M3-T17, Q21): `shared_broadcasts` is a second, short scan built from `Targetable.broadcasters()` alone (buoys
## and allies, never a sweep over every body). `broadcasts_for` gives one ship those beyond the near `SENSOR_RANGE_M` and
## within each broadcaster's own `broadcast_range_m`. Every faction hears the same broadcasts at the same ranges.
##
## The cache is rebuilt within a frame if a body it saw was freed; a body added later appears next frame. Tests that need a
## fresh scan call `invalidate()`.

const SENSOR_RANGE_M: float = 5000.0
## A hostile bolt is incoming when its closest approach is under this distance within this time.
const INCOMING_MISS_M: float = 15.0
const INCOMING_HORIZON_S: float = 2.0

## Profiling (M4-T01): while `PerfProbe` is on, `AiPilotDriver` times its calls into the scans and adds them here. Wall
## clock, never gameplay time.
static var timing: bool = false
static var _time_frame: int = -1
static var _time_sum_us: int = 0

static var _shared: ContactScan = null
static var _shared_broadcasts: ContactScan = null
## Returned for a frame with no broadcaster, so a ship that hears nothing allocates nothing. Read, never write.
static var _no_contacts: Array[Contact] = []

## The physics frame this scan is of (-1 for one built by hand).
var physics_frame: int = -1

# Per body, in scan order. Packed because the scan runs every tick (AC13's budget).
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
var _stamped: Dictionary = {}  # faction -> Array[Contact] with the relation set
var _hostile_ships: Dictionary = {}  # faction -> PackedByteArray, 1 for a ship hostile to it (nearest-k, M4-T04)
var _extent_m: float = -1.0  # computed on first use
var _bolt_positions: PackedVector3Array = PackedVector3Array()
var _bolt_velocities: PackedVector3Array = PackedVector3Array()
var _bolt_factions: Array[StringName] = []
var _bolt_shooters: PackedInt64Array = PackedInt64Array()
var _hostile_bolts: Dictionary = {}  # faction -> indices of the bolts hostile to it
var _reach: PackedFloat64Array = PackedFloat64Array()  # per body broadcast range (broadcast scan only)


## The scan of the current physics frame, built on the first call of the frame.
static func shared(tree: SceneTree) -> ContactScan:
	var frame: int = Engine.get_physics_frames()
	if _shared == null or _shared.physics_frame != frame or not _shared._bodies_alive():
		_shared = from_tree(tree)
		_shared.physics_frame = frame
	return _shared


## Adds one ship's scan time to this tick's total (`timing`).
static func add_time(us: int) -> void:
	var frame: int = Engine.get_physics_frames()
	if frame != _time_frame:
		_time_frame = frame
		_time_sum_us = 0
	_time_sum_us += us


## Microseconds spent building and querying the scans in the current physics tick (0 when nothing was timed).
static func time_this_tick_us() -> int:
	return _time_sum_us if _time_frame == Engine.get_physics_frames() else 0


## Drops the shared scans; the next `shared` (and `shared_broadcasts`) call builds a new one.
static func invalidate() -> void:
	_shared = null
	_shared_broadcasts = null


## The broadcasters of the current physics frame, built on the first call of the frame from `Targetable.broadcasters()`.
static func shared_broadcasts() -> ContactScan:
	var frame: int = Engine.get_physics_frames()
	if _shared_broadcasts == null or _shared_broadcasts.physics_frame != frame or not _shared_broadcasts._bodies_alive():
		_shared_broadcasts = from_broadcasters(Targetable.broadcasters())
		_shared_broadcasts.physics_frame = frame
	return _shared_broadcasts


## A scan of the active targetables in `list` only (no cache), each with its broadcast range.
static func from_broadcasters(list: Array[Targetable]) -> ContactScan:
	var scan := ContactScan.new()
	for targetable: Targetable in list:
		if not targetable.is_active():
			continue
		var body := targetable.get_parent() as Node3D
		if body == null:
			continue
		scan._add(body, targetable, Damageable.of(body))
		scan._reach.append(targetable.broadcast_range_m)
	return scan


## A scan of the tree as it is now (no cache).
static func from_tree(tree: SceneTree) -> ContactScan:
	var scan := ContactScan.new()
	var seen: Dictionary = {}
	# Hulls found from the group once, not by walking every body's children (AC13's budget).
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
	# Fast path: everything is in range for sure, so the faction list without this ship is what the loop would build.
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


## The nearest `k` of the contacts `contacts_for` gives (M4-T04), in scan order. When that leaves any out, the nearest
## hostile ship joins them (so a crowd of friends never hides the fight), and so does every contact `keeper` names: it is
## called only then and returns `[PackedInt64Array ids, PackedStringArray names]` (names case-insensitive). With `k` or
## fewer in range it is `contacts_for`'s list. Equal ranges go to the earlier body in the scan.
func nearest_for(own_body_id: int, own_position: Vector3, own_faction: StringName, k: int, keeper: Callable = Callable(),
		range_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	var stamped: Array[Contact] = _stamped_for(own_faction)
	var hostile: PackedByteArray = _hostile_ships[own_faction]
	var range_sq: float = range_m * range_m
	# The nearest so far, sorted by range: a partial selection, no sort of the whole list.
	var best_sq := PackedFloat64Array()
	var best := PackedInt32Array()
	var limit: float = range_sq
	var dropped: bool = false
	var hostile_at: int = -1
	var hostile_sq: float = INF
	for i: int in _body_ids.size():
		var d_sq: float = _positions[i].distance_squared_to(own_position)
		if d_sq > range_sq or _body_ids[i] == own_body_id:
			continue
		if hostile[i] == 1 and d_sq < hostile_sq:
			hostile_sq = d_sq
			hostile_at = i
		if d_sq > limit:
			dropped = true
			continue
		var at: int = best_sq.bsearch(d_sq, false)
		best_sq.insert(at, d_sq)
		best.insert(at, i)
		if best.size() >= k:
			dropped = dropped or best.size() > k
			best_sq.resize(k)
			best.resize(k)
			limit = best_sq[k - 1]
	if dropped:
		_keep(hostile_at, best, own_body_id, own_position, range_sq)
		if keeper.is_valid():
			var kept: Array = keeper.call()
			for id: int in kept[0] as PackedInt64Array:
				if id > 0:
					_keep(_ids.find(id), best, own_body_id, own_position, range_sq)
			for wanted: String in kept[1] as PackedStringArray:
				for i: int in _names.size():
					if _names[i].length() == wanted.length() and _names[i].nocasecmp_to(wanted) == 0:
						_keep(i, best, own_body_id, own_position, range_sq)
	best.sort()
	var out: Array[Contact] = []
	for i: int in best:
		out.append(stamped[i])
	return out


## The broadcasts a ship hears (from a `from_broadcasters` scan): beyond `near_m`, where contacts take over, and within
## each broadcaster's own range.
func broadcasts_for(own_body_id: int, own_position: Vector3, own_faction: StringName,
		near_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	if _body_ids.is_empty():
		return _no_contacts
	var stamped: Array[Contact] = _stamped_for(own_faction)
	var near_sq: float = near_m * near_m
	var out: Array[Contact] = []
	for i: int in stamped.size():
		if _body_ids[i] == own_body_id:
			continue
		var d_sq: float = _positions[i].distance_squared_to(own_position)
		if d_sq > near_sq and d_sq <= _reach[i] * _reach[i]:
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
		# Too far to close within the horizon, so it cannot pass close.
		var reach: float = rel_vel.length() * INCOMING_HORIZON_S + INCOMING_MISS_M + 1.0
		if rel_pos.length_squared() > reach * reach:
			continue
		if AvoidanceMath.closest_approach(rel_pos, rel_vel, INCOMING_HORIZON_S) < INCOMING_MISS_M:
			count += 1
	return count


# Adds body `i` to a nearest-k selection when it is in range, not the ship's own and not in it yet.
func _keep(i: int, chosen: PackedInt32Array, own_body_id: int, own_position: Vector3, range_sq: float) -> void:
	if i >= 0 and _body_ids[i] != own_body_id and not chosen.has(i) \
			and _positions[i].distance_squared_to(own_position) <= range_sq:
		chosen.append(i)


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


# The contacts as a ship of `faction` sees them, built once per faction.
func _stamped_for(faction: StringName) -> Array[Contact]:
	if _stamped.has(faction):
		return _stamped[faction]
	var list: Array[Contact] = []
	var hostile := PackedByteArray()
	var relations: Dictionary = {}  # looked up once per faction pair
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
		hostile.append(1 if c.is_ship and c.relation == Factions.Relation.HOSTILE else 0)
	_stamped[faction] = list
	_hostile_ships[faction] = hostile
	return list


# Upper bound on the distance between any two bodies.
func _extent() -> float:
	if _extent_m < 0.0:
		var lo: Vector3 = Vector3.INF
		var hi: Vector3 = -Vector3.INF
		for at: Vector3 in _positions:
			lo = lo.min(at)
			hi = hi.max(at)
		_extent_m = (hi - lo).length() if not _positions.is_empty() else 0.0
	return _extent_m


# The bolts hostile to `faction`, resolved once per faction because the relation lookup is the costly part.
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
