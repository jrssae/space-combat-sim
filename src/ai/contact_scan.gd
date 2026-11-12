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
## One hull read (M4-T42): every world attaches the native core (`WorldFrame`), so `shared` is always the core's rows
## (`from_core`); a tree with no world has no core and sees nothing.
##
## Native queries (M4-T05b, architecture §17.5): the native library's `NATIVE_CLASS` (required since M4-T37) answers:
## the queries and the freed-body check run in a native field that takes this scan's arrays once, on its first query, and
## answers with body indices; the contact lists are still built here from the shared faction lists. The GDScript loops it
## matched bit for bit went in M4-T42 (their answers are recorded in `tests/fixtures/parity/contact_field.json`); a scan
## whose arrays the field refuses (it logs why) answers nothing. A scan's arrays must not change once it has been queried.
##
## A contact's hull and selection are read when it is first handed out (a driver's own selection change after the build is
## taken as it was, `note_selection`).
## Kinds (`BodyKind`): rocks and mines are never contacts; `statics_for` gives a ship its nearest ones as obstacles. Rows
## with no node (an asteroid field's rocks, a belt's mines) live in `StaticRows` (M4-T29): `register_static` adds one, a
## rebase moves them, and the scan appends them whole. A side knows only its own and its friends' mines (Q27).
##
## The native core (M4-T15, architecture §17.13): with a `SimCore` attached to the world, `shared` comes from the core's
## rows (`from_core`, the same rows the tree's own gather read before M4-T42, bit for bit) and the field reads the core
## directly (bodies, statics and bolts) instead of taking a copy.
##
## The pilot kernels (M4-T16, architecture §17.13): a core scan's rows are the core's, in its order, so the indices a list
## was picked from (`picked_rows`) name the core rows of its contacts. `pilot_kernels` gives the native kernels that answer
## avoidance, the fire lane and the context lists from those rows, and `relation_row` a faction's relations in the core's
## faction order; both null or empty off the core.

const SENSOR_RANGE_M: float = 5000.0
## A hostile bolt is incoming when its closest approach is under this distance within this time.
const INCOMING_MISS_M: float = 15.0
const INCOMING_HORIZON_S: float = 2.0
## The native class that answers the queries (M4-T05b).
const NATIVE_CLASS: StringName = &"ScsContactField"
## The native pilot kernels a core scan hands its ships (M4-T16).
const PILOT_CLASS: StringName = &"ScsPilotKernels"

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

## The physics frame this scan is of (-1 for one built by hand).
var physics_frame: int = -1
## The scan rows of the latest list `contacts_for`, `nearest_for` or `statics_for` handed out, in its order (M4-T16): on a
## core scan, the core rows the pilot kernels read.
var picked_rows: PackedInt32Array = PackedInt32Array()

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
# A scan built by hand (tests) gives each row's hull and selection here; a built scan reads them live (`_live`).
var _hulls: PackedFloat64Array = PackedFloat64Array()
var _target_ids: PackedInt64Array = PackedInt64Array()
var _kinds: PackedByteArray = PackedByteArray()  # per body `BodyKind`; empty when every row is a ship
var _node_count: int = -1  # rows before this are nodes, the rest node-less statics; -1: every row
var _stamped: Dictionary = {}  # faction -> Array[Contact] with the relation set, each made when first handed out
var _relations: Dictionary = {}  # faction -> {other faction -> relation}, looked up once per pair
var _statics_n: int = -1  # rock and mine rows, counted on first use
var _node_statics: int = 0  # node rows of a static kind, as the core counts them
var _bolt_positions: PackedVector3Array = PackedVector3Array()
var _bolt_velocities: PackedVector3Array = PackedVector3Array()
var _bolt_factions: Array[StringName] = []
var _bolt_shooters: PackedInt64Array = PackedInt64Array()
var _reach: PackedFloat64Array = PackedFloat64Array()  # per body broadcast range (broadcast scan only)
var _field: Object = null  # the native field over this scan's arrays, made on the first native query
var _field_rejected: bool = false  # the field refused this scan's arrays (they differ in length): the scan answers nothing
var _field_rows: Dictionary = {}  # faction -> true once the field has its hostility row
var _friend_rows: Dictionary = {}  # faction -> true once the field knows whose mines it sees (Q27)
# A built scan (M4-T09) reads hull and selection when a contact is first handed out: the hulls' instance ids (0: none)
# and the selections drivers changed after the scan was built (body id -> the selection it had then).
var _live: bool = false
var _hull_ids: PackedInt64Array = PackedInt64Array()
var _target_before: Dictionary = {}
# The core whose rows a core or broadcast scan took, and its removals seen since (the freed-body check).
var _rows_of: SimCore = null
var _removals_at: int = 0
# A core scan (M4-T15): the core its field reads.
var _sim: SimCore = null
var _pilot: Object = null  # the pilot kernels over this scan's core rows, made on first ask (M4-T16)
var _pilot_known: bool = false
var _rows_version: int = -1  # the core's rows version this scan was taken at
var _relation_rows: Dictionary = {}  # faction -> PackedByteArray of relations in the core's faction order


## The scan of the current physics frame, built on the first call of the frame.
static func shared(tree: SceneTree) -> ContactScan:
	var frame: int = Engine.get_physics_frames()
	if _shared == null or _shared.physics_frame != frame or not _shared._bodies_alive():
		var built: ContactScan = from_core(tree)
		_shared = built if built != null else ContactScan.new()  # no world, no core: nothing to see
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


## Drops the shared scans; the next `shared` (and `shared_broadcasts`) call builds a new one, reading every body's faction,
## name, kind and radius again.
static func invalidate() -> void:
	_shared = null
	_shared_broadcasts = null
	var sim: SimCore = SimCore.current()
	if sim != null:
		sim.forget_attributes()


## The broadcasters of the current physics frame, built on the first call of the frame from `Targetable.broadcasters()`.
static func shared_broadcasts() -> ContactScan:
	var frame: int = Engine.get_physics_frames()
	if _shared_broadcasts == null or _shared_broadcasts.physics_frame != frame or not _shared_broadcasts._bodies_alive():
		var sim: SimCore = SimCore.current()
		if sim != null and sim.ensure_synced():
			_shared_broadcasts = _broadcast_scan(Targetable.broadcasters(), sim)
		else:
			_shared_broadcasts = ContactScan.new()  # no world, no core: nothing to hear
		_shared_broadcasts.physics_frame = frame
	return _shared_broadcasts


## The scan of the tree as the native core holds it this frame (no cache); null when no core is attached to this tree.
static func from_core(tree: SceneTree) -> ContactScan:
	var sim: SimCore = SimCore.for_tree(tree)
	if sim == null or not sim.ensure_synced():
		return null
	var scan := ContactScan.new()
	var rows: Array = sim.snapshot_rows()
	scan._take_rows(rows)
	scan._node_statics = rows[13]
	scan._append_static_rows()
	scan._sim = sim
	scan._rows_of = sim
	scan._removals_at = sim.removals
	scan._rows_version = int(sim.core.rows_version())
	return scan


## Asks the core to read `body`'s faction, name, kind and radius again at the next scan: for code that changes one of
## them on a body that stays in play (a pool ship hidden and shown again is noticed by itself).
static func touch(body: Node) -> void:
	var sim: SimCore = SimCore.current()
	if sim != null:
		sim.touch(body)


## Called by a ship's driver just before it changes its selection: this frame's scans (built before the change) then hand
## out the selection as it was when they were built, so the driver's own retargeting never shows in this tick's contacts.
static func note_selection(body: Node) -> void:
	var frame: int = Engine.get_physics_frames()
	var body_id: int = body.get_instance_id()
	for scan: ContactScan in [_shared, _shared_broadcasts]:
		if scan != null and scan._live and scan.physics_frame == frame and not scan._target_before.has(body_id):
			scan._target_before[body_id] = selection_of(body)


## The selection a ship's targeting holds as a contact reports it: a `Targetable` id, or -1.
static func selection_of(body: Node) -> int:
	var ship := body as Ship
	if ship != null and ship.targeting != null and ship.targeting.system.has_selection():
		return ship.targeting.system.selected_id()
	return -1


## Adds a body with no node to every scan (an asteroid field's rock by RID, a mine row): `id` must be unique and not an
## instance id; `kind` is a `BodyKind`. Rows come after the bodies, in the order they were registered. `world` is the
## `WorldFrame` whose local frame `position` is in: its rebases move the row; with none, nothing moves it. (`StaticRows`.)
static func register_static(id: int, position: Vector3, radius: float, kind: int = BodyKind.STATIC,
		faction: StringName = Factions.NEUTRAL, world: Node = null) -> void:
	StaticRows.register(id, position, radius, kind, faction, world)


## Removes the static row `id`.
static func unregister_static(id: int) -> void:
	StaticRows.unregister(id)


## Moves the static rows registered with `world` by `offset` (`WorldFrame.rebase` shifts them with its nodes).
static func shift_statics(offset: Vector3, world: Node) -> void:
	StaticRows.shift(offset, world)


## Removes every static row.
static func clear_statics() -> void:
	StaticRows.clear()


## Where this scan's rows came from: &"core" (the core's rows, M4-T15) or &"hand" (built by hand, or a broadcast scan).
func source() -> StringName:
	return &"core" if _sim != null else &"hand"


## Which code answers this scan's queries now: &"native", or &"none" for a scan whose arrays the field refused.
func path() -> StringName:
	return &"native" if _native() != null else &"none"


## Bodies the native field tested in its latest contact, nearest or statics query (the work count), -1 with no field.
func native_visits() -> int:
	var field: Object = _native()
	return field.visited() if field != null else -1


## The contacts a ship of `own_faction` at `own_position` sees: within `range_m`, never its own body, never a rock or mine.
func contacts_for(own_body_id: int, own_position: Vector3, own_faction: StringName,
		range_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	var stamped: Array[Contact] = _stamped_for(own_faction)
	var own_index: int = _body_ids.find(own_body_id)
	var field: Object = _native()
	if field != null:
		var found: PackedInt32Array = field.contacts(own_body_id, own_position, range_m)
		if own_index >= 0 and found.size() == stamped.size() - 1:
			picked_rows = found
			return _all_but(own_faction, stamped, own_index)
		return _pick(own_faction, stamped, found)
	picked_rows = PackedInt32Array()
	var none: Array[Contact] = []  # a refused scan: nothing, in a list the caller may keep
	return none


## The nearest `k` of the contacts `contacts_for` gives (M4-T04), in scan order. When that leaves any out, the nearest
## hostile ship joins them (so a crowd of friends never hides the fight), and so does every contact `keeper` names: it is
## called only then and returns `[PackedInt64Array ids, PackedStringArray names]` (names case-insensitive). With `k` or
## fewer in range it is `contacts_for`'s list, at about `contacts_for`'s cost. Equal ranges go to the earlier body in the scan.
## `k` of 0 or less cuts nothing: `contacts_for`'s list (as the `ai_nearest_k` setting's 0 means). Rocks and mines are
## never among them (`statics_for`).
func nearest_for(own_body_id: int, own_position: Vector3, own_faction: StringName, k: int, keeper: Callable = Callable(),
		range_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	var stamped: Array[Contact] = _stamped_for(own_faction)
	if k <= 0 or _body_ids.size() - _statics_count() <= k:
		return contacts_for(own_body_id, own_position, own_faction, range_m)  # no cut asked, or never more than k to cut
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
	picked_rows = PackedInt32Array()
	var none: Array[Contact] = []
	return none


## The rocks and mines a ship should steer round (M4-T09): those whose surface is within `range_m`, never its own body;
## with more than `k`, the `k` nearest by surface distance (equal ones to the earlier row). In scan order. None for `k` 0.
## A mine counts only for its own side and that side's friends; an enemy's stays hidden until it goes off (Q27).
func statics_for(own_body_id: int, own_position: Vector3, own_faction: StringName, k: int,
		range_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	if k <= 0 or _statics_count() == 0:
		picked_rows = PackedInt32Array()
		return _no_contacts
	var stamped: Array[Contact] = _stamped_for(own_faction)
	var field: Object = _native_with_friends(own_faction)
	if field != null:
		return _pick(own_faction, stamped, field.statics(own_body_id, own_position, own_faction, k, range_m))
	picked_rows = PackedInt32Array()
	return _no_contacts


## The broadcasts a ship hears (from a broadcast scan, `shared_broadcasts`): beyond `near_m`, where contacts take over, and within
## each broadcaster's own range.
func broadcasts_for(own_body_id: int, own_position: Vector3, own_faction: StringName,
		near_m: float = SENSOR_RANGE_M) -> Array[Contact]:
	if _body_ids.is_empty():
		return _no_contacts
	var stamped: Array[Contact] = _stamped_for(own_faction)
	var field: Object = _native()
	if field != null:
		return _pick(own_faction, stamped, field.broadcasts(own_body_id, own_position, near_m))
	return _no_contacts


## How many bolts hostile to `own_faction` (and not this ship's own) pass within `INCOMING_MISS_M` of the ship in the next
## `INCOMING_HORIZON_S`, both flying straight on.
func incoming_fire(own_body_id: int, own_position: Vector3, own_velocity: Vector3, own_faction: StringName) -> int:
	var field: Object = _native_with_row(own_faction)
	if field != null:
		return field.incoming(own_body_id, own_position, own_velocity, own_faction)
	return 0


## The native pilot kernels over this scan's core rows (M4-T16), or null: not a core scan, or the core's rows changed since
## the scan was taken (a resync or a rebase later in the frame: the indices would name other values), asked again on every
## call. The perception's own lists then answer as rows of their
## own (`PilotRows`).
func pilot_kernels() -> Object:
	if not _pilot_known:
		_pilot_known = true
		if _sim == null or not is_instance_valid(_sim) or _sim.core == null:
			return null
		if int(_sim.core.row_count()) == _body_ids.size():
			_pilot = NativeLib.instantiate(PILOT_CLASS)
			if _pilot != null:
				_pilot.attach_core(_sim.core)
	if _pilot == null or not is_instance_valid(_sim) \
			or int(_sim.core.rows_version()) != _rows_version:
		return null
	return _pilot


## Whether this is a core scan whose rows are still the ones it was taken from (M4-T17): the core's rows version has not
## moved since, so a native brain reading the live rows reads what this scan saw.
func rows_fresh() -> bool:
	return _sim != null and is_instance_valid(_sim) and _sim.core != null and int(_sim.core.rows_version()) == _rows_version


## The core's rows version this scan was taken at (M4-T18: the brain batch checks the rows have not moved since).
func rows_version_taken() -> int:
	return _rows_version


## How a ship of `faction` regards each faction of the core's table, as `Factions.Relation` values in that table's order
## (what the pilot kernels read); empty off the core.
func relation_row(faction: StringName) -> PackedByteArray:
	if _relation_rows.has(faction):
		return _relation_rows[faction]
	var row := PackedByteArray()
	if _sim != null and is_instance_valid(_sim) and _sim.core != null:
		for other: StringName in _sim.core.factions():
			row.append(_relation(faction, other))
	_relation_rows[faction] = row
	return row


# Takes the core's rows (`ScsSimCore.snapshot` or `select`).
func _take_rows(rows: Array) -> void:
	_body_ids = rows[0]
	_ids = rows[1]
	_factions = rows[2]
	_positions = rows[3]
	_velocities = rows[4]
	_forwards = rows[5]
	_ups = rows[6]
	_radii = rows[7]
	_is_ship = rows[8]
	_kinds = rows[9]
	_names = rows[10]
	_hull_ids = rows[11]
	_node_count = rows[12]
	_statics_n = rows[13]
	_live = true


# The broadcast scan of this frame: the active broadcasters of `list`, in that order, with their ranges, read now by
# the core of `sim`.
static func _broadcast_scan(list: Array[Targetable], sim: SimCore) -> ContactScan:
	var marker_ids := PackedInt64Array()
	var reaches := PackedFloat64Array()
	for targetable: Targetable in list:
		marker_ids.append(targetable.get_instance_id())
		reaches.append(targetable.broadcast_range_m)
	var rows: Array = sim.select_rows(marker_ids)
	var scan := ContactScan.new()
	scan._take_rows(rows)
	scan._rows_of = sim
	scan._removals_at = sim.removals
	for j: int in rows[14] as PackedInt32Array:
		scan._reach.append(reaches[j])
	return scan


# Adds body `i` to a nearest-k selection when it is in range, not the ship's own and not in it yet.
func _keep(i: int, chosen: PackedInt32Array, own_body_id: int, own_position: Vector3, range_sq: float) -> void:
	if i >= 0 and _body_ids[i] != own_body_id and not chosen.has(i) \
			and _positions[i].distance_squared_to(own_position) <= range_sq \
			and not (_statics_count() > 0 and BodyKind.is_static(_kinds[i])):
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
	picked_rows = indices
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


# The native field for this query, or null when it refused this scan's arrays. Made and loaded on the first query.
func _native() -> Object:
	if _field == null:
		if _field_rejected:
			return null
		var field: Object = NativeLib.instantiate(NATIVE_CLASS)
		if field == null:
			return null
		if _sim != null and is_instance_valid(_sim) and _sim.core != null:
			# A core scan: the field reads the core's rows and bolts; nothing is copied.
			field.attach_core(_sim.core, SENSOR_RANGE_M)
		# A field that refuses the arrays has logged why; this scan then answers nothing.
		elif not field.load(_body_ids, _positions, _factions, _is_ship, _reach, _bolt_positions, _bolt_velocities,
				_bolt_factions, _bolt_shooters, SENSOR_RANGE_M) \
				or (_statics_count() > 0 and not field.set_kinds(_kinds, _radii)):
			_field_rejected = true
			return null
		_field = field
	return _field


# The native field, once it knows which factions' mines `faction` knows about: its own and its friends' (Q27).
func _native_with_friends(faction: StringName) -> Object:
	var field: Object = _native()
	if field != null and not _friend_rows.has(faction):
		var row := PackedByteArray()
		for other: StringName in field.factions():
			row.append(1 if _relation(faction, other) == Factions.Relation.FRIENDLY else 0)
		field.set_friendly_row(faction, row)
		_friend_rows[faction] = true
	return field


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
	if _live:
		_stamp_live(c, i)
	else:
		c.hull_fraction = _hulls[i]
		c.target_id = _target_ids[i]
	c.kind = _kinds[i] if i < _kinds.size() else BodyKind.SHIP
	return c


# A built scan's hull and selection for body `i`, read now (both paths alike), but a selection a driver changed after the
# scan was built is taken as it was then (`note_selection`).
func _stamp_live(c: Contact, i: int) -> void:
	if _node_count >= 0 and i >= _node_count:
		return  # a static row: no hull, no selection (the contact's defaults)
	var hull := instance_from_id(_hull_ids[i]) as Damageable if _hull_ids[i] != 0 else null
	c.hull_fraction = hull.hull.fraction() if hull != null else -1.0
	var body_id: int = _body_ids[i]
	if _target_before.has(body_id):
		c.target_id = _target_before[body_id]
	else:
		c.target_id = selection_of(instance_from_id(body_id) as Node)


# How a ship of `faction` regards `other`, looked up once per pair in this scan.
func _relation(faction: StringName, other: StringName) -> Factions.Relation:
	if not _relations.has(faction):
		_relations[faction] = {}
	var known: Dictionary = _relations[faction]
	if not known.has(other):
		known[other] = Factions.relation(faction, other)
	return known[other]


# Appends the rows with no node (`StaticRows`) whole, column by column: no walk over them a tick.
func _append_static_rows() -> void:
	var columns: Dictionary = StaticRows.scan_columns()
	_body_ids.append_array(StaticRows.ids)
	_ids.append_array(StaticRows.ids)
	_names.append_array(columns["names"])
	_factions.append_array(StaticRows.factions)
	_positions.append_array(StaticRows.positions)
	_velocities.append_array(columns["zeros"])
	_forwards.append_array(columns["forwards"])
	_ups.append_array(columns["ups"])
	_radii.append_array(StaticRows.radii)
	_is_ship.append_array(columns["not_ship"])
	_hull_ids.append_array(columns["no_hull"])
	_kinds.append_array(StaticRows.kinds)
	_statics_n = _node_statics + int(columns["statics"])


# How many rows are rocks or mines (none when the scan has no kinds).
func _statics_count() -> int:
	if _statics_n < 0:
		_statics_n = 0
		for kind: int in _kinds:
			if BodyKind.is_static(kind):
				_statics_n += 1
	return _statics_n


# Whether every node this scan holds still exists. A core scan looks only when a marker or hull has left the tree.
func _bodies_alive() -> bool:
	if _rows_of != null:
		var removals: int = _rows_of.removals if is_instance_valid(_rows_of) else -1
		if _removals_at == removals:
			return true
		for i: int in _node_count:
			if not is_instance_id_valid(_body_ids[i]):
				return false
		_removals_at = removals
		return true
	var nodes: int = _node_count if _node_count >= 0 else _body_ids.size()
	var field: Object = _native() if nodes == _body_ids.size() else null
	if field != null:
		return field.bodies_alive()
	for i: int in nodes:
		if not is_instance_id_valid(_body_ids[i]):
			return false
	return true
