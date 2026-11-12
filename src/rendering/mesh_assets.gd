class_name MeshAssets
extends RefCounted
## Loads a hull's mesh (M4-T30a, architecture §7, §17.18): the textured mesh the generator wrote under the manifest's `mesh` section
## (`<asset>.glb` with its UV atlas and the four maps, one material per surface lit by the scene's lights). Every hull has one from
## M4-T30d, the break-up chunks too (`chunk_mesh`, on their parent's materials). One material per surface per asset, so the renderer
## instances every copy of a hull. Godot's scene importer builds each mesh's levels of detail.

const LIVERY_SHADER: Shader = preload("res://assets/shaders/hull_livery.gdshader")
const HULL_GLASS_SHADER: Shader = preload("res://assets/shaders/hull_glass.gdshader")
## The shader's table sizes (`hull_livery.gdshader`).
const MAX_STRIPES: int = 48
const MAX_PATTERNS: int = 12
const MAX_FIELDS: int = 8

const GLASS_SURFACE: String = "glass"
const MAP_KEYS: Array[String] = ["albedo", "normal", "orm", "emissive"]
## The maps a texture detail set replaces (`settings.texture_detail`, M5-T40); the glow is the same in every set.
const DETAIL_KEYS: Array[String] = ["albedo", "normal", "orm"]
## The same for a glass surface, which has no normal map.
const GLASS_DETAIL_KEYS: Array[String] = ["albedo", "orm"]

static var _cache: Dictionary = {}
## The textured meshes' glass materials and their manifest strengths, for `settings.cabin_glow_level` (Q36).
static var _glass: Array[ShaderMaterial] = []
static var _glass_strength: Array[float] = []
static var _livery_sections: Dictionary = {}
## The hulls' paint materials, for `settings.hull_sheen`: a clear coat so painted metal catches the light.
static var _sheen: Array[Material] = []
## The materials whose surface names a second texture set, with where their maps are, for `settings.texture_detail`.
static var _detailed: Array[Dictionary] = []
## How sharp the sheen's highlight and reflection are.
const SHEEN_ROUGHNESS: float = 0.35


## The parsed `manifest.json` of `asset_id`, or {} when it is missing or unreadable.
static func read_manifest(asset_id: String, asset_root: String = ShipSpec.ASSET_ROOT) -> Dictionary:
	var file := FileAccess.open(asset_root.path_join(asset_id).path_join("manifest.json"), FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}


## The textured mesh of a ship asset (its manifest's `mesh`), null when nothing was generated.
static func for_asset(asset_id: String, asset_root: String = ShipSpec.ASSET_ROOT) -> Mesh:
	var textured: Dictionary = read_manifest(asset_id, asset_root).get("mesh", {})
	if textured.is_empty():
		return null
	return load_textured(asset_root.path_join(asset_id), textured)


## A break-up chunk's textured mesh (M4-T30d): `file` (the chunk's glb, under `dir`) drawn with its parent's materials, so it shares
## the parent's maps and instances with the hull. `dir` is the parent asset's directory. Null when either mesh is missing.
static func chunk_mesh(dir: String, file: String) -> Mesh:
	var path: String = dir.path_join(file)
	if _cache.has(path):
		return _cache[path]
	var parent: Mesh = for_asset(dir.get_file(), dir.get_base_dir())
	var mesh: Mesh = _imported_mesh(path) if parent != null else null
	if mesh == null:
		push_warning("MeshAssets: %s or its parent's mesh is missing or not imported (run scripts/gen_assets.sh, then import)" % path)
		return null
	var by_name: Dictionary = {}
	for i: int in parent.get_surface_count():
		var material: Material = parent.surface_get_material(i)
		if material != null:
			by_name[String(material.resource_name)] = material
	for i: int in mesh.get_surface_count():
		var current: Material = mesh.surface_get_material(i)
		var name: String = String(current.resource_name) if current != null else ""
		mesh.surface_set_material(i, by_name.get(name, parent.surface_get_material(mini(i, parent.get_surface_count() - 1))))
	_cache[path] = mesh
	return mesh


## Whether an asset's manifest names a textured mesh.
static func is_textured(asset_id: String, asset_root: String = ShipSpec.ASSET_ROOT) -> bool:
	return not (read_manifest(asset_id, asset_root).get("mesh", {}) as Dictionary).is_empty()


## The textured mesh a manifest `mesh` section names, under `dir`, each surface with its own `StandardMaterial3D` from the maps;
## cached per file. Null when the glb is missing or not imported. A hull's paint takes `settings.hull_sheen`; pass `sheen` false
## for what is not painted metal (rocks).
static func load_textured(dir: String, entry: Dictionary, sheen: bool = true) -> Mesh:
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
		var livery: Dictionary = entry.get("livery", {})
		if bool(surface.get("blend", false)) and not livery.is_empty():
			mesh.surface_set_material(i, glass_material(dir, surface))
		elif not livery.is_empty():
			mesh.surface_set_material(i, _with_sheen(livery_material(dir, surface, livery), sheen))
		else:
			var material: StandardMaterial3D = textured_material(dir, surface)
			mesh.surface_set_material(i, _with_sheen(material, sheen and not bool(surface.get("blend", false))))
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
	_apply_surface_maps(material, dir, surface, DETAIL_KEYS)
	_watch_detail(material, dir, surface, DETAIL_KEYS)
	var emissive_file: String = String(surface.get("emissive", ""))
	var emissive: Texture2D = _texture(dir.path_join(emissive_file)) if not emissive_file.is_empty() else null
	if emissive == null and not emissive_file.is_empty():
		push_warning("MeshAssets: %s is missing or not imported" % dir.path_join(emissive_file))
	var strength: float = float(surface.get("emissive_strength", 1.0))
	if emissive != null and strength > 0.0:
		material.emission_enabled = true
		material.emission_texture = emissive
		material.emission = Color.BLACK
		material.emission_energy_multiplier = strength
	if bool(surface.get("blend", false)):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 1.0, 1.0, 1.0 - float(surface.get("transmittance", 0.0)))
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## The file of one of a surface's maps in the texture set `settings.texture_detail` picks: a set the surface's `detail` names
## (`low`, M5-T40), else the surface's own map: the full set, and the only set of a hull written with one.
static func map_file(surface: Dictionary, key: String) -> String:
	var sets: Dictionary = surface.get("detail", {})
	var chosen: Dictionary = sets.get(String(Settings.get_value(&"texture_detail")), {})
	return String(chosen.get(key, surface.get(key, "")))


# Remembers a material whose surface names a second texture set, so `settings.texture_detail` can swap its maps.
static func _watch_detail(material: Material, dir: String, surface: Dictionary, keys: Array[String]) -> void:
	if (surface.get("detail", {}) as Dictionary).is_empty():
		return
	_detailed.append({"material": material, "dir": dir, "surface": surface, "keys": keys})
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


# Gives a material the maps (`keys`) of the texture set in use: any hull's paint, livery or glass material.
static func _apply_surface_maps(material: Material, dir: String, surface: Dictionary, keys: Array[String]) -> void:
	var maps: Dictionary = {}
	for key: String in keys:
		var file: String = map_file(surface, key)
		var texture: Texture2D = _texture(dir.path_join(file)) if not file.is_empty() else null
		if texture == null and not file.is_empty():
			push_warning("MeshAssets: %s is missing or not imported" % dir.path_join(file))
		maps[key] = texture
	if material is ShaderMaterial:
		for key: String in keys:
			(material as ShaderMaterial).set_shader_parameter(StringName(key + "_map"), maps[key])
		return
	var standard := material as StandardMaterial3D
	standard.albedo_texture = maps["albedo"]
	standard.normal_enabled = maps["normal"] != null
	standard.normal_texture = maps["normal"]
	var orm: Texture2D = maps["orm"]
	if orm != null:
		standard.ao_enabled = true
		standard.ao_texture = orm
		standard.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		standard.roughness_texture = orm
		standard.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		standard.metallic_texture = orm
		standard.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		standard.roughness = 1.0
		standard.metallic = 1.0


## The livery section of an asset's textured mesh (M4-T30b), empty when it takes no livery; read once per asset.
static func livery_section(asset_id: String, asset_root: String = ShipSpec.ASSET_ROOT) -> Dictionary:
	var key: String = asset_root.path_join(asset_id)
	if not _livery_sections.has(key):
		_livery_sections[key] = (read_manifest(asset_id, asset_root).get("mesh", {}) as Dictionary).get("livery", {})
	return _livery_sections[key]


## The hull surface of a mesh that takes wing liveries: the four maps and the livery table (`hull_livery.gdshader`); each ship's
## colours, pattern and number are instance uniforms, so one material serves every wing.
static func livery_material(dir: String, surface: Dictionary, section: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LIVERY_SHADER
	material.resource_name = String(surface.get("name", ""))
	_apply_surface_maps(material, dir, surface, DETAIL_KEYS)
	_watch_detail(material, dir, surface, DETAIL_KEYS)
	var glow_file: String = String(surface.get("emissive", ""))
	var glow: Texture2D = _texture(dir.path_join(glow_file)) if not glow_file.is_empty() else null
	if glow == null and not glow_file.is_empty():
		push_warning("MeshAssets: %s is missing or not imported" % dir.path_join(glow_file))
	material.set_shader_parameter(&"emissive_map", glow)
	material.set_shader_parameter(&"emission_energy", float(surface.get("emissive_strength", 1.0)))
	var paint: Array = section.get("hull_paint", [0.35, 0.35, 0.35])
	material.set_shader_parameter(&"hull_paint", Vector3(float(paint[0]), float(paint[1]), float(paint[2])))
	var digits: Dictionary = section.get("digits", {})
	material.set_shader_parameter(&"digit_map", _texture(dir.path_join(String(digits.get("file", "")))))
	var cell: Array = digits.get("cell_px", [96, 128])
	var per_unit: float = float(digits.get("px_per_unit", 16.0))
	material.set_shader_parameter(&"digit_layout", Vector4(float(cell[0]) / per_unit, float(cell[1]) / per_unit,
			float(digits.get("advance", 5.4)), float(digits.get("range_units", 1.5))))
	var glyph: Array = digits.get("glyph", [4.0, 6.0])
	material.set_shader_parameter(&"glyph_size", Vector2(float(glyph[0]), float(glyph[1])))
	_set_livery_tables(material, section)
	return material


# The pattern table and the number fields as the shader's uniform arrays, in the section's order (the indices `Livery` uses).
static func _set_livery_tables(material: ShaderMaterial, section: Dictionary) -> void:
	var axis := PackedVector4Array()
	var range_ := PackedVector4Array()
	var facing := PackedVector4Array()
	var spans := PackedVector2Array()
	var patterns: Dictionary = section.get("patterns", {})
	for name: String in patterns:
		var stripes: Array = patterns[name]
		spans.append(Vector2(axis.size(), stripes.size()))
		for stripe: Dictionary in stripes:
			var a: Array = stripe.get("axis", [1, 0, 0])
			var f: Array = stripe.get("facing", [0, 1, 0])
			axis.append(Vector4(float(a[0]), float(a[1]), float(a[2]), 1.0 if bool(stripe.get("mirror", true)) else 0.0))
			range_.append(Vector4(float(stripe.get("lo", 0.0)), float(stripe.get("hi", 0.0)), float(stripe.get("slot", 1)),
					float(_zone_bits(stripe.get("zones", [])))))
			facing.append(Vector4(float(f[0]), float(f[1]), float(f[2]), float(stripe.get("min_facing", -2.0))))
	if axis.size() > MAX_STRIPES or spans.size() > MAX_PATTERNS:
		push_warning("MeshAssets: the livery table has %d stripes in %d patterns, over the shader's %d and %d" % [axis.size(), spans.size(), MAX_STRIPES, MAX_PATTERNS])
	axis.resize(MAX_STRIPES)
	range_.resize(MAX_STRIPES)
	facing.resize(MAX_STRIPES)
	spans.resize(MAX_PATTERNS)
	material.set_shader_parameter(&"stripe_axis", axis)
	material.set_shader_parameter(&"stripe_range", range_)
	material.set_shader_parameter(&"stripe_facing", facing)
	material.set_shader_parameter(&"pattern_span", spans)
	var centre := PackedVector4Array()
	var right := PackedVector4Array()
	var up := PackedVector4Array()
	var face := PackedVector4Array()
	var fields: Dictionary = section.get("number_fields", {})
	for name: String in fields:
		var field: Dictionary = fields[name]
		var c: Array = field.get("centre", [0, 0, 0])
		var r: Array = field.get("right", [1, 0, 0])
		var u: Array = field.get("up", [0, 0, -1])
		var f: Array = field.get("facing", [0, 1, 0])
		centre.append(Vector4(float(c[0]), float(c[1]), float(c[2]), float(field.get("height_m", 0.5))))
		right.append(Vector4(float(r[0]), float(r[1]), float(r[2]), float(field.get("weight", 1.0))))
		up.append(Vector4(float(u[0]), float(u[1]), float(u[2]), float(_zone_bits(field.get("zones", [])))))
		face.append(Vector4(float(f[0]), float(f[1]), float(f[2]), 0.0))
	for array: PackedVector4Array in [centre, right, up, face]:
		array.resize(MAX_FIELDS)
	material.set_shader_parameter(&"field_centre", centre)
	material.set_shader_parameter(&"field_right", right)
	material.set_shader_parameter(&"field_up", up)
	material.set_shader_parameter(&"field_facing", face)


static func _zone_bits(zones: Array) -> int:
	var bits: int = 0
	for zone: Variant in zones:
		bits |= 1 << int(zone)
	return bits


## The glass of a textured hull that takes liveries (Q36): dark and see-through, its dark red cabin glow at
## `settings.cabin_glow_level` (the manifest's strength at the default) and fading out by `settings.cabin_glow_view_m`.
static func glass_material(dir: String, surface: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HULL_GLASS_SHADER
	material.resource_name = String(surface.get("name", ""))
	_apply_surface_maps(material, dir, surface, GLASS_DETAIL_KEYS)
	_watch_detail(material, dir, surface, GLASS_DETAIL_KEYS)
	var glow_file: String = String(surface.get("emissive", ""))
	material.set_shader_parameter(&"emissive_map", _texture(dir.path_join(glow_file)) if not glow_file.is_empty() else null)
	material.set_shader_parameter(&"glass_alpha", 1.0 - float(surface.get("transmittance", 0.0)))
	_glass.append(material)
	_glass_strength.append(float(surface.get("emissive_strength", 0.0)))
	_apply_cabin_glow(_glass.size() - 1)
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	return material


static func _apply_cabin_glow(index: int) -> void:
	var level: float = float(Settings.get_value(&"cabin_glow_level"))
	# At `settings.cabin_glow_level`'s default the glass glows at the strength the manifest gives.
	var default_level: float = float(SettingsSchema.ENTRIES[&"cabin_glow_level"]["default"])
	_glass[index].set_shader_parameter(&"glow_energy", _glass_strength[index] * level / maxf(default_level, 1e-6))
	_glass[index].set_shader_parameter(&"glow_view_m", float(Settings.get_value(&"cabin_glow_view_m")))


# Registers a hull paint material for `settings.hull_sheen` and gives it the current sheen.
static func _with_sheen(material: Material, sheen: bool) -> Material:
	if not sheen:
		return material
	_sheen.append(material)
	_apply_sheen(material)
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	return material


static func _apply_sheen(material: Material) -> void:
	var amount: float = float(Settings.get_value(&"hull_sheen"))
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		standard.clearcoat_enabled = amount > 0.0
		standard.clearcoat = amount
		standard.clearcoat_roughness = SHEEN_ROUGHNESS
	elif material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(&"sheen", amount)
		(material as ShaderMaterial).set_shader_parameter(&"sheen_roughness", SHEEN_ROUGHNESS)


static func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"cabin_glow_level" or key == &"cabin_glow_view_m":
		for i: int in _glass.size():
			_apply_cabin_glow(i)
	elif key == &"hull_sheen":
		for material: Material in _sheen:
			_apply_sheen(material)
	elif key == &"texture_detail":
		for entry: Dictionary in _detailed:
			var keys: Array[String] = []
			keys.assign(entry["keys"])
			_apply_surface_maps(entry["material"] as Material, String(entry["dir"]), entry["surface"] as Dictionary, keys)


static func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


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
