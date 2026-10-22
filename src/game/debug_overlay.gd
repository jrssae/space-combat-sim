class_name DebugOverlay
extends CanvasLayer
## Full debug readout (F3, `settings.show_overlay`). Display only: Main hands it a snapshot each frame and
## tells it where the target bracket goes; the text rules live in OverlayText.

@onready var _label: Label = $Readout
@onready var _bracket: TargetBracket = $Bracket


func _ready() -> void:
	visible = bool(Settings.get_value(&"show_overlay"))
	_apply_text_size()
	Settings.changed.connect(_on_setting_changed)


func show_snapshot(snapshot: Dictionary) -> void:
	_label.text = OverlayText.format(snapshot)


func get_text() -> String:
	return _label.text


func show_bracket(screen_pos: Vector2) -> void:
	_bracket.show_at(screen_pos)


func hide_bracket() -> void:
	_bracket.hide_bracket()


func bracket() -> TargetBracket:
	return _bracket


# The label settings come from the scene file and are shared; this overlay is the only user.
func _apply_text_size() -> void:
	_label.label_settings.font_size = int(float(Settings.get_value(&"debug_text_size")))


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"show_overlay":
		visible = bool(value)
	elif key == &"debug_text_size":
		_apply_text_size()
