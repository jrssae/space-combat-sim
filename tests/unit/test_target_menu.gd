extends GutTest
## TargetMenu, pure (M5-T25): the categories ring with counts, a category's ring of the nearest five with "none" straight
## down, what a pick returns, and B walking back out. Also HudWaypoint: the later of the pilot's pick and a script's wins.

const C := TargetCategories.Category
const OWN: StringName = Factions.EARTH_ALLIANCE
const UP := Vector2(0.0, 1.0)
const DOWN := Vector2(0.0, -1.0)

var menu: TargetMenu


func before_each() -> void:
	menu = TargetMenu.new()


func after_all() -> void:
	Factions.reset()


func _info(id: int, range_m: float, faction: StringName = Factions.RAIDERS, role: int = Targetable.Role.SHIP, broadcast_m: float = 0.0,
		display_name: String = "") -> TargetInfo:
	var info := TargetInfo.new(id, display_name if not display_name.is_empty() else "Raider %d" % id, faction, Vector3(0.0, 0.0, -range_m))
	info.role = role
	info.broadcast_range_m = broadcast_m
	return info


# Seven raiders inside 5 km, three beyond, two allies, a civilian and two buoys.
func _battle() -> Array[TargetInfo]:
	var out: Array[TargetInfo] = []
	for i: int in 7:
		out.append(_info(10 + i, 4200.0 - 500.0 * float(i)))
	for i: int in 3:
		out.append(_info(30 + i, 8000.0 + 1000.0 * float(i)))
	out.append(_info(40, 600.0, OWN, Targetable.Role.SHIP, 1.0e5, "Alpha 2"))
	out.append(_info(41, 12000.0, OWN, Targetable.Role.SHIP, 1.0e5, "Alpha 3"))
	out.append(_info(50, 3000.0, &"narn", Targetable.Role.CIVILIAN, 15000.0, "Narn transport"))
	out.append(_info(60, 40000.0, Factions.NEUTRAL, Targetable.Role.BEACON, 1.0e6, "Nav Alpha"))
	out.append(_info(61, 900.0, Factions.NEUTRAL, Targetable.Role.BEACON, 1.0e6, "Nav Beta"))
	return out


func _objectives() -> Array[Dictionary]:
	return [
		{"text": "Escort the Narn transport to NAV BETA", "label": "Narn transport", "target_id": 50, "point": null,
				"position": Vector3(0.0, 0.0, -3000.0)},
		{"text": "Reach the gate", "label": "gate", "target_id": 0, "point": UniversePos.new(0.0, 0.0, -2500.0),
				"position": Vector3(0.0, 0.0, -2500.0)},
	]


func _open_category(category: C) -> void:
	menu.open(_battle(), Vector3.ZERO, OWN, _objectives())
	menu.radial.set_highlight(TargetCategories.ORDER.find(category))
	assert_true(menu.select().is_empty(), "opening a category picks nothing")


func _labels() -> Array[String]:
	var out: Array[String] = []
	for slot: Dictionary in menu.radial.slots():
		out.append(str(slot.get("label", "")))
	return out


func test_the_first_ring_is_the_six_categories_with_counts() -> void:
	menu.open(_battle(), Vector3.ZERO, OWN, _objectives())
	assert_true(menu.is_open())
	assert_eq(menu.page_name(), "categories")
	assert_eq(_labels(), ["ENEMIES", "ALLIES", "CIVILIAN", "UNKNOWN", "NAVIGATION", "OBJECTIVES"] as Array[String])
	var subs: Array[String] = []
	for slot: Dictionary in menu.radial.slots():
		subs.append(str(slot["sub"]))
	assert_eq(subs, ["7 in range", "2", "1", "3", "2", "2"] as Array[String])
	assert_eq(menu.radial.highlight(), 0, "it opens on ENEMIES, at the top")
	assert_eq(menu.radial.title(), "TACTICAL PAUSE")
	assert_eq(menu.radial.slots()[0]["color"], Factions.HOSTILE_COLOR)
	assert_eq(menu.radial.slots()[3]["color"], Factions.UNIDENTIFIED_COLOR)


func test_a_category_ring_holds_the_nearest_five_and_none_in_the_down_slice() -> void:
	_open_category(C.ENEMIES)
	assert_eq(menu.page_name(), "enemies")
	assert_eq(menu.radial.depth(), 2)
	assert_eq(menu.radial.title(), "TACTICAL PAUSE · ENEMIES")
	assert_eq(_labels(), ["RAIDER 16", "RAIDER 15", "RAIDER 14", "NONE", "RAIDER 13", "RAIDER 12"] as Array[String],
			"nearest first, clockwise from the top, none straight down")
	assert_eq(str(menu.radial.slots()[0]["sub"]), "1.2 km")
	assert_true(menu.point(DOWN))
	assert_eq(str(menu.radial.highlighted()["label"]), "NONE")


func test_every_ring_with_a_none_has_it_straight_down() -> void:
	for category: C in TargetCategories.ORDER:
		_open_category(category)
		assert_eq(menu.radial.slice_count(), 6, TargetCategories.NAMES[category])
		assert_eq(_labels()[3], "NONE", "%s: none is the down slice" % TargetCategories.NAMES[category])
		menu.close()


func test_picking_a_ship_returns_it_as_the_target_and_closes() -> void:
	_open_category(C.ENEMIES)
	menu.radial.set_highlight(1)
	var picked: Dictionary = menu.select()
	assert_eq(picked["action"], TargetMenu.ACTION_TARGET)
	assert_eq(int(picked["id"]), 15)
	assert_false(menu.is_open(), "a pick closes the menu")
	assert_eq(menu.radial.closed_by, &"pick")
	assert_eq(menu.page_name(), "")
	_open_category(C.ALLIES)
	assert_eq(_labels().slice(0, 2), ["ALPHA 2", "ALPHA 3"] as Array[String])
	assert_eq(menu.select()["action"], TargetMenu.ACTION_TARGET)
	_open_category(C.CIVILIAN)
	assert_eq(int(menu.select()["id"]), 50)


func test_unknown_contacts_have_no_name() -> void:
	_open_category(C.UNKNOWN)
	assert_eq(_labels(), ["UNKNOWN", "UNKNOWN", "UNKNOWN", "NONE", "", ""] as Array[String])
	assert_eq(str(menu.radial.slots()[0]["sub"]), "8.0 km")
	var picked: Dictionary = menu.select()
	assert_eq(picked["action"], TargetMenu.ACTION_TARGET)
	assert_eq(int(picked["id"]), 30, "the nearest unknown")
	assert_eq(str(picked["label"]), "UNKNOWN")


func test_a_beacon_or_an_objective_becomes_the_waypoint_never_the_target() -> void:
	_open_category(C.NAVIGATION)
	assert_eq(_labels().slice(0, 2), ["NAV BETA", "NAV ALPHA"] as Array[String])
	var beacon: Dictionary = menu.select()
	assert_eq(beacon["action"], TargetMenu.ACTION_WAYPOINT)
	assert_eq(int(beacon["id"]), 61)
	assert_eq(str(beacon["label"]), "NAV BETA")
	_open_category(C.OBJECTIVES)
	assert_eq(_labels()[0], "ESCORT THE NARN…", "a long objective is cut on its slice")
	assert_eq(str(menu.radial.slots()[0]["detail"]), "ESCORT THE NARN TRANSPORT TO NAV BETA", "and whole under the ring")
	assert_eq(str(menu.radial.slots()[0]["sub"]), "NARN TRANSPORT  3.0 km")
	assert_eq(_labels()[1], "REACH THE GATE")
	menu.radial.set_highlight(1)
	var place: Dictionary = menu.select()
	assert_eq(place["action"], TargetMenu.ACTION_WAYPOINT)
	assert_eq(int(place["id"]), 0, "a bare place has no contact")
	assert_not_null(place["point"])


func test_none_clears_that_kind_of_selection() -> void:
	for category: C in [C.ENEMIES, C.ALLIES, C.CIVILIAN, C.UNKNOWN]:
		_open_category(category)
		menu.point(DOWN)
		assert_eq(menu.select()["action"], TargetMenu.ACTION_CLEAR_TARGET, TargetCategories.NAMES[category])
		assert_false(menu.is_open())
	for category: C in [C.NAVIGATION, C.OBJECTIVES]:
		_open_category(category)
		menu.point(DOWN)
		assert_eq(menu.select()["action"], TargetMenu.ACTION_CLEAR_WAYPOINT, TargetCategories.NAMES[category])


func test_back_goes_to_the_categories_then_closes() -> void:
	_open_category(C.CIVILIAN)
	assert_true(menu.back(), "back from a category: the categories")
	assert_eq(menu.page_name(), "categories")
	assert_eq(menu.radial.highlight(), 2, "still on the category it came from")
	assert_false(menu.back(), "back from the categories closes")
	assert_false(menu.is_open())
	assert_eq(menu.radial.closed_by, &"back")


func test_an_empty_category_still_offers_none_and_at_most_five_objectives_show() -> void:
	var objectives: Array[Dictionary] = []
	for i: int in 8:
		objectives.append({"text": "Objective %d" % i, "label": "p", "target_id": 0, "point": null, "position": Vector3.ZERO})
	menu.open([] as Array[TargetInfo], Vector3.ZERO, OWN, objectives)
	assert_eq(str(menu.radial.slots()[0]["sub"]), "0 in range")
	assert_eq(menu.count(C.OBJECTIVES), 5, "up to five objectives")
	assert_true(menu.select().is_empty())
	assert_eq(_labels(), ["", "", "", "NONE", "", ""] as Array[String])
	assert_eq(menu.radial.highlight(), 3, "the highlight starts on the only entry")
	assert_eq(menu.select()["action"], TargetMenu.ACTION_CLEAR_TARGET)


func test_range_text() -> void:
	assert_eq(TargetMenu.range_text(850.4), "850 m")
	assert_eq(TargetMenu.range_text(1900.0), "1.9 km")
	assert_eq(TargetMenu.range_text(40000.0), "40.0 km")


func test_the_later_of_the_pilots_pick_and_a_scripts_waypoint_wins() -> void:
	var w := HudWaypoint.new()
	assert_true(w.shows_script(), "nothing picked: the script's, if it has one")
	assert_eq(w.describe(), "none")
	w.offer_script("mission:1")
	assert_eq(w.describe(), "script")
	w.set_pick("NAV BETA", 61)
	w.offer_script("mission:1")
	assert_true(w.shows_pick(), "the pilot spoke last")
	assert_eq(w.describe(), "NAV BETA")
	w.offer_script("mission:2")
	assert_false(w.shows_pick(), "the script set a waypoint anew: it wins")
	assert_true(w.shows_script())
	w.clear_pick()
	w.offer_script("mission:2")
	assert_false(w.shows_script(), "none, picked by the pilot, hides the script's too")
	assert_false(w.shows_pick())
	assert_eq(w.describe(), "none")
	w.offer_script("")
	assert_true(w.shows_script(), "until the script speaks again, even to clear its own")
	w.set_pick("NAV ALPHA", 60)
	w.drop_pick()
	assert_true(w.shows_script(), "a pick whose target is gone hands back to the script")
	assert_true(w.pick.is_empty())


# 500 candidates around the origin, half of them raiders, the rest allies, civilians and buoys that broadcast.
func _five_hundred() -> Array[TargetInfo]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261111
	var out: Array[TargetInfo] = []
	for i: int in 500:
		var info: TargetInfo = _info(i + 1, rng.randf_range(100.0, 24000.0))
		info.position = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() \
				* info.position.length()
		match i % 4:
			1:
				info.faction = OWN
				info.broadcast_range_m = 1.0e5
			2:
				info.faction = &"narn"
				info.role = Targetable.Role.CIVILIAN
				info.broadcast_range_m = 15000.0
			3:
				if i % 8 == 3:
					info.role = Targetable.Role.BEACON
					info.broadcast_range_m = 1.0e6
		out.append(info)
	return out


func test_opening_on_five_hundred_candidates_is_one_cheap_pass() -> void:
	var candidates: Array[TargetInfo] = _five_hundred()
	var best_usec: int = 1 << 60
	for _i: int in 20:
		var started: int = Time.get_ticks_usec()
		menu.open(candidates, Vector3.ZERO, OWN, _objectives())
		best_usec = mini(best_usec, Time.get_ticks_usec() - started)
		menu.close()
	gut.p("TargetMenu.open on 500 candidates: %d us (best of 20)" % best_usec)
	menu.open(candidates, Vector3.ZERO, OWN, _objectives())
	var total: int = 0
	for category: C in [C.ENEMIES, C.ALLIES, C.CIVILIAN, C.UNKNOWN, C.NAVIGATION]:
		total += menu.count(category)
	assert_eq(total, 500, "every candidate is counted in one category")
	var built: int = TargetInfo.built_count
	for category: C in TargetCategories.ORDER:
		menu.radial.set_highlight(TargetCategories.ORDER.find(category))
		menu.select()
		assert_lte(menu.radial.slots().filter(func(slot: Dictionary) -> bool: return not slot.is_empty()).size(), 6)
		menu.back()
	assert_eq(TargetInfo.built_count, built, "the rings are cut from the one sorted read: nothing is built again")
	# Opening is per event, during a pause: half a frame at 60 fps is plenty, and far above what it takes.
	WallClockBudget.assert_under(self, float(best_usec), 8000.0, "opening the menu on 500 candidates stays under 8 ms")
