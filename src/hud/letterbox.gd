class_name Letterbox
extends CanvasLayer
## The black bars of a cinematic (architecture §18 D55, M5-T08): they slide in from the top and bottom of the window while a shot
## plays and back out after it. `Main` sets `shown` when the camera enters or leaves its cinematic mode. The layer sits under the
## comms panel (41), so a line said during a shot shows over the bottom bar, as film subtitles do.

const LAYER: int = 39
## Each bar's height at full slide, as a share of the window's height (about a 2.35:1 picture on a 16:9 window).
const BAR_FRACTION: float = 0.12
## Seconds to slide fully in or out.
const SLIDE_S: float = 0.6
const BAR_COLOR: Color = Color.BLACK

## The bars are wanted on screen; they slide toward it.
var shown: bool = false
## How far in the bars are, 0 (gone) to 1 (fully in).
var amount: float = 0.0

var _top: ColorRect = null
var _bottom: ColorRect = null


func _ready() -> void:
	layer = LAYER
	name = "Letterbox"
	_top = _bar("Top", Control.PRESET_TOP_WIDE)
	_bottom = _bar("Bottom", Control.PRESET_BOTTOM_WIDE)
	_apply()


func _process(delta: float) -> void:
	amount = move_toward(amount, 1.0 if shown else 0.0, maxf(delta, 0.0) / SLIDE_S)
	_apply()


## Each bar's height in pixels this frame.
func bar_height_px() -> float:
	return get_viewport().get_visible_rect().size.y * BAR_FRACTION * smoothstep(0.0, 1.0, amount)


func _bar(bar_name: String, preset: Control.LayoutPreset) -> ColorRect:
	var bar := ColorRect.new()
	bar.name = bar_name
	bar.color = BAR_COLOR
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(preset)
	add_child(bar)
	return bar


func _apply() -> void:
	var h: float = bar_height_px()
	visible = h > 0.0
	_top.offset_top = 0.0
	_top.offset_bottom = h
	_bottom.offset_top = -h
	_bottom.offset_bottom = 0.0
