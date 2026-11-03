extends GutTest
## CommsLayout (architecture §18 D53, M5-T06): where the subtitle plate goes and how big its text is. It stays legible at 960x540
## and 1920x1080, inside the window, centred at the bottom, and clear of the chase view's bottom-corner gauges and radar.

const SIZES: Array[Vector2] = [Vector2(960.0, 540.0), Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(3840.0, 2160.0)]


# About what the HUD font makes of three wrapped lines.
func _lines(layout: CommsLayout, count: int) -> float:
	return float(count) * float(layout.text_px) * 1.2


# --- legibility ------------------------------------------------------------------------------------------------------------


func test_text_never_falls_under_the_legible_floor_and_scales_up_with_the_window() -> void:
	var small: CommsLayout = CommsLayout.compute(Vector2(960.0, 540.0))
	var full: CommsLayout = CommsLayout.compute(Vector2(1920.0, 1080.0))
	assert_gte(small.text_px, 16, "960x540: still readable")
	assert_gte(small.callsign_px, 14)
	assert_gte(full.text_px, 24, "1080p: a TV-distance subtitle")
	assert_gt(full.text_px, small.text_px)
	assert_gte(CommsLayout.compute(Vector2(3840.0, 2160.0)).text_px, 2 * full.text_px - 2, "and it grows with the window")


func test_a_line_wraps_to_a_comfortable_width_at_every_size() -> void:
	var chars_per_line: Array[float] = []
	for size: Vector2 in SIZES:
		var layout: CommsLayout = CommsLayout.compute(size)
		chars_per_line.append(layout.text_width() / (float(layout.text_px) * CommsLayout.MONO_ADVANCE))
	for n: float in chars_per_line:
		assert_between(n, 40.0, 80.0, "a monospace HUD font fits 40 to 80 characters on a line")


# --- placement -------------------------------------------------------------------------------------------------------------


func test_the_plate_sits_inside_the_window_centred_at_the_bottom() -> void:
	for size: Vector2 in SIZES:
		for cockpit: bool in [false, true]:
			var layout: CommsLayout = CommsLayout.compute(size, cockpit)
			var plate: Rect2 = layout.plate(_lines(layout, 3))
			var label: String = "%s cockpit %s" % [size, cockpit]
			assert_true(Rect2(Vector2.ZERO, size).encloses(plate), "%s: inside the window" % label)
			assert_almost_eq(plate.get_center().x, size.x * 0.5, 0.5, "%s: centred" % label)
			assert_gt(plate.position.y, size.y * 0.55, "%s: in the lower part of the picture" % label)
			assert_gt(size.y - plate.end.y, 0.0, "%s: clear of the very edge" % label)


func test_a_degenerate_window_keeps_the_plate_off_the_top_edge() -> void:
	var layout: CommsLayout = CommsLayout.compute(Vector2(64.0, 64.0))
	assert_gte(layout.plate(_lines(layout, 12)).position.y, 0.0)
	assert_gt(layout.text_width(), 0.0)


func test_a_taller_text_grows_the_plate_upwards_from_a_fixed_bottom() -> void:
	var layout: CommsLayout = CommsLayout.compute(Vector2(1920.0, 1080.0))
	var one: Rect2 = layout.plate(_lines(layout, 1))
	var three: Rect2 = layout.plate(_lines(layout, 3))
	assert_eq(one.end.y, three.end.y)
	assert_gt(three.size.y, one.size.y)
	assert_eq(one.size.x, three.size.x)


func test_the_plate_is_clear_of_the_chase_views_corner_gauges_and_radar() -> void:
	for size: Vector2 in [Vector2(960.0, 540.0), Vector2(1920.0, 1080.0)]:
		var input := HudInput.new()
		input.viewport_size = size
		input.cockpit = false
		var frame: HudFrame = HudLayout.compute(input)
		var layout: CommsLayout = CommsLayout.compute(size, false)
		var plate: Rect2 = layout.plate(_lines(layout, 3))
		var radar := Rect2(frame.radar_centre - Vector2.ONE * frame.radar_radius_px, Vector2.ONE * frame.radar_radius_px * 2.0)
		for rect: Rect2 in [frame.hull_rect, frame.fuel_rect, frame.charge_rect, radar]:
			assert_false(plate.intersects(rect), "%s: the plate %s keeps off %s" % [size, plate, rect])


# --- colour ----------------------------------------------------------------------------------------------------------------


func test_a_speaker_is_coloured_by_how_the_player_regards_their_faction() -> void:
	assert_eq(CommsLayout.faction_color(Factions.EARTH_ALLIANCE), Factions.FRIENDLY_COLOR)
	assert_eq(CommsLayout.faction_color(Factions.RAIDERS), Factions.HOSTILE_COLOR)
	assert_eq(CommsLayout.faction_color(Factions.NEUTRAL), Factions.NEUTRAL_COLOR)
	assert_eq(CommsLayout.faction_color(&"somebody_new"), Factions.NEUTRAL_COLOR, "an unknown faction reads as neutral")
	assert_eq(CommsLayout.faction_color(Factions.RAIDERS, Factions.RAIDERS), Factions.FRIENDLY_COLOR, "from the other side")
