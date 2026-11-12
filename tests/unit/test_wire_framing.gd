extends GutTest
## WireFraming and TargetPreviewLayout, pure (architecture §18.20, M5-T43): the preview's view holds a hull through its whole
## turn, and the panel sits vertically centred at the side opposite the ring.

const FIGHTER := AABB(Vector3(-8.5, -0.8, -4.3), Vector3(17.0, 2.0, 7.2))
const TANKER := AABB(Vector3(-25.7, -14.7, -137.2), Vector3(51.3, 31.3, 258.5))


# The half extents on screen of `bounds` turned by `yaw` about its centre, seen from `WireFraming.ELEVATION_DEG` above.
func _on_screen(bounds: AABB, yaw: float) -> Vector2:
	var view := Basis(Vector3.RIGHT, -deg_to_rad(WireFraming.ELEVATION_DEG)).inverse()
	var reach := Vector2.ZERO
	for i: int in 8:
		var corner: Vector3 = Basis(Vector3.UP, yaw) * (bounds.get_endpoint(i) - bounds.get_center())
		var seen: Vector3 = view * corner
		reach = Vector2(maxf(reach.x, absf(seen.x)), maxf(reach.y, absf(seen.y)))
	return reach


func test_the_hull_turns_fifteen_degrees_a_second_about_its_up_axis() -> void:
	assert_almost_eq(rad_to_deg(WireFraming.yaw_at(0.0)), WireFraming.START_YAW_DEG, 1e-4)
	assert_almost_eq(rad_to_deg(WireFraming.yaw_at(2.0) - WireFraming.yaw_at(0.0)), 30.0, 1e-4)
	assert_almost_eq(WireFraming.TURN_DEG_S, 15.0, 1e-6)
	assert_almost_eq(WireFraming.yaw_at(24.0), WireFraming.yaw_at(0.0), 1e-4, "a full turn in 24 s, and the angle wraps")


func test_the_view_holds_a_fighter_and_a_tanker_at_every_angle_of_the_turn() -> void:
	for bounds: AABB in [FIGHTER, TANKER]:
		for aspect: float in [1.0, 1.68, 0.6]:
			var height: float = WireFraming.view_height(bounds, aspect)
			var widest := Vector2.ZERO
			for step: int in 72:
				var reach: Vector2 = _on_screen(bounds, deg_to_rad(5.0 * float(step)))
				widest = Vector2(maxf(widest.x, reach.x), maxf(widest.y, reach.y))
				assert_lte(reach.y * 2.0, height * WireFraming.FILL + 1e-3, "inside the view's height")
				assert_lte(reach.x * 2.0, height * aspect * WireFraming.FILL + 1e-3, "inside its width")
			# And it fills the view along one axis at some angle: neither hull is a speck.
			var fill: float = maxf(widest.x * 2.0 / (height * aspect), widest.y * 2.0 / height)
			assert_gt(fill, 0.8, "the hull fills the panel")


func test_the_camera_looks_down_from_twenty_degrees_and_stands_clear_of_the_hull() -> void:
	var at: Vector3 = WireFraming.camera_offset(10.0)
	assert_almost_eq(at.length(), 10.0, 1e-4)
	assert_almost_eq(rad_to_deg(asin(at.y / 10.0)), 20.0, 1e-3)
	assert_almost_eq(at.x, 0.0, 1e-6)
	assert_gt(at.z, 0.0)
	assert_almost_eq(WireFraming.radius(TANKER), TANKER.size.length() * 0.5, 1e-4)
	assert_gt(WireFraming.view_height(AABB(), 1.0), 0.0, "an empty box still gives a view")


func test_the_panel_sits_vertically_centred_at_the_side_opposite_the_ring() -> void:
	for view: Vector2 in [Vector2(1920, 1080), Vector2(3840, 2160), Vector2(1200, 675), Vector2(1440, 1080), Vector2(800, 1080)]:
		var panel: Rect2 = TargetPreviewLayout.panel_rect(view)
		assert_almost_eq(panel.get_center().y, view.y * 0.5, 0.01, "vertically centred at %s" % view)
		assert_gte(panel.position.x, view.x * 0.5 - 0.01, "in the right half at %s" % view)
		assert_lte(panel.end.x, view.x + 0.01)
		var ring_edge: float = RadialLayout.centre(view).x + RadialLayout.outer_radius(view)
		assert_lte(ring_edge, panel.position.x + 0.01, "clear of the ring at %s" % view)
		var mirrored: Rect2 = TargetPreviewLayout.panel_rect(view, true)
		assert_almost_eq(mirrored.get_center().x, view.x - panel.get_center().x, 0.01, "the ring at the right puts it at the left")
	var hd: Rect2 = TargetPreviewLayout.panel_rect(Vector2(1920, 1080))
	assert_eq(hd.size, TargetPreviewLayout.PANEL_PX)
	assert_almost_eq(hd.get_center().x, 1920.0 - RadialLayout.CENTRE_X_PX, 0.01, "where the ring would be at the other side")
	assert_eq(TargetPreviewLayout.panel_rect(Vector2(3840, 2160)).size, TargetPreviewLayout.PANEL_PX * 2.0, "it scales with the UI at 4K")


func test_the_drawing_and_the_rows_stay_inside_the_panel() -> void:
	var panel: Rect2 = TargetPreviewLayout.panel_rect(Vector2(1920, 1080))
	var wire: Rect2 = TargetPreviewLayout.wire_rect(panel)
	assert_true(panel.encloses(wire))
	assert_gte(wire.size.y, 256.0, "the drawing is at least 256 px at 1080 lines")
	assert_lt(wire.end.y, panel.position.y + TargetPreviewLayout.TITLE_Y_PX - 29.0, "the title is under the drawing")
	var last_row: float = TargetPreviewLayout.FIRST_ROW_Y_PX + 3.0 * TargetPreviewLayout.ROW_STEP_PX
	assert_lt(last_row, TargetPreviewLayout.PANEL_PX.y - TargetPreviewLayout.PAD_PX, "four rows fit")
	var bar: Rect2 = TargetPreviewLayout.bar_rect(panel, panel.position.y + TargetPreviewLayout.FIRST_ROW_Y_PX)
	assert_true(panel.encloses(bar))
	assert_gt(bar.size.x, 200.0)
