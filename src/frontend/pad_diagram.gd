class_name PadDiagram
extends Control
## A generic XInput controller drawn in code with a legend of what each button does (architecture §18, D57, Q15). The outline,
## sticks, D-pad, face buttons, bumpers, triggers, Back and Start are original line art, no image. The legend is a
## `PadLegend`, so a rebind redraws it; the controls page can light the buttons of the action in focus.

const DESIGN: Vector2 = Vector2(900.0, 300.0)  # the layout's own units: the pad in the middle, the legend either side
const PAD_OFFSET: Vector2 = Vector2(240.0, 12.0)
const LEGEND_EDGE_LEFT: float = 224.0
const LEGEND_EDGE_RIGHT: float = 676.0
const FONT_DESIGN: float = 17.0
const LINE: Color = Color(0.55, 1.0, 0.6)
const LIT: Color = Color(1.0, 0.85, 0.3)

# The left half of the outline, top centre round to bottom centre (pad units); the right half mirrors it.
const _BODY_LEFT: PackedVector2Array = [
	Vector2(210, 56), Vector2(160, 52), Vector2(118, 50), Vector2(86, 56), Vector2(62, 74), Vector2(44, 110),
	Vector2(30, 160), Vector2(24, 206), Vector2(30, 234), Vector2(48, 246), Vector2(68, 240), Vector2(86, 222),
	Vector2(108, 194), Vector2(132, 180), Vector2(170, 176), Vector2(210, 176),
]
const _PAD_WIDTH: float = 420.0
const _CIRCLES: Dictionary = {
	&"a": [Vector2(318, 120), 10.0], &"b": [Vector2(338, 100), 10.0], &"x": [Vector2(298, 100), 10.0],
	&"y": [Vector2(318, 80), 10.0], &"back": [Vector2(186, 98), 6.0], &"start": [Vector2(234, 98), 6.0],
	&"l3": [Vector2(100, 100), 14.0], &"r3": [Vector2(270, 148), 14.0],
}
const _STICK_RINGS: Array[Array] = [[Vector2(100, 100), 26.0], [Vector2(270, 148), 26.0]]
const _RECTS: Dictionary = {
	&"lt": Rect2(96, 16, 44, 22), &"rt": Rect2(280, 16, 44, 22), &"lb": Rect2(84, 42, 68, 14), &"rb": Rect2(268, 42, 68, 14),
	&"dpad_up": Rect2(142, 128, 16, 20), &"dpad_down": Rect2(142, 148, 16, 20),
	&"dpad_left": Rect2(130, 140, 20, 16), &"dpad_right": Rect2(150, 140, 20, 16),
}
# Where a legend line's leader meets the pad. The face buttons carry their letter, so they need none.
const _ANCHORS: Dictionary = {
	&"lt": Vector2(96, 27), &"lb": Vector2(84, 49), &"ls": Vector2(76, 100), &"l3": Vector2(90, 112),
	&"dpad_up": Vector2(142, 138), &"dpad_down": Vector2(142, 158), &"dpad_left": Vector2(130, 148), &"dpad_right": Vector2(150, 148),
	&"back": Vector2(180, 98), &"rt": Vector2(324, 27), &"rb": Vector2(336, 49), &"rs": Vector2(296, 148), &"r3": Vector2(282, 160),
	&"start": Vector2(240, 98), &"a": Vector2(328, 124), &"b": Vector2(348, 100), &"x": Vector2(288, 100), &"y": Vector2(318, 70),
}
const _LEFT_SIDE: Array[StringName] = [&"lt", &"lb", &"ls", &"l3", &"dpad_up", &"dpad_down", &"dpad_left", &"dpad_right", &"back"]
const _LETTERED: Array[StringName] = [&"a", &"b", &"x", &"y"]

var legend: PadLegend = PadLegend.new()
var _lit: Array[StringName] = []


func _ready() -> void:
	custom_minimum_size = Vector2(240.0, 100.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Asks for the diagram to be at least `width` wide at the layout's own proportions (a compact page); 0 returns to the
## default minimum, and the box stretches.
func set_min_width(width: float) -> void:
	custom_minimum_size = Vector2(width, width * DESIGN.y / DESIGN.x) if width > 0.0 else Vector2(240.0, 100.0)


func set_legend(new_legend: PadLegend) -> void:
	legend = new_legend
	queue_redraw()


## Lights these pad parts (the controls page: the action in focus). An empty list lights nothing.
func set_highlight(widgets: Array[StringName]) -> void:
	_lit = widgets.duplicate()
	queue_redraw()


func highlighted() -> Array[StringName]:
	return _lit.duplicate()


## The legend as it is listed beside the pad: "TAG  what it does", left side then right, top to bottom.
func rows_text() -> PackedStringArray:
	var out := PackedStringArray()
	for side_left: bool in [true, false]:
		for widget: StringName in _sorted_side(side_left):
			out.append(_row_text(widget))
	return out


## Tops for rows of height `row_h` that would sit on `centers` (ascending), pushed apart so none overlap and kept inside
## `top`..`bottom`. The legend lists several buttons that are close together on the pad.
static func stack_rows(centers: PackedFloat32Array, row_h: float, top: float, bottom: float) -> PackedFloat32Array:
	var tops := PackedFloat32Array()
	tops.resize(centers.size())
	var next: float = top
	for i: int in centers.size():
		tops[i] = maxf(centers[i] - row_h * 0.5, next)
		next = tops[i] + row_h
	var limit: float = bottom
	for i: int in range(centers.size() - 1, -1, -1):
		tops[i] = minf(tops[i], limit - row_h)
		limit = tops[i]
	return tops


func _draw() -> void:
	var fit: float = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	if fit <= 0.0:
		return
	var origin: Vector2 = (size - DESIGN * fit) * 0.5
	var font: Font = get_theme_default_font()
	var font_size: int = clampi(roundi(FONT_DESIGN * fit), 9, 30)
	var rows: Array[Dictionary] = _layout_rows(fit, origin, font, font_size)
	for row: Dictionary in rows:  # leaders first, so the parts of the pad cover them
		if not _LETTERED.has(row["widget"]):
			var from: Vector2 = _map(PAD_OFFSET + (_ANCHORS[row["widget"]] as Vector2), fit, origin)
			var to := Vector2(origin.x + (LEGEND_EDGE_LEFT if row["left"] else LEGEND_EDGE_RIGHT) * fit + (4.0 if row["left"] else -4.0) * fit, row["y"])
			draw_line(from, to, Color(LINE.r, LINE.g, LINE.b, 0.35), maxf(1.0, fit))
	_draw_body(fit, origin)
	_draw_parts(fit, origin, font, font_size)
	for row: Dictionary in rows:
		var lit: bool = _lit.has(row["widget"])
		var color: Color = LIT if lit else Color(LINE.r, LINE.g, LINE.b, 0.95)
		var edge: float = origin.x + (LEGEND_EDGE_LEFT if row["left"] else LEGEND_EDGE_RIGHT) * fit
		var baseline: float = row["y"] + font.get_ascent(font_size) * 0.5 - font.get_descent(font_size) * 0.5
		if row["left"]:
			draw_string(font, Vector2(origin.x, baseline), row["text"], HORIZONTAL_ALIGNMENT_RIGHT, edge - origin.x, font_size, color)
		else:
			draw_string(font, Vector2(edge, baseline), row["text"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_body(fit: float, origin: Vector2) -> void:
	var outline := PackedVector2Array()
	for point: Vector2 in _body_points():
		outline.append(_map(PAD_OFFSET + point, fit, origin))
	draw_colored_polygon(outline, Color(0.02, 0.06, 0.05, 0.9))
	outline.append(outline[0])
	draw_polyline(outline, Color(LINE.r, LINE.g, LINE.b, 0.8), maxf(1.5, 2.0 * fit), true)


func _draw_parts(fit: float, origin: Vector2, font: Font, font_size: int) -> void:
	var bound: Array[StringName] = legend.widgets()
	for ring: Array in _STICK_RINGS:
		draw_arc(_map(PAD_OFFSET + (ring[0] as Vector2), fit, origin), (ring[1] as float) * fit, 0.0, TAU, 32,
				Color(LINE.r, LINE.g, LINE.b, 0.6), maxf(1.0, 1.5 * fit), true)
	var stick_fill: Dictionary = {&"ls": Vector2(100, 100), &"rs": Vector2(270, 148)}
	for widget: StringName in stick_fill:
		if bound.has(widget) or _lit.has(widget):
			draw_circle(_map(PAD_OFFSET + (stick_fill[widget] as Vector2), fit, origin), 22.0 * fit, _fill_of(widget, bound))
	for widget: StringName in _RECTS:
		var rect: Rect2 = _RECTS[widget]
		var mapped := Rect2(_map(PAD_OFFSET + rect.position, fit, origin), rect.size * fit)
		draw_rect(mapped, Color(0.02, 0.06, 0.05, 1.0), true)
		draw_rect(mapped, _fill_of(widget, bound), true)
		draw_rect(mapped, _edge_of(widget, bound), false, maxf(1.0, 1.5 * fit))
	for widget: StringName in _CIRCLES:
		var spec: Array = _CIRCLES[widget]
		var center: Vector2 = _map(PAD_OFFSET + (spec[0] as Vector2), fit, origin)
		var radius: float = (spec[1] as float) * fit
		draw_circle(center, radius, Color(0.02, 0.06, 0.05, 1.0))
		draw_circle(center, radius, _fill_of(widget, bound))
		draw_arc(center, radius, 0.0, TAU, 24, _edge_of(widget, bound), maxf(1.0, 1.5 * fit), true)
		if _LETTERED.has(widget):
			var letter: String = PadLegend.tag_of(widget)
			var width: float = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
			draw_string(font, center + Vector2(-width * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5),
					letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _edge_of(widget, bound))


func _fill_of(widget: StringName, bound: Array[StringName]) -> Color:
	if _lit.has(widget):
		return Color(LIT.r, LIT.g, LIT.b, 0.65)
	return Color(LINE.r, LINE.g, LINE.b, 0.28) if bound.has(widget) else Color(0, 0, 0, 0)


func _edge_of(widget: StringName, bound: Array[StringName]) -> Color:
	if _lit.has(widget):
		return LIT
	return Color(LINE.r, LINE.g, LINE.b, 0.95 if bound.has(widget) else 0.4)


# One entry per legend line: {widget, left, text, y} with y in pixels, the rows of each side kept apart.
func _layout_rows(fit: float, origin: Vector2, font: Font, font_size: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var row_h: float = font.get_height(font_size) * 1.15
	for side_left: bool in [true, false]:
		var widgets: Array[StringName] = _sorted_side(side_left)
		var centers := PackedFloat32Array()
		for widget: StringName in widgets:
			centers.append(_map(PAD_OFFSET + (_ANCHORS[widget] as Vector2), fit, origin).y)
		var tops: PackedFloat32Array = stack_rows(centers, row_h, 0.0, size.y)
		for i: int in widgets.size():
			rows.append({"widget": widgets[i], "left": side_left, "text": _row_text(widgets[i]), "y": tops[i] + row_h * 0.5})
	return rows


# The legend's widgets on one side of the pad, top to bottom by where they sit.
func _sorted_side(left: bool) -> Array[StringName]:
	var out: Array[StringName] = []
	for widget: StringName in legend.widgets():
		if _LEFT_SIDE.has(widget) == left:
			out.append(widget)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return (_ANCHORS[a] as Vector2).y < (_ANCHORS[b] as Vector2).y)
	return out


func _row_text(widget: StringName) -> String:
	return "%s  %s" % [PadLegend.tag_of(widget), legend.label_for(widget)]


static func _body_points() -> PackedVector2Array:
	var points := PackedVector2Array(_BODY_LEFT)
	for i: int in range(_BODY_LEFT.size() - 2, 0, -1):
		points.append(Vector2(_PAD_WIDTH - _BODY_LEFT[i].x, _BODY_LEFT[i].y))
	return points


static func _map(design: Vector2, fit: float, origin: Vector2) -> Vector2:
	return origin + design * fit
