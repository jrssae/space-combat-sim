extends GutTest
## The comms menu's model (architecture §18 D54, M5-T07): pages of four entries, the 4 s close timer on sim time, picks that
## return the entry, and the wing orders as the first page.


func _page(prefix: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in 4:
		out.append({"label": "%s%d" % [prefix, i], "payload": i})
	return out


func test_it_starts_closed_and_opens_on_the_first_page_with_the_full_timer() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("ORDERS", _page("o"))
	assert_false(menu.is_open())
	menu.open()
	assert_true(menu.is_open())
	assert_eq(menu.page_title(), "ORDERS")
	assert_eq(menu.entries().size(), 4)
	assert_almost_eq(menu.remaining_s(), CommsMenu.CLOSE_S, 1e-6)
	assert_eq(CommsMenu.CLOSE_S, 4.0)


func test_it_closes_itself_after_four_seconds_of_ticks() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("ORDERS", _page("o"))
	menu.open()
	menu.tick(3.9)
	assert_true(menu.is_open())
	assert_almost_eq(menu.remaining_s(), 0.1, 1e-6)
	menu.tick(0.1)
	assert_false(menu.is_open())
	assert_eq(menu.closed_by, &"timeout")


func test_a_closed_menu_ignores_time() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("ORDERS", _page("o"))
	menu.tick(10.0)
	assert_false(menu.is_open())
	assert_eq(menu.remaining_s(), 0.0)


func test_a_pick_returns_the_entry_and_closes_the_menu() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("ORDERS", _page("o"))
	menu.open()
	var entry: Dictionary = menu.pick(2)
	assert_eq(entry["label"], "o2")
	assert_eq(entry["payload"], 2)
	assert_false(menu.is_open())
	assert_eq(menu.closed_by, &"pick")
	assert_eq(menu.picks, 1)


func test_a_pick_while_closed_or_on_an_empty_slot_gives_nothing_and_changes_nothing() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("SHORT", [{"label": "only", "payload": 7}] as Array[Dictionary])
	assert_true(menu.pick(0).is_empty(), "closed")
	menu.open()
	assert_true(menu.pick(3).is_empty(), "no entry there")
	assert_true(menu.pick(-1).is_empty())
	assert_true(menu.is_open())
	assert_eq(menu.picks, 0)


func test_close_ends_it_and_a_reopen_starts_over_on_the_root_page() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("ORDERS", _page("o"))
	menu.open()
	menu.push_page("REPLIES", _page("r"))
	assert_eq(menu.page_title(), "REPLIES")
	menu.close()
	assert_false(menu.is_open())
	assert_eq(menu.closed_by, &"close")
	menu.open()
	assert_eq(menu.page_title(), "ORDERS")
	assert_almost_eq(menu.remaining_s(), CommsMenu.CLOSE_S, 1e-6)


func test_a_later_mission_can_push_a_page_of_replies_and_pop_back() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("ORDERS", _page("o"))
	menu.open()
	menu.tick(3.0)
	menu.push_page("REPLIES", _page("r"))
	assert_eq(menu.entries()[1]["label"], "r1")
	assert_almost_eq(menu.remaining_s(), CommsMenu.CLOSE_S, 1e-6, "a new page gives the time to read it")
	assert_eq(menu.page_count(), 2)
	menu.pop_page()
	assert_eq(menu.page_title(), "ORDERS")
	menu.pop_page()
	assert_eq(menu.page_count(), 1, "the root page stays")


func test_a_page_holds_at_most_four_entries() -> void:
	var menu := CommsMenu.new()
	var five: Array[Dictionary] = _page("x")
	five.append({"label": "fifth", "payload": 4})
	menu.set_root_page("TOO MANY", five)
	assert_eq(menu.entries().size(), CommsMenu.SLOTS)
	assert_push_warning_count(1)


func test_the_wing_orders_page_has_the_four_orders_in_the_order_of_the_keys() -> void:
	var menu := CommsMenu.new()
	menu.set_root_page("WING", CommsMenu.wing_orders())
	menu.open()
	var payloads: Array = []
	for entry: Dictionary in menu.entries():
		payloads.append(entry["payload"])
	assert_eq(payloads, [AiContext.Order.ATTACK_MY_TARGET, AiContext.Order.FORM_ON_ME, AiContext.Order.ENGAGE_AT_WILL,
			AiContext.Order.COVER_ME])
	assert_eq(menu.entries()[0]["label"], "ATTACK MY TARGET")
