class_name RunningLights
extends Node3D
## A ship's running lights in the scene (architecture §7.3, M3-T27): three markers built once, and the ship's own lights handed to its
## splat nodes. A thin adapter over `NavLights`. It holds no `Light3D` (the scene's 8 hold) and does nothing per frame: it changes only
## when the state or a setting does. The markers ride with the interpolated hull as children of the ship, hide with it when it is
## parked or destroyed, and the hull depth proxy hides them behind hulls. Radar and AI never read any of this.

const MARKER_SHADER: Shader = preload("res://assets/shaders/running_light_marker.gdshader")

# Every ship shares one quad and one material per colour, so markers batch.
static var _quad: QuadMesh = null
static var _materials: Dictionary[Color, ShaderMaterial] = {}

var _ship: Ship = null
var _markers: Array[MeshInstance3D] = []


## Places the markers and hands over the own lights: the first call builds the markers, a later one (a rebuilt ship) moves them.
func setup(ship: Ship) -> void:
	_ship = ship
	var wanted: Array[Dictionary] = NavLights.markers(ship.get_hardpoints().nav_lights)
	for i: int in wanted.size():
		if i == _markers.size():
			_markers.append(_new_marker())
		_markers[i].name = String(wanted[i]["name"])
		_markers[i].position = wanted[i]["position"]
		_markers[i].material_override = _material_for(wanted[i]["color"])
	apply()


## The marker nodes: port, starboard, top.
func markers() -> Array[MeshInstance3D]:
	return _markers


## Brings the markers and the splat nodes' own lights to the ship's state and the settings.
func apply() -> void:
	if _ship == null:
		return
	var lit: bool = _ship.running_lights
	for marker: MeshInstance3D in _markers:
		marker.visible = lit
	var lights := PackedFloat32Array()
	if bool(Settings.get_value(&"own_lights")):
		lights = NavLights.own_lights(_ship.get_hardpoints().nav_lights, lit, float(Settings.get_value(&"top_lamp_energy")),
				float(Settings.get_value(&"cabin_glow_level")), float(Settings.get_value(&"cabin_glow_view_m")),
				GaussianSplatNode.get_model_orientation_correction())
	for node: GaussianSplatNode in _ship.splat_nodes():
		node.set_own_lights(lights)


func _enter_tree() -> void:
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


func _on_setting_changed(key: StringName, value: Variant) -> void:
	match key:
		&"own_lights", &"top_lamp_energy", &"cabin_glow_level", &"cabin_glow_view_m":
			apply()
		&"running_light_min_px":
			for material: ShaderMaterial in _materials.values():
				material.set_shader_parameter(&"min_radius_px", float(value))


func _new_marker() -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE  # the shader scales it to the marker's radius
	var marker := MeshInstance3D.new()
	marker.mesh = _quad
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	return marker


static func _material_for(color: Color) -> ShaderMaterial:
	if not _materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = MARKER_SHADER
		material.set_shader_parameter(&"tint", Vector3(color.r, color.g, color.b))
		material.set_shader_parameter(&"min_radius_px", float(Settings.get_value(&"running_light_min_px")))
		_materials[color] = material
	return _materials[color]
