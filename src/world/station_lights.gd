class_name StationLights
extends Node
## Babylon 5's exterior lights (M7-T18), from its light hardpoints (`StationLightPlan`): the beacons, navigation lights and bay lamps
## as soft points on the hull (instanced, one draw call a group), the beacons fading in and out by the system's sim time, and the floods that
## light the hull in pools, summed in the hull shader. Each hull section gets its own copy of its material holding only the floods
## that can reach it; those on the other piece (a drum flood over the frame, a frame flood over the drum) follow the drum's turn every
## frame. No light node and no light slot: the bays' real lamps stay `BayLights`'. Console: provider and command `station_lights`.

const PROVIDER: StringName = &"station_lights"
const MARKER_SHADER: Shader = preload("res://assets/shaders/station_light_marker.gdshader")
const ACTIONS: Array[StringName] = [&"status", &"on", &"off"]
## The marker shader's gain at full brightness (`station_light_marker.gdshader`).
const MARKER_GAIN: float = 4.0

var plan: StationLightPlan = null
## The point groups' nodes, by `StationLightPlan` group.
var groups: Dictionary = {}
## Each lit hull section: `node`, `body`, `materials` (its own copies), `fixed` and `turning` (flood indices).
var sections: Array[Dictionary] = []
## Whether the lights are shown (the console's on and off, for A/B sheets).
var shown: bool = true
var _station: Station = null
var _drum_basis: Basis = Basis()
var _first_frame: bool = true


## The lights of `station`'s hardpoints, or null when they list none.
static func make(station: Station) -> StationLights:
	var made_plan: StationLightPlan = StationLightPlan.from_hardpoints(station.hardpoints)
	if made_plan.floods.is_empty() and made_plan.point_count() == 0:
		return null
	var made := StationLights.new()
	made.name = "StationLights"
	made.plan = made_plan
	made._station = station
	made._build_points()
	made._build_sections()
	return made


func _ready() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"points": {"get": plan.point_count, "doc": "Beacons, navigation lights and bay lamps drawn as points"},
		&"floods": {"get": func() -> int: return plan.floods.size(), "doc": "Floods lighting the hull"},
		&"lit_sections": {"get": func() -> int: return sections.size(), "doc": "Hull sections with floods of their own"},
		&"max_section_floods": {"get": max_section_floods, "doc": "The most floods any one section sums (the shader holds 64)"},
		&"turning_floods": {"get": turning_count, "doc": "Floods carried round by the drum's turn over the other piece, all sections"},
		&"beacons_lit": {"get": beacons_lit, "doc": "The beacons show now (any part of their fade, sim time)"},
		&"beacon_level": {"get": beacon_level, "doc": "The beacons' brightness now, 0 to 1 (4 s: dark, fade up, full, fade down)"},
		&"shown": {"get": func() -> bool: return shown, "doc": "The lights are drawn (station_lights on|off)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"station_lights",
			"Babylon 5's exterior lights: status, on, off (beacons, navigation lights, bay lamps and floods; for A/B captures)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status")] as Array[ConsoleArg]), _cmd_station_lights, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _process(_delta: float) -> void:
	if _station == null or _station.drum_pivot == null:
		return
	# Brightness only: the points' visibility belongs to the far prop, which hides them once the station is a dot (M7-T69).
	var level: float = beacon_level() if shown else 0.0
	for group: StringName in [StationLightPlan.FRAME_BLINK, StationLightPlan.DRUM_BLINK]:
		if groups.has(group):
			_set_gain(group, MARKER_GAIN * level)
	var basis: Basis = _station.drum_pivot.transform.basis
	if not shown or (not _first_frame and basis.is_equal_approx(_drum_basis)):
		return
	_drum_basis = basis
	_first_frame = false
	var drum_xform: Transform3D = _station.drum_pivot.transform
	for section: Dictionary in sections:
		if not (section["turning"] as PackedInt32Array).is_empty():
			_apply(section, drum_xform)


## Shows or hides every light (points and floods).
func set_shown(on: bool) -> void:
	shown = on
	for group: StringName in groups:
		_set_gain(group, MARKER_GAIN if on else 0.0)  # a dark point is not drawn (the marker shader's cull)
	for section: Dictionary in sections:
		if on:
			_apply(section, _station.drum_pivot.transform)
		else:
			for material: ShaderMaterial in section["materials"]:
				material.set_shader_parameter(&"flood_count", 0)
	_first_frame = true


## A point group's brightness (`station_light_marker.gdshader`'s gain).
func gain_of(group: StringName) -> float:
	var node := groups.get(group) as MultiMeshInstance3D
	var gain: Variant = _material_of(node).get_shader_parameter(&"gain") if node != null else 0.0
	return float(gain) if gain != null else MARKER_GAIN


func beacons_lit() -> bool:
	return beacon_level() > 0.0


## The beacons' brightness now, 0 to 1.
func beacon_level() -> float:
	return plan.beacon_level(_system_time())


func max_section_floods() -> int:
	var most: int = 0
	for section: Dictionary in sections:
		most = maxi(most, (section["fixed"] as PackedInt32Array).size() + (section["turning"] as PackedInt32Array).size())
	return most


func turning_count() -> int:
	var n: int = 0
	for section: Dictionary in sections:
		n += (section["turning"] as PackedInt32Array).size()
	return n


func _set_gain(group: StringName, gain: float) -> void:
	_material_of(groups[group] as MultiMeshInstance3D).set_shader_parameter(&"gain", gain)


static func _material_of(node: MultiMeshInstance3D) -> ShaderMaterial:
	return (node.multimesh.mesh as QuadMesh).material as ShaderMaterial


# The system's sim time (as the drum's turn takes it), never the wall clock.
func _system_time() -> float:
	var world: WorldFrame = WorldFrame.of(_station) if _station != null and _station.is_inside_tree() else null
	return world.system_time() if world != null else SimClock.now()


# One instanced mesh a point group, under the piece that carries it, so the drum's points turn with it and the far field's shrink
# carries them all.
func _build_points() -> void:
	for group: StringName in plan.points:
		var list: Array = plan.points[group]
		if list.is_empty():
			continue
		var material := ShaderMaterial.new()
		material.shader = MARKER_SHADER
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = material
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = quad
		multimesh.instance_count = list.size()
		for i: int in list.size():
			var point: Dictionary = list[i]
			var c: Color = point["colour"]
			multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, point["position"] as Vector3))
			multimesh.set_instance_custom_data(i, Color(c.r, c.g, c.b, float(point["radius_m"])))
		var node := MultiMeshInstance3D.new()
		node.name = "Lights_%s" % String(group).to_pascal_case()
		node.multimesh = multimesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		node.extra_cull_margin = 16384.0  # the points keep a pixel floor, so they show past their mesh's box
		var drum: bool = group == StationLightPlan.DRUM_STEADY or group == StationLightPlan.DRUM_BLINK
		(_station.drum_pivot if drum else _station.frame_piece as Node3D).add_child(node)
		groups[group] = node


# Each hull section that some flood reaches gets its own material copies and its list; the rest keep the shared materials, which
# carry none (so do the halls' and bays' inner faces, which are separate meshes on the shared materials).
func _build_sections() -> void:
	var rest := Transform3D(Basis.IDENTITY, _station.drum_origin)
	for pair: Array in [[_station.frame_piece, StationHardpoints.FRAME], [_station.drum_piece, StationHardpoints.DRUM]]:
		var piece: RenderPiece = pair[0]
		if piece == null or piece.sections == null:
			continue
		for s: Dictionary in piece.sections.sections:
			var node: MeshInstance3D = piece.section_node(String(s["name"]))
			if node == null or node.mesh == null:
				continue
			var box: AABB = Transform3D(Basis.IDENTITY, node.position) * node.mesh.get_aabb()
			var lists: Dictionary = plan.section_floods(pair[1], box, _station.drum_origin)
			if (lists["fixed"] as PackedInt32Array).is_empty() and (lists["turning"] as PackedInt32Array).is_empty():
				continue
			var materials: Array[ShaderMaterial] = []
			for k: int in node.mesh.get_surface_count():
				var shared := node.mesh.surface_get_material(k) as ShaderMaterial
				if shared == null or shared.shader != StationHullMaterial.SHADER:
					continue
				var own: ShaderMaterial = StationHullMaterial.copy_of(shared)
				node.set_surface_override_material(k, own)
				materials.append(own)
			if materials.is_empty():
				continue
			var section: Dictionary = {"node": node, "body": pair[1], "materials": materials, "fixed": lists["fixed"],
					"turning": lists["turning"]}
			sections.append(section)
			_apply(section, rest)


# A section's floods into its materials, the drum standing at `drum_xform`.
func _apply(section: Dictionary, drum_xform: Transform3D) -> void:
	var indices: PackedInt32Array = (section["fixed"] as PackedInt32Array) + (section["turning"] as PackedInt32Array)
	var count: int = mini(indices.size(), StationLightPlan.MAX_FLOODS)
	var packed: Array[PackedVector4Array] = plan.pack(String(section["body"]), indices.slice(0, count), drum_xform)
	for material: ShaderMaterial in section["materials"]:
		material.set_shader_parameter(&"flood_count", count)
		material.set_shader_parameter(&"flood_pos", packed[0])
		material.set_shader_parameter(&"flood_dir", packed[1])
		material.set_shader_parameter(&"flood_col", packed[2])


func _cmd_station_lights(args: Dictionary) -> ConsoleResult:
	match StringName(args[&"action"]):
		&"on":
			set_shown(true)
		&"off":
			set_shown(false)
	return ConsoleResult.line("station lights %s: %d points, %d floods over %d sections (at most %d a section, %d following the drum)" % [
			"on" if shown else "off", plan.point_count(), plan.floods.size(), sections.size(), max_section_floods(), turning_count()])
