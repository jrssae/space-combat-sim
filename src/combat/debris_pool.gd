class_name DebrisPool
extends Node3D
## Debris of broken-up ships (architecture §15.6, §15.7, D22). Splat-bearing chunks are built once, at scenario load
## (`prepare`): `SETS_PER_TYPE` complete sets (one `DebrisChunk` per chunk of the asset) per chunked asset, parked. The raider's
## sets serve raiders; the Starfury's (cut from its LOD1 hull, §16 D35) serve the allies and the player.
## `burst` takes a free set and flies it; with every set busy it makes mesh-only chunks instead (a mesh is cheap to create
## and free, a splat node is not). Assets without chunks get generic dark shards. So the number of `GaussianSplatNode`s in
## the tree never changes while playing.
##
## This node is `World/Debris`, at the World origin, so a chunk's local position is its World position.
## Velocity of a chunk = the ship's velocity + `w x r` (the ship's spin at the chunk's offset) + 4-15 m/s outward; spin up
## to 90 deg/s about a random axis. The random numbers come from the `seed` the caller gives (the ship's id and the tick),
## so the same break-up looks the same.
##
## Console: provider `debris` (`sets`, `free_sets`, `active_chunks`, `mesh_chunks`).

const SETS_PER_TYPE: int = 2
const OUTWARD_SPEED_MPS: Vector2 = Vector2(4.0, 15.0)
const MAX_SPIN_DEG_S: float = 90.0
const SHARD_COUNT: int = 12
const ASSET_ROOT: String = "res://assets/generated"

# asset id -> Array of sets; a set is an Array[DebrisChunk] in `chunks[]` order.
var _sets: Dictionary = {}
# asset id -> the chunk entries (Hardpoints.chunks) the sets were built from.
var _entries: Dictionary = {}
var _mesh_chunks_live: int = 0


func _ready() -> void:
	DebugConsole.registry.register_provider(&"debris", ConsoleVars.new({
		&"sets": {"get": func() -> int: return set_count(), "doc": "Splat chunk sets built at load"},
		&"free_sets": {"get": func() -> int: return free_set_count(), "doc": "Chunk sets parked and ready"},
		&"active_chunks": {"get": func() -> int: return active_chunk_count(), "doc": "Chunks (any kind) in flight"},
		&"mesh_chunks": {"get": func() -> int: return _mesh_chunks_live, "doc": "Mesh-only chunks in flight (every set was busy)"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Builds the sets for a ship type (`ShipCatalog`): `SETS_PER_TYPE` sets of its asset's generated chunks, parked. Types that
## share an asset share its sets (the player's `starfury_aurora` and the allies' `starfury_ally`, §16 D35), so a second call for
## the same asset builds nothing. Returns the number of sets the asset has (0 for an asset without chunks).
func prepare(type: StringName) -> int:
	var spec: ShipSpec = ShipCatalog.spec_for(type)
	if spec == null:
		return 0
	var asset_id := StringName(spec.asset_id)
	if _sets.has(asset_id):
		return set_count(asset_id)
	var hardpoints: Hardpoints = Hardpoints.load_file(spec.hardpoints_path())
	if not hardpoints.valid:
		push_warning("DebrisPool: %s; no debris for %s" % [hardpoints.error, type])
		return 0
	return prepare_chunks(asset_id, hardpoints.chunks)


## As `prepare`, from chunk entries directly (tests).
func prepare_chunks(asset_id: StringName, entries: Array[Dictionary], with_splats: bool = true) -> int:
	if entries.is_empty():
		return 0
	_entries[asset_id] = entries
	var sets: Array = _sets.get(asset_id, [])
	var dir: String = ASSET_ROOT.path_join(String(asset_id))
	for i: int in SETS_PER_TYPE:
		var set: Array[DebrisChunk] = []
		for entry: Dictionary in entries:
			var chunk: DebrisChunk = DebrisChunk.create(entry, dir, with_splats)
			add_child(chunk)
			set.append(chunk)
		sets.append(set)
	_sets[asset_id] = sets
	return SETS_PER_TYPE


## Breaks a ship up at `xform` (World-local body pose) moving at `velocity` and spinning at `angular_velocity` (World
## frame, rad/s). `chunks` are the ship's `Hardpoints.chunks`; empty means generic shards. Returns the chunks launched.
func burst(asset_id: StringName, chunks: Array[Dictionary], xform: Transform3D, velocity: Vector3,
		angular_velocity: Vector3, seed_value: int) -> Array[DebrisChunk]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var launched: Array[DebrisChunk] = []
	if chunks.is_empty():
		for i: int in SHARD_COUNT:
			var shard: DebrisChunk = DebrisChunk.create_shard(rng)
			_track_one_shot(shard)
			add_child(shard)
			_fly(shard, Vector3.ZERO, xform, velocity, angular_velocity, rng, Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * 0.6)
			launched.append(shard)
		return launched
	var set: Array = _free_set(asset_id)
	var dir: String = ASSET_ROOT.path_join(String(asset_id))
	for i: int in chunks.size():
		var chunk: DebrisChunk = set[i] if not set.is_empty() else null
		if chunk == null:
			chunk = DebrisChunk.create(chunks[i], dir, false)
			chunk.one_shot = true
			_track_one_shot(chunk)
			add_child(chunk)
		_fly(chunk, chunks[i]["offset"], xform, velocity, angular_velocity, rng)
		launched.append(chunk)
	return launched


## Chunk sets built: every asset's, or only `asset_id`'s.
func set_count(asset_id: StringName = &"") -> int:
	if asset_id != &"":
		return (_sets.get(asset_id, []) as Array).size()
	var n: int = 0
	for sets: Array in _sets.values():
		n += sets.size()
	return n


## Chunk sets parked and ready: every asset's, or only `asset_id`'s.
func free_set_count(asset_id: StringName = &"") -> int:
	var n: int = 0
	for key: StringName in _sets:
		if asset_id != &"" and key != asset_id:
			continue
		for set: Array in _sets[key]:
			n += 1 if _set_is_free(set) else 0
	return n


## Chunks in flight: pooled and one-shot, shards included.
func active_chunk_count() -> int:
	var n: int = 0
	for child: Node in get_children():
		if child is DebrisChunk and (child as DebrisChunk).is_active():
			n += 1
	return n


func mesh_chunks_in_flight() -> int:
	return _mesh_chunks_live


# --- internals ---------------------------------------------------------------------------------------------------


func _free_set(asset_id: StringName) -> Array:
	for set: Array in _sets.get(asset_id, []):
		if _set_is_free(set):
			return set
	return []


func _set_is_free(set: Array) -> bool:
	for chunk: DebrisChunk in set:
		if chunk.is_active():
			return false
	return true


func _track_one_shot(chunk: DebrisChunk) -> void:
	_mesh_chunks_live += 1
	chunk.tree_exited.connect(func() -> void: _mesh_chunks_live -= 1, CONNECT_ONE_SHOT)


func _fly(chunk: DebrisChunk, body_offset: Vector3, xform: Transform3D, velocity: Vector3, angular_velocity: Vector3,
		rng: RandomNumberGenerator, jitter: Vector3 = Vector3.ZERO) -> void:
	var r_world: Vector3 = xform.basis * body_offset + jitter
	var outward: Vector3 = r_world.normalized() if r_world.length_squared() > 1e-6 else Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
	var v: Vector3 = velocity + angular_velocity.cross(r_world) + outward * rng.randf_range(OUTWARD_SPEED_MPS.x, OUTWARD_SPEED_MPS.y)
	var axis := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
	axis = axis.normalized() if axis.length_squared() > 1e-9 else Vector3.UP
	var w: Vector3 = axis * deg_to_rad(rng.randf_range(0.0, MAX_SPIN_DEG_S))
	chunk.launch(Transform3D(xform.basis, xform.origin + r_world), v, w)
