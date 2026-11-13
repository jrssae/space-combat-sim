class_name PieceSections
extends RefCounted
## A big piece's sections and near-only props as the generator lists them (M7-T19, D72): the piece's mesh cut across its length
## into sections, each its own mesh with its own origin, so the engine picks a level of detail per section (its levels come from
## the importer, chosen per instance from its bounds) and culls the sections out of view; and the props, small parts drawn
## instanced under a section only within a near range. Pure: `RenderPiece` builds the nodes from it.
##
## The hull's sections have no visibility range: together they are the hull, drawn at every distance the piece is (the far prop
## shrinks them past the far plane). Only the props fade out, past `near_m`, where the piece's atlas carries their painted
## stand-in. No light in the game casts shadows (the key star and the light slots have them off), so nothing here casts one.

## How each section and prop is drawn with respect to shadows: off (see above).
const CAST_SHADOW: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
## How far two neighbours' cut planes may disagree, m.
const JOIN_TOLERANCE_M: float = 0.01

## Each section, in the generator's order (bow to stern): `name`, `file`, `origin` (Vector3, the piece's frame), `aabb` (AABB about
## its origin), `z0` and `z1` (its slab, -INF and INF at the open ends), `triangles`.
var sections: Array[Dictionary] = []
## The props' draw range: shown within `near_m`, faded out over `margin_m`.
var near_m: float = 0.0
var margin_m: float = 0.0
## The prop atlas's surface (a textured mesh surface entry: the four maps, the glow strength).
var prop_surface: Dictionary = {}
## Each prop kind's mesh file, by kind.
var prop_files: Dictionary = {}
## A kind's own draw range where it has one (M7-T05: the Cobra bays' door leaves are the doors, drawn as far as the hull), by kind.
var prop_near: Dictionary = {}
## Each group of props: `kind`, `section`, `transforms` (Array[Transform3D] in the section's frame), `aabb` (in that frame).
var prop_groups: Array[Dictionary] = []


## The sections of a piece's `mesh` entry and its `props` entry; null when it has no sections or they do not tile the piece (a
## gap, an overlap or a section without a file), so the caller draws the whole mesh instead.
static func from_entry(mesh_entry: Dictionary, props_entry: Dictionary = {}) -> PieceSections:
	var listed: Array = mesh_entry.get("sections", [])
	if listed.is_empty():
		return null
	var made := PieceSections.new()
	for item: Variant in listed:
		if not item is Dictionary or String((item as Dictionary).get("file", "")).is_empty():
			return null
		var s: Dictionary = item
		var z0: Variant = s.get("z0")
		var z1: Variant = s.get("z1")
		made.sections.append({
			"name": String(s.get("name", "")),
			"file": String(s["file"]),
			"origin": _vec(s.get("origin", [0.0, 0.0, 0.0])),
			"aabb": _box(s.get("aabb_min", [0.0, 0.0, 0.0]), s.get("aabb_max", [0.0, 0.0, 0.0])),
			"z0": -INF if z0 == null else float(z0),
			"z1": INF if z1 == null else float(z1),
			"triangles": int(s.get("triangles", 0)),
		})
	if not made.is_contiguous():
		push_warning("PieceSections: the sections do not tile the piece; it is drawn whole")
		return null
	made._read_props(props_entry)
	return made


## Whether the sections run end to end: open at both ends, each starting where the last ended.
func is_contiguous() -> bool:
	if sections.is_empty() or sections[0]["z0"] != -INF or sections[-1]["z1"] != INF:
		return false
	for k: int in range(1, sections.size()):
		if absf(float(sections[k]["z0"]) - float(sections[k - 1]["z1"])) > JOIN_TOLERANCE_M:
			return false
	return true


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in sections:
		out.append(String(s["name"]))
	return out


## The section named `name`, or {}.
func find(name: String) -> Dictionary:
	for s: Dictionary in sections:
		if s["name"] == name:
			return s
	return {}


## The name of the section whose slab holds `z` (the piece's frame); a point on a cut belongs to the section aft of it.
func section_at(z: float) -> String:
	for s: Dictionary in sections:
		if z >= float(s["z0"]) and z < float(s["z1"]):
			return String(s["name"])
	return ""


## Every section's box together, in the piece's frame.
func bounds() -> AABB:
	var out := AABB()
	for k: int in sections.size():
		var box: AABB = sections[k]["aabb"]
		box.position += sections[k]["origin"] as Vector3
		out = box if k == 0 else out.merge(box)
	return out


## The props' groups in the section named `section`.
func groups_in(section: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: Dictionary in prop_groups:
		if g["section"] == section:
			out.append(g)
	return out


## The draw range a prop group's instance gets: `end` and `end_margin` for its visibility range, and the fade; a kind with a
## range of its own (`kind`) gets that.
func prop_range(kind: String = "") -> Dictionary:
	return {"end": float(prop_near.get(kind, near_m)), "end_margin": margin_m, "fade": GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF}


## A transform as the manifest writes it: the basis' x, y and z columns, then the origin (12 numbers).
static func transform_of(flat: Array) -> Transform3D:
	if flat.size() != 12:
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(flat[0], flat[1], flat[2]), Vector3(flat[3], flat[4], flat[5]), Vector3(flat[6], flat[7], flat[8])),
			Vector3(flat[9], flat[10], flat[11]))


func _read_props(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	near_m = float(entry.get("near_m", 0.0))
	margin_m = float(entry.get("margin_m", 0.0))
	prop_surface = entry.get("surface", {})
	var kinds: Dictionary = entry.get("kinds", {})
	for kind: String in kinds:
		prop_files[kind] = String((kinds[kind] as Dictionary).get("file", ""))
		if (kinds[kind] as Dictionary).has("near_m"):
			prop_near[kind] = float((kinds[kind] as Dictionary)["near_m"])
	for item: Variant in entry.get("groups", []):
		var g: Dictionary = item
		var kind: String = String(g.get("kind", ""))
		if not prop_files.has(kind) or find(String(g.get("section", ""))).is_empty():
			push_warning("PieceSections: prop group %s in %s names an unknown kind or section" % [kind, g.get("section", "")])
			continue
		var transforms: Array[Transform3D] = []
		for flat: Variant in g.get("transforms", []):
			transforms.append(transform_of(flat as Array))
		prop_groups.append({"kind": kind, "section": String(g["section"]), "transforms": transforms,
				"aabb": _box(g.get("aabb_min", [0.0, 0.0, 0.0]), g.get("aabb_max", [0.0, 0.0, 0.0]))})


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO


static func _box(lo: Array, hi: Array) -> AABB:
	var a: Vector3 = _vec(lo)
	return AABB(a, _vec(hi) - a)
