extends GutTest
## Nothing on the HUD is drawn over anything else at its larger text (M8-T21: one size up): every text the painter draws, as
## it draws it, against every other text and every gauge on the same surface; the chase view's window and the cockpit's three
## screens, at 1080p and at the 960 by 540 test size, with the longest things each place shows.

const VIEWS: Array[Vector2] = [Vector2(1920.0, 1080.0), Vector2(960.0, 540.0)]
const SCREENS: Dictionary = {&"octagon": Vector2(560.0, 430.0), &"left": Vector2(500.0, 360.0), &"right": Vector2(500.0, 360.0)}
const ROSTER_TAGS: Array[String] = ["attack", "docking", "holding", "retreat"]


## A control that paints one surface and keeps what the painter drew.
class Canvas extends Control:
	var painter: HudPainter = null
	var frame: HudFrame = null
	var surface: HudSurface = null

	func _init() -> void:
		painter = HudPainter.new(self)
		painter.record_text = true

	func _draw() -> void:
		if frame != null:
			painter.paint(frame, surface)


func _hud_input(view: Vector2, cockpit: bool) -> HudInput:
	var input := HudInput.new()
	input.viewport_size = view
	input.projection = Projection.create_perspective(75.0, view.x / view.y, 0.05, 100000.0)
	input.cockpit = cockpit
	input.screen_sizes = SCREENS if cockpit else {}
	input.has_reference = true
	input.reference_name = "BABYLON 5 DOCKING BAY"
	input.reference_position = Vector3(0.0, 0.0, -412345.0)
	input.own_velocity = Vector3(120.0, -40.0, -13400.0)
	input.altitude_m = 412345.0
	input.altitude_body = "EPSILON III"
	input.damage_layout = DamageZones.Layout.X_FIGHTER
	input.damage_zones = PackedFloat32Array([0.0, 0.5, 0.0, 0.0, 1.0])
	input.fuel_unlimited = false
	input.fuel_fraction = 0.6
	input.fire_mode = "alternating"
	input.running_lights = false
	input.tracking = true
	input.status_line = "WAVE 12  TARGET PRACTICE  RAIDERS 14"
	input.ack_line = "WILCO, ATTACKING RAIDER 12"
	for i: int in ROSTER_TAGS.size():
		input.roster.append({"callsign": "ALPHA %d" % (i + 2), "hull": 0.8, "behaviour": ROSTER_TAGS[i], "target": "RAIDER STRIKE CARRIER 12"})
	input.objectives = [{"id": &"a", "text": "Escort the transport to the jumpgate", "primary": true, "state": &"active"},
			{"id": &"b", "text": "Bring every wingman home", "primary": false, "state": &"active"}]
	input.escorts = [{"name": "Mercy of Ceres", "hull": 0.42}, {"name": "Saturn 8 tanker", "hull": 1.0}]
	return input


func _target() -> TargetReadout:
	var target := TargetReadout.new()
	target.position = Vector3(30.0, -20.0, -3000.0)
	target.display_name = "RAIDER STRIKE CARRIER 12"
	target.range_m = 12345.0
	target.closing_mps = -1234.0
	target.hull_fraction = 0.5
	target.faction = Factions.RAIDERS
	target.damage_layout = DamageZones.Layout.DELTA
	target.damage_zones = PackedFloat32Array([0.0, 1.0, 0.0])
	return target


# What the painter drew on `surface`: every text's box, after one real paint.
func _painted(frame: HudFrame, surface: HudSurface) -> Array[Dictionary]:
	var canvas := Canvas.new()
	canvas.frame = frame
	canvas.surface = surface
	canvas.size = surface.size
	add_child_autofree(canvas)
	canvas.queue_redraw()
	await wait_process_frames(2)
	return canvas.painter.text_boxes


# The surface's gauges, by name.
func _gauges(surface: HudSurface) -> Dictionary:
	var out: Dictionary = {}
	var items: Array[StringName] = surface.items
	if items.has(HudSurface.HULL_BAR):
		out["hull bar"] = surface.hull_rect
	if items.has(HudSurface.FUEL_BAR):
		out["fuel bar"] = surface.fuel_rect
	if items.has(HudSurface.CHARGE_BAR):
		out["charge bar"] = surface.charge_rect
	if items.has(HudSurface.OWN_SILHOUETTE):
		out["own silhouette"] = surface.own_silhouette_rect
	if items.has(HudSurface.TARGET_SILHOUETTE) and surface.target_silhouette_rect.size != Vector2.ZERO:
		out["target silhouette"] = surface.target_silhouette_rect
	if items.has(HudSurface.TARGET_PANEL):
		out["target bar"] = surface.target_bar_rect
	if items.has(HudSurface.ROSTER):
		for i: int in surface.roster_rows.size():
			out["roster bar %d" % i] = surface.roster_rows[i].bar_rect
	return out


# Every pair of things drawn over each other on one surface, as "a | b".
func _clashes(boxes: Array[Dictionary], gauges: Dictionary, surface: HudSurface) -> PackedStringArray:
	var found := PackedStringArray()
	var whole := Rect2(Vector2.ZERO, surface.size)
	for i: int in boxes.size():
		var a: Rect2 = (boxes[i]["rect"] as Rect2).grow(-0.5)
		if not whole.encloses(a):
			found.append("%s | off the surface" % boxes[i]["text"])
		for j: int in range(i + 1, boxes.size()):
			if a.intersects((boxes[j]["rect"] as Rect2).grow(-0.5)):
				found.append("%s | %s" % [boxes[i]["text"], boxes[j]["text"]])
		for name: String in gauges:
			if a.intersects((gauges[name] as Rect2).grow(-0.5)):
				found.append("%s | %s" % [boxes[i]["text"], name])
	return found


func test_the_chase_views_window_draws_nothing_over_anything() -> void:
	for view: Vector2 in VIEWS:
		var frame: HudFrame = HudLayout.compute(_hud_input(view, false))
		var boxes: Array[Dictionary] = await _painted(frame, frame)
		assert_gt(boxes.size(), 20, "the whole HUD was drawn at %s" % view)
		assert_eq(_clashes(boxes, _gauges(frame), frame), PackedStringArray(), "chase view at %s" % view)


func test_the_cockpits_screens_draw_nothing_over_anything() -> void:
	for view: Vector2 in VIEWS:
		for with_target: bool in [false, true]:
			var input: HudInput = _hud_input(view, true)
			if with_target:
				input.target = _target()
				input.selected_id = 7
			var frame: HudFrame = HudLayout.compute(input)
			for id: StringName in [&"left", &"right", &"octagon"]:
				var surface: HudSurface = frame.screens[id]
				var boxes: Array[Dictionary] = await _painted(frame, surface)
				assert_gt(boxes.size(), 1, "%s was drawn" % id)
				assert_eq(_clashes(boxes, _gauges(surface), surface), PackedStringArray(),
						"the %s screen at %s%s" % [id, view, ", with a target" if with_target else ""])


func test_the_cockpits_window_keeps_its_lines_apart() -> void:
	for view: Vector2 in VIEWS:
		var frame: HudFrame = HudLayout.compute(_hud_input(view, true))
		var boxes: Array[Dictionary] = await _painted(frame, frame)
		assert_eq(_clashes(boxes, {}, frame), PackedStringArray(), "the window in the cockpit at %s" % view)


func test_a_long_roster_tag_stops_short_of_the_charge_bar() -> void:
	var frame: HudFrame = HudLayout.compute(_hud_input(VIEWS[0], true))
	var surface: HudSurface = frame.screens[&"right"]
	var boxes: Array[Dictionary] = await _painted(frame, surface)
	var rows: int = 0
	for box: Dictionary in boxes:
		if String(box["text"]).begins_with("ALPHA"):
			rows += 1
			assert_lte((box["rect"] as Rect2).end.x, surface.charge_rect.position.x, "%s ends before the bar" % box["text"])
	assert_eq(rows, ROSTER_TAGS.size())
