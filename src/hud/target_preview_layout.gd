class_name TargetPreviewLayout
extends RefCounted
## Where the target preview's panel sits (architecture §18.20, M5-T43), pure: vertically centred at the side of the screen
## opposite the radial menu, the hull's drawing at the top, the title and the rows under it. Sizes are for a window 1080 px
## high and scale with the ring (`RadialLayout`), so the two shrink together in a narrow window.

const PANEL_PX := Vector2(552.0, 624.0)
const PAD_PX: float = 24.0
## The drawing's height; its width is the panel's inside its padding.
const WIRE_HEIGHT_PX: float = 300.0
## Baselines from the panel's top.
const TITLE_Y_PX: float = 374.0
const SUBTITLE_Y_PX: float = 406.0
const FIRST_ROW_Y_PX: float = 456.0
const ROW_STEP_PX: float = 40.0
## A wrapped line of text (an objective) under the one before it.
const TEXT_STEP_PX: float = 28.0
const BAR_HEIGHT_PX: float = 20.0
## The hull bar starts this far from the panel's left and leaves this much at the right for the percentage.
const BAR_LEFT_PX: float = 110.0
const BAR_RIGHT_PX: float = 96.0
const CORNER_PX: float = 12.0


## The ring's scale: 1 at 1080 px high, less when a narrow window shrinks the ring.
static func scale_for(viewport: Vector2) -> float:
	return RadialLayout.outer_radius(viewport) / RadialLayout.OUTER_PX


## The panel: centred where the ring would be if it sat at the other side (`ring_right_side` is the ring's side).
static func panel_rect(viewport: Vector2, ring_right_side: bool = false) -> Rect2:
	var size: Vector2 = PANEL_PX * scale_for(viewport)
	var centre: Vector2 = RadialLayout.centre(viewport, not ring_right_side)
	var half: float = viewport.x * 0.5
	# Inside its own half of the window.
	var low: float = (half if not ring_right_side else 0.0) + size.x * 0.5
	var high: float = (viewport.x if not ring_right_side else half) - size.x * 0.5
	centre.x = clampf(centre.x, minf(low, high), maxf(low, high))
	return Rect2(centre - size * 0.5, size)


## The hull's drawing inside `panel`.
static func wire_rect(panel: Rect2) -> Rect2:
	var s: float = panel.size.x / PANEL_PX.x
	return Rect2(panel.position + Vector2(PAD_PX, PAD_PX) * s, Vector2(PANEL_PX.x - 2.0 * PAD_PX, WIRE_HEIGHT_PX) * s)


## The hull bar of a row whose baseline is `baseline_y` (panel space).
static func bar_rect(panel: Rect2, baseline_y: float) -> Rect2:
	var s: float = panel.size.x / PANEL_PX.x
	return Rect2(panel.position.x + (PAD_PX + BAR_LEFT_PX) * s, baseline_y - (BAR_HEIGHT_PX - 3.0) * s,
			(PANEL_PX.x - 2.0 * PAD_PX - BAR_LEFT_PX - BAR_RIGHT_PX) * s, BAR_HEIGHT_PX * s)
