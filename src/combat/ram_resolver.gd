class_name RamResolver
extends Node
## Ram damage (architecture §16 D32, §16.3, M3-T04): a collision hurts each hull by the velocity change it gives that hull's
## own body (`RamMath.severity`), with `HitInfo.cause` `ram`. Once per physics tick at `process_physics_priority` 210: after the
## `HitResolver` (200), before the `WingDirector` (290) and the `WaveDirector` (300), so a hull a ram destroys leaves play in
## the same tick (§15.7: the `DestructionDirector` hides it on `destroyed`) and the waves count it. Every `Ship` must run
## before it (priority below 210): `Ship.applied_force` is read here as this tick's.
##
## This node reads the scene and sweeps; `RamTracker` (pure) keeps the state between ticks. A ram is found one of two ways:
##
## - **Contact** (two rigid bodies): Jolt resolves the bounce and reports the contact (the direct body state). `RamTracker`
##   measures a new contact's Δv over a short window: the change of the hull's velocity its own forces (`Ship.applied_force`)
##   do not explain, so thrust is never a ram. The lighter body changes more and suffers more.
## - **Swept** (two rigid bodies whose relative motion in one tick is more than half the smaller `core_radius`, where Jolt's
##   discrete step could miss the hit or push one through the other, or whose layers do not pair in Jolt at all (none today,
##   M4-T14); or a prop without a physics body, a nav buoy, at any
##   speed): shape by shape, `ConvexSweep` sweeps each of one body's hit volumes, relative to the other body over the coming
##   step, against each of the other's. Two ships ram when a point of either is at least `RamMath.RAM_DEPTH_M` (0.3 m) deep
##   inside the other: a pass 0.3 m clear is never a ram, and shallower clips are Jolt's. A prop rams at any touch, since
##   nothing else would notice it. Each side's Δv is the momentum split of a perfectly inelastic hit, `|v_rel| × m_other /
##   (m_self + m_other)`, through the same curve: at 600 m/s closing two Starfuries change by 300 m/s each and both are
##   destroyed. The sweep runs at tunnelling speed even while Jolt reports a contact (that is when Jolt cannot be trusted);
##   `RamTracker` keeps it to one ram per pair per collision.
##
## Only the pairs `RamBroadPhase` finds near each other this tick, and the pairs Jolt holds in contact, are looked at (M4-T03,
## §17.3): any other pair could neither sweep into each other nor be kept touching, so skipping it changes nothing.
##
## Rocks (M4-T29, §17.16) are `StaticRows` with no node: a grid of them is kept between ticks (built again only when a rock
## changes) and each ship asks it for the rocks it could reach this tick. A rock is a prop to the swept test (any touch rams,
## a sphere of its radius, a mass nothing moves), so a ship that flies into one takes the whole closing speed.
##
## With the native core on (M4-T15, `SimCore`), the hulls come as columns from the core's rows and `ScsRamPhase` pairs them
## from the same rows (the GDScript `RamBroadPhase` stays the reference); the resolver then builds a hull's Dictionary only
## for the pairs. Without it, the resolver walks the tree as before.
##
## God mode protects the player's hull (`Damageable.apply_hit`); the bounce is Jolt's and still happens. `HitInfo.shooter_id` is
## the other body and `faction` its faction: relations and friendly fire do not matter, a collision hurts whoever it hits.
## `settings.ram_damage` (read every tick) switches it off; ships still bounce.
##
## Rebase-safe (M3-T14): between ticks only velocities, instance ids and the open contact windows' points are kept, and `world`'s
## `rebased` moves those points with the hulls. Jolt reports contacts where its last step left the bodies, so a rebase made since
## that step (the automatic one runs at priority 0, the console's too, both before this node) is taken off the points read this
## tick. `Main` sets `world`; a resolver without one (tests with no rebase) reads the points as Jolt gives them.
##
## Console: provider `ram` (`events`, `last`, `resolve_us`). `resolve_us` is a profiling readout from the wall clock, not
## gameplay time.

## A ram reached a hull; `info.applied` is set by then.
signal ram_resolved(info: HitInfo)

const LATE_PRIORITY: int = 210
const KIND_CONTACT: String = "contact"
const KIND_TUNNEL: String = "tunnelling"
const KIND_PROP: String = "prop"
## The native class that pairs the core's hull rows when the core is on (M4-T15).
const PHASE_CLASS: StringName = &"ScsRamPhase"
## Room round the swept test's early rejects (M4-T34), far above the rounding of a placed volume's bounds.
const SWEEP_CULL_PAD_M: float = 0.05

## Rams resolved this session (one per hull reached), the last one, and the last tick's cost in microseconds.
var events: int = 0
var last_ram: String = "none"
var resolve_us: int = 0
## Hulls gathered on the last tick, and ship and rock pairs the rocks' grid tested (work counts, M4-T29).
var hulls_last_tick: int = 0
var static_pairs_visited: int = 0
## Wall-clock microseconds of the last tick's gather of hulls (a readout only).
var gather_us: int = 0
## `settings.ram_damage` as of the last tick.
var enabled: bool = true
## Volumes the swept test has placed in another hull's frame so far (a work count, M4-T34).
var volumes_placed: int = 0
## Throws the sparks of a ram (`Main` sets it); none without it.
var fx: FxPool = null
## False keeps the resolver on its own gather of the tree even when the native core is on (M4-T15), for pairing the two.
var use_core: bool = true
## Contacts, windows and one ram per pair per collision, between ticks.
var tracker: RamTracker = RamTracker.new()
## The World whose rebases the contact points follow (see the class notes).
var world: WorldFrame = null:
	set = set_world

# The rebases since Jolt's last step: this tick's contact points are still in the frame before them.
var _shift_since_step := Vector3.ZERO
# This tick's hulls as columns (M4-T15), from the core or the tree, and the per-hull Dictionaries made on demand.
var _count: int = 0
var _ids := PackedInt64Array()
var _hull_ids := PackedInt64Array()
var _rigid := PackedByteArray()
var _rigid_rows := PackedInt32Array()  # the rigid hulls' indices
var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _bases := PackedVector3Array()  # three columns (the x, y and z axes) a hull
var _hulls: Array = []  # Dictionary or null per hull
var _delta: float = 0.0
var _source: StringName = &"tree"
var _gather_frame: int = -1
var _phase: Object = null  # the native ram phase (`PHASE_CLASS`), made on first use
var _phase_class_known: int = -1
# The rocks (M4-T29): their grid, kept until a rock changes, and a hull for each rock a ship came near (row id -> Damageable,
# never in the tree, freed with this node).
var _rocks: HitBroadPhase = HitBroadPhase.new()
var _solid: StaticRows.Solid = null
var _rock_hulls: Dictionary = {}
# Each hull's index by body id, built when first needed in a tick.
var _contact_native: bool = false  # the contacts read in one native call over the rows (M4-T35)
var _index_of: Dictionary[int, int] = {}
var _index_built: bool = false


# The latest resolver in a tree (M4-T22 fix round 1: the tier's rams land through it, so `ram_resolved` hears them).
static var _current: RamResolver = null


func _init() -> void:
	process_physics_priority = LATE_PRIORITY


func _enter_tree() -> void:
	_current = self


## The latest resolver in a tree, or null.
static func current() -> RamResolver:
	return _current if _current != null and is_instance_valid(_current) and _current.is_inside_tree() else null


func _ready() -> void:
	DebugConsole.registry.register_provider(&"ram", ConsoleVars.new({
		&"events": {"get": func() -> int: return events, "doc": "Rams resolved this session, one per hull reached"},
		&"last": {"get": func() -> String: return last_ram,
				"doc": "The last ram: other -> hull, how it was found, the hull's velocity change, damage"},
		&"resolve_us": {"get": func() -> int: return resolve_us, "unit": "us",
				"doc": "Cost of the last tick's ram checks (profiling only, wall clock)"},
		&"gather_us": {"get": func() -> int: return gather_us, "unit": "us",
				"doc": "Cost of the last tick's gather of hulls (profiling only, wall clock)"},
		&"source": {"get": func() -> String: return String(_source),
				"doc": "Where the last tick's hulls came from: core (the native core's rows, M4-T15) or tree (the resolver's own walk)"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _current == self:
		_current = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for hull: Variant in _rock_hulls.values():
			(hull as Damageable).free()
		_rock_hulls.clear()


func _physics_process(delta: float) -> void:
	resolve(delta)


func set_world(value: WorldFrame) -> void:
	if world != null and world.rebased.is_connected(_on_rebased):
		world.rebased.disconnect(_on_rebased)
	world = value
	if world != null:
		world.rebased.connect(_on_rebased)


func _on_rebased(offset: Vector3) -> void:
	_shift_since_step += offset
	tracker.shift(offset)


## One tick of ram detection with time step `delta`. `_physics_process` calls it every tick: contacts are compared with the
## previous call, so a test that steps it by hand must call it every tick too.
func resolve(delta: float) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	enabled = bool(Settings.get_value(&"ram_damage"))
	if enabled:
		var sim: SimCore = _gather(delta)
		gather_us = Time.get_ticks_usec() - started_us
		hulls_last_tick = _count
		_contact_native = sim != null
		var in_contact: PackedInt64Array
		if _contact_native:
			in_contact = _resolve_contacts_native(sim, delta)
		else:
			in_contact = _resolve_contacts_columns(delta)
		_resolve_swept(sim, in_contact, delta)
		_resolve_rocks(sim, delta)
		tracker.end_tick()
	else:
		tracker.reset()  # a contact that began while off is never rammed when it is switched back on
	_shift_since_step = Vector3.ZERO  # Jolt steps after this tick's scripts: its next contacts are in the frame of now
	resolve_us = Time.get_ticks_usec() - started_us


## Where the last gather came from: &"tree" (the resolver's own walk) or &"core" (the native core's rows, M4-T15).
func source() -> StringName:
	return _source


## How the last tick's contacts reached the tracker: &"native" (one call over the core's rows, M4-T35) or &"columns" (read
## per hull, a world with no core).
func contact_path() -> StringName:
	return &"native" if _contact_native else &"columns"


## The broad phase alone, for the parity tests (M4-T15): the keys `_resolve_swept` walks, with `always` added.
func broad_phase_pairs(delta: float, always: PackedInt64Array) -> PackedInt64Array:
	var sim: SimCore = _gather(delta)
	return _pairs(sim, delta, always)


# This tick's active hulls as columns (index i, in the `damageable` group's order): from the core when it is on (the core
# it read, returned), else from the tree. Everything a ram needs of a hull is read before any ram is applied (a ram can
# park a ship mid-loop); the per-hull Dictionary the swept test takes is made only for the hulls a pair names.
func _gather(delta: float) -> SimCore:
	_delta = delta
	_hulls.clear()
	_index_built = false
	var sim: SimCore = SimCore.for_tree(get_tree()) if use_core and _phase_available() else null
	if sim != null and _synced(sim):
		_source = &"core"
		var hulls: Array = sim.core.hull_columns()
		_ids = hulls[0]
		_hull_ids = hulls[1]
		_rigid = hulls[2]
		_positions = hulls[3]
		_velocities = hulls[4]
		_rigid_rows = hulls[7]
		_bases = hulls[6]
		_count = _ids.size()
	else:
		_source = &"tree"
		sim = null
		_gather_tree()
	_hulls.resize(_count)
	hulls_last_tick = _count
	return sim


# The core's rows as of now: the tick's sync points in play; a second gather inside one physics frame (a test stepping
# the resolver by hand) reads everything again, since anything may have moved between.
func _synced(sim: SimCore) -> bool:
	var frame: int = Engine.get_physics_frames()
	var again: bool = _gather_frame == frame
	_gather_frame = frame
	if again:
		return sim.sync_now() and sim.sync_bolts_now()
	return sim.ensure_bolts_synced()


# The own walk of the tree into the same columns.
func _gather_tree() -> void:
	_ids.clear()
	_hull_ids.clear()
	_rigid.clear()
	_positions.clear()
	_velocities.clear()
	_bases.clear()
	_rigid_rows.clear()
	for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
		var damageable := node as Damageable
		if damageable == null or not damageable.is_active():
			continue
		var body: Node3D = damageable.body()
		var rigid := body as RigidBody3D
		if rigid != null:
			_rigid_rows.append(_ids.size())
		_ids.append(body.get_instance_id())
		_hull_ids.append(damageable.get_instance_id())
		_rigid.append(1 if rigid != null else 0)
		_positions.append(body.global_position)
		# Not stepped yet this tick: Jolt moves a body by about velocity * delta in the coming step; a prop moved itself
		# in its own `_physics_process`, earlier in this tick.
		_velocities.append(rigid.linear_velocity if rigid != null else _prop_velocity(body))
		var basis: Basis = body.global_basis
		_bases.append(basis.x)
		_bases.append(basis.y)
		_bases.append(basis.z)
	_count = _ids.size()


# Whether the native ram phase answers now (the core path needs it).
func _phase_available() -> bool:
	if _phase_class_known < 0:
		_phase_class_known = 1 if NativeLib.has_class(PHASE_CLASS) else 0
	if _phase_class_known == 0:
		return false
	if _phase == null:
		_phase = NativeLib.instantiate(PHASE_CLASS)
	return _phase != null


# The pairs near enough to meet this tick plus `always`, in `RamBroadPhase`'s form: natively from the core's rows, or
# from the columns gathered here.
func _pairs(sim: SimCore, delta: float, always: PackedInt64Array) -> PackedInt64Array:
	if sim != null:
		return _phase.pairs(sim.core, delta, always)
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	var radii := PackedFloat32Array()
	starts.resize(_count)
	ends.resize(_count)
	radii.resize(_count)
	for i: int in _count:
		var hull: Dictionary = _hull(i)
		starts[i] = hull["start"]
		ends[i] = hull["end"]
		radii[i] = (hull["damageable"] as Damageable).bounding_radius
	return RamBroadPhase.pairs(starts, ends, radii, always)


# Hull `i` as the swept test and the ram maths take it, made when first needed this tick.
func _hull(i: int) -> Dictionary:
	var found: Variant = _hulls[i]
	if found != null:
		return found
	var damageable := instance_from_id(_hull_ids[i]) as Damageable
	var body := instance_from_id(_ids[i]) as Node3D
	var rigid: bool = _rigid[i] == 1
	var basis := Basis(_bases[i * 3], _bases[i * 3 + 1], _bases[i * 3 + 2])
	var position: Vector3 = _positions[i]
	var velocity: Vector3 = _velocities[i]
	var hull: Dictionary = {
		"damageable": damageable,
		"body": body,
		"id": _ids[i],
		"rigid": rigid,
		"basis": basis,
		"to_body": basis.transposed(),
		"mass": damageable.ram_mass() if damageable != null else 0.0,
		"velocity": velocity,
		"start": position if rigid else position - velocity * _delta,
		"end": position + velocity * _delta if rigid else position,
		"accel": _accel(i),
	}
	_hulls[i] = hull
	return hull


# What hull `i`'s own forces do to its velocity this tick (`Ship.applied_force`), so thrust is never a ram.
func _accel(i: int) -> Vector3:
	if _rigid[i] != 1:
		return Vector3.ZERO
	var ship := instance_from_id(_ids[i]) as Ship
	if ship == null or ship.mass <= 0.0:
		return Vector3.ZERO
	return ship.applied_force() / ship.mass


# --- contacts: Jolt bounced them ---------------------------------------------------------------------------------


# Lands the contact rams and returns the pairs of hulls Jolt reported touching, in `RamBroadPhase`'s form, on a world with
# no core. The tracker is fed columns (M4-T34): every rigid hull's id, velocity and accel, and contact lists only for the
# hulls Jolt reports touching something, so a tick with no contact builds no object per hull.
func _resolve_contacts_columns(delta: float) -> PackedInt64Array:
	var ids := PackedInt64Array()
	var velocities := PackedVector3Array()
	var accels := PackedVector3Array()
	var touches: Dictionary[int, Dictionary] = {}
	var touch_rows := PackedInt32Array()
	for i: int in _rigid_rows:
		var body := instance_from_id(_ids[i]) as RigidBody3D
		if body == null or not is_instance_id_valid(_hull_ids[i]):
			continue
		var id: int = _ids[i]
		ids.append(id)
		velocities.append(_velocities[i])
		accels.append(_accel_of(body))
		var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state == null or state.get_contact_count() == 0:
			continue
		var contacts: Dictionary[int, RamTracker.Touch] = {}
		for c: int in state.get_contact_count():
			var other_id: int = state.get_contact_collider_id(c)
			if not contacts.has(other_id):
				contacts[other_id] = RamTracker.Touch.new(state.get_contact_local_position(c) - _shift_since_step,
						-state.get_contact_local_normal(c))
		touches[id] = contacts
		touch_rows.append(i)
	var in_contact := PackedInt64Array()
	var t: int = 0
	for id: int in touches:
		var i: int = touch_rows[t]
		t += 1
		for other_id: int in touches[id]:
			var k: int = _index().get(other_id, -1)
			if k >= 0:
				in_contact.append(mini(i, k) * _count + maxi(i, k))
	var pending: Array[Array] = []
	for ram: RamTracker.ContactRam in tracker.contacts_columns(ids, velocities, accels, touches, _limits, delta):
		var damageable: Damageable = _hull(_index()[ram.hull_id])["damageable"]
		if damageable == null:
			continue  # its node went since the gather
		var other_at: int = _index().get(ram.other_id, -1)
		var other_hull: Damageable = _hull(other_at)["damageable"] if other_at >= 0 else null
		var other_faction: StringName = other_hull.faction if other_hull != null else &""
		var info := HitInfo.new(ram.hull_id, ram.other_id, other_faction, damageable.hull.max_hp * ram.severity, ram.point,
				ram.normal, ram.relative_speed, HitInfo.CAUSE_RAM)
		pending.append(_pending(damageable, info, KIND_CONTACT, ram.dv))
	_apply_all(pending)
	return in_contact


# `_resolve_contacts_columns` with the contacts, velocities and accelerations read in one native call over the core's rows
# (M4-T35): the same columns to the tracker, built in GDScript only for the hulls Jolt reports touching; a hull whose
# acceleration the flight step did not write (a ship on its own model) is asked as before.
func _resolve_contacts_native(sim: SimCore, delta: float) -> PackedInt64Array:
	var read: Array = _phase.contacts(sim.core, _shift_since_step)
	var rows: PackedInt32Array = read[0]
	var ids: PackedInt64Array = read[1]
	var velocities: PackedVector3Array = read[2]
	var accels: PackedVector3Array = read[3]
	var known: PackedByteArray = read[4]
	for k: int in ids.size():
		if known[k] == 0:
			accels[k] = _accel(rows[k])
	var touched_rows: PackedInt32Array = read[5]
	var starts: PackedInt32Array = read[6]
	var others: PackedInt64Array = read[7]
	var points: PackedVector3Array = read[8]
	var normals: PackedVector3Array = read[9]
	var touches: Dictionary[int, Dictionary] = {}
	var in_contact := PackedInt64Array()
	for t: int in touched_rows.size():
		var i: int = touched_rows[t]
		var contacts: Dictionary[int, RamTracker.Touch] = {}
		for c: int in range(starts[t], starts[t + 1]):
			var other_id: int = others[c]
			if not contacts.has(other_id):
				contacts[other_id] = RamTracker.Touch.new(points[c], normals[c])
		touches[_ids[i]] = contacts
		for other_id: int in contacts:
			var k: int = _index().get(other_id, -1)
			if k >= 0:
				in_contact.append(mini(i, k) * _count + maxi(i, k))
	var pending: Array[Array] = []
	for ram: RamTracker.ContactRam in tracker.contacts_columns(ids, velocities, accels, touches, _limits, delta):
		var damageable: Damageable = _hull(_index()[ram.hull_id])["damageable"]
		if damageable == null:
			continue  # its node went since the gather
		var other_at: int = _index().get(ram.other_id, -1)
		var other_hull: Damageable = _hull(other_at)["damageable"] if other_at >= 0 else null
		var other_faction: StringName = other_hull.faction if other_hull != null else &""
		var info := HitInfo.new(ram.hull_id, ram.other_id, other_faction, damageable.hull.max_hp * ram.severity, ram.point,
				ram.normal, ram.relative_speed, HitInfo.CAUSE_RAM)
		pending.append(_pending(damageable, info, KIND_CONTACT, ram.dv))
	_apply_all(pending)
	return in_contact


# Each hull's index by body id this tick, built on first ask.
func _index() -> Dictionary[int, int]:
	if not _index_built:
		_index_built = true
		_index_of.clear()
		for i: int in _count:
			_index_of[_ids[i]] = i
	return _index_of


# A rigid hull's ram limits, `[safe_dv_mps, lethal_dv_mps]`, by body id (the tracker asks for a hull with an open window).
func _limits(body_id: int) -> PackedFloat64Array:
	var damageable := instance_from_id(_hull_ids[_index()[body_id]]) as Damageable
	return PackedFloat64Array([damageable.ram_safe_dv_mps, damageable.ram_lethal_dv_mps])


# `_accel` for a body already looked up.
static func _accel_of(body: RigidBody3D) -> Vector3:
	var ship := body as Ship
	if ship == null or ship.mass <= 0.0:
		return Vector3.ZERO
	return ship.applied_force() / ship.mass


# --- swept: tunnelling speeds and props -------------------------------------------------------------------------


# Whether Jolt can report a contact between two rigid hulls (M4-T14). Where it cannot, the swept test decides at any speed, since
# no contact would follow it.
static func _jolt_can_touch(first: Dictionary, second: Dictionary) -> bool:
	var a := first["body"] as RigidBody3D
	var b := second["body"] as RigidBody3D
	return CollisionLayers.collide(a.collision_layer, a.collision_mask, b.collision_layer, b.collision_mask)


# The pairs near enough to meet this tick, and those in contact, in the order of a pass over every pair (a ram earlier in the
# pass can destroy a hull a later pair holds).
func _resolve_swept(sim: SimCore, in_contact: PackedInt64Array, delta: float) -> void:
	var count: int = _count
	for key: int in _pairs(sim, delta, in_contact):
		@warning_ignore("integer_division")
		var i: int = key / count
		var first: Dictionary = _hull(i)
		var second: Dictionary = _hull(key - i * count)
		if not (first["rigid"] or second["rigid"]):
			continue  # props never ram each other
		var first_hull: Damageable = first["damageable"]
		var second_hull: Damageable = second["damageable"]
		if first_hull == null or second_hull == null or first_hull.hull.destroyed or second_hull.hull.destroyed:
			continue  # a hull that went earlier this tick
		var both_rigid: bool = first["rigid"] and second["rigid"]
		var relative_speed: float = ((first["velocity"] as Vector3) - (second["velocity"] as Vector3)).length()
		if both_rigid and _jolt_can_touch(first, second) \
				and not RamMath.is_tunnelling(relative_speed, delta, first_hull.core_radius, second_hull.core_radius):
			tracker.keep_touching(first["id"], second["id"])  # Jolt's speed: its contacts decide
			continue
		# A ship's Jolt contacts handle shallow clips; a prop has no body, so any touch is a ram.
		var hit: Dictionary = _sweep_pair(first, second, both_rigid)
		if not hit.is_empty() and tracker.swept_meeting(first["id"], second["id"]):
			_ram_swept(first, second, hit["point"], KIND_TUNNEL if both_rigid else KIND_PROP)


# The ships that fly into a rock this tick, through the rocks' grid: each rigid hull asks for the rocks its swept sphere
# could reach, and those go through the swept test as props.
func _resolve_rocks(sim: SimCore, delta: float) -> void:
	var solid: StaticRows.Solid = StaticRows.solid()
	if solid != _solid:
		_solid = solid
		_rocks.keep(solid.positions, solid.radii)
	static_pairs_visited = 0
	if solid.ids.is_empty() or _rigid_rows.is_empty():
		return
	var keys: PackedInt64Array
	if sim != null:
		keys = _rocks.kept_pairs_hulls_core(sim.core, delta, RamBroadPhase.MARGIN_M)
	else:
		var mids := PackedVector3Array()
		var reach := PackedFloat64Array()
		for i: int in _rigid_rows:
			var hull: Dictionary = _hull(i)
			var start: Vector3 = hull["start"]
			var end: Vector3 = hull["end"]
			mids.append((start + end) * 0.5)
			reach.append(start.distance_to(end) * 0.5 + (hull["damageable"] as Damageable).bounding_radius
					+ RamBroadPhase.MARGIN_M)
		keys = _rocks.kept_pairs(mids, reach)
	static_pairs_visited = _rocks.visited
	var rock_count: int = solid.ids.size()
	for key: int in keys:
		@warning_ignore("integer_division")
		var k: int = key / rock_count
		var ship: Dictionary = _hull(_rigid_rows[k])
		var ship_hull: Damageable = ship["damageable"]
		if ship_hull == null or ship_hull.hull.destroyed:
			continue  # a hull that went earlier this tick
		var rock: Dictionary = _rock(solid, key - k * rock_count)
		var hit: Dictionary = _sweep_pair(ship, rock, false)
		if not hit.is_empty() and tracker.swept_meeting(ship["id"], rock["id"]):
			_ram_swept(ship, rock, hit["point"], KIND_PROP)


# Rock `s` as the swept test sees a hull: a sphere at rest that nothing moves or breaks.
func _rock(solid: StaticRows.Solid, s: int) -> Dictionary:
	var id: int = solid.ids[s]
	var radius: float = solid.radii[s]
	var hull: Damageable = _rock_hulls.get(id)
	if hull == null or hull.bounding_radius != radius or hull.faction != solid.factions[s]:
		if hull != null:
			hull.free()
		hull = Damageable.new()
		var sphere := CapsuleShape3D.new()
		sphere.radius = radius
		sphere.height = 2.0 * radius
		var collision: Array[Dictionary] = [{"name": "rock", "shape": sphere, "transform": Transform3D.IDENTITY}]
		hull.setup(collision, StaticRows.SOLID_HULL, solid.factions[s])
		hull.hit_by_anyone = true
		hull.invulnerable = true
		hull.ram_mass_kg = StaticRows.SOLID_MASS_KG
		_rock_hulls[id] = hull
	var at: Vector3 = solid.positions[s]
	return {
		"damageable": hull,
		"body": null,
		"id": id,
		"rigid": false,
		"basis": Basis.IDENTITY,
		"to_body": Basis.IDENTITY,
		"mass": StaticRows.SOLID_MASS_KG,
		"velocity": Vector3.ZERO,
		"start": at,
		"end": at,
		"accel": Vector3.ZERO,
	}


# Shape by shape, whether some point of one body comes at least `RamMath.RAM_DEPTH_M` deep inside the other over this tick,
# either way round (`deep`), or touches it at all (not `deep`: a prop). `ConvexSweep` is exact for boxes and capsules at any
# speed. Worked in `second`'s frame at the tick's start, `first` moving relative to it in a straight line. Each step is
# cheaper than the next and filters for it: the bodies' bounding spheres, a volume's swept box against the other body's box
# and then against each of its volumes' boxes, the whole volumes, then the shrunk ones. The first pair of volumes that rams
# decides. {point}: World-local, between those two volumes when their bounding spheres met (best effort, for the damage
# zones); empty for no ram.
func _sweep_pair(first: Dictionary, second: Dictionary, deep: bool) -> Dictionary:
	var to_second: Basis = second["to_body"]
	var second_start: Vector3 = second["start"]
	var second_move: Vector3 = (second["end"] as Vector3) - second_start
	var start: Vector3 = to_second * ((first["start"] as Vector3) - second_start)
	var move: Vector3 = to_second * ((first["end"] as Vector3) - (first["start"] as Vector3) - second_move)
	var mine: Damageable = first["damageable"]
	var theirs: Damageable = second["damageable"]
	if SweepMath.segment_sphere(start, start + move, Vector3.ZERO, mine.bounding_radius + theirs.bounding_radius) < 0.0:
		return {}  # the bodies never come near each other this tick
	if not _sphere_reaches(start, mine.bounding_radius, move, theirs.ram_bounds):
		return {}  # no volume of this body can reach the other's box (M4-T34)
	var pose := Transform3D(to_second * (first["basis"] as Basis), start)
	for i: int in mine.ram_volumes.size():
		var volume: ConvexSweep.Convex = mine.ram_volumes[i]
		if not _sphere_reaches(pose * volume.centre, volume.reach, move, theirs.ram_bounds):
			continue  # this volume cannot either
		volumes_placed += 1
		var a: ConvexSweep.Convex = volume.placed(pose)
		var swept: AABB = a.swept_bounds(move)
		if not swept.intersects(theirs.ram_bounds):
			continue
		var a_core: ConvexSweep.Convex = null
		for j: int in theirs.ram_volumes.size():
			var b: ConvexSweep.Convex = theirs.ram_volumes[j]
			if not swept.intersects(b.bounds) or not ConvexSweep.overlaps(a, move, b):
				continue
			if deep:
				if a_core == null:
					a_core = mine.ram_cores[i].placed(pose)
				if not (ConvexSweep.overlaps(a, move, theirs.ram_cores[j]) or ConvexSweep.overlaps(a_core, move, b)):
					continue  # they touch, but not that deep: Jolt's
			var t: float = maxf(ConvexSweep.spheres_meet(a, move, b), 0.0)
			return {"point": second_start + second_move * t + (second["basis"] as Basis) * ((a.centre + move * t + b.centre) * 0.5)}
	return {}


# Whether a sphere of `radius` round `centre`, swept by `move`, can reach `box` (M4-T34). Padded, so it never says no where a
# volume inside the sphere would reach the box: it only spares the swept test work whose answer is no ram.
static func _sphere_reaches(centre: Vector3, radius: float, move: Vector3, box: AABB) -> bool:
	var r: float = radius + SWEEP_CULL_PAD_M
	var held := AABB(centre - Vector3(r, r, r), Vector3(r, r, r) * 2.0)
	return held.merge(AABB(held.position + move, held.size)).intersects(box)


# Both sides of a swept hit, each by its own share of the momentum split.
func _ram_swept(first: Dictionary, second: Dictionary, point: Vector3, kind: String) -> void:
	_apply_all(ram_pending(first, second, point, kind))


## Lands rams found outside the resolver (the low-attention tier's, M4-T22 fix round 1) as the resolver lands its own.
func land(pending: Array[Array]) -> void:
	_apply_all(pending)


## A ram between two hulls (`id`, `damageable`, `velocity`, `mass` each) at `point`, by the swept rule: each takes the hull
## share its own velocity change gives when the two move on together. The rams to apply, labelled with `kind`.
static func ram_pending(first: Dictionary, second: Dictionary, point: Vector3, kind: String) -> Array[Array]:
	var relative: Vector3 = (first["velocity"] as Vector3) - (second["velocity"] as Vector3)
	var speed: float = relative.length()
	var normal: Vector3 = relative / speed if speed > 1e-6 else Vector3.ZERO  # first's side faces where second came from
	var pending: Array[Array] = []
	for side: Array in [[first, second, normal], [second, first, -normal]]:
		var hull: Dictionary = side[0]
		var other: Dictionary = side[1]
		var damageable: Damageable = hull["damageable"]
		var dv: float = RamMath.split_dv(speed, hull["mass"], other["mass"])
		var damage: float = RamMath.damage(dv, damageable.ram_safe_dv_mps, damageable.ram_lethal_dv_mps, damageable.hull.max_hp)
		if damage > 0.0:
			var info := HitInfo.new(hull["id"], other["id"], (other["damageable"] as Damageable).faction, damage, point, side[2],
					speed, HitInfo.CAUSE_RAM)
			pending.append(_pending(damageable, info, kind, dv))
	return pending


# --- shared ------------------------------------------------------------------------------------------------------


# A ram to apply, labelled now: applying one can send a raider back to the pool, and a parked raider has lost its name.
static func _pending(damageable: Damageable, info: HitInfo, kind: String, dv: float) -> Array:
	return [damageable, info, "%s -> %s: %s, dv %.1f m/s" % [HitResolver.name_of(info.shooter_id),
			HitResolver.name_of(info.target_id), kind, dv]]


func _apply_all(pending: Array[Array]) -> void:
	for ram: Array in pending:
		var damageable: Damageable = ram[0]
		var info: HitInfo = ram[1]
		events += 1
		damageable.apply_hit(info)
		if fx != null:
			fx.burst(FxSpecs.RAM, info.point, info.normal, _body_velocity(damageable.body()))
		last_ram = "%s, %.1f of %.1f applied" % [ram[2], info.applied, info.damage]
		ram_resolved.emit(info)


static func _prop_velocity(body: Node3D) -> Vector3:
	var buoy := body as NavBuoy
	return buoy.velocity if buoy != null else Vector3.ZERO


static func _body_velocity(body: Node3D) -> Vector3:
	var rigid := body as RigidBody3D
	return rigid.linear_velocity if rigid != null else _prop_velocity(body)
