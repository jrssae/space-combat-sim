class_name ThrusterVisuals
extends Node3D
## Thruster exhaust plumes (architecture §7.1): one per pod main nozzle, per pod retro nozzle and per cosmetic RCS
## nozzle. A plume is a `Node3D` at the nozzle's hardpoint position whose local +Y axis is the nozzle's `exhaust`
## direction, so it comes out of the nozzle and points the way the gas goes whatever the camera does (the glows used to
## be camera-facing billboards, which never read as coming out of a nozzle). It has two meshes:
##
## - `Cone`: an open, unshaded, additive cone with its base at the nozzle position, extending along `exhaust`, fading
##   to nothing at the far end (vertex alpha). Its length and radius scale with the level.
## - `Core`: a small soft disc at the nozzle exit, perpendicular to the exhaust, the hot spot you see when looking
##   straight into the nozzle.
##
## Meshes rather than splats because the intensity changes every frame; they are transparent, so they draw after the
## splats and are hidden behind the hull by the hull depth proxy (§7.2).
##
## Wiring (Main, M1-T15, does this; the node does not know the Ship class). Add the node as a child of the ship body
## so node-local is ship-local, then:
##
##     visuals.setup(layout, ship.get_flight_output)    # a Callable returning the latest FlightOutput, or null
##
## Each frame (`_process`) the levels come from the output through `ThrusterGlowLevels` (pod nozzles from the
## post-trim `main_levels` / `retro_levels`, RCS nozzles from the strongest of their tags), are smoothed with a
## first-order lag of `smoothing_s` (80 ms), and drive each plume's length and radius (proportional to level) and alpha
## (the instance `transparency`, 1 - level). A plume below `hide_below` is hidden. With no output (null) every plume
## fades out.
##
## The plumes are children of the ship and keep the default physics-interpolation mode, so they ride with the
## interpolated hull; only their scale and alpha change per frame, which is invisible next to a 16 ms tick.
## How it looks is (H).

const PLUME_MATERIAL: Material = preload("res://assets/materials/thruster_plume.tres")
const CORE_MATERIAL: Material = preload("res://assets/materials/thruster_glow.tres")
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
## Diameter of the core disc as a multiple of the plume radius.
const CORE_DIAMETER_PER_RADIUS: float = 2.6
## The plume radius at level 0 as a fraction of the radius at level 1 (plumes widen a little as they brighten).
const MIN_RADIUS_FRACTION: float = 0.6

## Full-level length of the cone, m, per kind of nozzle.
@export var main_length_m: float = 2.6
@export var retro_length_m: float = 1.5
@export var rcs_length_m: float = 0.6
## Full-level radius of the cone at the nozzle, m (the Starfury's bells are 0.5 m main, 0.25 m retro).
@export var main_radius_m: float = 0.4
@export var retro_radius_m: float = 0.2
@export var rcs_radius_m: float = 0.06
## Time constant of the level smoothing, s.
@export var smoothing_s: float = 0.08
## Plumes with a smoothed level under this are hidden.
@export var hide_below: float = 0.01

static var _cone_mesh: ArrayMesh = null
static var _core_mesh: QuadMesh = null

var _layout: ThrusterLayout = null
var _output_source: Callable = Callable()
var _plumes: Array[Node3D] = []
var _cones: Array[MeshInstance3D] = []
var _cores: Array[MeshInstance3D] = []
var _lengths: PackedFloat64Array = PackedFloat64Array()
var _radii: PackedFloat64Array = PackedFloat64Array()
var _levels: PackedFloat64Array = PackedFloat64Array()


func _process(delta: float) -> void:
	advance(delta)


## Called by Main with the ship's thruster layout and a Callable returning the latest `FlightOutput` (or null).
## Builds the plumes, replacing any from an earlier call. An unusable layout leaves the node empty with a warning.
func setup(layout: ThrusterLayout, output_source: Callable) -> void:
	_clear()
	_output_source = output_source
	_layout = layout
	if layout == null or not layout.valid:
		push_warning("ThrusterVisuals.setup: no usable thruster layout (%s)" % ("none" if layout == null else layout.error))
		_layout = null
		return
	for i: int in layout.nozzle_count():
		var is_main: bool = ThrusterLayout.is_main_group(layout.nozzle_groups[i])
		_add_plume(POD_PREFIX + layout.nozzle_names[i], layout.nozzle_positions[i], layout.nozzle_exhausts[i],
				main_length_m if is_main else retro_length_m, main_radius_m if is_main else retro_radius_m)
	for entry: Dictionary in layout.rcs_nozzles:
		_add_plume(RCS_PREFIX + str(entry["name"]), entry["position"], entry["exhaust"], rcs_length_m, rcs_radius_m)


## Number of plumes: every pod nozzle plus every RCS nozzle.
func glow_count() -> int:
	return _plumes.size()


## The plume node at `index` (pod nozzles in `ThrusterLayout` order, then RCS nozzles in hardpoint order). Its
## position is the nozzle position and its local +Y axis the exhaust direction; `Cone` and `Core` are its children.
func glow(index: int) -> Node3D:
	return _plumes[index]


## The cone mesh node of the plume at `index`.
func cone(index: int) -> MeshInstance3D:
	return _cones[index]


## The core disc node of the plume at `index`.
func core(index: int) -> MeshInstance3D:
	return _cores[index]


## Smoothed level 0..1 of the plume at `index`; what its length, radius and alpha are drawn from.
func glow_level(index: int) -> float:
	return _levels[index]


## Reads the output and moves every plume `delta` seconds along its smoothing. `_process` calls it each frame; public
## so tests can step it with a chosen `delta`.
func advance(delta: float) -> void:
	if _layout == null:
		return
	var output: FlightOutput = null
	if _output_source.is_valid():
		output = _output_source.call() as FlightOutput
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(_layout, output)
	for i: int in _plumes.size():
		_levels[i] = ThrusterGlowLevels.smooth(_levels[i], targets[i], delta, smoothing_s)
		_apply(i)


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


func _add_plume(plume_name: String, at: Vector3, exhaust: Vector3, length: float, radius: float) -> void:
	var plume := Node3D.new()
	plume.name = plume_name
	plume.transform = Transform3D(plume_basis(exhaust), at)
	plume.visible = false

	var cone_node := MeshInstance3D.new()
	cone_node.name = CONE_NAME
	cone_node.mesh = cone_mesh()
	cone_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.add_child(cone_node)

	var core_node := MeshInstance3D.new()
	core_node.name = CORE_NAME
	core_node.mesh = core_mesh()
	core_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core_node.position = Vector3(0.0, CORE_OFFSET_M, 0.0)
	core_node.rotation = Vector3(-PI / 2.0, 0.0, 0.0)  # the quad faces +Z; turn it to face along the plume's +Y
	plume.add_child(core_node)

	add_child(plume)
	_plumes.append(plume)
	_cones.append(cone_node)
	_cores.append(core_node)
	_lengths.append(length)
	_radii.append(radius)
	_levels.append(0.0)


func _apply(index: int) -> void:
	var level: float = _levels[index]
	# Never exactly zero: a singular transform would trip the engine's matrix checks even while hidden.
	var shown: float = maxf(level, hide_below)
	var radius: float = _radii[index] * lerpf(MIN_RADIUS_FRACTION, 1.0, shown)
	_plumes[index].visible = level >= hide_below
	_cones[index].scale = Vector3(radius, _lengths[index] * shown, radius)
	_cones[index].transparency = 1.0 - level
	_cores[index].scale = Vector3.ONE * (radius * CORE_DIAMETER_PER_RADIUS)
	_cores[index].transparency = 1.0 - level


func _clear() -> void:
	for node: Node3D in _plumes:
		if is_instance_valid(node):
			remove_child(node)
			node.free()  # out of the tree already, so freeing at once is safe and leaves no orphan
	_plumes.clear()
	_cones.clear()
	_cores.clear()
	_lengths.clear()
	_radii.clear()
	_levels.clear()
