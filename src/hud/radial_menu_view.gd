class_name RadialMenuView
extends CanvasLayer
## Draws a `RadialMenu` (architecture §18.19, M5-T25): the ring vertically centred at the left side (`RadialLayout`), the
## highlighted slice lit, each entry's label and second line in its colour, the stick's pointer in the hub, the page's
## heading at the top and a hint under the ring. It runs while the game is paused, and only while it shows: closed, it is
## hidden and does not process. Above the HUD (40) and the comms menu (42), below the debug overlay (50) and the pause menu
## (60). The focus pull (T44, `FocusPullView`, layer 44) blurs and dims everything under it while the menu shows.

const LAYER: int = 45
const HUB_COLOR: Color = Color(0.0, 0.0, 0.0, 0.6)
const PLATE_ALPHA: float = 0.72
const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)
## Text sizes at 1080 px high.
const LABEL_PX: float = 22.0
const SUB_PX: float = 16.0
const HEADING_PX: float = 26.0
const HINT_PX: float = 20.0
const MIN_TEXT_PX: int = 9
## A label too wide for its slice shrinks to this share of its size before it is cut.
const MIN_LABEL_SHARE: float = 0.6

var menu: RadialMenu = null
## The direction last pointed (x right, y up, 0..1): the pointer in the hub.
var pointer: Vector2 = Vector2.ZERO
## The line under the ring: what select and back do on this page.
var hint: String = ""
## The ring sits at the right side instead (T43's panel then takes the left).
var right_side: bool = false

## What the last draw put on screen (tests read it).
var drawn_centre: Vector2 = Vector2.ZERO
var drawn_radius: float = 0.0
var drawn_labels: Array[String] = []
var drawn_heading: String = ""
var draws: int = 0

var _canvas: RingCanvas = null
var _focus: FocusPullView = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = RingCanvas.new()
	_canvas.name = "RingCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.view = self
	add_child(_canvas)
	# A sibling, not a child: it must go on easing back after this layer hides.
	_focus = FocusPullView.new()
	_focus.name = "FocusPull"
	if get_parent() != null:
		get_parent().add_child.call_deferred(_focus)
	else:
		add_child(_focus)
	set_showing(false)


func _exit_tree() -> void:
	if _focus != null and is_instance_valid(_focus) and _focus.get_parent() != self:
		_focus.queue_free()


## Shows or hides the layer; hidden, it does no work at all.
func set_showing(showing: bool) -> void:
	visible = showing
	set_process(showing)
	if _focus != null:
		_focus.set_open(showing)
	if showing:
		refresh()


## The focus pull's eased amount now, 0..1 (0 sharp).
func focus_amount() -> float:
	return _focus.amount() if _focus != null else 0.0


## The model changed (a new highlight, a new page): draw it.
func refresh() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _process(_delta: float) -> void:
	refresh()  # the window may resize under an open menu


## Draws the menu on `canvas`. Called from the canvas's `_draw`.
func paint(canvas: Control) -> void:
	drawn_labels = []
	if menu == null or not menu.is_open():
		return
	var size: Vector2 = canvas.size
	var outer: float = RadialLayout.outer_radius(size)
	var inner: float = RadialLayout.inner_radius(size)
	var at: Vector2 = RadialLayout.centre(size, right_side)
	var s: float = outer / RadialLayout.OUTER_PX
	var count: int = menu.slice_count()
	var tint: Color = menu.color()
	var rim := Color(tint.r, tint.g, tint.b, 0.55)
	var font: Font = HudPainter.font()
	canvas.draw_circle(at, outer, Color(tint.r * 0.08, tint.g * 0.08, tint.b * 0.08, PLATE_ALPHA))
	canvas.draw_circle(at, inner, HUB_COLOR)
	var slots: Array[Dictionary] = menu.slots()
	var lit: int = menu.highlight()
	if lit >= 0:
		var lit_color: Color = slots[lit].get("color", tint)
		var polygon: PackedVector2Array = RadialLayout.slice_polygon(at, inner, outer, lit, count)
		canvas.draw_colored_polygon(polygon, Color(lit_color.r, lit_color.g, lit_color.b, 0.36))
		polygon.append(polygon[0])
		canvas.draw_polyline(polygon, lit_color, maxf(3.0 * s, 1.5), true)
	canvas.draw_arc(at, outer, 0.0, TAU, 96, rim, maxf(2.0 * s, 1.0), true)
	canvas.draw_arc(at, inner, 0.0, TAU, 64, rim, maxf(2.0 * s, 1.0), true)
	for i: int in count:
		var line: PackedVector2Array = RadialLayout.spoke(at, inner, outer, i, count)
		canvas.draw_line(line[0], line[1], rim, maxf(2.0 * s, 1.0), true)
	# Each label may be as wide as its slice is at the labels' radius.
	var room: float = 2.0 * RadialLayout.label_radius(size) * sin(PI / float(maxi(count, 2))) * 0.92
	for i: int in count:
		var slot: Dictionary = slots[i]
		if slot.is_empty():
			drawn_labels.append("")
			continue
		var color: Color = slot.get("color", tint)
		if i == lit:
			color = color.lerp(Color.WHITE, 0.35)
		var middle: Vector2 = RadialLayout.label_pos(at, RadialLayout.label_radius(size), i, count)
		var sub: String = str(slot.get("sub", ""))
		var label: String = str(slot.get("label", ""))
		_centred(canvas, font, label, middle + Vector2(0.0, (-2.0 if not sub.is_empty() else 8.0) * s), LABEL_PX * s, color, room)
		if not sub.is_empty():
			_centred(canvas, font, sub, middle + Vector2(0.0, 22.0 * s), SUB_PX * s, Color(color.r, color.g, color.b, 0.85), room)
		drawn_labels.append(label)
	# The stick in the hub.
	var line_color: Color = Factions.HUD_LINE_COLOR
	canvas.draw_line(at, RadialLayout.pointer_tip(at, inner, pointer), line_color, maxf(3.0 * s, 1.5), true)
	canvas.draw_circle(at, maxf(6.0 * s, 2.5), line_color)
	drawn_heading = menu.title()
	_centred(canvas, font, drawn_heading, Vector2(size.x * 0.5, RadialLayout.HEADING_Y_PX * RadialLayout.scale_for(size)),
			HEADING_PX * RadialLayout.scale_for(size), line_color, size.x)
	_centred(canvas, font, hint, at + Vector2(0.0, outer + RadialLayout.HINT_BELOW_PX * s), HINT_PX * s, line_color, size.x)
	var detail: String = str(menu.highlighted().get("detail", ""))
	if not detail.is_empty():
		var x: float = clampf(at.x, size.x * 0.25, size.x * 0.75)
		_centred(canvas, font, detail, Vector2(x, at.y + outer + RadialLayout.DETAIL_BELOW_PX * s), SUB_PX * s, line_color, size.x * 0.5)
	drawn_centre = at
	drawn_radius = outer
	draws += 1


# One line centred on `middle`, shrunk and then cut to fit `room`, with a shadow so it reads over a bright view.
func _centred(canvas: Control, font: Font, text: String, middle: Vector2, px: float, color: Color, room: float) -> void:
	if text.is_empty():
		return
	var size: int = maxi(roundi(px), MIN_TEXT_PX)
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	if width > room:
		size = maxi(maxi(int(floorf(float(size) * maxf(room / width, MIN_LABEL_SHARE))), MIN_TEXT_PX), 1)
		width = minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x, room)
	var baseline: Vector2 = middle + Vector2(-width * 0.5, float(size) * 0.35)
	canvas.draw_string(font, baseline + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, room, size, SHADOW_COLOR)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, room, size, color)


## The control the ring draws on, full window.
class RingCanvas extends Control:
	var view: RadialMenuView = null

	func _draw() -> void:
		if view != null:
			view.paint(self)
