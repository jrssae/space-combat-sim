class_name Upscaling
extends RefCounted
## The upscalers and internal-resolution presets `settings.upscaler` and `settings.upscale_preset` offer (M4-T40, architecture
## §7.7), and what they set on a viewport. Pure. `auto` picks by the window's height: FSR 2.2 at Quality for a 4K or larger
## window, native below. No frame generation: Godot's FSR 2.2 adds no frames.

const AUTO: StringName = &"auto"
const NATIVE: StringName = &"native"
const BILINEAR: StringName = &"bilinear"
const FSR1: StringName = &"fsr1"
const FSR2: StringName = &"fsr2"
const UPSCALERS: Array[StringName] = [AUTO, NATIVE, BILINEAR, FSR1, FSR2]

const QUALITY: StringName = &"quality"
const BALANCED: StringName = &"balanced"
const PERFORMANCE: StringName = &"performance"
const ULTRA_PERFORMANCE: StringName = &"ultra_performance"
const CUSTOM: StringName = &"custom"
const PRESETS: Array[StringName] = [AUTO, NATIVE, QUALITY, BALANCED, PERFORMANCE, ULTRA_PERFORMANCE, CUSTOM]

## AMD's FSR 2 ratios (1.5, 1.7, 2 and 3 times fewer lines), so a 2 160-line window renders whole lines: 1 440, 1 080, 720.
const SCALES: Dictionary = {NATIVE: 1.0, QUALITY: 1.0 / 1.5, BALANCED: 1.0 / 1.7, PERFORMANCE: 0.5, ULTRA_PERFORMANCE: 1.0 / 3.0}
## The smallest custom scale: a third of the window's height, as Ultra Performance.
const MIN_SCALE: float = 0.33
## A window this tall or taller gets FSR 2.2 at Quality under `auto`; a shorter one renders native.
const AUTO_MIN_LINES: int = 2160


## The share of the window's height the 3D renders at for `preset` (`custom` uses `custom_scale`).
static func preset_scale(preset: StringName, custom_scale: float = 1.0) -> float:
	if preset == CUSTOM:
		return clampf(custom_scale, MIN_SCALE, 1.0)
	return float(SCALES.get(preset, 1.0))


## The lines the 3D renders for a window `window_lines` tall.
static func internal_lines(window_lines: int, scale: float) -> int:
	return roundi(float(window_lines) * scale)


static func mode(upscaler: StringName) -> Viewport.Scaling3DMode:
	match upscaler:
		FSR1:
			return Viewport.SCALING_3D_MODE_FSR
		FSR2:
			return Viewport.SCALING_3D_MODE_FSR2
	return Viewport.SCALING_3D_MODE_BILINEAR


## Whether the upscaler reprojects past frames (its own anti-aliasing, and it needs motion vectors).
static func temporal(upscaler: StringName) -> bool:
	return upscaler == FSR2


## What the settings mean for a window `window_lines` tall: the upscaler and preset `auto` resolves to, the Godot mode and the scale.
static func plan(upscaler: StringName, preset: StringName, custom_scale: float, window_lines: int) -> Dictionary:
	var big: bool = window_lines >= AUTO_MIN_LINES
	var applied: StringName = upscaler if UPSCALERS.has(upscaler) else NATIVE
	if applied == AUTO:
		applied = FSR2 if big else NATIVE
	var chosen: StringName = preset if PRESETS.has(preset) else NATIVE
	if chosen == AUTO:
		chosen = QUALITY if big else NATIVE
	if applied == NATIVE:
		chosen = NATIVE
	return {"upscaler": applied, "preset": chosen, "mode": mode(applied), "scale": preset_scale(chosen, custom_scale)}


## Sets `viewport`'s 3D scaling to `p_plan` (from `plan`) with FSR's sharpness (Godot's scale: 0 is the sharpest, 2 the softest).
static func apply(viewport: Viewport, p_plan: Dictionary, sharpness: float) -> void:
	viewport.scaling_3d_mode = p_plan["mode"]
	viewport.scaling_3d_scale = p_plan["scale"]
	viewport.fsr_sharpness = sharpness
