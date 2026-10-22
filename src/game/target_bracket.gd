class_name TargetBracket
extends Control
## 24 px square drawn around the selected target's screen position (M1-T15).

const SIZE := 24.0
const COLOR := Color(0.55, 1.0, 0.6, 0.9)

var _screen_pos: Vector2 = Vector2.ZERO
var _shown: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_at(screen_pos: Vector2) -> void:
	_screen_pos = screen_pos
	_shown = true
	queue_redraw()


func hide_bracket() -> void:
	if _shown:
		_shown = false
		queue_redraw()


func is_shown() -> bool:
	return _shown


func get_bracket_position() -> Vector2:
	return _screen_pos


func _draw() -> void:
	if not _shown:
		return
	var half := SIZE * 0.5
	draw_rect(Rect2(_screen_pos - Vector2(half, half), Vector2(SIZE, SIZE)), COLOR, false, 1.5)
