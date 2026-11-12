extends GutTest
## The comms menu's pages on the radial framework (architecture §18.22, M5-T46): the wing orders as the first ring on the four
## compass slices, sub-pages on the page stack, B back and out, a select that returns the entry and closes.


func _page(prefix: String, n: int = 4) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in n:
		out.append({"label": "%s%d" % [prefix, i], "payload": i})
	return out


func _menu() -> CommsMenu:
	var menu := CommsMenu.new()
	menu.set_root_page("ORDERS", _page("o"))
	return menu


func test_it_starts_closed_and_opens_on_the_first_page() -> void:
	var menu: CommsMenu = _menu()
	assert_false(menu.is_open())
	menu.open()
	assert_true(menu.is_open())
	assert_eq(menu.page_title(), "ORDERS")
	assert_eq(menu.page_count(), 1)
	assert_eq(menu.radial.slice_count(), 4)
	assert_eq(menu.radial.highlight(), 0, "the first entry is lit until the stick points")


func test_without_a_root_page_it_does_not_open() -> void:
	var menu := CommsMenu.new()
	menu.open()
	assert_false(menu.is_open())


func test_the_wing_orders_sit_up_right_down_left_in_the_order_of_keys_1_to_4() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("WING ORDERS", CommsMenu.wing_orders())
	menu.open()
	var expected: Array[int] = [AiContext.Order.ATTACK_MY_TARGET, AiContext.Order.FORM_ON_ME, AiContext.Order.ENGAGE_AT_WILL,
			AiContext.Order.COVER_ME]
	var up_right_down_left: Array[Vector2] = [Vector2(0, 1), Vector2.RIGHT, Vector2(0, -1), Vector2.LEFT]
	for i: int in 4:
		menu.radial.point(up_right_down_left[i])
		assert_eq(menu.radial.highlighted()["payload"], expected[i], "slice %d" % i)


func test_select_returns_the_lit_entry_and_closes() -> void:
	var menu: CommsMenu = _menu()
	menu.open()
	menu.radial.point(Vector2(0, -1))
	var entry: Dictionary = menu.select()
	assert_eq(entry["payload"], 2)
	assert_false(menu.is_open())
	assert_eq(menu.closed_by(), &"pick")
	assert_eq(menu.picks(), 1)


func test_a_short_page_pads_to_four_slices_and_the_highlight_skips_blanks() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("REPLIES", _page("r", 2))
	menu.open()
	assert_eq(menu.radial.slice_count(), 4)
	menu.radial.point(Vector2(0, -1))
	assert_eq(menu.radial.highlight(), 0, "a blank slice is never lit")


func test_an_entry_with_a_page_pushes_it_and_b_comes_back() -> void:
	var menu := CommsMenu.new()
	var entries: Array[Dictionary] = _page("o")
	entries[1]["page"] = {"title": "SUB", "entries": _page("s", 3)}
	menu.set_root_page("ORDERS", entries)
	menu.open()
	menu.radial.point(Vector2.RIGHT)
	assert_true(menu.select().is_empty(), "opening a page returns nothing")
	assert_true(menu.is_open())
	assert_eq(menu.page_count(), 2)
	assert_eq(menu.page_title(), "SUB")
	assert_eq(menu.picks(), 1)
	assert_true(menu.back(), "B goes back a page")
	assert_eq(menu.page_title(), "ORDERS")
	assert_false(menu.back(), "B from the first page closes")
	assert_false(menu.is_open())
	assert_eq(menu.closed_by(), &"back")


func test_a_pick_on_a_sub_page_closes_the_whole_stack() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("ORDERS", _page("o"))
	menu.open()
	menu.push_page("REPLIES", _page("r"))
	menu.radial.point(Vector2.LEFT)
	assert_eq(menu.select()["label"], "r3")
	assert_false(menu.is_open())
	assert_eq(menu.page_count(), 0)


func test_open_again_starts_on_the_first_page() -> void:
	var menu: CommsMenu = _menu()
	menu.open()
	menu.push_page("REPLIES", _page("r"))
	menu.close()
	menu.open()
	assert_eq(menu.page_count(), 1)
	assert_eq(menu.page_title(), "ORDERS")


func test_a_closed_menu_has_nothing_to_select() -> void:
	assert_true(_menu().select().is_empty())
