class_name ThrusterVisuals
extends MultiMeshInstance3D
## Thruster exhaust plumes (architecture §7.1): one per pod main nozzle, per pod retro nozzle and per cosmetic RCS
## nozzle. A plume sits at the nozzle's hardpoint position with its local +Y axis along the nozzle's `exhaust` direction, so
## it comes out of the nozzle and points the way the gas goes whatever the camera does. It has two parts:
##
## - the cone: open, unshaded, additive, its base at the nozzle position, extending along `exhaust`, fading to nothing at the
##   far end (vertex alpha). Its length and radius scale with the level.
## - the core: a small soft disc at the nozzle exit, perpendicular to the exhaust, the hot spot you see when looking straight
##   into the nozzle.
##
## Two ways to draw them, chosen before `setup` by `instanced`:
##
## - Nodes (the player's ship): a `Node3D` per plume with a `Cone` and a `Core` mesh instance; the plume's level is each mesh's
##   `transparency`. This node's own multimesh stays empty.
## - Instanced (AI ships, M4-T11, §17.10): this node is one multimesh with an instance per plume, cone and core baked into one
##   surface with one material; the level is the instance colour's alpha. One draw call for every plume of the ship, no node.
##
## The plumes are transparent meshes, so they draw after the opaque hulls and are hidden behind the hull by its depth (§7.2).
##
## Wiring (Main, M1-T15, does this; the node does not know the Ship class). Add the node as a child of the ship body
## so node-local is ship-local, then:
##
##     visuals.setup(layout, ship.get_flight_output)    # a Callable returning the latest FlightOutput, or null
##
## Each frame (`frame_update`, from the `FramePasses` plumes pass, M4-T36) the levels come from the output through
## `ThrusterGlowLevels` (pod nozzles from the post-trim `main_levels` / `retro_levels`, RCS nozzles from the strongest of their
## tags), are smoothed with a first-order lag of `smoothing_s` (80 ms), and drive each plume's length and radius (proportional
## to level) and alpha.
## A plume below `hide_below` is hidden. With no output (null) every plume fades out. While the node is hidden (a parked
## ship, a far ship drawn as a dot) the instanced plumes leave the pass and their lights go dark. Once every level has reached
## its target within `SETTLE_LEVEL` the levels are set to the targets and the plumes are left alone until the output changes:
## a ship holding one command converges in about half a second and then costs one comparison a frame (M4-T36).
##
## `glow_color` (the ship's `engine_glow_color`) tints the plumes: the shared materials carry the Starfury's blue-white,
## and any other colour gets its own copies of the materials (set it before `setup`); instanced ships share one per colour.
##
## Lights (M3-T22): each main pod nozzle also owns a `LightEmitter`, `EmitterCurves.NOZZLE_OFFSET_M` out along the exhaust, so
## the plume lights its pod and strut. Its energy follows the smoothed level (0 at idle), its colour is the plume's, and
## it competes through the `LightRig`'s `LightPicker` for a slot. RCS and retro nozzles give no light (too many). The
## emitters are in the rig's candidates only while the ship is in play: a parked or freed ship takes them out, and
## the pass puts them back when it is back. `own_ship` (the player's) gives them the picker's top priority.
##
## The plumes ride with the interpolated hull (children of the ship, or this node's instances); only their scale and alpha
## change per frame, which is invisible next to a 16 ms tick. How it looks is (H).

const PLUME_MATERIAL: Material = preload("res://assets/materials/thruster_plume.tres")
const CORE_MATERIAL: Material = preload("res://assets/materials/thruster_glow.tres")
## The colour baked into the shared plume and core materials.
const DEFAULT_GLOW_COLOR: Color = Color(0.7, 0.9, 1.8, 1.0)
const POD_PREFIX: String = "Plume_"
const RCS_PREFIX: String = "PlumeRcs_"
const CONE_NAME: String = "Cone"
const CORE_NAME: String = "Core"

## Sides of the cone, and rings along it (the rings carry the fade, so more of them make a smoother one).
const CONE_SEGMENTS: int = 16
const CONE_RINGS: int = 6
## Radius at the far end of the cone as a fraction of the radius at the nozzle.
const CONE_TIP_RADIUS: float = 0.3
## Vertex alpha along the cone is `(1 - t) ^ CONE_FADE_POWER` for t = 0 at the nozzle to 1 at the far end.
const CONE_FADE_POWER: float = 1.6
## The core disc sits this far out of the nozzle along the exhaust, so it never z-fights the nozzle's own surface.
const CORE_OFFSET_M: float = 0.05
## The instanced core's offset as a share of the plume's length (its instance is scaled by the length): 0.05 m at a main
## nozzle's full level.
const CORE_OFFSET_SHARE: float = 0.02
## Diameter of the core disc as a multiple of the plume radius.
const CORE_DIAMETER_PER_RADIUS: float = 2.6
## The core texture's falloff, baked into the instanced disc's vertex colours: (radius share, level).
const CORE_FALLOFF: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(0.3, 0.55), Vector2(1.0, 0.0)]
## The plume radius at level 0 as a fraction of the radius at level 1 (plumes widen a little as they brighten).
const MIN_RADIUS_FRACTION: float = 0.6
## Floats per instance in the multimesh buffer: a 3x4 transform and a colour.
const STRIDE: int = 16
## A plume this close to its target level counts as there (M4-T36): about a thousandth of a millimetre on a main plume.
const SETTLE_LEVEL: float = 1e-4

## Full-level length of the cone, m, per kind of nozzle.
@export var main_length_m: float = 2.6
@export var retro_length_m: float = 1.5
@export var rcs_length_m: float = 0.6
## Full-level radius of the cone at the nozzle, m (the Starfury's bells are 0.5 m main, 0.25 m retro).
@export var main_radius_m: float = 0.4
@export var retro_radius_m: float = 0.2
@export var rcs_radius_m: float = 0.06
## HDR colour of the plumes; differs from the default only for ships with another engine colour.
@export var glow_color: Color = DEFAULT_GLOW_COLOR
## The player's own ship: its nozzle lights outrank every other emitter, so they stay picked while it fires.
@export var own_ship: bool = false
## Time constant of the level smoothing, s.
@export var smoothing_s: float = 0.08
## Plumes with a smoothed level under this are hidden.
@export var hide_below: float = 0.01
## Draw every plume as an instance of this node's multimesh instead of nodes (M4-T11, AI ships). Set before `setup`.
@export var instanced: bool = false

static var _cone_mesh: ArrayMesh = null
static var _core_mesh: QuadMesh = null
static var _plume_mesh: ArrayMesh = null
# Instanced ships share one plume material per engine colour.
static var _instanced_materials: Dictionary[Color, Material] = {}

var _layout: ThrusterLayout = null
var _output_source: Callable = Callable()
var _tinted_plume_material: Material = null
var _tinted_core_material: Material = null
var _plumes: Array[Node3D] = []
var _cones: Array[MeshInstance3D] = []
var _cores: Array[MeshInstance3D] = []
var _lengths: PackedFloat64Array = PackedFloat64Array()
var _radii: PackedFloat64Array = PackedFloat64Array()
var _levels: PackedFloat64Array = PackedFloat64Array()
# Instanced: each plume's pose at the nozzle (before its scale), and the buffer the multimesh draws.
var _bases: Array[Transform3D] = []
var _buffer: PackedFloat32Array = PackedFloat32Array()
# One entry per plume: the nozzle's light, or null for retro and RCS nozzles.
var _lights: Array[LightEmitter] = []
var _rig: LightRig = null
var _lights_in_rig: bool = false
# Every level is at its target and the output has not changed since (M4-T36): the plumes need no work.
var _settled: bool = false
var _last_main := PackedFloat64Array()
var _last_retro := PackedFloat64Array()
var _last_force: Vector3 = Vector3.ZERO
var _last_torque: Vector3 = Vector3.ZERO
var _last_had_output: bool = false


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## One frame of the plumes: the `FramePasses` plumes pass calls it for every ship in play.
func frame_update(delta: float) -> void:
	if instanced and not is_visible_in_tree():
		_go_dark()
		return
	advance(delta)
	_enter_rig()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			_join_pass()
		NOTIFICATION_EXIT_TREE:
			_leave_rig()  # a ship that leaves play stops processing, so its lights must go from the competition here
			var passes: FramePasses = FramePasses.of(self)
			if passes != null:
				passes.remove_plumes(self)
		NOTIFICATION_DISABLED:
			_leave_rig()
		NOTIFICATION_VISIBILITY_CHANGED:
			# A hidden instanced ship (parked, or a far dot) leaves the pass with its lights dark, and joins it again when shown.
			if instanced and is_inside_tree():
				if is_visible_in_tree():
					_join_pass()
				else:
					_go_dark()
					var passes: FramePasses = FramePasses.of(self)
					if passes != null:
						passes.remove_plumes(self)


## Called by Main with the ship's thruster layout and a Callable returning the latest `FlightOutput` (or null).
## Builds the plumes, replacing any from an earlier call. An unusable layout leaves the node empty with a warning.
func setup(layout: ThrusterLayout, output_source: Callable) -> void:
	_clear()
	_output_source = output_source
	_layout = layout
	_build_tint_materials()
	if layout == null or not layout.valid:
		push_warning("ThrusterVisuals.setup: no usable thruster layout (%s)" % ("none" if layout == null else layout.error))
		_layout = null
		return
	for i: int in layout.nozzle_count():
		var is_main: bool = ThrusterLayout.is_main_group(layout.nozzle_groups[i])
		_add_plume(POD_PREFIX + layout.nozzle_names[i], layout.nozzle_positions[i], layout.nozzle_exhausts[i],
				main_length_m if is_main else retro_length_m, main_radius_m if is_main else retro_radius_m, is_main)
	for entry: Dictionary in layout.rcs_nozzles:
		_add_plume(RCS_PREFIX + str(entry["name"]), entry["position"], entry["exhaust"], rcs_length_m, rcs_radius_m)
	if instanced:
		_build_multimesh()


## Number of plumes: every pod nozzle plus every RCS nozzle.
func glow_count() -> int:
	return _levels.size()


## The plume node at `index` (pod nozzles in `ThrusterLayout` order, then RCS nozzles in hardpoint order), or null when
## instanced. Its position is the nozzle position and its local +Y axis the exhaust direction; `Cone` and `Core` are its children.
func glow(index: int) -> Node3D:
	return null if instanced else _plumes[index]


## The cone mesh node of the plume at `index` (null when instanced).
func cone(index: int) -> MeshInstance3D:
	return null if instanced else _cones[index]


## The core disc node of the plume at `index` (null when instanced).
func core(index: int) -> MeshInstance3D:
	return null if instanced else _cores[index]


## Whether the plume at `index` is drawn now.
func glow_shown(index: int) -> bool:
	return _levels[index] >= hide_below if instanced else _plumes[index].visible


## Smoothed level 0..1 of the plume at `index`; what its length, radius and alpha are drawn from.
func glow_level(index: int) -> float:
	return _levels[index]


## The material the plumes' cones are drawn with: the tinted copy, or the shared default.
func plume_material() -> Material:
	if instanced:
		return material_override
	return _tinted_plume_material if _tinted_plume_material != null else PLUME_MATERIAL


## Instanced: the pose (scale included) the plume at `index` was last drawn with, in this node's frame.
func instance_transform(index: int) -> Transform3D:
	var b: int = index * STRIDE
	return Transform3D(Vector3(_buffer[b], _buffer[b + 4], _buffer[b + 8]), Vector3(_buffer[b + 1], _buffer[b + 5], _buffer[b + 9]),
			Vector3(_buffer[b + 2], _buffer[b + 6], _buffer[b + 10]), Vector3(_buffer[b + 3], _buffer[b + 7], _buffer[b + 11]))


## Instanced: the colour the plume at `index` was last drawn with (its alpha is the level, 0 while hidden).
func instance_color(index: int) -> Color:
	var b: int = index * STRIDE + 12
	return Color(_buffer[b], _buffer[b + 1], _buffer[b + 2], _buffer[b + 3])


## The light of the plume at `index`, or null when that nozzle gives none (only main pod nozzles do).
func nozzle_light(index: int) -> LightEmitter:
	return _lights[index]


## Number of nozzle lights.
func light_count() -> int:
	var n: int = 0
	for emitter: LightEmitter in _lights:
		n += 1 if emitter != null else 0
	return n


## Reads the output and moves every plume `delta` seconds along its smoothing. `frame_update` calls it each frame; public
## so tests can step it with a chosen `delta`.
func advance(delta: float) -> void:
	if _layout == null:
		return
	var output: FlightOutput = null
	if _output_source.is_valid():
		output = _output_source.call() as FlightOutput
	if _settled and _same_output(output):
		return  # every plume holds its target: nothing moves
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(_layout, output)
	var settled: bool = true
	for i: int in _levels.size():
		_levels[i] = ThrusterGlowLevels.smooth(_levels[i], targets[i], delta, smoothing_s)
		settled = settled and absf(_levels[i] - targets[i]) <= SETTLE_LEVEL
	if settled:
		_levels = targets  # there: the smoothing would only creep the last ten-thousandth
	for i: int in _levels.size():
		_apply(i)
		if _lights[i] != null:
			_lights[i].energy = EmitterCurves.nozzle_energy(_levels[i])
	_upload()
	_settled = settled
	if settled:
		_note_output(output)


## Whether every plume holds its target and the plumes are left alone until the output changes (M4-T36).
func is_settled() -> bool:
	return _settled


## Puts every plume and nozzle light out at once: a ship back in play (a new pilot, a respawn) starts cold.
func reset() -> void:
	_settled = false
	for i: int in _levels.size():
		_levels[i] = 0.0
		_apply(i)
		if _lights[i] != null:
			_lights[i].energy = 0.0
	_upload()


## A basis whose +Y axis is `exhaust` (any length; zero falls back to +Z) and whose other axes are arbitrary but
## orthonormal and right-handed.
static func plume_basis(exhaust: Vector3) -> Basis:
	var y: Vector3 = exhaust.normalized() if exhaust.length_squared() > 1e-12 else Vector3.BACK
	var helper: Vector3 = Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var x: Vector3 = helper.cross(y).normalized()
	return Basis(x, y, x.cross(y))


## The shared unit cone: base (radius 1, alpha 1) at the origin, axis +Y to y = 1, far-end radius `CONE_TIP_RADIUS`
## with alpha 0. Vertex colours carry the fade, so one material serves every plume.
static func cone_mesh() -> ArrayMesh:
	if _cone_mesh != null:
		return _cone_mesh
	var arrays: Array = _cone_arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, PLUME_MATERIAL)
	_cone_mesh = mesh
	return _cone_mesh


## The shared unit disc quad (soft radial falloff in the material's texture), facing +Z in its own frame.
static func core_mesh() -> QuadMesh:
	if _core_mesh != null:
		return _core_mesh
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = CORE_MATERIAL
	_core_mesh = quad
	return _core_mesh


## The instanced plume (M4-T11): the unit cone and the core disc in one surface, drawn with the plume material. The disc lies
## across +Y at `CORE_OFFSET_SHARE` of the length, its radius `CORE_DIAMETER_PER_RADIUS / 2` of the cone's, its texture's
## falloff baked into vertex colours, so an instance scaled (radius, length, radius) draws both parts as the nodes do.
static func plume_mesh() -> ArrayMesh:
	if _plume_mesh != null:
		return _plume_mesh
	var arrays: Array = _cone_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var centre: int = vertices.size()
	var disc_radius: float = CORE_DIAMETER_PER_RADIUS * 0.5
	vertices.append(Vector3(0.0, CORE_OFFSET_SHARE, 0.0))
	normals.append(Vector3.UP)
	colors.append(Color(1.0, 1.0, 1.0, 1.0))
	for ring: int in range(1, CORE_FALLOFF.size()):
		var share: Vector2 = CORE_FALLOFF[ring]
		for segment: int in CONE_SEGMENTS:
			var angle: float = TAU * float(segment) / float(CONE_SEGMENTS)
			vertices.append(Vector3(cos(angle), 0.0, sin(angle)) * disc_radius * share.x + Vector3(0.0, CORE_OFFSET_SHARE, 0.0))
			normals.append(Vector3.UP)
			colors.append(Color(share.y, share.y, share.y, share.y))
	for segment: int in CONE_SEGMENTS:
		var next: int = (segment + 1) % CONE_SEGMENTS
		indices.append_array(PackedInt32Array([centre, centre + 1 + segment, centre + 1 + next]))
	for ring: int in range(1, CORE_FALLOFF.size() - 1):
		var inner: int = centre + 1 + (ring - 1) * CONE_SEGMENTS
		var outer: int = inner + CONE_SEGMENTS
		for segment: int in CONE_SEGMENTS:
			var next: int = (segment + 1) % CONE_SEGMENTS
			indices.append_array(PackedInt32Array([inner + segment, outer + segment, inner + next, inner + next, outer + segment, outer + next]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_plume_mesh = mesh
	return _plume_mesh


static func _cone_arrays() -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for ring: int in CONE_RINGS + 1:
		var t: float = float(ring) / float(CONE_RINGS)
		var radius: float = lerpf(1.0, CONE_TIP_RADIUS, t)
		var alpha: float = pow(1.0 - t, CONE_FADE_POWER)
		for segment: int in CONE_SEGMENTS:
			var angle: float = TAU * float(segment) / float(CONE_SEGMENTS)
			var around := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(around * radius + Vector3(0.0, t, 0.0))
			normals.append(around)
			colors.append(Color(1.0, 1.0, 1.0, alpha))
	for ring: int in CONE_RINGS:
		for segment: int in CONE_SEGMENTS:
			var next: int = (segment + 1) % CONE_SEGMENTS
			var a: int = ring * CONE_SEGMENTS + segment
			var b: int = ring * CONE_SEGMENTS + next
			var c: int = (ring + 1) * CONE_SEGMENTS + segment
			var d: int = (ring + 1) * CONE_SEGMENTS + next
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _add_plume(plume_name: String, at: Vector3, exhaust: Vector3, length: float, radius: float, lit: bool = false) -> void:
	var anchor: Node3D = self
	var offset: Vector3 = at + exhaust.normalized() * EmitterCurves.NOZZLE_OFFSET_M  # out along the exhaust
	if instanced:
		_bases.append(Transform3D(plume_basis(exhaust), at))
	else:
		var plume := Node3D.new()
		plume.name = plume_name
		plume.transform = Transform3D(plume_basis(exhaust), at)
		plume.visible = false

		var cone_node := MeshInstance3D.new()
		cone_node.name = CONE_NAME
		cone_node.mesh = cone_mesh()
		cone_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone_node.material_override = _tinted_plume_material
		plume.add_child(cone_node)

		var core_node := MeshInstance3D.new()
		core_node.name = CORE_NAME
		core_node.mesh = core_mesh()
		core_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core_node.material_override = _tinted_core_material
		core_node.position = Vector3(0.0, CORE_OFFSET_M, 0.0)
		core_node.rotation = Vector3(-PI / 2.0, 0.0, 0.0)  # the quad faces +Z; turn it to face along the plume's +Y
		plume.add_child(core_node)

		add_child(plume)
		_plumes.append(plume)
		_cones.append(cone_node)
		_cores.append(core_node)
		anchor = plume
		offset = Vector3(0.0, EmitterCurves.NOZZLE_OFFSET_M, 0.0)  # +Y is along the exhaust
	var light: LightEmitter = null
	if lit:
		light = LightEmitter.new(plume_name, LightEmitter.PRIORITY_PLAYER_OWN if own_ship else LightEmitter.PRIORITY_NOZZLE,
				EmitterCurves.light_color(glow_color), 0.0, EmitterCurves.NOZZLE_RANGE_M)
		light.anchor = anchor
		light.offset = offset
	_lights.append(light)
	_lengths.append(length)
	_radii.append(radius)
	_levels.append(0.0)


func _apply(index: int) -> void:
	var level: float = _levels[index]
	# Never exactly zero: a singular transform would trip the engine's matrix checks even while hidden.
	var shown: float = maxf(level, hide_below)
	var radius: float = _radii[index] * lerpf(MIN_RADIUS_FRACTION, 1.0, shown)
	if instanced:
		var basis: Basis = _bases[index].basis * Basis.from_scale(Vector3(radius, _lengths[index] * shown, radius))
		var origin: Vector3 = _bases[index].origin
		var b: int = index * STRIDE
		_buffer[b] = basis.x.x
		_buffer[b + 1] = basis.y.x
		_buffer[b + 2] = basis.z.x
		_buffer[b + 3] = origin.x
		_buffer[b + 4] = basis.x.y
		_buffer[b + 5] = basis.y.y
		_buffer[b + 6] = basis.z.y
		_buffer[b + 7] = origin.y
		_buffer[b + 8] = basis.x.z
		_buffer[b + 9] = basis.y.z
		_buffer[b + 10] = basis.z.z
		_buffer[b + 11] = origin.z
		_buffer[b + 12] = 1.0
		_buffer[b + 13] = 1.0
		_buffer[b + 14] = 1.0
		_buffer[b + 15] = level if level >= hide_below else 0.0
		return
	_plumes[index].visible = level >= hide_below
	_cones[index].scale = Vector3(radius, _lengths[index] * shown, radius)
	_cones[index].transparency = 1.0 - level
	_cores[index].scale = Vector3.ONE * (radius * CORE_DIAMETER_PER_RADIUS)
	_cores[index].transparency = 1.0 - level


# Instanced: one multimesh, an instance per plume, all cold.
func _build_multimesh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plume_mesh()
	mm.instance_count = _levels.size()
	multimesh = mm
	material_override = _instanced_material(glow_color)
	_buffer.resize(_levels.size() * STRIDE)
	for i: int in _levels.size():
		_apply(i)
	_upload()


func _upload() -> void:
	if instanced and multimesh != null and multimesh.instance_count > 0:
		RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _buffer)


# The plume material in `color`, shared by every instanced ship of that colour: the instance colour (the level) multiplies
# its vertex colours.
static func _instanced_material(color: Color) -> Material:
	if not _instanced_materials.has(color):
		var copy := PLUME_MATERIAL.duplicate() as StandardMaterial3D
		copy.albedo_color = color
		copy.emission = color
		copy.vertex_color_use_as_albedo = true
		_instanced_materials[color] = copy
	return _instanced_materials[color]


# Own copies of the two materials in `glow_color`, or none (null overrides) for the default colour.
func _build_tint_materials() -> void:
	_tinted_plume_material = null
	_tinted_core_material = null
	if instanced or glow_color.is_equal_approx(DEFAULT_GLOW_COLOR):
		return
	_tinted_plume_material = _tinted(PLUME_MATERIAL)
	_tinted_core_material = _tinted(CORE_MATERIAL)


func _tinted(base: Material) -> Material:
	var copy := base.duplicate() as StandardMaterial3D
	copy.albedo_color = glow_color
	copy.emission = glow_color
	return copy


# Joins the plumes pass (once); an instanced ship that is hidden joins when it shows.
func _join_pass() -> void:
	if instanced and not is_visible_in_tree():
		return
	var passes: FramePasses = FramePasses.of(self)
	if passes != null:
		passes.add_plumes(self)


# Whether `output` is what the plumes last smoothed toward (the fields the levels are read from).
func _same_output(output: FlightOutput) -> bool:
	if output == null:
		return not _last_had_output
	return _last_had_output and output.main_levels == _last_main and output.retro_levels == _last_retro \
			and output.rcs_force_level == _last_force and output.rcs_torque_level == _last_torque


func _note_output(output: FlightOutput) -> void:
	_last_had_output = output != null
	if output != null:
		_last_main = output.main_levels.duplicate()
		_last_retro = output.retro_levels.duplicate()
		_last_force = output.rcs_force_level
		_last_torque = output.rcs_torque_level


# A hidden instanced ship: its lights stop competing until it shows again.
func _go_dark() -> void:
	if _lights_in_rig:
		_leave_rig()


# Puts the nozzle lights in the rig's competition (once, however often it is called), shining at their plumes' levels: leaving
# put them out, and a settled ship does not rewrite them (M4-T36 fix round 1).
func _enter_rig() -> void:
	if _lights_in_rig:
		return
	_rig = LightRig.of(self)
	if _rig == null:
		return
	for i: int in _lights.size():
		if _lights[i] != null:
			_lights[i].energy = EmitterCurves.nozzle_energy(_levels[i])
			_rig.add_emitter(_lights[i])
	_lights_in_rig = true


func _leave_rig() -> void:
	for emitter: LightEmitter in _lights:
		if emitter != null:
			emitter.energy = 0.0
			if _rig != null and is_instance_valid(_rig):
				_rig.remove_emitter(emitter)
	_lights_in_rig = false


func _clear() -> void:
	_leave_rig()
	_settled = false
	for node: Node3D in _plumes:
		if is_instance_valid(node):
			remove_child(node)
			node.free()  # out of the tree already, so freeing at once is safe and leaves no orphan
	_plumes.clear()
	_cones.clear()
	_cores.clear()
	_bases.clear()
	_lengths.clear()
	_radii.clear()
	_levels.clear()
	_lights.clear()
	multimesh = null
	material_override = null
	_buffer.clear()
