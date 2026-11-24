class_name HullMarks
extends RefCounted
## Painted hull lettering (M10-T21): the pure rules behind the letters and numbers on a hull. The generator leaves `marks` in
## `hardpoints.json` (each a place, a face normal, an up and a height) and one glyph atlas (`tools/procgen/core/glyphs.py`); a ship
## picks the text for each mark when it spawns, so every Omega carries the first letter of its own name and every Hyperion its
## whole name (M10-T22). Nodes live in `HullMarkNode`.

## What a mark's `text` says when it is the ship's initial.
const INITIAL: String = "initial"
## What a mark's `text` says when it is the ship's whole name.
const NAME: String = "name"
## What a mark's `text` says when it is the ship's hull number.
const NUMBER: String = "number"
## How far a letter floats off the hull face, m, so it never z-fights the plating.
const STANDOFF_M: float = 0.6
## How far behind its letters a name board's panel sits, and its line behind the panel, m: apart, so neither flickers.
const PLACARD_STEP_M: float = 0.08


## The text mark `mark` shows on a ship called `display_name`: the ship's initial, its name, or the mark's own string. Uppercase,
## spaces kept as gaps between words; "" when nothing printable is left.
static func text_for(mark: Dictionary, display_name: String, chars: String, hull_number: String = "") -> String:
	var text: String = str(mark.get("text", INITIAL))
	if text == INITIAL:
		text = initial_of(display_name)
	elif text == NAME:
		text = name_of(display_name)
	elif text == NUMBER:
		text = hull_number
	var out: String = ""
	for c: String in text.to_upper():
		if chars.contains(c) or (c == " " and not out.is_empty() and not out.ends_with(" ")):
			out += c
	return out.strip_edges()


## Whether `mark` is painted on a ship of `faction`: a mark with no `only_faction` is on every ship (the renegades' red X is not).
static func shown_for(mark: Dictionary, faction: StringName) -> bool:
	var only: String = str(mark.get("only_faction", ""))
	return only.is_empty() or only == String(faction)


## The first letter of the ship's own name: "EAS Agamemnon" gives "A" (a leading all-capitals word is the faction's prefix).
static func initial_of(display_name: String) -> String:
	return name_of(display_name).substr(0, 1).to_upper()


## The ship's own name without its faction's prefix: "EAS Lexington 2" gives "Lexington 2".
static func name_of(display_name: String) -> String:
	var words: PackedStringArray = display_name.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	var skip: int = 1 if words.size() > 1 and words[0].length() >= 2 and words[0] == words[0].to_upper() and words[0].to_upper() != words[0].to_lower() else 0
	return " ".join(words.slice(skip))


## Whether `mark` is a picture (the Earth Alliance emblem, M10-T22) rather than lettering: it names its own image file.
static func is_image(mark: Dictionary) -> bool:
	return mark.get("image") is String and not str(mark["image"]).is_empty()


## The atlas file `mark`'s letters are printed from: the outlined print for a mark that asks for a black outline (the Hyperion's
## bow name and hull number), the plain one otherwise or when the hull has no outlined print.
static func atlas_file(mark: Dictionary, atlas: Dictionary) -> String:
	if bool(mark.get("outline", false)) and str(atlas.get("outlined_file", "")) != "":
		return str(atlas["outlined_file"])
	return str(atlas.get("file", ""))


## The atlas cell (column, row) of `char`, or (-1, -1) when the atlas has no such glyph.
static func cell_of(char: String, atlas: Dictionary) -> Vector2i:
	var chars: String = str(atlas.get("chars", ""))
	var columns: int = maxi(int(atlas.get("columns", 1)), 1)
	var at: int = chars.find(char)
	return Vector2i(-1, -1) if at < 0 or char.is_empty() else Vector2i(at % columns, at / columns)


## Where each character of `text` sits along the mark, in letter heights from the text's centre: the atlas's own widths and
## tracking (`tools/procgen/core/glyphs.py`) when it has them, an even 0.8 pitch when it does not. `stretch` widens the print.
static func offsets(text: String, atlas: Dictionary, stretch: float = 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var tracking: float = float(atlas.get("tracking", 0.0))
	var pen: float = 0.0
	for c: String in text:
		var w: float = _char_width(c, atlas)
		out.append((pen + 0.5 * w) * stretch)
		pen += w + tracking
	var middle: float = 0.5 * text_width(text, atlas, stretch)
	for i: int in out.size():
		out[i] -= middle
	return out


## How wide `text` prints, in letter heights, as `offsets` lays it out.
static func text_width(text: String, atlas: Dictionary, stretch: float = 1.0) -> float:
	var tracking: float = float(atlas.get("tracking", 0.0))
	var pen: float = 0.0
	for c: String in text:
		pen += _char_width(c, atlas) + tracking
	return maxf(pen - tracking, 0.0) * stretch


static func _char_width(c: String, atlas: Dictionary) -> float:
	if c == " ":
		return float(atlas.get("space", 0.32))
	var widths: Array = atlas.get("widths", []) if atlas.get("widths") is Array else []
	var at: int = str(atlas.get("chars", "")).find(c)
	if at >= 0 and at < widths.size():
		return float(widths[at])
	return 0.8 - float(atlas.get("tracking", 0.0))


## The board behind `text` on `mark` (its `placard`: the destroyers' name boards, M10-T67), m: the panel the letters sit on, its
## margin clear of them all round, and its black line's width. Zero when the mark has no board or no text.
static func placard_size(mark: Dictionary, text: String, atlas: Dictionary) -> Vector2:
	var board: Dictionary = mark.get("placard", {}) if mark.get("placard") is Dictionary else {}
	if board.is_empty() or text.is_empty():
		return Vector2.ZERO
	var height: float = float(mark.get("height_m", 10.0))
	var margin: float = 2.0 * float(board.get("margin", 0.35)) * height
	return Vector2(text_width(text, atlas, float(mark.get("stretch", 1.0))) * height + margin, height + margin)


## The width of the line round a mark's board, m.
static func placard_line_m(mark: Dictionary) -> float:
	var board: Dictionary = mark.get("placard", {}) if mark.get("placard") is Dictionary else {}
	return float(board.get("line_width", 0.0)) * float(mark.get("height_m", 10.0))


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
