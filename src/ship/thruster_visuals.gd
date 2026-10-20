class_name ThrusterVisuals
extends Node3D
## Thruster glow (architecture §7.1): one additive billboard quad per pod main nozzle, per pod retro nozzle and per
## cosmetic RCS nozzle, at the hardpoint positions. Meshes rather than splats because the intensity changes every
## frame; the Forward+ transparent pass draws them after the splats, so a glow inside the hull still shows.
##
## Wiring (Main, M1-T15, does this; the node does not know the Ship class). Add the node as a child of the ship body
## so node-local is ship-local, then:
##
##     visuals.setup(layout, ship.get_flight_output)    # a Callable returning the latest FlightOutput, or null
##
## Each frame (`_process`) the glow levels come from the output through `ThrusterGlowLevels` (pod nozzles from the
## post-trim `main_levels` / `retro_levels`, RCS nozzles from the strongest of their tags), are smoothed with a
## first-order lag of `smoothing_s` (80 ms), and drive each quad's scale (proportional to level) and alpha
## (the instance `transparency`, 1 - level). A glow below `hide_below` is hidden. With no output (null) every glow
## fades out.
##
## The quads are children of the ship and keep the default physics-interpolation mode, so they ride with the
## interpolated hull; only their scale and alpha change per frame, which is invisible next to a 16 ms tick.
## How it looks is (H).

const MATERIAL: Material = preload("res://assets/materials/thruster_glow.tres")
const POD_PREFIX: String = "Glow_"
const RCS_PREFIX: String = "GlowRcs_"

## Full-size edge length of the glow quad, m.
@export var main_size_m: float = 2.4
@export var retro_size_m: float = 1.2
@export var rcs_size_m: float = 0.5
## Time constant of the level smoothing, s.
@export var smoothing_s: float = 0.08
## Glows with a smoothed level under this are hidden.
@export var hide_below: float = 0.01

var _layout: ThrusterLayout = null
var _output_source: Callable = Callable()
var _quad: QuadMesh = null
var _glows: Array[MeshInstance3D] = []
var _sizes: PackedFloat64Array = PackedFloat64Array()
var _levels: PackedFloat64Array = PackedFloat64Array()


func _process(delta: float) -> void:
	advance(delta)


## Called by Main with the ship's thruster layout and a Callable returning the latest `FlightOutput` (or null).
## Builds the glows, replacing any from an earlier call. An unusable layout leaves the node empty with a warning.
func setup(layout: ThrusterLayout, output_source: Callable) -> void:
	_clear()
	_output_source = output_source
	_layout = layout
	if layout == null or not layout.valid:
		push_warning("ThrusterVisuals.setup: no usable thruster layout (%s)" % ("none" if layout == null else layout.error))
		_layout = null
		return
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_quad.material = MATERIAL
	for i: int in layout.nozzle_count():
		var size: float = main_size_m if ThrusterLayout.is_main_group(layout.nozzle_groups[i]) else retro_size_m
		_add_glow(POD_PREFIX + layout.nozzle_names[i], layout.nozzle_positions[i], size)
	for entry: Dictionary in layout.rcs_nozzles:
		_add_glow(RCS_PREFIX + str(entry["name"]), entry["position"], rcs_size_m)


## Number of glows: every pod nozzle plus every RCS nozzle.
func glow_count() -> int:
	return _glows.size()


## The glow node at `index` (pod nozzles in `ThrusterLayout` order, then RCS nozzles in hardpoint order).
func glow(index: int) -> MeshInstance3D:
	return _glows[index]


## Smoothed level 0..1 of the glow at `index`; what its scale and alpha are drawn from.
func glow_level(index: int) -> float:
	return _levels[index]


## Reads the output and moves every glow `delta` seconds along its smoothing. `_process` calls it each frame; public
## so tests can step it with a chosen `delta`.
func advance(delta: float) -> void:
	if _layout == null:
		return
	var output: FlightOutput = null
	if _output_source.is_valid():
		output = _output_source.call() as FlightOutput
	var targets: PackedFloat64Array = ThrusterGlowLevels.targets(_layout, output)
	for i: int in _glows.size():
		_levels[i] = ThrusterGlowLevels.smooth(_levels[i], targets[i], delta, smoothing_s)
		_apply(i)


func _add_glow(glow_name: String, at: Vector3, size: float) -> void:
	var node := MeshInstance3D.new()
	node.name = glow_name
	node.mesh = _quad
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	_glows.append(node)
	_sizes.append(size)
	_levels.append(0.0)


func _apply(index: int) -> void:
	var level: float = _levels[index]
	var node: MeshInstance3D = _glows[index]
	node.visible = level >= hide_below
	# Never exactly zero: a singular transform would trip the engine's matrix checks even while hidden.
	node.scale = Vector3.ONE * (_sizes[index] * maxf(level, hide_below))
	node.transparency = 1.0 - level


func _clear() -> void:
	for node: MeshInstance3D in _glows:
		if is_instance_valid(node):
			remove_child(node)
			node.free()  # out of the tree already, so freeing at once is safe and leaves no orphan
	_glows.clear()
	_sizes.clear()
	_levels.clear()
