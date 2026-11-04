class_name RunningLights
extends MultiMeshInstance3D
## A ship's running lights in the scene (architecture §7.3, M3-T27): three markers built once. A thin adapter over `NavLights`. It holds
## no `Light3D` (the scene's 8 hold) and does nothing per frame: it changes only when the state or a setting does. The markers ride
## with the interpolated hull as children of the ship, hide with it when it is parked or destroyed, and hulls hide them by their
## depth. Radar and AI never read any of this.
##
## Two ways to draw the markers, chosen before `setup` by `instanced`: a `MeshInstance3D` each (the player's ship), or, on AI ships
## (M4-T11, §17.10), three instances of this node's own multimesh with the colour in each instance's custom data, one draw call
## and no node. Either way the same quad, shader and footprint.

const MARKER_SHADER: Shader = preload("res://assets/shaders/running_light_marker.gdshader")

# Every ship shares one quad and one material per colour, so markers batch; instanced ships share one material.
static var _quad: QuadMesh = null
static var _materials: Dictionary[Color, ShaderMaterial] = {}
static var _instanced_material: ShaderMaterial = null

## Draw the markers as instances of this node's multimesh instead of nodes (M4-T11, AI ships). Set before `setup`.
var instanced: bool = false

var _ship: Ship = null
var _markers: Array[MeshInstance3D] = []
# Instanced: each marker's place in the ship's frame and its colour.
var _positions: PackedVector3Array = PackedVector3Array()
var _tints: PackedColorArray = PackedColorArray()

static var _warned_no_lights: bool = false


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Places the markers and hands over the own lights: the first call builds the markers, a later one (a rebuilt ship) moves them.
func setup(ship: Ship) -> void:
	_ship = ship
	var wanted: Array[Dictionary] = NavLights.markers(ship.get_hardpoints().nav_lights)
	if wanted.is_empty() and ship.get_hardpoints().valid and not _warned_no_lights:
		_warned_no_lights = true  # stale generated assets would otherwise just look like a ship with its lights off
		push_warning("RunningLights: %s lists no nav_lights (run scripts/gen_assets.sh)" % ship.spec.asset_id)
	if instanced:
		_setup_instances(wanted)
	else:
		for i: int in wanted.size():
			if i == _markers.size():
				_markers.append(_new_marker())
			_markers[i].name = String(wanted[i]["name"])
			_markers[i].position = wanted[i]["position"]
			_markers[i].material_override = _material_for(wanted[i]["color"])
	apply()


## The marker nodes: port, starboard, top (none when instanced).
func markers() -> Array[MeshInstance3D]:
	return _markers


## How many markers the ship has (3, or 0 when its hull names no lights).
func marker_count() -> int:
	return _positions.size() if instanced else _markers.size()


## Where marker `index` sits, in the ship's frame (port, starboard, top).
func marker_position(index: int) -> Vector3:
	return _positions[index] if instanced else _markers[index].position


## The HDR colour of marker `index`.
func marker_tint(index: int) -> Color:
	if instanced:
		return _tints[index]
	var tint: Vector3 = (_markers[index].material_override as ShaderMaterial).get_shader_parameter(&"tint")
	return Color(tint.x, tint.y, tint.z)


## Whether the markers are drawn now: the lights on, and the ship in play and near enough to be more than a dot.
func markers_shown() -> bool:
	if not is_visible_in_tree() or marker_count() == 0:
		return false
	if instanced:
		return multimesh != null and multimesh.visible_instance_count != 0
	return _markers[0].visible


## Brings the markers to the ship's state.
func apply() -> void:
	if _ship == null:
		return
	var lit: bool = _ship.running_lights
	for marker: MeshInstance3D in _markers:
		marker.visible = lit
	if instanced and multimesh != null:
		multimesh.visible_instance_count = -1 if lit else 0


func _enter_tree() -> void:
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


func _on_setting_changed(key: StringName, value: Variant) -> void:
	match key:
		&"running_light_min_px":
			for material: ShaderMaterial in _materials.values():
				material.set_shader_parameter(&"min_radius_px", float(value))
			if _instanced_material != null:
				_instanced_material.set_shader_parameter(&"min_radius_px", float(value))


# One instance per marker: its place, and its colour in the custom data the shader reads.
func _setup_instances(wanted: Array[Dictionary]) -> void:
	_positions.clear()
	_tints.clear()
	for entry: Dictionary in wanted:
		_positions.append(entry["position"])
		_tints.append(entry["color"])
	if multimesh == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _shared_quad()
		multimesh = mm
		material_override = _instanced_marker_material()
	multimesh.instance_count = _positions.size()
	for i: int in _positions.size():
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, _positions[i]))
		var tint: Color = _tints[i]
		multimesh.set_instance_custom_data(i, Color(tint.r, tint.g, tint.b, 1.0))


func _new_marker() -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.mesh = _shared_quad()
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	return marker


static func _shared_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE  # the shader scales it to the marker's radius
	return _quad


static func _material_for(color: Color) -> ShaderMaterial:
	if not _materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = MARKER_SHADER
		material.set_shader_parameter(&"tint", Vector3(color.r, color.g, color.b))
		material.set_shader_parameter(&"min_radius_px", float(Settings.get_value(&"running_light_min_px")))
		_materials[color] = material
	return _materials[color]


static func _instanced_marker_material() -> ShaderMaterial:
	if _instanced_material == null:
		_instanced_material = ShaderMaterial.new()
		_instanced_material.shader = MARKER_SHADER
		_instanced_material.set_shader_parameter(&"use_instance_tint", true)
		_instanced_material.set_shader_parameter(&"min_radius_px", float(Settings.get_value(&"running_light_min_px")))
	return _instanced_material
