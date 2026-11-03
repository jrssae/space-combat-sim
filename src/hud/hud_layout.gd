class_name HudLayout
extends RefCounted
## The combat HUD's layout (architecture §15.9, D26), pure: `compute(input) -> HudFrame`. It projects with the camera's own
## matrices (clip = projection x view x point; behind the camera when clip.w <= 0; NDC to pixels with y down) so it agrees with
## `Camera3D.unproject_position`, and it knows nothing about nodes, fonts or drawing: `Hud` draws the frame it returns.
##
## Sizes scale with viewport height / 1080. Colours come from `Factions` (hostile red, friendly blue, neutral or unknown
## yellow; the HUD's own line work is green).

const BORESIGHT_RANGE_M: float = 1000.0
const MIN_SPEED_FOR_MARKER_MPS: float = 1.0
const MIN_BOX_PX: float = 24.0
const EDGE_MARGIN_PX: float = 48.0
const GRID_SPAN_DEG: float = 30.0
const LINE_COLOR: Color = Factions.HUD_LINE_COLOR
const AMBER: Color = Color(1.0, 0.8, 0.2)
const RED: Color = Color(1.0, 0.3, 0.25)
## The octagon's grid (M3-T29): red, with the rings and own ship in the line colour.
## The chase view's radar radius at 1080p; a bigger radar draws everything on it larger by the same ratio.
const RADAR_RADIUS_UNITS: float = 78.0
const OCTAGON_GRID_COLOR: Color = Color(0.95, 0.12, 0.10)
const OCTAGON_GRID_ALPHA: float = 0.2  # dim enough that the radar's red hostile contacts stand off it
## The console's indicator lamps, by id: lit in this colour, dark otherwise.
const LAMP_COLORS: Dictionary = {&"assist": Color(0.92, 0.95, 1.0), &"guns": Color(1.0, 0.16, 0.12), &"lights": Color(0.92, 0.95, 1.0),
		&"track": Color(1.0, 0.16, 0.12)}
## The screens' heights in layout units; a screen's scale is its pixel height over this, so what it shows fits at any resolution.
const OCTAGON_UNITS: float = 300.0
const SIDE_SCREEN_UNITS: float = 250.0
## The right screen's charge bar: its share of the screen's width.
const CHARGE_BAR_WIDTH_SHARE: float = 40.0 / 640.0
## The wing roster, top left (at 1080 px; scaled): its first row's top-left corner, the row pitch and the hull bar.
const ROSTER_ORIGIN: Vector2 = Vector2(48.0, 48.0)
const ROSTER_ROW_PX: float = 24.0
const ROSTER_BAR: Vector2 = Vector2(64.0, 8.0)
## The acknowledgement line's baseline below the status line's (under AUTO-TRACK's, 26 px below it).
const ACK_BELOW_STATUS_PX: float = 50.0
const STATUS_Y_PX: float = 36.0
## The objectives list (M5-T05), top right (at 1080 px; scaled): the caption's baseline below the FPS counter, and the line pitch.
const OBJECTIVES_TOP_PX: float = 110.0
const OBJECTIVE_ROW_PX: float = 22.0
## A roster row's short form of what a wingman is doing, by behaviour id.
const ROSTER_TAGS: Dictionary = {"formation": "FORM", "attack": "ATK", "evade": "EVADE", "retreat": "RETREAT",
		"follow_path": "NAV", "idle": "IDLE", "none": "-"}


## One wingman's line in the roster: the hull bar (outline `bar_rect`, filled to `hull`, in `color`), and the callsign and tag
## (`text`, baseline left at `text_pos`); `down` rows have an empty bar and read DOWN.
class RosterRow extends RefCounted:
	var text: String = ""
	var text_pos: Vector2 = Vector2.ZERO
	var bar_rect: Rect2 = Rect2()
	var hull: float = 0.0
	var color: Color = Factions.FRIENDLY_COLOR
	var down: bool = false


static func compute(input: HudInput) -> HudFrame:
	var f := HudFrame.new()
	f.viewport_size = input.viewport_size
	f.size = input.viewport_size
	f.cockpit = input.cockpit
	f.scale = maxf(input.viewport_size.y / 1080.0, 0.25)  # a floor, so a degenerate viewport cannot ask for a zero-size font
	_markers(input, f)
	_target(input, f)
	_gauges(input, f)
	_grid(input, f)
	_radar(input, f)
	_waypoint(input, f)
	_wing(input, f)
	_objectives(input, f)
	f.status_line = input.status_line
	f.items = HudSurface.ALL_ITEMS.duplicate()
	if not f.grid_visible:
		f.items.erase(HudSurface.GRID)
	f.lamps = {&"assist": input.assist, &"guns": input.guns_ready, &"lights": input.running_lights, &"track": input.tracking}
	if on_screens(input):
		_split_onto_screens(input, f)
	if not f.objective_lines.is_empty():
		f.items.append(HudSurface.OBJECTIVES)  # on the window in both views
	return f


## Whether the instruments are on the console's screens: the cockpit view, in a ship that has them.
static func on_screens(input: HudInput) -> bool:
	return input.cockpit and not input.screen_sizes.is_empty()


## Pixel position of a World-frame point and whether it is in front of the camera: `{"in_front": bool, "pos": Vector2}`.
## `pos` is meaningful only when `in_front`.
static func project(input: HudInput, point: Vector3) -> Dictionary:
	var p_view: Vector3 = input.camera_transform.affine_inverse() * point
	var clip: Vector4 = input.projection * Vector4(p_view.x, p_view.y, p_view.z, 1.0)
	if clip.w <= 1e-6:
		return {"in_front": false, "pos": Vector2.ZERO}
	var ndc := Vector2(clip.x / clip.w, clip.y / clip.w)
	return {"in_front": true, "pos": Vector2((ndc.x * 0.5 + 0.5) * input.viewport_size.x, (0.5 - ndc.y * 0.5) * input.viewport_size.y)}


static func on_screen(input: HudInput, pos: Vector2) -> bool:
	return pos.x >= 0.0 and pos.y >= 0.0 and pos.x <= input.viewport_size.x and pos.y <= input.viewport_size.y


## Colour of a damage zone: the HUD's own green when untouched, then yellow, orange and red as it is wrecked (severity 0..1).
static func damage_color(severity: float) -> Color:
	if severity <= 0.0:
		return Factions.HUD_LINE_COLOR
	if severity < 0.34:
		return Color(1.0, 0.9, 0.2)
	if severity < 0.67:
		return Color(1.0, 0.55, 0.15)
	return RED


static func hull_color(fraction: float) -> Color:
	if fraction > 0.5:
		return Factions.HUD_LINE_COLOR
	if fraction > 0.25:
		return AMBER
	return RED


# --- boresight and velocity marker ---------------------------------------------------------------------------------


static func _markers(input: HudInput, f: HudFrame) -> void:
	var nose: Dictionary = project(input, input.own_position - input.own_basis.z * BORESIGHT_RANGE_M)
	f.boresight_pos = nose["pos"]
	f.boresight_visible = bool(nose["in_front"]) and on_screen(input, f.boresight_pos)
	f.speed_mps = input.own_velocity.length()
	f.tracking = input.tracking
	_velocity_readout(input, f)
	if f.speed_mps < MIN_SPEED_FOR_MARKER_MPS or not input.show_velocity_marker:
		return
	var heading: Vector3 = input.own_velocity / f.speed_mps
	var prograde: Dictionary = project(input, input.own_position + heading * BORESIGHT_RANGE_M)
	if bool(prograde["in_front"]):
		f.velocity_pos = prograde["pos"]
		f.velocity_visible = on_screen(input, f.velocity_pos)
		return
	# Prograde is behind the camera: show retrograde (the point the ship is moving away from) instead.
	var retro: Dictionary = project(input, input.own_position - heading * BORESIGHT_RANGE_M)
	f.retrograde = true
	f.velocity_pos = retro["pos"]
	f.velocity_visible = bool(retro["in_front"]) and on_screen(input, f.velocity_pos)


# The speed with its direction against the nose, and the reference point's range and closing speed.
static func _velocity_readout(input: HudInput, f: HudFrame) -> void:
	if f.speed_mps >= MIN_SPEED_FOR_MARKER_MPS:
		f.drift_dir = RadarModel.radar_direction(input.own_basis.transposed() * input.own_velocity)
		var angles: Vector2 = velocity_angles_deg(input.own_basis, input.own_velocity)
		f.velocity_h_deg = angles.x
		f.velocity_v_deg = angles.y
		f.velocity_angles_valid = true
	if input.has_reference:
		var offset: Vector3 = input.reference_position - input.own_position
		f.reference_range_m = offset.length()
		f.reference_valid = true
		if f.reference_range_m > 1e-3:
			# Positive when the ship is closing on the reference: the ship's velocity relative to it, along the line to it.
			f.reference_closing_mps = (input.own_velocity - input.reference_velocity).dot(offset / f.reference_range_m)


## Direction of `velocity` against the nose of a ship with orientation `basis` (-Z forward): `x` is the horizontal angle,
## positive to the right of the nose, in -180..180 (180 = flying backward); `y` the vertical angle, positive above the nose,
## in -90..90. A velocity of zero gives (0, 0).
static func velocity_angles_deg(basis: Basis, velocity: Vector3) -> Vector2:
	var v: Vector3 = basis.transposed() * velocity
	if v.length_squared() < 1e-12:
		return Vector2.ZERO
	var horizontal: float = rad_to_deg(atan2(v.x, -v.z))
	var vertical: float = rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
	return Vector2(horizontal, vertical)


# --- target box, edge arrow, lead ------------------------------------------------------------------------------------


static func _target(input: HudInput, f: HudFrame) -> void:
	var t: TargetReadout = input.target
	if t == null:
		return
	f.target_present = true
	f.target_name = t.display_name
	f.target_range_m = t.range_m
	f.target_closing_mps = t.closing_mps
	f.target_hull = t.hull_fraction
	f.target_relation = Factions.relation(input.faction, t.faction)
	f.target_color = Factions.hud_color(f.target_relation)
	var shown: Dictionary = project(input, t.position)
	if bool(shown["in_front"]) and on_screen(input, shown["pos"]):
		f.target_on_screen = true
		f.target_box = _box_around(input, f, t, shown["pos"])
	else:
		var edge: Dictionary = _edge_arrow(input, f, t.position)
		f.edge_arrow_pos = edge["pos"]
		f.edge_arrow_angle = edge["angle"]
		f.edge_arrow_visible = true
	# The lead: where the bolt meets the target, from the mean muzzle position, hidden when there is no solution in range.
	var lead: Dictionary = InterceptMath.solve(input.muzzle_position, input.own_velocity, t.position, t.velocity,
			input.weapon_speed_mps, input.weapon_lifetime_s)
	if bool(lead["ok"]):
		var at: Dictionary = project(input, lead["lead_point"])
		if bool(at["in_front"]):
			f.lead_pos = at["pos"]
			f.lead_visible = on_screen(input, f.lead_pos)
			f.lead_tof_s = float(lead["t"])


# A square at least MIN_BOX_PX (scaled) wide, or the target's projected bounding radius if that is larger.
static func _box_around(input: HudInput, f: HudFrame, t: TargetReadout, centre: Vector2) -> Rect2:
	var half: float = 0.5 * MIN_BOX_PX * f.scale
	if t.bounding_radius > 0.0:
		var right: Vector3 = input.camera_transform.basis.x
		var edge: Dictionary = project(input, t.position + right * t.bounding_radius)
		if bool(edge["in_front"]):
			half = maxf(half, ((edge["pos"] as Vector2) - centre).length())
	return Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)


# On the screen border, pointing the way to a point that is off screen or behind the camera: `{"pos": Vector2, "angle": float}`.
static func _edge_arrow(input: HudInput, f: HudFrame, point: Vector3) -> Dictionary:
	var p_view: Vector3 = input.camera_transform.affine_inverse() * point
	var dir := Vector2(p_view.x, -p_view.y)  # screen frame: x right, y down; the side the target is on
	if dir.length() < 1e-4:
		dir = Vector2(0.0, 1.0)  # dead ahead of or behind the camera's axis: point down
	dir = dir.normalized()
	var half: Vector2 = input.viewport_size * 0.5 - Vector2.ONE * EDGE_MARGIN_PX * f.scale
	# Scale `dir` out from the centre until it meets the inset border.
	var k: float = minf(half.x / maxf(absf(dir.x), 1e-6), half.y / maxf(absf(dir.y), 1e-6))
	return {"pos": input.viewport_size * 0.5 + dir * k, "angle": dir.angle()}


# --- route waypoint (M3-T09) -------------------------------------------------------------------------------------------


# The route's next waypoint: a marker where it projects, or an edge arrow, with its label and range.
static func _waypoint(input: HudInput, f: HudFrame) -> void:
	if not input.has_waypoint:
		return
	f.waypoint_present = true
	f.waypoint_label = input.waypoint_label
	f.waypoint_range_m = input.own_position.distance_to(input.waypoint_position)
	var shown: Dictionary = project(input, input.waypoint_position)
	if bool(shown["in_front"]) and on_screen(input, shown["pos"]):
		f.waypoint_on_screen = true
		f.waypoint_pos = shown["pos"]
		return
	var edge: Dictionary = _edge_arrow(input, f, input.waypoint_position)
	f.waypoint_edge_visible = true
	f.waypoint_edge_pos = edge["pos"]
	f.waypoint_edge_angle = edge["angle"]


# --- bottom-edge gauges --------------------------------------------------------------------------------------------


static func _gauges(input: HudInput, f: HudFrame) -> void:
	f.hull_fraction = clampf(input.hull_fraction, 0.0, 1.0)
	f.hull_color = hull_color(f.hull_fraction)
	f.god = input.god
	f.fuel_fraction = clampf(input.fuel_fraction, 0.0, 1.0)
	f.fuel_unlimited = input.fuel_unlimited
	f.own_layout = input.damage_layout
	f.own_zones = input.damage_zones
	f.charge_fraction = clampf(input.charge_fraction, 0.0, 1.0)
	f.fire_mode = input.fire_mode
	var w: float = input.viewport_size.x
	var h: float = input.viewport_size.y
	var s: float = f.scale
	var bar := Vector2(260.0, 14.0) * s
	var margin: float = 48.0 * s
	f.speed_pos = Vector2(w * 0.5, h - 40.0 * s)
	f.speed_align_right = not input.cockpit
	if not input.cockpit:
		# Chase view: the ship fills the middle, so the readout sits above the radar in the bottom-right corner.
		f.speed_pos = Vector2(w - margin, h - 56.0 * s - 30.0 * s - 2.0 * 78.0 * s - 28.0 * s)
	f.hull_rect = Rect2(Vector2(margin, h - 90.0 * s), bar)
	f.fuel_rect = Rect2(Vector2(margin, h - 56.0 * s), bar)
	f.charge_rect = Rect2(Vector2(w - margin - bar.x, h - 56.0 * s), bar)
	f.running_lights_dark = not input.running_lights
	f.running_lights_text = "LIGHTS OFF" if f.running_lights_dark else "LIGHTS ON"
	f.running_lights_pos = f.charge_rect.position + Vector2(0.0, -24.0 * s)
	var outline := Vector2(150.0, 112.0) * s
	f.own_silhouette_rect = Rect2(Vector2(margin, h - 98.0 * s - outline.y - 22.0 * s), outline)


# --- targeting grid --------------------------------------------------------------------------------------------------


static func _grid(input: HudInput, f: HudFrame) -> void:
	f.grid_visible = input.cockpit or input.show_grid
	if on_screens(input):
		f.grid_visible = false  # its place is the octagon
	if not f.grid_visible:
		return
	var side: float = 260.0 * f.scale
	_fill_grid(input, f, Rect2(Vector2(input.viewport_size.x * 0.5 - side * 0.5, input.viewport_size.y * 0.62 - side * 0.5), Vector2(side, side)))


# The grid on `surface`, in `rect`, with the marker for the selected target.
static func _fill_grid(input: HudInput, surface: HudSurface, rect: Rect2) -> void:
	surface.grid_visible = true
	surface.grid_rect = rect
	var side: float = minf(rect.size.x, rect.size.y)
	var t: TargetReadout = input.target
	if t == null:
		return
	# The target's bearing in the ship's frame, as angles off the nose: azimuth right and elevation up.
	var rel: Vector3 = input.own_basis.transposed() * (t.position - input.own_position)
	if -rel.z <= 1e-4:
		return  # behind the beam: no marker (the edge arrow covers it)
	var az: float = rad_to_deg(atan2(rel.x, -rel.z))
	var el: float = rad_to_deg(atan2(rel.y, -rel.z))
	surface.grid_marker_inside = absf(az) <= GRID_SPAN_DEG and absf(el) <= GRID_SPAN_DEG
	var nx: float = clampf(az / GRID_SPAN_DEG, -1.0, 1.0)
	var ny: float = clampf(el / GRID_SPAN_DEG, -1.0, 1.0)
	surface.grid_marker = rect.get_center() + Vector2(nx, -ny) * side * 0.5
	surface.grid_marker_visible = true


# --- radar -------------------------------------------------------------------------------------------------------------


static func _radar(input: HudInput, f: HudFrame) -> void:
	f.radar_radius_px = RADAR_RADIUS_UNITS * f.scale
	f.radar_centre = Vector2(input.viewport_size.x * 0.5, input.viewport_size.y - 176.0 * f.scale)
	if not input.cockpit:
		# Chase view: bottom-right corner, over the charge bar.
		f.radar_centre = Vector2(input.viewport_size.x - 48.0 * f.scale - 130.0 * f.scale, input.viewport_size.y - 56.0 * f.scale - 30.0 * f.scale - f.radar_radius_px)
	if input.target != null and input.target.damage_layout != DamageZones.Layout.NONE:
		f.target_layout = input.target.damage_layout
		f.target_zones = input.target.damage_zones
		var outline := Vector2(150.0, 112.0) * f.scale
		if input.cockpit:
			f.target_silhouette_rect = Rect2(f.radar_centre + Vector2(f.radar_radius_px + 28.0 * f.scale, -outline.y * 0.5), outline)
		else:
			f.target_silhouette_rect = Rect2(f.radar_centre + Vector2(-f.radar_radius_px - 28.0 * f.scale - outline.x, -outline.y * 0.5), outline)
	f.drift_radius_px = 58.0 * f.scale
	# Beside the speed readout: to its left, on the same lines (the readout is right-aligned in the chase view, centred in the cockpit).
	if input.cockpit:
		f.drift_centre = f.speed_pos + Vector2(-120.0 * f.scale - f.drift_radius_px, -30.0 * f.scale)
	else:
		f.drift_centre = f.speed_pos + Vector2(-215.0 * f.scale - f.drift_radius_px, 0.0)
	f.radar_dots = RadarModel.dots(input.contacts, input.selected_id, input.own_position, input.own_basis, input.faction)


# --- wing roster and acknowledgements (M3-T11) -----------------------------------------------------------------------


## The roster's short form of a wingman's activity: `FORM`, `ATK RAIDER 3` (the target when known), `EVADE`, `DOWN`...
## An unknown behaviour reads as its id in capitals.
static func roster_tag(behaviour: String, target: String = "", down: bool = false) -> String:
	if down:
		return "DOWN"
	var tag: String = ROSTER_TAGS.get(behaviour, behaviour.to_upper())
	if behaviour == "attack" and not target.is_empty():
		tag += " " + target
	return tag


static func _wing(input: HudInput, f: HudFrame) -> void:
	var s: float = f.scale
	var origin: Vector2 = ROSTER_ORIGIN * s
	# Clear of the debug overlay's text at the top left, while it shows.
	if input.overlay_bottom_px > 0.0:
		origin.y = maxf(origin.y, input.overlay_bottom_px + 8.0 * s)
	f.roster_rows = _roster_rows(input, origin, s)
	f.ack_line = input.ack_line
	f.ack_pos = Vector2(input.viewport_size.x * 0.5, (STATUS_Y_PX + ACK_BELOW_STATUS_PX) * s)
	f.status_pos = Vector2(input.viewport_size.x * 0.5, STATUS_Y_PX * s)
	f.tracking_pos = Vector2(input.viewport_size.x * 0.5, 62.0 * s)


static func _roster_rows(input: HudInput, origin: Vector2, s: float, pitch: float = ROSTER_ROW_PX) -> Array[RosterRow]:
	var rows: Array[RosterRow] = []
	for i: int in input.roster.size():
		var entry: Dictionary = input.roster[i]
		var row := RosterRow.new()
		var top: float = origin.y + pitch * s * float(i)
		row.down = bool(entry.get("down", false))
		row.hull = 0.0 if row.down else clampf(float(entry.get("hull", 0.0)), 0.0, 1.0)
		row.color = RED if row.down else input.roster_color
		row.bar_rect = Rect2(Vector2(origin.x, top + 6.0 * s), ROSTER_BAR * s)
		row.text = "%s  %s" % [str(entry.get("callsign", "")),
				roster_tag(str(entry.get("behaviour", "")), str(entry.get("target", "")), row.down)]
		row.text_pos = Vector2(origin.x + (ROSTER_BAR.x + 10.0) * s, top + 16.0 * s)
		rows.append(row)
	return rows


# --- mission objectives (M5-T05) ------------------------------------------------------------------------------------------


## The objectives list's line for one objective: its text (its id when it has none) in capitals, optional ones marked.
static func objective_text(objective: Dictionary) -> String:
	var text: String = str(objective.get("text", ""))
	if text.is_empty():
		text = str(objective.get("id", ""))
	return text.to_upper() + ("" if bool(objective.get("primary", true)) else "  (OPTIONAL)")


static func _objectives(input: HudInput, f: HudFrame) -> void:
	f.objective_lines = []
	if input.objectives.is_empty():
		return
	var s: float = f.scale
	var x: float = input.viewport_size.x - 48.0 * s
	f.objectives_caption_pos = Vector2(x, OBJECTIVES_TOP_PX * s)
	for i: int in input.objectives.size():
		var objective: Dictionary = input.objectives[i]
		f.objective_lines.append({"text": objective_text(objective),
				"pos": Vector2(x, (OBJECTIVES_TOP_PX + OBJECTIVE_ROW_PX * float(i + 1)) * s),
				"primary": bool(objective.get("primary", true))})


# --- the console's screens (M3-T29) ---------------------------------------------------------------------------------------


# The cockpit view with screens: the window keeps only what must line up with the world; everything else goes to the console.
static func _split_onto_screens(input: HudInput, f: HudFrame) -> void:
	f.items = [HudSurface.BORESIGHT, HudSurface.VELOCITY, HudSurface.TARGET_MARKS, HudSurface.WAYPOINT]
	f.roster_rows = []
	f.screens = {}
	for id: StringName in input.screen_sizes:
		var size: Vector2 = input.screen_sizes[id]
		match id:
			&"octagon":
				f.screens[id] = _octagon_screen(input, size)
			&"left":
				f.screens[id] = _left_screen(size)
			&"right":
				f.screens[id] = _right_screen(input, size)


static func _screen(size: Vector2, units: float) -> HudSurface:
	var surface := HudSurface.new()
	surface.size = size
	surface.scale = size.y / units
	return surface


# Radar and tactical grid: a red grid filling the display, the sphere over it, and AUTO-TRACK across the top when it is on.
static func _octagon_screen(input: HudInput, size: Vector2) -> HudSurface:
	var surface: HudSurface = _screen(size, OCTAGON_UNITS)
	surface.items = [HudSurface.GRID, HudSurface.RADAR, HudSurface.TRACKING]
	surface.grid_color = OCTAGON_GRID_COLOR
	surface.grid_line_alpha = OCTAGON_GRID_ALPHA
	surface.grid_marker_diagonal = true
	_fill_grid(input, surface, Rect2(Vector2.ZERO, size))
	surface.radar_centre = size * 0.5
	surface.radar_radius_px = 0.40 * size.y
	surface.radar_labels = true
	surface.tracking_pos = Vector2(size.x * 0.5, 30.0 * surface.scale)
	return surface


# Own ship: damage wireframe and drift sphere above, the speed large with its angles and reference under them, and at the bottom the hull as
# a thick full-width bar: in the cockpit view this screen is its only place, so it reads first.
static func _left_screen(size: Vector2) -> HudSurface:
	var surface: HudSurface = _screen(size, SIDE_SCREEN_UNITS)
	var s: float = surface.scale
	var width: float = size.x / s  # in layout units
	surface.items = [HudSurface.SPEED, HudSurface.HULL_BAR, HudSurface.FUEL_BAR, HudSurface.RUNNING_LIGHTS, HudSurface.DRIFT, HudSurface.OWN_SILHOUETTE]
	surface.own_silhouette_rect = Rect2(Vector2(8.0, 18.0) * s, Vector2(minf(130.0, width * 0.38), 90.0) * s)
	surface.drift_radius_px = 42.0 * s
	surface.drift_centre = Vector2(width - 8.0 - 42.0, 20.0 + 42.0) * s
	surface.speed_pos = Vector2(width * 0.5, 158.0) * s
	surface.speed_size = 30.0
	surface.running_lights_pos = Vector2(8.0, 126.0) * s  # above the speed block: the REF line can run wide
	surface.fuel_rect = Rect2(Vector2(width - 8.0 - 74.0, 122.0) * s, Vector2(74.0, 5.0) * s)
	surface.hull_rect = Rect2(Vector2(8.0, 212.0) * s, Vector2(width - 16.0, 30.0) * s)
	surface.bar_caption_size = 17.0
	surface.bar_percent = true
	return surface


# The selected target across the full width, a divider, then the small charge bar at the right edge with the wing and the lines to its left.
static func _right_screen(input: HudInput, size: Vector2) -> HudSurface:
	var surface: HudSurface = _screen(size, SIDE_SCREEN_UNITS)
	var s: float = surface.scale
	var width: float = size.x / s
	surface.items = [HudSurface.TARGET_PANEL, HudSurface.TARGET_SILHOUETTE, HudSurface.CHARGE_BAR, HudSurface.STATUS, HudSurface.ACK, HudSurface.ROSTER]
	surface.target_panel_pos = Vector2(8.0, 24.0) * s
	surface.target_bar_rect = Rect2(Vector2(8.0, 58.0) * s, Vector2(width * 0.52, 12.0) * s)
	surface.target_silhouette_rect = Rect2(Vector2(width - 8.0 - 108.0, 6.0) * s, Vector2(108.0, 78.0) * s)
	surface.divider_y = 90.0 * s
	var bar_width: float = width * CHARGE_BAR_WIDTH_SHARE
	surface.charge_vertical = true
	surface.charge_caption_pos = Vector2(width - 6.0, 106.0) * s
	surface.charge_rect = Rect2(Vector2(width - 6.0 - bar_width, 126.0) * s, Vector2(bar_width, 250.0 - 126.0 - 6.0) * s)
	var text_width: float = width - 8.0 - 6.0 - bar_width - 8.0
	surface.roster_caption_pos = Vector2(8.0, 106.0) * s
	surface.roster_text_size = 14.0
	surface.roster_rows = _roster_rows(input, Vector2(8.0, 110.0) * s, s, 20.0)
	surface.lines_centred = false
	surface.lines_width = text_width * s
	surface.ack_pos = Vector2(8.0, 204.0) * s
	surface.status_pos = Vector2(8.0, 222.0) * s
	return surface
