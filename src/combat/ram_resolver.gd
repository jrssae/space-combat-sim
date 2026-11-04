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

## Rams resolved this session (one per hull reached), the last one, and the last tick's cost in microseconds.
var events: int = 0
var last_ram: String = "none"
var resolve_us: int = 0
## Hulls gathered from the tree on the last tick, and ship and rock pairs the rocks' grid tested (work counts, M4-T29).
var hulls_last_tick: int = 0
var static_pairs_visited: int = 0
## `settings.ram_damage` as of the last tick.
var enabled: bool = true
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
# The rocks (M4-T29): their grid, kept until a rock changes, and a hull for each rock a ship came near (row id -> Damageable,
# never in the tree, freed with this node).
var _rocks: HitBroadPhase = HitBroadPhase.new()
var _solid: StaticRows.Solid = null
var _rock_hulls: Dictionary = {}


func _init() -> void:
	process_physics_priority = LATE_PRIORITY


func _ready() -> void:
	DebugConsole.registry.register_provider(&"ram", ConsoleVars.new({
		&"events": {"get": func() -> int: return events, "doc": "Rams resolved this session, one per hull reached"},
		&"last": {"get": func() -> String: return last_ram,
				"doc": "The last ram: other -> hull, how it was found, the hull's velocity change, damage"},
		&"resolve_us": {"get": func() -> int: return resolve_us, "unit": "us",
				"doc": "Cost of the last tick's ram checks (profiling only, wall clock)"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


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
		var hulls: Array[Dictionary] = _gather(delta)
		hulls_last_tick = hulls.size()
		var in_contact: PackedInt64Array = _resolve_contacts(hulls, delta)
		_resolve_swept(hulls, in_contact, delta)
		_resolve_rocks(hulls)
		tracker.end_tick()
	else:
		tracker.reset()  # a contact that began while off is never rammed when it is switched back on
	_shift_since_step = Vector3.ZERO  # Jolt steps after this tick's scripts: its next contacts are in the frame of now
	resolve_us = Time.get_ticks_usec() - started_us


## Where the last gather came from: &"tree" (the resolver's own walk) or &"core" (the native core's rows, M4-T15).
func source() -> StringName:
	return &"tree"


## The broad phase alone, for the parity tests (M4-T15): the keys `_resolve_swept` walks, with `always` added.
func broad_phase_pairs(delta: float, always: PackedInt64Array) -> PackedInt64Array:
	var hulls: Array[Dictionary] = _gather(delta)
	var count: int = hulls.size()
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	var radii := PackedFloat32Array()
	starts.resize(count)
	ends.resize(count)
	radii.resize(count)
	for i: int in count:
		starts[i] = hulls[i]["start"]
		ends[i] = hulls[i]["end"]
		radii[i] = (hulls[i]["damageable"] as Damageable).bounding_radius
	return RamBroadPhase.pairs(starts, ends, radii, always)


# Everything about the active hulls this tick needs, read before any ram is applied (a ram can park a ship mid-loop).
func _gather(delta: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
		var damageable := node as Damageable
		if damageable == null or not damageable.is_active():
			continue
		var body: Node3D = damageable.body()
		var rigid := body as RigidBody3D
		var position: Vector3 = body.global_position
		var basis: Basis = body.global_basis
		var hull: Dictionary = {
			"damageable": damageable,
			"body": body,
			"id": body.get_instance_id(),
			"rigid": rigid != null,
			"basis": basis,
			"to_body": basis.transposed(),
			"mass": damageable.ram_mass(),
		}
		if rigid != null:
			# Not stepped yet this tick: Jolt moves it by about velocity * delta in the coming step.
			var velocity: Vector3 = rigid.linear_velocity
			var ship := rigid as Ship
			hull["velocity"] = velocity
			hull["start"] = position
			hull["end"] = position + velocity * delta
			hull["accel"] = ship.applied_force() / rigid.mass if ship != null and rigid.mass > 0.0 else Vector3.ZERO
		else:
			# A prop moves itself in its own `_physics_process`, earlier in this tick.
			var velocity: Vector3 = _prop_velocity(body)
			hull["velocity"] = velocity
			hull["start"] = position - velocity * delta
			hull["end"] = position
			hull["accel"] = Vector3.ZERO
		out.append(hull)
	return out


# --- contacts: Jolt bounced them ---------------------------------------------------------------------------------


# Lands the contact rams; returns the pairs of `hulls` Jolt reported touching, in `RamBroadPhase`'s form.
func _resolve_contacts(hulls: Array[Dictionary], delta: float) -> PackedInt64Array:
	var by_id: Dictionary = {}
	var index_of: Dictionary[int, int] = {}
	for i: int in hulls.size():
		by_id[hulls[i]["id"]] = hulls[i]
		index_of[hulls[i]["id"]] = i
	var samples: Array[RamTracker.Sample] = []
	var in_contact := PackedInt64Array()
	for i: int in hulls.size():
		var hull: Dictionary = hulls[i]
		if hull["rigid"]:
			var damageable: Damageable = hull["damageable"]
			var sample := RamTracker.Sample.new(hull["id"], hull["velocity"], hull["accel"], damageable.ram_safe_dv_mps,
					damageable.ram_lethal_dv_mps)
			_read_contacts(hull["body"] as RigidBody3D, sample, _shift_since_step)
			samples.append(sample)
			for other_id: int in sample.contacts:
				var k: int = index_of.get(other_id, -1)
				if k >= 0:
					in_contact.append(mini(i, k) * hulls.size() + maxi(i, k))
	var pending: Array[Array] = []
	for ram: RamTracker.ContactRam in tracker.contacts(samples, delta):
		var damageable: Damageable = (by_id[ram.hull_id] as Dictionary)["damageable"]
		var other: Dictionary = by_id.get(ram.other_id, {})
		var info := HitInfo.new(ram.hull_id, ram.other_id, (other["damageable"] as Damageable).faction if not other.is_empty() else &"",
				damageable.hull.max_hp * ram.severity, ram.point, ram.normal, ram.relative_speed, HitInfo.CAUSE_RAM)
		pending.append(_pending(damageable, info, KIND_CONTACT, ram.dv))
	_apply_all(pending)
	return in_contact


# Every body Jolt reported touching `rigid` in its last step, with the first contact point and `rigid`'s surface normal there
# (Jolt's normal points from the other body into this one). `shift` is what the World was rebased by since that step.
static func _read_contacts(rigid: RigidBody3D, sample: RamTracker.Sample, shift: Vector3) -> void:
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(rigid.get_rid())
	if state == null:
		return
	for i: int in state.get_contact_count():
		sample.touch(state.get_contact_collider_id(i), state.get_contact_local_position(i) - shift,
				-state.get_contact_local_normal(i))


# --- swept: tunnelling speeds and props -------------------------------------------------------------------------


# Whether Jolt can report a contact between two rigid hulls (M4-T14). Where it cannot, the swept test decides at any speed, since
# no contact would follow it.
static func _jolt_can_touch(first: Dictionary, second: Dictionary) -> bool:
	var a := first["body"] as RigidBody3D
	var b := second["body"] as RigidBody3D
	return CollisionLayers.collide(a.collision_layer, a.collision_mask, b.collision_layer, b.collision_mask)


# The pairs near enough to meet this tick, and those in contact, in the order of a pass over every pair (a ram earlier in the
# pass can destroy a hull a later pair holds).
func _resolve_swept(hulls: Array[Dictionary], in_contact: PackedInt64Array, delta: float) -> void:
	var count: int = hulls.size()
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	var radii := PackedFloat32Array()
	starts.resize(count)
	ends.resize(count)
	radii.resize(count)
	for i: int in count:
		starts[i] = hulls[i]["start"]
		ends[i] = hulls[i]["end"]
		radii[i] = (hulls[i]["damageable"] as Damageable).bounding_radius
	for key: int in RamBroadPhase.pairs(starts, ends, radii, in_contact):
		@warning_ignore("integer_division")
		var i: int = key / count
		var first: Dictionary = hulls[i]
		var second: Dictionary = hulls[key - i * count]
		if not (first["rigid"] or second["rigid"]):
			continue  # props never ram each other
		var first_hull: Damageable = first["damageable"]
		var second_hull: Damageable = second["damageable"]
		if first_hull.hull.destroyed or second_hull.hull.destroyed:
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
func _resolve_rocks(hulls: Array[Dictionary]) -> void:
	var solid: StaticRows.Solid = StaticRows.solid()
	if solid != _solid:
		_solid = solid
		_rocks.keep(solid.positions, solid.radii)
	static_pairs_visited = 0
	if solid.ids.is_empty():
		return
	var ships := PackedInt32Array()
	var mids := PackedVector3Array()
	var reach := PackedFloat64Array()
	for i: int in hulls.size():
		var hull: Dictionary = hulls[i]
		if not hull["rigid"]:
			continue  # props never ram each other
		var start: Vector3 = hull["start"]
		var end: Vector3 = hull["end"]
		ships.append(i)
		mids.append((start + end) * 0.5)
		reach.append(start.distance_to(end) * 0.5 + (hull["damageable"] as Damageable).bounding_radius
				+ RamBroadPhase.MARGIN_M)
	if ships.is_empty():
		return
	var rock_count: int = solid.ids.size()
	var keys: PackedInt64Array = _rocks.kept_pairs(mids, reach)
	static_pairs_visited = _rocks.visited
	for key: int in keys:
		@warning_ignore("integer_division")
		var k: int = key / rock_count
		var ship: Dictionary = hulls[ships[k]]
		if (ship["damageable"] as Damageable).hull.destroyed:
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
	var pose := Transform3D(to_second * (first["basis"] as Basis), start)
	for i: int in mine.ram_volumes.size():
		var a: ConvexSweep.Convex = mine.ram_volumes[i].placed(pose)
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


# Both sides of a swept hit, each by its own share of the momentum split.
func _ram_swept(first: Dictionary, second: Dictionary, point: Vector3, kind: String) -> void:
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
	_apply_all(pending)


# --- shared ------------------------------------------------------------------------------------------------------


# A ram to apply, labelled now: applying one can send a raider back to the pool, and a parked raider has lost its name.
func _pending(damageable: Damageable, info: HitInfo, kind: String, dv: float) -> Array:
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
