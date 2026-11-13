class_name DebrisChunk
extends Node3D
## One piece of a broken-up ship (architecture §15.6, §15.7): a `MeshInstance3D` drawing the chunk's textured mesh (M4-T30d, its
## `mesh` entry, cut from the hull on the hull's maps, so chunks instance with the hulls), or its OBJ for an entry without one. It
## drifts and spins kinematically (no collisions), falls with the frame's pull (M6-T07, `HeldPull`), lives `LIFETIME_S`, shrinks to nothing over `SHRINK_S`, hides and parks (`parked`
## is emitted; a one-shot chunk frees itself instead). A Starfury's chunk is first *held* (M3-T28): drawn and busy, but placed by its
## wreck (`place_held`) until `release` sets it flying, and it wears its ship's livery (`set_livery`).
##
## Frames: the chunk's meshes are centred on the chunk's own centroid, so the node's origin is that centroid; `offset` (from
## `hardpoints.json` `chunks[]`) is where it sat in the ship's body frame.

## The chunk finished its life and is parked.
signal parked(chunk: DebrisChunk)

const LIFETIME_S: float = 8.0
const SHRINK_S: float = 0.5
const MESH_NAME: String = "ChunkMesh"

var chunk_name: String = ""
## The chunk's centroid in the ship's body frame.
var offset: Vector3 = Vector3.ZERO
## Frees itself instead of parking (one-shot chunks and generic shards are not pooled).
var one_shot: bool = false
## World-frame velocity (m/s) and angular velocity (rad/s).
var velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
var mesh_instance: MeshInstance3D = null
## The chunk's textured mesh (M4-T30d), null for a shard or before the assets are generated.
var textured_mesh: Mesh = null

var _age_s: float = 0.0
var _pull := HeldPull.new()  # gravity (M6-T07), read once a second of its life
var _vent: FxPool = null
var _vent_handle: int = 0
var _orientation: Basis = Basis.IDENTITY  # orthonormal, kept apart from the scale so spinning cannot drift the size
var _active: bool = false
var _placed_this_tick: bool = false
var _held: bool = false


## A parked chunk from a `hardpoints.json` `chunks[]` entry (`name`, `obj`, `offset`, `mesh`) in `asset_dir`.
static func create(entry: Dictionary, asset_dir: String) -> DebrisChunk:
	var chunk := DebrisChunk.new()
	chunk.name = "Chunk_%s" % String(entry.get("name", "x")).to_pascal_case()
	chunk.chunk_name = String(entry.get("name", ""))
	chunk.offset = entry.get("offset", Vector3.ZERO)
	chunk.mesh_instance = MeshInstance3D.new()
	chunk.mesh_instance.name = MESH_NAME
	chunk.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var textured: String = String(entry.get("mesh", ""))
	if not textured.is_empty():
		chunk.textured_mesh = MeshAssets.chunk_mesh(asset_dir, textured)
	if chunk.textured_mesh == null:
		chunk.mesh_instance.mesh = _obj_mesh(asset_dir.path_join(String(entry.get("obj", ""))))
	else:
		chunk.mesh_instance.mesh = chunk.textured_mesh
	chunk.add_child(chunk.mesh_instance)
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


# A chunk without a textured mesh draws its OBJ, matte.
static func _obj_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		push_warning("DebrisChunk: %s is missing or not imported (run scripts/gen_assets.sh, then import)" % path)
		return null
	var mesh := load(path) as Mesh
	MeshMaterials.matte(mesh)
	return mesh


func _init() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)


func _exit_tree() -> void:
	_stop_vent()


func _physics_process(delta: float) -> void:
	if _placed_this_tick:  # the pool already put it where the wreck is this tick; a step now would pop it ahead
		_placed_this_tick = false
		return
	advance(delta)


## Paints the textured chunk in its ship's livery (null: plain). Pooled chunks are repainted for every wreck.
func set_livery(livery: Livery) -> void:
	if mesh_instance == null or textured_mesh == null or not (textured_mesh.surface_get_material(0) is ShaderMaterial):
		return  # a hull without a livery table (a raider's) takes no livery values
	(livery if livery != null else Livery.new()).apply(mesh_instance)


## True from `launch` until the chunk parks.
func is_active() -> bool:
	return _active


## Puts the chunk at `xform` (World-local, the chunk's own centroid) and sets it flying. Resets physics interpolation so
## it does not smear from where it was parked.
func launch(xform: Transform3D, p_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	ShiftableRegistry.set_out(self, WorldFrame.PARKED_META, false)
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	_orientation = xform.basis.orthonormalized()
	global_transform = Transform3D(_orientation, xform.origin)
	velocity = p_velocity
	angular_velocity = p_angular_velocity
	_age_s = 0.0
	_pull.reset()
	_active = true
	reset_physics_interpolation()


## Puts the chunk at `xform` as part of a wreck moving at `p_velocity` (the wreck's motion at the chunk): drawn and busy, but
## only `place_held` moves it. Its life and vent start at `release`.
func hold(xform: Transform3D, p_velocity: Vector3, p_angular_velocity: Vector3) -> void:
	launch(xform, p_velocity, p_angular_velocity)
	_held = true


## Follows its wreck to `xform` (World-local), moving at `p_velocity`.
func place_held(xform: Transform3D, p_velocity: Vector3) -> void:
	_orientation = xform.basis.orthonormalized()
	global_transform = Transform3D(_orientation, xform.origin)
	velocity = p_velocity


func is_held() -> bool:
	return _held


## Lets a held chunk go: it flies on at `p_velocity` and `p_angular_velocity` from where it is, its life starting now.
func release(p_velocity: Vector3, p_angular_velocity: Vector3, placed_this_tick: bool = false) -> void:
	_held = false
	_placed_this_tick = placed_this_tick
	velocity = p_velocity
	angular_velocity = p_angular_velocity
	_age_s = 0.0


## Sparks and venting from `pool` for `duration_s`, following the chunk (same velocity, same start). Ends with the chunk.
func vent(pool: FxPool, duration_s: float) -> void:
	_stop_vent()
	_vent = pool
	_vent_handle = pool.burst(FxSpecs.DEBRIS, global_position, Vector3.UP, velocity, duration_s)


## True while an emitter is venting for this chunk, and its handle in the pool (tests).
func has_vent() -> bool:
	return _vent != null and _vent.is_live(_vent_handle)


func vent_handle() -> int:
	return _vent_handle


## A velocity rebase (`WorldFrame.boost`): a chunk in flight keeps its universe velocity. A held one follows its wreck.
func frame_boost(dv: Vector3) -> void:
	if _active:
		velocity -= dv
		_pull.reset()


## Moves the chunk `delta` seconds: drift, spin, and the shrink-out at the end of its life. Public for tests.
func advance(delta: float) -> void:
	if not _active or _held:
		return
	_age_s += delta
	velocity = _pull.kick(self, velocity, delta)
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
	_held = false
	_stop_vent()
	_park_state()


func _finish() -> void:
	_active = false
	_held = false
	_stop_vent()
	parked.emit(self)
	if one_shot:
		queue_free()
	else:
		_park_state()


# A chunk that is gone leaves no emitter venting where it was.
func _stop_vent() -> void:
	if _vent != null and is_instance_valid(_vent):
		_vent.stop(_vent_handle)
	_vent = null
	_vent_handle = 0


func _park_state() -> void:
	ShiftableRegistry.set_out(self, WorldFrame.PARKED_META, true)  # rebases leave it: `launch` places it (M6-T21)
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	scale = Vector3.ONE
	_orientation = Basis.IDENTITY
