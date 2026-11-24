class_name HullMarkNode
extends MeshInstance3D
## One painted letter on a hull (M10-T21): a quad a little off the face, showing one cell of the generated glyph atlas; or one
## painted picture (the Earth Alliance emblem, M10-T22) showing its own image, lit by its flood. A thin adapter; the rules are in
## `HullMarks`.

## The faction this mark is painted for; empty for every ship's.
var only_faction: StringName = &""

static var _materials: Dictionary = {}  # "<atlas path>|<cell>|<colour>" -> StandardMaterial3D, shared by every ship


## The nodes for `marks` (from `hardpoints.json`) on a ship called `display_name`, or none when the hull has no atlas or the
## name gives no letter. `dir` is the asset's folder.
static func build_all(marks: Array[Dictionary], atlas: Dictionary, dir: String, display_name: String) -> Array[HullMarkNode]:
	var out: Array[HullMarkNode] = []
	if marks.is_empty() or atlas.is_empty() or not ResourceLoader.exists(dir.path_join(str(atlas.get("file", "")))):
		return out
	var chars: String = str(atlas.get("chars", ""))
	for mark: Dictionary in marks:
		if HullMarks.is_image(mark):
			var picture: HullMarkNode = create_image(mark, dir)
			if picture != null:
				out.append(picture)
			continue
		var path: String = dir.path_join(HullMarks.atlas_file(mark, atlas))
		if not ResourceLoader.exists(path):
			continue
		var texture: Texture2D = load(path) as Texture2D
		var text: String = HullMarks.text_for(mark, display_name, chars, ShipNames.hull_number_of(display_name))
		var offsets: PackedFloat32Array = HullMarks.offsets(text, atlas, float(mark.get("stretch", 1.0)))
		out.append_array(create_placard(mark, HullMarks.placard_size(mark, text, atlas)))
		for i: int in text.length():
			var node: HullMarkNode = create(mark, text, i, atlas, texture, path, offsets[i])
			if node != null:
				out.append(node)
	return out


## Character `index` of `text` on `mark`, `offset` letter heights from the mark's centre (`HullMarks.offsets`); with no offset
## given, letters sit at an even pitch, centred on the mark.
static func create(mark: Dictionary, text: String, index: int, atlas: Dictionary, texture: Texture2D, path: String, offset: float = NAN) -> HullMarkNode:
	var cell: Vector2i = HullMarks.cell_of(text.substr(index, 1), atlas)
	if cell.x < 0:
		return null
	var height: float = float(mark.get("height_m", 10.0))
	var normal := _vec(mark.get("normal"))
	var basis: Basis = HullMarks.quad_basis(normal, _vec(mark.get("up")))
	var side: float = HullMarks.quad_side_m(height, atlas)
	var stretch: float = float(mark.get("stretch", 1.0))
	var shift: float = (offset if not is_nan(offset) else HullMarks.offsets(text, atlas, stretch)[index]) * height
	var node := HullMarkNode.new()
	node.name = "Mark%s%d" % [str(mark.get("name", "mark")).to_pascal_case().validate_node_name(), index]
	var quad := QuadMesh.new()
	quad.size = Vector2(side * stretch, side)
	node.mesh = quad
	node.material_override = _material(texture, path, cell, int(atlas.get("columns", 1)), _colour(mark.get("colour")))
	node.only_faction = StringName(str(mark.get("only_faction", "")))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.transform = Transform3D(basis, _vec(mark.get("position")) + normal.normalized() * HullMarks.STANDOFF_M + basis.x * shift)
	return node


## The board behind a name (`HullMarks.placard_size`): a light panel and, behind it, a black one a line's width bigger all round.
## Opaque, so the letters in front always draw over them. None for a mark without a board.
static func create_placard(mark: Dictionary, size: Vector2) -> Array[HullMarkNode]:
	var out: Array[HullMarkNode] = []
	if size == Vector2.ZERO:
		return out
	var board: Dictionary = mark["placard"]
	var normal := _vec(mark.get("normal"))
	var basis: Basis = HullMarks.quad_basis(normal, _vec(mark.get("up")))
	var line: float = HullMarks.placard_line_m(mark)
	# Each layer: its name, size, colour and how many steps behind the letters it sits.
	for layer: Array in [["Panel", size, board.get("colour"), 1.0], ["Line", size + Vector2.ONE * 2.0 * line, board.get("line_colour"), 2.0]]:
		var node := HullMarkNode.new()
		node.name = "Mark%s%s" % [str(mark.get("name", "mark")).to_pascal_case().validate_node_name(), layer[0]]
		var quad := QuadMesh.new()
		quad.size = layer[1]
		node.mesh = quad
		node.material_override = _board_material(_colour(layer[2]))
		node.only_faction = StringName(str(mark.get("only_faction", "")))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var standoff: float = HullMarks.STANDOFF_M - float(layer[3]) * HullMarks.PLACARD_STEP_M
		node.transform = Transform3D(basis, _vec(mark.get("position")) + normal.normalized() * standoff)
		out.append(node)
	return out


static func _board_material(colour: Color) -> StandardMaterial3D:
	var key: String = "board|%s" % colour.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.6
	m.metallic = 0.2
	_materials[key] = m
	return m


## A picture mark (`HullMarks.is_image`): one quad its size showing its image, sharp at any range (mipmapped, filtered
## anisotropically), with its flood's light added as the hull's baked pools add theirs. Null when the image is missing.
static func create_image(mark: Dictionary, dir: String) -> HullMarkNode:
	var path: String = dir.path_join(str(mark.get("image", "")))
	if not ResourceLoader.exists(path):
		return null
	var normal := _vec(mark.get("normal"))
	var basis: Basis = HullMarks.quad_basis(normal, _vec(mark.get("up")))
	var node := HullMarkNode.new()
	node.name = "Mark%s" % str(mark.get("name", "image")).to_pascal_case().validate_node_name()
	var quad := QuadMesh.new()
	quad.size = Vector2(float(mark.get("width_m", 10.0)), float(mark.get("height_m", 10.0)))
	node.mesh = quad
	var glow: Dictionary = mark.get("glow", {}) if mark.get("glow") is Dictionary else {}
	node.material_override = _image_material(path, dir.path_join(str(glow.get("file", ""))) if glow.has("file") else "", float(glow.get("energy", 0.0)))
	node.only_faction = StringName(str(mark.get("only_faction", "")))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.transform = Transform3D(basis, _vec(mark.get("position")) + normal.normalized() * HullMarks.STANDOFF_M)
	return node


static func _image_material(path: String, glow_path: String, energy: float) -> StandardMaterial3D:
	var key: String = "%s|%s|%s" % [path, glow_path, energy]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path) as Texture2D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 0.6
	m.metallic = 0.2
	if not glow_path.is_empty() and ResourceLoader.exists(glow_path) and energy > 0.0:
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission_texture = load(glow_path) as Texture2D
		m.emission_energy_multiplier = energy
	_materials[key] = m
	return m


static func _material(texture: Texture2D, path: String, cell: Vector2i, columns: int, colour: Color) -> StandardMaterial3D:
	var key: String = "%s|%d,%d|%s" % [path, cell.x, cell.y, colour.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.albedo_color = colour
	m.uv1_scale = Vector3(1.0 / columns, 1.0 / columns, 1.0)
	m.uv1_offset = Vector3(float(cell.x) / columns, float(cell.y) / columns, 0.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC  # crisp when the hull is seen edge-on
	m.roughness = 0.6
	m.metallic = 0.2
	_materials[key] = m
	return m


static func _vec(v: Variant) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() == 3 else Vector3.ZERO


static func _colour(v: Variant) -> Color:
	return Color(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() == 3 else Color(0.84, 0.85, 0.87)
