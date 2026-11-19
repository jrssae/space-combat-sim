extends GutTest
## RadialMenu and RadialLayout, pure (M5-T25): the stick picks a slice, "none" sits in the down slice, pages stack and B walks
## back out, and the ring sits vertically centred at one side. M8-T24 (D90): one equal slice per entry for 1 to 8 entries, no
## blank slices.

var menu: RadialMenu


func before_each() -> void:
	menu = RadialMenu.new()


func _entries(n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in n:
		out.append({"label": "E%d" % i, "payload": i})
	return out


func _dir(deg: float, length: float = 1.0) -> Vector2:
	# Clockwise from straight up, as the slices are numbered.
	return Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg))) * length


func test_slices_are_numbered_clockwise_from_the_top() -> void:
	for i: int in 6:
		assert_eq(RadialMenu.slice_at(_dir(60.0 * float(i)), 6), i, "slice %d at %d degrees" % [i, 60 * i])
	assert_eq(RadialMenu.slice_at(_dir(29.0), 6), 0)
	assert_eq(RadialMenu.slice_at(_dir(31.0), 6), 1)
	assert_eq(RadialMenu.slice_at(_dir(-29.0), 6), 0)
	assert_eq(RadialMenu.slice_at(_dir(-31.0), 6), 5)
	assert_eq(RadialMenu.slice_at(Vector2(0.0, -1.0), 6), 3, "the stick pulled down points at the down slice")
	for i: int in 4:
		assert_eq(RadialMenu.slice_at(_dir(90.0 * float(i)), 4), i)


func test_a_stick_near_the_centre_points_at_nothing() -> void:
	assert_eq(RadialMenu.slice_at(Vector2.ZERO, 6), -1)
	assert_eq(RadialMenu.slice_at(_dir(60.0, RadialMenu.POINT_THRESHOLD - 0.01), 6), -1)
	assert_eq(RadialMenu.slice_at(_dir(60.0, RadialMenu.POINT_THRESHOLD + 0.01), 6), 1)
	assert_eq(RadialMenu.slice_at(Vector2.UP, 0), -1, "no slices, no slice")


func test_a_direction_on_a_boundary_takes_the_slice_nearer_the_top() -> void:
	# The arrow keys: a plain right or left sits on a boundary of a six-slice ring.
	assert_eq(RadialMenu.slice_at(Vector2(1.0, 0.0), 6), 1, "right: the upper right slice")
	assert_eq(RadialMenu.slice_at(Vector2(-1.0, 0.0), 6), 5, "left: the upper left slice")
	assert_eq(RadialMenu.slice_at(Vector2(1.0, -1.0).normalized(), 6), 2, "down and right: the lower right slice")
	assert_eq(RadialMenu.slice_at(Vector2(-1.0, -1.0).normalized(), 6), 4)
	assert_eq(RadialMenu.slice_at(Vector2(1.0, 1.0).normalized(), 4), 0, "a diagonal on a four-slice ring: the top")
	assert_eq(RadialMenu.slice_at(Vector2(1.0, -1.0).normalized(), 4), 1, "between right and down: right is nearer the top")


func test_one_to_eight_entries_lay_out_equal_slices_clockwise_from_the_top() -> void:
	for count: int in range(1, 9):
		var width: float = 360.0 / float(count)
		menu.open("RING", _entries(count))
		assert_eq(menu.slice_count(), count, "%d entries: %d slices" % [count, count])
		for i: int in count:
			assert_almost_eq(rad_to_deg(RadialMenu.slice_angle(i, count)), width * float(i), 1e-3,
					"%d entries: slice %d centred %.1f degrees clockwise from the top" % [count, i, width * float(i)])
			assert_eq(int(menu.slots()[i]["payload"]), i, "%d entries: page order clockwise" % count)
	assert_almost_eq(rad_to_deg(RadialMenu.slice_angle(1, 3)), 120.0, 1e-3, "three entries: 120 degrees each")
	assert_almost_eq(rad_to_deg(RadialMenu.slice_angle(1, 5)), 72.0, 1e-3, "five entries: 72 degrees each")


func test_the_stick_picks_the_nearest_slice_up_to_its_edges_for_every_count() -> void:
	for count: int in range(1, 9):
		var width: float = 360.0 / float(count)
		for i: int in count:
			var mid: float = width * float(i)
			assert_eq(RadialMenu.slice_at(_dir(mid), count), i, "%d: the centre of slice %d" % [count, i])
			assert_eq(RadialMenu.slice_at(_dir(mid - width * 0.5 + 0.2), count), i, "%d: just inside slice %d's leading edge" % [count, i])
			assert_eq(RadialMenu.slice_at(_dir(mid + width * 0.5 - 0.2), count), i, "%d: just inside slice %d's trailing edge" % [count, i])
			if count > 1:
				assert_eq(RadialMenu.slice_at(_dir(mid + width * 0.5 + 0.2), count), (i + 1) % count,
						"%d: just past slice %d is the next" % [count, i])
	for deg: float in [0.0, 90.0, 180.0, 270.0, 359.0]:
		assert_eq(RadialMenu.slice_at(_dir(deg), 1), 0, "a ring of one: every direction is its entry")


func test_the_arrow_keys_mean_one_slice_on_every_count() -> void:
	# Straight down on an odd ring is a boundary of two slices as far from the top: the later one, where "none" sits.
	assert_eq(RadialMenu.slice_at(Vector2(0.0, -1.0), 3), 2)
	assert_eq(RadialMenu.slice_at(Vector2(0.0, -1.0), 5), 3)
	assert_eq(RadialMenu.slice_at(Vector2(0.0, -1.0), 7), 4)
	assert_eq(RadialMenu.slice_at(Vector2(0.0, -1.0), 1), 0)
	assert_eq(RadialMenu.slice_at(Vector2(1.0, 0.0), 2), 0, "right on a ring of two: the boundary takes the top")
	assert_eq(RadialMenu.slice_at(Vector2(0.0, -1.0), 2), 1)
	assert_eq(RadialMenu.slice_at(Vector2(1.0, 0.0), 3), 1, "right on a ring of three: the lower right slice")
	assert_eq(RadialMenu.slice_at(Vector2(-1.0, 0.0), 3), 2)


func test_none_sits_in_the_down_slice_and_the_ring_has_no_blanks() -> void:
	var none: Dictionary = {"label": "NONE", "payload": -1}
	for n: int in range(0, 8):
		var slots: Array[Dictionary] = RadialMenu.arrange(_entries(n), none)
		assert_eq(slots.size(), n + 1, "%d entries and none: %d slices" % [n, n + 1])
		var at: int = slots.find(none)
		assert_eq(at, RadialMenu.none_slice(n + 1))
		assert_eq(RadialMenu.slice_at(Vector2(0.0, -1.0), slots.size()), at, "%d entries: the stick pulled down finds none" % n)
		if (n + 1) % 2 == 0:
			assert_almost_eq(rad_to_deg(RadialMenu.slice_angle(at, n + 1)), 180.0, 1e-3, "%d entries: none is straight down" % n)
		var seen: Array[int] = []
		for slot: Dictionary in slots:
			assert_false(slot.is_empty(), "%d entries: no blank slice" % n)
			if slot != none:
				seen.append(int(slot["payload"]))
		assert_eq(seen, range(n), "%d entries: clockwise from the top, in order" % n)
	assert_eq(RadialMenu.arrange(_entries(1), none)[0]["label"], "E0", "the first entry stays at the top")


func test_unavailable_entries_leave_the_ring() -> void:
	var page: Array[Dictionary] = _entries(4)
	page.insert(2, {})
	page.append({})
	assert_eq(RadialMenu.arrange(page).size(), 4, "arrange leaves blanks out")
	menu.open("RING", page)
	assert_eq(menu.slice_count(), 4, "so does the ring: one slice per entry present")
	for i: int in 4:
		assert_eq(int(menu.slots()[i]["payload"]), i, "the rest close up in page order")
	menu.open("EMPTY", [{}, {}] as Array[Dictionary])
	assert_eq(menu.slice_count(), 0)
	assert_eq(menu.highlight(), -1)
	assert_true(menu.select().is_empty(), "nothing to select on an empty page")
	assert_eq(menu.picks, 0)


func test_entries_are_reached_by_their_place_in_page_order() -> void:
	# The D-pad and the numbered keys (M8-T24): the owner highlights entry n and selects it.
	for count: int in range(1, 9):
		menu.open("RING", _entries(count))
		for i: int in 8:
			assert_eq(menu.has_entry(i), i < count, "%d entries: entry %d" % [count, i])
		menu.set_highlight(count - 1)
		assert_eq(int(menu.select()["payload"]), count - 1)
	assert_false(menu.has_entry(-1))
	menu.close()
	assert_false(menu.has_entry(0), "closed: no entries")


func test_the_highlight_follows_the_stick_and_stays_when_it_centres() -> void:
	menu.open("ROOT", _entries(6))
	assert_eq(menu.highlight(), 0, "it opens on the top slice")
	assert_true(menu.point(_dir(120.0)))
	assert_eq(menu.highlight(), 2)
	assert_false(menu.point(Vector2.ZERO), "a centred stick keeps the last highlight")
	assert_eq(menu.highlight(), 2)
	assert_false(menu.point(_dir(120.0)), "the same slice again is no change")
	assert_eq(int(menu.highlighted()["payload"]), 2)


func test_pages_stack_and_back_walks_out() -> void:
	menu.open("ROOT", _entries(6), Color.GREEN)
	menu.point(_dir(60.0))
	assert_eq(int(menu.select()["payload"]), 1)
	assert_true(menu.is_open(), "select leaves the closing to the owner")
	menu.push("SECOND", _entries(3), Color.RED)
	assert_eq(menu.depth(), 2)
	assert_eq(menu.title(), "SECOND")
	assert_eq(menu.color(), Color.RED)
	assert_eq(menu.highlight(), 0, "a new page opens on its first entry")
	assert_true(menu.back(), "back from the second ring: still open")
	assert_eq(menu.title(), "ROOT")
	assert_eq(menu.highlight(), 1, "the first ring remembers where it was")
	assert_false(menu.back(), "back from the first ring closes")
	assert_false(menu.is_open())
	assert_eq(menu.closed_by, &"back")
	assert_eq(menu.depth(), 0)
	assert_eq(menu.slice_count(), 0)
	assert_eq(menu.highlight(), -1)


func test_closed_it_ignores_everything() -> void:
	assert_false(menu.point(Vector2.UP))
	assert_true(menu.select().is_empty())
	assert_false(menu.back())
	menu.push("X", _entries(2))
	assert_false(menu.is_open(), "a push does not open it")
	menu.open("ROOT", _entries(2))
	menu.close(&"pick")
	assert_eq(menu.closed_by, &"pick")
	menu.open("ROOT", _entries(2))
	assert_eq(menu.closed_by, &"", "opening forgets the last close")


func test_the_ring_is_vertically_centred_at_the_left_side() -> void:
	for size: Vector2 in [Vector2(1920.0, 1080.0), Vector2(3840.0, 2160.0), Vector2(960.0, 540.0), Vector2(640.0, 1080.0)]:
		var c: Vector2 = RadialLayout.centre(size)
		var r: float = RadialLayout.outer_radius(size)
		assert_almost_eq(c.y, size.y * 0.5, 1e-3, "%s: vertically centred" % size)
		assert_gt(c.x - r, 0.0, "%s: the ring is inside the left edge" % size)
		assert_lt(c.x + r, size.x * 0.5 + 1.0, "%s: and clear of the middle of the screen" % size)
		assert_lt(c.y + r, size.y, "%s: inside the bottom" % size)
		var mirrored: Vector2 = RadialLayout.centre(size, true)
		assert_almost_eq(mirrored.x, size.x - c.x, 1e-3, "%s: the right side mirrors it" % size)
	assert_almost_eq(RadialLayout.outer_radius(Vector2(3840.0, 2160.0)), 2.0 * RadialLayout.outer_radius(Vector2(1920.0, 1080.0)), 1e-3,
			"it scales with the window's height")


func test_a_slice_polygon_holds_its_label_and_spans_hub_to_rim() -> void:
	var at := Vector2(400.0, 500.0)
	for count: int in range(1, 9):
		for i: int in count:
			var polygon: PackedVector2Array = RadialLayout.slice_polygon(at, 100.0, 250.0, i, count)
			var label: Vector2 = RadialLayout.label_pos(at, 180.0, i, count)
			assert_true(Geometry2D.is_point_in_polygon(label, polygon), "%d/%d: the label is inside its slice" % [i, count])
			assert_false(Geometry2D.triangulate_polygon(polygon).is_empty(), "%d/%d: one simple polygon, drawable" % [i, count])
			if count > 1:
				var other: Vector2 = RadialLayout.label_pos(at, 180.0, (i + 1) % count, count)
				assert_false(Geometry2D.is_point_in_polygon(other, polygon), "%d/%d: the next label is not" % [i, count])
			for p: Vector2 in polygon:
				var d: float = p.distance_to(at)
				assert_between(d, 100.0 - 1e-2, 250.0 + 1e-2)
	assert_almost_eq(RadialLayout.label_pos(at, 180.0, 0, 6), at + Vector2(0.0, -180.0), Vector2(1e-3, 1e-3), "slice 0 is straight up")
	assert_almost_eq(RadialLayout.label_pos(at, 180.0, 3, 6), at + Vector2(0.0, 180.0), Vector2(1e-3, 1e-3), "slice 3 straight down")
	var spoke: PackedVector2Array = RadialLayout.spoke(at, 100.0, 250.0, 0, 6)
	assert_almost_eq(spoke[0].distance_to(at), 100.0, 1e-3)
	assert_almost_eq(spoke[1].distance_to(at), 250.0, 1e-3)
	assert_lt(spoke[1].x, at.x, "slice 0's leading spoke is to its left")


func test_the_pointer_follows_the_stick_inside_the_hub() -> void:
	var at := Vector2(400.0, 500.0)
	assert_eq(RadialLayout.pointer_tip(at, 100.0, Vector2.ZERO), at)
	var up: Vector2 = RadialLayout.pointer_tip(at, 100.0, Vector2(0.0, 1.0))
	assert_lt(up.y, at.y, "stick up is up the screen")
	assert_lt(up.distance_to(at), 100.0, "inside the hub")
	assert_almost_eq(RadialLayout.pointer_tip(at, 100.0, Vector2(3.0, 0.0)).distance_to(at), up.distance_to(at), 1e-3, "clamped")
