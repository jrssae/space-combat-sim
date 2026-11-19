extends GutTest
## The readout control of the debug overlay and the FPS counter (M8-T21): the body font, digit slots, columns or a right edge.


func _readout(text: String, px: int = 20) -> ReadoutText:
	var readout := ReadoutText.new()
	readout.font_size = px
	readout.text = text
	add_child_autofree(readout)
	return readout


func test_it_is_as_large_as_its_lines() -> void:
	var readout: ReadoutText = _readout("FPS 60  16.7 ms\nsettings.invert_y = false")
	var font: Font = GameFonts.body()
	assert_eq(readout.line_count(), 2)
	assert_almost_eq(readout.text_height(), font.get_height(20) * 2.0, 0.001)
	var widest: float = maxf(GameFonts.line_width(font, "FPS 60  16.7 ms", 20), GameFonts.line_width(font, "settings.invert_y = false", 20))
	assert_almost_eq(readout.get_minimum_size().x, ceilf(widest), 0.001)
	assert_almost_eq(readout.get_minimum_size().y, ceilf(readout.text_height()), 0.001)


func test_a_changing_number_does_not_change_its_size() -> void:
	var readout: ReadoutText = _readout("FPS 111  11.1 ms")
	var before: Vector2 = readout.get_minimum_size()
	readout.text = "FPS 108  10.8 ms"
	assert_eq(readout.get_minimum_size(), before, "the FPS counter's panel does not twitch")


func test_no_text_no_lines() -> void:
	var readout: ReadoutText = _readout("")
	assert_eq(readout.line_count(), 0)
	assert_eq(readout.get_minimum_size(), Vector2.ZERO)


func test_right_aligned_lines_end_at_the_right_edge() -> void:
	var readout: ReadoutText = _readout("FPS 60  16.7 ms\nx")
	readout.align_right = true
	readout.size = Vector2(400.0, 80.0)
	var font: Font = GameFonts.body()
	for i: int in 2:
		var cell: Dictionary = readout.placed(i)[0]
		assert_almost_eq(float(cell["x"]) + GameFonts.line_width(font, cell["text"], 20), 400.0, 0.001)


func test_with_columns_the_cells_stand_in_readout_columns() -> void:
	var readout: ReadoutText = _readout("VEL   +0.0  +0.0  -85.2  (body x/y/z)\nVEL   -111.1  +88.8  -1.0  (body x/y/z)")
	readout.columns = true
	var font: Font = GameFonts.body()
	var first: Array[Dictionary] = readout.placed(0)
	var second: Array[Dictionary] = readout.placed(1)
	assert_eq(first.size(), 5)
	for i: int in range(1, 4):
		assert_almost_eq(float(first[i]["x"]) + GameFonts.line_width(font, first[i]["text"], 20),
				float(second[i]["x"]) + GameFonts.line_width(font, second[i]["text"], 20), 0.01, "column %d ends in one place" % i)
	assert_eq(readout.get_minimum_size().x, 0.0, "a column readout does not push the layout around it")
