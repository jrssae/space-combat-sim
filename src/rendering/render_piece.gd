class_name RenderPiece
extends Node3D
## One big stand-in piece (M4-T27, Q24; textured in M4-T30d, architecture §17.17): the textured mesh of a generator's piece entry
## (`tools/procgen/core/pieces.py`: `mesh`, `aabb_min`, `aabb_max`). The station's drum and frame and the capital hulls are pieces.
## The mesh's levels of detail are the engine's (the importer built them).
##
## A piece whose mesh lists sections (M7-T19, `PieceSections`) is drawn as one child mesh per section instead of one mesh, so the
## part near the camera draws full detail and the far end coarse, and its near-only props as instanced meshes under their
## sections. The sections are rigid children: a turning piece turns them as one.

## The piece's bounding radius about its own origin, m.
var radius_m: float = 0.0
## The sections and props, or null for a piece drawn whole.
var sections: PieceSections = null

var _mesh_node: MeshInstance3D = null
## Each section's mesh node, by name.
var _section_nodes: Dictionary = {}
var _prop_nodes: Array[MultiMeshInstance3D] = []


## Builds the mesh from `entry`, files under `dir`.
func build(dir: String, entry: Dictionary) -> void:
	var mesh_entry: Dictionary = entry.get("mesh", {})
	sections = PieceSections.from_entry(mesh_entry, entry.get("props", {}))
	if sections != null:
		_build_sections(dir, mesh_entry)
	else:
		_mesh_node = MeshInstance3D.new()
		_mesh_node.name = "HullMesh"
		if entry.has("mesh"):
			_mesh_node.mesh = MeshAssets.load_textured(dir, mesh_entry)
		_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_mesh_node)
	var lo: Array = entry.get("aabb_min", [0.0, 0.0, 0.0])
	var hi: Array = entry.get("aabb_max", [0.0, 0.0, 0.0])
	for corner: Vector3 in [Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0], hi[1], hi[2])]:
		radius_m = maxf(radius_m, corner.length())


## The textured mesh (null before it is generated, or for a piece drawn in sections).
func mesh() -> Mesh:
	return _mesh_node.mesh if _mesh_node != null else null


## The drawn meshes' box in the piece's frame: the whole mesh's, or every section's together.
func bounds() -> AABB:
	if _mesh_node != null and _mesh_node.mesh != null:
		return _mesh_node.mesh.get_aabb()
	var out := AABB()
	var first: bool = true
	for node: MeshInstance3D in _section_nodes.values():
		if node.mesh == null:
			continue
		var box: AABB = node.transform * node.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func is_mesh_shown() -> bool:
	if _mesh_node != null:
		return _mesh_node.is_visible_in_tree()
	for node: MeshInstance3D in _section_nodes.values():
		if node.mesh != null and node.is_visible_in_tree():
			return true
	return false


## The mesh node of the section named `name`, or null.
func section_node(name: String) -> MeshInstance3D:
	return _section_nodes.get(name) as MeshInstance3D


## The near-only props' instanced meshes.
func prop_nodes() -> Array[MultiMeshInstance3D]:
	return _prop_nodes


func _build_sections(dir: String, mesh_entry: Dictionary) -> void:
	for s: Dictionary in sections.sections:
		var node := MeshInstance3D.new()
		node.name = "Sec_%s" % String(s["name"]).to_pascal_case()
		node.position = s["origin"]
		node.mesh = MeshAssets.section_mesh(dir, mesh_entry, String(s["file"]))
		node.cast_shadow = PieceSections.CAST_SHADOW
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(node)
		_section_nodes[String(s["name"])] = node
		for group: Dictionary in sections.groups_in(String(s["name"])):
			_add_props(dir, node, group)


# One group of props as an instanced mesh under its section, shown only near.
func _add_props(dir: String, section: MeshInstance3D, group: Dictionary) -> void:
	var mesh: Mesh = MeshAssets.prop_mesh(dir, sections.prop_surface, String(sections.prop_files[group["kind"]]))
	if mesh == null:
		return
	var transforms: Array[Transform3D] = group["transforms"]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for k: int in transforms.size():
		multimesh.set_instance_transform(k, transforms[k])
	var node := MultiMeshInstance3D.new()
	node.name = "Props_%s" % String(group["kind"]).to_pascal_case()
	node.multimesh = multimesh
	var range_: Dictionary = sections.prop_range()
	node.visibility_range_end = float(range_["end"])
	node.visibility_range_end_margin = float(range_["end_margin"])
	node.visibility_range_fade_mode = range_["fade"] as GeometryInstance3D.VisibilityRangeFadeMode
	node.cast_shadow = PieceSections.CAST_SHADOW
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	section.add_child(node)
	_prop_nodes.append(node)
