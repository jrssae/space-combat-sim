class_name RenderPiece
extends Node3D
## One big stand-in piece drawn either way (M4-T27, Q24, architecture §17.16): a chain of splat levels or the painted mesh of the same
## surface, from a generator's piece entry (`tools/procgen/core/pieces.py`: `lods` with their centroids, `paint_mesh`). The station's
## drum and frame and the capital hulls of the render comparison are pieces.
##
## While splats are drawn it shows one level, the coarsest whose spacing still projects to at most `MAX_SPACING_PX` at the piece's
## nearest point, so a station seen from 15 km draws a few thousand splats and from 1 km its full detail. The mesh's own levels are
## the engine's (the importer built them).

## The splat spacing a level may project to on screen, px, before a finer level is shown.
const MAX_SPACING_PX: float = 2.0

enum Look { SPLAT, MESH }

var look: Look = Look.SPLAT
## Each level's spacing, m, finest first.
var spacings := PackedFloat32Array()
## The piece's bounding radius about its own origin, m.
var radius_m: float = 0.0

var _levels: Array[GaussianSplatNode] = []
var _mesh_node: MeshInstance3D = null
var _level: int = -1


## Builds the levels and the mesh from `entry`, files under `dir`. The splat nodes get their records before they enter the tree.
func build(dir: String, entry: Dictionary) -> void:
	for lod: Variant in entry.get("lods", []):
		var row: Dictionary = lod
		var node := GaussianSplatNode.new()
		node.name = "Lod%d" % int(row["level"])
		var path: String = dir.path_join(String(row["file"]))
		if ResourceLoader.exists(path):
			node.gaussian = load(path) as GaussianResource
		SplatLightingLoader.attach(node, dir.path_join(String(row.get("lighting", ""))) if row.has("lighting") else "")
		var c: Array = row.get("centroid", [0.0, 0.0, 0.0])
		node.position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		node.visible = false
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(node)
		_levels.append(node)
		spacings.append(float(row["spacing_m"]))
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "PaintMesh"
	_mesh_node.mesh = PaintMeshes.load_entry(dir, entry.get("paint_mesh", {})) if entry.has("paint_mesh") else null
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mesh_node.visible = false
	add_child(_mesh_node)
	var lo: Array = entry.get("aabb_min", [0.0, 0.0, 0.0])
	var hi: Array = entry.get("aabb_max", [0.0, 0.0, 0.0])
	for corner: Vector3 in [Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0], hi[1], hi[2])]:
		radius_m = maxf(radius_m, corner.length())
	_apply()


## Draws the splats or the mesh.
func set_look(value: Look) -> void:
	if value == look and _level >= 0:
		return
	look = value
	_apply()


## The level shown now (-1 while the mesh is drawn).
func level() -> int:
	return _level if look == Look.SPLAT else -1


## Splats drawn now.
func visible_splats() -> int:
	if look != Look.SPLAT or _level < 0 or _level >= _levels.size() or _levels[_level].gaussian == null:
		return 0
	return _levels[_level].gaussian.point_count


## The painted mesh (null before it is generated).
func mesh() -> Mesh:
	return _mesh_node.mesh if _mesh_node != null else null


func is_mesh_shown() -> bool:
	return _mesh_node != null and _mesh_node.visible


## The level for a camera `distance_m` from the piece's centre, with `px_per_m_at_1m` pixels per metre at one metre.
static func level_for(level_spacings: PackedFloat32Array, distance_m: float, piece_radius_m: float, px_per_m_at_1m: float) -> int:
	var nearest: float = maxf(distance_m - piece_radius_m, 1.0)
	var pick: int = 0
	for i: int in level_spacings.size():
		if level_spacings[i] * px_per_m_at_1m / nearest <= MAX_SPACING_PX:
			pick = i
	return pick


func _process(_delta: float) -> void:
	if look != Look.SPLAT or _levels.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return
	var height: float = LodSwitcherMath.render_height(get_viewport())
	var px_per_m: float = height / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	var pick: int = level_for(spacings, camera.global_position.distance_to(global_position), radius_m, px_per_m)
	if pick != _level:
		_level = pick
		_apply()


func _apply() -> void:
	if _level < 0:
		_level = _levels.size() - 1
	for i: int in _levels.size():
		_levels[i].visible = look == Look.SPLAT and i == _level
	if _mesh_node != null:
		_mesh_node.visible = look == Look.MESH
