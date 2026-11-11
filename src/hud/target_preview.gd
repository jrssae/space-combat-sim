class_name TargetPreview
extends CanvasLayer
## The target menu's preview panel (architecture §18.20, M5-T43): at the side of the screen opposite the ring, the highlighted
## entry's hull as a turning green wireframe (`WirePreview`), its name in the IFF colour, class and faction, and the rows of its
## `TargetPreviewModel`. It shows only while the menu's second ring is open; hidden, neither it nor its viewport does any work.
## It runs while the game is paused. On the ring's layer, above T44's blur.
##
## Console: provider `target_preview`.

const LAYER: int = RadialMenuView.LAYER
const GROUND_COLOR: Color = Color(0.012, 0.075, 0.043, 0.72)
const RIM_ALPHA: float = 0.45
const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)
## Text sizes at 1080 px high.
const TITLE_PX: float = 29.0
const SUBTITLE_PX: float = 19.0
const ROW_PX: float = 23.0
const FLAG_PX: float = 19.0
const PLACEHOLDER_PX: float = 34.0
const MIN_TEXT_PX: int = 9
## An objective's text takes at most this many lines.
const TEXT_LINES: int = 3

var model: TargetPreviewModel = TargetPreviewModel.none()
var wire: WirePreview = null
## The side the ring is at; the panel takes the other.
var ring_right_side: bool = false
## What the last draw put on screen (tests read it).
var drawn_panel := Rect2()
var drawn_lines: Array[String] = []
var draws: int = 0
## Times an entry's data was read into the panel.
var shows: int = 0
## What the last frame's panel work took on the CPU (fitting the viewport and drawing the panel), microseconds: a measurement.
var last_frame_usec: int = 0

var _canvas: PanelCanvas = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	wire = WirePreview.new()
	wire.name = "Wire"
	add_child(wire)
	_canvas = PanelCanvas.new()
	_canvas.name = "PanelCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.view = self
	add_child(_canvas)
	_register_console()
	hide_panel()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Shows `entry`; `parts` are its hull's meshes (`WirePreview.show_hull`), `key` names the hull. With no parts the panel
## shows the model's placeholder in the hull's place.
func show_model(entry: TargetPreviewModel, key: String = "", parts: Array[Dictionary] = []) -> void:
	model = entry if entry != null else TargetPreviewModel.none()
	shows += 1
	if parts.is_empty() or model.hull_id.is_empty():
		wire.clear()
		wire.set_live(false)
	else:
		_fit_wire()
		wire.show_hull(key, parts)
		wire.set_live(true)
	visible = true
	set_process(true)
	_canvas.queue_redraw()


## Hides the panel and stops its viewport.
func hide_panel() -> void:
	visible = false
	set_process(false)
	if wire != null:
		wire.clear()
		wire.set_live(false)
	model = TargetPreviewModel.none()


func is_showing() -> bool:
	return visible


func _process(_delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	_fit_wire()  # the window may resize under an open menu
	_canvas.queue_redraw()
	last_frame_usec = Time.get_ticks_usec() - started


# The viewport renders at the size it is drawn at.
func _fit_wire() -> void:
	var view: Vector2 = _canvas.size if _canvas.size.x > 0.0 else Vector2(get_viewport().get_visible_rect().size)
	var rect: Rect2 = TargetPreviewLayout.wire_rect(TargetPreviewLayout.panel_rect(view, ring_right_side))
	var wanted := Vector2i(maxi(roundi(rect.size.x), 2), maxi(roundi(rect.size.y), 2))
	if wire.size != wanted:
		wire.size = wanted


## Draws the panel on `canvas`. Called from the canvas's `_draw`.
func paint(canvas: Control) -> void:
	drawn_lines = []
	if not visible:
		return
	var started: int = Time.get_ticks_usec()
	var panel: Rect2 = TargetPreviewLayout.panel_rect(canvas.size, ring_right_side)
	var s: float = panel.size.x / TargetPreviewLayout.PANEL_PX.x
	var font: Font = HudPainter.font()
	var line: Color = Factions.HUD_LINE_COLOR
	var box := StyleBoxFlat.new()
	box.bg_color = GROUND_COLOR
	box.border_color = Color(line.r, line.g, line.b, RIM_ALPHA)
	box.set_border_width_all(maxi(roundi(2.0 * s), 1))
	box.set_corner_radius_all(roundi(TargetPreviewLayout.CORNER_PX * s))
	canvas.draw_style_box(box, panel)
	var wire_rect: Rect2 = TargetPreviewLayout.wire_rect(panel)
	var left: float = panel.position.x + TargetPreviewLayout.PAD_PX * s
	var right: float = panel.end.x - TargetPreviewLayout.PAD_PX * s
	var room: float = right - left
	if wire.has_hull():
		canvas.draw_texture_rect(wire.get_texture(), wire_rect, false)
	elif not model.placeholder.is_empty():
		var px: int = _fit(font, model.placeholder, PLACEHOLDER_PX * s, room)
		var width: float = font.get_string_size(model.placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
		_line(canvas, font, model.placeholder, wire_rect.get_center() + Vector2(-width * 0.5, float(px) * 0.35), px, model.title_color)
	elif model.kind == TargetPreviewModel.Kind.OBJECTIVE or model.kind == TargetPreviewModel.Kind.BEACON:
		# A place with no hull: the waypoint's diamond.
		var r: float = wire_rect.size.y * 0.22
		var c: Vector2 = wire_rect.get_center()
		canvas.draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
				c + Vector2(0, -r)]), model.title_color, maxf(2.0 * s, 1.0), true)
	if not model.flag.is_empty():
		_line(canvas, font, model.flag, wire_rect.position + Vector2(4.0 * s, FLAG_PX * s), _fit(font, model.flag, FLAG_PX * s, room),
				Factions.HOSTILE_COLOR)
	var top: float = panel.position.y
	_line(canvas, font, model.title, Vector2(left, top + TargetPreviewLayout.TITLE_Y_PX * s), _fit(font, model.title, TITLE_PX * s, room),
			model.title_color)
	_line(canvas, font, model.subtitle, Vector2(left, top + TargetPreviewLayout.SUBTITLE_Y_PX * s),
			_fit(font, model.subtitle, SUBTITLE_PX * s, room), Color(line.r, line.g, line.b, 0.85))
	var y: float = top + TargetPreviewLayout.FIRST_ROW_Y_PX * s
	var row_px: int = maxi(roundi(ROW_PX * s), MIN_TEXT_PX)
	for row: Dictionary in model.rows:
		var label: String = str(row.get("label", ""))
		var value: String = str(row.get("value", ""))
		if label.is_empty():
			y = _wrapped(canvas, font, value, Vector2(left, y), room, maxi(roundi(SUBTITLE_PX * s), MIN_TEXT_PX), line, s)
			continue
		_line(canvas, font, label, Vector2(left, y), row_px, line)
		if row.has("bar"):
			var bar: Rect2 = TargetPreviewLayout.bar_rect(panel, y)
			var color: Color = row.get("color", line)
			canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(row["bar"]), 0.0, 1.0), bar.size.y)), color, true)
			canvas.draw_rect(bar, line, false, maxf(1.5 * s, 1.0))
		var width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, row_px).x
		_line(canvas, font, value, Vector2(right - width, y), row_px, line)
		drawn_lines.append("%s %s" % [label, value])
		y += TargetPreviewLayout.ROW_STEP_PX * s
	drawn_panel = panel
	draws += 1
	last_frame_usec += Time.get_ticks_usec() - started


# One line with its shadow, baseline at `at`.
func _line(canvas: Control, font: Font, text: String, at: Vector2, px: int, color: Color) -> void:
	if text.is_empty():
		return
	canvas.draw_string(font, at + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, SHADOW_COLOR)
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, color)
	drawn_lines.append(text)


# A long text over at most `TEXT_LINES` lines; returns the next row's baseline.
func _wrapped(canvas: Control, font: Font, text: String, at: Vector2, room: float, px: int, color: Color, s: float) -> float:
	canvas.draw_multiline_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, room, px, TEXT_LINES, color)
	drawn_lines.append(text)
	var height: float = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, room, px, TEXT_LINES).y
	return at.y + maxf(height, TargetPreviewLayout.TEXT_STEP_PX * s) + 0.5 * TargetPreviewLayout.ROW_STEP_PX * s


# The size at which `text` fits `room`, from `px` down.
func _fit(font: Font, text: String, px: float, room: float) -> int:
	var size: int = maxi(roundi(px), MIN_TEXT_PX)
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	if width > room and width > 0.0:
		size = maxi(int(floorf(float(size) * room / width)), MIN_TEXT_PX)
	return size


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"target_preview", ConsoleVars.new({
		&"visible": {"get": func() -> bool: return visible, "doc": "The preview panel is showing (the target menu's second ring is open)"},
		&"entity": {"get": func() -> String: return model.title if visible and not model.title.is_empty() else "none",
				"doc": "The entry the panel describes"},
		&"kind": {"get": func() -> String: return String(TargetPreviewModel.Kind.keys()[model.kind]).to_lower(),
				"doc": "What it is: none, ship, beacon, objective or unknown"},
		&"hull": {"get": func() -> String: return wire.hull_key if not wire.hull_key.is_empty() else "none",
				"doc": "The hull drawn as a wireframe (its asset, with its mounted pods), or none"},
		&"edges": {"get": func() -> int: return wire.edge_count, "doc": "Lines in the wireframe (0 while they are being found)"},
		&"building": {"get": func() -> bool: return wire.building, "doc": "The hull's edges are still being found, a slice a frame"},
		&"rendering": {"get": func() -> bool: return wire.live, "doc": "The wireframe's viewport renders (never while the panel is hidden)"},
		&"lines": {"get": func() -> String: return _console_lines(), "doc": "The panel's rows"},
		&"flag": {"get": func() -> String: return model.flag if not model.flag.is_empty() else "none", "doc": "ATTACKING YOU, or none"},
		&"cache": {"get": func() -> int: return WirePreview.cache_size(), "doc": "Meshes whose edges are kept for the session"},
		&"last_build_ms": {"get": func() -> float: return wire.last_build_ms, "unit": "ms",
				"doc": "What finding the last new hull's edges took in all"},
		&"last_build_slice_ms": {"get": func() -> float: return wire.last_build_max_slice_ms, "unit": "ms",
				"doc": "The longest single frame's share of it"},
		&"last_build_frames": {"get": func() -> int: return wire.last_build_frames, "doc": "Frames it was spread over"},
		&"shows": {"get": func() -> int: return shows, "doc": "Times an entry's data was read into the panel"},
		&"frame_ms": {"get": func() -> float: return float(last_frame_usec) / 1000.0 if visible else 0.0, "unit": "ms",
				"doc": "The panel's CPU work in the last frame (0 while it is hidden: nothing of it runs)"},
	}), self)


func _console_lines() -> String:
	var out := PackedStringArray()
	if not model.subtitle.is_empty():
		out.append(model.subtitle)
	for row: Dictionary in model.rows:
		out.append(("%s %s" % [row.get("label", ""), row.get("value", "")]).strip_edges())
	return "; ".join(out) if not out.is_empty() else "none"


## The control the panel draws on, full window.
class PanelCanvas extends Control:
	var view: TargetPreview = null

	func _draw() -> void:
		if view != null:
			view.paint(self)
