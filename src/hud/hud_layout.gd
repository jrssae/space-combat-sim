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
const AMBER: Color = Color(1.0, 0.8, 0.2)
const RED: Color = Color(1.0, 0.3, 0.25)


static func compute(input: HudInput) -> HudFrame:
	var f := HudFrame.new()
	f.viewport_size = input.viewport_size
	f.scale = maxf(input.viewport_size.y / 1080.0, 0.25)  # a floor, so a degenerate viewport cannot ask for a zero-size font
	_markers(input, f)
	_target(input, f)
	_gauges(input, f)
	_grid(input, f)
	_radar(input, f)
	f.status_line = input.status_line
	return f


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
	if f.speed_mps < MIN_SPEED_FOR_MARKER_MPS:
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
	f.target_color = Factions.hud_color(Factions.relation(input.faction, t.faction))
	var shown: Dictionary = project(input, t.position)
	if bool(shown["in_front"]) and on_screen(input, shown["pos"]):
		f.target_on_screen = true
		f.target_box = _box_around(input, f, t, shown["pos"])
	else:
		_edge_arrow(input, f, t.position)
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


# On the screen border, pointing the way to a target that is off screen or behind the camera.
static func _edge_arrow(input: HudInput, f: HudFrame, point: Vector3) -> void:
	var p_view: Vector3 = input.camera_transform.affine_inverse() * point
	var dir := Vector2(p_view.x, -p_view.y)  # screen frame: x right, y down; the side the target is on
	if dir.length() < 1e-4:
		dir = Vector2(0.0, 1.0)  # dead ahead of or behind the camera's axis: point down
	dir = dir.normalized()
	var half: Vector2 = input.viewport_size * 0.5 - Vector2.ONE * EDGE_MARGIN_PX * f.scale
	# Scale `dir` out from the centre until it meets the inset border.
	var k: float = minf(half.x / maxf(absf(dir.x), 1e-6), half.y / maxf(absf(dir.y), 1e-6))
	f.edge_arrow_pos = input.viewport_size * 0.5 + dir * k
	f.edge_arrow_angle = dir.angle()
	f.edge_arrow_visible = true


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
	f.hull_rect = Rect2(Vector2(margin, h - 90.0 * s), bar)
	f.fuel_rect = Rect2(Vector2(margin, h - 56.0 * s), bar)
	f.charge_rect = Rect2(Vector2(w - margin - bar.x, h - 56.0 * s), bar)
	var outline := Vector2(150.0, 112.0) * s
	f.own_silhouette_rect = Rect2(Vector2(margin, h - 98.0 * s - outline.y - 22.0 * s), outline)


# --- targeting grid --------------------------------------------------------------------------------------------------


static func _grid(input: HudInput, f: HudFrame) -> void:
	f.grid_visible = input.cockpit or input.show_grid
	if not f.grid_visible:
		return
	var side: float = 260.0 * f.scale
	f.grid_rect = Rect2(Vector2(input.viewport_size.x * 0.5 - side * 0.5, input.viewport_size.y * 0.62 - side * 0.5), Vector2(side, side))
	var t: TargetReadout = input.target
	if t == null:
		return
	# The target's bearing in the ship's frame, as angles off the nose: azimuth right and elevation up.
	var rel: Vector3 = input.own_basis.transposed() * (t.position - input.own_position)
	if -rel.z <= 1e-4:
		return  # behind the beam: no marker (the edge arrow covers it)
	var az: float = rad_to_deg(atan2(rel.x, -rel.z))
	var el: float = rad_to_deg(atan2(rel.y, -rel.z))
	f.grid_marker_inside = absf(az) <= GRID_SPAN_DEG and absf(el) <= GRID_SPAN_DEG
	var nx: float = clampf(az / GRID_SPAN_DEG, -1.0, 1.0)
	var ny: float = clampf(el / GRID_SPAN_DEG, -1.0, 1.0)
	f.grid_marker = f.grid_rect.get_center() + Vector2(nx, -ny) * side * 0.5
	f.grid_marker_visible = true


# --- radar -------------------------------------------------------------------------------------------------------------


static func _radar(input: HudInput, f: HudFrame) -> void:
	f.radar_radius_px = 78.0 * f.scale
	f.radar_centre = Vector2(input.viewport_size.x * 0.5, input.viewport_size.y - 176.0 * f.scale)
	if input.target != null and input.target.damage_layout != DamageZones.Layout.NONE:
		f.target_layout = input.target.damage_layout
		f.target_zones = input.target.damage_zones
		var outline := Vector2(150.0, 112.0) * f.scale
		f.target_silhouette_rect = Rect2(f.radar_centre + Vector2(f.radar_radius_px + 28.0 * f.scale, -outline.y * 0.5), outline)
	f.radar_dots = RadarModel.dots(input.contacts, input.selected_id, input.own_position, input.own_basis, input.faction)
