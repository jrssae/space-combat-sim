class_name FocusPullView
extends CanvasLayer
## Draws the focus pull (architecture §18.21, M5-T44): one full-screen rect between the HUD and the radial menu that blurs
## and dims everything under it. It eases on real frame time, since the game is paused behind an open menu. At rest the
## layer is hidden and does not process, so a closed menu costs nothing.

## Between the HUD (40) and its comms menu (42), and the radial menu (45): under the menu and the target preview only.
const LAYER: int = 44
## Mip levels of blur at setting 1.0 and the share of black at setting 1.0.
const MAX_LOD: float = 3.0
const MAX_DIM: float = 0.35

var pull: FocusPull = FocusPull.new()

var _rect: ColorRect = null
var _material: ShaderMaterial = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/shaders/focus_pull.gdshader") as Shader
	_rect = ColorRect.new()
	_rect.name = "Blur"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)
	_rest()


## A radial menu opened or closed. With the setting at 0 the pull never shows.
func set_open(open: bool) -> void:
	if strength() <= 0.0:
		return
	pull.set_open(open)
	if open and not visible:
		visible = true
		set_process(true)
		_apply()


## The setting, 0..1.
func strength() -> float:
	return clampf(float(Settings.get_value(&"target_menu_blur")), 0.0, 1.0)


## The eased amount now, 0..1.
func amount() -> float:
	return pull.amount()


func _process(delta: float) -> void:
	pull.advance(delta / maxf(Engine.time_scale, 0.001))
	if pull.at_rest():
		_rest()
		return
	_apply()


func _apply() -> void:
	var s: float = strength() * pull.amount()
	_material.set_shader_parameter(&"lod_level", MAX_LOD * s)
	_material.set_shader_parameter(&"dim", MAX_DIM * s)


func _rest() -> void:
	visible = false
	set_process(false)
