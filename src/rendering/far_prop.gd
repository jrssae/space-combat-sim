class_name FarProp
extends Node3D
## Keeps a big prop (the jumpgate, the station's stand-in) visible and its true size from 100 m out to its broadcast range and
## beyond (M6-T15, D70, AC9). A child of the prop; its visuals sit under one `Look` node, which this shrinks toward the eye past
## the far plane's reach, then hands over to a far dot once the prop is a few pixels across (`FarPropMath` has the rules).
## The prop's collision, its `Targetable` and its place in the World never move: only the picture does.
##
## The look and the dot are ordinary children (not `top_level`), so a rebase or a drift that moves the prop moves them with it
## until the next frame places them again.
##
## Each frame, after the cameras have moved (as the scaled-space layer does), from the camera's drawn pose. The dot's colour is
## the prop's mean albedo lit as its mesh is from this side (`FarPropMath.hull_phase`), plus the ambient and its own glow, so
## a prop in the planet's shadow or seen against the sun is no brighter or darker as a dot than as a mesh. Visual only.
##
## Console: `FarPropHost`'s provider and command `far`.

const GROUP: StringName = &"far_props"
const NODE_NAME: String = "FarProp"
const DOT_SHADER: Shader = preload("res://assets/shaders/far_prop_dot.gdshader")
## The dot's light per unit albedo (M6-T15's Done notes: the gate's mesh against its dot on the RX 6950 XT, 30 px across, the
## sun at 0, 60, 110 and 160 degrees and off): the key star's share at full phase per unit energy, the ambient's per unit of
## its energy, and what the hull shows with no sun at all beyond the ambient (its lamps, windows and sheen).
const SUN_GAIN: float = 0.47
const AMBIENT_GAIN: float = 1.0
const GLOW_SHARE: float = 0.41

## Shown by the console.
var display_name: String = ""
## How far out the prop is meant to be seen (its `Targetable`'s broadcast range), m; the readouts and tests check up to it.
var range_m: float = 0.0
## The prop's visuals (shrunk together), and the ones that fade out into the dot (all but `keep_drawn`).
var look: Node3D = null
var math: FarPropMath = null
## The prop's mean albedo, linear.
var albedo: Color = Color(0.1, 0.1, 0.1)
var dot: MeshInstance3D = null

## This frame's state, for readouts and tests: the camera's distance to the prop's centre, the shrink, whether the dot is
## wanted, the cross-fade (0 the mesh, 1 the dot), pixels per radian, and the direction to the eye in the prop's frame.
var distance_m: float = 0.0
var shrink: float = 1.0
var wants_dot: bool = false
var fade: float = 0.0
var k_px_per_rad: float = 0.0
var to_eye_local: Vector3 = Vector3.BACK
## Pins the cross-fade (0 the mesh, 1 the dot) for captures and the GPU test; below 0 it follows the distance.
var held_fade: float = -1.0

var _prop: Node3D = null
var _rest: Transform3D = Transform3D.IDENTITY
## Visuals under `look` that stay drawn as they are when the prop is a dot.
var keep_drawn: Array[Node3D] = []
var _faded: Array[GeometryInstance3D] = []
var _faded_known: bool = false
var _material: ShaderMaterial = null
var _faded_level: float = 0.0
var _far_lod: bool = false


## Puts `visuals` (children of `prop`) under one `Look` node and keeps them drawn far out with a far prop made from the
## manifest section `far`. Visuals added to `look` later are shrunk too; those in `keep_drawn` stay shown as they are when it is
## a dot (an open vortex). Null when the section is missing (the prop is then drawn as before, to the far plane). Call before the
## visuals register anything with the tree (a moved node leaves and enters it again).
static func attach(prop: Node3D, visuals: Array[Node3D], far: Dictionary, p_albedo: Color, p_range_m: float,
		p_display_name: String) -> FarProp:
	var model: FarPropMath = FarPropMath.from_section(far)
	if model == null:
		push_warning("FarProp: %s has no far section (rebuild its asset); it vanishes past the far plane" % p_display_name)
		return null
	var holder := Node3D.new()
	holder.name = "Look"
	holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # placed each frame, not each tick
	prop.add_child(holder)
	for v: Node3D in visuals:
		if v != null:
			v.reparent(holder, false)
	var made := FarProp.new()
	made.name = NODE_NAME
	made.display_name = p_display_name
	made.range_m = p_range_m
	made.math = model
	made.albedo = p_albedo
	made.look = holder
	made._prop = prop
	prop.add_child(made)
	return made


## The far prop of `prop`, or null.
static func of(prop: Node) -> FarProp:
	return prop.get_node_or_null(NodePath(NODE_NAME)) as FarProp if prop != null else null


## The mean albedo of a textured asset, linear: its mesh's, or its pieces' averaged.
static func albedo_of(manifest: Dictionary) -> Color:
	var sums: Array[Array] = []
	var mesh: Dictionary = manifest.get("mesh", {})
	if mesh.has("mean_albedo"):
		sums.append(mesh["mean_albedo"])
	var pieces: Dictionary = manifest.get("pieces", {})
	for piece: Variant in pieces.values():
		var m: Variant = ((piece as Dictionary).get("mesh", {}) as Dictionary).get("mean_albedo")
		if m is Array:
			sums.append(m)
	if sums.is_empty():
		return Color(0.1, 0.1, 0.1)
	var c := Color(0.0, 0.0, 0.0)
	for s: Array in sums:
		c += Color(float(s[0]), float(s[1]), float(s[2]), 0.0) / float(sums.size())
	c.a = 1.0
	return c


func _init() -> void:
	add_to_group(GROUP)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# After the camera rig has moved the cameras this frame.
	process_priority = ScaledSpace.LATE_PRIORITY


func _ready() -> void:
	_rest = look.transform if look != null else Transform3D.IDENTITY
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_material = ShaderMaterial.new()
	_material.shader = DOT_SHADER
	dot = MeshInstance3D.new()
	dot.name = "Dot"
	dot.mesh = quad
	dot.material_override = _material
	dot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	dot.visible = false
	add_child(dot)


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera != null:
		update(camera, delta)


## Places the prop's picture for `camera` now, the cross-fade `delta_s` further on. `_process` calls it; public for tests.
func update(camera: Camera3D, delta_s: float) -> void:
	if look == null or math == null or _prop == null or not _prop.is_inside_tree():
		return
	var view: Transform3D = camera.get_global_transform_interpolated()
	var eye: Vector3 = view.origin
	var pose: Transform3D = _prop.get_global_transform_interpolated()
	var centre: Vector3 = pose * math.centre
	var offset: Vector3 = centre - eye
	distance_m = offset.length()
	k_px_per_rad = k_of(camera)
	shrink = FarPropMath.shrink(distance_m, math.pull_m(camera.far))
	to_eye_local = (pose.basis.orthonormalized().inverse() * -offset) if distance_m > 0.0 else Vector3.BACK
	if not _faded_known:
		_faded_known = true
		_collect_faded(look)
	wants_dot = math.is_dot(distance_m, wants_dot, k_px_per_rad)
	fade = FarPropMath.step_fade(fade, wants_dot, delta_s) if held_fade < 0.0 else clampf(held_fade, 0.0, 1.0)
	_place_look(eye, pose)
	_apply_lod()
	_apply_fade()
	_place_dot(camera, eye, offset)


## Which path draws the prop now: near, shrunk, fading or dot.
func path() -> StringName:
	if fade >= 1.0:
		return &"dot"
	if fade > 0.0:
		return &"fading"
	return &"shrunk" if shrink < 1.0 else &"near"


## The screen pixels the prop covers now, by the model (the GPU test checks the real picture against it).
func cover_px2() -> float:
	return math.cover_px2(to_eye_local, distance_m, fade, k_px_per_rad) if math != null and distance_m > 0.0 else 0.0


## The dot's colour now, linear.
func dot_paint() -> Color:
	var paint: Variant = _material.get_shader_parameter(&"paint") if _material != null else null
	return Color(paint.x, paint.y, paint.z) if paint is Vector3 else Color.BLACK


# The prop's visuals scaled by `shrink` about the eye: the same angle, the same light, inside the far plane.
func _place_look(eye: Vector3, pose: Transform3D) -> void:
	if shrink >= 1.0:
		if look.transform != _rest:
			look.transform = _rest
		return
	var about_eye := Transform3D(Basis.from_scale(Vector3.ONE * shrink), eye * (1.0 - shrink))
	look.global_transform = about_eye * pose * _rest


# Shrunk, the mesh keeps its finer levels so its thin parts still reach the screen up to the hand-off.
func _apply_lod() -> void:
	var far: bool = shrink < 1.0
	if far == _far_lod:
		return
	_far_lod = far
	for g: GeometryInstance3D in _faded:
		if is_instance_valid(g):
			g.lod_bias = FarPropMath.FAR_LOD_BIAS if far else 1.0


# The mesh fades out as the dot fades in; it is hidden once the dot alone draws it.
func _apply_fade() -> void:
	if is_equal_approx(fade, _faded_level):
		return
	_faded_level = fade
	for g: GeometryInstance3D in _faded:
		if is_instance_valid(g):
			g.transparency = fade
			g.visible = fade < 1.0


func _place_dot(camera: Camera3D, eye: Vector3, offset: Vector3) -> void:
	dot.visible = fade > 0.0
	if not dot.visible:
		return
	var area: float = math.area_toward(to_eye_local)
	var radius: float = FarPropMath.dot_radius_m(area) * shrink
	dot.global_transform = Transform3D(Basis.IDENTITY, eye + offset * shrink)
	dot.custom_aabb = AABB(-Vector3.ONE * (radius + 1.0), Vector3.ONE * 2.0 * (radius + 1.0))
	_material.set_shader_parameter(&"radius_m", radius)
	_material.set_shader_parameter(&"fade", fade)
	var paint: Color = _paint(camera, offset)
	# A Vector3, not a Color: a Color handed to a vec3 uniform is taken as sRGB and darkened.
	_material.set_shader_parameter(&"paint", Vector3(paint.r, paint.g, paint.b))


# The mean albedo lit as the mesh is: the key star on the side we see, the ambient everywhere.
func _paint(camera: Camera3D, offset: Vector3) -> Color:
	var rig: LightRig = LightRig.of(self)
	var key: DirectionalLight3D = rig.key_star if rig != null else null
	var sun: float = 0.0
	var phase: float = 0.0
	var tint := Color.WHITE
	if key != null and key.visible:
		sun = key.light_energy * SUN_GAIN
		tint = key.light_color.srgb_to_linear()
		# The key star's +Z points at the star; the eye is back along `offset` from the prop.
		phase = acos(clampf(key.global_basis.z.normalized().dot(-offset.normalized()), -1.0, 1.0))
	var ambient: float = _ambient(camera) * AMBIENT_GAIN + GLOW_SHARE
	var lit: float = FarPropMath.hull_phase(phase)
	return Color(albedo.r * (ambient + sun * lit * tint.r), albedo.g * (ambient + sun * lit * tint.g),
			albedo.b * (ambient + sun * lit * tint.b))


func _ambient(camera: Camera3D) -> float:
	var env: Environment = camera.environment if camera.environment != null else camera.get_world_3d().environment
	return env.ambient_light_energy if env != null else 0.0


## Pixels per radian at the centre of `camera`'s picture.
static func k_of(camera: Camera3D) -> float:
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var across: float = size.x if camera.keep_aspect == Camera3D.KEEP_WIDTH else size.y
	return FarPropMath.px_per_rad(across, camera.fov)


# Every mesh under the look but the kept ones, read once the prop has built its visuals.
func _collect_faded(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Node3D and keep_drawn.has(child as Node3D):
			continue
		if child is GeometryInstance3D:
			_faded.append(child as GeometryInstance3D)
		_collect_faded(child)
