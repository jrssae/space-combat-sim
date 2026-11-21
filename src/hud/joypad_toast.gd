class_name JoypadToast
extends CanvasLayer
## The short line that says a gamepad connected or disconnected (M8-T22, D88), at the top of the screen over the HUD, the
## pause menu and the front end, under the console. `Joypads` owns it; it never takes focus or the mouse.

const LAYER: int = 95
const SHOW_S: float = 4.0
const TOP_MARGIN: float = 24.0

var _left_s: float = 0.0
var _label: Label = null


func _ready() -> void:
	layer = LAYER
	name = "JoypadToast"
	process_mode = Node.PROCESS_MODE_ALWAYS  # a pad that drops while the game is paused is still announced
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme = load("res://src/frontend/theme.tres") as Theme
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y = TOP_MARGIN
	add_child(panel)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_left_s -= delta
	if _left_s <= 0.0:
		visible = false


## Shows `text` for a few seconds, replacing a line still up.
func show_text(text: String) -> void:
	if text.is_empty():
		return
	_label.text = text
	_left_s = SHOW_S
	visible = true


## The line showing, "" when none is.
func text() -> String:
	return _label.text if visible else ""
