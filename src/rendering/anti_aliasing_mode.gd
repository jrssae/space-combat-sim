class_name AntiAliasingMode
extends RefCounted
## The anti-aliasing modes `settings.anti_aliasing` offers (M4-T38, architecture §7.6) and the viewport switches each one sets.
## Pure: one mode is one of Godot's three switches, so modes never stack (MSAA with TAA costs both and gains little).

const OFF: StringName = &"off"
const FXAA: StringName = &"fxaa"
const SMAA: StringName = &"smaa"
const MSAA_2X: StringName = &"msaa_2x"
const MSAA_4X: StringName = &"msaa_4x"
const TAA: StringName = &"taa"
## What `read` answers for a viewport no mode would set up.
const CUSTOM: StringName = &"custom"
const MODES: Array[StringName] = [OFF, FXAA, SMAA, MSAA_2X, MSAA_4X, TAA]


static func msaa(mode: StringName) -> Viewport.MSAA:
	match mode:
		MSAA_2X:
			return Viewport.MSAA_2X
		MSAA_4X:
			return Viewport.MSAA_4X
	return Viewport.MSAA_DISABLED


static func screen_space(mode: StringName) -> Viewport.ScreenSpaceAA:
	match mode:
		FXAA:
			return Viewport.SCREEN_SPACE_AA_FXAA
		SMAA:
			return Viewport.SCREEN_SPACE_AA_SMAA
	return Viewport.SCREEN_SPACE_AA_DISABLED


static func taa(mode: StringName) -> bool:
	return mode == TAA


## Whether the mode reprojects last frame's picture, so everything that moves must carry its motion vector.
static func wants_motion_vectors(mode: StringName) -> bool:
	return taa(mode)


## Sets `viewport` up for `mode` (an unknown mode is off).
static func apply(viewport: Viewport, mode: StringName) -> void:
	viewport.msaa_3d = msaa(mode)
	viewport.screen_space_aa = screen_space(mode)
	viewport.use_taa = taa(mode)


## The mode `viewport` is set up for, or `CUSTOM`.
static func read(viewport: Viewport) -> StringName:
	for mode: StringName in MODES:
		if viewport.msaa_3d == msaa(mode) and viewport.screen_space_aa == screen_space(mode) and viewport.use_taa == taa(mode):
			return mode
	return CUSTOM
