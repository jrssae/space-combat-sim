extends GutTest
## The comms menu's pages on the radial framework (architecture §18.22, M5-T46): the wing orders as the first ring, one slice per
## entry (M8-T24), sub-pages on the page stack, B back and out, a select that returns the entry and closes.


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


func test_the_wing_orders_follow_their_keys_one_slice_each() -> void:
	# M8-T24 (D90): the orders of keys 1-4 first, so the D-pad's four directions give them; then DOCK (key 6) and the hold-fire
	# orders (keys 7 and 8). Seven entries, seven slices, no blank.
	var menu := CommsMenu.new()
	menu.set_root_page("WING ORDERS", CommsMenu.wing_orders())
	menu.open()
	var expected: Array = [AiContext.Order.ATTACK_MY_TARGET, AiContext.Order.FORM_ON_ME, AiContext.Order.ENGAGE_AT_WILL,
			AiContext.Order.COVER_ME, CommsMenu.PAYLOAD_DOCK, AiContext.Order.FORM_HOLD_FIRE, AiContext.Order.HOLD_POSITION]
	assert_eq(menu.radial.slice_count(), 7)
	for i: int in expected.size():
		assert_eq(menu.radial.slots()[i]["payload"], expected[i], "entry %d" % i)
	assert_eq(menu.radial.slots()[4]["label"], "DOCK")
	# With no home dock in range the order cannot be given: DOCK leaves the ring and the rest close up.
	var without: Array[Dictionary] = CommsMenu.wing_orders(false)
	assert_eq(without.size(), 6)
	for entry: Dictionary in without:
		assert_ne(entry["label"], "DOCK", "DOCK is left out")
	menu.set_root_page("WING ORDERS", without)
	menu.open()
	assert_eq(menu.radial.slice_count(), 6, "six entries, six slices of 60 degrees")
	assert_eq(menu.radial.slots()[4]["label"], "FORM UP")


func test_the_stick_finds_every_wing_order_wherever_the_ring_puts_it() -> void:
	# The page lists the orders; the ring lays them out, so the stick is pointed at the slice the ring gave each.
	var menu := CommsMenu.new()
	for dock: bool in [true, false]:
		menu.set_root_page("WING ORDERS", CommsMenu.wing_orders(dock))
		for entry: Dictionary in CommsMenu.wing_orders(dock):
			menu.open()
			var count: int = menu.radial.slice_count()
			var at: int = -1
			for i: int in count:
				if menu.radial.slots()[i]["label"] == entry["label"]:
					at = i
			assert_gt(at, -1, "%s is on the ring" % entry["label"])
			var angle: float = RadialMenu.slice_angle(at, count)
			menu.radial.point(Vector2(sin(angle), cos(angle)))
			assert_eq(menu.radial.highlight(), at, "the stick finds %s" % entry["label"])
			var picked: Dictionary = menu.select()
			assert_eq(picked["payload"], entry["payload"], entry["label"])
			assert_false(menu.is_open())
	var hold_fire: Array[Dictionary] = CommsMenu.wing_orders().filter(func(e: Dictionary) -> bool: return e["sub"] == "hold fire")
	assert_eq(hold_fire.size(), 2, "FORM UP and HOLD POSITION (M8-T19)")


func test_select_returns_the_lit_entry_and_closes() -> void:
	var menu: CommsMenu = _menu()
	menu.open()
	menu.radial.point(Vector2(0, -1))
	var entry: Dictionary = menu.select()
	assert_eq(entry["payload"], 2)
	assert_false(menu.is_open())
	assert_eq(menu.closed_by(), &"pick")
	assert_eq(menu.picks(), 1)


func test_a_short_page_has_one_slice_per_entry() -> void:
	# M8-T24 (D90): two replies are two halves, three are thirds; a page is never padded.
	var menu := CommsMenu.new()
	for n: int in range(1, 9):
		menu.set_root_page("REPLIES", _page("r", n))
		menu.open()
		assert_eq(menu.radial.slice_count(), n, "%d entries" % n)
	menu.set_root_page("REPLIES", _page("r", 2))
	menu.open()
	menu.radial.point(Vector2(0, -1))
	assert_eq(menu.radial.highlight(), 1, "two entries: the bottom half is the second")
	menu.set_root_page("REPLIES", _page("r", 10))
	menu.open()
	assert_eq(menu.radial.slice_count(), CommsMenu.MAX_SLOTS, "at most eight")


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
