class_name BeamDraw
extends Node3D
## Draws every capital beam (M10-T12, D12.9): one multimesh per kind (pulsed, sustained), so all beams of a kind are one draw
## call however many fire. Each beam is two tubes along its line, a coloured glow and a whiter core (`beam.gdshader`), never
## thinner on screen than `MIN_PX`. A sustained beam is drawn as the last tick left it; a pulse lasts one tick in the game but
## is drawn for `PULSE_S`, fading. A child of `World` at its origin, its lines in World-local metres, moved with a rebase.
## Visual only: `CapitalBeams` hands it the lines each tick; `_process` writes the buffers.

const NODE_NAME: StringName = &"BeamDraw"
const SHADER: Shader = preload("res://assets/shaders/beam.gdshader")
## How long a pulse stays on screen, s (fading out).
const PULSE_S: float = 0.4
## The least width a beam is drawn on screen, px.
const MIN_PX: float = 2.0
## The core's width and brightness against the glow's.
const CORE_WIDTH: float = 0.3
const CORE_WHITE: float = 2.5
## Floats per instance: a 3x4 transform, then the colour.
const STRIDE: int = 16

## Instances drawn by the last frame, per kind (readouts for tests and the console).
var pulsed_shown: int = 0
var sustained_shown: int = 0

var _pulsed: MultiMeshInstance3D = null
var _sustained: MultiMeshInstance3D = null
# The sustained lines of the last tick and the pulses still shown: [from, to, colour, width, age_s].
var _lines: Array[Array] = []
var _pulses: Array[Array] = []
var _buffer := PackedFloat32Array()


static func of(world: Node) -> BeamDraw:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as BeamDraw


static func attach(world: Node) -> BeamDraw:
	var found: BeamDraw = of(world)
	if found != null or world == null or not is_instance_valid(world):
		return found
	var made := BeamDraw.new()
	world.add_child(made)
	return made


func _init() -> void:
	name = NODE_NAME
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	_pulsed = _batch(material, "Pulsed")
	_sustained = _batch(material, "Sustained")


func _ready() -> void:
	var world := get_parent() as WorldFrame
	if world != null and not world.rebased.is_connected(_on_rebased):
		world.rebased.connect(_on_rebased)


## The sustained beams on this tick, replacing the last tick's.
func set_lines(lines: Array[Array]) -> void:
	_lines = lines


## A pulse just fired from `from` to `to`, drawn for `PULSE_S`.
func add_pulse(from: Vector3, to: Vector3, color: Color, width_m: float) -> void:
	_pulses.append([from, to, color, width_m, 0.0])


## Instances of `kind` (`WeaponSpec.BEAM_PULSED` or `BEAM_SUSTAINED`) the last frame drew: two tubes a beam.
func shown(kind: int) -> int:
	return pulsed_shown if kind == WeaponSpec.BEAM_PULSED else sustained_shown


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var kept: Array[Array] = []
	for p: Array in _pulses:
		p[4] = float(p[4]) + delta
		if float(p[4]) < PULSE_S:
			kept.append(p)
	_pulses = kept
	pulsed_shown = _write(_pulsed, _pulses, camera, true)
	sustained_shown = _write(_sustained, _lines, camera, false)


# The lines `lines` into `batch`'s buffer, a glow and a core each; how many instances it drew.
func _write(batch: MultiMeshInstance3D, lines: Array[Array], camera: Camera3D, fading: bool) -> int:
	var count: int = lines.size() * 2
	var mm: MultiMesh = batch.multimesh
	if mm.instance_count < count:
		mm.instance_count = maxi(count, mm.instance_count * 2)
	if count == 0:
		mm.visible_instance_count = 0
		return 0
	_buffer.resize(mm.instance_count * STRIDE)
	var px_rad: float = _pixel_angle(camera)
	var eye: Vector3 = global_transform.affine_inverse() * camera.global_position if camera != null else Vector3.ZERO
	var k: int = 0
	for line: Array in lines:
		var from: Vector3 = line[0]
		var to: Vector3 = line[1]
		var color: Color = line[2]
		var fade: float = 1.0 - float(line[4]) / PULSE_S if fading else 1.0
		var near: float = eye.distance_to(Geometry3D.get_closest_point_to_segment(eye, from, to)) if camera != null else 0.0
		var width: float = maxf(float(line[3]), near * px_rad * MIN_PX)
		_put(k, from, to, width, Color(color.r, color.g, color.b, fade))
		var white := Color(color.r * 0.3 + CORE_WHITE, color.g * 0.3 + CORE_WHITE, color.b * 0.3 + CORE_WHITE, fade)
		_put(k + 1, from, to, width * CORE_WIDTH, white)
		k += 2
	mm.buffer = _buffer
	mm.visible_instance_count = count
	return count


# Instance `k`: a unit tube along `from` to `to`, `width` across, in `color`.
func _put(k: int, from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var along: Vector3 = to - from
	var length: float = along.length()
	var axis: Vector3 = along / length if length > 1e-4 else Vector3.UP
	var side: Vector3 = axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up: Vector3 = side.cross(axis)
	var bx: Vector3 = side * width
	var by: Vector3 = axis * maxf(length, 1e-3)
	var bz: Vector3 = up * width
	var o: Vector3 = (from + to) * 0.5
	var b: int = k * STRIDE
	_buffer[b] = bx.x
	_buffer[b + 1] = by.x
	_buffer[b + 2] = bz.x
	_buffer[b + 3] = o.x
	_buffer[b + 4] = bx.y
	_buffer[b + 5] = by.y
	_buffer[b + 6] = bz.y
	_buffer[b + 7] = o.y
	_buffer[b + 8] = bx.z
	_buffer[b + 9] = by.z
	_buffer[b + 10] = bz.z
	_buffer[b + 11] = o.z
	_buffer[b + 12] = color.r
	_buffer[b + 13] = color.g
	_buffer[b + 14] = color.b
	_buffer[b + 15] = color.a


# The angle one pixel subtends at the screen's centre, rad (0 with no camera).
func _pixel_angle(camera: Camera3D) -> float:
	if camera == null:
		return 0.0
	var height: float = maxf(float(get_viewport().get_visible_rect().size.y), 1.0)
	return deg_to_rad(camera.fov) / height


func _batch(material: ShaderMaterial, label: String) -> MultiMeshInstance3D:
	var tube := CylinderMesh.new()
	tube.height = 1.0
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.radial_segments = 8
	tube.rings = 0
	tube.cap_top = false
	tube.cap_bottom = false
	var batch := MultiMeshInstance3D.new()
	batch.name = label
	batch.material_override = material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	batch.custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)  # spread over the whole world: never culled as one
	batch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tube
	mm.visible_instance_count = 0
	batch.multimesh = mm
	add_child(batch)
	return batch


# A rebase moved the World by `offset`: the lines held move with it.
func _on_rebased(offset: Vector3) -> void:
	for line: Array in _lines:
		line[0] = (line[0] as Vector3) - offset
		line[1] = (line[1] as Vector3) - offset
	for p: Array in _pulses:
		p[0] = (p[0] as Vector3) - offset
		p[1] = (p[1] as Vector3) - offset
