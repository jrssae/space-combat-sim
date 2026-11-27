class_name RenderPiece
extends Node3D
## One big stand-in piece (M4-T27, Q24; textured in M4-T30d, architecture §17.17): the textured mesh of a generator's piece entry
## (`tools/procgen/core/pieces.py`: `mesh`, `aabb_min`, `aabb_max`). The station's drum and frame and the capital hulls are pieces.
## The mesh's levels of detail are the engine's (the importer built them).
##
## A piece whose mesh lists sections (M7-T19, `PieceSections`) is drawn as one child mesh per section instead of one mesh, so the
## part near the camera draws full detail and the far end coarse, and its near-only props as instanced meshes under their
## sections. The sections are rigid children: a turning piece turns them as one. A piece drawn whole with an `interior_file` (a
## capital's bay halls, M10-T72) draws those faces as a child of its mesh on `LightRig.INTERIOR_LAYER`, out of the sun's light.
## A piece drawn whole whose mesh lists a far level (a capital's, M10-T89) draws that far away instead (`FarMeshRange`): the full
## mesh and whatever else hangs on the piece are the far mesh's visibility dependents.

## The interior node's key for a piece drawn whole (a capital's bays, M10-T72).
const WHOLE: String = ""

## The piece's bounding radius about its own origin, m.
var radius_m: float = 0.0
## The sections and props, or null for a piece drawn whole.
var sections: PieceSections = null
## The far mesh drawn past its swap distance (M10-T89), or null when the piece has none.
var far_node: MeshInstance3D = null
## The far level's manifest entry (`mesh.lods[0]`), empty without one.
var far_lod: Dictionary = {}

## The pieces with a far mesh, so the console can change how every one is used.
static var _with_far: Array[RenderPiece] = []

var _mesh_node: MeshInstance3D = null
## Each section's mesh node, by name.
var _section_nodes: Dictionary = {}
## The mesh nodes of the sections' interior faces, by section name (only the sections that have any).
var _interior_nodes: Dictionary = {}
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
		_add_whole_interior(dir, mesh_entry)
		_add_far(dir, mesh_entry)
	var lo: Array = entry.get("aabb_min", [0.0, 0.0, 0.0])
	var hi: Array = entry.get("aabb_max", [0.0, 0.0, 0.0])
	for corner: Vector3 in [Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0], hi[1], hi[2])]:
		radius_m = maxf(radius_m, corner.length())


## Puts the piece in its style's second colouring (1) or its first (0): a hull with a sheen layer (M10-T06), per ship.
func set_skin_variant(variant: float) -> void:
	if _mesh_node != null:
		HullSheenMaterial.set_variant(_mesh_node, variant)
	if _interior_nodes.has(WHOLE):
		HullSheenMaterial.set_variant(_interior_nodes[WHOLE] as MeshInstance3D, variant)
	for node: MeshInstance3D in _section_nodes.values():
		HullSheenMaterial.set_variant(node, variant)
	if far_node != null:
		HullSheenMaterial.set_variant(far_node, variant)


## Makes everything on the piece but its far mesh (the full mesh, and what was added since: marks, doors) draw only while the
## far mesh does not (M10-T89). Call it again after adding children.
func hide_when_far() -> void:
	if far_node == null:
		return
	for child: Node in get_children():
		if child != far_node and child is Node3D:
			(child as Node3D).visibility_parent = (child as Node3D).get_path_to(far_node)


## Uses every live piece's far mesh as `mode` says (the console's `capital far`), and every piece built from now on.
static func set_far_mode(mode: FarMeshRange.Mode) -> void:
	FarMeshRange.mode = mode
	for piece: RenderPiece in _with_far.duplicate():
		if not is_instance_valid(piece):
			_with_far.erase(piece)
		elif piece.far_node != null:
			FarMeshRange.apply(piece.far_node, piece.far_lod, mode)


## Live pieces with a far mesh.
static func far_count() -> int:
	_with_far = _with_far.filter(func(p: RenderPiece) -> bool: return is_instance_valid(p))
	return _with_far.size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_with_far.erase(self)


# The far mesh (M10-T89) on the hull's own material pipeline, swapped in by Godot's visibility ranges.
func _add_far(dir: String, mesh_entry: Dictionary) -> void:
	var lod: Dictionary = FarMeshRange.lod_of(mesh_entry)
	if lod.is_empty():
		return
	var mesh: Mesh = MeshAssets.load_textured(dir, lod)
	if mesh == null:
		return
	far_lod = lod
	far_node = MeshInstance3D.new()
	far_node.name = "FarMesh"
	far_node.mesh = mesh
	far_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(far_node)
	FarMeshRange.apply(far_node, lod, FarMeshRange.mode)
	hide_when_far()
	_with_far.append(self)


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


## The mesh node of a section's interior faces (on `LightRig.INTERIOR_LAYER`), or null; `WHOLE` for a piece drawn whole.
func interior_node(name: String) -> MeshInstance3D:
	return _interior_nodes.get(name) as MeshInstance3D


## The near-only props' instanced meshes.
func prop_nodes() -> Array[MultiMeshInstance3D]:
	return _prop_nodes


func _build_sections(dir: String, mesh_entry: Dictionary) -> void:
	for s: Dictionary in sections.sections:
		var node := MeshInstance3D.new()
		node.name = "Sec_%s" % String(s["name"]).to_pascal_case()
		node.position = s["origin"]
		node.mesh = MeshAssets.section_mesh(dir, mesh_entry, String(s["file"]))
		# The station hull's tiles run in the piece's space (M7-T24), unbroken across the section joints.
		node.set_instance_shader_parameter(&"piece_offset", s["origin"])
		node.cast_shadow = PieceSections.CAST_SHADOW
		node.layers = 1 | LightRig.SHADOW_CASTER_LAYER
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(node)
		_section_nodes[String(s["name"])] = node
		if not String(s["interior_file"]).is_empty():
			_add_interior(dir, mesh_entry, node, s)
		for group: Dictionary in sections.groups_in(String(s["name"])):
			_add_props(dir, node, group)


# The section's faces inside a hall or a bay: the same material, drawn on the layer the sun's light leaves out.
func _add_interior(dir: String, mesh_entry: Dictionary, section: MeshInstance3D, s: Dictionary) -> void:
	var node := MeshInstance3D.new()
	node.name = "Interior"
	node.mesh = MeshAssets.section_mesh(dir, mesh_entry, String(s["interior_file"]))
	node.set_instance_shader_parameter(&"piece_offset", s["origin"])
	node.layers = LightRig.INTERIOR_LAYER | LightRig.SHADOW_CASTER_LAYER
	node.cast_shadow = PieceSections.CAST_SHADOW
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	section.add_child(node)
	_interior_nodes[String(s["name"])] = node


# A whole hull's bays: their halls drawn on the layer the sun's light leaves out, with the hull's own materials.
func _add_whole_interior(dir: String, mesh_entry: Dictionary) -> void:
	var node: MeshInstance3D = MeshAssets.interior_node(dir, mesh_entry, _mesh_node.mesh)
	if node == null:
		return
	_mesh_node.add_child(node)
	_interior_nodes[WHOLE] = node


# One group of props as an instanced mesh under its section, shown only near.
func _add_props(dir: String, section: MeshInstance3D, group: Dictionary) -> void:
	var kind: String = String(group["kind"])
	var detail: Dictionary = sections.prop_detail if sections.prop_detailed.has(kind) else {}
	var mesh: Mesh = MeshAssets.prop_mesh(dir, sections.prop_surface, String(sections.prop_files[kind]), detail)
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
	var range_: Dictionary = sections.prop_range(String(group["kind"]))
	node.visibility_range_end = float(range_["end"])
	node.visibility_range_end_margin = float(range_["end_margin"])
	node.visibility_range_fade_mode = range_["fade"] as GeometryInstance3D.VisibilityRangeFadeMode
	node.cast_shadow = PieceSections.CAST_SHADOW
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var inside: bool = sections.prop_interior.has(String(group["kind"]))
	node.layers = (LightRig.INTERIOR_LAYER if inside else 1) | LightRig.SHADOW_CASTER_LAYER
	section.add_child(node)
	_prop_nodes.append(node)
