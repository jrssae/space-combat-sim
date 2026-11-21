class_name HullMarks
extends RefCounted
## Painted hull lettering (M10-T21): the pure rules behind the letters and numbers on a hull. The generator leaves `marks` in
## `hardpoints.json` (each a place, a face normal, an up and a height) and one glyph atlas (`tools/procgen/core/glyphs.py`); a ship
## picks the text for each mark when it spawns, so every Omega carries the first letter of its own name. Nodes live in
## `HullMarkNode`.

## What a mark's `text` says when it is the ship's initial.
const INITIAL: String = "initial"
## How far a letter floats off the hull face, m, so it never z-fights the plating.
const STANDOFF_M: float = 0.6


## The text mark `mark` shows on a ship called `display_name`: the ship's initial, or the mark's own string. Uppercase; "" when
## nothing printable is left.
static func text_for(mark: Dictionary, display_name: String, chars: String) -> String:
	var text: String = str(mark.get("text", INITIAL))
	if text == INITIAL:
		text = initial_of(display_name)
	var out: String = ""
	for c: String in text.to_upper():
		if chars.contains(c):
			out += c
	return out


## Whether `mark` is painted on a ship of `faction`: a mark with no `only_faction` is on every ship (the renegades' red X is not).
static func shown_for(mark: Dictionary, faction: StringName) -> bool:
	var only: String = str(mark.get("only_faction", ""))
	return only.is_empty() or only == String(faction)


## The first letter of the ship's own name: "EAS Agamemnon" gives "A" (a leading all-capitals word is the faction's prefix).
static func initial_of(display_name: String) -> String:
	var words: PackedStringArray = display_name.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	var skip: int = 1 if words.size() > 1 and words[0].length() >= 2 and words[0] == words[0].to_upper() and words[0].to_upper() != words[0].to_lower() else 0
	return words[skip].substr(0, 1).to_upper()


## The atlas cell (column, row) of `char`, or (-1, -1) when the atlas has no such glyph.
static func cell_of(char: String, atlas: Dictionary) -> Vector2i:
	var chars: String = str(atlas.get("chars", ""))
	var columns: int = maxi(int(atlas.get("columns", 1)), 1)
	var at: int = chars.find(char)
	return Vector2i(-1, -1) if at < 0 or char.is_empty() else Vector2i(at % columns, at / columns)


## The quad's side, m, for letters `height_m` tall: the glyph fills only part of its square cell.
static func quad_side_m(height_m: float, atlas: Dictionary) -> float:
	return height_m / maxf(float(atlas.get("glyph_height_share", 1.0)), 0.1)


## The basis of a quad that reads upright and left to right from outside the face: its +Z is the face normal and its Y the way
## the letters stand (made square to the normal).
static func quad_basis(normal: Vector3, up: Vector3) -> Basis:
	var n: Vector3 = normal.normalized()
	var u: Vector3 = (up - n * up.dot(n)).normalized()
	return Basis(u.cross(n), u, n)


## The marks in a hardpoints dictionary (empty when the hull carries none).
static func marks_of(hardpoints: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hardpoints.get("marks") is Array:
		for m: Variant in hardpoints["marks"]:
			if m is Dictionary:
				out.append(m)
	return out
