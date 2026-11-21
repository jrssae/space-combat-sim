class_name HullSheenMaterial
extends RefCounted
## The material of a hull with a sheen layer (M10-T06, D12.2): the Vorlons' and the Shadows' organic skins and the semi-organic
## hulls'. A surface whose manifest entry has a `sheen` (the style's numbers, `tools/procgen/core/sheen.py`) draws with
## `hull_organic.gdshader`: the four maps, the hull's shared detail tile where it names one, and the sheen layer over them.
## `settings.texture_detail` swaps the atlas maps between the sets as the ships' maps swap.

const SHADER: Shader = preload("res://assets/shaders/hull_organic.gdshader")
const MAP_KEYS: Array[String] = ["albedo", "normal", "orm", "emissive"]
## The layer's numbers by kind; each is a uniform of the same name (`hull_sheen_layer.gdshaderinc`).
const SCALARS: Array[String] = ["iri_strength", "iri_base", "iri_power", "iri_view", "iri_metal", "pattern_scale_m", "pattern_cells",
		"pattern_edge", "pattern_cover", "pattern_dark", "pattern_iri", "pattern_rough", "pattern_speed_mps", "glow_energy", "glow_veins",
		"glow_rim", "glow_pulse_s", "glow_pulse", "coat"]
const COLOURS: Array[String] = ["pattern_tint", "glow_colour"]
const IRIDESCENCE: String = "iri_sh"
const SH_COUNT: int = 9

## The materials made, with where their maps are, for `settings.texture_detail`.
static var _made: Array[Dictionary] = []


## Whether a surface entry asks for this material.
static func wants(surface: Dictionary) -> bool:
	return surface.get("sheen") is Dictionary and not (surface["sheen"] as Dictionary).is_empty()


## A material for one surface (`dir` holds its maps), in the texture set in use, wearing the surface's sheen.
static func make(dir: String, surface: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.resource_name = String(surface.get("name", ""))
	material.set_shader_parameter(&"emission_energy", float(surface.get("emissive_strength", 1.0)))
	var detail: Dictionary = surface.get("world_detail", {})
	var tile_m: float = float(detail.get("tile_m", 0.0))
	if tile_m > 0.0:
		var albedo: Texture2D = _texture(dir.path_join(String(detail.get("albedo", ""))))
		var normal: Texture2D = _texture(dir.path_join(String(detail.get("normal", ""))))
		if albedo != null and normal != null:
			material.set_shader_parameter(&"detail_albedo_map", albedo)
			material.set_shader_parameter(&"detail_normal_map", normal)
			material.set_shader_parameter(&"detail_tile_m", tile_m)
		else:
			push_warning("HullSheenMaterial: the detail tile of %s is missing or not imported" % dir)
	apply_sheen(material, surface["sheen"] as Dictionary)
	apply_set(material, dir, surface)
	_made.append({"material": material, "dir": dir, "surface": surface})
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	return material


## Gives a material a sheen's numbers (a manifest `sheen` entry); a number the entry leaves out keeps the shader's default.
static func apply_sheen(material: ShaderMaterial, sheen: Dictionary) -> void:
	for key: String in SCALARS:
		if sheen.has(key):
			material.set_shader_parameter(StringName(key), float(sheen[key]))
	for key: String in COLOURS:
		var colour: Variant = sheen.get(key)
		if colour is Array and (colour as Array).size() == 3:
			material.set_shader_parameter(StringName(key), Vector3(float(colour[0]), float(colour[1]), float(colour[2])))
	var rows: Variant = sheen.get(IRIDESCENCE)
	if rows is Array and (rows as Array).size() == SH_COUNT:
		var coefficients := PackedVector3Array()
		for row: Array in rows:
			coefficients.append(Vector3(float(row[0]), float(row[1]), float(row[2])))
		material.set_shader_parameter(StringName(IRIDESCENCE), coefficients)


## Gives a material the maps of the texture set in use.
static func apply_set(material: ShaderMaterial, dir: String, surface: Dictionary) -> void:
	for key: String in MAP_KEYS:
		var file: String = MeshAssets.map_file(surface, key)
		var texture: Texture2D = _texture(dir.path_join(file)) if not file.is_empty() else null
		if texture == null and not file.is_empty():
			push_warning("HullSheenMaterial: %s is missing or not imported" % dir.path_join(file))
		material.set_shader_parameter(StringName(key + "_map"), texture)


static func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key != &"texture_detail":
		return
	for entry: Dictionary in _made:
		apply_set(entry["material"] as ShaderMaterial, String(entry["dir"]), entry["surface"] as Dictionary)


static func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
