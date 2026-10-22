class_name RenderScale
extends RefCounted
## The 3D scale that keeps the splat renderer inside its tile budget, pure. GDGS's compute backend sorts splats by a 32-bit key whose top 16
## bits are the 16 x 16 px tile index, so a frame of more than 65 535 tiles (about 16.7 million pixels: 6144 x 3382 on a maximized
## 6K desktop is 81 000 tiles) wraps the index and the bottom fifth of the picture renders black. Above the budget the 3D scene is
## rendered at a lower internal resolution and scaled up; the HUD and the text stay at the window's resolution.

const TILE_PX: int = 16
## A little under 65 535, so rounding up to whole tiles never crosses it.
const MAX_TILES: int = 62000


## Tiles in a frame of `width` x `height` pixels (rounded up to whole tiles on each axis).
static func tile_count(width: int, height: int) -> int:
	if width <= 0 or height <= 0:
		return 0
	return ((width + TILE_PX - 1) / TILE_PX) * ((height + TILE_PX - 1) / TILE_PX)


## The `Viewport.scaling_3d_scale` for a window of `width` x `height` pixels: 1 while it fits, otherwise the largest scale (in
## steps of 0.01 downward) at which the scaled frame is within `MAX_TILES`.
static func scale_for(width: int, height: int) -> float:
	if tile_count(width, height) <= MAX_TILES:
		return 1.0
	var scale: float = sqrt(float(MAX_TILES * TILE_PX * TILE_PX) / float(width * height))
	scale = floorf(scale * 100.0) / 100.0
	while scale > 0.1 and tile_count(int(ceilf(width * scale)), int(ceilf(height * scale))) > MAX_TILES:
		scale -= 0.01
	return maxf(scale, 0.1)
