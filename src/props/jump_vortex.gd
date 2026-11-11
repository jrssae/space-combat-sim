class_name JumpVortex
extends Node3D
## A jumpgate's vortex (M6-T14, D69): meshes and a shader only (D22), built once with the gate and shown while an opening runs.
## Blue for an arrival, orange to golden yellow for a departure; the timing is `VortexTiming`'s. The age runs on physics ticks
## from `delta` (a pause freezes it); the visuals follow it each rendered frame. A child of the gate, so a rebase moves it.
##
## The funnel opens toward the gate's back (+Z): departures fly into it along +Z, arrivals come out of it along -Z.

enum Direction { ARRIVAL, DEPARTURE }
const DIRECTION_NAMES: Array[StringName] = [&"arrival", &"departure"]

const SHADER: Shader = preload("res://src/props/jump_vortex.gdshader")
const GLOW_MATERIAL: StandardMaterial3D = preload("res://assets/materials/thruster_glow.tres")
## Fallback colours (linear) when the hardpoints say nothing: the generator's values.
const DEFAULT_COLOURS: Dictionary = {
	&"arrival": [Color(0.045, 0.23, 0.9), Color(0.38, 0.65, 1.0)],
	&"departure": [Color(0.95, 0.42, 0.06), Color(1.0, 0.82, 0.38)],
}
const DEFAULT_FLASH: Color = Color(1.0, 0.62, 0.86)
## The funnel's depth behind the gate's plane, as a share of its radius: a deep whirlpool seen from an angle.
const DEPTH_FRACTION: float = 0.9
const SEGMENTS: int = 64
const RINGS: int = 24
## The flash at its peak and a tip glow, as a share of the vortex radius.
const FLASH_SIZE: float = 0.9
const TIP_SIZE: float = 0.18
const LIGHT_PEAK_ENERGY: float = 12.0

var radius_m: float = 720.0
## The opening flash's colour (the gate's hardpoints), also the screen's flash in the player's jump.
var flash_colour: Color = DEFAULT_FLASH
var direction: Direction = Direction.ARRIVAL
## Sim seconds since this opening began; meaningless while closed.
var age_s: float = 0.0
## Openings so far (tests, console).
var openings: int = 0
var timing: VortexTiming = VortexTiming.new()

var funnel: MeshInstance3D = null
var flash_quad: MeshInstance3D = null
var tips: Array[MeshInstance3D] = []
var emitter: LightEmitter = null

var _active: bool = false
var _material: ShaderMaterial = null
var _colours: Dictionary = DEFAULT_COLOURS.duplicate()
var _rig: LightRig = null

static var _funnel_mesh: ArrayMesh = null


## Builds the meshes for a vortex of `p_radius_m` with the gate's `vortex` hardpoints entry (colours, flash) and its inner tips
## (`tip_positions`, gate-local). Call once, before it enters the tree.
func setup(p_radius_m: float, vortex_data: Dictionary, tip_positions: Array[Vector3]) -> void:
	radius_m = maxf(p_radius_m, 1.0)
	var colours: Variant = vortex_data.get("colours")
	if colours is Dictionary:
		for key: StringName in DEFAULT_COLOURS:
			var entry: Variant = (colours as Dictionary).get(String(key))
			if entry is Dictionary:
				_colours[key] = [_colour((entry as Dictionary).get("colour"), DEFAULT_COLOURS[key][0]),
						_colour((entry as Dictionary).get("highlight"), DEFAULT_COLOURS[key][1])]
	flash_colour = _colour(vortex_data.get("flash"), DEFAULT_FLASH)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	funnel = MeshInstance3D.new()
	funnel.name = "Funnel"
	funnel.mesh = funnel_mesh()
	funnel.material_override = _material
	funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(funnel)
	flash_quad = _billboard("Flash", flash_colour * 3.0)
	for i: int in tip_positions.size():
		var tip: MeshInstance3D = _billboard("Tip%d" % i, flash_colour * 2.5)
		tip.position = tip_positions[i]
		tips.append(tip)
	emitter = LightEmitter.new("jump_vortex", LightEmitter.PRIORITY_EXPLOSION, Color.WHITE, 0.0, radius_m * 6.0)
	emitter.anchor = self
	_hide_all()


func _exit_tree() -> void:
	_leave_rig()


## Starts an opening in `p_direction` that stays open `hold_s` once grown. An opening already running the same way is kept open
## that much longer instead; one running the other way refuses (one direction per opening). Returns whether it is opening.
func open(p_direction: Direction, hold_s: float = VortexTiming.DEFAULT_HOLD_S) -> bool:
	if _active and direction != p_direction:
		return false
	if _active and timing.phase(age_s) != VortexTiming.Phase.CLOSING:
		timing.extend(age_s, hold_s)
		return true
	if _active:
		return false  # closing: it must finish before it opens again
	direction = p_direction
	timing = VortexTiming.new(hold_s)
	age_s = 0.0
	_active = true
	openings += 1
	var pair: Array = _colours[DIRECTION_NAMES[direction]]
	_material.set_shader_parameter(&"colour", pair[0])
	_material.set_shader_parameter(&"highlight", pair[1])
	_material.set_shader_parameter(&"spin", 1.0 if direction == Direction.ARRIVAL else -1.0)
	emitter.color = (pair[1] as Color)
	_rig = LightRig.of(self)
	if _rig != null:
		_rig.add_emitter(emitter)
	update_visuals()
	return true


## Starts the close now, or once the funnel is fully open.
func close() -> void:
	if _active:
		timing.close_now(age_s)


## Keeps the current opening open at least `hold_s` more.
func extend(hold_s: float) -> void:
	if _active:
		timing.extend(age_s, hold_s)


func is_active() -> bool:
	return _active


## Ships of `p_direction` may pass now.
func is_open_for(p_direction: Direction) -> bool:
	return _active and direction == p_direction and timing.is_open(age_s)


## A ship going `p_direction` may go through now: the funnel at least half grown (a ship a little early still makes it).
func is_passable_for(p_direction: Direction) -> bool:
	return _active and direction == p_direction and timing.radius_scale(age_s) >= 0.5


## Seconds until it is open for `p_direction`: 0 when it is, INF when it is closed or opening the other way.
func open_in_s(p_direction: Direction) -> float:
	if not _active or direction != p_direction or timing.phase(age_s) >= VortexTiming.Phase.CLOSING:
		return INF
	return timing.open_in_s(age_s)


func phase_name() -> String:
	return timing.phase_name(age_s) if _active else "closed"


func direction_name() -> StringName:
	return DIRECTION_NAMES[direction] if _active else &"none"


func _physics_process(delta: float) -> void:
	advance(delta)


func _process(_delta: float) -> void:
	update_visuals()


## Moves the opening `delta` sim seconds on; it hides itself when done. Public for tests.
func advance(delta: float) -> void:
	if not _active:
		return
	age_s += delta
	if timing.is_done(age_s):
		_active = false
		_leave_rig()
		_hide_all()


## Puts the meshes and the light on the opening's current age.
func update_visuals() -> void:
	if not _active:
		return
	var size: float = timing.radius_scale(age_s)
	funnel.visible = size > 0.0
	funnel.scale = Vector3(radius_m, radius_m, radius_m * DEPTH_FRACTION) * maxf(size, 1e-3)
	_material.set_shader_parameter(&"level", clampf(size * 1.4, 0.0, 1.0))
	_material.set_shader_parameter(&"swirl_time", SimClock.now())
	var flash_level: float = timing.flash(age_s)
	flash_quad.visible = flash_level > 0.0
	flash_quad.scale = Vector3.ONE * radius_m * 2.0 * FLASH_SIZE * maxf(flash_level, 1e-3)
	var tip_level: float = timing.tip_glow(age_s)
	for tip: MeshInstance3D in tips:
		tip.visible = tip_level > 0.0
		tip.scale = Vector3.ONE * radius_m * 2.0 * TIP_SIZE * maxf(tip_level, 1e-3)
	emitter.energy = LIGHT_PEAK_ENERGY * maxf(flash_level, size * 0.5)


## A funnel of unit radius from the rim (z 0) to the eye (z 1), UV.x round it and UV.y rim to eye; shared by every vortex.
static func funnel_mesh() -> ArrayMesh:
	if _funnel_mesh != null:
		return _funnel_mesh
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring: int in RINGS + 1:
		var v: float = float(ring) / float(RINGS)
		var r: float = lerpf(1.0, 0.04, pow(v, 0.55))
		var z: float = pow(v, 1.6)
		for seg: int in SEGMENTS + 1:
			var u: float = float(seg) / float(SEGMENTS)
			vertices.append(Vector3(cos(u * TAU) * r, sin(u * TAU) * r, z))
			uvs.append(Vector2(u, v))
	var row: int = SEGMENTS + 1
	for ring: int in RINGS:
		for seg: int in SEGMENTS:
			var a: int = ring * row + seg
			indices.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_funnel_mesh = ArrayMesh.new()
	_funnel_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _funnel_mesh


func _hide_all() -> void:
	if funnel != null:
		funnel.visible = false
	if flash_quad != null:
		flash_quad.visible = false
	for tip: MeshInstance3D in tips:
		tip.visible = false
	if emitter != null:
		emitter.energy = 0.0


func _leave_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.remove_emitter(emitter)
	_rig = null


func _billboard(node_name: String, color: Color) -> MeshInstance3D:
	var glow := GLOW_MATERIAL.duplicate() as StandardMaterial3D
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.billboard_keep_scale = true  # sized by the node's scale, hundreds of metres across
	glow.albedo_color = color
	glow.emission = color
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = glow
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = quad
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	return mesh


static func _colour(raw: Variant, fallback: Color) -> Color:
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback
