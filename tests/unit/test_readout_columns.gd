extends GutTest
## Where a debug readout's cells go (M8-T21): columns without padding spaces, for a font that is not fixed-width.

const PX: float = 20.0


# A stand-in for the font: every character 10 px wide.
func _measure(text: String) -> float:
	return 10.0 * float(text.length())


func _place(line: String) -> Array[Dictionary]:
	return ReadoutColumns.place(line, PX, _measure)


func _right_edge(cell: Dictionary) -> float:
	return float(cell["x"]) + _measure(cell["text"])


func test_cells_are_cut_at_two_or_more_spaces() -> void:
	assert_eq(ReadoutColumns.cells("VEL   +0.0  -12.5  (body x/y/z)"), PackedStringArray(["VEL", "+0.0", "-12.5", "(body x/y/z)"]))
	assert_eq(ReadoutColumns.cells("ASSIST ON   POD YAW +0.0 °/s"), PackedStringArray(["ASSIST ON", "POD YAW +0.0 °/s"]))
	assert_eq(ReadoutColumns.cells(""), PackedStringArray())
	assert_eq(ReadoutColumns.cells("settings.invert_y = false"), PackedStringArray(["settings.invert_y = false"]))


func test_what_counts_as_a_number() -> void:
	for cell: String in ["+0.0", "-85.2", "42", "1219.000"]:
		assert_true(ReadoutColumns.is_number(cell), cell)
	for cell: String in ["none", "85.2 m/s", "m/s", "", "(36 %)"]:
		assert_false(ReadoutColumns.is_number(cell), cell)


func test_numbers_end_at_their_columns_edge_whatever_their_digits() -> void:
	var small: Array[Dictionary] = _place("VEL   +0.0  +0.0  -1.1  (body x/y/z)")
	var large: Array[Dictionary] = _place("VEL   -111.1  +88.8  -1234.5  (body x/y/z)")
	assert_eq(small.size(), 5)
	for i: int in range(1, 4):
		assert_almost_eq(_right_edge(small[i]), _right_edge(large[i]), 0.001, "column %d" % i)
	assert_almost_eq(_right_edge(small[1]), (ReadoutColumns.LABEL_EM + ReadoutColumns.NUMBER_EM) * PX, 0.001)
	assert_almost_eq(_right_edge(small[2]) - _right_edge(small[1]), ReadoutColumns.NUMBER_EM * PX, 0.001, "columns are evenly apart")
	assert_almost_eq(float(small[4]["x"]), float(large[4]["x"]), 0.001, "and the text after them stays put")


func test_two_readouts_share_their_columns() -> void:
	var speed: Array[Dictionary] = _place("SPD   85.2  m/s")
	var velocity: Array[Dictionary] = _place("VEL   +0.0  +0.0  -85.2  (body x/y/z)")
	assert_almost_eq(_right_edge(speed[1]), _right_edge(velocity[1]), 0.001, "the speed sits over the first velocity")
	assert_eq(float(speed[0]["x"]), 0.0)


func test_text_after_a_label_starts_at_the_value_column() -> void:
	var gpu: Array[Dictionary] = _place("GPU   AMD Radeon RX 6950 XT (RADV NAVI21)")
	var target: Array[Dictionary] = _place("TGT   NAV BRAVO  1243 m  +12.4 m/s")
	assert_almost_eq(float(gpu[1]["x"]), ReadoutColumns.LABEL_EM * PX, 0.001)
	assert_almost_eq(float(target[1]["x"]), ReadoutColumns.LABEL_EM * PX, 0.001)
	assert_gt(float(target[2]["x"]), _right_edge(target[1]), "the next cell clears the one before")
	assert_gt(float(target[3]["x"]), _right_edge(target[2]))


func test_a_line_without_a_label_runs_left_to_right() -> void:
	var placed: Array[Dictionary] = _place("ASSIST ON   POD YAW +0.0 °/s   POD TRIM 0 %")
	assert_eq(placed.size(), 3)
	assert_eq(float(placed[0]["x"]), 0.0)
	for i: int in range(1, 3):
		assert_almost_eq(float(placed[i]["x"]), _right_edge(placed[i - 1]) + ReadoutColumns.GAP_EM * PX, 0.001)


func test_a_number_too_long_for_its_column_is_not_drawn_over_the_one_before() -> void:
	var placed: Array[Dictionary] = _place("POS   -1234567.891  0.000  12.500  m [local]")
	assert_gte(float(placed[1]["x"]), ReadoutColumns.LABEL_EM * PX, "it starts where the column does")
	assert_gt(float(placed[2]["x"]), _right_edge(placed[1]), "and the next number clears it")


func test_a_single_cell_is_drawn_from_the_left() -> void:
	var placed: Array[Dictionary] = _place("settings.invert_y = false")
	assert_eq(placed.size(), 1)
	assert_eq(float(placed[0]["x"]), 0.0)
	assert_true(_place("").is_empty())
