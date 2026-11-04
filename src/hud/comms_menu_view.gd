class_name CommsMenuView
extends CanvasLayer
## Draws the `CommsMenu` (architecture §18 D54, M5-T07): a plate at the left edge, vertically centred, with the page title and
## the four entries laid out as the D-pad (up, right, down, left), and a bar for the time left. The left-middle is free in both
## camera views: the wing roster and acknowledgements sit top-left and top-right, the gauges at the bottom, and subtitles bottom
## centre. It sits above the comms panel (41) and below the pause menu (60).
##
## Console: provider `comms_menu` (`open`, `page`, `remaining_s`, `picks`, `closed_by`).

const LAYER: int = 42
const PLATE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.62)
const TEXT_COLOR: Color = Color(0.94, 0.98, 0.96)
const TITLE_COLOR: Color = Color(0.45, 0.85, 1.0)
const KEY_COLOR: Color = Color(1.0, 0.8, 0.2)
const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)
## What each slot's D-pad direction is called, in slot order.
const DIRECTION_TAGS: Array[String] = ["UP", "RIGHT", "DOWN", "LEFT"]
## Sizes at 1080 px high (scaled with the window), and the floors a small window keeps.
const TEXT_PX: float = 24.0
const MIN_TEXT_PX: int = 16
const PAD_PX: float = 14.0
const SIDE_MARGIN_PX: float = 48.0
const TAG_COLUMN_EM: float = 3.6
const LABEL_COLUMN_EM: float = 11.5

var menu: CommsMenu = null

## What the last draw put on screen (tests read it).
var drawn_plate: Rect2 = Rect2()
var drawn_rows: Array[String] = []
var draws: int = 0

var _canvas: MenuCanvas = null
var _was_open: bool = false


func _ready() -> void:
	layer = LAYER
	name = "CommsMenuView"
	_canvas = MenuCanvas.new()
	_canvas.name = "MenuCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.view = self
	add_child(_canvas)
	DebugConsole.registry.register_provider(&"comms_menu", ConsoleVars.new({
		&"open": {"get": func() -> bool: return menu != null and menu.is_open(), "doc": "The comms menu is showing"},
		&"page": {"get": func() -> String: return menu.page_title() if menu != null else "", "doc": "The title of the page showing"},
		&"remaining_s": {"get": func() -> float: return menu.remaining_s() if menu != null else 0.0, "unit": "s",
				"doc": "Time left before the menu closes itself"},
		&"picks": {"get": func() -> int: return menu.picks if menu != null else 0, "doc": "Entries picked so far"},
		&"closed_by": {"get": func() -> String: return String(menu.closed_by) if menu != null else "",
				"doc": "Why it last closed: pick, close or timeout"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _process(_delta: float) -> void:
	# The bar moves while it is open; one last draw clears the plate when it closes.
	var open: bool = menu != null and menu.is_open()
	if open or _was_open:
		_canvas.queue_redraw()
	_was_open = open


## Draws the plate on `canvas`. Called from the canvas's `_draw`.
func paint(canvas: Control) -> void:
	if menu == null or not menu.is_open():
		drawn_rows = []
		return
	var scale: float = maxf(canvas.size.y / 1080.0, 0.25)
	var px: int = maxi(roundi(TEXT_PX * scale), MIN_TEXT_PX)
	var pad: float = maxf(PAD_PX * scale, 8.0)
	var font: Font = HudPainter.font()
	var row_h: float = float(px) * 1.5
	var entries: Array[Dictionary] = menu.entries()
	var size := Vector2(float(px) * (TAG_COLUMN_EM + LABEL_COLUMN_EM) + 2.0 * pad, row_h * float(entries.size() + 1) + 2.0 * pad)
	var plate := Rect2(Vector2(SIDE_MARGIN_PX * scale, (canvas.size.y - size.y) * 0.5), size)
	canvas.draw_rect(plate, PLATE_COLOR, true)
	var x: float = plate.position.x + pad
	var y: float = plate.position.y + pad + float(px)
	_text(canvas, font, menu.page_title(), Vector2(x, y), px, TITLE_COLOR)
	drawn_rows = []
	for i: int in entries.size():
		y += row_h
		_text(canvas, font, DIRECTION_TAGS[i], Vector2(x, y), px, KEY_COLOR)
		var label: String = String(entries[i]["label"])
		_text(canvas, font, label, Vector2(x + float(px) * TAG_COLUMN_EM, y), px, TEXT_COLOR)
		drawn_rows.append(label)
	var share: float = clampf(menu.remaining_s() / CommsMenu.CLOSE_S, 0.0, 1.0)
	canvas.draw_rect(Rect2(Vector2(plate.position.x, plate.end.y - 3.0 * scale - 1.0), Vector2(plate.size.x * share, 3.0 * scale + 1.0)),
			KEY_COLOR, true)
	drawn_plate = plate
	draws += 1


func _text(canvas: Control, font: Font, text: String, baseline: Vector2, size: int, color: Color) -> void:
	canvas.draw_string(font, baseline + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, SHADOW_COLOR)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


## The control the menu draws on, full window.
class MenuCanvas extends Control:
	var view: CommsMenuView = null

	func _draw() -> void:
		if view != null:
			view.paint(self)
