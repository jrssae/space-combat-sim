class_name HudPainter
extends RefCounted
## Draws the HUD's instruments on one canvas (M3-T29): the 2D layer and each console screen hold one, so there is a single set of drawing
## code. `paint` runs inside that canvas's `_draw`. Data comes from the `HudFrame`, places from the `HudSurface`.
##
## Elements: boresight cross, (optionally, `settings.hud_velocity_marker`) a prograde circle with wings or retrograde circle with a cross, the
## drift sphere by the speed readout, target box (corner brackets) with name, range, closing speed and a hull bar, an edge arrow for an
## off-screen target, the lead diamond, the status line; speed with the direction of travel against the nose (horizontal then vertical
## degrees) and the range and closing speed to the reference point, hull bar with the ship's damage silhouette above it, a fuel bar (only
## when the tank is finite), weapon charge and fire mode, the radar sphere with the target's damage silhouette beside it, whether the running
## lights are on (M3-T27), a grid with a reticle and the target's offset from the nose on it.

const LINE_COLOR: Color = HudLayout.LINE_COLOR
const TEXT_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.8)
## Sides of the radar's batched dots (M4-T36): round at their few pixels.
const DOT_SEGMENTS: int = 16

## What the last radar paint cost, us (a readout): the dot buffers and the draws.
static var radar_paint_us: int = 0
static var _shared_font: Font = null
static var _dot_mesh: ArrayMesh = null
# Hollow rim dots' rings, by their thickness over their radius (M4-T23).
static var _ring_meshes: Dictionary = {}

## What the last `paint` was asked to draw (tests and the console read it).
var painted: Array[StringName] = []

var _canvas: CanvasItem = null
var _font: Font = null
# The radar's contacts as one draw each (M4-T36): the dots and, on a labelled radar, their dark backings.
var _dots: MultiMesh = null
var _backings: MultiMesh = null
# The hollow rim dots (broadcasts beyond the sensors) as one draw too (M4-T23: the tier's far allies are hundreds of them).
var _rims: MultiMesh = null


func _init(canvas: CanvasItem) -> void:
	_canvas = canvas
	_font = _hud_font()


## The HUD's font, for what is drawn beside the instruments (the comms panel's subtitles).
static func font() -> Font:
	return _hud_font()


static func _hud_font() -> Font:
	if _shared_font == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "Monospace"])
		_shared_font = system
	return _shared_font


## Draws what `surface` lists, from `f`.
func paint(f: HudFrame, surface: HudSurface) -> void:
	painted = surface.items
	var s: float = surface.scale
	var w: float = maxf(1.0, 2.0 * s)  # 2 px lines at 1080p
	var items: Array[StringName] = surface.items
	if items.has(HudSurface.BORESIGHT):
		_draw_boresight(f, s, w)
	if items.has(HudSurface.VELOCITY):
		_draw_velocity(f, s, w)
	if items.has(HudSurface.TARGET_MARKS):
		_draw_target_marks(f, s, w, items.has(HudSurface.TARGET_LABEL))
	if items.has(HudSurface.TARGET_PANEL):
		_draw_target_panel(f, surface, s, w)
	if items.has(HudSurface.WAYPOINT):
		_draw_waypoint(f, s, w)
	if items.has(HudSurface.GRID):
		_draw_grid(surface, f, s, w)
	if items.has(HudSurface.SPEED):
		_draw_speed(f, surface, s)
	if items.has(HudSurface.HULL_BAR):
		_captioned_bar(surface, surface.hull_rect, f.hull_fraction, f.hull_color, "HULL" + ("  GOD" if f.god else ""), s, w)
	if items.has(HudSurface.FUEL_BAR) and not f.fuel_unlimited:
		_bar(surface.fuel_rect, f.fuel_fraction, LINE_COLOR, w)
		_text("FUEL", surface.fuel_rect.position + Vector2(0.0, -6.0 * s), 14.0 * s, LINE_COLOR)
	if items.has(HudSurface.CHARGE_BAR):
		if surface.charge_vertical:
			_draw_vertical_charge(f, surface, s, w)
		else:
			_captioned_bar(surface, surface.charge_rect, f.charge_fraction, LINE_COLOR, "CHARGE  %s" % f.fire_mode.to_upper(), s, w)
	if items.has(HudSurface.RUNNING_LIGHTS):
		_text(f.running_lights_text, surface.running_lights_pos, 14.0 * s, HudLayout.AMBER if f.running_lights_dark else LINE_COLOR)
	if items.has(HudSurface.RADAR):
		var before_us: int = Time.get_ticks_usec()
		_draw_radar(f, surface, s, w)
		radar_paint_us = Time.get_ticks_usec() - before_us
	if items.has(HudSurface.DRIFT):
		_draw_drift_sphere(f, surface, s, w)
	if items.has(HudSurface.OWN_SILHOUETTE):
		_draw_silhouette(f.own_layout, f.own_zones, surface.own_silhouette_rect, "YOU", w)
	if items.has(HudSurface.TARGET_SILHOUETTE):
		_draw_silhouette(f.target_layout, f.target_zones, surface.target_silhouette_rect, "" if items.has(HudSurface.TARGET_PANEL) else f.target_name, w)
	if items.has(HudSurface.TRACKING) and f.tracking:
		_text("AUTO-TRACK", surface.tracking_pos, 16.0 * s, HudLayout.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	if items.has(HudSurface.STATUS) and not f.status_line.is_empty():
		_line(surface, f.status_line, surface.status_pos, 18.0 * s)
	if items.has(HudSurface.ACK) and not f.ack_line.is_empty():
		_line(surface, f.ack_line, surface.ack_pos, 16.0 * s)
	if items.has(HudSurface.ROSTER):
		_draw_roster(surface, s, w)
	if items.has(HudSurface.OBJECTIVES):
		_draw_objectives(f, s)


# The wing roster (M3-T11): per wingman a hull bar in the wing's colour, the callsign and what it is doing.
func _draw_roster(surface: HudSurface, s: float, w: float) -> void:
	if surface.roster_caption_pos != Vector2.ZERO and not surface.roster_rows.is_empty():
		_text("WING", surface.roster_caption_pos, 12.0 * s, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.7))
	for row: HudLayout.RosterRow in surface.roster_rows:
		_bar(row.bar_rect, row.hull, row.color, w)
		_text(row.text, row.text_pos, surface.roster_text_size * s, row.color if row.down else LINE_COLOR)


# The mission's active objectives (M5-T05), right-aligned at the top right: optional ones fainter.
func _draw_objectives(f: HudFrame, s: float) -> void:
	var faint := Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.7)
	_text("OBJECTIVES", f.objectives_caption_pos, 12.0 * s, faint, HORIZONTAL_ALIGNMENT_RIGHT)
	for line: Dictionary in f.objective_lines:
		_text(String(line["text"]), line["pos"] as Vector2, 15.0 * s, LINE_COLOR if bool(line["primary"]) else faint,
				HORIZONTAL_ALIGNMENT_RIGHT)


# --- helpers --------------------------------------------------------------------------------------------------


func _text(text: String, pos: Vector2, size: float, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var width: float = _font.get_string_size(text, align, -1.0, int(size)).x
	var origin: Vector2 = pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		origin.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		origin.x -= width
	_canvas.draw_string(_font, origin + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(size), TEXT_SHADOW)
	_canvas.draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(size), color)


# A status or acknowledgement line: centred on the 2D layer, on a screen starting at `at`, smaller, and wrapped to the room it has.
func _line(surface: HudSurface, text: String, at: Vector2, size: float) -> void:
	if surface.lines_centred:
		_text(text, at, size, LINE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var fitted: int = int(13.0 * surface.scale)
	_canvas.draw_multiline_string(_font, at + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, surface.lines_width, fitted, -1, TEXT_SHADOW)
	_canvas.draw_multiline_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, surface.lines_width, fitted, -1, LINE_COLOR)


# The bar that stands up at a screen's edge: its label and fire mode right-aligned above it, filling from the bottom.
func _draw_vertical_charge(f: HudFrame, surface: HudSurface, s: float, w: float) -> void:
	var rect: Rect2 = surface.charge_rect
	_text("CHARGE", surface.charge_caption_pos, 12.0 * s, LINE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(f.fire_mode.to_upper(), surface.charge_caption_pos + Vector2(0.0, 14.0 * s), 11.0 * s, LINE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	_canvas.draw_rect(rect, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.15), true)
	var filled: float = rect.size.y * clampf(f.charge_fraction, 0.0, 1.0)
	_canvas.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - filled), Vector2(rect.size.x, filled)), Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.8), true)
	_canvas.draw_rect(rect, LINE_COLOR, false, w * 0.75)


# A gauge with its caption above it and, where the surface asks, its number at the far end.
func _captioned_bar(surface: HudSurface, rect: Rect2, fraction: float, color: Color, caption: String, s: float, w: float) -> void:
	_bar(rect, fraction, color, w)
	var size: float = surface.bar_caption_size * s
	_text(caption, rect.position + Vector2(0.0, -6.0 * s), size, color)
	if surface.bar_percent:
		_text("%d%%" % roundi(fraction * 100.0), Vector2(rect.end.x, rect.position.y - 6.0 * s), size, color, HORIZONTAL_ALIGNMENT_RIGHT)


func _bar(rect: Rect2, fraction: float, color: Color, w: float) -> void:
	_canvas.draw_rect(rect, Color(color.r, color.g, color.b, 0.15), true)
	_canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)), Color(color.r, color.g, color.b, 0.8), true)
	_canvas.draw_rect(rect, color, false, w * 0.75)


func _brackets(rect: Rect2, color: Color, w: float, arm: float) -> void:
	var tl: Vector2 = rect.position
	var br: Vector2 = rect.end
	var tr := Vector2(br.x, tl.y)
	var bl := Vector2(tl.x, br.y)
	for corner: Array in [[tl, Vector2(arm, 0.0), Vector2(0.0, arm)], [tr, Vector2(-arm, 0.0), Vector2(0.0, arm)],
			[bl, Vector2(arm, 0.0), Vector2(0.0, -arm)], [br, Vector2(-arm, 0.0), Vector2(0.0, -arm)]]:
		_canvas.draw_line(corner[0], corner[0] + corner[1], color, w)
		_canvas.draw_line(corner[0], corner[0] + corner[2], color, w)


# --- boresight, velocity marker -----------------------------------------------------------------------------


func _draw_boresight(f: HudFrame, s: float, w: float) -> void:
	if not f.boresight_visible:
		return
	var c: Vector2 = f.boresight_pos
	var r: float = 14.0 * s
	var gap: float = 4.0 * s
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_canvas.draw_line(c + d * gap, c + d * r, LINE_COLOR, w)


func _draw_velocity(f: HudFrame, s: float, w: float) -> void:
	if not f.velocity_visible:
		return
	var v: Vector2 = f.velocity_pos
	var r: float = 11.0 * s
	_canvas.draw_arc(v, r, 0.0, TAU, 28, LINE_COLOR, w)
	# Named, so it is clear these show the direction of travel (a fixed direction in space), not a position on the ship.
	_text("RETRO" if f.retrograde else "PRO", v + Vector2(r + 4.0 * s, -r - 2.0 * s), 11.0 * s, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.8))
	if f.retrograde:
		_canvas.draw_line(v + Vector2(-r, -r) * 0.7, v + Vector2(r, r) * 0.7, LINE_COLOR, w)
		_canvas.draw_line(v + Vector2(-r, r) * 0.7, v + Vector2(r, -r) * 0.7, LINE_COLOR, w)
	else:
		_canvas.draw_line(v + Vector2(r, 0.0), v + Vector2(r + 10.0 * s, 0.0), LINE_COLOR, w)
		_canvas.draw_line(v + Vector2(-r, 0.0), v + Vector2(-r - 10.0 * s, 0.0), LINE_COLOR, w)
		_canvas.draw_line(v + Vector2(0.0, -r), v + Vector2(0.0, -r - 8.0 * s), LINE_COLOR, w)


# --- target ---------------------------------------------------------------------------------------------------


func _draw_target_marks(f: HudFrame, s: float, w: float, labelled: bool) -> void:
	if not f.target_present:
		return
	var color: Color = f.target_color
	var label: String = _target_line(f)
	if f.target_on_screen:
		var box: Rect2 = f.target_box
		_brackets(box, color, w, maxf(8.0 * s, box.size.x * 0.28))
		if labelled:
			_text(label, Vector2(box.position.x, box.end.y + 18.0 * s), 15.0 * s, color)
			if f.target_hull >= 0.0:
				_bar(Rect2(Vector2(box.position.x, box.end.y + 24.0 * s), Vector2(maxf(box.size.x, 60.0 * s), 6.0 * s)), f.target_hull, color, w)
	elif f.edge_arrow_visible:
		var p: Vector2 = f.edge_arrow_pos
		var a: float = f.edge_arrow_angle
		var size: float = 16.0 * s
		var tip: Vector2 = p + Vector2.from_angle(a) * size
		var left: Vector2 = p + Vector2.from_angle(a + 2.5) * size * 0.8
		var right: Vector2 = p + Vector2.from_angle(a - 2.5) * size * 0.8
		_canvas.draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(color.r, color.g, color.b, 0.85))
		if labelled:
			_text(label, p + Vector2(0.0, 28.0 * s), 14.0 * s, color, HORIZONTAL_ALIGNMENT_CENTER)
	if f.lead_visible:
		var l: Vector2 = f.lead_pos
		var r: float = 9.0 * s
		_canvas.draw_polyline(PackedVector2Array([l + Vector2(0.0, -r), l + Vector2(r, 0.0), l + Vector2(0.0, r), l + Vector2(-r, 0.0), l + Vector2(0.0, -r)]), color, w)


# The target's readout as a panel, for a screen: name, then range and closing speed, then its hull.
func _draw_target_panel(f: HudFrame, surface: HudSurface, s: float, w: float) -> void:
	var at: Vector2 = surface.target_panel_pos
	if surface.divider_y > 0.0:
		_canvas.draw_line(Vector2(8.0 * s, surface.divider_y), Vector2(surface.size.x - 8.0 * s, surface.divider_y), Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.45), w * 0.5)
	if not f.target_present:
		_text("NO TARGET", at, 18.0 * s, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.5))
		return
	_text(f.target_name, at, 20.0 * s, f.target_color)
	_text("%s  %+.0f m/s" % [_range_text(f.target_range_m), f.target_closing_mps], at + Vector2(0.0, 24.0 * s), 16.0 * s, LINE_COLOR)
	if f.target_hull >= 0.0:
		_bar(surface.target_bar_rect, f.target_hull, f.target_color, w)


static func _target_line(f: HudFrame) -> String:
	return "%s  %s  %+.0f m/s" % [f.target_name, _range_text(f.target_range_m), f.target_closing_mps]


# The route's next waypoint (M3-T09): a plain diamond with `NAV n` and the range, or an edge arrow. T11 draws the final look.
func _draw_waypoint(f: HudFrame, s: float, w: float) -> void:
	if not f.waypoint_present:
		return
	var label: String = "%s  %s" % [f.waypoint_label, _range_text(f.waypoint_range_m)]
	if f.waypoint_on_screen:
		var c: Vector2 = f.waypoint_pos
		var r: float = 12.0 * s
		_canvas.draw_polyline(PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r, 0.0), c + Vector2(0.0, r), c + Vector2(-r, 0.0),
				c + Vector2(0.0, -r)]), LINE_COLOR, w)
		_text(label, c + Vector2(0.0, r + 16.0 * s), 14.0 * s, LINE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	elif f.waypoint_edge_visible:
		var p: Vector2 = f.waypoint_edge_pos
		var a: float = f.waypoint_edge_angle
		var size: float = 14.0 * s
		_canvas.draw_polyline(PackedVector2Array([p + Vector2.from_angle(a + 2.5) * size * 0.8, p + Vector2.from_angle(a) * size,
				p + Vector2.from_angle(a - 2.5) * size * 0.8]), LINE_COLOR, w)
		_text(label, p + Vector2(0.0, 26.0 * s), 13.0 * s, LINE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)


## "H +12.5  V -3.0" (degrees off the nose, horizontal then vertical), or dashes when the ship is not moving.
static func angles_text(f: HudFrame) -> String:
	if not f.velocity_angles_valid:
		return "H ---    V ---"
	return "H %+.1f°   V %+.1f°" % [f.velocity_h_deg, f.velocity_v_deg]


## "REF BABYLON 5  3.20 km  +450 m/s": what the speed is read against (its name explains a jump in the speed when it
## changes), the distance to it and the speed at which it is closing (+) or opening (-).
static func reference_text(f: HudFrame) -> String:
	var named: String = "REF %s  " % f.reference_name if not f.reference_name.is_empty() else "REF "
	return "%s%s  %+.0f m/s" % [named, _range_text(f.reference_range_m), f.reference_closing_mps]


## "ALT 412 km": the height above the body the ship is near (M6-T08), "" when none is near.
static func altitude_text(f: HudFrame) -> String:
	if not f.altitude_valid:
		return ""
	return "ALT %s" % _range_text(f.altitude_m)


static func _range_text(range_m: float) -> String:
	return "%.2f km" % (range_m / 1000.0) if range_m >= 1000.0 else "%.0f m" % range_m


# --- targeting grid ---------------------------------------------------------------------------------------------


func _draw_grid(surface: HudSurface, f: HudFrame, s: float, w: float) -> void:
	if not surface.grid_visible:
		return
	var rect: Rect2 = surface.grid_rect
	var tint: Color = surface.grid_color
	var dim := Color(tint.r, tint.g, tint.b, surface.grid_line_alpha)
	_canvas.draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.05), true)
	# Square cells from the middle out, so a wide rect simply has more of them across.
	var centre: Vector2 = rect.get_center()
	var cell: float = rect.size.y / float(surface.grid_cells)
	var across: int = ceili(rect.size.x * 0.5 / cell - 1e-3)
	var down: int = ceili(rect.size.y * 0.5 / cell - 1e-3)
	for i: int in range(-across, across + 1):
		var x: float = centre.x + cell * float(i)
		if x >= rect.position.x - 1e-3 and x <= rect.end.x + 1e-3:
			_canvas.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), dim, w * 0.5)
	for i: int in range(-down, down + 1):
		var y: float = centre.y + cell * float(i)
		_canvas.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), dim, w * 0.5)
	_canvas.draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.5), false, w * 0.75)
	_canvas.draw_arc(centre, minf(rect.size.x, rect.size.y) * 0.12, 0.0, TAU, 32, LINE_COLOR, w)
	if surface.grid_marker_visible:
		var m: Vector2 = surface.grid_marker
		var color := Color(f.target_color.r, f.target_color.g, f.target_color.b, 1.0 if surface.grid_marker_inside else 0.5)
		if surface.grid_marker_diagonal:
			_canvas.draw_arc(m, 9.0 * s, 0.0, TAU, 20, color, w * 0.75)
			_canvas.draw_line(m + Vector2(-16.0, 16.0) * s, m + Vector2(16.0, -16.0) * s, color, w * 0.75)
		else:
			_canvas.draw_rect(Rect2(m - Vector2(5.0, 5.0) * s, Vector2(10.0, 10.0) * s), color, true)


# --- speed --------------------------------------------------------------------------------------------------------


func _draw_speed(f: HudFrame, surface: HudSurface, s: float) -> void:
	var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT if surface.speed_align_right else HORIZONTAL_ALIGNMENT_CENTER
	var at: Vector2 = surface.speed_pos
	_text("%.0f m/s" % f.speed_mps, at + Vector2(0.0, -22.0 * s), surface.speed_size * s, LINE_COLOR, align)
	_text(angles_text(f), at, 16.0 * s, LINE_COLOR, align)
	if f.reference_valid:
		_text(reference_text(f), at + Vector2(0.0, 20.0 * s), 14.0 * s, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.75), align)
	if f.altitude_valid:
		_text(altitude_text(f), at + Vector2(0.0, 36.0 * s), 14.0 * s, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.75), align)


# --- drift sphere -------------------------------------------------------------------------------------------------


# A small sphere in the ship's frame (nose up the screen, as the radar's) with your ship at the centre and an arrow along the
# direction you are travelling: along the nose when you fly straight, off to the side when you drift, pointing at you (a short
# stalk to the equator tells above from below) when you back up. Always drawn; a dot at the centre while you are at rest.
func _draw_drift_sphere(f: HudFrame, surface: HudSurface, s: float, w: float) -> void:
	var c: Vector2 = surface.drift_centre
	var r: float = surface.drift_radius_px
	if r <= 0.0:
		return
	var dim := Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.55)
	_canvas.draw_circle(c, r, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.06))
	_canvas.draw_arc(c, r, 0.0, TAU, 40, dim, w)
	_ring(c, r, dim, w * 0.9, 0)
	_ring(c, r, dim, w * 0.9, 1)
	_canvas.draw_polyline(PackedVector2Array([c + Vector2(0.0, -6.0 * s), c + Vector2(4.0 * s, 5.0 * s), c + Vector2(-4.0 * s, 5.0 * s), c + Vector2(0.0, -6.0 * s)]), LINE_COLOR, w * 0.75)
	_text("DRIFT", c + Vector2(-r, -r - 4.0 * s), 12.0 * s, LINE_COLOR)
	if f.drift_dir == Vector3.ZERO:
		return
	var tip_point: Vector3 = f.drift_dir * 0.92
	var tip: Vector2 = RadarModel.to_screen(tip_point, c, r)
	var foot: Vector2 = RadarModel.to_screen(Vector3(tip_point.x, tip_point.y, 0.0), c, r)
	_canvas.draw_line(foot, tip, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.45), w * 0.5)
	# The shaft shades from a dim blue-green tail at your ship to a bright amber tip, so the head end is obvious at a glance.
	var tail_color := Color(0.25, 0.55, 0.7, 0.5)
	var tip_color := Color(1.0, 0.85, 0.3, 1.0)
	var segments: int = 8
	for i: int in segments:
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		_canvas.draw_line(c.lerp(tip, t0), c.lerp(tip, t1), tail_color.lerp(tip_color, (t0 + t1) * 0.5), w * (1.2 + 1.6 * t1))
	var along: Vector2 = (tip - c).normalized() if tip.distance_to(c) > 0.5 else Vector2.UP
	var side := Vector2(-along.y, along.x)
	var head: float = 10.0 * s
	_canvas.draw_colored_polygon(PackedVector2Array([tip, tip - along * head + side * head * 0.45, tip - along * head - side * head * 0.45]), tip_color)
	# And in words under the sphere: ahead, astern or across.
	var ahead: float = f.drift_dir.y
	var caption: String = "FWD" if ahead > 0.35 else ("AFT" if ahead < -0.35 else "SIDE")
	var caption_color: Color = tip_color if ahead > 0.35 else (Color(1.0, 0.5, 0.35) if ahead < -0.35 else LINE_COLOR)
	_text(caption, c + Vector2(0.0, r + 14.0 * s), 12.0 * s, caption_color, HORIZONTAL_ALIGNMENT_CENTER)
	# Where you have come from: a small open circle on the far side.
	var back: Vector2 = RadarModel.to_screen(-tip_point * 0.8, c, r)
	_canvas.draw_arc(back, 3.0 * s, 0.0, TAU, 12, dim, w * 0.75)


# --- damage silhouettes -----------------------------------------------------------------------------------------


# A ship's main components in `rect`, coloured by how badly each is hurt (green untouched, then yellow, orange, red), with
# `caption` above: a wireframe whose damaged parts draw heavier, or outlines filled by their damage.
func _draw_silhouette(layout: DamageZones.Layout, zones: PackedFloat32Array, rect: Rect2, caption: String, w: float) -> void:
	if layout == DamageZones.Layout.NONE or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	for entry: Dictionary in Silhouette.wireframe(layout, rect.size.x / rect.size.y):
		var zone: int = entry["zone"]
		var severity: float = float(zones[zone]) if zone < zones.size() else 0.0
		var color: Color = HudLayout.damage_color(severity)
		var segments := PackedVector2Array()
		for p: Vector2 in entry["segments"]:
			segments.append(rect.get_center() + p * rect.size)
		_canvas.draw_multiline(segments, Color(color.r, color.g, color.b, 0.8 if severity <= 0.0 else 1.0),
				w * (0.6 if severity <= 0.0 else 1.1))
	for entry: Dictionary in Silhouette.polygons(layout):
		var zone: int = entry["zone"]
		var severity: float = float(zones[zone]) if zone < zones.size() else 0.0
		var color: Color = HudLayout.damage_color(severity)
		var points := PackedVector2Array()
		for p: Vector2 in entry["points"]:
			points.append(rect.get_center() + p * rect.size)
		_canvas.draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.16 if severity <= 0.0 else 0.6))
		var closed := points.duplicate()
		closed.append(points[0])
		_canvas.draw_polyline(closed, color, w * 0.75)
	if not caption.is_empty():
		_text(caption, rect.position + Vector2(0.0, -4.0), 13.0 * (rect.size.y / 112.0), LINE_COLOR)


# --- radar sphere -----------------------------------------------------------------------------------------------


func _draw_radar(f: HudFrame, surface: HudSurface, s: float, w: float) -> void:
	var c: Vector2 = surface.radar_centre
	var r: float = surface.radar_radius_px
	if r <= 0.0:
		return
	var k: float = r / HudLayout.RADAR_RADIUS_UNITS  # the same radar on every surface, only larger
	var dim := Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.7 if surface.radar_labels else 0.35)
	# The sphere: its outline, the equatorial ring and the forward-up meridian, all in the ship's frame.
	_canvas.draw_arc(c, r, 0.0, TAU, 48, dim, w * 0.75)
	_ring(c, r, dim, w * 0.75, 0)
	_ring(c, r, dim, w * 0.75, 1)
	if surface.radar_labels:
		# Named, with the ring where the scale turns logarithmic.
		_ring(c, r, dim, w * 0.6, 0, RadarModel.LINEAR_RADIUS)
		_text("%d km" % int(RadarModel.MAX_RANGE_M / 1000.0), c + Vector2(r * 0.72, -r * 0.72), 14.0 * s, LINE_COLOR)
		_text("%d km" % int(RadarModel.LINEAR_RANGE_M / 1000.0), RadarModel.to_screen(Vector3(RadarModel.LINEAR_RADIUS, 0.0, 0.0), c, r) + Vector2(4.0, -3.0) * s, 14.0 * s, LINE_COLOR)
	# The contacts in a few batched draws (M4-T36): every stalk in one call, every plain dot in one multimesh, every hollow rim
	# dot in another (M4-T23), then the selection.
	var plot: RadarPlot = f.radar_plot
	var to_screen: Transform2D = RadarPlot.screen_transform(c, r)
	var dots: RadarDotBuffers = RadarModel.dot_buffers(plot, c, r, 5.5 * k, 3.0 * k, TEXT_SHADOW, surface.radar_labels,
			PackedInt32Array([_instances(_dots), _instances(_rims), _instances(_backings)]))
	if surface.radar_labels:  # dark backings under everything, so contacts read over the octagon's grid and never hide each other
		_backings = _submit_dots(_backings, dots.backing, dots.backing_count, _dot_unit_mesh())
	# Own ship at the centre, nose up.
	_canvas.draw_polyline(PackedVector2Array([c + Vector2(0.0, -6.0 * k), c + Vector2(4.0 * k, 5.0 * k), c + Vector2(-4.0 * k, 5.0 * k), c + Vector2(0.0, -6.0 * k)]), LINE_COLOR, w * 0.75)
	if plot.size() == 0:
		return
	_canvas.draw_multiline_colors(to_screen * plot.stalk_units, plot.stalk_colors, w * 0.5)
	_dots = _submit_dots(_dots, dots.plain, dots.plain_count, _dot_unit_mesh())
	# A broadcast beyond the sensors is hollow, on the rim (M3-T17): every one but the selection in one ring multimesh.
	_rims = _submit_dots(_rims, dots.rim, dots.rim_count, _ring_unit_mesh((w * 0.6) / (3.0 * k)))
	var i: int = plot.selected_index
	if i >= 0:
		var at_selected: Vector2 = to_screen * plot.point_units[i]
		if plot.rims[i] == 1:
			_canvas.draw_arc(at_selected, 4.5 * k, 0.0, TAU, 12, plot.colors[i], w * 0.6)
		else:
			_canvas.draw_circle(at_selected, 4.5 * k, plot.colors[i])
		_canvas.draw_arc(at_selected, 8.0 * k, 0.0, TAU, 20, plot.colors[i], w * 0.75)
	# The waypoint's contact (M5-T25): a diamond in the HUD's own colour, as its marker in the view.
	var wp: int = f.waypoint_radar_index
	if wp >= 0 and wp < plot.point_units.size():
		var at_waypoint: Vector2 = to_screen * plot.point_units[wp]
		var d: float = 9.0 * k
		_canvas.draw_polyline(PackedVector2Array([at_waypoint + Vector2(0.0, -d), at_waypoint + Vector2(d, 0.0), at_waypoint + Vector2(0.0, d),
				at_waypoint + Vector2(-d, 0.0), at_waypoint + Vector2(0.0, -d)]), LINE_COLOR, w * 0.75)


# A multimesh's instance count, 0 before it is made.
static func _instances(dots: MultiMesh) -> int:
	return dots.instance_count if dots != null else 0


# Draws the first `count` dots of `buffer` with `mesh` in one multimesh. The buffer comes sized for the multimesh
# (`RadarModel.dot_buffers`), so it goes to the server whole. Returns the multimesh, made on first use (one per kind, as one
# draw keeps its buffer).
func _submit_dots(dots: MultiMesh, buffer: PackedFloat32Array, count: int, mesh: Mesh) -> MultiMesh:
	if dots == null:
		dots = MultiMesh.new()
		dots.transform_format = MultiMesh.TRANSFORM_2D
		dots.use_colors = true
	if dots.mesh != mesh:
		dots.mesh = mesh
	if count == 0:
		dots.visible_instance_count = 0
		return dots
	var capacity: int = RadarDotBuffers.instances(buffer)
	if dots.instance_count != capacity:
		dots.instance_count = capacity  # grows rarely, never shrinks
	RenderingServer.multimesh_set_buffer(dots.get_rid(), buffer)
	dots.visible_instance_count = count
	_canvas.draw_multimesh(dots, null)
	return dots


# A filled unit circle, the radar's dot.
static func _dot_unit_mesh() -> ArrayMesh:
	if _dot_mesh != null:
		return _dot_mesh
	var vertices := PackedVector2Array([Vector2.ZERO])
	var indices := PackedInt32Array()
	for i: int in DOT_SEGMENTS:
		var a: float = TAU * float(i) / float(DOT_SEGMENTS)
		vertices.append(Vector2(cos(a), sin(a)))
		indices.append_array(PackedInt32Array([0, 1 + i, 1 + (i + 1) % DOT_SEGMENTS]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	_dot_mesh = ArrayMesh.new()
	_dot_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _dot_mesh


# A unit ring of `thickness` (over its radius), centred on the radius: a hollow rim dot (M4-T23). Kept per thickness.
static func _ring_unit_mesh(thickness: float) -> ArrayMesh:
	var key: int = roundi(thickness * 1000.0)
	if _ring_meshes.has(key):
		return _ring_meshes[key]
	var inner: float = maxf(1.0 - thickness * 0.5, 0.0)
	var outer: float = 1.0 + thickness * 0.5
	var vertices := PackedVector2Array()
	var indices := PackedInt32Array()
	for i: int in DOT_SEGMENTS:
		var a: float = TAU * float(i) / float(DOT_SEGMENTS)
		vertices.append(Vector2(cos(a), sin(a)) * inner)
		vertices.append(Vector2(cos(a), sin(a)) * outer)
		var j: int = (i + 1) % DOT_SEGMENTS
		indices.append_array(PackedInt32Array([2 * i, 2 * i + 1, 2 * j + 1, 2 * i, 2 * j + 1, 2 * j]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ring_meshes[key] = mesh
	return mesh


# A ring of the radar sphere at `reach` of its radius: 0 = the equatorial plane (X/Y), 1 = the vertical plane through the nose (Y/Z).
func _ring(c: Vector2, r: float, color: Color, w: float, kind: int, reach: float = 1.0) -> void:
	var points := PackedVector2Array()
	for i: int in range(49):
		var a: float = TAU * float(i) / 48.0
		var p: Vector3 = Vector3(cos(a), sin(a), 0.0) if kind == 0 else Vector3(0.0, cos(a), sin(a))
		points.append(RadarModel.to_screen(p * reach, c, r))
	_canvas.draw_polyline(points, color, w)
