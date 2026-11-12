class_name HudFrame
extends HudSurface
## One frame of the combat HUD as screen-space data (architecture §15.9): what `HudLayout.compute` returns and `Hud` draws.
## Positions are pixels with y down (as Godot's `Camera3D.unproject_position`); an element that is `visible` is on screen
## and in front of the camera. As a `HudSurface` it is also the layout of the 2D layer; `screens` holds the console's (M3-T29), which
## draw from this same data.

## The cockpit view is showing. In the chase view the ship fills the middle of the screen, so the gauges, the radar and the speed
## readout move out to the corners (`speed_align_right` is true there) and the whole HUD is drawn fainter (`Hud`).
var cockpit: bool = false
var viewport_size: Vector2 = Vector2(1920.0, 1080.0)
## The console's screens by id (`octagon`, `left`, `right`, each a `HudSurface`), when the cockpit view has them; empty otherwise.
var screens: Dictionary = {}
## The console's indicator lamps by id, on or off: real states, `HudLayout.LAMP_COLORS` gives their colours.
var lamps: Dictionary = {}

## Boresight (the nose axis at 1 km).
var boresight_visible: bool = false
var boresight_pos: Vector2 = Vector2.ZERO
## Velocity marker: prograde, or retrograde when prograde is behind the camera.
var velocity_visible: bool = false
var velocity_pos: Vector2 = Vector2.ZERO
var retrograde: bool = false
var speed_mps: float = 0.0
## Where the ship is going relative to where its nose points, degrees: horizontal (+ = to the right of the nose) and
## vertical (+ = above the nose). 0 / 0 is flying straight ahead, 180 horizontal is flying backward. `velocity_angles_valid`
## is false below `HudLayout.MIN_SPEED_FOR_MARKER_MPS`, where the direction means nothing.
var velocity_h_deg: float = 0.0
var velocity_v_deg: float = 0.0
var velocity_angles_valid: bool = false
## The drift sphere's arrow: the unit direction of travel in radar space (X right, Y forward, Z up; zero when the ship is not moving).
var drift_dir: Vector3 = Vector3.ZERO
## The reference point: distance to it, and the rate at which that distance closes (+ = approaching), m/s.
var reference_valid: bool = false
var reference_range_m: float = 0.0
var reference_closing_mps: float = 0.0
## Auto-track is holding the nose on the lead point.
var tracking: bool = false

## The selected target: present, the box around it (only when it is on screen), its colour by relation and the readout.
var target_present: bool = false
var target_on_screen: bool = false
var target_box: Rect2 = Rect2()
var target_color: Color = Factions.NEUTRAL_COLOR
var target_relation: Factions.Relation = Factions.Relation.NEUTRAL
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
## Damage silhouettes: the player's (over the hull gauge) and the selected target's (beside the radar). A layout of NONE means
## nothing to draw.
var own_layout: DamageZones.Layout = DamageZones.Layout.NONE
var own_zones: PackedFloat32Array = PackedFloat32Array()
var target_layout: DamageZones.Layout = DamageZones.Layout.NONE
var target_zones: PackedFloat32Array = PackedFloat32Array()
var charge_fraction: float = 1.0
var fire_mode: String = ""
## The running-lights indicator (M3-T27): its text; `running_lights_dark` when off.
var running_lights_text: String = ""
var running_lights_dark: bool = false

## The radar's contacts on the sphere (far to near, the selected one last), packed for the painter (M4-T36).
var radar_plot: RadarPlot = RadarPlot.new()
## What `RadarModel.plot` cost this frame, us (a readout).
var radar_plot_us: int = 0
## The same as `RadarModel.Dot`s, built when read (tests and readouts).
var radar_dots: Array[RadarModel.Dot]:
	get:
		return radar_plot.to_dots()

var status_line: String = ""
## The order acknowledgement under the status line ("" for none).
var ack_line: String = ""

## The route waypoint marker (M3-T09; T11 draws the final look): present, its label and range, on screen at `waypoint_pos`,
## else an edge arrow at `waypoint_edge_pos` pointing `waypoint_edge_angle` (radians, screen frame), as the target's.
var waypoint_present: bool = false
var waypoint_on_screen: bool = false
var waypoint_pos: Vector2 = Vector2.ZERO
var waypoint_label: String = ""
var waypoint_range_m: float = 0.0
var waypoint_edge_visible: bool = false
var waypoint_edge_pos: Vector2 = Vector2.ZERO
var waypoint_edge_angle: float = 0.0
## The waypoint's contact in `radar_plot` (M5-T25), or -1: the radar marks it with a diamond.
var waypoint_radar_index: int = -1

## The mission's objectives list (M5-T05), top right, right-aligned: the caption's baseline, then one line per active objective
## (`{text: String, pos: Vector2, primary: bool}`).
var objectives_caption_pos: Vector2 = Vector2.ZERO
var objective_lines: Array[Dictionary] = []
