class_name FarFlashes
extends MultiMeshInstance3D
## Far deaths as point flashes (M4-T23, architecture §17.14): every death past the reduced explosion's distance, near ship or
## tier row, is one instance of the world's one multimesh, so a far battle's deaths cost one draw call and no node or particle.
## A flash drifts with the dead ship's velocity, rises fast and fades over its life; it is as big as the fireball it replaces and
## as bright as the explosion's glow, and lasts longer for a bigger blast (`ExplosionLod`); `far_flash.gdshader` keeps it at
## least a pixel and dims it by the inverse square below that.
##
## A child of `World` (`attach`) at the World's origin, its flashes in World-local metres. It is shiftable, so a rebase moves
## the drawn flashes with everything else; it then goes back to the origin and moves its flashes instead. Visual only:
## `_process` ages and writes them, so a paused game freezes them.

const NODE_NAME: String = "FarFlashes"
const SHADER: Shader = preload("res://assets/shaders/far_flash.gdshader")
## Floats per instance: a 3x4 transform, then the custom data (light, radius).
const STRIDE: int = 16

var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _radii := PackedFloat64Array()
var _lives := PackedFloat64Array()
var _ages := PackedFloat64Array()
var _buffer := PackedFloat32Array()
## Flashes started so far (a readout).
var started: int = 0


## The world's flashes, or null before the first far death.
static func of(world: Node) -> FarFlashes:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as FarFlashes


## The world's flashes, made on first use.
static func attach(world: Node) -> FarFlashes:
	var found: FarFlashes = of(world)
	if found != null or world == null or not is_instance_valid(world):
		return found
	var made := FarFlashes.new()
	world.add_child(made)
	return made


func _init() -> void:
	name = NODE_NAME
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)  # spread over the whole world: never culled as one
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material_override = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.visible_instance_count = 0


func _ready() -> void:
	var world := get_parent() as WorldFrame
	if world != null and not world.rebased.is_connected(_on_rebased):
		world.rebased.connect(_on_rebased)


func _process(delta: float) -> void:
	advance(delta)


## Starts the flash of a hull of `radius_m` whose blast held `energy_j`, at `at` (World-local), drifting at `velocity`.
func add(at: Vector3, velocity: Vector3, radius_m: float, energy_j: float) -> void:
	_positions.append(at)
	_velocities.append(velocity)
	_radii.append(ExplosionLod.flash_radius_m(radius_m))
	_lives.append(ExplosionLod.flash_s(energy_j))
	_ages.append(0.0)
	started += 1
	_write()


## Flashes still shining.
func flash_count() -> int:
	return _positions.size()


## The global position of flash `index`.
func flash_position(index: int) -> Vector3:
	return global_transform * _positions[index]


## Moves every flash `delta` seconds on (drift, age) and drops the finished ones. Public for the tests.
func advance(delta: float) -> void:
	for i: int in range(_positions.size() - 1, -1, -1):
		_ages[i] += delta
		if _ages[i] >= _lives[i]:
			_positions.remove_at(i)
			_velocities.remove_at(i)
			_radii.remove_at(i)
			_lives.remove_at(i)
			_ages.remove_at(i)
			continue
		_positions[i] += _velocities[i] * delta
	_write()


func _write() -> void:
	var n: int = _positions.size()
	if n > multimesh.instance_count:
		multimesh.instance_count = maxi(n, multimesh.instance_count * 2)  # grows rarely, never shrinks
		_buffer.resize(multimesh.instance_count * STRIDE)
	for i: int in n:
		var b: int = i * STRIDE
		var at: Vector3 = _positions[i]
		var light: float = ExplosionLod.PEAK * ExplosionLod.envelope(maxf(_ages[i], ExplosionLod.RISE_S * 0.5), _lives[i])
		_buffer[b] = 1.0
		_buffer[b + 1] = 0.0
		_buffer[b + 2] = 0.0
		_buffer[b + 3] = at.x
		_buffer[b + 4] = 0.0
		_buffer[b + 5] = 1.0
		_buffer[b + 6] = 0.0
		_buffer[b + 7] = at.y
		_buffer[b + 8] = 0.0
		_buffer[b + 9] = 0.0
		_buffer[b + 10] = 1.0
		_buffer[b + 11] = at.z
		_buffer[b + 12] = ExplosionLod.COLOR.r * light
		_buffer[b + 13] = ExplosionLod.COLOR.g * light
		_buffer[b + 14] = ExplosionLod.COLOR.b * light
		_buffer[b + 15] = _radii[i]
	if multimesh.instance_count > 0:
		RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _buffer)
	multimesh.visible_instance_count = n


# The rebase moved this node with the world; back to the origin, with the flashes moved instead.
func _on_rebased(offset: Vector3) -> void:
	position += offset
	for i: int in _positions.size():
		_positions[i] -= offset
	_write()
