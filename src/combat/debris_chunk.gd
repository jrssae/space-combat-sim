class_name DebrisChunk
extends Node3D
## One piece of a broken-up ship (architecture §15.6, §15.7): a `GaussianSplatNode` child at identity that is never added,
## removed or re-transformed by hand (D22: GDGS re-merges the whole scene's splat data on every register and unregister;
## `SplatPoseSync` only draws it at the chunk's interpolated pose), and a `MeshInstance3D` with the chunk's OBJ, in group
## `splat_fallback_mesh`, shown instead of the splats when the splat renderer cannot draw them (and always for a chunk
## made without splats). It drifts and spins kinematically (no collisions), lives `LIFETIME_S`, shrinks to nothing over
## `SHRINK_S`, hides and parks (`parked` is emitted; a one-shot chunk frees itself instead).
##
## Frames: the chunk's PLY and OBJ are centred on the chunk's own centroid, so the node's origin is that centroid;
## `offset` (from `hardpoints.json` `chunks[]`) is where it sat in the ship's body frame.

## The chunk finished its life and is parked.
signal parked(chunk: DebrisChunk)

const LIFETIME_S: float = 8.0
const SHRINK_S: float = 0.5
const SPLATS_NAME: String = "ChunkSplats"
const MESH_NAME: String = "ChunkMesh"

var chunk_name: String = ""
## The chunk's centroid in the ship's body frame.
var offset: Vector3 = Vector3.ZERO
## Frees itself instead of parking (mesh-only chunks and generic shards are not pooled).
var one_shot: bool = false
## World-frame velocity (m/s) and angular velocity (rad/s).
var velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
var splats: GaussianSplatNode = null
var mesh_instance: MeshInstance3D = null

var _age_s: float = 0.0
var _orientation: Basis = Basis.IDENTITY  # orthonormal, kept apart from the scale so spinning cannot drift the size
var _active: bool = false
var _fallback: bool = false


## A parked chunk from a `hardpoints.json` `chunks[]` entry (`name`, `ply`, `obj`, `offset`) in `asset_dir`. With
## `with_splats` it owns a `GaussianSplatNode` (build these at scenario load only); without, only the mesh.
static func create(entry: Dictionary, asset_dir: String, with_splats: bool) -> DebrisChunk:
	var chunk := DebrisChunk.new()
	chunk.name = "Chunk_%s" % String(entry.get("name", "x")).to_pascal_case()
	chunk.chunk_name = String(entry.get("name", ""))
	chunk.offset = entry.get("offset", Vector3.ZERO)
	chunk.mesh_instance = MeshInstance3D.new()
	chunk.mesh_instance.name = MESH_NAME
	chunk.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var obj_path: String = asset_dir.path_join(String(entry.get("obj", "")))
	if ResourceLoader.exists(obj_path):
		chunk.mesh_instance.mesh = load(obj_path) as Mesh
		MeshMaterials.matte(chunk.mesh_instance.mesh)
	else:
		push_warning("DebrisChunk: %s is missing or not imported (run scripts/gen_assets.sh, then import)" % obj_path)
	chunk.add_child(chunk.mesh_instance)
	if with_splats:
		chunk.splats = GaussianSplatNode.new()
		chunk.splats.name = SPLATS_NAME
		var sync := SplatPoseSync.new()
		sync.name = "ChunkSplatSync"
		chunk.add_child(chunk.splats)
		chunk.add_child(sync)
		sync.splats = chunk.splats
		var ply_path: String = asset_dir.path_join(String(entry.get("ply", "")))
		if ResourceLoader.exists(ply_path):
			chunk.splats.gaussian = load(ply_path) as GaussianResource
		else:
			push_warning("DebrisChunk: %s is missing or not imported (run scripts/gen_assets.sh, then import)" % ply_path)
	chunk._park_state()
	return chunk


## A generic shard (a small dark box or prism) for assets without chunks.
static func create_shard(rng: RandomNumberGenerator) -> DebrisChunk:
	var chunk := DebrisChunk.new()
	chunk.name = "Shard"
	chunk.chunk_name = "shard"
	chunk.one_shot = true
	var mesh: Mesh
	if rng.randf() < 0.5:
		var box := BoxMesh.new()
		box.size = Vector3(rng.randf_range(0.2, 0.9), rng.randf_range(0.05, 0.25), rng.randf_range(0.2, 0.9))
		mesh = box
	else:
		var prism := PrismMesh.new()
		prism.size = Vector3(rng.randf_range(0.3, 1.0), rng.randf_range(0.2, 0.7), rng.randf_range(0.05, 0.2))
		mesh = prism
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.15, 0.14)
	material.roughness = 0.9
	chunk.mesh_instance = MeshInstance3D.new()
	chunk.mesh_instance.name = MESH_NAME
	chunk.mesh_instance.mesh = mesh
	chunk.mesh_instance.material_override = material
	chunk.add_child(chunk.mesh_instance)
	chunk._park_state()
	return chunk


func _init() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_to_group(SplatStatus.MESH_GROUP)


func _ready() -> void:
	_apply_visibility()


func _physics_process(delta: float) -> void:
	advance(delta)


## Splat renderer unavailable (or forced off): show the mesh, hide the splats. `SplatStatus` calls this.
func use_fallback_mesh(enabled: bool) -> void:
	_fallback = enabled
	_apply_visibility()


## True from `launch` until the chunk parks.
func is_active() -> bool:
	return _active


## Puts the chunk at `xform` (World-local, the chunk's own centroid) and sets it flying. Resets physics interpolation so
## it does not smear from where it was parked.
func launch(xform: Transform3D, p_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	_orientation = xform.basis.orthonormalized()
	global_transform = Transform3D(_orientation, xform.origin)
	velocity = p_velocity
	angular_velocity = p_angular_velocity
	_age_s = 0.0
	_active = true
	_apply_visibility()
	reset_physics_interpolation()


## Moves the chunk `delta` seconds: drift, spin, and the shrink-out at the end of its life. Public for tests.
func advance(delta: float) -> void:
	if not _active:
		return
	_age_s += delta
	global_position += velocity * delta
	var angle: float = angular_velocity.length() * delta
	if angle > 0.0:
		_orientation = (Basis(angular_velocity.normalized(), angle) * _orientation).orthonormalized()
	var size: float = 1.0
	if _age_s >= LIFETIME_S:
		size = 1.0 - clampf((_age_s - LIFETIME_S) / SHRINK_S, 0.0, 1.0)
	global_basis = _orientation.scaled(Vector3.ONE * maxf(size, 1e-4))
	if size <= 0.0:
		_finish()


## Seconds since launch.
func age_s() -> float:
	return _age_s


func park() -> void:
	_active = false
	_park_state()


func _finish() -> void:
	_active = false
	parked.emit(self)
	if one_shot:
		queue_free()
	else:
		_park_state()


func _park_state() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	scale = Vector3.ONE
	_orientation = Basis.IDENTITY


func _apply_visibility() -> void:
	if mesh_instance != null:
		mesh_instance.visible = _fallback or splats == null
	if splats != null:
		splats.visible = not _fallback
