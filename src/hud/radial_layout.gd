class_name RadialLayout
extends RefCounted
## Where a radial menu sits on screen (architecture §18.19, M5-T25), pure: the ring vertically centred at one side, its slices
## as polygons and the points their labels hang on. Sizes are for a window 1080 px high and scale with it. `RadialMenuView`
## draws from this; T43's target panel takes the opposite side.

const OUTER_PX: float = 276.0
const INNER_PX: float = 108.0
## The ring's centre from the near side edge.
const CENTRE_X_PX: float = 432.0
## Where the labels' middle line sits, between the hub and the rim.
const LABEL_RADIUS_PX: float = 196.0
const SIDE_MARGIN_PX: float = 24.0
## The heading's baseline from the top, and the hint's below the ring.
const HEADING_Y_PX: float = 72.0
const HINT_BELOW_PX: float = 60.0
## The detail line (the highlighted entry's long text) under the hint.
const DETAIL_BELOW_PX: float = 96.0
# Arc steps per slice outline: smooth at 4K, a few dozen points per ring.
const _ARC_STEPS: int = 12


static func scale_for(viewport: Vector2) -> float:
	return maxf(viewport.y / 1080.0, 0.25)


static func outer_radius(viewport: Vector2) -> float:
	# A narrow window shrinks the ring rather than letting it run off the side.
	return minf(OUTER_PX * scale_for(viewport), maxf((viewport.x * 0.5 - SIDE_MARGIN_PX) * 0.5, 8.0))


static func inner_radius(viewport: Vector2) -> float:
	return outer_radius(viewport) * INNER_PX / OUTER_PX


static func label_radius(viewport: Vector2) -> float:
	return outer_radius(viewport) * LABEL_RADIUS_PX / OUTER_PX


## The ring's centre: vertically centred, at the left side or (`right_side`) the right.
static func centre(viewport: Vector2, right_side: bool = false) -> Vector2:
	var r: float = outer_radius(viewport)
	# Inside its own half of the window, whatever the window's shape.
	var x: float = clampf(CENTRE_X_PX * scale_for(viewport), r + SIDE_MARGIN_PX, maxf(viewport.x * 0.5 - r, r + SIDE_MARGIN_PX))
	return Vector2(viewport.x - x if right_side else x, viewport.y * 0.5)


## The screen direction (y down) of an angle measured clockwise from straight up.
static func direction(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))


## The outline of slice `index` of `count` between the hub and the rim, closed, clockwise from its hub corner.
static func slice_polygon(at: Vector2, inner: float, outer: float, index: int, count: int) -> PackedVector2Array:
	var half: float = PI / float(maxi(count, 1))
	var mid: float = RadialMenu.slice_angle(index, count)
	var points := PackedVector2Array()
	for k: int in _ARC_STEPS + 1:
		points.append(at + direction(mid - half + 2.0 * half * float(k) / float(_ARC_STEPS)) * inner)
	for k: int in _ARC_STEPS + 1:
		points.append(at + direction(mid + half - 2.0 * half * float(k) / float(_ARC_STEPS)) * outer)
	return points


## The spoke between slice `index` and the one before it: from the hub to the rim.
static func spoke(at: Vector2, inner: float, outer: float, index: int, count: int) -> PackedVector2Array:
	var dir: Vector2 = direction(RadialMenu.slice_angle(index, count) - PI / float(maxi(count, 1)))
	return PackedVector2Array([at + dir * inner, at + dir * outer])


## The middle of slice `index`'s label block.
static func label_pos(at: Vector2, radius: float, index: int, count: int) -> Vector2:
	return at + direction(RadialMenu.slice_angle(index, count)) * radius


## The tip of the stick's pointer in the hub for a direction `v` (x right, y up, 0..1).
static func pointer_tip(at: Vector2, inner: float, v: Vector2) -> Vector2:
	return at + Vector2(v.x, -v.y).limit_length(1.0) * inner * 0.88
