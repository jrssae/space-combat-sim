class_name ControlHint
extends CanvasLayer
## The control check's hint on the HUD (M8 D80): what the instructor asks for (`FIRE BOTH MAIN PODS`), the buttons that do it
## on the pad and the keyboard (`LT + RT / W`, the live bindings) and a bar for how far the check has come. `MissionRunner`
## sets `label`, `buttons` and `progress` each tick (an empty label hides it) and `suppressed` while a cinematic plays. It sits
## on the HUD's layer, centred under the status and acknowledgement lines.

const LAYER: int = 40
## At 1080 px, scaled with the window's height: the two lines' baselines and sizes, and the bar under them.
const LABEL_Y_PX: float = 150.0
const LABEL_PX: float = 24.0
const BUTTONS_Y_PX: float = 182.0
const BUTTONS_PX: float = 20.0
const BAR_Y_PX: float = 194.0
const BAR_SIZE_PX: Vector2 = Vector2(260.0, 6.0)

var label: String = ""
var buttons: String = ""
## How far the open check has come, 0..1.
var progress: float = 0.0
## A cinematic is playing: nothing shows.
var suppressed: bool = false
## What the last draw put on screen (tests read it), and how many draws.
var drawn_label: String = ""
var drawn_buttons: String = ""
var drawn_bar: Rect2 = Rect2()
var draws: int = 0

var _canvas: HintCanvas = null


## Where the hint goes in a window of `viewport`: `{scale, label_pos, buttons_pos, bar}` (the lines' centred baselines).
static func place(viewport: Vector2) -> Dictionary:
	var s: float = maxf(viewport.y / 1080.0, 0.25)
	var mid: float = viewport.x * 0.5
	return {"scale": s, "label_pos": Vector2(mid, LABEL_Y_PX * s), "buttons_pos": Vector2(mid, BUTTONS_Y_PX * s),
			"bar": Rect2(Vector2(mid - BAR_SIZE_PX.x * s * 0.5, BAR_Y_PX * s), BAR_SIZE_PX * s)}


func _ready() -> void:
	layer = LAYER
	name = "ControlHint"
	_canvas = HintCanvas.new()
	_canvas.name = "HintCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.hint = self
	add_child(_canvas)


func _process(_delta: float) -> void:
	visible = is_showing()
	if visible:
		_canvas.queue_redraw()


func is_showing() -> bool:
	return not label.is_empty() and not suppressed


## The control that paints the hint in the HUD's font and colour.
class HintCanvas extends Control:
	var hint: ControlHint = null

	func _draw() -> void:
		if hint == null or not hint.is_showing():
			return
		var at: Dictionary = ControlHint.place(get_viewport_rect().size)
		var s: float = at["scale"]
		_centred(hint.label, at["label_pos"], ControlHint.LABEL_PX * s)
		_centred(hint.buttons, at["buttons_pos"], ControlHint.BUTTONS_PX * s)
		var bar: Rect2 = at["bar"]
		var color: Color = HudPainter.LINE_COLOR
		draw_rect(bar, Color(color.r, color.g, color.b, 0.15), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hint.progress, 0.0, 1.0), bar.size.y)), color, true)
		hint.drawn_label = hint.label
		hint.drawn_buttons = hint.buttons
		hint.drawn_bar = bar
		hint.draws += 1

	func _centred(text: String, at: Vector2, size: float) -> void:
		if text.is_empty():
			return
		var font: Font = HudPainter.font()
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(size)).x
		var origin: Vector2 = at - Vector2(width * 0.5, 0.0)
		draw_string(font, origin + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(size), HudPainter.TEXT_SHADOW)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(size), HudPainter.LINE_COLOR)
