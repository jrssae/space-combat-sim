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
##
## Native queries (M4-T05b, architecture §17.5): when the native library provides `NATIVE_CLASS` and `perf_native` is on,
## the queries and the freed-body check run in a native field that takes this scan's arrays once, on its first query, and
## answers with body indices; the contact lists are still built here from the shared faction lists. The GDScript code is
## the fallback and the reference, and both give the same answers bit for bit. The setting is read on every query, so a
## flip takes effect at once, even on a scan already in use. A scan's arrays must not change once it has been queried.

const SENSOR_RANGE_M: float = 5000.0
## A hostile bolt is incoming when its closest approach is under this distance within this time.
const INCOMING_MISS_M: float = 15.0
const INCOMING_HORIZON_S: float = 2.0
## The native class that answers the queries when the library is loaded and `perf_native` is on (M4-T05b).
const NATIVE_CLASS: StringName = &"ScsContactField"

## Profiling (M4-T01): while `PerfProbe` is on, `AiPilotDriver` times its calls into the scans and adds them here. Wall
## clock, never gameplay time.
static var timing: bool = false
static var _time_frame: int = -1
static var _time_sum_us: int = 0

static var _shared: ContactScan = null
static var _shared_broadcasts: ContactScan = null
## Returned for a frame with no broadcaster, so a ship that hears nothing allocates nothing. Read, never write.
static var _no_contacts: Array[Contact] = []
# Whether the loaded library provides `NATIVE_CLASS` (-1 until first asked; classes never change while the game runs).
static var _native_class_known: int = -1

## The physics frame this scan is of (-1 for one built by hand).
var physics_frame: int = -1
## False forces the GDScript path for this scan, so a test or a bench can pair it with the native one.
var use_native: bool = true

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
var _stamped: Dictionary = {}  # faction -> Array[Contact] with the relation set, each made when first handed out
var _relations: Dictionary = {}  # faction -> {other faction -> relation}, looked up once per pair
var _hostile_ships: Dictionary = {}  # faction -> PackedByteArray, 1 for a ship hostile to it (nearest-k, M4-T04)
var _extent_m: float = -1.0  # computed on first use
var _bolt_positions: PackedVector3Array = PackedVector3Array()
var _bolt_velocities: PackedVector3Array = PackedVector3Array()
var _bolt_factions: Array[StringName] = []
var _bolt_shooters: PackedInt64Array = PackedInt64Array()
var _hostile_bolts: Dictionary = {}  # faction -> indices of the bolts hostile to it
var _reach: PackedFloat64Array = PackedFloat64Array()  # per body broadcast range (broadcast scan only)
var _field: Object = null  # the native field over this scan's arrays, made on the first native query
var _field_rows: Dictionary = {}  # faction -> true once the field has its hostility row


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


## Which code answers this scan's queries now: &"native" or &"gdscript".
func path() -> StringName:
	return &"native" if _native() != null else &"gdscript"


## Bodies the native field tested in its latest contact or nearest query (the work count), -1 on the GDScript path.
func native_visits() -> int:
	var field: Object = _native()
	return field.visited() if field != null else -1


## The contacts a ship of `own_faction` at `own_position` sees: within `range_m`, never its own body.
func contacts_for(own_body_id: int, own_position: Vector3, own_faction: StringName,
		range_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	var stamped: Array[Contact] = _stamped_for(own_faction)
	var own_index: int = _body_ids.find(own_body_id)
	var field: Object = _native()
	if field != null:
		var found: PackedInt32Array = field.contacts(own_body_id, own_position, range_m)
		if own_index >= 0 and found.size() == stamped.size() - 1:
			return _all_but(own_faction, stamped, own_index)
		return _pick(own_faction, stamped, found)
	# Fast path: everything is in range for sure, so the faction list without this ship is what the loop would build.
	if own_index >= 0 and _extent() + own_position.distance_to(_positions[own_index]) < range_m * 0.999:
		return _all_but(own_faction, stamped, own_index)
	var range_sq: float = range_m * range_m
	var found := PackedInt32Array()
	for i: int in stamped.size():
		if _body_ids[i] != own_body_id and _positions[i].distance_squared_to(own_position) <= range_sq:
			found.append(i)
	return _pick(own_faction, stamped, found)


## The nearest `k` of the contacts `contacts_for` gives (M4-T04), in scan order. When that leaves any out, the nearest
## hostile ship joins them (so a crowd of friends never hides the fight), and so does every contact `keeper` names: it is
## called only then and returns `[PackedInt64Array ids, PackedStringArray names]` (names case-insensitive). With `k` or
## fewer in range it is `contacts_for`'s list, at about `contacts_for`'s cost. Equal ranges go to the earlier body in the scan.
func nearest_for(own_body_id: int, own_position: Vector3, own_faction: StringName, k: int, keeper: Callable = Callable(),
		range_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	var stamped: Array[Contact] = _stamped_for(own_faction)
	if _body_ids.size() <= k:
		return contacts_for(own_body_id, own_position, own_faction, range_m)  # never more than k to cut
	var range_sq: float = range_m * range_m
	var field: Object = _native_with_row(own_faction)
	if field != null:
		var chosen: PackedInt32Array = field.nearest(own_body_id, own_position, own_faction, k, range_m)
		if chosen.is_empty() or chosen[chosen.size() - 1] != -1:
			return _pick(own_faction, stamped, chosen)  # k or fewer in range, in scan order
		chosen.resize(chosen.size() - 1)  # the cut left something out: the nearest k and the nearest hostile
		_keep_named(chosen, keeper, own_body_id, own_position, range_sq)
		chosen.sort()
		return _pick(own_faction, stamped, chosen)
	var hostile: PackedByteArray = _hostile_ships_for(own_faction)
	# Gather like `contacts_for` until more than k are in range; only then select, keeping the nearest k sorted by range.
	var gathered := PackedInt32Array()
	var best_sq := PackedFloat64Array()
	var best := PackedInt32Array()
	var selecting: bool = false
	var limit: float = range_sq
	var hostile_at: int = -1
	var hostile_sq: float = INF
	for i: int in _body_ids.size():
		var d_sq: float = _positions[i].distance_squared_to(own_position)
		if d_sq > range_sq or _body_ids[i] == own_body_id:
			continue
		if not selecting:
			gathered.append(i)
			if gathered.size() <= k:
				continue
			selecting = true
			for j: int in gathered:
				var g_sq: float = _positions[j].distance_squared_to(own_position)
				if hostile[j] == 1 and g_sq < hostile_sq:
					hostile_sq = g_sq
					hostile_at = j
				var g_at: int = best_sq.bsearch(g_sq, false)
				best_sq.insert(g_at, g_sq)
				best.insert(g_at, j)
			best_sq.resize(k)
			best.resize(k)
			limit = best_sq[k - 1]
			continue
		if hostile[i] == 1 and d_sq < hostile_sq:
			hostile_sq = d_sq
			hostile_at = i
		if d_sq > limit:
			continue
		var at: int = best_sq.bsearch(d_sq, false)
		best_sq.insert(at, d_sq)
		best.insert(at, i)
		best_sq.resize(k)
		best.resize(k)
		limit = best_sq[k - 1]
	if not selecting:
		best = gathered  # k or fewer in range: all of them, already in scan order
	else:
		_keep(hostile_at, best, own_body_id, own_position, range_sq)
		_keep_named(best, keeper, own_body_id, own_position, range_sq)
		best.sort()
	return _pick(own_faction, stamped, best)


## The broadcasts a ship hears (from a `from_broadcasters` scan): beyond `near_m`, where contacts take over, and within
## each broadcaster's own range.
func broadcasts_for(own_body_id: int, own_position: Vector3, own_faction: StringName,
		near_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	if _body_ids.is_empty():
		return _no_contacts
	var stamped: Array[Contact] = _stamped_for(own_faction)
	var field: Object = _native()
	if field != null:
		return _pick(own_faction, stamped, field.broadcasts(own_body_id, own_position, near_m))
	var near_sq: float = near_m * near_m
	var found := PackedInt32Array()
	for i: int in stamped.size():
		if _body_ids[i] == own_body_id:
			continue
		var d_sq: float = _positions[i].distance_squared_to(own_position)
		if d_sq > near_sq and d_sq <= _reach[i] * _reach[i]:
			found.append(i)
	return _pick(own_faction, stamped, found)


## How many bolts hostile to `own_faction` (and not this ship's own) pass within `INCOMING_MISS_M` of the ship in the next
## `INCOMING_HORIZON_S`, both flying straight on.
func incoming_fire(own_body_id: int, own_position: Vector3, own_velocity: Vector3, own_faction: StringName) -> int:
	var field: Object = _native_with_row(own_faction)
	if field != null:
		return field.incoming(own_body_id, own_position, own_velocity, own_faction)
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


# Adds what `keeper` names (ids, then names case-insensitive) to a nearest-k selection that left something out.
func _keep_named(chosen: PackedInt32Array, keeper: Callable, own_body_id: int, own_position: Vector3, range_sq: float) -> void:
	if not keeper.is_valid():
		return
	var kept: Array = keeper.call()
	for id: int in kept[0] as PackedInt64Array:
		if id > 0:
			_keep(_ids.find(id), chosen, own_body_id, own_position, range_sq)
	for wanted: String in kept[1] as PackedStringArray:
		for i: int in _names.size():
			if _names[i].length() == wanted.length() and _names[i].nocasecmp_to(wanted) == 0:
				_keep(i, chosen, own_body_id, own_position, range_sq)


# The contacts at `indices` of `faction`'s list, in that order, each made the first time it is handed out.
func _pick(faction: StringName, stamped: Array[Contact], indices: PackedInt32Array) -> Array[Contact]:
	var out: Array[Contact] = []
	for i: int in indices:
		var c: Contact = stamped[i]
		if c == null:
			c = _stamp(faction, i)
			stamped[i] = c
		out.append(c)
	return out


# Every contact of `faction`'s list but body `skip`.
func _all_but(faction: StringName, stamped: Array[Contact], skip: int) -> Array[Contact]:
	for i: int in stamped.size():
		if stamped[i] == null:
			stamped[i] = _stamp(faction, i)
	var all: Array[Contact] = stamped.duplicate()
	all.remove_at(skip)
	return all


# The native field for this query, or null for the GDScript path. Made and loaded on the first native query.
func _native() -> Object:
	if not use_native or not NativeLib.enabled():
		return null
	if _native_class_known < 0:
		_native_class_known = 1 if NativeLib.has_class(NATIVE_CLASS) else 0
	if _native_class_known == 0:
		return null
	if _field == null:
		_field = NativeLib.instantiate(NATIVE_CLASS)
		if _field == null:
			return null
		_field.load(_body_ids, _positions, _factions, _is_ship, _reach, _bolt_positions, _bolt_velocities, _bolt_factions,
				_bolt_shooters, SENSOR_RANGE_M)
	return _field


# The native field, once it knows which factions are hostile to `faction` (from `Factions`, which it never calls itself).
func _native_with_row(faction: StringName) -> Object:
	var field: Object = _native()
	if field != null and not _field_rows.has(faction):
		var row := PackedByteArray()
		for other: StringName in field.factions():
			row.append(1 if _relation(faction, other) == Factions.Relation.HOSTILE else 0)
		field.set_hostile_row(faction, row)
		_field_rows[faction] = true
	return field


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


# The contacts as a ship of `faction` sees them: one list per faction, shared, each contact made when first handed out
# (a broadcaster nobody hears, or a body no ship of the faction sees, costs nothing).
func _stamped_for(faction: StringName) -> Array[Contact]:
	if _stamped.has(faction):
		return _stamped[faction]
	var list: Array[Contact] = []
	list.resize(_body_ids.size())
	_stamped[faction] = list
	return list


# Body `i` as a ship of `faction` sees it.
func _stamp(faction: StringName, i: int) -> Contact:
	var c := Contact.new()
	c.id = _ids[i]
	c.name = _names[i]
	c.faction = _factions[i]
	c.relation = _relation(faction, _factions[i])
	c.position = _positions[i]
	c.velocity = _velocities[i]
	c.forward = _forwards[i]
	c.up = _ups[i]
	c.bounding_radius = _radii[i]
	c.is_ship = _is_ship[i] == 1
	c.hull_fraction = _hulls[i]
	c.target_id = _target_ids[i]
	return c


# How a ship of `faction` regards `other`, looked up once per pair in this scan.
func _relation(faction: StringName, other: StringName) -> Factions.Relation:
	if not _relations.has(faction):
		_relations[faction] = {}
	var known: Dictionary = _relations[faction]
	if not known.has(other):
		known[other] = Factions.relation(faction, other)
	return known[other]


# 1 for each body that is a ship hostile to `faction` (the GDScript nearest-k path).
func _hostile_ships_for(faction: StringName) -> PackedByteArray:
	if _hostile_ships.has(faction):
		return _hostile_ships[faction]
	var hostile := PackedByteArray()
	for i: int in _body_ids.size():
		hostile.append(1 if _is_ship[i] == 1 and _relation(faction, _factions[i]) == Factions.Relation.HOSTILE else 0)
	_hostile_ships[faction] = hostile
	return hostile


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
	var field: Object = _native()
	if field != null:
		return field.bodies_alive()
	for id: int in _body_ids:
		if not is_instance_id_valid(id):
			return false
	return true
