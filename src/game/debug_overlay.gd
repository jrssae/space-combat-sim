class_name DebugOverlay
extends CanvasLayer
## Full debug readout (F3, `settings.show_overlay`). Display only: Main hands it a snapshot each frame and
## tells it where the target bracket goes; the text rules live in OverlayText.

const TEXT_COLOR: Color = Color(0.75, 1.0, 0.8)

@onready var _readout: ReadoutText = $Readout
@onready var _bracket: TargetBracket = $Bracket


func _ready() -> void:
	visible = bool(Settings.get_value(&"show_overlay"))
	_readout.columns = true
	_readout.color = TEXT_COLOR
	_apply_text_size()
	Settings.changed.connect(_on_setting_changed)


func show_snapshot(snapshot: Dictionary) -> void:
	_readout.text = OverlayText.format(snapshot)


func get_text() -> String:
	return _readout.text


## Where the readout's text ends on screen, pixels: what the HUD keeps its top-left instruments clear of.
func text_bottom_px() -> float:
	return _readout.position.y + _readout.text_height()


func show_bracket(screen_pos: Vector2) -> void:
	_bracket.show_at(screen_pos)


func hide_bracket() -> void:
	_bracket.hide_bracket()


func bracket() -> TargetBracket:
	return _bracket


func _apply_text_size() -> void:
	_readout.font_size = int(float(Settings.get_value(&"debug_text_size")))


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"show_overlay":
		visible = bool(value)
	elif key == &"debug_text_size":
		_apply_text_size()
