class_name ExplosionPool
extends Node3D
## Every explosion drawn in the world (architecture §15.7; M10-T11, roadmap L10): a death's, a mine's, a missile's warhead, a
## capital's break-up blasts. A fixed number of slots, all drawn by two multimeshes that share one mesh and one material each
## (the fireballs, the billboard flashes), so an explosion builds no node, mesh or material and a chain of a hundred costs two
## draw calls. Made entirely in code (no textures):
##
## - light: one `LightEmitter` a slot, made once. It competes through the `LightRig`'s `LightPicker` for a slot while it shines:
##   energy 0 -> 8 -> 0 over 0.25 s, range 4 x radius;
## - billboard flash: an additive quad, 0.15 s;
## - fireball: a sphere growing to 1.2 x radius over 0.8 s, `explosion_fireball.gdshader` (its age and noise seed per instance),
##   gone by 1.5 s, when the slot is free again;
## - pool bursts (`FxSpecs`) from the `FxPool`: sparks, glowing fragments and a gas shell, thrown once at the start.
##
## The reduced effect (M4-T23, `ExplosionLod`): no light and only the gas shell's puffs. With every slot busy the oldest
## explosion gives its slot to the new one (`stolen` counts them): the newest blast is the one the eye is on.
##
## A child of `World/Effects` at the World's origin (`attach`), its explosions in World-local metres, drifting with the velocity
## they were given and the frame's pull. The physics tick moves them (`step`), as it moves everything a rebase sees; `_process`
## ages and draws them a tick behind, between their last two places, as interpolated nodes are drawn (`advance`), so a paused
## game freezes them. A rebase moves the explosions, a velocity rebase changes their velocity.

const NODE_NAME: String = "ExplosionPool"
## Explosions alive at once.
const CAPACITY: int = 64
const LIGHT_S: float = 0.25
const LIGHT_PEAK_ENERGY: float = 8.0
const LIGHT_RANGE_PER_RADIUS: float = 4.0
const LIGHT_COLOR := Color(1.0, 0.78, 0.5)
const FLASH_S: float = 0.15
const FIREBALL_S: float = 1.5
const FIREBALL_GROW_S: float = 0.8
const FIREBALL_FINAL_SCALE: float = 1.2
const MIN_RADIUS_M: float = 0.5
const FIREBALL_SHADER: Shader = preload("res://src/combat/explosion_fireball.gdshader")
const FLASH_SHADER: Shader = preload("res://src/combat/explosion_flash.gdshader")
## Floats per instance: a 3x4 transform, then the custom data.
const STRIDE: int = 16

## Explosions started and slots taken from a live explosion, since the pool was made (readouts).
var started: int = 0
var stolen: int = 0
## Where the sparks, fragments and gas shell come from; none without it.
var fx: FxPool = null

var fireballs: MultiMeshInstance3D = null
var flashes: MultiMeshInstance3D = null

var _alive := PackedByteArray()
var _reduced := PackedByteArray()
var _tags := PackedInt32Array()
var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _radii := PackedFloat32Array()
var _ages := PackedFloat32Array()
var _seeds := PackedFloat32Array()
var _emitters: Array[LightEmitter] = []
var _lit := PackedByteArray()
var _pulls: Array[HeldPull] = []
var _fire_buffer := PackedFloat32Array()
var _flash_buffer := PackedFloat32Array()
var _live: int = 0
var _rig: LightRig = null


## The pool under `effects`, or null before the first explosion.
static func of(effects: Node) -> ExplosionPool:
	if effects == null or not is_instance_valid(effects):
		return null
	return effects.get_node_or_null(NodePath(NODE_NAME)) as ExplosionPool


## The pool under `effects`, made on first use.
static func attach(effects: Node) -> ExplosionPool:
	var found: ExplosionPool = of(effects)
	if found != null or effects == null or not is_instance_valid(effects):
		return found
	var made := ExplosionPool.new()
	effects.add_child(made)
	return made


## Energy of an explosion's light `age_s` after it appeared: a triangle, up to the peak at a third of the way and back to zero.
static func light_energy(age_s: float) -> float:
	var t: float = clampf(age_s / LIGHT_S, 0.0, 1.0)
	var rise: float = 1.0 / 3.0
	return LIGHT_PEAK_ENERGY * (t / rise if t < rise else (1.0 - t) / (1.0 - rise))


## The fireball's radius `age_s` after it appeared, for an explosion of `radius_m`.
static func fireball_radius(radius_m: float, age_s: float) -> float:
	var grow: float = 1.0 - pow(1.0 - clampf(age_s / FIREBALL_GROW_S, 0.0, 1.0), 2.0)
	return radius_m * FIREBALL_FINAL_SCALE * lerpf(0.15, 1.0, grow)


func _init() -> void:
	name = NODE_NAME
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_alive.resize(CAPACITY)
	_reduced.resize(CAPACITY)
	_tags.resize(CAPACITY)
	_positions.resize(CAPACITY)
	_velocities.resize(CAPACITY)
	_radii.resize(CAPACITY)
	_ages.resize(CAPACITY)
	_seeds.resize(CAPACITY)
	_lit.resize(CAPACITY)
	for i: int in CAPACITY:
		var emitter := LightEmitter.new("explosion", LightEmitter.PRIORITY_EXPLOSION, LIGHT_COLOR, 0.0, 1.0)
		_emitters.append(emitter)
		_pulls.append(HeldPull.new())
	_fire_buffer.resize(CAPACITY * STRIDE)
	_flash_buffer.resize(CAPACITY * STRIDE)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 28
	sphere.rings = 14
	var fire_material := ShaderMaterial.new()
	fire_material.shader = FIREBALL_SHADER
	fire_material.set_shader_parameter(&"duration", FIREBALL_S)
	fireballs = _batch("Fireballs", sphere, fire_material)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var flash_material := ShaderMaterial.new()
	flash_material.shader = FLASH_SHADER
	flashes = _batch("Flashes", quad, flash_material)


func _ready() -> void:
	var world: WorldFrame = WorldFrame.of(self)
	if world != null and not world.rebased.is_connected(_on_rebased):
		world.rebased.connect(_on_rebased)
		world.boosted.connect(_on_boosted)


func _exit_tree() -> void:
	for i: int in CAPACITY:
		_put_out(i)
	_rig = null


func _physics_process(delta: float) -> void:
	step(delta)


func _process(delta: float) -> void:
	advance(delta)


## Moves every explosion `delta` seconds on its drift and the frame's pull (the physics tick).
func step(delta: float) -> void:
	if _live == 0:
		return
	var world: WorldFrame = WorldFrame.of(self)
	for i: int in CAPACITY:
		if _alive[i] == 0:
			continue
		if world != null:
			_velocities[i] = _pulls[i].kick_at(world, _positions[i], _velocities[i], delta)
		_positions[i] += _velocities[i] * delta


## Starts an explosion of `radius_m` at `at` (World-local) drifting at `velocity`; `reduced` for the far effect (no light, the
## gas shell only), `tag` for the caller to count its own (mines). Returns its slot.
func spawn(radius_m: float, velocity: Vector3, at: Vector3, reduced: bool = false, tag: int = 0) -> int:
	var slot: int = _free_slot()
	if _alive[slot] != 0:
		stolen += 1
		_put_out(slot)
	else:
		_live += 1
	_alive[slot] = 1
	_reduced[slot] = 1 if reduced else 0
	_tags[slot] = tag
	_positions[slot] = at
	_velocities[slot] = velocity
	_radii[slot] = maxf(radius_m, MIN_RADIUS_M)
	_ages[slot] = 0.0
	_seeds[slot] = fposmod(float(started) * 0.618034, 1.0)
	_pulls[slot].reset()
	started += 1
	var emitter: LightEmitter = _emitters[slot]
	emitter.omni_range = LIGHT_RANGE_PER_RADIUS * _radii[slot]
	emitter.energy = 0.0
	emitter.position = _global(at)
	if not reduced and _light_rig() != null:
		_rig.add_emitter(emitter)
		_lit[slot] = 1
	if fx != null and is_instance_valid(fx):
		var start: Vector3 = _global(at)
		if not reduced:
			fx.burst(FxSpecs.EXPLOSION_SPARKS, start, Vector3.UP, velocity)
			fx.burst(FxSpecs.EXPLOSION_FRAGMENTS, start, Vector3.UP, velocity)
		fx.burst(FxSpecs.EXPLOSION_GAS, start, Vector3.UP, velocity)
	# The next `advance` draws it, so many explosions in one frame cost one upload.
	return slot


## Ages every explosion `delta` seconds, frees the finished slots and draws the rest. Public for tests.
func advance(delta: float) -> void:
	var behind_s: float = 0.0
	if is_inside_tree() and not Engine.is_in_physics_frame():
		behind_s = (1.0 - Engine.get_physics_interpolation_fraction()) / float(Engine.physics_ticks_per_second)
	var fires: int = 0
	var flashes_drawn: int = 0
	for i: int in CAPACITY:
		if _alive[i] == 0:
			continue
		var age: float = _ages[i] + delta
		_ages[i] = age
		if age >= FIREBALL_S:
			_put_out(i)
			_alive[i] = 0
			_live -= 1
			continue
		var at: Vector3 = _positions[i] - _velocities[i] * behind_s
		if _lit[i] != 0:
			var emitter: LightEmitter = _emitters[i]
			emitter.energy = light_energy(age)
			emitter.position = _global(at)
			if age >= LIGHT_S:
				_put_out(i)  # the light is over; the rest is meshes
		_write(_fire_buffer, fires, at, fireball_radius(_radii[i], age), age, _seeds[i])
		fires += 1
		if age < FLASH_S:
			var t: float = age / FLASH_S
			_write(_flash_buffer, flashes_drawn, at, _radii[i] * lerpf(1.6, 3.2, t), 1.0 - t, 0.0)
			flashes_drawn += 1
	_upload(fireballs, _fire_buffer, fires)
	_upload(flashes, _flash_buffer, flashes_drawn)


## Ends every explosion at once (a scene reset, tests).
func clear() -> void:
	for i: int in CAPACITY:
		_put_out(i)
		_alive[i] = 0
	_live = 0
	advance(0.0)


## Explosions alive now: every one, or those started with `tag`.
func live_count(tag: int = -1) -> int:
	if tag < 0:
		return _live
	var n: int = 0
	for i: int in CAPACITY:
		n += 1 if _alive[i] != 0 and _tags[i] == tag else 0
	return n


## The slots alive now, oldest first.
func live_slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in CAPACITY:
		if _alive[i] != 0:
			out.append(i)
	var ages: PackedFloat32Array = _ages
	var sorted: Array = Array(out)
	sorted.sort_custom(func(a: int, b: int) -> bool: return ages[a] > ages[b])
	return PackedInt32Array(sorted)


## The newest explosion's slot, or -1 with none alive.
func newest() -> int:
	var best: int = -1
	for i: int in CAPACITY:
		if _alive[i] != 0 and (best < 0 or _ages[i] < _ages[best]):
			best = i
	return best


func is_alive(slot: int) -> bool:
	return _alive[slot] != 0


## Slot `slot`'s explosion: its radius (the hull's), place (World-local), drift velocity, age, reduced or not, tag.
func radius_of(slot: int) -> float:
	return _radii[slot]


func position_of(slot: int) -> Vector3:
	return _positions[slot]


func velocity_of(slot: int) -> Vector3:
	return _velocities[slot]


func age_of(slot: int) -> float:
	return _ages[slot]


func is_reduced(slot: int) -> bool:
	return _reduced[slot] != 0


func tag_of(slot: int) -> int:
	return _tags[slot]


## Whether slot `slot`'s light competes for a slot in the light rig now, and its emitter.
func is_lit(slot: int) -> bool:
	return _lit[slot] != 0


func emitter_of(slot: int) -> LightEmitter:
	return _emitters[slot]


## Fireballs and flashes drawn by the last `advance`.
func drawn() -> Vector2i:
	return Vector2i(fireballs.multimesh.visible_instance_count, flashes.multimesh.visible_instance_count)


## Instance `index` as the last `advance` drew it, a fireball (`fire`) or a flash: `{at, size, a, b}` (its custom data: a
## fireball's age and seed, a flash's strength). Read from the pool's own buffer (tests; the headless server keeps none).
func drawn_instance(fire: bool, index: int) -> Dictionary:
	var buffer: PackedFloat32Array = _fire_buffer if fire else _flash_buffer
	var o: int = index * STRIDE
	return {"at": Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11]), "size": buffer[o], "a": buffer[o + 12], "b": buffer[o + 13]}


# A free slot, else the oldest explosion's.
func _free_slot() -> int:
	var oldest: int = 0
	for i: int in CAPACITY:
		if _alive[i] == 0:
			return i
		if _ages[i] > _ages[oldest]:
			oldest = i
	return oldest


# Slot `slot`'s light leaves the rig.
func _put_out(slot: int) -> void:
	if _lit[slot] == 0:
		return
	_lit[slot] = 0
	_emitters[slot].energy = 0.0
	if _rig != null and is_instance_valid(_rig):
		_rig.remove_emitter(_emitters[slot])


func _light_rig() -> LightRig:
	if _rig == null or not is_instance_valid(_rig):
		_rig = LightRig.of(self)
	return _rig


func _global(local: Vector3) -> Vector3:
	return global_transform * local if is_inside_tree() else local


func _batch(node_name: String, mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)  # spread over the whole world: never culled as one
	node.material_override = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	node.multimesh = mm
	add_child(node)
	return node


# One instance: a uniform scale `size` at `at`, custom data (a, b).
static func _write(buffer: PackedFloat32Array, index: int, at: Vector3, size: float, a: float, b: float) -> void:
	var o: int = index * STRIDE
	buffer[o] = size
	buffer[o + 1] = 0.0
	buffer[o + 2] = 0.0
	buffer[o + 3] = at.x
	buffer[o + 4] = 0.0
	buffer[o + 5] = size
	buffer[o + 6] = 0.0
	buffer[o + 7] = at.y
	buffer[o + 8] = 0.0
	buffer[o + 9] = 0.0
	buffer[o + 10] = size
	buffer[o + 11] = at.z
	buffer[o + 12] = a
	buffer[o + 13] = b
	buffer[o + 14] = 0.0
	buffer[o + 15] = 0.0


static func _upload(node: MultiMeshInstance3D, buffer: PackedFloat32Array, count: int) -> void:
	if count == 0 and node.multimesh.visible_instance_count == 0:
		return  # nothing drawn before or now: no upload
	if count > 0:
		MultiMeshUpload.set_buffer(node.multimesh, buffer)
	node.multimesh.visible_instance_count = count


# A velocity rebase: every explosion keeps its universe velocity.
func _on_boosted(dv: Vector3) -> void:
	for i: int in CAPACITY:
		if _alive[i] != 0:
			_velocities[i] -= dv
			_pulls[i].reset()


# A rebase moves the world's objects by `-offset`: the explosions go with them.
func _on_rebased(offset: Vector3) -> void:
	for i: int in CAPACITY:
		if _alive[i] != 0:
			_positions[i] -= offset
			_emitters[i].position = _global(_positions[i])
