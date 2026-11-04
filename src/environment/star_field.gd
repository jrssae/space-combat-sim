class_name StarField
extends MultiMeshInstance3D
## The stars of the sky as points (architecture §17.19, M4-T30c): one multimesh instance per star of `sky_default_stars.f32`,
## drawn by `star_point.gdshader` in one draw call. Each instance's basis Z is its star's direction and its origin is the node's,
## so the shader reads only rotations: the camera turns inside a fixed sky and no camera offset can shift a star. `SkyFollower`
## keeps the node on the camera so its box is never culled. Unlit: stars are emitters.

const SHADER_PATH: String = "res://assets/shaders/star_point.gdshader"
## Floats per star in the file: the direction, the colour tint, the brightness.
const RECORD_FLOATS: int = 7
## Half the size of the box round the camera that the renderer culls the field by.
const CULL_HALF_SIZE_M: float = 100.0
## Floats per instance in a multimesh buffer with a 3D transform and custom data.
const _BUFFER_STRIDE: int = 16

var _count: int = 0
## The buffer last given to the multimesh, kept so the stars can be read back where the renderer keeps none (headless).
var _buffer := PackedFloat32Array()


func _init() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The box round the camera that holds every star, so the field is never culled.
	custom_aabb = AABB(-Vector3.ONE * CULL_HALF_SIZE_M, Vector3.ONE * 2.0 * CULL_HALF_SIZE_M)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = QuadMesh.new()
	multimesh = mesh
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	# Drawn first among the transparent surfaces: the sky is behind everything.
	material.render_priority = Material.RENDER_PRIORITY_MIN
	material_override = material


## Loads `count` stars from the generator's file and draws each as a disc of `radius_mrad` with a `floor_px` floor. On a missing
## or short file it warns, draws nothing and returns false.
func load_file(path: String, count: int, radius_mrad: float, floor_px: float) -> bool:
	_set_stars(PackedFloat32Array(), 0)
	if not FileAccess.file_exists(path):
		push_warning("StarField: %s is missing (run scripts/gen_assets.sh); no stars" % path)
		return false
	var floats: PackedFloat32Array = FileAccess.get_file_as_bytes(path).to_float32_array()
	if count < 1 or floats.size() != count * RECORD_FLOATS:
		push_warning("StarField: %s holds %d floats, not %d records of %d; no stars" % [path, floats.size(), count, RECORD_FLOATS])
		return false
	var material: ShaderMaterial = material_override as ShaderMaterial
	material.set_shader_parameter(&"radius_rad", radius_mrad * 0.001)
	material.set_shader_parameter(&"min_radius_px", floor_px)
	_set_stars(floats, count)
	return true


## Draws no stars, for a sky with no generated asset.
func clear() -> void:
	_set_stars(PackedFloat32Array(), 0)


func star_count() -> int:
	return _count


## The unit direction of star `index`, in the world frame.
func direction_of(index: int) -> Vector3:
	var b: int = index * _BUFFER_STRIDE
	return Vector3(_buffer[b + 2], _buffer[b + 6], _buffer[b + 10])


## The linear light of star `index`: its colour times its brightness.
func light_of(index: int) -> Color:
	var b: int = index * _BUFFER_STRIDE
	return Color(_buffer[b + 12], _buffer[b + 13], _buffer[b + 14], _buffer[b + 15])


func _set_stars(records: PackedFloat32Array, count: int) -> void:
	var buffer := PackedFloat32Array()
	buffer.resize(count * _BUFFER_STRIDE)
	for i: int in count:
		var r: int = i * RECORD_FLOATS
		var b: int = i * _BUFFER_STRIDE
		var brightness: float = records[r + 6]
		# Rows of the 3x4 transform: an orthonormal basis whose Z is the star's direction, the origin at the node.
		var z := Vector3(records[r], records[r + 1], records[r + 2])
		var helper: Vector3 = Vector3.RIGHT if absf(z.y) > 0.95 else Vector3.UP
		var x: Vector3 = helper.cross(z).normalized()
		var y: Vector3 = z.cross(x)
		buffer[b] = x.x
		buffer[b + 1] = y.x
		buffer[b + 2] = z.x
		buffer[b + 4] = x.y
		buffer[b + 5] = y.y
		buffer[b + 6] = z.y
		buffer[b + 8] = x.z
		buffer[b + 9] = y.z
		buffer[b + 10] = z.z
		buffer[b + 12] = records[r + 3] * brightness
		buffer[b + 13] = records[r + 4] * brightness
		buffer[b + 14] = records[r + 5] * brightness
		buffer[b + 15] = 1.0
	multimesh.instance_count = count
	if count > 0:
		multimesh.buffer = buffer
	_buffer = buffer
	_count = count
