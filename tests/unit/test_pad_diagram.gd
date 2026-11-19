extends GutTest
## PadDiagram (architecture §18, D57, Q15): the legend rows the controller drawing lists, kept apart where several buttons
## sit close together, and the parts it lights for the action in focus.


func _profile(table: Dictionary) -> ControlProfile:
	var profile := ControlProfile.new()
	for action: StringName in table:
		profile.bindings[action] = table[action]
	return profile


func _diagram(table: Dictionary) -> PadDiagram:
	var diagram := PadDiagram.new()
	diagram.size = Vector2(900.0, 300.0)
	add_child_autofree(diagram)
	diagram.set_legend(PadLegend.from_profile(_profile(table)))
	return diagram


func test_rows_are_listed_left_side_then_right_top_to_bottom_by_where_the_button_sits() -> void:
	var diagram: PadDiagram = _diagram({
		&"fire": ["pad:button:0"], &"main_left": ["pad:axis:4+"], &"main_right": ["pad:axis:5+"],
		&"retro_left": ["pad:button:9"], &"toggle_flight_assist": ["pad:button:11"], &"pause": ["pad:button:6"],
	})
	assert_eq(diagram.rows_text(), PackedStringArray([
		"LT  Left main pod", "LB  Left retro", "D-pad up  Flight assist",
		"RT  Right main pod", "Start  Pause", "A  Fire"]))


func test_a_stick_row_names_everything_on_the_stick() -> void:
	var diagram: PadDiagram = _diagram({&"pitch_up": ["pad:axis:3-"], &"yaw_left": ["pad:axis:2-"]})
	assert_eq(diagram.rows_text(), PackedStringArray(["R stick  Pitch / Yaw"]))


func test_the_left_stick_row_also_says_it_points_the_radial_menus() -> void:
	var diagram: PadDiagram = _diagram({&"strafe_left": ["pad:axis:0-"], &"strafe_right": ["pad:axis:0+"]})
	assert_eq(diagram.rows_text(), PackedStringArray(["L stick  Strafe / Menu pointer"]), "T37: the menus' stick is the left one")


func test_an_empty_legend_lists_nothing() -> void:
	assert_eq(_diagram({}).rows_text().size(), 0)


func test_the_action_in_focus_lights_its_buttons() -> void:
	var diagram: PadDiagram = _diagram({&"fire": ["pad:button:0"]})
	assert_eq(diagram.highlighted(), [] as Array[StringName])
	diagram.set_highlight([&"a"] as Array[StringName])
	assert_eq(diagram.highlighted(), [&"a"] as Array[StringName])
	diagram.set_highlight([] as Array[StringName])
	assert_eq(diagram.highlighted().size(), 0)


func test_rows_that_would_overlap_are_pushed_apart() -> void:
	var tops: PackedFloat32Array = PadDiagram.stack_rows(PackedFloat32Array([100.0, 102.0, 104.0]), 20.0, 0.0, 300.0)
	for i: int in range(1, tops.size()):
		assert_gte(tops[i] - tops[i - 1], 20.0 - 0.001, "row %d clears the one above" % i)
	assert_almost_eq(tops[1] - tops[0], 20.0, 0.001)


func test_rows_that_have_room_stay_on_their_buttons() -> void:
	var tops: PackedFloat32Array = PadDiagram.stack_rows(PackedFloat32Array([30.0, 120.0, 220.0]), 20.0, 0.0, 300.0)
	assert_almost_eq(tops[0], 20.0, 0.001, "centred on 30")
	assert_almost_eq(tops[1], 110.0, 0.001)
	assert_almost_eq(tops[2], 210.0, 0.001)


func test_rows_stay_inside_the_panel() -> void:
	var low: PackedFloat32Array = PadDiagram.stack_rows(PackedFloat32Array([280.0, 290.0, 299.0]), 20.0, 0.0, 300.0)
	assert_almost_eq(low[2] + 20.0, 300.0, 0.001, "the last row ends at the bottom")
	assert_gte(low[0], 0.0)
	var high: PackedFloat32Array = PadDiagram.stack_rows(PackedFloat32Array([0.0, 1.0]), 20.0, 0.0, 300.0)
	assert_almost_eq(high[0], 0.0, 0.001, "the first row starts at the top")
	assert_almost_eq(high[1], 20.0, 0.001)


func test_pressed_parts_are_kept_apart_from_the_lit_ones() -> void:
	var diagram: PadDiagram = _diagram({&"fire": ["pad:button:0"]})
	diagram.set_highlight([&"a"] as Array[StringName])
	diagram.set_pressed([&"x", &"rs"] as Array[StringName])
	assert_eq(diagram.pressed(), [&"x", &"rs"] as Array[StringName], "M8-T22: what the player holds, bound or not")
	assert_eq(diagram.highlighted(), [&"a"] as Array[StringName], "the action in focus stays lit")
	diagram.set_pressed([] as Array[StringName])
	assert_eq(diagram.pressed(), [] as Array[StringName])


func test_a_pressed_part_is_drawn_brighter_than_a_lit_one() -> void:
	var diagram: PadDiagram = _diagram({&"fire": ["pad:button:0"]})
	var bound: Array[StringName] = [&"a"]
	diagram.set_highlight([&"a"] as Array[StringName])
	assert_eq(diagram._edge_of(&"a", bound), PadDiagram.LIT)
	diagram.set_pressed([&"a"] as Array[StringName])
	assert_eq(diagram._edge_of(&"a", bound), PadDiagram.PRESSED, "the press shows over the focus highlight")
	assert_gt(diagram._fill_of(&"a", bound).a, 0.8)
	assert_eq(diagram._edge_of(&"y", bound), Color(PadDiagram.LINE.r, PadDiagram.LINE.g, PadDiagram.LINE.b, 0.4), "the rest is as before")
