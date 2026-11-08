class_name TurretMount
extends Node3D
## A defensive turret on a ship (M5-T21, D61): a gunner, not a pilot. The ship's brain keeps flying while its turrets pick
## their own targets. Everything a turret decides runs in the native core (`TurretRows`): the pick in the AI job one tick
## behind, the aim, gate and shot on the main thread each tick. This node is the mount's place on the ship (its origin the
## pivot, +Y its base's up, -Z the rest direction the core's azimuth starts from) and its model: `FramePasses` turns the
## model to the core's aim once a frame (no `_process` here). `ShipAssembly` builds one per `turrets[]` entry.
##
## The model hangs from two holders: `yaw` turns round the base's up by the azimuth, `pitch` (its child, at the trunnion) lifts
## by the elevation. A model's base goes under `yaw`, its barrels under `pitch`, both with the barrel along -Z at rest. The
## hull's own model is its manifest's `turret` entry (`model_for`, T27's textured mesh), pooled with the ship (D22).

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
# The turret models split for their mounts, by asset id (empty when the asset has none).
static var _models: Dictionary[String, Dictionary] = {}

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


## Puts a model from `model_for` on the mount: its base on `yaw`, its barrels on `pitch` at the trunnion.
func use_model(model: Dictionary) -> void:
	if model.is_empty():
		return
	var trunnion: Vector3 = model["trunnion"]
	pitch.position = trunnion
	var base := MeshInstance3D.new()
	base.name = "Base"
	base.mesh = model["base"]
	var barrel := MeshInstance3D.new()
	barrel.name = "Barrels"
	barrel.mesh = model["barrel"]
	barrel.position = -trunnion
	set_model(base, barrel)


## The turret model a hull's manifest names (`turret`: its mesh in the turret's frame, the trunnion and the muzzles), split
## once per asset into `base` (what turns round the base) and `barrel` (the barrels, which lift too), with `trunnion`;
## empty when the asset has no turret model.
static func model_for(asset_id: String) -> Dictionary:
	if _models.has(asset_id):
		return _models[asset_id]
	var entry: Dictionary = MeshAssets.read_manifest(asset_id).get("turret", {})
	var model: Dictionary = {}
	var mesh: Mesh = null
	if not (entry.get("mesh", {}) as Dictionary).is_empty():
		mesh = MeshAssets.load_textured(ShipSpec.ASSET_ROOT.path_join(asset_id), entry["mesh"])
	if mesh != null:
		var trunnion: Vector3 = _vec3(entry.get("trunnion", [0.0, 0.0, 0.0]))
		var muzzles: Array[Vector3] = []
		for m: Variant in entry.get("muzzles", []):
			muzzles.append(_vec3(m))
		var parts: Array[ArrayMesh] = split_barrels(mesh, muzzles, trunnion)
		model = {"base": parts[0], "barrel": parts[1], "trunnion": trunnion}
	_models[asset_id] = model
	return model


## A turret mesh split into what turns round the base and the barrels: a triangle is a barrel's when every corner lies within
## a barrel's reach of a muzzle's axis (along -Z through the muzzle) between the muzzle and the trunnion, and it is a barrel's
## side (facing across the axis) or one of its flat rings (all at one depth), not the dome its root sinks into. Public for the
## tests.
static func split_barrels(mesh: Mesh, muzzles: Array[Vector3], trunnion: Vector3) -> Array[ArrayMesh]:
	var base := ArrayMesh.new()
	var barrel := ArrayMesh.new()
	# The barrels sit a fifth of their spacing in radius (the generator's proportions); the reach leaves room for the brake.
	var reach: float = 0.3 * muzzles[0].distance_to(muzzles[1]) if muzzles.size() >= 2 else 0.0
	for s: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for i: int in vertices.size():
				indices[i] = i
		var on_barrel := PackedByteArray()
		on_barrel.resize(vertices.size())
		for i: int in vertices.size():
			var v: Vector3 = vertices[i]
			for m: Vector3 in muzzles:
				if reach > 0.0 and v.z >= m.z - 1e-3 and v.z <= trunnion.z and Vector2(v.x - m.x, v.y - m.y).length() <= reach:
					on_barrel[i] = 1
					break
		var kept := PackedInt32Array()
		var lifted := PackedInt32Array()
		for t: int in range(0, indices.size() - 2, 3):
			var a: int = indices[t]
			var b: int = indices[t + 1]
			var c: int = indices[t + 2]
			var into: PackedInt32Array = kept
			if on_barrel[a] == 1 and on_barrel[b] == 1 and on_barrel[c] == 1 \
					and _barrel_shaped(vertices[a], vertices[b], vertices[c]):
				into = lifted
			into.append(a)
			into.append(b)
			into.append(c)
		for pair: Array in [[base, kept], [barrel, lifted]]:
			var target: ArrayMesh = pair[0]
			if (pair[1] as PackedInt32Array).is_empty():
				continue
			var part: Array = arrays.duplicate()
			part[Mesh.ARRAY_INDEX] = pair[1]
			target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part)
			target.surface_set_material(target.get_surface_count() - 1, mesh.surface_get_material(s))
	return [base, barrel]


# A barrel's face: its side runs along the axis, its rings (the brake's step, the muzzle, the root) lie at one depth.
static func _barrel_shaped(a: Vector3, b: Vector3, c: Vector3) -> bool:
	if absf(a.z - b.z) < 1e-4 and absf(a.z - c.z) < 1e-4:
		return true
	var n: Vector3 = (b - a).cross(c - a)
	return n.length_squared() > 1e-12 and absf(n.normalized().z) < 0.2


static func _vec3(v: Variant) -> Vector3:
	var a: Array = v if v is Array else []
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO


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


# Joins the core's mounts (a turret's shot is a bolt row); without a core the turret holds fire.
func _bind() -> void:
	var sim: SimCore = SimCore.for_tree(get_tree()) if is_inside_tree() else null
	if sim == null or sim.turrets == null or not sim.bolt_rows_on() or _body == null or weapon == null:
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
