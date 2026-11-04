class_name MeshAssets
extends RefCounted
## Loads a hull's mesh (M4-T30a, architecture §17.18): the textured mesh the generator wrote under the manifest's `mesh` section
## (`<asset>.glb` with its UV atlas and the four maps, one `StandardMaterial3D` per surface lit by the scene's lights), or, for an
## asset T30b has not converted yet, T27's painted mesh (`paint_mesh`, the paint shader). One material per surface per asset, so the
## renderer instances every copy of a hull. Godot's scene importer builds each mesh's levels of detail.
##
## The paint materials are kept in `materials` so `PaintMeshLights` can give them the scene's 8 lights each frame.

const OPAQUE_SHADER: Shader = preload("res://assets/shaders/paint_mesh.gdshader")
const GLASS_SHADER: Shader = preload("res://assets/shaders/paint_mesh_glass.gdshader")
const MAX_MATERIALS: int = 32
const GLASS_SURFACE: String = "glass"
const MAP_KEYS: Array[String] = ["albedo", "normal", "orm", "emissive"]

## Every paint material made so far (shared by every user of its mesh), for the lights.
static var materials: Array[ShaderMaterial] = []
static var _cache: Dictionary = {}


## The mesh of a ship asset: textured when its manifest has `mesh`, else painted (`paint_mesh`); null when nothing was generated.
static func for_asset(asset_id: String, asset_root: String = ShipSpec.ASSET_ROOT) -> Mesh:
	var manifest: Dictionary = SplatLod.read_manifest(asset_id, asset_root)
	var dir: String = asset_root.path_join(asset_id)
	var textured: Dictionary = manifest.get("mesh", {})
	if not textured.is_empty():
		return load_textured(dir, textured)
	var entry: Dictionary = manifest.get("paint_mesh", {})
	if entry.is_empty():
		return null
	return load_entry(dir, entry)


## Whether an asset's manifest names a textured mesh.
static func is_textured(asset_id: String, asset_root: String = ShipSpec.ASSET_ROOT) -> bool:
	return not (SplatLod.read_manifest(asset_id, asset_root).get("mesh", {}) as Dictionary).is_empty()


## The textured mesh a manifest `mesh` section names, under `dir`, each surface with its own `StandardMaterial3D` from the maps;
## cached per file. Null when the glb is missing or not imported.
static func load_textured(dir: String, entry: Dictionary) -> Mesh:
	var path: String = dir.path_join(String(entry.get("file", "")))
	if _cache.has(path):
		return _cache[path]
	var mesh: Mesh = _imported_mesh(path)
	if mesh == null:
		push_warning("MeshAssets: %s is missing or not imported (run scripts/gen_assets.sh, then import)" % path)
		return null
	var surfaces: Array = entry.get("surfaces", [])
	for i: int in mesh.get_surface_count():
		var current: Material = mesh.surface_get_material(i)
		var name: String = String(current.resource_name) if current != null else ""
		var surface: Dictionary = _surface_named(surfaces, name, i)
		mesh.surface_set_material(i, textured_material(dir, surface))
	_cache[path] = mesh
	return mesh


# The manifest surface whose name the imported material carries, else the one at the primitive's index.
static func _surface_named(surfaces: Array, name: String, index: int) -> Dictionary:
	for surface: Dictionary in surfaces:
		if String(surface.get("name", "")) == name:
			return surface
	return surfaces[index] if index < surfaces.size() else {}


## A PBR material for one surface of a textured mesh: the albedo (sRGB), the normal map, occlusion, roughness and metal from the
## ORM map's channels, the emissive map at the surface's strength; glass as an alpha-blended, two-sided surface that lets the
## manifest's transmittance through.
static func textured_material(dir: String, surface: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = String(surface.get("name", ""))
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var maps: Dictionary = {}
	for key: String in MAP_KEYS:
		var file: String = String(surface.get(key, ""))
		var texture: Texture2D = _texture(dir.path_join(file)) if not file.is_empty() else null
		if texture == null and not file.is_empty():
			push_warning("MeshAssets: %s is missing or not imported" % dir.path_join(file))
		maps[key] = texture
	material.albedo_texture = maps["albedo"]
	if maps["normal"] != null:
		material.normal_enabled = true
		material.normal_texture = maps["normal"]
	var orm: Texture2D = maps["orm"]
	if orm != null:
		material.ao_enabled = true
		material.ao_texture = orm
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.roughness_texture = orm
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		material.metallic_texture = orm
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		material.roughness = 1.0
		material.metallic = 1.0
	var strength: float = float(surface.get("emissive_strength", 1.0))
	if maps["emissive"] != null and strength > 0.0:
		material.emission_enabled = true
		material.emission_texture = maps["emissive"]
		material.emission = Color.BLACK
		material.emission_energy_multiplier = strength
	if bool(surface.get("blend", false)):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 1.0, 1.0, 1.0 - float(surface.get("transmittance", 0.0)))
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The painted mesh an entry names (M4-T27), under `dir`, with its paint materials; cached per file. Null when the file is missing.
static func load_entry(dir: String, entry: Dictionary) -> Mesh:
	var path: String = dir.path_join(String(entry.get("file", "")))
	if _cache.has(path):
		return _cache[path]
	var mesh: Mesh = _imported_mesh(path)
	if mesh == null:
		push_warning("MeshAssets: %s is missing or not imported (run scripts/gen_assets.sh, then import)" % path)
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
