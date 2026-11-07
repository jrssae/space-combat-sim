class_name TurretMount
extends Node3D
## A defensive turret on a ship (M5-T21, D61): a gunner, not a pilot. The ship's brain keeps flying while its turrets pick
## their own targets. Everything a turret decides runs in the native core (`TurretRows`): the pick in the AI job one tick
## behind, the aim, gate and shot on the main thread each tick. This node is the mount's place on the ship (its origin the
## pivot, +Y its base's up, -Z the rest direction the core's azimuth starts from) and its model: `FramePasses` turns the
## model to the core's aim once a frame (no `_process` here). `ShipAssembly` builds one per `turrets[]` entry.
##
## The model hangs from two holders: `yaw` turns round the base's up by the azimuth, `pitch` (its child) lifts by the
## elevation. A model's base goes under `yaw`, its barrel under `pitch`, both with the barrel along -Z at rest.

## A shot left the barrel at `at` (World frame): the sound and anything else that follows a shot.
signal shot_fired(at: Vector3)

## The entry's name in `hardpoints.json`.
var mount_name: String = ""
## The base's up in the ship's frame, and the cone round it the barrel may point into, degrees (200: a hemisphere and 10
## degrees below the base).
var up: Vector3 = Vector3.UP
var arc_deg: float = 200.0
## m from the pivot to the barrel's tip, where a shot leaves.
var barrel_m: float = 3.0
var weapon: WeaponSpec = null
var faction: StringName = Factions.NEUTRAL:
	set(value):
		faction = value
		if _slot >= 0 and _sim != null and is_instance_valid(_sim) and _sim.core != null:
			_sim.core.set_turret_faction(_slot, value)

var yaw: Node3D = null
var pitch: Node3D = null
## Shots this mount fired (a readout).
var shots: int = 0

# Every mount in a tree, so the core can bind them all when it comes or goes.
static var _live: Array[TurretMount] = []

var _body: RigidBody3D = null
var _sim: SimCore = null
var _slot: int = -1


## A mount from one `Hardpoints.turrets` entry, firing `p_weapon` for `p_faction`.
static func create(entry: Dictionary, p_weapon: WeaponSpec, p_faction: StringName) -> TurretMount:
	var mount := TurretMount.new()
	mount.mount_name = String(entry.get("name", "turret"))
	mount.name = "Turret_%s" % mount.mount_name
	mount.up = entry.get("up", Vector3.UP)
	mount.arc_deg = float(entry.get("arc_deg", 200.0))
	mount.barrel_m = float(entry.get("barrel_m", 3.0))
	mount.weapon = p_weapon
	mount.faction = p_faction
	mount.transform = Transform3D(base_basis(mount.up), entry.get("position", Vector3.ZERO))
	return mount


## The mount's basis in the ship's frame: +Y the base's up, -Z the rest direction (the ship's nose laid flat on the base,
## or its top when the base faces the nose), as the core's `rest_forward` takes it.
static func base_basis(p_up: Vector3) -> Basis:
	var u: Vector3 = p_up.normalized() if not p_up.is_zero_approx() else Vector3.UP
	var flat: Vector3 = Vector3.FORWARD - u * u.dot(Vector3.FORWARD)
	if flat.length_squared() <= 1e-4:
		flat = Vector3.UP - u * u.dot(Vector3.UP)
	var forward: Vector3 = flat.normalized()
	var z: Vector3 = -forward
	return Basis(u.cross(z), u, z)


func _init() -> void:
	yaw = Node3D.new()
	yaw.name = "Yaw"
	add_child(yaw)
	pitch = Node3D.new()
	pitch.name = "Pitch"
	yaw.add_child(pitch)


func _enter_tree() -> void:
	_live.append(self)
	_body = get_parent() as RigidBody3D
	_bind()
	var passes: FramePasses = FramePasses.of(self)
	if passes != null:
		passes.add_turret(self)


func _exit_tree() -> void:
	_live.erase(self)
	_unbind()
	var passes: FramePasses = FramePasses.current()
	if passes != null:
		passes.remove_turret(self)


func _notification(what: int) -> void:
	# A parked ship's turrets hold fire; back in play, each starts afresh (a new binding in the core).
	if _slot >= 0 and (what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED) and is_instance_valid(_sim) \
			and _sim.core != null:
		_sim.core.set_turret_live(_slot, what == NOTIFICATION_ENABLED)


## Puts a model on the mount: `base` turns with the azimuth, `barrel` (optional) lifts with the elevation too.
func set_model(base: Node3D, barrel: Node3D = null) -> void:
	if base != null:
		yaw.add_child(base)
	if barrel != null:
		pitch.add_child(barrel)


## Turns the model to an azimuth and elevation (rad), as the core's row holds them (the frame pass calls it).
func turn_to(azimuth: float, elevation: float) -> void:
	yaw.rotation = Vector3(0.0, azimuth, 0.0)
	pitch.rotation = Vector3(elevation, 0.0, 0.0)


## The core's slot for this mount, -1 when unbound.
func slot() -> int:
	return _slot


## The core this mount is bound to, or null.
func bound_sim() -> SimCore:
	return _sim if _slot >= 0 and is_instance_valid(_sim) else null


## The core fired a shot from this mount (`TurretRows.step`).
func on_fired(at: Vector3) -> void:
	shots += 1
	shot_fired.emit(at)


## Binds every mount to the core, as the core stands now (it came or went).
static func rebind_all() -> void:
	for mount: TurretMount in _live:
		if is_instance_valid(mount):
			mount._bind()


# Joins the core's mounts when it owns the bolts (a turret's shot is a bolt row); else the turret holds fire.
func _bind() -> void:
	var sim: SimCore = SimCore.for_tree(get_tree()) if is_inside_tree() else null
	if sim == null or sim.turrets == null or not SimCore.bolt_rows_enabled() or _body == null or weapon == null:
		_unbind()
		return
	if _slot >= 0 and _sim == sim:
		return
	_unbind()
	var slot_now: int = sim.turrets.register(self, _body.get_instance_id(), weapon, faction)
	if slot_now < 0:
		return
	_sim = sim
	_slot = slot_now
	if not can_process():
		_sim.core.set_turret_live(_slot, false)


func _unbind() -> void:
	if _slot >= 0 and is_instance_valid(_sim) and _sim.turrets != null:
		_sim.turrets.unregister(_slot)
	_slot = -1
	_sim = null
