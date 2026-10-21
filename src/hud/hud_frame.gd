class_name HudFrame
extends RefCounted
## One frame of the combat HUD as screen-space data (architecture §15.9): what `HudLayout.compute` returns and `Hud` draws.
## Positions are pixels with y down (as Godot's `Camera3D.unproject_position`); an element that is `visible` is on screen
## and in front of the camera.

## viewport height / 1080: sizes and line widths scale with it.
var scale: float = 1.0
var viewport_size: Vector2 = Vector2(1920.0, 1080.0)

## Boresight (the nose axis at 1 km).
var boresight_visible: bool = false
var boresight_pos: Vector2 = Vector2.ZERO
## Velocity marker: prograde, or retrograde when prograde is behind the camera.
var velocity_visible: bool = false
var velocity_pos: Vector2 = Vector2.ZERO
var retrograde: bool = false
var speed_mps: float = 0.0

## The selected target: present, the box around it (only when it is on screen), its colour by relation and the readout.
var target_present: bool = false
var target_on_screen: bool = false
var target_box: Rect2 = Rect2()
var target_color: Color = Factions.NEUTRAL_COLOR
var target_name: String = ""
var target_range_m: float = 0.0
var target_closing_mps: float = 0.0
## 0..1, or -1 without a hull (no bar).
var target_hull: float = -1.0
## Edge arrow: shown when the target is off screen or behind; `edge_arrow_angle` points the way (radians, screen frame).
var edge_arrow_visible: bool = false
var edge_arrow_pos: Vector2 = Vector2.ZERO
var edge_arrow_angle: float = 0.0
## Lead reticle (a diamond): hidden without an intercept solution or beyond the bolt's range.
var lead_visible: bool = false
var lead_pos: Vector2 = Vector2.ZERO
var lead_tof_s: float = 0.0

## Bottom-edge gauges.
var hull_fraction: float = 1.0
var hull_color: Color = Factions.HUD_LINE_COLOR
var god: bool = false
var fuel_fraction: float = 1.0
var fuel_unlimited: bool = true
var charge_fraction: float = 1.0
var fire_mode: String = ""
var speed_pos: Vector2 = Vector2.ZERO
var hull_rect: Rect2 = Rect2()
var fuel_rect: Rect2 = Rect2()
var charge_rect: Rect2 = Rect2()

## The targeting grid (cockpit view, or by setting): a square low and centred, a circular reticle, and the target's offset
## from the nose as a marker (clamped to the grid; `grid_marker_inside` is false when the target is beyond its edge).
var grid_visible: bool = false
var grid_rect: Rect2 = Rect2()
var grid_cells: int = 8
var grid_marker_visible: bool = false
var grid_marker: Vector2 = Vector2.ZERO
var grid_marker_inside: bool = false

## The radar sphere: its centre and radius in pixels, and the dots (far to near, the selected one last).
var radar_centre: Vector2 = Vector2.ZERO
var radar_radius_px: float = 0.0
var radar_dots: Array[RadarModel.Dot] = []

var status_line: String = ""
