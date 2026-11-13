class_name JumpVortex
extends Node3D
## A jump vortex (M6-T14, T19, D69): the funnel of light a ship comes out of or goes into hyperspace through, meshes and shaders
## only (D22). Stand-alone: a jumpgate opens one fitted to its arms, raiders arriving at open points open one sized for the ship
## (`JumpPointPool`), and a capital ship can open its own the same way (M12).
##
## The node's origin is the mouth's centre and its -Z the way ships come out (the funnel recedes along +Z); `fit` gives the mouth's
## radius and the depth. An opening runs on `VortexTiming`: the opener's lead-in (a gate's arm sequence; none for a ship-made
## point), the flash at the jump point's centre (the funnel's base), the funnel unfolding from that point forward to the rim of
## its mouth, open, then folding back to the centre and a flash there as it goes. Blue for an arrival, turning counter-clockwise seen from in front, its patches spiralling
## out from the throat; orange to golden yellow for a departure, turning clockwise, its patches spiralling in (`VortexSwirl`).
## A gate's mouth is an ellipse (`VortexFit`); the funnel keeps that section down to its throat. The age runs on physics ticks from `delta` (a pause freezes it); the visuals follow it
## each rendered frame. In `world_shiftable` when it stands alone, so a rebase moves it; a gate's moves with the gate.
##
## Cheap at a hundred (M6-T20): every vortex of one set of colours shares its materials (one per direction, one flash) and the
## meshes; its own values (growth, the base's view, the swirl's time, the detail) are instance uniforms. The detail follows the
## mouth's size on screen (`VortexLod`), and a pool may cap which of its points carry a light (`lit`) or a sound (`muted`).
## Nothing processes while it is closed; a pool can draw its points itself (`driven`).

enum Direction { ARRIVAL, DEPARTURE }
const DIRECTION_NAMES: Array[StringName] = [&"arrival", &"departure"]

const SCENE_PATH: String = "res://src/props/jump_vortex.tscn"
const FUNNEL_SHADER: Shader = preload("res://src/props/jump_vortex.gdshader")
const GLOW_SHADER: Shader = preload("res://src/props/jump_glow.gdshader")
## Colours (linear) when the opener gives none: the gate generator's values.
const DEFAULT_COLOURS: Dictionary = {
	&"arrival": [Color(0.06, 0.38, 0.85), Color(0.36, 0.75, 1.0)],
	&"departure": [Color(0.95, 0.42, 0.06), Color(1.0, 0.82, 0.38)],
}
const DEFAULT_FLASH: Color = Color(1.0, 0.62, 0.86)
const SEGMENTS: int = 96
const RINGS: int = 40
## The coarse funnel a point a few pixels across draws (`VortexLod.coarse_mesh`).
const COARSE_SEGMENTS: int = 24
const COARSE_RINGS: int = 10
## The flash at its peak, as a share of the mouth's radius.
const FLASH_SIZE: float = 1.1
const LIGHT_PEAK_ENERGY: float = 12.0
## The funnel's overall brightness by direction: the blue arrival follows the dim show still (`jumpgate.png`), the orange
## departure the brighter video frames.
const BRIGHTNESS: Dictionary = {&"arrival": 0.5, &"departure": 1.2}
## An arrival's sound (the generated `jump_in`); silent without it.
const SOUND_PATH: String = "res://assets/generated/sfx_world/jump_in.wav"
const SOUND_DB: float = 2.0

## The mouth's semi-axes and the depth.
var fit: VortexFit = VortexFit.new()
## The opening flash's colour, also the screen's flash in the player's jump.
var flash_colour: Color = DEFAULT_FLASH
var direction: Direction = Direction.ARRIVAL
## Sim seconds since this opening began; meaningless while closed.
var age_s: float = 0.0
## Openings so far (tests, console).
var openings: int = 0
var timing: VortexTiming = VortexTiming.new()
## Whether its light enters the rig while it is open (a pool lights only its nearest few points).
var lit: bool = true:
	set(value):
		if value == lit:
			return
		lit = value
		if _active and lit:
			_join_rig()
		elif _active:
			_leave_rig()
## No arrival sound on this opening (a pool keeps a wave of points from all sounding at once).
var muted: bool = false
## Drawn by its pool (`update_visuals_for`), not by its own `_process`.
var driven: bool = false:
	set(value):
		driven = value
		_sync_processing()
## The mouth's radius on screen at the last draw, px, and the detail level it gave (`VortexLod.level`).
var radius_px: float = VortexLod.MAX_PX
var lod_level: int = 0
## Ships flying its funnel now (M6-T22, `VortexTransits`): it is kept open while any is, and a pool does not take it back.
var passing: int = 0
## The node whose frame is the vortex's true one when it is drawn under a far stand-in (a gate's vortex follows its gate's
## `FarProp` look, which shrinks toward the eye far away); null for a stand-alone point.
var frame_owner: Node3D = null
## Every vortex draws this level when 0 or more (`vortex lod <level>`, for captures); -1 follows the size on screen.
static var forced_level: int = -1

var funnel: MeshInstance3D = null
var flash_quad: MeshInstance3D = null
var emitter: LightEmitter = null
var sound: AudioStreamPlayer3D = null

var _active: bool = false
var _materials: Array[ShaderMaterial] = []  # by direction, shared with every vortex of these colours
var _colours: Dictionary = DEFAULT_COLOURS.duplicate()
var _rig: LightRig = null
var _sounded: bool = false
var _coarse: bool = false
var _lod_a: Vector4 = Vector4(-1.0, -1.0, -1.0, -1.0)
var _lod_b: Vector4 = Vector4(-1.0, -1.0, -1.0, -1.0)

static var _funnel_mesh: ArrayMesh = null
static var _coarse_mesh: ArrayMesh = null
static var _quad: QuadMesh = null
static var _material_cache: Dictionary = {}  # colours and direction -> the funnel's material
static var _flash_cache: Dictionary = {}  # flash colour -> the flash's material
static var _stream: AudioStreamWAV = null
static var _stream_checked: bool = false


## A vortex built and ready to add to the tree: `vortex_data` as a gate's `vortex` hardpoints entry (colours, flash; empty for the
## defaults), `standalone` when it is not a gate's child (it then follows rebases itself).
static func create(vortex_data: Dictionary = {}, standalone: bool = true, with_sound: bool = true) -> JumpVortex:
	var vortex := (load(SCENE_PATH) as PackedScene).instantiate() as JumpVortex
	if standalone:
		vortex.add_to_group(WorldFrame.SHIFTABLE_GROUP)
		vortex.add_to_group(WorldFrame.ANCHORED_GROUP)
	vortex.setup(vortex_data, with_sound)
	return vortex


## Builds the meshes, the light and the sound. Call once, before it enters the tree (`create` does).
func setup(vortex_data: Dictionary = {}, with_sound: bool = true) -> void:
	var colours: Variant = vortex_data.get("colours")
	if colours is Dictionary:
		for key: StringName in DEFAULT_COLOURS:
			var entry: Variant = (colours as Dictionary).get(String(key))
			if entry is Dictionary:
				_colours[key] = [_colour((entry as Dictionary).get("colour"), DEFAULT_COLOURS[key][0]),
						_colour((entry as Dictionary).get("highlight"), DEFAULT_COLOURS[key][1])]
	flash_colour = _colour(vortex_data.get("flash"), DEFAULT_FLASH)
	_materials = [funnel_material(_colours, Direction.ARRIVAL), funnel_material(_colours, Direction.DEPARTURE)]
	funnel = MeshInstance3D.new()
	funnel.name = "Funnel"
	funnel.mesh = funnel_mesh()
	funnel.material_override = _materials[Direction.ARRIVAL]
	funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(funnel)
	flash_quad = MeshInstance3D.new()
	flash_quad.name = "Flash"
	flash_quad.mesh = _flash_mesh()
	flash_quad.material_override = flash_material(flash_colour)
	flash_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_quad.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	add_child(flash_quad)
	emitter = LightEmitter.new("jump_vortex", LightEmitter.PRIORITY_EXPLOSION, Color.WHITE, 0.0, 600.0)
	emitter.anchor = self
	if with_sound:
		sound = AudioStreamPlayer3D.new()
		sound.name = "Sound"
		sound.bus = AudioDirector.BUS
		sound.unit_size = 120.0
		sound.max_distance = 15000.0
		sound.volume_db = SOUND_DB
		sound.stream = _jump_sound()
		add_child(sound)
	_hide_all()


func _ready() -> void:
	_sync_processing()


func _exit_tree() -> void:
	_leave_rig()


## The funnel's shared material for `colours` (as `DEFAULT_COLOURS`) going `p_direction`: made once, then every vortex of those
## colours draws with it.
static func funnel_material(colours: Dictionary, p_direction: Direction) -> ShaderMaterial:
	var way: StringName = DIRECTION_NAMES[p_direction]
	var pair: Array = colours[way]
	var key: String = "%s %s %s" % [way, pair[0], pair[1]]
	var cached: ShaderMaterial = _material_cache.get(key)
	if cached != null:
		return cached
	var material := ShaderMaterial.new()
	material.shader = FUNNEL_SHADER
	material.set_shader_parameter(&"colour", pair[0])
	material.set_shader_parameter(&"highlight", pair[1])
	material.set_shader_parameter(&"flow", VortexSwirl.radial(p_direction))
	material.set_shader_parameter(&"turn", VortexSwirl.turn_in_mesh(p_direction))
	material.set_shader_parameter(&"brightness", BRIGHTNESS[way])
	_material_cache[key] = material
	return material


## The centre flash's shared material for `colour`.
static func flash_material(colour: Color) -> ShaderMaterial:
	var key: String = str(colour)
	var cached: ShaderMaterial = _flash_cache.get(key)
	if cached != null:
		return cached
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter(&"tint", Vector3(colour.r, colour.g, colour.b) * 3.0)
	material.set_shader_parameter(&"rays", 1.2)
	material.set_shader_parameter(&"lift", 0.0)
	_flash_cache[key] = material
	return material


## Places the vortex at `xform` (its parent's frame: the origin the mouth's centre, -Z the way ships come out), sizes it by
## `p_fit` and opens it. A vortex already running refuses (false); a pool picks another.
func open_at(xform: Transform3D, p_fit: VortexFit, p_direction: Direction, hold_s: float = VortexTiming.DEFAULT_HOLD_S,
		lead_s: float = 0.0) -> bool:
	if _active:
		return false
	transform = xform
	fit.mouth_radius_m = p_fit.mouth_radius_m
	fit.mouth_half_width_m = p_fit.mouth_half_width_m
	fit.depth_m = p_fit.depth_m
	fit.mouth_z_m = p_fit.mouth_z_m
	reset_physics_interpolation()
	return open(p_direction, hold_s, lead_s)


## Starts an opening in `p_direction` that stays open `hold_s` once grown, after the opener's `lead_s`. An opening already running
## the same way is kept open that much longer instead; one running the other way refuses (one direction per opening). Returns
## whether it is opening.
func open(p_direction: Direction, hold_s: float = VortexTiming.DEFAULT_HOLD_S, lead_s: float = 0.0) -> bool:
	if _active and direction != p_direction:
		return false
	if _active and timing.phase(age_s) < VortexTiming.Phase.CLOSING:
		timing.extend(age_s, hold_s)
		return true
	if _active:
		return false  # closing or in its closing flash: it must finish before it opens again
	direction = p_direction
	timing.reset(hold_s, lead_s)
	age_s = 0.0
	_active = true
	_sounded = false
	openings += 1
	funnel.material_override = _materials[direction]
	emitter.color = (_colours[DIRECTION_NAMES[direction]][1] as Color)
	emitter.omni_range = fit.mouth_radius_m * 6.0
	if lit:
		_join_rig()
	_sync_processing()
	if not driven:
		update_visuals()
	return true


## Starts the close now, or once the funnel is fully open.
func close() -> void:
	if _active:
		timing.close_now(age_s)


## Ends the opening at once, with no close (a pool taking its oldest point back).
func stop() -> void:
	_active = false
	_leave_rig()
	_hide_all()
	_sync_processing()


## Keeps the current opening open at least `hold_s` more.
func extend(hold_s: float) -> void:
	if _active:
		timing.extend(age_s, hold_s)


func is_active() -> bool:
	return _active


## Ships of `p_direction` may pass now.
func is_open_for(p_direction: Direction) -> bool:
	return _active and direction == p_direction and timing.is_open(age_s)


## A ship going `p_direction` may go through now: the funnel at least half unfolded (a ship a little early still makes it).
func is_passable_for(p_direction: Direction) -> bool:
	return _active and direction == p_direction and timing.growth(age_s) >= 0.5


## Seconds until it is open for `p_direction`: 0 when it is, INF when it is closed or opening the other way.
func open_in_s(p_direction: Direction) -> float:
	if not _active or direction != p_direction or timing.phase(age_s) >= VortexTiming.Phase.CLOSING:
		return INF
	return timing.open_in_s(age_s)


## The vortex's frame in the World (origin the mouth's centre, +Z down the funnel), wherever it is drawn.
func true_frame() -> Transform3D:
	if frame_owner != null and is_instance_valid(frame_owner):
		return frame_owner.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, fit.mouth_z_m))
	return global_transform if is_inside_tree() else transform


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
	if not _sounded and age_s >= timing.lead_s:
		_sounded = true
		if not muted and sound != null and sound.stream != null and direction == Direction.ARRIVAL and is_inside_tree():
			sound.play()
	if timing.is_done(age_s):
		stop()


## Puts the meshes and the light on the opening's current age, its detail on its size from the viewport's camera (full detail
## with none).
func update_visuals() -> void:
	if not _active:
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		update_visuals_for(global_position if is_inside_tree() else position, 0.0)
		return
	var height: float = get_viewport().get_visible_rect().size.y
	update_visuals_for(camera.global_position, camera.get_camera_projection().y.y * 0.5 * height)


## `update_visuals` for a camera at `camera_position` with `px_per_unit` (`VortexLod.px_per_unit`; 0 for full detail); a pool
## works these out once for all its points.
func update_visuals_for(camera_position: Vector3, px_per_unit: float) -> void:
	if not _active:
		return
	var grown: float = timing.growth(age_s)
	funnel.visible = grown > 0.0
	funnel.scale = Vector3(fit.mouth_half_width_m, fit.mouth_radius_m, fit.depth_m)
	var xform: Transform3D = global_transform if is_inside_tree() else transform
	var to_camera: Vector3 = camera_position - xform.origin
	var axis: Vector3 = xform.basis.z.normalized()
	# Seen from its base (M6-T22): a camera inside the funnel, following a ship down it, looks at the base from in front.
	var from_base: Vector3 = camera_position - xform * Vector3(0.0, 0.0, fit.depth_m)
	var facing: float = (from_base + axis * 1e-3).normalized().dot(axis)
	# The base glows from the side and behind, and fades to black looking down the funnel from in front.
	funnel.set_instance_shader_parameter(&"vortex_state", Vector4(grown, smoothstep(-0.45, -0.05, facing), SimClock.now(), 0.0))
	if px_per_unit > 0.0:
		var scale_m: float = maxf(fit.mouth_half_width_m, fit.mouth_radius_m) * xform.basis.y.length()
		radius_px = VortexLod.projected_radius_px(scale_m, to_camera.length(), px_per_unit)
	else:
		radius_px = VortexLod.MAX_PX
	_set_detail()
	var flash_level: float = timing.flash(age_s)
	flash_quad.visible = flash_level > 0.0
	flash_quad.position = Vector3(0.0, 0.0, fit.depth_m)
	flash_quad.scale = Vector3.ONE * fit.mouth_radius_m * FLASH_SIZE * maxf(sqrt(flash_level), 1e-3)
	flash_quad.set_instance_shader_parameter(&"level", flash_level)
	emitter.energy = LIGHT_PEAK_ENERGY * maxf(flash_level, grown * 0.5)


## The layers' weights the funnel draws now (`VortexLod.LAYER_NAMES` order): from its size on screen, or the forced level.
func detail() -> PackedFloat32Array:
	if forced_level >= 0:
		return VortexLod.level_weights(forced_level)
	return VortexLod.weights(radius_px)


# Hands the funnel its layers' weights and mesh, only when they change.
func _set_detail() -> void:
	var w: PackedFloat32Array = detail()
	lod_level = VortexLod.level(radius_px) if forced_level < 0 else forced_level
	var a := Vector4(w[0], w[1], w[2], w[3])
	var b := Vector4(w[4], w[5], 0.0, 0.0)
	if a != _lod_a:
		_lod_a = a
		funnel.set_instance_shader_parameter(&"vortex_lod_a", a)
	if b != _lod_b:
		_lod_b = b
		funnel.set_instance_shader_parameter(&"vortex_lod_b", b)
	var coarse: bool = VortexLod.coarse_mesh(radius_px, _coarse) and forced_level < 0
	if coarse != _coarse:
		_coarse = coarse
		funnel.mesh = coarse_funnel_mesh() if coarse else funnel_mesh()


## Whether the funnel draws its coarse mesh now.
func is_coarse() -> bool:
	return _coarse


## A unit funnel grid shared by every vortex: UV.x round it, UV.y from the rim (0) to the centre (1), closed at the centre. The
## shader shapes it (and unfolds it); the vertices here only give it the right bounds. Its triangles run from the base out to the
## rim, so the translucent walls are drawn over the base and hide its dark circle from an oblique view.
static func funnel_mesh() -> ArrayMesh:
	if _funnel_mesh == null:
		_funnel_mesh = _grid(SEGMENTS, RINGS)
	return _funnel_mesh


## The same funnel with fewer vertices, for a point a few pixels across.
static func coarse_funnel_mesh() -> ArrayMesh:
	if _coarse_mesh == null:
		_coarse_mesh = _grid(COARSE_SEGMENTS, COARSE_RINGS)
	return _coarse_mesh


static func _flash_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(2.0, 2.0)
	return _quad


# The funnel's unit grid with `segments` round it and `rings` from the rim to the centre.
static func _grid(segments: int, rings: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring: int in rings + 1:
		var v: float = float(ring) / float(rings)
		var r: float = 1.0 - v
		for seg: int in segments + 1:
			var u: float = float(seg) / float(segments)
			vertices.append(Vector3(cos(u * TAU) * r, sin(u * TAU) * r, v))
			uvs.append(Vector2(u, v))
	var row: int = segments + 1
	for ring: int in range(rings - 1, -1, -1):
		for seg: int in segments:
			var a: int = ring * row + seg
			indices.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _hide_all() -> void:
	if funnel != null:
		funnel.visible = false
	if flash_quad != null:
		flash_quad.visible = false
	if emitter != null:
		emitter.energy = 0.0


func _join_rig() -> void:
	_rig = LightRig.of(self)
	if _rig != null:
		_rig.add_emitter(emitter)


func _leave_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.remove_emitter(emitter)
	_rig = null


# Processes only while open: a hundred closed points cost nothing a tick. A driven one is drawn by its pool.
func _sync_processing() -> void:
	set_physics_process(_active)
	set_process(_active and not driven)


static func _colour(raw: Variant, fallback: Color) -> Color:
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


# The generated sound, loaded once for every vortex; without it (assets not built) arrivals are silent.
static func _jump_sound() -> AudioStreamWAV:
	if not _stream_checked:
		_stream_checked = true
		if ResourceLoader.exists(SOUND_PATH):
			_stream = load(SOUND_PATH) as AudioStreamWAV
		else:
			push_warning("JumpVortex: %s is missing or not imported (run scripts/gen_assets.sh, then import); arrivals are silent" % SOUND_PATH)
	return _stream
