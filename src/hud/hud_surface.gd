class_name HudSurface
extends RefCounted
## One place the HUD draws on, and where each instrument goes on it (M3-T29): the 2D layer over the window, or a screen in the console.
## `HudLayout` fills it, `HudPainter` draws it. It holds layout only: the numbers come from the `HudFrame` it is drawn with.

## The instruments, by the name `items` lists them.
const BORESIGHT: StringName = &"boresight"
const VELOCITY: StringName = &"velocity"
## The target's brackets, or its edge arrow, and the lead diamond: what must line up with the world.
const TARGET_MARKS: StringName = &"target_marks"
## The target's name, range and hull bar under its brackets.
const TARGET_LABEL: StringName = &"target_label"
## The same readout as a panel on a screen.
const TARGET_PANEL: StringName = &"target_panel"
const WAYPOINT: StringName = &"waypoint"
const GRID: StringName = &"grid"
const SPEED: StringName = &"speed"
const HULL_BAR: StringName = &"hull_bar"
const FUEL_BAR: StringName = &"fuel_bar"
const CHARGE_BAR: StringName = &"charge_bar"
const RUNNING_LIGHTS: StringName = &"running_lights"
const RADAR: StringName = &"radar"
const DRIFT: StringName = &"drift"
const OWN_SILHOUETTE: StringName = &"own_silhouette"
const TARGET_SILHOUETTE: StringName = &"target_silhouette"
const TRACKING: StringName = &"tracking"
const STATUS: StringName = &"status"
const ACK: StringName = &"ack"
const ROSTER: StringName = &"roster"
## The whole HUD in one place, as the chase view draws it, in drawing order.
const ALL_ITEMS: Array[StringName] = [BORESIGHT, VELOCITY, TARGET_MARKS, TARGET_LABEL, WAYPOINT, GRID, SPEED, HULL_BAR, FUEL_BAR, CHARGE_BAR,
		RUNNING_LIGHTS, RADAR, DRIFT, OWN_SILHOUETTE, TARGET_SILHOUETTE, TRACKING, STATUS, ACK, ROSTER]

## What this surface shows, in drawing order.
var items: Array[StringName] = []
## Its size in pixels, and the factor every drawn size scales by: viewport height / 1080 on the 2D layer, its own on a screen.
var size: Vector2 = Vector2(1920.0, 1080.0)
var scale: float = 1.0

var speed_pos: Vector2 = Vector2.ZERO
var speed_align_right: bool = false
## The speed's size in pixels at this surface's scale.
var speed_size: float = 22.0
## The drift sphere: a ship-frame sphere with an arrow along the direction of travel.
var drift_centre: Vector2 = Vector2.ZERO
var drift_radius_px: float = 0.0
var own_silhouette_rect: Rect2 = Rect2()
var target_silhouette_rect: Rect2 = Rect2()
var hull_rect: Rect2 = Rect2()
var fuel_rect: Rect2 = Rect2()
var charge_rect: Rect2 = Rect2()
## The bars' captions, and whether the hull bar also shows its number: larger where the bar is the only one in view.
var bar_caption_size: float = 14.0
var bar_percent: bool = false
## The charge bar stands up and fills from the bottom, with `CHARGE` and the fire mode right-aligned above it, the label's baseline here.
var charge_vertical: bool = false
var charge_caption_pos: Vector2 = Vector2.ZERO
## The left end of the running-lights text.
var running_lights_pos: Vector2 = Vector2.ZERO

## The targeting grid: a reticle in the middle of square cells, and the target's offset from the nose as a marker (clamped to the grid;
## `grid_marker_inside` is false when the target is beyond its edge).
var grid_visible: bool = false
var grid_rect: Rect2 = Rect2()
var grid_cells: int = 8
var grid_marker_visible: bool = false
var grid_marker: Vector2 = Vector2.ZERO
var grid_marker_inside: bool = false
## The marker is a ring on a diagonal stroke rather than a filled square.
var grid_marker_diagonal: bool = false
var grid_color: Color = HudLayout.LINE_COLOR
var grid_line_alpha: float = 0.22

## The radar sphere: its centre and radius in pixels. With `radar_icons` its contacts are icons coloured and shaped by relation
## (`HudLayout.octagon_icon_color`), because a red grid would swallow the faction colours, and its range rings are named.
var radar_centre: Vector2 = Vector2.ZERO
var radar_radius_px: float = 0.0
var radar_icons: bool = false

## The target panel's first line (left end of its baseline) and its hull bar, and the line that closes the panel off (0 for none).
var target_panel_pos: Vector2 = Vector2.ZERO
var target_bar_rect: Rect2 = Rect2()
var divider_y: float = 0.0

## Where the text lines go; `lines_centred` when they are centred on these points rather than starting at them. With a `lines_width` a
## line too long for it wraps.
var tracking_pos: Vector2 = Vector2.ZERO
var status_pos: Vector2 = Vector2.ZERO
var ack_pos: Vector2 = Vector2.ZERO
var lines_centred: bool = true
var lines_width: float = 0.0
## The wing roster: one row per slot, its text size, and where its `WING` caption goes (zero for none).
var roster_rows: Array[HudLayout.RosterRow] = []
var roster_text_size: float = 15.0
var roster_caption_pos: Vector2 = Vector2.ZERO
