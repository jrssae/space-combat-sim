class_name GameFonts
extends RefCounted
## The game's two fonts (M8-T21, D87): Babylon5 for titles and headlines, Babylon5Credits for body text and the whole HUD.
## Controls get them from the project theme (`THEME_PATH`, filled by `install`); code that draws its own text asks here, so
## no other font is loaded.
##
## Neither font has digits of one width, so a changing number would shift its neighbours: `draw_line` gives every digit a slot
## as wide as "0", and `line_width` measures that.

const TITLE_PATH: String = "res://assets/fonts/babylon5.ttf"
const BODY_PATH: String = "res://assets/fonts/babylon5_credits.ttf"
const THEME_PATH: String = "res://src/ui/game_theme.tres"
## The label variations of the theme that use the title font.
const TITLE_VARIATIONS: Array[StringName] = [&"Title", &"Headline", &"Heading"]
const _ZERO: int = 48
const _NINE: int = 57
const _PIECES_KEPT: int = 512

static var _title: Font = null
static var _body: Font = null
# A line's pieces by its text: the HUD draws the same captions every frame.
static var _pieces_by_text: Dictionary = {}


## Puts the two fonts into the project theme: the body font for every control, the title font for the title variations.
## Done when the game starts (the `Fonts` autoload) rather than in the theme's file, which the engine loads before a fresh
## checkout's first import, when a font file cannot be loaded yet.
static func install() -> void:
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null:
		push_error("GameFonts: no project theme (gui/theme/custom should be %s)" % THEME_PATH)
		return
	if theme.default_font == body():
		return
	theme.default_font = body()
	for variation: StringName in TITLE_VARIATIONS:
		theme.set_type_variation(variation, &"Label")
		theme.set_font(&"font", variation, title())


## Babylon5: titles and headlines.
static func title() -> Font:
	if _title == null:
		_title = load(TITLE_PATH) as Font
	return _title


## Babylon5Credits: body text and the HUD.
static func body() -> Font:
	if _body == null:
		_body = load(BODY_PATH) as Font
	return _body


## The width of one digit's slot at `px`.
static func digit_slot(font: Font, px: int) -> float:
	return font.get_char_size(_ZERO, px).x


## How wide `draw_line` draws `text`.
static func line_width(font: Font, text: String, px: int) -> float:
	var pieces: PackedStringArray = pieces_of(text)
	if pieces.size() == 1:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var slot: float = digit_slot(font, px)
	var width: float = 0.0
	for i: int in pieces.size():
		if i % 2 == 1:
			width += slot * float(pieces[i].length())
		elif not pieces[i].is_empty():
			width += font.get_string_size(pieces[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	return width


## Draws one line from `baseline`, every digit centred in its slot, so a number keeps its width whatever its digits.
static func draw_line(canvas: CanvasItem, font: Font, baseline: Vector2, text: String, px: int, color: Color) -> void:
	var pieces: PackedStringArray = pieces_of(text)
	if pieces.size() == 1:
		canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, color)
		return
	var slot: float = digit_slot(font, px)
	var x: float = baseline.x
	for i: int in pieces.size():
		var piece: String = pieces[i]
		if i % 2 == 1:
			for at: int in piece.length():
				var inset: float = (slot - font.get_char_size(piece.unicode_at(at), px).x) * 0.5
				canvas.draw_char(font, Vector2(x + inset, baseline.y), piece[at], px, color)
				x += slot
		elif not piece.is_empty():
			canvas.draw_string(font, Vector2(x, baseline.y), piece, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, color)
			x += font.get_string_size(piece, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x


## `text` cut where digits start and stop: other text at even places (the first may be empty), runs of digits at odd ones.
static func pieces_of(text: String) -> PackedStringArray:
	if _pieces_by_text.has(text):
		return _pieces_by_text[text]
	var pieces := PackedStringArray()
	var start: int = 0
	var in_digits: bool = false
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		var digit: bool = code >= _ZERO and code <= _NINE
		if digit != in_digits:
			pieces.append(text.substr(start, i - start))
			start = i
			in_digits = digit
	pieces.append(text.substr(start))
	if _pieces_by_text.size() >= _PIECES_KEPT:
		_pieces_by_text.clear()
	_pieces_by_text[text] = pieces
	return pieces
