class_name PaintMeshes
extends RefCounted
## Loads the painted meshes (M4-T27, Q24, architecture §17.17): a hull's own surface as triangles, the render comparison's mesh path.
## Each generator writes `<name>_mesh.glb` beside its splats and a `paint_mesh` manifest section (the material table and panel
## grid); this gives the imported mesh with one shared `ShaderMaterial` per surface, the paint shader filled from that section.
## Godot's scene importer builds the mesh's levels of detail, so a far mesh draws fewer triangles on its own.
##
## The materials are kept in `materials` so `PaintMeshLights` can give them the scene's 8 lights each frame.

const OPAQUE_SHADER: Shader = preload("res://assets/shaders/paint_mesh.gdshader")
const GLASS_SHADER: Shader = preload("res://assets/shaders/paint_mesh_glass.gdshader")
const MAX_MATERIALS: int = 32
const GLASS_SURFACE: String = "glass"

## Every paint material made so far (shared by every user of its mesh), for the lights.
static var materials: Array[ShaderMaterial] = []
static var _cache: Dictionary = {}


## The painted mesh of a ship asset (its manifest's `paint_mesh`), or null when it was not generated or imported.
static func for_asset(asset_id: String, asset_root: String = ShipSpec.ASSET_ROOT) -> Mesh:
	var manifest: Dictionary = SplatLod.read_manifest(asset_id, asset_root)
	var entry: Dictionary = manifest.get("paint_mesh", {})
	if entry.is_empty():
		return null
	return load_entry(asset_root.path_join(asset_id), entry)


## The mesh an entry names, under `dir`, with its paint materials; cached per file. Null when the file is missing.
static func load_entry(dir: String, entry: Dictionary) -> Mesh:
	var path: String = dir.path_join(String(entry.get("file", "")))
	if _cache.has(path):
		return _cache[path]
	var mesh: Mesh = _imported_mesh(path)
	if mesh == null:
		push_warning("PaintMeshes: %s is missing or not imported (run scripts/gen_assets.sh, then import)" % path)
		return null
	for i: int in mesh.get_surface_count():
		var current: Material = mesh.surface_get_material(i)
		var glass: bool = current != null and String(current.resource_name) == GLASS_SURFACE
		mesh.surface_set_material(i, make_material(entry, glass))
	_cache[path] = mesh
	return mesh


## A paint material for `entry`: the material table, the panel grid and, for glass, how much it stops.
static func make_material(entry: Dictionary, glass: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLASS_SHADER if glass else OPAQUE_SHADER
	var albedo := PackedVector3Array()
	var paneled := PackedFloat32Array()
	albedo.resize(MAX_MATERIALS)
	paneled.resize(MAX_MATERIALS)
	var transmittance: float = 0.0
	var table: Array = entry.get("materials", [])
	for k: int in mini(table.size(), MAX_MATERIALS):
		var row: Dictionary = table[k]
		var c: Array = row.get("albedo", [0.5, 0.5, 0.5])
		albedo[k] = Vector3(float(c[0]), float(c[1]), float(c[2]))
		paneled[k] = 1.0 if bool(row.get("paneled", false)) else 0.0
		transmittance = maxf(transmittance, float(row.get("transmittance", 0.0)))
	material.set_shader_parameter(&"paint_albedo", albedo)
	material.set_shader_parameter(&"paint_paneled", paneled)
	var panel: Dictionary = entry.get("panel", {})
	material.set_shader_parameter(&"panel_size_m", float(panel.get("size_m", 0.6)))
	material.set_shader_parameter(&"panel_line_width_m", float(panel.get("line_width_m", 0.04)))
	material.set_shader_parameter(&"panel_line_darkness", float(panel.get("line_darkness", 0.55)))
	material.set_shader_parameter(&"panel_tint_jitter", float(panel.get("tint_jitter", 0.05)))
	if glass:
		material.set_shader_parameter(&"glass_alpha", 1.0 - transmittance)
	materials.append(material)
	return material


# The first mesh of an imported glb scene.
static func _imported_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var found: Mesh = _first_mesh(root)
	root.free()
	return found


static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child: Node in node.get_children():
		var mesh: Mesh = _first_mesh(child)
		if mesh != null:
			return mesh
	return null
