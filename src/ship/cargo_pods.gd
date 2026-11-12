class_name CargoPods
extends Node3D
## A hull's removable cargo pods (M5-T16, D59, Q17: the Brakiri Bokmai). Built once with its ship from the hardpoints'
## `cargo_pods[]` mounts and the manifest's `pod` entry, pooled with it (D22): every mount has its pod's mesh and collision
## shapes ready, and `set_count` mounts the first n of them. A mounted pod adds its mass, inertia and hit volumes to the ship
## and switches LOD with the hull (the importer's mesh levels, and the far dot hides it with the hull). When the ship breaks
## up, `debris_entries` hands the mounted pods to the debris as chunks of their own. Letting go of a pod in flight waits for
## M14's tether.

const NODE_NAME: StringName = &"CargoPods"
## The most pods a hull carries (the Bokmai's three mounts).
const MAX_PODS: int = 3

## Pods mounted now.
var count: int = 0
## The pod's mass, kg (the manifest's `pod.mass_kg`).
var pod_mass_kg: float = 0.0

var _ship: Ship = null
var _mounts: Array[Dictionary] = []
var _pod_collision: Array[Dictionary] = []
var _meshes: Array[MeshInstance3D] = []
var _owners: Array[PackedInt32Array] = []
var _pod_obj: String = ""
var _pod_glb: String = ""


## The pods for `ship`, or null when its hull has no pod mounts or no pod model. Adds itself under the ship with every pod
## mounted.
static func build_for(ship: Ship) -> CargoPods:
	var hardpoints: Hardpoints = ship.get_hardpoints()
	if hardpoints == null or not hardpoints.valid or hardpoints.cargo_pods.is_empty():
		return null
	var pod: Dictionary = MeshAssets.read_manifest(ship.spec.asset_id).get("pod", {})
	if pod.is_empty():
		push_warning("CargoPods: %s has pod mounts but no pod model (run scripts/gen_assets.sh)" % ship.spec.asset_id)
		return null
	var pods := CargoPods.new()
	pods.name = NODE_NAME
	pods._ship = ship
	pods._mounts = hardpoints.cargo_pods.slice(0, MAX_PODS)
	pods.pod_mass_kg = float(pod.get("mass_kg", 0.0))
	pods._pod_obj = String(pod.get("obj", ""))
	pods._pod_glb = String((pod.get("mesh", {}) as Dictionary).get("file", ""))
	for raw: Variant in pod.get("collision", []):
		var entry: Dictionary = Hardpoints.collision_entry(raw)
		if not entry.is_empty():
			pods._pod_collision.append(entry)
	ship.add_child(pods)
	pods._build()
	pods.set_count(-1)
	return pods


## The CargoPods under `ship`, or null.
static func of(ship: Node) -> CargoPods:
	return ship.get_node_or_null(NodePath(NODE_NAME)) as CargoPods if ship != null else null


## The mounts this hull has.
func mount_count() -> int:
	return _mounts.size()


## Mounts the first `n` pods (clamped to the mounts; -1 mounts them all) and takes the others off: mass, inertia, Jolt
## shapes, hit volumes and meshes follow.
func set_count(n: int) -> void:
	count = _mounts.size() if n < 0 else clampi(n, 0, _mounts.size())
	for i: int in _mounts.size():
		var on: bool = i < count
		_meshes[i].visible = on
		for owner_id: int in _owners[i]:
			_ship.shape_owner_set_disabled(owner_id, not on)
	_apply_mass()
	_apply_hit_volumes()
	if _ship.is_inside_tree():
		ContactScan.touch(_ship)  # the core reads the hull's new bounding radius at its next sync


## The hull's hit volumes with the mounted pods' (ship frame).
func collision_with_pods() -> Array[Dictionary]:
	var out: Array[Dictionary] = _ship.get_hardpoints().collision.duplicate()
	for i: int in count:
		for entry: Dictionary in _pod_collision:
			out.append({"name": "%s_%s" % [_mounts[i]["name"], entry["name"]], "type": entry["type"], "shape": entry["shape"],
					"transform": (_mounts[i]["transform"] as Transform3D) * (entry["transform"] as Transform3D)})
	return out


## The mounted pods as drawn parts, ship frame (`{mesh, transform}`): what the target preview adds to the hull (T43).
func mounted_parts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in count:
		if _meshes[i].mesh != null:
			out.append({"mesh": _meshes[i].mesh, "transform": _mounts[i]["transform"]})
	return out


## The mounted pods as break-up chunks (`Hardpoints.chunks`' form): each flies off on its own.
func debris_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in count:
		var at: Vector3 = _mounts[i]["position"]
		out.append({"name": String(_mounts[i]["name"]), "obj": _pod_obj, "offset": at, "joint": at, "mesh": _pod_glb})
	return out


# Every mount's mesh and Jolt shapes, made once; `set_count` only shows, hides and switches them.
func _build() -> void:
	var mesh: Mesh = MeshAssets.chunk_mesh(Ship.asset_dir(_ship.spec), _pod_glb) if not _pod_glb.is_empty() else null
	for mount: Dictionary in _mounts:
		var instance := MeshInstance3D.new()
		instance.name = "Pod_%s" % String(mount["name"]).to_pascal_case()
		instance.mesh = mesh
		instance.transform = mount["transform"]
		add_child(instance)
		_meshes.append(instance)
		var owners := PackedInt32Array()
		for entry: Dictionary in _pod_collision:
			var owner_id: int = _ship.create_shape_owner(_ship)
			_ship.shape_owner_add_shape(owner_id, entry["shape"])
			_ship.shape_owner_set_transform(owner_id, (mount["transform"] as Transform3D) * (entry["transform"] as Transform3D))
			owners.append(owner_id)
		_owners.append(owners)


# The ship's mass and inertia with the mounted pods as point masses about the hull's centre of mass.
func _apply_mass() -> void:
	var spec: ShipSpec = _ship.spec
	var inertia: Vector3 = spec.inertia
	var com: Vector3 = _ship.get_hardpoints().center_of_mass
	for i: int in count:
		var r: Vector3 = (_mounts[i]["position"] as Vector3) - com
		inertia += pod_mass_kg * Vector3(r.y * r.y + r.z * r.z, r.x * r.x + r.z * r.z, r.x * r.x + r.y * r.y)
	_ship.mass = spec.mass + pod_mass_kg * count
	_ship.inertia = inertia


# The hull's hit volumes follow the pods (the hull's health is kept).
func _apply_hit_volumes() -> void:
	var damageable: Damageable = Damageable.of(_ship)
	if damageable != null and damageable.hull != null:
		damageable.set_volumes(collision_with_pods())
