class_name BandTintMaterial
extends RefCounted
## The material of a hull whose bands are repainted per ship (M10-T53, Q86: the Asimov liners' liveries). A surface whose manifest
## entry has a `band_tint` (`tools/procgen/styles/ea_asimov.band_tint`: the baked band colour, the liveries' colours and the names
## list they follow) draws with `hull_band_tint.gdshader`, one atlas for every livery; a surface that also has `band_bars` (the
## liner's turning band, Q95) has the ship's bars drawn on it by the shader, six or eight by the ship. Both are the ship's
## `skin_variant` (`variant`: the livery plus `MAX_LIVERIES` times the bar count's place), set per drawn node as
## `HullSheenMaterial.set_variant` does. `settings.texture_detail` swaps the maps.

const SHADER: Shader = preload("res://assets/shaders/hull_band_tint.gdshader")
const MAP_KEYS: Array[String] = ["albedo", "normal", "orm", "emissive"]
const MAX_LIVERIES: int = 8
const MAX_BAR_COUNTS: int = 4

## The materials made, with where their maps are, for `settings.texture_detail`.
static var _made: Array[Dictionary] = []


## Whether a surface entry asks for this material.
static func wants(surface: Dictionary) -> bool:
	return surface.get("band_tint") is Dictionary and not (surface["band_tint"] as Dictionary).is_empty()


## A material for one surface (`dir` holds its maps), in the texture set in use, with its liveries' colours.
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
	var tint: Dictionary = surface["band_tint"]
	material.set_shader_parameter(&"band_base", _vec(tint.get("base", [0.0, 0.0, 0.0])))
	var colours := PackedVector3Array()
	for row: Variant in tint.get("colours", []):
		if colours.size() < MAX_LIVERIES:
			colours.append(_vec(row))
	while colours.size() < MAX_LIVERIES:
		colours.append(Vector3.ZERO)
	material.set_shader_parameter(&"band_colours", colours)
	material.set_shader_parameter(&"band_count", mini((tint.get("colours", []) as Array).size(), MAX_LIVERIES))
	_set_bars(material, tint, surface.get("band_bars", {}) as Dictionary)
	apply_set(material, dir, surface)
	_made.append({"material": material, "dir": dir, "surface": surface})
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	return material


## Where the shader draws the bars on this surface (`bars`, the manifest's `band_bars`) and how many a ship may have.
static func _set_bars(material: ShaderMaterial, tint: Dictionary, bars: Dictionary) -> void:
	var counts := PackedInt32Array()
	for count: Variant in tint.get("bar_counts", []):
		if counts.size() < MAX_BAR_COUNTS:
			counts.append(int(count))
	if bars.is_empty() or counts.is_empty():
		return
	var span: Array = bars.get("span_m", [0.0, 0.0])
	material.set_shader_parameter(&"bar_radius", float(bars.get("radius_m", 0.0)))
	material.set_shader_parameter(&"bar_span", Vector2(float(span[0]), float(span[1])))
	material.set_shader_parameter(&"bar_half_m", float(bars.get("half_width_m", 0.0)))
	material.set_shader_parameter(&"band_white", _vec(tint.get("white", [0.65, 0.65, 0.65])))
	material.set_shader_parameter(&"bar_count_choices", counts.size())
	counts.resize(MAX_BAR_COUNTS)
	material.set_shader_parameter(&"bar_counts", counts)


## The livery the ship called `display_name` wears, as an index into `tint`'s liveries: its name's place in the names list `tint`
## follows (`data/ships/names.json`), so the list's first ship wears the first (the default) and the same ship always wears the same;
## a name not on the list takes a stable one from its letters (FNV-1a). 0 for no name. A repeated name ("EAS Heinlein 2") is its
## first's.
static func livery_index(tint: Dictionary, display_name: String, names: PackedStringArray = PackedStringArray()) -> int:
	var count: int = mini((tint.get("colours", []) as Array).size(), MAX_LIVERIES)
	var place: int = _place(tint, display_name, names)
	return place % count if count > 1 and place >= 0 else 0


## Which of `tint`'s bar counts the ship has (Q95), as an index: by its name's place too, going round the counts as the livery
## goes round the colours, so the names give every pairing of the two. 0 for no name or one count.
static func bar_choice(tint: Dictionary, display_name: String, names: PackedStringArray = PackedStringArray()) -> int:
	var count: int = mini((tint.get("bar_counts", []) as Array).size(), MAX_BAR_COUNTS)
	var place: int = _place(tint, display_name, names)
	return place % count if count > 1 and place >= 0 else 0


## How many bars the ship has; 0 for a hull without bars.
static func bar_count(tint: Dictionary, display_name: String, names: PackedStringArray = PackedStringArray()) -> int:
	var counts: Array = tint.get("bar_counts", [])
	return int(counts[bar_choice(tint, display_name, names)]) if not counts.is_empty() else 0


## The ship's `skin_variant`: its livery and its bar count in one number, as the shader reads them.
static func variant(tint: Dictionary, display_name: String, names: PackedStringArray = PackedStringArray()) -> int:
	return livery_index(tint, display_name, names) + MAX_LIVERIES * bar_choice(tint, display_name, names)


## The name's place in the list `tint` follows, a stable number from its letters for a name off the list, -1 for no name.
static func _place(tint: Dictionary, display_name: String, names: PackedStringArray) -> int:
	var name: String = HullMarks.name_of(display_name)
	if name.is_empty():
		return -1
	var words: PackedStringArray = name.split(" ", false)
	if words.size() > 1 and words[words.size() - 1].is_valid_int():
		name = " ".join(words.slice(0, words.size() - 1))
	var listed: PackedStringArray = names if not names.is_empty() else ShipNames.names_for(StringName(String(tint.get("names_type", ""))))
	var at: int = listed.find(name)
	return at if at >= 0 else Livery.fnv1a(name.to_lower())


## The livery's key ("green", "blue", ...) at `index` of `tint`, "" past its list.
static func livery_key(tint: Dictionary, index: int) -> String:
	var keys: Array = tint.get("liveries", [])
	return String(keys[index]) if index >= 0 and index < keys.size() else ""


## A ship's `skin_variant` for a hull's mesh entry (a manifest `mesh` section): its first band-tinted surface's, 0 with none.
static func variant_of_mesh(mesh_entry: Dictionary, display_name: String) -> int:
	for surface: Dictionary in mesh_entry.get("surfaces", []):
		if wants(surface):
			return variant(surface["band_tint"] as Dictionary, display_name)
	return 0


## Gives a material the maps of the texture set in use.
static func apply_set(material: ShaderMaterial, dir: String, surface: Dictionary) -> void:
	for key: String in MAP_KEYS:
		var file: String = MeshAssets.map_file(surface, key)
		var texture: Texture2D = _texture(dir.path_join(file)) if not file.is_empty() else null
		if texture == null and not file.is_empty():
			push_warning("BandTintMaterial: %s is missing or not imported" % dir.path_join(file))
		material.set_shader_parameter(StringName(key + "_map"), texture)


static func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key != &"texture_detail":
		return
	for entry: Dictionary in _made:
		apply_set(entry["material"] as ShaderMaterial, String(entry["dir"]), entry["surface"] as Dictionary)


static func _vec(row: Variant) -> Vector3:
	if row is Array and (row as Array).size() == 3:
		return Vector3(float(row[0]), float(row[1]), float(row[2]))
	return Vector3.ZERO


static func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
