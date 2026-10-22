class_name RamResolver
extends Node
## Ram damage (architecture §16 D32, §16.3, M3-T04): a collision hurts each hull by the velocity change it gives that hull's
## own body (`RamMath.severity`), with `HitInfo.cause` `ram`. Once per physics tick at `process_physics_priority` 210: after the
## `HitResolver` (200), before the `WingDirector` (290) and the `WaveDirector` (300), so a hull a ram destroys leaves play in
## the same tick (§15.7: the `DestructionDirector` hides it on `destroyed`) and the waves count it.
##
## Over the active `Damageable`s, a ram is found one of three ways:
##
## - **Contact** (two rigid bodies at ordinary speeds): Jolt resolves the bounce and reports the contact. When a rigid body
##   reports a contact that was not there on the last run, a window of `CONTACT_WINDOW_TICKS` ticks opens: its Δv is the
##   largest change from its velocity before the contact (kept from the previous run) that its own forces (`Ship.applied_force`,
##   summed over the window) do not explain (`RamMath.contact_dv`), so thrust is never a ram. Jolt may report a speculative
##   contact a tick before the bounce and spread the bounce over two steps, hence the window; the ram lands once, when it
##   closes, or at once when the Δv is already lethal. Each body takes its own Δv, so the lighter one suffers more.
## - **Tunnelling** (two rigid bodies whose relative motion in one tick is more than half the smaller `core_radius`): Jolt's
##   discrete step could miss the hit or push one through the other. A target-relative swept test like the `HitResolver`'s
##   moves each body's origin, relative to the other over the coming step, against the other's hit volumes grown by its own
##   core radius. A hit destroys both (damage = `hull_max`).
## - **Props** (one side has no physics body: a nav buoy): the same swept test at any speed; each side's Δv is the momentum
##   split `|v_rel| × m_other / (m_self + m_other)` (`RamMath.split_dv`).
##
## One ram per pair per contact: a contact Jolt keeps reporting, or a swept overlap that lasts into the next tick, is not
## rammed again, and Jolt owns a pair while it reports a contact (no swept test then). God mode protects the player's hull
## (`Damageable.apply_hit`); the bounce is Jolt's and still happens. `HitInfo.shooter_id` is the other body and `faction` its
## faction: relations and friendly fire do not matter, a collision hurts whoever it hits. `settings.ram_damage` (read every
## tick) switches it off; ships still bounce.
##
## Rebase-safe: only velocities and instance ids are kept between ticks, never positions.
##
## Console: provider `ram` (`events`, `last`, `resolve_us`). `resolve_us` is a profiling readout from the wall clock, not
## gameplay time.

## A ram reached a hull; `info.applied` is set by then.
signal ram_resolved(info: HitInfo)

const LATE_PRIORITY: int = 210
## Ticks over which a new contact's velocity change is measured, counting the tick it is first reported.
const CONTACT_WINDOW_TICKS: int = 3
const KIND_CONTACT: String = "contact"
const KIND_TUNNEL: String = "tunnelling"
const KIND_PROP: String = "prop"

## Rams resolved this session (one per hull reached), the last one, and the last tick's cost in microseconds.
var events: int = 0
var last_ram: String = "none"
var resolve_us: int = 0
## `settings.ram_damage` as of the last tick.
var enabled: bool = true

# Instance id of every rigid body that was active on the previous run -> {"velocity", "accel", "contacts"} as of then.
var _previous: Dictionary = {}
# Pair keys (`_pair_key`) of the swept pairs whose volumes met on the previous run.
var _swept_touching: Dictionary = {}
# Instance id of a rigid body -> its open contact window (`_open_window`).
var _windows: Dictionary = {}


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


## One tick of ram detection with time step `delta`. `_physics_process` calls it every tick: the contact path compares with
## the previous call, so a test that steps it by hand must call it every tick too.
func resolve(delta: float) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	enabled = bool(Settings.get_value(&"ram_damage"))
	if enabled:
		var hulls: Array[Dictionary] = _gather(delta)
		var in_contact: Dictionary = {}
		_resolve_contacts(hulls, delta, in_contact)
		_resolve_swept(hulls, delta, in_contact)
		_remember(hulls)
	else:
		# Nothing carries over: a contact that began while off is never rammed when it is switched back on.
		_previous.clear()
		_swept_touching.clear()
		_windows.clear()
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
			hull["contacts"] = _contacts_of(rigid)
		else:
			# A prop moves itself in its own `_physics_process`, earlier in this tick.
			var velocity: Vector3 = _prop_velocity(body)
			hull["velocity"] = velocity
			hull["start"] = position - velocity * delta
			hull["end"] = position
			hull["accel"] = Vector3.ZERO
			hull["contacts"] = {}
		out.append(hull)
	return out


# --- contacts: Jolt bounced them ---------------------------------------------------------------------------------


func _resolve_contacts(hulls: Array[Dictionary], delta: float, in_contact: Dictionary) -> void:
	var by_id: Dictionary = {}
	for hull: Dictionary in hulls:
		by_id[hull["id"]] = hull
	var windows: Dictionary = {}
	var rams: Array[Array] = []
	for hull: Dictionary in hulls:
		var contacts: Dictionary = hull["contacts"]
		for other_id: int in contacts:
			in_contact[_pair_key(hull["id"], other_id)] = true
		var previous: Dictionary = _previous.get(hull["id"], {})
		if previous.is_empty():
			continue  # no velocity from the previous tick (just spawned, respawned or switched on)
		var window: Dictionary = _windows.get(hull["id"], {})
		if window.is_empty():
			var other_id: int = _first_new(contacts, previous["contacts"])
			if other_id == 0:
				continue
			window = _open_window(hull, other_id, previous, by_id)
		window["own_dv"] = (window["own_dv"] as Vector3) + (previous["accel"] as Vector3) * delta
		window["dv"] = maxf(float(window["dv"]), RamMath.contact_dv(hull["velocity"], window["v_before"], window["own_dv"]))
		window["ticks_left"] = int(window["ticks_left"]) - 1
		var damageable: Damageable = hull["damageable"]
		var severity: float = RamMath.severity(window["dv"], damageable.ram_safe_dv_mps, damageable.ram_lethal_dv_mps)
		if int(window["ticks_left"]) > 0 and severity < 1.0:
			windows[hull["id"]] = window  # still measuring
			continue
		if severity > 0.0:
			var info := HitInfo.new(hull["id"], window["other_id"], window["faction"], damageable.hull.max_hp * severity,
					window["point"], window["normal"], window["relative_speed"], HitInfo.CAUSE_RAM)
			rams.append([damageable, info, KIND_CONTACT, window["dv"]])
	_windows = windows  # a body that left play, or whose window closed, has none
	for ram: Array in rams:
		_apply(ram[0], ram[1], ram[2], ram[3])


# A new contact of `hull` with `other_id`: what it started from, and where and how fast the two met.
func _open_window(hull: Dictionary, other_id: int, previous: Dictionary, by_id: Dictionary) -> Dictionary:
	var other: Dictionary = by_id.get(other_id, {})
	var other_velocity: Vector3 = (_previous.get(other_id, {}) as Dictionary).get("velocity", Vector3.ZERO)
	var touch: Array = (hull["contacts"] as Dictionary)[other_id]
	return {
		"other_id": other_id,
		"faction": (other["damageable"] as Damageable).faction if not other.is_empty() else &"",
		"v_before": previous["velocity"],
		"own_dv": Vector3.ZERO,
		"dv": 0.0,
		"ticks_left": CONTACT_WINDOW_TICKS,
		"point": touch[0],
		"normal": -(touch[1] as Vector3),
		"relative_speed": ((previous["velocity"] as Vector3) - other_velocity).length(),
	}


# The first body in `contacts` that was not in `previous_contacts`, or 0.
static func _first_new(contacts: Dictionary, previous_contacts: Dictionary) -> int:
	for other_id: int in contacts:
		if not previous_contacts.has(other_id):
			return other_id
	return 0


# Every body Jolt reported touching `rigid` in its last step: instance id -> [World point, normal from the other body].
static func _contacts_of(rigid: RigidBody3D) -> Dictionary:
	var out: Dictionary = {}
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(rigid.get_rid())
	if state == null:
		return out
	for i: int in state.get_contact_count():
		var other_id: int = state.get_contact_collider_id(i)
		if not out.has(other_id):
			out[other_id] = [state.get_contact_local_position(i), state.get_contact_local_normal(i)]
	return out


# --- swept: tunnelling speeds and props -------------------------------------------------------------------------


func _resolve_swept(hulls: Array[Dictionary], delta: float, in_contact: Dictionary) -> void:
	var touching: Dictionary = {}
	for i: int in hulls.size():
		var first: Dictionary = hulls[i]
		for j: int in range(i + 1, hulls.size()):
			var second: Dictionary = hulls[j]
			var both_rigid: bool = first["rigid"] and second["rigid"]
			if not (first["rigid"] or second["rigid"]):
				continue  # props never ram each other
			var first_hull: Damageable = first["damageable"]
			var second_hull: Damageable = second["damageable"]
			if both_rigid and not RamMath.is_tunnelling(((first["velocity"] as Vector3) - (second["velocity"] as Vector3)).length(),
					delta, first_hull.core_radius, second_hull.core_radius):
				continue  # Jolt's speed
			var key: String = _pair_key(first["id"], second["id"])
			if in_contact.has(key) or first_hull.hull.destroyed or second_hull.hull.destroyed:
				continue  # Jolt owns the pair, or a hull went earlier this tick
			var hit: Dictionary = _sweep_into(first, second)
			var reverse: Dictionary = _sweep_into(second, first)
			if hit.is_empty() or (not reverse.is_empty() and float(reverse["t"]) < float(hit["t"])):
				hit = reverse
			if hit.is_empty():
				continue
			touching[key] = true
			if not _swept_touching.has(key):
				_ram_swept(first, second, hit["point"], both_rigid)
	_swept_touching = touching


# `other`'s origin, moving relative to `hull` over this tick, against `hull`'s volumes grown by `other`'s core radius:
# {t, point (World-local, `other`'s origin at the touch)}, or empty.
func _sweep_into(hull: Dictionary, other: Dictionary) -> Dictionary:
	var to_body: Basis = hull["to_body"]
	var start: Vector3 = hull["start"]
	var end: Vector3 = hull["end"]
	var a: Vector3 = to_body * ((other["start"] as Vector3) - start)
	var b: Vector3 = to_body * ((other["end"] as Vector3) - end)
	var damageable: Damageable = hull["damageable"]
	var t: float = RamMath.sweep(damageable.shapes, damageable.bounding_radius, a, b,
			(other["damageable"] as Damageable).core_radius)
	if t < 0.0:
		return {}
	return {"t": t, "point": start + (end - start) * t + (hull["basis"] as Basis) * (a + t * (b - a))}


func _ram_swept(first: Dictionary, second: Dictionary, point: Vector3, tunnelling: bool) -> void:
	var relative: Vector3 = (first["velocity"] as Vector3) - (second["velocity"] as Vector3)
	var speed: float = relative.length()
	var normal: Vector3 = relative / speed if speed > 1e-6 else Vector3.ZERO  # first's side faces where second came from
	var rams: Array[Array] = []
	for side: Array in [[first, second, normal], [second, first, -normal]]:
		var hull: Dictionary = side[0]
		var other: Dictionary = side[1]
		var damageable: Damageable = hull["damageable"]
		var dv: float = RamMath.split_dv(speed, hull["mass"], other["mass"])
		var damage: float = damageable.hull.max_hp if tunnelling else RamMath.damage(dv, damageable.ram_safe_dv_mps,
				damageable.ram_lethal_dv_mps, damageable.hull.max_hp)
		if damage <= 0.0:
			continue
		var info := HitInfo.new(hull["id"], other["id"], (other["damageable"] as Damageable).faction, damage, point, side[2],
				speed, HitInfo.CAUSE_RAM)
		rams.append([damageable, info, KIND_TUNNEL if tunnelling else KIND_PROP, dv])
	for ram: Array in rams:
		_apply(ram[0], ram[1], ram[2], ram[3])


# --- shared ------------------------------------------------------------------------------------------------------


# Every rigid body active now, for the next run's contact path. A hull destroyed this tick is out of play next tick.
func _remember(hulls: Array[Dictionary]) -> void:
	_previous.clear()
	for hull: Dictionary in hulls:
		if hull["rigid"] and not (hull["damageable"] as Damageable).hull.destroyed:
			_previous[hull["id"]] = {"velocity": hull["velocity"], "accel": hull["accel"], "contacts": hull["contacts"]}


func _apply(damageable: Damageable, info: HitInfo, kind: String, dv: float) -> void:
	# Names first: a destroyed raider goes back to the pool (and loses its name) inside apply_hit.
	var line: String = "%s -> %s: %s, dv %.1f m/s" % [HitResolver.name_of(info.shooter_id), HitResolver.name_of(info.target_id),
			kind, dv]
	events += 1
	damageable.apply_hit(info)
	last_ram = "%s, %.1f of %.1f applied" % [line, info.applied, info.damage]
	ram_resolved.emit(info)


static func _pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func _prop_velocity(body: Node3D) -> Vector3:
	var buoy := body as NavBuoy
	return buoy.velocity if buoy != null else Vector3.ZERO
