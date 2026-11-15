class_name StationHullMaterial
extends RefCounted
## The station hull's material (M7-T24, D72): one tier's atlas with the station's two detail tiles over it (`station_hull.gdshader`).
## A surface whose `world_detail` says `shader: station` draws with it; `settings.texture_detail` swaps both the atlas and the fine
## tile between the sets, as the ships' maps swap.

const SHADER: Shader = preload("res://assets/shaders/station_hull.gdshader")
## The atlas maps a set replaces, and the tiles' maps (the shader's `<key>_map`); the panel tile is the same in both sets.
const ATLAS_KEYS: Array[String] = ["albedo", "normal", "orm"]
const TILE_KEYS: Array[String] = ["fine_colour", "fine_normal", "panel_colour", "panel_normal"]

## The materials made, with where their maps are, for `settings.texture_detail`.
static var _made: Array[Dictionary] = []


## Whether a surface entry asks for this material.
static func wants(surface: Dictionary) -> bool:
	return String((surface.get("world_detail", {}) as Dictionary).get("shader", "")) == "station"


## A material for one tier's surface (`dir` holds its maps), in the texture set in use.
static func make(dir: String, surface: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.resource_name = String(surface.get("name", ""))
	var detail: Dictionary = surface.get("world_detail", {})
	material.set_shader_parameter(&"fine_tile_m", float(detail.get("fine_tile_m", 16.0)))
	material.set_shader_parameter(&"panel_tile_m", float(detail.get("panel_tile_m", 128.0)))
	var emissive_file: String = String(surface.get("emissive", ""))
	if not emissive_file.is_empty():
		material.set_shader_parameter(&"emissive_map", _texture(dir.path_join(emissive_file)))
	material.set_shader_parameter(&"emission_energy", float(surface.get("emissive_strength", 1.0)))
	apply_set(material, dir, surface)
	_made.append({"material": material, "dir": dir, "surface": surface})
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	return material


## The file of one of the material's maps in the set `settings.texture_detail` picks: the atlas's from the surface's `detail`, the
## tiles' from its `world_detail` (`low` naming the low set's), else the surface's own.
static func map_file(surface: Dictionary, key: String) -> String:
	var set_name: String = String(Settings.get_value(&"texture_detail"))
	if key in ATLAS_KEYS:
		return MeshAssets.map_file(surface, key)
	var detail: Dictionary = surface.get("world_detail", {})
	var chosen: Dictionary = detail.get(set_name, {})
	return String(chosen.get(key, detail.get(key, "")))


## Gives a material the maps of the texture set in use.
static func apply_set(material: ShaderMaterial, dir: String, surface: Dictionary) -> void:
	for key: String in ATLAS_KEYS + TILE_KEYS:
		var file: String = map_file(surface, key)
		var texture: Texture2D = _texture(dir.path_join(file)) if not file.is_empty() else null
		if texture == null and not file.is_empty():
			push_warning("StationHullMaterial: %s is missing or not imported" % dir.path_join(file))
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
