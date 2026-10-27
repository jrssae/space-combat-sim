class_name Hud
extends CanvasLayer
## The combat HUD (architecture §15.9, D26): a green-line display drawn from the `HudFrame` that the pure `HudLayout` computes
## every frame. Layer 40, below the debug overlay (50). This node only draws: `Main` sets `input_provider`, a Callable
## returning this frame's `HudInput`; `settings.show_hud` shows or hides it. Console provider `hud`.
##
## Elements: boresight cross, (optionally, `settings.hud_velocity_marker`) a prograde circle with wings or retrograde circle with a cross, the drift sphere by the speed readout, target box (corner brackets) with
## name, range, closing speed and a hull bar, an edge arrow for an off-screen target, the lead diamond, a status line top
## centre; bottom edge: speed (centre) with the direction of travel against the nose (horizontal then vertical degrees) and the
## range and closing speed to the reference point, hull bar (left) with the ship's damage silhouette above it, a fuel bar
## (only when the tank is finite), weapon charge and fire mode (right), the radar sphere above the speed readout and the target's
## damage silhouette beside it; in the cockpit view (or by `settings.hud_targeting_grid`) a translucent grid with a reticle low and
## centred, and the target's offset from the nose on it.

const LINE_COLOR: Color = Factions.HUD_LINE_COLOR
const DIM_ALPHA: float = 0.45

## A Callable returning a `HudInput`; unset = nothing drawn.
var input_provider: Callable = Callable()
## The frame drawn last (for tests and the console).
var frame: HudFrame = HudFrame.new()

var _canvas: HudCanvas = null


func _ready() -> void:
	layer = 40
	_canvas = HudCanvas.new()
	_canvas.name = "HudCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.hud = self
	add_child(_canvas)
	visible = bool(Settings.get_value(&"show_hud"))
	Settings.changed.connect(_on_setting_changed)
	DebugConsole.registry.register_provider(&"hud", ConsoleVars.new({
		&"visible": {"get": func() -> bool: return visible, "doc": "The HUD is shown (settings.show_hud)"},
		&"lead_tof_s": {"get": func() -> Variant: return frame.lead_tof_s if frame.lead_visible else null, "unit": "s",
				"doc": "Time of flight to the lead point, while the lead reticle shows"},
		&"lead_on_screen": {"get": func() -> bool: return frame.lead_visible, "doc": "The lead reticle is on screen"},
		&"prograde_on_screen": {"get": func() -> bool: return frame.velocity_visible and not frame.retrograde,
				"doc": "The prograde marker is on screen"},
		&"target_box": {"get": func() -> Variant: return frame.target_box if frame.target_on_screen else null,
				"doc": "Screen rectangle of the target box, while the target is on screen"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _process(_delta: float) -> void:
	if not visible or not input_provider.is_valid():
		return
	var input: HudInput = input_provider.call() as HudInput
	if input == null or input.viewport_size.x < 1.0 or input.viewport_size.y < 1.0:
		return
	frame = HudLayout.compute(input)
	# The chase view is busier (the whole ship is on screen): the HUD is drawn fainter there.
	_canvas.modulate.a = 1.0 if frame.cockpit else float(Settings.get_value(&"hud_chase_opacity"))
	_canvas.queue_redraw()


## Draws `f` now (tests set a frame directly).
func show_frame(f: HudFrame) -> void:
	frame = f
	if _canvas != null:
		_canvas.queue_redraw()


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"show_hud":
		visible = bool(value)


## The control that does the drawing; it reads the HUD's last frame.
class HudCanvas extends Control:
	var hud: Hud = null
	var _font: Font = null

	func _ready() -> void:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "Monospace"])
		_font = system

	func _draw() -> void:
		if hud == null:
			return
		var f: HudFrame = hud.frame
		var s: float = f.scale
		var w: float = maxf(1.0, 2.0 * s)  # 2 px lines at 1080p
		_draw_markers(f, s, w)
		_draw_target(f, s, w)
		_draw_waypoint(f, s, w)
		_draw_grid(f, s, w)
		_draw_gauges(f, s, w)
		_draw_radar(f, s, w)
		_draw_drift_sphere(f, s, w)
		_draw_silhouette(f.own_layout, f.own_zones, f.own_silhouette_rect, "YOU", w)
		_draw_silhouette(f.target_layout, f.target_zones, f.target_silhouette_rect, f.target_name, w)
		if f.tracking:
			_text("AUTO-TRACK", Vector2(f.viewport_size.x * 0.5, 62.0 * s), 16.0 * s, HudLayout.AMBER, HORIZONTAL_ALIGNMENT_CENTER)
		if not f.status_line.is_empty():
			_text(f.status_line, Vector2(f.viewport_size.x * 0.5, 36.0 * s), 18.0 * s, LINE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)

	# --- helpers --------------------------------------------------------------------------------------------------

	func _text(text: String, pos: Vector2, size: float, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		var shadow := Color(0.0, 0.0, 0.0, 0.8)
		var width: float = _font.get_string_size(text, align, -1.0, int(size)).x
		var origin: Vector2 = pos
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			origin.x -= width * 0.5
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			origin.x -= width
		draw_string(_font, origin + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(size), shadow)
		draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(size), color)

	func _bar(rect: Rect2, fraction: float, color: Color, w: float) -> void:
		draw_rect(rect, Color(color.r, color.g, color.b, 0.15), true)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)), Color(color.r, color.g, color.b, 0.8), true)
		draw_rect(rect, color, false, w * 0.75)

	func _brackets(rect: Rect2, color: Color, w: float, arm: float) -> void:
		var tl: Vector2 = rect.position
		var br: Vector2 = rect.end
		var tr := Vector2(br.x, tl.y)
		var bl := Vector2(tl.x, br.y)
		for corner: Array in [[tl, Vector2(arm, 0.0), Vector2(0.0, arm)], [tr, Vector2(-arm, 0.0), Vector2(0.0, arm)],
				[bl, Vector2(arm, 0.0), Vector2(0.0, -arm)], [br, Vector2(-arm, 0.0), Vector2(0.0, -arm)]]:
			draw_line(corner[0], corner[0] + corner[1], color, w)
			draw_line(corner[0], corner[0] + corner[2], color, w)

	# --- boresight, velocity marker -----------------------------------------------------------------------------

	func _draw_markers(f: HudFrame, s: float, w: float) -> void:
		if f.boresight_visible:
			var c: Vector2 = f.boresight_pos
			var r: float = 14.0 * s
			var gap: float = 4.0 * s
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				draw_line(c + d * gap, c + d * r, LINE_COLOR, w)
		if f.velocity_visible:
			var v: Vector2 = f.velocity_pos
			var r: float = 11.0 * s
			draw_arc(v, r, 0.0, TAU, 28, LINE_COLOR, w)
			# Named, so it is clear these show the direction of travel (a fixed direction in space), not a position on the ship.
			_text("RETRO" if f.retrograde else "PRO", v + Vector2(r + 4.0 * s, -r - 2.0 * s), 11.0 * s, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.8))
			if f.retrograde:
				draw_line(v + Vector2(-r, -r) * 0.7, v + Vector2(r, r) * 0.7, LINE_COLOR, w)
				draw_line(v + Vector2(-r, r) * 0.7, v + Vector2(r, -r) * 0.7, LINE_COLOR, w)
			else:
				draw_line(v + Vector2(r, 0.0), v + Vector2(r + 10.0 * s, 0.0), LINE_COLOR, w)
				draw_line(v + Vector2(-r, 0.0), v + Vector2(-r - 10.0 * s, 0.0), LINE_COLOR, w)
				draw_line(v + Vector2(0.0, -r), v + Vector2(0.0, -r - 8.0 * s), LINE_COLOR, w)

	# --- target ---------------------------------------------------------------------------------------------------

	func _draw_target(f: HudFrame, s: float, w: float) -> void:
		if not f.target_present:
			return
		var color: Color = f.target_color
		var label: String = "%s  %s  %+.0f m/s" % [f.target_name, _range_text(f.target_range_m), f.target_closing_mps]
		if f.target_on_screen:
			var box: Rect2 = f.target_box
			_brackets(box, color, w, maxf(8.0 * s, box.size.x * 0.28))
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
			draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(color.r, color.g, color.b, 0.85))
			_text(label, p + Vector2(0.0, 28.0 * s), 14.0 * s, color, HORIZONTAL_ALIGNMENT_CENTER)
		if f.lead_visible:
			var l: Vector2 = f.lead_pos
			var r: float = 9.0 * s
			draw_polyline(PackedVector2Array([l + Vector2(0.0, -r), l + Vector2(r, 0.0), l + Vector2(0.0, r), l + Vector2(-r, 0.0), l + Vector2(0.0, -r)]), color, w)

	# The route's next waypoint (M3-T09): a plain diamond with `NAV n` and the range, or an edge arrow. T11 draws the final look.
	func _draw_waypoint(f: HudFrame, s: float, w: float) -> void:
		if not f.waypoint_present:
			return
		var label: String = "%s  %s" % [f.waypoint_label, _range_text(f.waypoint_range_m)]
		if f.waypoint_on_screen:
			var c: Vector2 = f.waypoint_pos
			var r: float = 12.0 * s
			draw_polyline(PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r, 0.0), c + Vector2(0.0, r), c + Vector2(-r, 0.0),
					c + Vector2(0.0, -r)]), LINE_COLOR, w)
			_text(label, c + Vector2(0.0, r + 16.0 * s), 14.0 * s, LINE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
		elif f.waypoint_edge_visible:
			var p: Vector2 = f.waypoint_edge_pos
			var a: float = f.waypoint_edge_angle
			var size: float = 14.0 * s
			draw_polyline(PackedVector2Array([p + Vector2.from_angle(a + 2.5) * size * 0.8, p + Vector2.from_angle(a) * size,
					p + Vector2.from_angle(a - 2.5) * size * 0.8]), LINE_COLOR, w)
			_text(label, p + Vector2(0.0, 26.0 * s), 13.0 * s, LINE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)

	## "H +12.5  V -3.0" (degrees off the nose, horizontal then vertical), or dashes when the ship is not moving.
	static func angles_text(f: HudFrame) -> String:
		if not f.velocity_angles_valid:
			return "H ---    V ---"
		return "H %+.1f°   V %+.1f°" % [f.velocity_h_deg, f.velocity_v_deg]

	## "REF 3.2 km  +450 m/s": distance to the reference point and the speed at which it is closing (+) or opening (-).
	static func reference_text(f: HudFrame) -> String:
		return "REF %s  %+.0f m/s" % [_range_text(f.reference_range_m), f.reference_closing_mps]

	static func _range_text(range_m: float) -> String:
		return "%.2f km" % (range_m / 1000.0) if range_m >= 1000.0 else "%.0f m" % range_m

	# --- targeting grid ---------------------------------------------------------------------------------------------

	func _draw_grid(f: HudFrame, s: float, w: float) -> void:
		if not f.grid_visible:
			return
		var rect: Rect2 = f.grid_rect
		var dim := Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.22)
		draw_rect(rect, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.05), true)
		for i: int in range(f.grid_cells + 1):
			var t: float = float(i) / float(f.grid_cells)
			draw_line(rect.position + Vector2(rect.size.x * t, 0.0), rect.position + Vector2(rect.size.x * t, rect.size.y), dim, w * 0.5)
			draw_line(rect.position + Vector2(0.0, rect.size.y * t), rect.position + Vector2(rect.size.x, rect.size.y * t), dim, w * 0.5)
		draw_rect(rect, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.5), false, w * 0.75)
		draw_arc(rect.get_center(), rect.size.x * 0.12, 0.0, TAU, 32, LINE_COLOR, w)
		if f.grid_marker_visible:
			var m: Vector2 = f.grid_marker
			var color: Color = f.target_color if f.grid_marker_inside else Color(f.target_color.r, f.target_color.g, f.target_color.b, 0.5)
			draw_rect(Rect2(m - Vector2(5.0, 5.0) * s, Vector2(10.0, 10.0) * s), color, true)

	# --- gauges -------------------------------------------------------------------------------------------------------

	func _draw_gauges(f: HudFrame, s: float, w: float) -> void:
		var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT if f.speed_align_right else HORIZONTAL_ALIGNMENT_CENTER
		_text("%.0f m/s" % f.speed_mps, f.speed_pos + Vector2(0.0, -22.0 * s), 22.0 * s, LINE_COLOR, align)
		_text(angles_text(f), f.speed_pos + Vector2(0.0, 0.0), 16.0 * s, LINE_COLOR, align)
		if f.reference_valid:
			_text(reference_text(f), f.speed_pos + Vector2(0.0, 20.0 * s), 14.0 * s, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.75), align)
		_bar(f.hull_rect, f.hull_fraction, f.hull_color, w)
		_text("HULL" + ("  GOD" if f.god else ""), f.hull_rect.position + Vector2(0.0, -6.0 * s), 14.0 * s, f.hull_color)
		if not f.fuel_unlimited:
			_bar(f.fuel_rect, f.fuel_fraction, LINE_COLOR, w)
			_text("FUEL", f.fuel_rect.position + Vector2(0.0, -6.0 * s), 14.0 * s, LINE_COLOR)
		_bar(f.charge_rect, f.charge_fraction, LINE_COLOR, w)
		_text("CHARGE  %s" % f.fire_mode.to_upper(), f.charge_rect.position + Vector2(0.0, -6.0 * s), 14.0 * s, LINE_COLOR)

	# --- drift sphere -------------------------------------------------------------------------------------------------

	# A small sphere in the ship's frame (nose up the screen, as the radar's) with your ship at the centre and an arrow along the
	# direction you are travelling: along the nose when you fly straight, off to the side when you drift, pointing at you (a short
	# stalk to the equator tells above from below) when you back up. Always drawn; a dot at the centre while you are at rest.
	func _draw_drift_sphere(f: HudFrame, s: float, w: float) -> void:
		var c: Vector2 = f.drift_centre
		var r: float = f.drift_radius_px
		if r <= 0.0:
			return
		var dim := Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.55)
		draw_circle(c, r, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.06))
		draw_arc(c, r, 0.0, TAU, 40, dim, w)
		_ring(c, r, dim, w * 0.9, 0)
		_ring(c, r, dim, w * 0.9, 1)
		draw_polyline(PackedVector2Array([c + Vector2(0.0, -6.0 * s), c + Vector2(4.0 * s, 5.0 * s), c + Vector2(-4.0 * s, 5.0 * s), c + Vector2(0.0, -6.0 * s)]), LINE_COLOR, w * 0.75)
		_text("DRIFT", c + Vector2(-r, -r - 4.0 * s), 12.0 * s, LINE_COLOR)
		if f.drift_dir == Vector3.ZERO:
			return
		var tip_point: Vector3 = f.drift_dir * 0.92
		var tip: Vector2 = RadarModel.to_screen(tip_point, c, r)
		var foot: Vector2 = RadarModel.to_screen(Vector3(tip_point.x, tip_point.y, 0.0), c, r)
		draw_line(foot, tip, Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.45), w * 0.5)
		# The shaft shades from a dim blue-green tail at your ship to a bright amber tip, so the head end is obvious at a glance.
		var tail_color := Color(0.25, 0.55, 0.7, 0.5)
		var tip_color := Color(1.0, 0.85, 0.3, 1.0)
		var segments: int = 8
		for i: int in segments:
			var t0: float = float(i) / float(segments)
			var t1: float = float(i + 1) / float(segments)
			draw_line(c.lerp(tip, t0), c.lerp(tip, t1), tail_color.lerp(tip_color, (t0 + t1) * 0.5), w * (1.2 + 1.6 * t1))
		var along: Vector2 = (tip - c).normalized() if tip.distance_to(c) > 0.5 else Vector2.UP
		var side := Vector2(-along.y, along.x)
		var head: float = 10.0 * s
		draw_colored_polygon(PackedVector2Array([tip, tip - along * head + side * head * 0.45, tip - along * head - side * head * 0.45]), tip_color)
		# And in words under the sphere: ahead, astern or across.
		var ahead: float = f.drift_dir.y
		var caption: String = "FWD" if ahead > 0.35 else ("AFT" if ahead < -0.35 else "SIDE")
		var caption_color: Color = tip_color if ahead > 0.35 else (Color(1.0, 0.5, 0.35) if ahead < -0.35 else LINE_COLOR)
		_text(caption, c + Vector2(0.0, r + 14.0 * s), 12.0 * s, caption_color, HORIZONTAL_ALIGNMENT_CENTER)
		# Where you have come from: a small open circle on the far side.
		var back: Vector2 = RadarModel.to_screen(-tip_point * 0.8, c, r)
		draw_arc(back, 3.0 * s, 0.0, TAU, 12, dim, w * 0.75)

	# --- damage silhouettes -----------------------------------------------------------------------------------------

	# The outline of a ship's main components in `rect`, each filled by how badly it is hurt (green untouched, then yellow,
	# orange, red), with `caption` above.
	func _draw_silhouette(layout: DamageZones.Layout, zones: PackedFloat32Array, rect: Rect2, caption: String, w: float) -> void:
		if layout == DamageZones.Layout.NONE or rect.size.x <= 0.0:
			return
		for entry: Dictionary in Silhouette.polygons(layout):
			var zone: int = entry["zone"]
			var severity: float = float(zones[zone]) if zone < zones.size() else 0.0
			var color: Color = HudLayout.damage_color(severity)
			var points := PackedVector2Array()
			for p: Vector2 in entry["points"]:
				points.append(rect.get_center() + p * rect.size)
			draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.16 if severity <= 0.0 else 0.6))
			var closed := points.duplicate()
			closed.append(points[0])
			draw_polyline(closed, color, w * 0.75)
		_text(caption, rect.position + Vector2(0.0, -4.0), 13.0 * (rect.size.y / 112.0), LINE_COLOR)

	# --- radar sphere -----------------------------------------------------------------------------------------------

	func _draw_radar(f: HudFrame, s: float, w: float) -> void:
		var c: Vector2 = f.radar_centre
		var r: float = f.radar_radius_px
		if r <= 0.0:
			return
		var dim := Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, 0.35)
		# The sphere: its outline, the equatorial ring and the forward-up meridian, all in the ship's frame.
		draw_arc(c, r, 0.0, TAU, 48, dim, w * 0.75)
		_ring(c, r, dim, w * 0.75, 0)
		_ring(c, r, dim, w * 0.75, 1)
		# Own ship at the centre, nose up.
		draw_polyline(PackedVector2Array([c + Vector2(0.0, -6.0 * s), c + Vector2(4.0 * s, 5.0 * s), c + Vector2(-4.0 * s, 5.0 * s), c + Vector2(0.0, -6.0 * s)]), LINE_COLOR, w * 0.75)
		for dot: RadarModel.Dot in f.radar_dots:
			var at: Vector2 = RadarModel.to_screen(dot.point, c, r)
			var foot: Vector2 = RadarModel.to_screen(dot.foot, c, r)
			draw_line(foot, at, Color(dot.color.r, dot.color.g, dot.color.b, 0.5), w * 0.5)
			draw_circle(at, (4.5 if dot.selected else 3.0) * s, dot.color)
			if dot.selected:
				draw_arc(at, 8.0 * s, 0.0, TAU, 20, dot.color, w * 0.75)

	# A ring of the radar sphere: 0 = the equatorial plane (X/Y), 1 = the vertical plane through the nose (Y/Z).
	func _ring(c: Vector2, r: float, color: Color, w: float, kind: int) -> void:
		var points := PackedVector2Array()
		for i: int in range(49):
			var a: float = TAU * float(i) / 48.0
			var p: Vector3 = Vector3(cos(a), sin(a), 0.0) if kind == 0 else Vector3(0.0, cos(a), sin(a))
			points.append(RadarModel.to_screen(p, c, r))
		draw_polyline(points, color, w)
