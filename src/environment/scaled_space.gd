class_name ScaledSpace
extends Node3D
## The scaled-space layer (M6-T10, D68): the star and the planets, drawn where they truly are in the sky and as large as they
## truly look, from anywhere in the local space and after any rebase. Each body is a small stand-in sphere a few km from the
## camera (`ScaledPlacement`), re-placed every frame from the ephemeris at sim time and the drawn camera, so no far position
## reaches the GPU. The layer shares the near world's camera and pass; its shader pins its depth just in front of the far
## plane, behind every near thing (the measured choice, M6-T10's Done notes).
##
## It also answers what the light needs: the true direction to the star and how much of its disc a planet leaves showing at
## the camera (`key_light`), which `SpaceEnvironment` puts on the `KeyStar`.
##
## The World is the one the current camera is in (`WorldFrame.of`), so nothing here assumes one frame (D71). With no star
## system on that World nothing is drawn and the light is left alone.
##
## Console (§6.4): provider `scaled`, command `scaled`. The look of the stand-ins is M6-T11's and T12's; (H).

const SHADER_PATH: String = "res://assets/shaders/scaled_body.gdshader"
## Runs after the camera rig has moved the cameras this frame, as the sky does.
const LATE_PRIORITY: int = 1000
## Until scenarios seed their epoch (M6-T09, Q9), the layer looks at the system this much later than the sim clock: at the
## data's epoch 0 the station sits in the middle of the planet's shadow, and a third of its orbit on it has the sun and a
## gibbous planet. `scaled epoch` moves it.
const STAND_IN_EPOCH_S: float = 23_300.0
const PLANET_COLOUR: Color = Color(0.55, 0.36, 0.25)
## How bright the star's disc is drawn against a lit surface's 1.
const STAR_BRIGHTNESS: float = 8.0
const SPHERE_SEGMENTS: int = 128
const ACTIONS: PackedStringArray = ["status", "epoch", "show", "hide"]

## Added to the sim clock before the ephemeris is asked, s.
var epoch_offset_s: float = STAND_IN_EPOCH_S

var _system: StarSystem = null
var _spheres: Dictionary = {}  # StringName -> MeshInstance3D
var _placements: Dictionary = {}  # StringName -> ScaledPlacement
var _star: StringName = &""
var _sun_direction: Vector3 = Vector3.UP
var _has_sun: bool = false
var _key_light: float = 1.0
var _mesh: SphereMesh = null
var _shader: Shader = null


func _init() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = LATE_PRIORITY


func _ready() -> void:
	DebugConsole.registry.register_provider(&"scaled", ConsoleVars.new({
		&"bodies": {"get": drawn_count, "doc": "Far bodies drawn on the scaled-space layer this frame"},
		&"layout": {"get": _layout_text, "doc": "Each body: angular size, direction from the camera (game axes), true distance and where its stand-in is drawn"},
		&"has_sun": {"get": has_sun, "doc": "Whether the World has a star system, so the key light follows the true sun"},
		&"sun_direction": {"get": sun_direction, "doc": "Unit vector from the camera to the star, game axes"},
		&"key_light": {"get": key_light, "doc": "The part of the star's disc no planet hides at the camera, 0 to 1: the key light's factor"},
		&"epoch_h": {"get": func() -> float: return epoch_offset_s / 3600.0, "unit": "h",
				"doc": "How much later than the sim clock the layer looks at the system (a stand-in until scenarios set an epoch)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"scaled",
			"The scaled-space layer (M6-T10): status, epoch <hours> (look at the system that much later than the sim clock, to move the sun and the planet's phase for captures), show or hide (draw the far bodies or not, to measure them)",
			[ConsoleArg.enum_optional(&"action", ACTIONS), ConsoleArg.float_optional(&"hours")]), _cmd_scaled, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _process(_delta: float) -> void:
	refresh(get_viewport().get_camera_3d())


## Places every body for `camera` now. `_process` calls it; public for the tests.
func refresh(camera: Camera3D) -> void:
	var world: WorldFrame = WorldFrame.of(camera) if camera != null else null
	var system: StarSystem = world.star_system if world != null else null
	if system == null or not system.is_valid() or world.anchor_name == &"":
		_clear()
		return
	if system != _system:
		_build(system)
	var time_s: float = SimClock.now() + epoch_offset_s
	var view: Transform3D = camera.get_global_transform_interpolated()
	var eye: PackedFloat64Array = ScaledPlacement.camera_from_anchor(world.origin, view.origin)
	var places: Dictionary = {}
	for id: StringName in system.body_ids:
		places[id] = body_from_anchor(world, id, time_s)
	var to_star: PackedFloat64Array = _from(eye, places.get(_star, PackedFloat64Array()))
	_has_sun = to_star.size() == 3
	_key_light = 1.0
	for id: StringName in system.body_ids:
		var at: PackedFloat64Array = places[id]
		var sphere: MeshInstance3D = _spheres[id]
		if at.size() < 3:
			sphere.visible = false
			_placements.erase(id)
			continue
		var radius_m: float = float(system.info(id)["radius_m"])
		var placed: ScaledPlacement = ScaledPlacement.place(eye, at, radius_m)
		_placements[id] = placed
		if id == _star:
			_sun_direction = placed.direction
		elif _has_sun:
			_key_light = minf(_key_light, EclipseMath.lit_fraction(to_star, float(system.info(_star)["radius_m"]),
					_from(eye, at), radius_m))
		sphere.visible = true
		sphere.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * placed.radius), view.origin + placed.offset)
		var material: ShaderMaterial = sphere.material_override as ShaderMaterial
		material.set_shader_parameter(&"layer_depth", placed.depth)
	if _has_sun:
		for id: StringName in system.body_ids:
			# Each body is lit from where the star is seen from it, not from the camera.
			var lit_from: PackedFloat64Array = _from(places[id], places[_star])
			if id != _star and lit_from.size() == 3:
				(_spheres[id].material_override as ShaderMaterial).set_shader_parameter(&"sun_direction", _unit(lit_from))


## Where body `id` is from the World's anchor at `time_s`: three numbers, m, game axes; empty when it cannot be told.
## A place on a rail sees the body straight from the ephemeris; a free-falling anchor is held against its home body.
static func body_from_anchor(world: WorldFrame, id: StringName, time_s: float) -> PackedFloat64Array:
	var system: StarSystem = world.star_system
	if system == null or not system.has_id(id) or not system.has_id(world.anchor_name):
		return PackedFloat64Array()
	if system.place_ids.has(world.anchor_name):
		var seen: PackedFloat64Array = system.relative_state(id, world.anchor_name, time_s)
		return ScaledPlacement.to_game(seen) if seen.size() >= 3 else PackedFloat64Array()
	var anchor: PackedFloat64Array = world.anchor_state()
	if anchor.size() < 3:
		return PackedFloat64Array()
	if id == world.anchor_name:
		return PackedFloat64Array([-anchor[0], -anchor[1], -anchor[2]])
	var from_home: PackedFloat64Array = system.relative_state(id, world.anchor_name, time_s)
	if from_home.size() < 3:
		return PackedFloat64Array()
	var home: PackedFloat64Array = ScaledPlacement.to_game(from_home)
	return PackedFloat64Array([home[0] - anchor[0], home[1] - anchor[1], home[2] - anchor[2]])


## How many bodies are drawn this frame.
func drawn_count() -> int:
	return _placements.size() if visible else 0


## The placement of body `id` this frame, or null when it is not drawn.
func placement_of(id: StringName) -> ScaledPlacement:
	return _placements.get(id) as ScaledPlacement


## The stand-in sphere of body `id`, or null.
func sphere_of(id: StringName) -> MeshInstance3D:
	return _spheres.get(id) as MeshInstance3D


func has_sun() -> bool:
	return _has_sun


## Unit vector from the camera to the star, game axes; meaningful while `has_sun()`.
func sun_direction() -> Vector3:
	return _sun_direction


## The part of the star's disc no planet hides at the camera, 0 to 1.
func key_light() -> float:
	return _key_light


# One sphere per body of `system`; the star's is the one that glows, in the star's own colour.
func _build(system: StarSystem) -> void:
	for sphere: MeshInstance3D in _spheres.values():
		sphere.queue_free()
	_spheres.clear()
	_placements.clear()
	_system = system
	_star = &""
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 1.0
		_mesh.height = 2.0
		_mesh.radial_segments = SPHERE_SEGMENTS
		_mesh.rings = SPHERE_SEGMENTS / 2
		_shader = load(SHADER_PATH) as Shader
	for id: StringName in system.body_ids:
		var is_star: bool = system.info(id)["kind"] == &"star"
		if is_star and _star == &"":
			_star = id
		var material := ShaderMaterial.new()
		material.shader = _shader
		material.set_shader_parameter(&"glows", 1.0 if is_star else 0.0)
		material.set_shader_parameter(&"brightness", STAR_BRIGHTNESS if is_star else 1.0)
		material.set_shader_parameter(&"colour",
				StarColor.linear_from_kelvin(StarCatalog.temperature_k(system.id)).linear_to_srgb() if is_star else PLANET_COLOUR)
		var sphere := MeshInstance3D.new()
		sphere.name = String(id).to_pascal_case()
		sphere.mesh = _mesh
		sphere.material_override = material
		sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sphere.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		sphere.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(sphere)
		_spheres[id] = sphere


# No star system in view: nothing drawn, the light left as the scene made it.
func _clear() -> void:
	if _placements.is_empty() and not _has_sun:
		return
	for sphere: MeshInstance3D in _spheres.values():
		sphere.visible = false
	_placements.clear()
	_has_sun = false
	_key_light = 1.0


static func _from(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	if a.size() < 3 or b.size() < 3:
		return PackedFloat64Array()
	return PackedFloat64Array([b[0] - a[0], b[1] - a[1], b[2] - a[2]])


static func _unit(v: PackedFloat64Array) -> Vector3:
	var length: float = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	return Vector3(v[0] / length, v[1] / length, v[2] / length) if length > 0.0 else Vector3.UP


func _layout_text() -> String:
	var lines := PackedStringArray()
	for id: StringName in _placements:
		var placed: ScaledPlacement = _placements[id]
		lines.append("%s %.3f deg dir (%.4f, %.4f, %.4f) at %.1f km drawn %.0f m r %.1f m" % [id, placed.angular_size_deg(),
				placed.direction.x, placed.direction.y, placed.direction.z, placed.distance_m / 1000.0, placed.offset.length(),
				placed.radius])
	return "; ".join(lines) if visible else "hidden"


func _cmd_scaled(args: Dictionary) -> ConsoleResult:
	var action: StringName = StringName(args[&"action"]) if args[&"action"] != null else &"status"
	match action:
		&"epoch":
			if args[&"hours"] == null:
				return ConsoleResult.failure("scaled epoch: give the hours to look ahead of the sim clock")
			epoch_offset_s = float(args[&"hours"]) * 3600.0
		&"show":
			visible = true
		&"hide":
			visible = false
	refresh(get_viewport().get_camera_3d())
	return ConsoleResult.line("scaled: %d bodies; epoch +%.2f h; key light %.3f; %s" % [drawn_count(), epoch_offset_s / 3600.0,
			_key_light, _layout_text()])
