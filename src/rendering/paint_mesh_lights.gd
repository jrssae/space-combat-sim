class_name PaintMeshLights
extends Node
## Gives every painted mesh (M4-T27, `MeshAssets`) the light the splats get: the light rig's 8 lights packed as GDGS packs them
## (`GaussianLightRig`'s raster uniforms) and the relight settings, once a frame, so a mesh ship and a splat ship side by side are
## lit alike. It reads the rig's own slots, so it never walks the scene for lights.

const MAX_LIGHTS: int = 8

var _vectors := PackedVector3Array()
var _colors := PackedColorArray()
var _params := PackedColorArray()
var _spots := PackedVector3Array()


func _init() -> void:
	for array: Variant in [_vectors, _colors, _params, _spots]:
		array.resize(MAX_LIGHTS)


func _process(_delta: float) -> void:
	if MeshAssets.materials.is_empty():
		return
	var count: int = pack(SplatLightRig.of(self))
	var relight_on: bool = bool(Settings.get_value(&"splat_relight"))
	var unlit: float = float(Settings.get_value(&"relight_unlit_level"))
	var ambient: float = float(Settings.get_value(&"relight_ambient"))
	var gain: float = float(Settings.get_value(&"relight_light_gain"))
	for material: ShaderMaterial in MeshAssets.materials:
		material.set_shader_parameter(&"light_count", count)
		material.set_shader_parameter(&"light_vectors", _vectors)
		material.set_shader_parameter(&"light_colors", _colors)
		material.set_shader_parameter(&"light_params", _params)
		material.set_shader_parameter(&"light_spot_directions", _spots)
		material.set_shader_parameter(&"relight_on", relight_on)
		material.set_shader_parameter(&"relight_unlit_level", unlit)
		material.set_shader_parameter(&"relight_ambient", ambient)
		material.set_shader_parameter(&"relight_light_gain", gain)


## Packs the rig's shining lights into the arrays (GDGS's layout) and returns how many; 0 without a rig.
func pack(rig: SplatLightRig) -> int:
	if rig == null:
		return 0
	var count: int = 0
	for light: Light3D in rig.slots():
		if count >= MAX_LIGHTS:
			break
		if light == null or not light.is_visible_in_tree() or is_zero_approx(light.light_energy):
			continue
		var to_light: Vector3 = light.global_transform.basis.z.normalized()
		var energy: float = -light.light_energy if light.light_negative else light.light_energy
		var tint: Color = light.light_color
		var type: int = 0
		var vector: Vector3 = to_light
		var range_value: float = 0.0
		var decay: float = 0.0
		if light is OmniLight3D:
			type = 1
			vector = light.global_position
			range_value = (light as OmniLight3D).omni_range
			decay = (light as OmniLight3D).omni_attenuation
		_vectors[count] = vector
		_colors[count] = Color(tint.r * energy, tint.g * energy, tint.b * energy, type)
		_params[count] = Color(1.0 / maxf(range_value, 0.001), decay, -1.0, 1.0)
		_spots[count] = -to_light
		count += 1
	return count
