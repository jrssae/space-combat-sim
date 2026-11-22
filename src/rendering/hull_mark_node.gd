class_name HullMarkNode
extends MeshInstance3D
## One painted letter on a hull (M10-T21): a quad a little off the face, showing one cell of the generated glyph atlas. A thin
## adapter; the rules are in `HullMarks`.

## The faction this mark is painted for; empty for every ship's.
var only_faction: StringName = &""

static var _materials: Dictionary = {}  # "<atlas path>|<cell>|<colour>" -> StandardMaterial3D, shared by every ship


## The nodes for `marks` (from `hardpoints.json`) on a ship called `display_name`, or none when the hull has no atlas or the
## name gives no letter. `dir` is the asset's folder.
static func build_all(marks: Array[Dictionary], atlas: Dictionary, dir: String, display_name: String) -> Array[HullMarkNode]:
	var out: Array[HullMarkNode] = []
	var path: String = dir.path_join(str(atlas.get("file", "")))
	if marks.is_empty() or atlas.is_empty() or not ResourceLoader.exists(path):
		return out
	var texture: Texture2D = load(path) as Texture2D
	var chars: String = str(atlas.get("chars", ""))
	for mark: Dictionary in marks:
		var text: String = HullMarks.text_for(mark, display_name, chars, ShipNames.hull_number_of(display_name))
		for i: int in text.length():
			var node: HullMarkNode = create(mark, text, i, atlas, texture, path)
			if node != null:
				out.append(node)
	return out


## Character `index` of `text` on `mark`: letters of a longer text sit side by side, centred on the mark.
static func create(mark: Dictionary, text: String, index: int, atlas: Dictionary, texture: Texture2D, path: String) -> HullMarkNode:
	var cell: Vector2i = HullMarks.cell_of(text.substr(index, 1), atlas)
	if cell.x < 0:
		return null
	var height: float = float(mark.get("height_m", 10.0))
	var normal := _vec(mark.get("normal"))
	var basis: Basis = HullMarks.quad_basis(normal, _vec(mark.get("up")))
	var side: float = HullMarks.quad_side_m(height, atlas)
	var pitch: float = 0.8 * height  # a letter's advance, m
	var shift: float = (float(index) - 0.5 * float(text.length() - 1)) * pitch
	var node := HullMarkNode.new()
	node.name = "Mark%s%d" % [str(mark.get("name", "mark")).to_pascal_case().validate_node_name(), index]
	var quad := QuadMesh.new()
	quad.size = Vector2(side, side)
	node.mesh = quad
	node.material_override = _material(texture, path, cell, int(atlas.get("columns", 1)), _colour(mark.get("colour")))
	node.only_faction = StringName(str(mark.get("only_faction", "")))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.transform = Transform3D(basis, _vec(mark.get("position")) + normal.normalized() * HullMarks.STANDOFF_M + basis.x * shift)
	return node


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
	m.roughness = 0.6
	m.metallic = 0.2
	_materials[key] = m
	return m


static func _vec(v: Variant) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() == 3 else Vector3.ZERO


static func _colour(v: Variant) -> Color:
	return Color(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() == 3 else Color(0.84, 0.85, 0.87)
