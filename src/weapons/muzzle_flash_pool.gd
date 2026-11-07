class_name MuzzleFlashPool
extends Node3D
## One pool of muzzle flashes for the lean ships (M4-T35, refactor finding 12; architecture §17.13): instead of a `MuzzleFlash`
## node under a `Marker3D` per muzzle, a lean ship's cannon triggers a flash here with its ship and the muzzle's transform in
## the ship's frame (the hardpoints' data), and one `MultiMeshInstance3D` draws every live flash once a frame, each a billboard
## quad at `ship.global_transform * muzzle` grown and faded as `MuzzleFlash` grew and faded its quad, with the per-instance
## colour's alpha as the fade. A flash lights the nose as before: a `LightEmitter` anchored on the ship at the muzzle (plus
## the flash's offset down the barrel) enters the `LightRig`'s competition for `EmitterCurves.FLASH_S`; the emitters are a
## small set reused across shots, so a volley allocates nothing.
##
## One pool per World (`attach`), made by the first lean cannon that needs it; the player's ship keeps its markers and
## flash nodes (the HUD reads the markers). A visual, animated once a frame by the frame's passes (`FramePasses`, M4-T36:
## no `_process` of its own); how it looks is (H).

const NODE_NAME: StringName = &"MuzzleFlashPool"
## The most flashes alight at once; older ones are dropped when the pool is full.
const CAPACITY: int = 256
## The most lights the pool enters at once (the rig has 8 slots; more candidates only cost the picker).
const LIGHTS: int = 24

## Flashes drawn in the last frame (a readout).
var drawn: int = 0

var _instance: MultiMeshInstance3D = null
var _ships: Array[Node3D] = []
var _muzzles: Array[Transform3D] = []
var _ages: PackedFloat64Array = PackedFloat64Array()
var _emitters: Array[LightEmitter] = []  # per live flash, null when it has no light
var _spare: Array[LightEmitter] = []
var _rig: LightRig = null
var _buffer: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := (MuzzleFlash.MATERIAL as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.vertex_color_use_as_albedo = true  # the instance colour's alpha is the fade
	quad.material = material
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.mesh = quad
	mesh.custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)
	mesh.instance_count = CAPACITY
	mesh.visible_instance_count = 0
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Flashes"
	_instance.multimesh = mesh
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_instance, false, Node.INTERNAL_MODE_BACK)
	_buffer.resize(CAPACITY * 16)


func _enter_tree() -> void:
	var passes: FramePasses = FramePasses.of(self)
	if passes != null:
		passes.add_flash_pool(self)


func _exit_tree() -> void:
	var passes: FramePasses = FramePasses.current()
	if passes != null:
		passes.remove_flash_pool(self)
	for emitter: LightEmitter in _emitters:
		_end_light(emitter)
	_emitters.clear()
	_ships.clear()
	_muzzles.clear()
	_ages.clear()


## The pool under `world`, made on first ask; null without a world.
static func attach(world: Node) -> MuzzleFlashPool:
	if world == null or not is_instance_valid(world) or not world.is_inside_tree():
		return null
	var found := world.get_node_or_null(NodePath(NODE_NAME)) as MuzzleFlashPool
	if found != null:
		return found
	var made := MuzzleFlashPool.new()
	world.add_child(made)
	return made


## Starts a flash at `muzzle` (in `ship`'s frame) riding with `ship`.
func trigger(ship: Node3D, muzzle: Transform3D) -> void:
	if _ships.size() >= CAPACITY:
		_drop(0)
	_ships.append(ship)
	_muzzles.append(muzzle)
	_ages.append(0.0)
	_emitters.append(_start_light(ship, muzzle))


## Ends every flash of `ship` at once (a ship back in play shows nothing of its last shot).
func clear_for(ship: Node3D) -> void:
	var i: int = _ships.size() - 1
	while i >= 0:
		if _ships[i] == ship:
			_drop(i)
		i -= 1


## Flashes alight now, and those of `ship`.
func active_count() -> int:
	return _ships.size()


func active_for(ship: Node3D) -> int:
	var count: int = 0
	for s: Node3D in _ships:
		if s == ship:
			count += 1
	return count


## Ages every flash by `delta` seconds and draws the live ones (the frame's pass, `FramePasses.advance_flash_pools`).
func advance(delta: float) -> void:
	var i: int = _ships.size() - 1
	while i >= 0:
		_ages[i] += delta
		var ship: Node3D = _ships[i]
		if _ages[i] >= EmitterCurves.FLASH_S or not is_instance_valid(ship) or not ship.is_inside_tree() \
				or not ship.is_visible_in_tree():
			_drop(i)
		elif _emitters[i] != null:
			_emitters[i].energy = EmitterCurves.flash_energy(_ages[i])
		i -= 1
	drawn = 0
	for k: int in _ships.size():
		var age: float = _ages[k]
		if age >= MuzzleFlash.DURATION_S:
			continue  # the light outlasts the quad by 10 ms
		var t: float = age / MuzzleFlash.DURATION_S
		var size: float = MuzzleFlash.SIZE_M * lerpf(MuzzleFlash.START_SCALE, 1.0, t)
		var at: Vector3 = _ships[k].get_global_transform_interpolated() * _muzzles[k].origin
		var base: int = drawn * 16
		_buffer[base] = size
		_buffer[base + 1] = 0.0
		_buffer[base + 2] = 0.0
		_buffer[base + 3] = at.x
		_buffer[base + 4] = 0.0
		_buffer[base + 5] = size
		_buffer[base + 6] = 0.0
		_buffer[base + 7] = at.y
		_buffer[base + 8] = 0.0
		_buffer[base + 9] = 0.0
		_buffer[base + 10] = size
		_buffer[base + 11] = at.z
		_buffer[base + 12] = 1.0
		_buffer[base + 13] = 1.0
		_buffer[base + 14] = 1.0
		_buffer[base + 15] = 1.0 - t
		drawn += 1
	if _instance != null:
		if drawn > 0:
			RenderingServer.multimesh_set_buffer(_instance.multimesh.get_rid(), _buffer)
		_instance.multimesh.visible_instance_count = drawn


# Removes flash `i`, its light with it.
func _drop(i: int) -> void:
	_end_light(_emitters[i])
	_ships.remove_at(i)
	_muzzles.remove_at(i)
	_ages.remove_at(i)
	_emitters.remove_at(i)


# A light for a new flash on `ship` at `muzzle`, or null when the pool's lights are all alight.
func _start_light(ship: Node3D, muzzle: Transform3D) -> LightEmitter:
	if _rig == null or not is_instance_valid(_rig):
		_rig = LightRig.of(self)
	if _rig == null:
		return null
	var alight: int = 0
	for e: LightEmitter in _emitters:
		if e != null:
			alight += 1
	if alight >= LIGHTS:
		return null
	var emitter: LightEmitter
	if _spare.is_empty():
		emitter = LightEmitter.new("muzzle flash", LightEmitter.PRIORITY_MUZZLE_FLASH, Color(1.0, 0.85, 0.6), 0.0,
				EmitterCurves.FLASH_RANGE_M)
	else:
		emitter = _spare.pop_back()
	emitter.anchor = ship
	emitter.offset = muzzle * Vector3(0.0, 0.0, -EmitterCurves.FLASH_OFFSET_M)  # the muzzle's -Z is down the barrel
	emitter.energy = EmitterCurves.flash_energy(0.0)
	_rig.add_emitter(emitter)
	return emitter


func _end_light(emitter: LightEmitter) -> void:
	if emitter == null:
		return
	emitter.energy = 0.0
	if _rig != null and is_instance_valid(_rig):
		_rig.remove_emitter(emitter)
	emitter.anchor = null
	_spare.append(emitter)
