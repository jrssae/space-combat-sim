extends GutTest
## The HUD's split for the cockpit's console screens (M3-T29, AC40), pure: what the window keeps, what each screen is given and where it goes.

const VIEW: Vector2 = Vector2(1920.0, 1080.0)
const SIZES: Dictionary = {&"octagon": Vector2(560.0, 430.0), &"left": Vector2(500.0, 360.0), &"right": Vector2(500.0, 360.0)}
const WINDOW_ITEMS: Array[StringName] = [HudSurface.BORESIGHT, HudSurface.VELOCITY, HudSurface.TARGET_MARKS, HudSurface.WAYPOINT]


func _hud(cockpit: bool = true, sizes: Dictionary = SIZES) -> HudInput:
	var input := HudInput.new()
	input.viewport_size = VIEW
	input.projection = Projection.create_perspective(75.0, VIEW.x / VIEW.y, 0.05, 50000.0)
	input.cockpit = cockpit
	input.screen_sizes = sizes
	input.damage_layout = DamageZones.Layout.X_FIGHTER
	input.damage_zones = PackedFloat32Array([0.0, 0.5, 0.0, 0.0, 1.0])
	return input


func _target() -> TargetReadout:
	var target := TargetReadout.new()
	target.position = Vector3(30.0, -20.0, -300.0)
	target.display_name = "RAIDER 3"
	target.range_m = 301.0
	target.closing_mps = 12.0
	target.hull_fraction = 0.5
	target.faction = Factions.RAIDERS
	target.damage_layout = DamageZones.Layout.DELTA
	target.damage_zones = PackedFloat32Array([0.0, 1.0, 0.0])
	return target


func _roster() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append({"callsign": "ALPHA 2", "hull": 0.8, "behaviour": "formation"})
	rows.append({"callsign": "ALPHA 3", "hull": 0.0, "behaviour": "attack", "down": true})
	return rows


# --- what goes where -------------------------------------------------------------------------------------------------


func test_without_screens_the_cockpit_keeps_the_whole_hud_on_the_window() -> void:
	var f: HudFrame = HudLayout.compute(_hud(true, {}))
	assert_true(f.screens.is_empty())
	assert_eq(f.items, HudSurface.ALL_ITEMS, "a ship without screens loses no instrument")
	assert_true(f.grid_visible)


func test_in_the_cockpit_the_window_keeps_only_the_aiming_marks() -> void:
	var f: HudFrame = HudLayout.compute(_hud())
	assert_eq(f.items, WINDOW_ITEMS)
	assert_does_not_have(f.items, HudSurface.HULL_BAR, "the bars left the window for the left screen")
	assert_does_not_have(f.items, HudSurface.CHARGE_BAR)
	assert_false(f.grid_visible, "the floating grid leaves for the octagon")


func test_hull_is_on_the_left_screen_and_charge_on_the_right_and_nowhere_else() -> void:
	var f: HudFrame = HudLayout.compute(_hud())
	for id: StringName in f.screens:
		var items: Array[StringName] = (f.screens[id] as HudSurface).items
		assert_eq(items.has(HudSurface.HULL_BAR), id == &"left", "hull on %s" % id)
		assert_eq(items.has(HudSurface.CHARGE_BAR), id == &"right", "charge on %s" % id)


func test_the_hull_bar_is_the_left_screens_largest_readout() -> void:
	# Its only place in the cockpit view, so it reads first: full width, thick, a larger caption and the number.
	var left: HudSurface = HudLayout.compute(_hud()).screens[&"left"]
	assert_gt(left.hull_rect.size.x, left.size.x * 0.9, "nearly the screen's width")
	assert_gt(left.hull_rect.size.y, left.size.y * 0.1, "thick")
	assert_gt(left.bar_caption_size, 14.0, "a larger caption than the chase view's")
	assert_true(left.bar_percent, "and the number beside it")
	assert_gt(left.hull_rect.position.y, left.size.y * 0.5, "low on the screen, under the other readouts")


func test_the_charge_bar_stands_at_the_right_edge_under_the_target_section() -> void:
	var right: HudSurface = HudLayout.compute(_hud()).screens[&"right"]
	var bar: Rect2 = right.charge_rect
	assert_true(right.charge_vertical)
	assert_almost_eq(bar.size.x / right.size.x, 40.0 / 640.0, 0.005, "about 40/640 of the screen's width")
	assert_gt(bar.position.x, right.size.x * 0.85, "at the right edge")
	assert_lt(right.size.x - bar.end.x, 12.0 * right.scale, "up against it")
	assert_gt(right.charge_caption_pos.y, right.divider_y, "its label is under the target section's divider")
	assert_gt(bar.position.y, right.charge_caption_pos.y + 12.0 * right.scale, "the bar runs from under its two lines of label")
	assert_gt(bar.end.y, right.size.y * 0.96, "to the bottom of the screen")
	assert_gt(bar.size.y, bar.size.x * 3.0, "standing up")


func test_the_target_section_keeps_the_full_width_above_the_divider() -> void:
	var input: HudInput = _hud()
	input.target = _target()
	var right: HudSurface = HudLayout.compute(input).screens[&"right"]
	assert_gt(right.divider_y, 0.0)
	assert_lt(right.target_bar_rect.end.y, right.divider_y)
	assert_lt(right.target_silhouette_rect.end.y, right.divider_y)
	assert_gt(right.target_silhouette_rect.end.x, right.charge_rect.position.x, "the outline reaches over the charge bar's column")


func test_the_wing_and_lines_sit_left_of_the_charge_bar() -> void:
	var input: HudInput = _hud()
	input.roster = _roster()
	input.ack_line = "ALPHA 2: COPY"
	input.status_line = "WAVE 2   RAIDERS 3   KILLS 4   YOURS 1   ASSISTS 2"
	var right: HudSurface = HudLayout.compute(input).screens[&"right"]
	var left_of_bar: float = right.charge_rect.position.x
	for row: HudLayout.RosterRow in right.roster_rows:
		assert_lt(row.bar_rect.end.x, left_of_bar)
		assert_gt(row.bar_rect.position.y, right.divider_y, "under the divider")
	assert_gt(right.lines_width, 0.0, "long lines wrap")
	assert_lt(right.status_pos.x + right.lines_width, left_of_bar)
	assert_lt(right.ack_pos.x + right.lines_width, left_of_bar)
	assert_gt(right.status_pos.y, right.ack_pos.y, "the status lines under the acknowledgement")


func test_the_left_screen_lists_the_mockups_readouts() -> void:
	var left: Array[StringName] = (HudLayout.compute(_hud()).screens[&"left"] as HudSurface).items
	for item: StringName in [HudSurface.OWN_SILHOUETTE, HudSurface.HULL_BAR, HudSurface.FUEL_BAR, HudSurface.RUNNING_LIGHTS, HudSurface.SPEED, HudSurface.DRIFT]:
		assert_has(left, item)
	assert_does_not_have(left, HudSurface.TRACKING, "auto-track is on the octagon")


func test_auto_track_reads_on_the_octagon() -> void:
	var octagon: HudSurface = HudLayout.compute(_hud()).screens[&"octagon"]
	assert_has(octagon.items, HudSurface.TRACKING)
	assert_true(Rect2(Vector2.ZERO, octagon.size).has_point(octagon.tracking_pos))
	assert_almost_eq(octagon.tracking_pos.x, octagon.size.x * 0.5, 1.0, "centred")
	assert_lt(octagon.tracking_pos.y, octagon.size.y * 0.2, "at the top, away from own ship")


func test_speed_reads_large_on_the_left_screen_only() -> void:
	var f: HudFrame = HudLayout.compute(_hud())
	var left: HudSurface = f.screens[&"left"]
	assert_gt(left.speed_size, HudLayout.compute(_hud(false)).speed_size, "larger than the chase view's")
	assert_eq(HudLayout.compute(_hud(false)).speed_size, 22.0, "the chase view's as before")


func test_the_edge_arrow_stays_on_the_window() -> void:
	var input: HudInput = _hud()
	input.target = _target()
	input.target.position = Vector3(0.0, 0.0, 500.0)  # behind
	var f: HudFrame = HudLayout.compute(input)
	assert_true(f.edge_arrow_visible)
	assert_has(f.items, HudSurface.TARGET_MARKS)
	assert_does_not_have(f.items, HudSurface.TARGET_LABEL, "its name and range are on the right screen")


func test_the_chase_view_keeps_both_bars_on_the_2d_layer_as_before() -> void:
	var f: HudFrame = HudLayout.compute(_hud(false))
	assert_has(f.items, HudSurface.HULL_BAR)
	assert_has(f.items, HudSurface.CHARGE_BAR)
	assert_eq(f.hull_rect, Rect2(Vector2(48.0, VIEW.y - 90.0), Vector2(260.0, 14.0)))
	assert_eq(f.charge_rect, Rect2(Vector2(VIEW.x - 48.0 - 260.0, VIEW.y - 56.0), Vector2(260.0, 14.0)))
	assert_eq(f.bar_caption_size, 14.0)
	assert_false(f.bar_percent)
	assert_false(f.charge_vertical)


func test_every_other_instrument_is_on_a_screen() -> void:
	var f: HudFrame = HudLayout.compute(_hud())
	var shown: Dictionary = {}
	for item: StringName in f.items:
		shown[item] = true
	for id: StringName in f.screens:
		for item: StringName in (f.screens[id] as HudSurface).items:
			shown[item] = true
	for item: StringName in HudSurface.ALL_ITEMS:
		if item != HudSurface.TARGET_LABEL:  # its name, range and hull bar are the right screen's target panel
			assert_true(shown.has(item), "%s is shown somewhere" % item)
	assert_true(shown.has(HudSurface.TARGET_PANEL))


func test_each_screen_shows_what_q29_gave_it() -> void:
	var screens: Dictionary = HudLayout.compute(_hud()).screens
	assert_eq_deep(screens.keys(), SIZES.keys())
	assert_eq((screens[&"octagon"] as HudSurface).items, [HudSurface.GRID, HudSurface.RADAR, HudSurface.TRACKING] as Array[StringName])
	var left: Array[StringName] = (screens[&"left"] as HudSurface).items
	for item: StringName in [HudSurface.OWN_SILHOUETTE, HudSurface.HULL_BAR, HudSurface.SPEED, HudSurface.DRIFT]:
		assert_has(left, item)
	var right: Array[StringName] = (screens[&"right"] as HudSurface).items
	for item: StringName in [HudSurface.TARGET_PANEL, HudSurface.TARGET_SILHOUETTE, HudSurface.ROSTER, HudSurface.CHARGE_BAR, HudSurface.ACK, HudSurface.STATUS]:
		assert_has(right, item)


func test_a_screen_is_given_the_frames_own_data() -> void:
	var input: HudInput = _hud()
	input.target = _target()
	input.roster = _roster()
	input.own_velocity = Vector3(0.0, 0.0, -100.0)
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.speed_mps, 100.0)
	assert_eq(f.target_name, "RAIDER 3")
	assert_eq(f.target_layout, DamageZones.Layout.DELTA)
	assert_eq(f.roster_rows.size(), 0, "the window has no roster")
	var rows: Array[HudLayout.RosterRow] = (f.screens[&"right"] as HudSurface).roster_rows
	assert_eq(rows.size(), 2)
	assert_string_contains(rows[0].text, "ALPHA 2")
	assert_true(rows[1].down)


func test_the_chase_view_ignores_screen_sizes() -> void:
	var with_screens: HudFrame = HudLayout.compute(_hud(false))
	var without: HudFrame = HudLayout.compute(_hud(false, {}))
	assert_true(with_screens.screens.is_empty())
	assert_eq(with_screens.items, without.items)
	assert_eq(with_screens.hull_rect, without.hull_rect)
	assert_eq(with_screens.charge_rect, without.charge_rect)
	assert_eq(with_screens.radar_centre, without.radar_centre)
	assert_eq(with_screens.speed_pos, without.speed_pos)
	assert_eq(with_screens.own_silhouette_rect, without.own_silhouette_rect)


func test_the_grid_setting_adds_the_grid_to_the_chase_view_only() -> void:
	var chase: HudInput = _hud(false)
	chase.show_grid = true
	var f: HudFrame = HudLayout.compute(chase)
	assert_true(f.grid_visible)
	assert_has(f.items, HudSurface.GRID)
	var cockpit: HudInput = _hud()
	cockpit.show_grid = true
	assert_false(HudLayout.compute(cockpit).grid_visible)
	assert_does_not_have(HudLayout.compute(_hud(false)).items, HudSurface.GRID, "off by default")


# --- rects -------------------------------------------------------------------------------------------------------------


func _inside(surface: HudSurface, rect: Rect2, what: String) -> void:
	assert_true(Rect2(Vector2.ZERO, surface.size).encloses(rect), "%s: %s fits in %s" % [what, rect, surface.size])
	assert_gt(rect.size.x, 0.0, what)
	assert_gt(rect.size.y, 0.0, what)


func _check_rects(sizes: Dictionary) -> void:
	var input: HudInput = _hud(true, sizes)
	input.fuel_unlimited = false
	input.target = _target()
	input.roster = _roster()
	var screens: Dictionary = HudLayout.compute(input).screens
	var left: HudSurface = screens[&"left"]
	_inside(left, left.own_silhouette_rect, "own silhouette")
	_inside(left, left.hull_rect, "hull")
	_inside(left, left.fuel_rect, "fuel")
	_inside(left, Rect2(left.drift_centre - Vector2.ONE * left.drift_radius_px, Vector2.ONE * 2.0 * left.drift_radius_px), "drift")
	assert_false(left.own_silhouette_rect.intersects(left.hull_rect), "the bar clears the wireframe")
	assert_false(left.hull_rect.intersects(left.fuel_rect))
	var right: HudSurface = screens[&"right"]
	_inside(right, right.charge_rect, "charge")
	_inside(right, right.target_silhouette_rect, "target silhouette")
	_inside(right, right.target_bar_rect, "target hull bar")
	for row: HudLayout.RosterRow in right.roster_rows:
		_inside(right, row.bar_rect, "roster row")
		assert_lt(row.text_pos.y, right.size.y)
	var octagon: HudSurface = screens[&"octagon"]
	_inside(octagon, octagon.grid_rect, "grid")
	_inside(octagon, Rect2(octagon.radar_centre - Vector2.ONE * octagon.radar_radius_px, Vector2.ONE * 2.0 * octagon.radar_radius_px), "radar")
	assert_almost_eq(octagon.radar_centre, octagon.size * 0.5, Vector2.ONE, "the radar sits in the middle of the octagon")


func test_each_screens_rects_fit_inside_it() -> void:
	_check_rects(SIZES)
	_check_rects({&"octagon": Vector2(280.0, 215.0), &"left": Vector2(250.0, 180.0), &"right": Vector2(250.0, 180.0)})
	_check_rects({&"octagon": Vector2(1120.0, 860.0), &"left": Vector2(1000.0, 720.0), &"right": Vector2(1000.0, 720.0)})


func test_a_screens_sizes_scale_with_its_height() -> void:
	var small: HudSurface = HudLayout.compute(_hud(true, {&"octagon": Vector2(280.0, 215.0), &"left": Vector2(250.0, 180.0), &"right": Vector2(250.0, 180.0)})).screens[&"left"]
	var large: HudSurface = HudLayout.compute(_hud()).screens[&"left"]
	assert_almost_eq(large.scale / small.scale, 2.0, 1e-5)


# --- the octagon's look ------------------------------------------------------------------------------------------------


func test_the_octagon_has_a_red_grid_and_named_range_rings() -> void:
	var f: HudFrame = HudLayout.compute(_hud())
	var octagon: HudSurface = f.screens[&"octagon"]
	assert_eq(octagon.grid_color, HudLayout.OCTAGON_GRID_COLOR)
	assert_gt(octagon.grid_color.r, octagon.grid_color.g * 2.0, "red")
	assert_true(octagon.radar_labels, "its range rings are named")
	assert_true(octagon.grid_marker_diagonal, "the tactical grid's diagonal marker")
	var chase: HudInput = _hud(false)
	chase.show_grid = true
	var c: HudFrame = HudLayout.compute(chase)
	assert_eq(c.grid_color, HudLayout.LINE_COLOR, "the chase view's grid stays green")
	assert_false(c.radar_labels)
	assert_false(c.grid_marker_diagonal)

func test_the_frame_carries_the_targets_relation() -> void:
	var input: HudInput = _hud()
	input.target = _target()
	assert_eq(HudLayout.compute(input).target_relation, Factions.Relation.HOSTILE)


func test_the_octagons_grid_marker_is_the_targets_offset_from_the_nose() -> void:
	var input: HudInput = _hud()
	input.target = TargetReadout.new()
	input.target.position = Vector3(tan(deg_to_rad(15.0)) * 1000.0, -tan(deg_to_rad(15.0)) * 1000.0, -1000.0)
	var octagon: HudSurface = HudLayout.compute(input).screens[&"octagon"]
	assert_true(octagon.grid_marker_visible)
	assert_true(octagon.grid_marker_inside)
	var half: float = minf(octagon.grid_rect.size.x, octagon.grid_rect.size.y) * 0.5
	assert_almost_eq(octagon.grid_marker, octagon.grid_rect.get_center() + Vector2(0.5, 0.5) * half, Vector2.ONE * 0.5)


func test_a_screen_carries_status_and_acknowledgement() -> void:
	var input: HudInput = _hud()
	input.status_line = "WAVE 2   RAIDERS 3   KILLS 4"
	input.ack_line = "ALPHA 2: COPY"
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.status_line, input.status_line)
	assert_eq(f.ack_line, input.ack_line)
	var right: HudSurface = f.screens[&"right"]
	assert_has(right.items, HudSurface.STATUS)
	assert_has(right.items, HudSurface.ACK)
	assert_lt(right.status_pos.y, right.size.y)
	assert_lt(right.ack_pos.y, right.size.y)
	assert_does_not_have(f.items, HudSurface.STATUS)


# --- indicator lamps ----------------------------------------------------------------------------------------------------


func test_the_lamps_follow_their_states() -> void:
	var input: HudInput = _hud()
	input.assist = true
	input.guns_ready = false
	input.running_lights = true
	input.tracking = false
	var lamps: Dictionary = HudLayout.compute(input).lamps
	assert_eq_deep(lamps, {&"assist": true, &"guns": false, &"lights": true, &"track": false})
	input.assist = false
	input.guns_ready = true
	input.running_lights = false
	input.tracking = true
	assert_eq_deep(HudLayout.compute(input).lamps, {&"assist": false, &"guns": true, &"lights": false, &"track": true})


func test_every_lamp_has_a_colour() -> void:
	for lamp: StringName in HudLayout.compute(_hud()).lamps:
		assert_true(HudLayout.LAMP_COLORS.has(lamp), String(lamp))


# --- the overlay fix -----------------------------------------------------------------------------------------------------


func test_the_roster_moves_clear_of_the_debug_overlay() -> void:
	var input: HudInput = _hud(false)
	input.roster = _roster()
	var free: HudFrame = HudLayout.compute(input)
	assert_almost_eq(free.roster_rows[0].bar_rect.position.y, 54.0, 1e-3, "at the top left with no overlay")
	input.overlay_bottom_px = 280.0
	var moved: HudFrame = HudLayout.compute(input)
	assert_gt(moved.roster_rows[0].bar_rect.position.y, 280.0, "below the overlay's last line")
	assert_almost_eq(moved.roster_rows[0].bar_rect.position.x, free.roster_rows[0].bar_rect.position.x, 1e-3)
	assert_almost_eq(moved.roster_rows[1].bar_rect.position.y - moved.roster_rows[0].bar_rect.position.y,
			free.roster_rows[1].bar_rect.position.y - free.roster_rows[0].bar_rect.position.y, 1e-3, "same pitch")
	input.overlay_bottom_px = 10.0
	assert_almost_eq(HudLayout.compute(input).roster_rows[0].bar_rect.position.y, 54.0, 1e-3, "a short overlay moves nothing")


func test_the_overlay_does_not_move_the_right_screens_roster() -> void:
	var input: HudInput = _hud()
	input.roster = _roster()
	var free: HudSurface = HudLayout.compute(input).screens[&"right"]
	input.overlay_bottom_px = 280.0
	var same: HudSurface = HudLayout.compute(input).screens[&"right"]
	assert_eq(same.roster_rows[0].bar_rect, free.roster_rows[0].bar_rect)
