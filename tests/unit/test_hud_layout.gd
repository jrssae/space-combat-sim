extends GutTest
## HudLayout (M2-T08, AC10, architecture §15.9): the pure layout on hand-built cameras. The agreement with a real
## `Camera3D.unproject_position` is checked in `test_hud.gd`.

const VIEW := Vector2(1920.0, 1080.0)
const TOL: float = 1e-3


## A camera at the origin looking down -Z with a 75 degree vertical field of view.
func _hud_input() -> HudInput:
	var input := HudInput.new()
	input.camera_transform = Transform3D.IDENTITY
	input.projection = Projection.create_perspective(75.0, VIEW.x / VIEW.y, 0.05, 100000.0)
	input.viewport_size = VIEW
	return input


func _target(position: Vector3, velocity: Vector3 = Vector3.ZERO, faction: StringName = Factions.RAIDERS) -> TargetReadout:
	var t := TargetReadout.new()
	t.id = 7
	t.display_name = "RAIDER 1"
	t.faction = faction
	t.position = position
	t.velocity = velocity
	t.range_m = position.length()
	t.closing_mps = 12.0
	t.hull_fraction = 0.8
	return t


# --- projection ----------------------------------------------------------------------------------------------------


func test_a_point_on_the_axis_projects_to_the_centre() -> void:
	var p: Dictionary = HudLayout.project(_hud_input(), Vector3(0.0, 0.0, -500.0))
	assert_true(p["in_front"])
	assert_almost_eq(p["pos"], VIEW * 0.5, Vector2.ONE * TOL)


func test_up_is_up_the_screen_and_right_is_right() -> void:
	var c: Vector2 = HudLayout.project(_hud_input(), Vector3(0.0, 0.0, -100.0))["pos"]
	var up: Vector2 = HudLayout.project(_hud_input(), Vector3(0.0, 10.0, -100.0))["pos"]
	var right: Vector2 = HudLayout.project(_hud_input(), Vector3(10.0, 0.0, -100.0))["pos"]
	assert_lt(up.y, c.y)
	assert_gt(right.x, c.x)


func test_the_vertical_field_of_view_is_respected() -> void:
	# At 75 degrees vertical, a point at the top-edge angle projects to y = 0.
	var z: float = 100.0
	var top: Vector2 = HudLayout.project(_hud_input(), Vector3(0.0, z * tan(deg_to_rad(37.5)), -z))["pos"]
	assert_almost_eq(top.y, 0.0, 0.05)


func test_a_point_behind_the_camera_is_not_in_front() -> void:
	assert_false(HudLayout.project(_hud_input(), Vector3(0.0, 0.0, 100.0))["in_front"])
	assert_false(HudLayout.project(_hud_input(), Vector3(5.0, 5.0, 0.0))["in_front"], "in the camera's plane")


func test_a_moved_and_turned_camera() -> void:
	var input: HudInput = _hud_input()
	input.camera_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(100.0, 0.0, 0.0))  # looks along -X
	var p: Dictionary = HudLayout.project(input, Vector3(-400.0, 0.0, 0.0))
	assert_true(p["in_front"])
	assert_almost_eq(p["pos"], VIEW * 0.5, Vector2.ONE * TOL)


# --- boresight and velocity marker -------------------------------------------------------------------------------------


func test_the_boresight_is_the_nose_axis_at_a_kilometre() -> void:
	var f: HudFrame = HudLayout.compute(_hud_input())
	assert_true(f.boresight_visible)
	assert_almost_eq(f.boresight_pos, VIEW * 0.5, Vector2.ONE * TOL)
	var input: HudInput = _hud_input()
	input.own_basis = Basis(Vector3.UP, deg_to_rad(90.0))  # the nose is 90 degrees off the camera's view
	assert_false(HudLayout.compute(input).boresight_visible)


func test_prograde_shows_where_the_ship_is_going() -> void:
	var input: HudInput = _hud_input()
	input.own_velocity = Vector3(10.0, 0.0, -100.0)
	var f: HudFrame = HudLayout.compute(input)
	assert_true(f.velocity_visible)
	assert_false(f.retrograde)
	assert_gt(f.velocity_pos.x, VIEW.x * 0.5, "drifting right")
	assert_almost_eq(f.speed_mps, sqrt(10.0 * 10.0 + 100.0 * 100.0), 1e-6)


func test_the_marker_switches_to_retrograde_when_prograde_is_behind() -> void:
	var input: HudInput = _hud_input()
	input.own_velocity = Vector3(0.0, 0.0, 80.0)  # backing up: prograde is behind the camera
	var f: HudFrame = HudLayout.compute(input)
	assert_true(f.retrograde)
	assert_true(f.velocity_visible)
	assert_almost_eq(f.velocity_pos, VIEW * 0.5, Vector2.ONE * TOL, "retrograde is dead ahead")


func test_no_velocity_marker_at_rest() -> void:
	var f: HudFrame = HudLayout.compute(_hud_input())
	assert_false(f.velocity_visible)
	assert_eq(f.speed_mps, 0.0)


# --- target box, edge arrow, lead ----------------------------------------------------------------------------------------


func test_a_target_on_screen_gets_a_box_at_least_24_px_in_its_faction_colour() -> void:
	var input: HudInput = _hud_input()
	input.target = _target(Vector3(0.0, 0.0, -3000.0))
	var f: HudFrame = HudLayout.compute(input)
	assert_true(f.target_present)
	assert_true(f.target_on_screen)
	assert_false(f.edge_arrow_visible)
	assert_almost_eq(f.target_box.get_center(), VIEW * 0.5, Vector2.ONE * TOL)
	assert_almost_eq(f.target_box.size.x, 24.0, 1e-3, "the minimum")
	assert_eq(f.target_color, Factions.HOSTILE_COLOR)
	assert_eq(f.target_name, "RAIDER 1")
	assert_eq(f.target_closing_mps, 12.0)
	assert_eq(f.target_hull, 0.8)


func test_the_box_grows_to_the_projected_bounding_radius() -> void:
	var input: HudInput = _hud_input()
	var t: TargetReadout = _target(Vector3(0.0, 0.0, -100.0))
	t.bounding_radius = 10.0
	input.target = t
	var f: HudFrame = HudLayout.compute(input)
	var px_per_m: float = (VIEW.y * 0.5) / tan(deg_to_rad(37.5)) / 100.0
	assert_almost_eq(f.target_box.size.x * 0.5, 10.0 * px_per_m, 0.5)
	assert_gt(f.target_box.size.x, 24.0)


func test_the_box_scales_with_the_viewport_height() -> void:
	var input: HudInput = _hud_input()
	input.viewport_size = Vector2(960.0, 540.0)
	input.projection = Projection.create_perspective(75.0, 960.0 / 540.0, 0.05, 100000.0)
	input.target = _target(Vector3(0.0, 0.0, -3000.0))
	var f: HudFrame = HudLayout.compute(input)
	assert_almost_eq(f.scale, 0.5, 1e-6)
	assert_almost_eq(f.target_box.size.x, 12.0, 1e-3, "half the pixels at half the height")


func test_friendly_and_neutral_targets_have_their_colours() -> void:
	var input: HudInput = _hud_input()
	input.target = _target(Vector3(0.0, 0.0, -500.0), Vector3.ZERO, Factions.EARTH_ALLIANCE)
	assert_eq(HudLayout.compute(input).target_color, Factions.FRIENDLY_COLOR)
	input.target = _target(Vector3(0.0, 0.0, -500.0), Vector3.ZERO, Factions.NEUTRAL)
	assert_eq(HudLayout.compute(input).target_color, Factions.NEUTRAL_COLOR)


func test_an_off_screen_target_hides_the_box_and_shows_the_edge_arrow() -> void:
	var input: HudInput = _hud_input()
	input.target = _target(Vector3(2000.0, 0.0, -500.0))  # far to the right
	var f: HudFrame = HudLayout.compute(input)
	assert_false(f.target_on_screen)
	assert_true(f.edge_arrow_visible)
	assert_gt(f.edge_arrow_pos.x, VIEW.x - 100.0, "on the right border")
	assert_almost_eq(f.edge_arrow_pos.y, VIEW.y * 0.5, 1.0)
	assert_almost_eq(f.edge_arrow_angle, 0.0, 1e-3, "pointing right")
	assert_true(f.target_present, "the readout still shows")


func test_a_target_above_points_up_and_a_target_behind_points_to_its_side() -> void:
	var input: HudInput = _hud_input()
	input.target = _target(Vector3(0.0, 3000.0, -200.0))
	var up: HudFrame = HudLayout.compute(input)
	assert_true(up.edge_arrow_visible)
	assert_lt(up.edge_arrow_pos.y, 100.0, "on the top border")
	assert_almost_eq(up.edge_arrow_angle, -PI * 0.5, 1e-3)
	input.target = _target(Vector3(-300.0, 0.0, 800.0))  # behind and to the left
	var behind: HudFrame = HudLayout.compute(input)
	assert_false(behind.target_on_screen)
	assert_true(behind.edge_arrow_visible)
	assert_lt(behind.edge_arrow_pos.x, VIEW.x * 0.5, "the left side")
	input.target = _target(Vector3(0.0, 0.0, 800.0))  # dead astern
	assert_true(HudLayout.compute(input).edge_arrow_visible)


func test_no_target_no_box_no_lead() -> void:
	var f: HudFrame = HudLayout.compute(_hud_input())
	assert_false(f.target_present)
	assert_false(f.target_on_screen)
	assert_false(f.lead_visible)
	assert_false(f.edge_arrow_visible)


# --- route waypoint (M3-T09) -------------------------------------------------------------------------------------------


func test_the_waypoint_marker_sits_on_the_projected_route_point() -> void:
	var input: HudInput = _hud_input()
	assert_false(HudLayout.compute(input).waypoint_present, "no route, no marker")
	input.has_waypoint = true
	input.waypoint_position = Vector3(120.0, -40.0, -900.0)
	input.waypoint_label = "NAV 2"
	input.own_position = Vector3(0.0, 0.0, -10.0)
	var f: HudFrame = HudLayout.compute(input)
	assert_true(f.waypoint_present)
	assert_true(f.waypoint_on_screen)
	assert_almost_eq(f.waypoint_pos, HudLayout.project(input, input.waypoint_position)["pos"] as Vector2, Vector2.ONE * TOL)
	assert_eq(f.waypoint_label, "NAV 2")
	assert_almost_eq(f.waypoint_range_m, input.own_position.distance_to(input.waypoint_position), 1e-3, "range from the ship")
	assert_false(f.waypoint_edge_visible)
	assert_false(f.edge_arrow_visible, "the target's arrow is its own")


func test_a_waypoint_off_screen_or_behind_gets_an_edge_arrow() -> void:
	var input: HudInput = _hud_input()
	input.has_waypoint = true
	input.waypoint_label = "NAV 3"
	input.waypoint_position = Vector3(3000.0, 0.0, -100.0)  # far right
	var right: HudFrame = HudLayout.compute(input)
	assert_false(right.waypoint_on_screen)
	assert_true(right.waypoint_edge_visible)
	assert_gt(right.waypoint_edge_pos.x, VIEW.x - 100.0, "on the right border")
	assert_almost_eq(right.waypoint_edge_angle, 0.0, 1e-3, "pointing right")
	input.waypoint_position = Vector3(0.0, 0.0, 800.0)  # dead astern
	var behind: HudFrame = HudLayout.compute(input)
	assert_true(behind.waypoint_edge_visible)
	assert_false(behind.target_present, "no target meanwhile")


func test_the_lead_reticle_sits_on_the_projected_intercept_point() -> void:
	var input: HudInput = _hud_input()
	input.muzzle_position = Vector3(0.0, -1.0, -3.0)
	input.own_velocity = Vector3(0.0, 0.0, -30.0)
	input.weapon_speed_mps = 400.0
	input.weapon_lifetime_s = 4.0
	input.target = _target(Vector3(60.0, 20.0, -900.0), Vector3(-40.0, 0.0, 10.0))
	var solution: Dictionary = InterceptMath.solve(input.muzzle_position, input.own_velocity, input.target.position, input.target.velocity, 400.0, 4.0)
	assert_true(solution["ok"])
	var expected: Dictionary = HudLayout.project(input, solution["lead_point"])
	var f: HudFrame = HudLayout.compute(input)
	assert_true(f.lead_visible)
	assert_almost_eq(f.lead_pos, expected["pos"], Vector2.ONE * TOL)
	assert_almost_eq(f.lead_tof_s, float(solution["t"]), 1e-9)


func test_the_lead_hides_without_a_solution_or_beyond_the_bolts_range() -> void:
	var input: HudInput = _hud_input()
	input.weapon_speed_mps = 400.0
	input.weapon_lifetime_s = 4.0
	input.target = _target(Vector3(0.0, 0.0, -5000.0), Vector3(0.0, 0.0, -600.0))  # fleeing faster than the bolt
	assert_false(HudLayout.compute(input).lead_visible, "no solution")
	input.target = _target(Vector3(0.0, 0.0, -3000.0))  # 7.5 s of flight: past a 4 s lifetime
	assert_false(HudLayout.compute(input).lead_visible, "beyond the bolt's range")
	input.target = _target(Vector3(0.0, 0.0, -1000.0))
	assert_true(HudLayout.compute(input).lead_visible, "2.5 s: inside it")


# --- gauges -----------------------------------------------------------------------------------------------------------


func test_hull_colour_thresholds() -> void:
	assert_eq(HudLayout.hull_color(1.0), Factions.HUD_LINE_COLOR)
	assert_eq(HudLayout.hull_color(0.51), Factions.HUD_LINE_COLOR)
	assert_eq(HudLayout.hull_color(0.5), HudLayout.AMBER, "green above 50 %, amber from there")
	assert_eq(HudLayout.hull_color(0.26), HudLayout.AMBER)
	assert_eq(HudLayout.hull_color(0.25), HudLayout.RED)
	assert_eq(HudLayout.hull_color(0.0), HudLayout.RED)


func test_gauges_follow_the_input() -> void:
	var input: HudInput = _hud_input()
	input.hull_fraction = 0.4
	input.god = true
	input.fuel_fraction = 0.7
	input.fuel_unlimited = false
	input.charge_fraction = 0.25
	input.fire_mode = "linked"
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.hull_fraction, 0.4)
	assert_eq(f.hull_color, HudLayout.AMBER)
	assert_true(f.god)
	assert_eq(f.fuel_fraction, 0.7)
	assert_false(f.fuel_unlimited)
	assert_eq(f.charge_fraction, 0.25)
	assert_eq(f.fire_mode, "linked")


func test_unlimited_fuel_reads_full_with_the_infinity_flag() -> void:
	var input: HudInput = _hud_input()
	input.fuel_fraction = 1.0
	input.fuel_unlimited = true
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.fuel_fraction, 1.0)
	assert_true(f.fuel_unlimited)


func test_gauge_values_are_clamped() -> void:
	var input: HudInput = _hud_input()
	input.hull_fraction = 1.7
	input.fuel_fraction = -0.2
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.hull_fraction, 1.0)
	assert_eq(f.fuel_fraction, 0.0)


func test_the_gauges_sit_on_the_bottom_edge() -> void:
	var cockpit_input: HudInput = _hud_input()
	cockpit_input.cockpit = true
	var f: HudFrame = HudLayout.compute(cockpit_input)
	assert_gt(f.speed_pos.y, VIEW.y - 100.0)
	assert_almost_eq(f.speed_pos.x, VIEW.x * 0.5, 1e-6, "speed: bottom centre")
	assert_lt(f.hull_rect.position.x, VIEW.x * 0.25, "hull and fuel: bottom left")
	assert_lt(f.fuel_rect.position.x, VIEW.x * 0.25)
	assert_gt(f.charge_rect.position.x, VIEW.x * 0.75, "weapon charge: bottom right")
	assert_lt(f.radar_centre.y, f.speed_pos.y, "the radar is above the speed readout")
	assert_almost_eq(f.radar_centre.x, VIEW.x * 0.5, 1e-6)
	assert_false(f.speed_align_right)


func test_the_chase_view_moves_the_middle_clutter_into_the_corners() -> void:
	var input: HudInput = _hud_input()
	input.cockpit = false
	var f: HudFrame = HudLayout.compute(input)
	assert_gt(f.radar_centre.x, VIEW.x * 0.75, "radar: bottom right")
	assert_gt(f.speed_pos.x, VIEW.x * 0.75, "speed: bottom right")
	assert_true(f.speed_align_right)
	assert_lt(f.speed_pos.y + 24.0, f.radar_centre.y - f.radar_radius_px, "the readout sits above the radar, not on it")
	assert_lt(f.radar_centre.y + f.radar_radius_px, f.charge_rect.position.y, "and the radar clears the charge bar")
	# Nothing of the cockpit's bottom-centre cluster is left in the middle third of the screen.
	var middle_lo: float = VIEW.x / 3.0
	var middle_hi: float = VIEW.x * 2.0 / 3.0
	for x: float in [f.radar_centre.x - f.radar_radius_px, f.speed_pos.x - 200.0, f.own_silhouette_rect.end.x]:
		assert_false(x > middle_lo and x < middle_hi, "x = %.0f is not in the middle third" % x)
	assert_false(f.cockpit)
	input.cockpit = true
	assert_true(HudLayout.compute(input).cockpit)


func test_the_status_line_passes_through() -> void:
	var input: HudInput = _hud_input()
	input.status_line = "WAVE 2   RAIDERS 3   KILLS 4"
	assert_eq(HudLayout.compute(input).status_line, "WAVE 2   RAIDERS 3   KILLS 4")


# --- the targeting grid -------------------------------------------------------------------------------------------------


func test_the_grid_shows_in_the_cockpit_or_by_setting() -> void:
	var input: HudInput = _hud_input()
	assert_false(HudLayout.compute(input).grid_visible)
	input.cockpit = true
	assert_true(HudLayout.compute(input).grid_visible)
	input.cockpit = false
	input.show_grid = true
	assert_true(HudLayout.compute(input).grid_visible)


func test_the_grid_is_low_and_centred() -> void:
	var input: HudInput = _hud_input()
	input.cockpit = true
	var f: HudFrame = HudLayout.compute(input)
	assert_almost_eq(f.grid_rect.get_center().x, VIEW.x * 0.5, 1e-6)
	assert_gt(f.grid_rect.get_center().y, VIEW.y * 0.5, "below the middle")
	assert_eq(f.grid_cells, 8)
	assert_lt(f.grid_rect.end.y, f.radar_centre.y - f.radar_radius_px, "clear of the radar")


func test_the_grid_marker_is_the_targets_offset_from_the_nose() -> void:
	var input: HudInput = _hud_input()
	input.cockpit = true
	input.target = _target(Vector3(0.0, 0.0, -1000.0))
	var centred: HudFrame = HudLayout.compute(input)
	assert_true(centred.grid_marker_visible)
	assert_true(centred.grid_marker_inside)
	assert_almost_eq(centred.grid_marker, centred.grid_rect.get_center(), Vector2.ONE * TOL)
	input.target = _target(Vector3(1000.0 * tan(deg_to_rad(15.0)), 1000.0 * tan(deg_to_rad(-15.0)), -1000.0))
	var off: HudFrame = HudLayout.compute(input)
	var half: float = off.grid_rect.size.x * 0.5
	assert_almost_eq(off.grid_marker.x, off.grid_rect.get_center().x + half * 0.5, 0.5, "15 of 30 degrees right: half way to the edge")
	assert_almost_eq(off.grid_marker.y, off.grid_rect.get_center().y + half * 0.5, 0.5, "15 degrees below: lower")


func test_the_grid_marker_clamps_to_the_edge_outside_its_span() -> void:
	var input: HudInput = _hud_input()
	input.cockpit = true
	input.target = _target(Vector3(1000.0, 0.0, -1000.0))  # 45 degrees right
	var f: HudFrame = HudLayout.compute(input)
	assert_true(f.grid_marker_visible)
	assert_false(f.grid_marker_inside)
	assert_almost_eq(f.grid_marker.x, f.grid_rect.end.x, 1e-3)
	input.target = _target(Vector3(0.0, 0.0, 1000.0))  # behind: no marker
	assert_false(HudLayout.compute(input).grid_marker_visible)


# --- the radar through the layout -----------------------------------------------------------------------------------------


func test_the_layout_carries_the_radar_dots() -> void:
	var input: HudInput = _hud_input()
	input.contacts = [TargetInfo.new(1, "A", Factions.RAIDERS, Vector3(0.0, 0.0, -1000.0)), TargetInfo.new(2, "B", Factions.NEUTRAL, Vector3(0.0, 0.0, -99000.0))]
	input.selected_id = 1
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.radar_dots.size(), 1)
	assert_true(f.radar_dots[0].selected)
	assert_gt(f.radar_radius_px, 0.0)


# --- Velocity direction against the nose, the reference point, damage colours (post-M2 HUD) -------------------------


func test_velocity_angles_are_zero_when_flying_straight_ahead() -> void:
	var angles: Vector2 = HudLayout.velocity_angles_deg(Basis.IDENTITY, Vector3(0.0, 0.0, -300.0))
	assert_almost_eq(angles.x, 0.0, 1e-6)
	assert_almost_eq(angles.y, 0.0, 1e-6)


func test_velocity_angles_horizontal_is_right_of_the_nose_and_vertical_is_above_it() -> void:
	var right: Vector2 = HudLayout.velocity_angles_deg(Basis.IDENTITY, Vector3(100.0, 0.0, -100.0))
	assert_almost_eq(right.x, 45.0, 1e-6, "moving right of the nose")
	assert_almost_eq(right.y, 0.0, 1e-6)
	var up: Vector2 = HudLayout.velocity_angles_deg(Basis.IDENTITY, Vector3(0.0, 100.0, -100.0))
	assert_almost_eq(up.y, 45.0, 1e-6, "moving above the nose")
	assert_almost_eq(up.x, 0.0, 1e-6)
	var down_left: Vector2 = HudLayout.velocity_angles_deg(Basis.IDENTITY, Vector3(-100.0, -100.0, -100.0))
	assert_lt(down_left.x, 0.0)
	assert_lt(down_left.y, 0.0)


func test_velocity_angles_follow_the_ships_orientation() -> void:
	# The ship yaws 30 degrees to the left but keeps moving along -Z: the travel direction is 30 degrees to its right.
	var yawed := Basis(Vector3.UP, deg_to_rad(30.0))
	var angles: Vector2 = HudLayout.velocity_angles_deg(yawed, Vector3(0.0, 0.0, -100.0))
	assert_almost_eq(angles.x, 30.0, 1e-4)


func test_flying_backward_is_180_horizontal() -> void:
	var angles: Vector2 = HudLayout.velocity_angles_deg(Basis.IDENTITY, Vector3(0.0, 0.0, 100.0))
	assert_almost_eq(absf(angles.x), 180.0, 1e-6)
	assert_almost_eq(angles.y, 0.0, 1e-6)
	assert_eq(HudLayout.velocity_angles_deg(Basis.IDENTITY, Vector3.ZERO), Vector2.ZERO)


func test_the_frame_carries_the_angles_only_above_the_marker_speed() -> void:
	var input := HudInput.new()
	input.own_velocity = Vector3(10.0, 0.0, -10.0)
	var frame: HudFrame = HudLayout.compute(input)
	assert_true(frame.velocity_angles_valid)
	assert_almost_eq(frame.velocity_h_deg, 45.0, 1e-4)
	input.own_velocity = Vector3(0.1, 0.0, 0.0)
	assert_false(HudLayout.compute(input).velocity_angles_valid, "too slow for a direction to mean anything")


func test_reference_range_and_closing_speed() -> void:
	var input := HudInput.new()
	input.has_reference = true
	input.reference_position = Vector3(0.0, 0.0, -1000.0)
	input.own_velocity = Vector3(0.0, 0.0, -250.0)
	var frame: HudFrame = HudLayout.compute(input)
	assert_true(frame.reference_valid)
	assert_almost_eq(frame.reference_range_m, 1000.0, 1e-6)
	assert_almost_eq(frame.reference_closing_mps, 250.0, 1e-6, "approaching it")
	input.own_velocity = Vector3(0.0, 0.0, 250.0)
	assert_almost_eq(HudLayout.compute(input).reference_closing_mps, -250.0, 1e-6, "moving away")
	input.own_velocity = Vector3(400.0, 0.0, 0.0)
	assert_almost_eq(HudLayout.compute(input).reference_closing_mps, 0.0, 1e-6, "sideways neither closes nor opens")
	input.has_reference = false
	assert_false(HudLayout.compute(input).reference_valid)


func test_damage_colours_run_from_green_through_yellow_and_orange_to_red() -> void:
	assert_eq(HudLayout.damage_color(0.0), Factions.HUD_LINE_COLOR)
	var yellow: Color = HudLayout.damage_color(0.2)
	var orange: Color = HudLayout.damage_color(0.5)
	var red: Color = HudLayout.damage_color(0.9)
	assert_eq(red, HudLayout.RED)
	assert_gt(yellow.g, orange.g, "yellow is greener than orange")
	assert_gt(orange.g, red.g, "orange is greener than red")
	assert_ne(yellow, orange)


func test_the_silhouettes_come_from_the_input() -> void:
	var input := HudInput.new()
	input.cockpit = true
	input.damage_layout = DamageZones.Layout.X_FIGHTER
	input.damage_zones = PackedFloat32Array([0.0, 0.5, 0.0, 0.0, 1.0])
	var frame: HudFrame = HudLayout.compute(input)
	assert_eq(frame.own_layout, DamageZones.Layout.X_FIGHTER)
	assert_eq(frame.own_zones, input.damage_zones)
	assert_gt(frame.own_silhouette_rect.size.x, 0.0)
	assert_eq(frame.target_layout, DamageZones.Layout.NONE, "no target, no target silhouette")
	var target := TargetReadout.new()
	target.damage_layout = DamageZones.Layout.DELTA
	target.damage_zones = PackedFloat32Array([0.0, 1.0, 0.0])
	input.target = target
	frame = HudLayout.compute(input)
	assert_eq(frame.target_layout, DamageZones.Layout.DELTA)
	assert_gt(frame.target_silhouette_rect.position.x, frame.radar_centre.x, "beside the radar (cockpit: to its right)")
	input.cockpit = false
	frame = HudLayout.compute(input)
	assert_lt(frame.target_silhouette_rect.end.x, frame.radar_centre.x, "chase: to its left, clear of the corner")
	var buoy := TargetReadout.new()
	input.target = buoy
	assert_eq(HudLayout.compute(input).target_layout, DamageZones.Layout.NONE, "a buoy has no zones")


# --- Drift sphere and the optional world marker ----------------------------------------------------------------------


func test_the_drift_sphere_points_along_the_travel_direction_in_the_ship_frame() -> void:
	var input: HudInput = _hud_input()
	input.own_velocity = Vector3(0.0, 0.0, -300.0)
	assert_almost_eq(HudLayout.compute(input).drift_dir.y, 1.0, 1e-6, "straight ahead: up the sphere (radar Y = forward)")
	input.own_velocity = Vector3(300.0, 0.0, 0.0)
	var right: Vector3 = HudLayout.compute(input).drift_dir
	assert_almost_eq(right.x, 1.0, 1e-6, "drifting right: to the right")
	input.own_velocity = Vector3(0.0, 0.0, 300.0)
	assert_almost_eq(HudLayout.compute(input).drift_dir.y, -1.0, 1e-6, "backing up: down the sphere, toward the pilot")
	input.own_velocity = Vector3(0.0, 300.0, 0.0)
	assert_almost_eq(HudLayout.compute(input).drift_dir.z, 1.0, 1e-6, "drifting up: out of the screen")


func test_the_drift_sphere_follows_the_ships_orientation_not_the_world() -> void:
	var input: HudInput = _hud_input()
	input.own_velocity = Vector3(0.0, 0.0, -300.0)
	input.own_basis = Basis(Vector3.UP, deg_to_rad(90.0))  # the nose now points to -X: the ship is flying sideways, to its right
	var d: Vector3 = HudLayout.compute(input).drift_dir
	assert_almost_eq(d.x, 1.0, 1e-6)


func test_at_rest_the_sphere_is_drawn_without_an_arrow_and_always_has_a_place() -> void:
	var input: HudInput = _hud_input()
	input.own_velocity = Vector3.ZERO
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.drift_dir, Vector3.ZERO)
	assert_gt(f.drift_radius_px, 0.0)
	for cockpit: bool in [true, false]:
		input.cockpit = cockpit
		var g: HudFrame = HudLayout.compute(input)
		assert_true(Rect2(Vector2.ZERO, VIEW).encloses(Rect2(g.drift_centre - Vector2.ONE * g.drift_radius_px, Vector2.ONE * 2.0 * g.drift_radius_px)),
				"the sphere is on screen (cockpit %s)" % cockpit)
		assert_lt(g.drift_centre.distance_to(g.radar_centre), 1000.0)
		assert_gt(g.drift_centre.distance_to(g.radar_centre), g.radar_radius_px + g.drift_radius_px, "and clear of the radar (cockpit %s)" % cockpit)


func test_the_world_marker_can_be_switched_off() -> void:
	var input: HudInput = _hud_input()
	input.own_velocity = Vector3(0.0, 0.0, -300.0)
	assert_true(HudLayout.compute(input).velocity_visible)
	input.show_velocity_marker = false
	assert_false(HudLayout.compute(input).velocity_visible)
	assert_gt(HudLayout.compute(input).drift_dir.length(), 0.5, "the sphere is unaffected")
