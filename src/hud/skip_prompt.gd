class_name SkipPrompt
extends CanvasLayer
## The opening's skip prompt (M7-T54): `HOLD X / SHIFT / MOUSE 4: SKIP` and the hold's bar, on its own layer above the letterbox
## (39) and the HUD (40), so it shows over a cinematic as well as during the briefing. `MissionRunner` sets `text` (empty hides
## it) and `progress` each tick; `HudLayout.prompt_frame` places it as the HUD places an interaction's prompt.

const LAYER: int = 42
## What the prompt asks for, after the buttons to hold.
const LABEL: String = "SKIP"

## The prompt, "" for none.
var text: String = ""
## How far the hold has run, 0..1.
var progress: float = 0.0
## The frame drawn last (tests read it).
var frame: HudFrame = HudFrame.new()

var _canvas: PromptCanvas = null


## The prompt for the buttons `buttons` (`BindingNames.of_action(InputAdapter.AUTOTRACK)`).
static func prompt_text(buttons: String) -> String:
	return "HOLD %s: %s" % [buttons, LABEL]


func _ready() -> void:
	layer = LAYER
	name = "SkipPrompt"
	_canvas = PromptCanvas.new()
	_canvas.name = "PromptCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.prompt = self
	add_child(_canvas)


func _process(_delta: float) -> void:
	visible = not text.is_empty()
	if not visible:
		return
	frame = HudLayout.prompt_frame(get_viewport().get_visible_rect().size, text, progress)
	_canvas.queue_redraw()


## The control that paints the prompt with the HUD's painter.
class PromptCanvas extends Control:
	var prompt: SkipPrompt = null
	var painter: HudPainter = null

	func _ready() -> void:
		painter = HudPainter.new(self)

	func _draw() -> void:
		if prompt != null and painter != null and not prompt.text.is_empty():
			painter.paint(prompt.frame, prompt.frame)
