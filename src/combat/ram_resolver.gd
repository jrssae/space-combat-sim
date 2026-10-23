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
##   discrete step could miss the hit or push one through the other; or a prop without a physics body, a nav buoy, at any
##   speed): a target-relative swept test like the `HitResolver`'s moves each body's origin, relative to the other over the
##   coming step, against the other's hit volumes grown by its own `origin_core_radius`, a sphere round its origin that stays
##   inside its hull. Each side's Δv is the momentum split of a perfectly inelastic hit, `|v_rel| × m_other / (m_self +
##   m_other)`, through the same curve: at 600 m/s closing two Starfuries change by 300 m/s each and both are destroyed. The
##   sweep runs at tunnelling speed even while Jolt reports a contact (that is when Jolt cannot be trusted); `RamTracker` keeps
##   it to one ram per pair per collision.
##
## God mode protects the player's hull (`Damageable.apply_hit`); the bounce is Jolt's and still happens. `HitInfo.shooter_id` is
## the other body and `faction` its faction: relations and friendly fire do not matter, a collision hurts whoever it hits.
## `settings.ram_damage` (read every tick) switches it off; ships still bounce.
##
## Rebase-safe: only velocities and instance ids are kept between ticks, never positions.
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
## `settings.ram_damage` as of the last tick.
var enabled: bool = true
## Contacts, windows and one ram per pair per collision, between ticks.
var tracker: RamTracker = RamTracker.new()


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


func _physics_process(delta: float) -> void:
	resolve(delta)


## One tick of ram detection with time step `delta`. `_physics_process` calls it every tick: contacts are compared with the
## previous call, so a test that steps it by hand must call it every tick too.
func resolve(delta: float) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	enabled = bool(Settings.get_value(&"ram_damage"))
	if enabled:
		var hulls: Array[Dictionary] = _gather(delta)
		_resolve_contacts(hulls, delta)
		_resolve_swept(hulls, delta)
		tracker.end_tick()
	else:
		tracker.reset()  # a contact that began while off is never rammed when it is switched back on
	resolve_us = Time.get_ticks_usec() - started_us


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


func _resolve_contacts(hulls: Array[Dictionary], delta: float) -> void:
	var by_id: Dictionary = {}
	var samples: Array[RamTracker.Sample] = []
	for hull: Dictionary in hulls:
		by_id[hull["id"]] = hull
		if hull["rigid"]:
			var damageable: Damageable = hull["damageable"]
			var sample := RamTracker.Sample.new(hull["id"], hull["velocity"], hull["accel"], damageable.ram_safe_dv_mps,
					damageable.ram_lethal_dv_mps)
			_read_contacts(hull["body"] as RigidBody3D, sample)
			samples.append(sample)
	var pending: Array[Array] = []
	for ram: RamTracker.ContactRam in tracker.contacts(samples, delta):
		var damageable: Damageable = (by_id[ram.hull_id] as Dictionary)["damageable"]
		var other: Dictionary = by_id.get(ram.other_id, {})
		var info := HitInfo.new(ram.hull_id, ram.other_id, (other["damageable"] as Damageable).faction if not other.is_empty() else &"",
				damageable.hull.max_hp * ram.severity, ram.point, ram.normal, ram.relative_speed, HitInfo.CAUSE_RAM)
		pending.append(_pending(damageable, info, KIND_CONTACT, ram.dv))
	_apply_all(pending)


# Every body Jolt reported touching `rigid` in its last step, with the first contact point and `rigid`'s surface normal there
# (Jolt's normal points from the other body into this one).
static func _read_contacts(rigid: RigidBody3D, sample: RamTracker.Sample) -> void:
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(rigid.get_rid())
	if state == null:
		return
	for i: int in state.get_contact_count():
		sample.touch(state.get_contact_collider_id(i), state.get_contact_local_position(i), -state.get_contact_local_normal(i))


# --- swept: tunnelling speeds and props -------------------------------------------------------------------------


func _resolve_swept(hulls: Array[Dictionary], delta: float) -> void:
	for i: int in hulls.size():
		var first: Dictionary = hulls[i]
		for j: int in range(i + 1, hulls.size()):
			var second: Dictionary = hulls[j]
			if not (first["rigid"] or second["rigid"]):
				continue  # props never ram each other
			var first_hull: Damageable = first["damageable"]
			var second_hull: Damageable = second["damageable"]
			if first_hull.hull.destroyed or second_hull.hull.destroyed:
				continue  # a hull that went earlier this tick
			var both_rigid: bool = first["rigid"] and second["rigid"]
			var relative_speed: float = ((first["velocity"] as Vector3) - (second["velocity"] as Vector3)).length()
			if both_rigid and not RamMath.is_tunnelling(relative_speed, delta, first_hull.core_radius, second_hull.core_radius):
				tracker.keep_touching(first["id"], second["id"])  # Jolt's speed: its contacts decide
				continue
			var hit: Dictionary = _sweep_into(first, second)
			var reverse: Dictionary = _sweep_into(second, first)
			if hit.is_empty() or (not reverse.is_empty() and float(reverse["t"]) < float(hit["t"])):
				hit = reverse
			if not hit.is_empty() and tracker.swept_meeting(first["id"], second["id"]):
				_ram_swept(first, second, hit["point"], KIND_TUNNEL if both_rigid else KIND_PROP)


# `other`'s origin, moving relative to `hull` over this tick, against `hull`'s volumes grown by `other`'s origin core:
# {t, point (World-local, `other`'s origin at the touch)}, or empty.
func _sweep_into(hull: Dictionary, other: Dictionary) -> Dictionary:
	var to_body: Basis = hull["to_body"]
	var start: Vector3 = hull["start"]
	var end: Vector3 = hull["end"]
	var a: Vector3 = to_body * ((other["start"] as Vector3) - start)
	var b: Vector3 = to_body * ((other["end"] as Vector3) - end)
	var damageable: Damageable = hull["damageable"]
	var t: float = RamMath.sweep(damageable.shapes, damageable.bounding_radius, a, b,
			(other["damageable"] as Damageable).origin_core_radius)
	if t < 0.0:
		return {}
	return {"t": t, "point": start + (end - start) * t + (hull["basis"] as Basis) * (a + t * (b - a))}


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
		last_ram = "%s, %.1f of %.1f applied" % [ram[2], info.applied, info.damage]
		ram_resolved.emit(info)


static func _prop_velocity(body: Node3D) -> Vector3:
	var buoy := body as NavBuoy
	return buoy.velocity if buoy != null else Vector3.ZERO
