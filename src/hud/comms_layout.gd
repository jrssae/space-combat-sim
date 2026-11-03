class_name CommsLayout
extends RefCounted
## Where the comms panel's subtitle plate goes and how big its text is (architecture §18 D53). Pure: the window's size in, pixels
## out. The plate sits at the bottom centre, between the chase view's corner gauges and radar, and the text never drops under a
## legible size, so a line reads at 960x540 as well as at 1080p. The panel measures the wrapped text and asks `plate` for the box.

## Sizes at 1080 px high (scaled with the window), and the floors the text keeps in a small one.
const TEXT_PX: float = 26.0
const CALLSIGN_PX: float = 20.0
const MIN_TEXT_PX: int = 17
const MIN_CALLSIGN_PX: int = 14
const PAD_PX: float = 14.0
const MIN_PAD_PX: float = 8.0
## The plate's lowest edge above the window's bottom, and the window margin it keeps at the sides.
const BOTTOM_PX: float = 40.0
const SIDE_MARGIN_PX: float = 48.0
## The plate is half the window wide, never narrower than this (so a small window still wraps at a sensible length).
const WIDTH_SHARE: float = 0.5
const MIN_WIDTH_PX: float = 640.0
## The callsign row's height as a multiple of its size.
const CALLSIGN_ROW: float = 1.4
## How wide one character of the HUD's monospace font is, as a multiple of its size.
const MONO_ADVANCE: float = 0.6

var scale: float = 1.0
var text_px: int = 0
var callsign_px: int = 0
var pad_px: float = 0.0
var width_px: float = 0.0
## The window's size, and the y of the plate's bottom edge.
var viewport: Vector2 = Vector2.ZERO
var bottom_y: float = 0.0


## The layout for a window `viewport` pixels across. `cockpit` is the camera: both views share one place for now.
static func compute(window: Vector2, _cockpit: bool = false) -> CommsLayout:
	var layout := CommsLayout.new()
	layout.viewport = window
	layout.scale = maxf(window.y / 1080.0, 0.25)
	layout.text_px = maxi(roundi(TEXT_PX * layout.scale), MIN_TEXT_PX)
	layout.callsign_px = maxi(roundi(CALLSIGN_PX * layout.scale), MIN_CALLSIGN_PX)
	layout.pad_px = maxf(PAD_PX * layout.scale, MIN_PAD_PX)
	var room: float = maxf(window.x - 2.0 * SIDE_MARGIN_PX * layout.scale, 1.0)
	layout.width_px = clampf(window.x * WIDTH_SHARE, minf(MIN_WIDTH_PX, room), room)
	layout.bottom_y = window.y - BOTTOM_PX * layout.scale
	return layout


## The width the wrapped text has inside the plate.
func text_width() -> float:
	return width_px - 2.0 * pad_px


## The plate for a text `text_height` pixels tall: bottom-anchored and centred, so a longer line grows it upwards (never past
## the window's top edge).
func plate(text_height: float) -> Rect2:
	var height: float = pad_px + float(callsign_px) * CALLSIGN_ROW + text_height + pad_px
	return Rect2(Vector2((viewport.x - width_px) * 0.5, maxf(bottom_y - height, 0.0)), Vector2(width_px, height))


## The colour of a speaker's callsign: how `viewer` (the player's faction) regards theirs, as the radar and target box do.
static func faction_color(faction: StringName, viewer: StringName = Factions.EARTH_ALLIANCE) -> Color:
	return Factions.hud_color(Factions.relation(viewer, faction))
