class_name VortexLod
extends RefCounted
## How much detail a jump vortex draws for its size on screen (M6-T20, AC13), so a hundred points cost little at a distance and
## keep their look up close. Pure.
##
## The detail is a set of layer weights from the mouth's projected radius in pixels. The layers drop out finest first: the hair
## streaks (finest, fine, then broad), the patch layers with the rim's wisps, the fine cloud octave and last the coarse one,
## leaving a soft disc of the base colour with its rim and dark throat. Each layer fades over a band of radii (no pop); the
## shader blends a fading layer toward its mean, so the tone does not shift. Each band sits where the shader's own per-pixel
## filter has already mostly melted that layer, so the drop is hard to see. The centre flash is not a layer: it keeps its timing
## at every size. Below a few pixels the funnel also swaps to a coarse mesh (with a margin, so it does not flicker).

enum Layer { FINEST, FINE, BROAD, PATCHES, OCTAVE, CLOUD }
const LAYER_NAMES: Array[StringName] = [&"finest", &"fine", &"broad", &"patches", &"octave", &"cloud"]
const LAYER_COUNT: int = 6
## Each layer's band in projected mouth radius, px: gone at or below the first, whole at or above the second (1.5 times it).
## Hairs of 600, 300 and 120 strands melt into their mean below about 270, 135 and 55 px by the shader's own filter.
const BANDS_PX: Array[Vector2] = [Vector2(160.0, 240.0), Vector2(80.0, 120.0), Vector2(36.0, 54.0), Vector2(16.0, 24.0),
		Vector2(8.0, 12.0), Vector2(4.0, 6.0)]
## Levels, finest first: level k has the first k layers gone (0 everything, 6 the soft disc).
const LEVEL_COUNT: int = LAYER_COUNT + 1
## The coarse mesh below this radius, px, and the full one again above `FULL_MESH_PX`.
const COARSE_MESH_PX: float = 10.0
const FULL_MESH_PX: float = 14.0
## Larger than any screen: a camera inside the mouth.
const MAX_PX: float = 1.0e6
## The nearest this many open points carry a light; the rest glow without one (the rig has 7 slots for every light in play).
const LIT_POINTS: int = 3


## The mouth's radius on screen, px: `radius_m` seen from `distance_m` by a camera of `px_per_unit` (half the viewport's height in
## px times the projection's vertical scale, 1 / tan(half the field)).
static func projected_radius_px(radius_m: float, distance_m: float, px_per_unit: float) -> float:
	if distance_m <= radius_m:
		return MAX_PX
	return minf(radius_m * px_per_unit / distance_m, MAX_PX)


## `px_per_unit` of a camera with vertical field `fov_deg` drawing a viewport `height_px` high.
static func px_per_unit(fov_deg: float, height_px: float) -> float:
	return 0.5 * height_px / tan(deg_to_rad(clampf(fov_deg, 1.0, 179.0)) * 0.5)


## One layer's weight at `radius_px`: 0 gone, 1 whole, eased across its band.
static func weight(layer: Layer, radius_px: float) -> float:
	var band: Vector2 = BANDS_PX[layer]
	return smoothstep(band.x, band.y, radius_px)


## Every layer's weight at `radius_px`, finest first.
static func weights(radius_px: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LAYER_COUNT)
	for layer: int in LAYER_COUNT:
		out[layer] = weight(layer as Layer, radius_px)
	return out


## The weights a forced `level` gives (`vortex lod <level>`): its first `level` layers gone, the rest whole.
static func level_weights(level: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LAYER_COUNT)
	for layer: int in LAYER_COUNT:
		out[layer] = 0.0 if layer < level else 1.0
	return out


## The level at `radius_px`: how many layers are wholly gone (0 everything drawn, 6 the soft disc).
static func level(radius_px: float) -> int:
	var gone: int = 0
	for layer: int in LAYER_COUNT:
		if weight(layer as Layer, radius_px) <= 0.0:
			gone += 1
	return gone


## Whether `radius_px` lies inside some layer's band, between two levels.
static func blending(radius_px: float) -> bool:
	for layer: int in LAYER_COUNT:
		var w: float = weight(layer as Layer, radius_px)
		if w > 0.0 and w < 1.0:
			return true
	return false


## A projected radius in the middle of `level` (between the band that ends it and the next one), px; for captures.
static func radius_for_level(p_level: int) -> float:
	if p_level <= 0:
		return BANDS_PX[0].y * 1.5
	if p_level >= LAYER_COUNT:
		return BANDS_PX[LAYER_COUNT - 1].x * 0.5
	return sqrt(BANDS_PX[p_level - 1].x * BANDS_PX[p_level].y)


## Whether the funnel draws its coarse mesh at `radius_px`, given whether it did last frame.
static func coarse_mesh(radius_px: float, was_coarse: bool) -> bool:
	return radius_px < (FULL_MESH_PX if was_coarse else COARSE_MESH_PX)


## Which of the open points carry a light: the indices of the `count` nearest by `distances`, nearest first.
static func lit(distances: PackedFloat32Array, count: int = LIT_POINTS) -> PackedInt32Array:
	var out := PackedInt32Array()
	var kept := PackedFloat32Array()
	for i: int in distances.size():
		var d: float = distances[i]
		if out.size() == count and d >= kept[count - 1]:
			continue
		var at: int = out.size()
		while at > 0 and d < kept[at - 1]:
			at -= 1
		out.insert(at, i)
		kept.insert(at, d)
		if out.size() > count:
			out.resize(count)
			kept.resize(count)
	return out
