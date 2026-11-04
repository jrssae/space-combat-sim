class_name RenderPiece
extends Node3D
## One big stand-in piece (M4-T27, Q24; textured in M4-T30d, architecture §17.17): the textured mesh of a generator's piece entry
## (`tools/procgen/core/pieces.py`: `mesh`, `aabb_min`, `aabb_max`). The station's drum and frame and the capital hulls are pieces.
## The mesh's levels of detail are the engine's (the importer built them).

## The piece's bounding radius about its own origin, m.
var radius_m: float = 0.0

var _mesh_node: MeshInstance3D = null


## Builds the mesh from `entry`, files under `dir`.
func build(dir: String, entry: Dictionary) -> void:
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "HullMesh"
	if entry.has("mesh"):
		_mesh_node.mesh = MeshAssets.load_textured(dir, entry["mesh"])
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh_node)
	var lo: Array = entry.get("aabb_min", [0.0, 0.0, 0.0])
	var hi: Array = entry.get("aabb_max", [0.0, 0.0, 0.0])
	for corner: Vector3 in [Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0], hi[1], hi[2])]:
		radius_m = maxf(radius_m, corner.length())


## The textured mesh (null before it is generated).
func mesh() -> Mesh:
	return _mesh_node.mesh if _mesh_node != null else null


func is_mesh_shown() -> bool:
	return _mesh_node != null and _mesh_node.is_visible_in_tree()
