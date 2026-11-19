class_name ReadoutText
extends Control
## Lines of readout text in the game's body font with fixed digit slots (M8-T21): what the debug overlay and the FPS counter
## show. A Label cannot hold a changing number still in this font. With `columns` each line's cells stand in
## `ReadoutColumns`' columns; with `align_right` the lines end at the right edge.

const SHADOW_OFFSET: Vector2 = Vector2(1.5, 1.5)

var text: String = "":
	set = set_text
var font_size: int = 16:
	set = set_font_size
var color: Color = Color.WHITE
var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.85)
var columns: bool = false
var align_right: bool = false

var _lines: PackedStringArray = PackedStringArray()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_text(value: String) -> void:
	if value == text:
		return
	text = value
	_lines = text.split("\n") if not text.is_empty() else PackedStringArray()
	update_minimum_size()
	queue_redraw()


func set_font_size(value: int) -> void:
	font_size = value
	update_minimum_size()
	queue_redraw()


func line_count() -> int:
	return _lines.size()


## The height of the text, px.
func text_height() -> float:
	return GameFonts.body().get_height(font_size) * float(_lines.size())


## Each cell of line `index` with the x it starts at, as it is drawn.
func placed(index: int) -> Array[Dictionary]:
	var font: Font = GameFonts.body()
	var line: String = _lines[index]
	if columns:
		return ReadoutColumns.place(line, float(font_size), func(cell: String) -> float: return GameFonts.line_width(font, cell, font_size))
	var x: float = size.x - GameFonts.line_width(font, line, font_size) if align_right else 0.0
	return [{"text": line, "x": x}]


func _get_minimum_size() -> Vector2:
	var font: Font = GameFonts.body()
	var width: float = 0.0
	if not columns:  # a column readout is not sized by its text: its lines must not move the layout around it
		for line: String in _lines:
			width = maxf(width, GameFonts.line_width(font, line, font_size))
	return Vector2(ceilf(width), ceilf(text_height()))


func _draw() -> void:
	var font: Font = GameFonts.body()
	var step: float = font.get_height(font_size)
	var baseline: float = font.get_ascent(font_size)
	for i: int in _lines.size():
		for cell: Dictionary in placed(i):
			var at := Vector2(float(cell["x"]), baseline + step * float(i))
			GameFonts.draw_line(self, font, at + SHADOW_OFFSET, cell["text"], font_size, shadow_color)
			GameFonts.draw_line(self, font, at, cell["text"], font_size, color)
