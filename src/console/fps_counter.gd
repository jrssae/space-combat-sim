class_name FpsCounter
extends CanvasLayer
## Minimal top-right readout owned by DebugConsole (architecture §6.4): FPS and frame time when
## `settings.show_fps` is on, then one line per watched path. Separate from the debug overlay so it works in every
## scene and while the overlay is hidden. Hidden when there is nothing to show.

var show_fps: bool = false:
	set = set_show_fps
## Callable(path: String) -> String, the line drawn for a watched path (ConsoleRegistry.format_path).
var formatter: Callable = Callable()

var _watches: PackedStringArray = PackedStringArray()

@onready var _label: Label = %Readout


func _ready() -> void:
	_refresh_visibility()


func _process(_delta: float) -> void:
	if visible:
		_label.text = compose_text()


func set_show_fps(value: bool) -> void:
	show_fps = value
	_refresh_visibility()


func set_watches(paths: PackedStringArray) -> void:
	_watches = paths.duplicate()
	_refresh_visibility()


func watches() -> PackedStringArray:
	return _watches.duplicate()


## The text the label shows this frame.
func compose_text() -> String:
	var out := PackedStringArray()
	if show_fps:
		var fps: float = Engine.get_frames_per_second()
		out.append("FPS %d  %.1f ms" % [roundi(fps), 1000.0 / maxf(fps, 1.0)])
	for path: String in _watches:
		out.append(String(formatter.call(path)) if formatter.is_valid() else path)
	return "\n".join(out)


func _refresh_visibility() -> void:
	visible = show_fps or not _watches.is_empty()
	if visible and _label != null:
		_label.text = compose_text()
