class_name WirePreview
extends SubViewport
## The target preview's drawing (architecture §18.20, M5-T43): one hull as green lines on nothing, turning slowly, in a world of
## its own so nothing of the game leaks in. Per part two draws, the solid mesh for depth (`wire_solid`) and its feature edges
## tested against it (`wire_lines`), so the far side's lines are hidden; then one pass over the view outlines the hull from its
## depth (`wire_outline`), for rounded hulls with no crease at their outline. It renders only while `live`; otherwise the
## viewport is `UPDATE_DISABLED` and the node does not process. A mesh's edges are found once (`FeatureEdgeJob`, a slice a
## frame) and kept for the session.

const SOLID_SHADER: Shader = preload("res://assets/shaders/wire_solid.gdshader")
const LINES_SHADER: Shader = preload("res://assets/shaders/wire_lines.gdshader")
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/wire_outline.gdshader")
## What a frame may spend on finding edges, microseconds.
const BUILD_BUDGET_USEC: int = 2000
## The lines come toward the camera by this share of the hull's radius, and a depth step of this share is an outline.
const PULL_SHARE: float = 0.006
const OUTLINE_STEP_SHARE: float = 0.03

## The hull showing: its key (an asset id, with its pod count), "" for none.
var hull_key: String = ""
## Lines drawn for it, and whether some of its parts are still being worked out.
var edge_count: int = 0
var building: bool = false
## What finding the last hull's edges took in all, and the longest slice of it, milliseconds; and the frames it was spread over.
var last_build_ms: float = 0.0
var last_build_max_slice_ms: float = 0.0
var last_build_frames: int = 0
var live: bool = false

# Mesh instance id -> {"mesh": Mesh (kept alive), "lines": ArrayMesh, "edges": int}: every hull whose edges have been found.
static var _edges: Dictionary = {}

var _pivot: Node3D = null
var _holder: Node3D = null
var _camera: Camera3D = null
var _outline: MeshInstance3D = null
var _solid_material: ShaderMaterial = null
var _lines_material: ShaderMaterial = null
var _outline_material: ShaderMaterial = null
var _parts: Array[Dictionary] = []  # {"mesh": Mesh, "solid": MeshInstance3D, "lines": MeshInstance3D}
var _job: FeatureEdgeJob = null
var _job_mesh: Mesh = null
var _bounds := AABB()
var _shown_s: float = 0.0
var _build_usec: int = 0
var _build_max_usec: int = 0
var _build_frames: int = 0


## Hulls whose edges are kept.
static func cache_size() -> int:
	return _edges.size()


## Forgets every hull's edges (tests).
static func clear_cache() -> void:
	_edges.clear()


func _init() -> void:
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_4X
	# The whole mesh, never the importer's coarser levels: the lines are found on it and must lie on its faces.
	mesh_lod_threshold = 0.0
	positional_shadow_atlas_size = 0
	size = Vector2i(256, 256)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_solid_material = ShaderMaterial.new()
	_solid_material.shader = SOLID_SHADER
	_lines_material = ShaderMaterial.new()
	_lines_material.shader = LINES_SHADER
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_holder = Node3D.new()
	_holder.name = "Hull"
	_pivot.add_child(_holder)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(_camera)
	_camera.current = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_outline = MeshInstance3D.new()
	_outline.name = "Outline"
	_outline.mesh = quad
	_outline.material_override = _outline_material
	_outline.extra_cull_margin = 16384.0
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_camera.add_child(_outline)
	set_colors(Factions.HUD_LINE_COLOR)
	set_live(false)


## The lines' colour; the ground is a dark shade of it.
func set_colors(line: Color) -> void:
	_lines_material.set_shader_parameter(&"line_color", line)
	_outline_material.set_shader_parameter(&"line_color", line)
	_solid_material.set_shader_parameter(&"ground", Color(line.r * 0.03, line.g * 0.07, line.b * 0.06, 1.0))


## Renders and turns while on; off, nothing of it runs.
func set_live(on: bool) -> void:
	live = on
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)


## Shows a hull: `parts` are its meshes in the hull's frame (`{mesh, transform}`, the hull first, then what is mounted on
## it), `key` names it. The turn starts over.
func show_hull(key: String, parts: Array[Dictionary]) -> void:
	clear()
	hull_key = key
	_bounds = AABB()
	for part: Dictionary in parts:
		var mesh: Mesh = part.get("mesh")
		if mesh == null:
			continue
		var at: Transform3D = part.get("transform", Transform3D.IDENTITY)
		var solid := MeshInstance3D.new()
		solid.mesh = mesh
		solid.transform = at
		solid.material_override = _solid_material
		solid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_holder.add_child(solid)
		var lines := MeshInstance3D.new()
		lines.transform = at
		lines.material_override = _lines_material
		lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_holder.add_child(lines)
		_parts.append({"mesh": mesh, "solid": solid, "lines": lines})
		var box: AABB = at * mesh.get_aabb()
		_bounds = box if _parts.size() == 1 else _bounds.merge(box)
	_frame()
	_build_usec = 0
	_build_max_usec = 0
	_build_frames = 0
	_assign_lines()


## Shows nothing.
func clear() -> void:
	for part: Dictionary in _parts:
		(part["solid"] as Node).queue_free()
		(part["lines"] as Node).queue_free()
	_parts.clear()
	_job = null
	_job_mesh = null
	building = false
	hull_key = ""
	edge_count = 0
	_shown_s = 0.0


func has_hull() -> bool:
	return not _parts.is_empty()


## The hull's yaw now, radians.
func yaw() -> float:
	return _pivot.rotation.y if _pivot != null else 0.0


func _process(delta: float) -> void:
	_shown_s += delta
	_pivot.rotation.y = WireFraming.yaw_at(_shown_s)
	if _camera != null and size.y > 0:
		_camera.size = WireFraming.view_height(_bounds, float(size.x) / float(size.y))
	if building:
		_work()


# The camera stands off the hull's centre and the depth range holds just the hull, whatever its size.
func _frame() -> void:
	_holder.position = -_bounds.get_center()
	_pivot.rotation.y = WireFraming.yaw_at(0.0)
	var r: float = WireFraming.radius(_bounds)
	_camera.position = WireFraming.camera_offset(2.0 * r)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.near = 0.8 * r
	_camera.far = 3.2 * r
	_camera.size = WireFraming.view_height(_bounds, float(size.x) / float(maxi(size.y, 1)))
	_lines_material.set_shader_parameter(&"pull_m", PULL_SHARE * r)
	_outline_material.set_shader_parameter(&"step_m", OUTLINE_STEP_SHARE * r)


# Gives every part the lines already found and starts on the first part without them.
func _assign_lines() -> void:
	edge_count = 0
	building = false
	for part: Dictionary in _parts:
		var mesh: Mesh = part["mesh"]
		var known: Dictionary = _edges.get(mesh.get_instance_id(), {})
		if known.is_empty():
			if not building:
				building = true
				_job_mesh = mesh
				_job = null
			continue
		(part["lines"] as MeshInstance3D).mesh = known["lines"]
		edge_count += int(known["edges"])


# One frame's slice of the edge search; a finished mesh's lines are kept and drawn.
func _work() -> void:
	var started: int = Time.get_ticks_usec()
	if _job == null:
		_job = FeatureEdgeJob.for_mesh(_job_mesh)  # reading the mesh back is its own slice
	else:
		_job.step(BUILD_BUDGET_USEC)
	var spent: int = Time.get_ticks_usec() - started
	_build_usec += spent
	_build_max_usec = maxi(_build_max_usec, spent)
	_build_frames += 1
	if not _job.done:
		return
	var lines: PackedVector3Array = _job.lines()
	@warning_ignore("integer_division")
	_edges[_job_mesh.get_instance_id()] = {"mesh": _job_mesh, "lines": FeatureEdges.line_mesh(lines), "edges": lines.size() / 2}
	_job = null
	_job_mesh = null
	_assign_lines()
	if not building:
		last_build_ms = float(_build_usec) / 1000.0
		last_build_max_slice_ms = float(_build_max_usec) / 1000.0
		last_build_frames = _build_frames
