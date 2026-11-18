extends GutTest
## The REF and ALT lines (M7-T73): they wrap to the room beside the drift sphere and never cover another HUD element,
## for the longest texts at every window size and in both views.

const SIZES: Array[Vector2] = [Vector2(960.0, 540.0), Vector2(1920.0, 1080.0), Vector2(2560.0, 1440.0), Vector2(3840.0, 2160.0)]
const NAMES: Array[String] = ["EPSILON III", "BABYLON 5 DOCKING BAY", "JUMPGATE", "NAV POINT ALPHA 12"]


func _hud_input(size: Vector2, cockpit: bool, ref_name: String) -> HudInput:
	var input := HudInput.new()
	input.camera_transform = Transform3D.IDENTITY
	input.projection = Projection.create_perspective(75.0, size.x / size.y, 0.05, 100000.0)
	input.viewport_size = size
	input.cockpit = cockpit
	input.has_reference = true
	input.reference_name = ref_name
	input.reference_position = Vector3(0.0, 0.0, -412345.0)
	input.own_velocity = Vector3(0.0, 0.0, -4500.0)
	input.altitude_m = 412345.0
	input.altitude_body = "EPSILON III"
	return input


func _obstacles(f: HudFrame) -> Dictionary:
	var r: float = f.drift_radius_px
	var rr: float = f.radar_radius_px
	var out: Dictionary = {
		"drift": Rect2(f.drift_centre - Vector2(r, r), Vector2(r, r) * 2.0),
		"radar": Rect2(f.radar_centre - Vector2(rr, rr), Vector2(rr, rr) * 2.0),
		"hull": f.hull_rect, "fuel": f.fuel_rect, "charge": f.charge_rect, "own": f.own_silhouette_rect,
	}
	if f.target_silhouette_rect.size != Vector2.ZERO:
		out["target"] = f.target_silhouette_rect
	return out


func _line_rects(f: HudFrame) -> Array[Rect2]:
	var font: Font = HudPainter.font()
	var s: float = f.scale
	var rects: Array[Rect2] = []
	var y: float = 20.0
	for line: String in HudPainter.readout_lines(f, font, 14.0 * s, f.speed_text_width):
		var w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(14.0 * s)).x
		var x: float = f.speed_pos.x - (w if f.speed_align_right else w * 0.5)
		rects.append(Rect2(Vector2(x, f.speed_pos.y + y * s - 12.0 * s), Vector2(w, 15.0 * s)))
		y += HudPainter.READOUT_LINE_PX
	return rects


func test_the_readout_lines_clear_every_other_element() -> void:
	for size: Vector2 in SIZES:
		for cockpit: bool in [false, true]:
			for ref_name: String in NAMES:
				var f: HudFrame = HudLayout.compute(_hud_input(size, cockpit, ref_name))
				var obstacles: Dictionary = _obstacles(f)
				var rects: Array[Rect2] = _line_rects(f)
				assert_gt(rects.size(), 1, "the long text wraps onto more than one line")
				for rect: Rect2 in rects:
					assert_true(Rect2(Vector2.ZERO, size).encloses(rect), "%s %s %s: on screen" % [size, cockpit, ref_name])
					for key: String in obstacles:
						assert_false(rect.intersects(obstacles[key]), "%s cockpit=%s %s: line %s covers %s" % [size, cockpit, ref_name, rect, key])


func test_a_short_reference_stays_on_one_line() -> void:
	var input: HudInput = _hud_input(Vector2(1920.0, 1080.0), false, "B5")
	input.own_velocity = Vector3.ZERO
	input.altitude_m = NAN
	input.reference_position = Vector3(0.0, 0.0, -90.0)
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(HudPainter.readout_lines(f, HudPainter.font(), 14.0 * f.scale, f.speed_text_width).size(), 1)


func test_the_cockpit_left_screen_wraps_to_its_width() -> void:
	var surface: HudSurface = HudLayout._left_screen(Vector2(512.0, 256.0))
	assert_gt(surface.speed_text_width, 0.0)
