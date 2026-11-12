extends GutTest
## RadialMenu and RadialLayout, pure (M5-T25): the stick picks a slice, "none" sits in the down slice, pages stack and B walks
## back out, and the ring sits vertically centred at one side.

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


func test_none_always_sits_in_the_down_slice() -> void:
	var none: Dictionary = {"label": "NONE", "payload": -1}
	for n: int in 6:
		var slots: Array[Dictionary] = RadialMenu.arrange(_entries(n), none, 6)
		assert_eq(slots.size(), 6, "%d entries: a six-slice ring" % n)
		assert_eq(slots[RadialMenu.down_slice(6)], none, "%d entries: none is straight down" % n)
		var seen: Array[int] = []
		for slot: Dictionary in slots:
			if not slot.is_empty() and slot != none:
				seen.append(int(slot["payload"]))
		assert_eq(seen, range(n), "%d entries: clockwise from the top, in order" % n)
	# Any size of ring that has a none: an even count, none at the bottom.
	for n: int in range(1, 9):
		var slots: Array[Dictionary] = RadialMenu.arrange(_entries(n), none)
		assert_eq(slots.size() % 2, 0, "%d entries: an even ring" % n)
		assert_eq(slots[RadialMenu.down_slice(slots.size())], none)
		assert_eq(RadialMenu.slice_at(Vector2(0.0, -1.0), slots.size()), RadialMenu.down_slice(slots.size()))


func test_without_a_none_the_entries_fill_the_ring_in_order() -> void:
	var slots: Array[Dictionary] = RadialMenu.arrange(_entries(4))
	assert_eq(slots.size(), 4)
	assert_eq(int(slots[2]["payload"]), 2)
	assert_eq(RadialMenu.arrange(_entries(2), {}, 4).size(), 4, "padded with blanks to the ring asked for")
	assert_eq(RadialMenu.down_slice(5), -1, "an odd ring has no slice straight down")


func test_the_highlight_follows_the_stick_and_stays_when_it_centres() -> void:
	menu.open("ROOT", _entries(6))
	assert_eq(menu.highlight(), 0, "it opens on the top slice")
	assert_true(menu.point(_dir(120.0)))
	assert_eq(menu.highlight(), 2)
	assert_false(menu.point(Vector2.ZERO), "a centred stick keeps the last highlight")
	assert_eq(menu.highlight(), 2)
	assert_false(menu.point(_dir(120.0)), "the same slice again is no change")
	assert_eq(int(menu.highlighted()["payload"]), 2)


func test_the_highlight_never_lands_on_a_blank_slice() -> void:
	var none: Dictionary = {"label": "NONE"}
	menu.open("RING", RadialMenu.arrange(_entries(2), none, 6))
	assert_false(menu.point(_dir(120.0)), "slice 2 is blank")
	assert_eq(menu.highlight(), 0)
	assert_true(menu.point(_dir(180.0)))
	assert_eq(menu.highlighted(), none)
	menu.open("EMPTY", [{}, {}] as Array[Dictionary])
	assert_eq(menu.highlight(), -1)
	assert_true(menu.select().is_empty(), "nothing to select on a page of blanks")
	assert_eq(menu.picks, 0)


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
	for count: int in [4, 6]:
		for i: int in count:
			var polygon: PackedVector2Array = RadialLayout.slice_polygon(at, 100.0, 250.0, i, count)
			var label: Vector2 = RadialLayout.label_pos(at, 180.0, i, count)
			assert_true(Geometry2D.is_point_in_polygon(label, polygon), "%d/%d: the label is inside its slice" % [i, count])
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
