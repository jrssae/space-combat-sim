class_name RenderScale
extends RefCounted
## The 3D scale that keeps a very large window's 3D under a pixel budget, pure: a frame of more than `MAX_TILES` tiles of 16 x 16 px
## (about 16 million pixels; 6144 x 3382 on a maximized 6K desktop is 81 000 tiles) is rendered at a lower internal resolution and
## scaled up, so the GPU never pays for 20 million pixels; the HUD and the text stay at the window's resolution. The budget was the
## M3 renderer's hard limit (its sort key held 65 535 tiles); it stays as the cap until T26's resolution scaling replaces it.

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
