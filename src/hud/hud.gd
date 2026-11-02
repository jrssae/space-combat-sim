class_name Hud
extends CanvasLayer
## The combat HUD (architecture §15.9, D26): a green-line display drawn from the `HudFrame` that the pure `HudLayout` computes
## every frame. Layer 40, below the debug overlay (50). This node only runs it: `Main` sets `input_provider`, a Callable
## returning this frame's `HudInput`; `settings.show_hud` shows or hides it. `HudPainter` does the drawing, on this layer and, in the cockpit
## view, on the console's `screens` (M3-T29). Console provider `hud`.

## A Callable returning a `HudInput`; unset = nothing drawn.
var input_provider: Callable = Callable()
## The frame drawn last (for tests and the console).
var frame: HudFrame = HudFrame.new()
## The player ship's console screens (M3-T29), or null: they get the frame while the cockpit view shows them, and go dark with the HUD.
var screens: CockpitScreens = null:
	set(value):
		screens = value
		if screens != null:
			screens.set_powered(visible)

var _canvas: HudCanvas = null


func _ready() -> void:
	layer = 40
	_canvas = HudCanvas.new()
	_canvas.name = "HudCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.hud = self
	add_child(_canvas)
	visible = bool(Settings.get_value(&"show_hud"))
	Settings.changed.connect(_on_setting_changed)
	DebugConsole.registry.register_provider(&"hud", ConsoleVars.new({
		&"visible": {"get": func() -> bool: return visible, "doc": "The HUD is shown (settings.show_hud)"},
		&"lead_tof_s": {"get": func() -> Variant: return frame.lead_tof_s if frame.lead_visible else null, "unit": "s",
				"doc": "Time of flight to the lead point, while the lead reticle shows"},
		&"lead_on_screen": {"get": func() -> bool: return frame.lead_visible, "doc": "The lead reticle is on screen"},
		&"prograde_on_screen": {"get": func() -> bool: return frame.velocity_visible and not frame.retrograde,
				"doc": "The prograde marker is on screen"},
		&"target_box": {"get": func() -> Variant: return frame.target_box if frame.target_on_screen else null,
				"doc": "Screen rectangle of the target box, while the target is on screen"},
		&"window_items": {"get": func() -> String: return ",".join(frame.items), "doc": "What the 2D layer draws this frame"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _process(_delta: float) -> void:
	if not visible or not input_provider.is_valid():
		return
	var input: HudInput = input_provider.call() as HudInput
	if input == null or input.viewport_size.x < 1.0 or input.viewport_size.y < 1.0:
		return
	frame = HudLayout.compute(input)
	# The chase view is busier (the whole ship is on screen): the HUD is drawn fainter there.
	_canvas.modulate.a = 1.0 if frame.cockpit else float(Settings.get_value(&"hud_chase_opacity"))
	_canvas.queue_redraw()
	if screens != null and not frame.screens.is_empty():
		screens.show_frame(frame)


## Draws `f` now (tests set a frame directly).
func show_frame(f: HudFrame) -> void:
	frame = f
	if _canvas != null:
		_canvas.queue_redraw()


## What the 2D layer drew last (tests read it).
func painted_items() -> Array[StringName]:
	return _canvas.painter.painted


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"show_hud":
		visible = bool(value)
		if screens != null:
			screens.set_powered(visible)


## The control that holds the 2D layer's painter; it paints the HUD's last frame.
class HudCanvas extends Control:
	var hud: Hud = null
	var painter: HudPainter = null

	func _ready() -> void:
		painter = HudPainter.new(self)

	func _draw() -> void:
		if hud != null and painter != null:
			painter.paint(hud.frame, hud.frame)
