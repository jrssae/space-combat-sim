extends GutTest
## CapitalMarksLayout (M8-T08): far hostile capitals get a marker with their class and range until their hull is big enough
## to read; off screen an edge arrow; none for the selected target or the waypoint (one label per spot, M8-T33); the nearest
## few only; the rules come from data/hud/capital_markers.json.

const VIEW := Vector2(1920.0, 1080.0)
## The strike carrier's bounding radius, about, m.
const RADIUS_M: float = 82.0


func after_each() -> void:
	CapitalMarkerRules.reload()


func _rules() -> CapitalMarkerRules:
	var rules := CapitalMarkerRules.new()
	rules.max_range_m = 30000.0
	rules.hide_above_px = 14.0
	rules.max_markers = 4
	return rules


## A camera at the origin looking down -Z, an Earth Alliance pilot there.
func _hud_input(capitals: Array[Dictionary]) -> HudInput:
	var input := HudInput.new()
	input.camera_transform = Transform3D.IDENTITY
	input.projection = Projection.create_perspective(70.0, VIEW.x / VIEW.y, 0.05, 100000.0)
	input.viewport_size = VIEW
	input.faction = Factions.EARTH_ALLIANCE
	input.capitals = capitals
	input.capital_rules = _rules()
	return input


func _capital(id: int, at: Vector3, faction: StringName = Factions.RAIDERS, label: String = "STRIKE CARRIER") -> Dictionary:
	return {"id": id, "position": at, "radius_m": RADIUS_M, "label": label, "faction": faction}


func _marks(input: HudInput) -> Array[Dictionary]:
	return HudLayout.compute(input).capital_marks


func test_a_far_hostile_capital_is_marked_with_its_class_and_range() -> void:
	var f: HudFrame = HudLayout.compute(_hud_input([_capital(5, Vector3(0.0, 0.0, -8500.0))]))
	assert_eq(f.capital_marks.size(), 1)
	var mark: Dictionary = f.capital_marks[0]
	assert_true(mark["on_screen"])
	assert_almost_eq(mark["pos"], VIEW * 0.5, Vector2.ONE)
	assert_eq(mark["label"], "STRIKE CARRIER")
	assert_almost_eq(float(mark["range_m"]), 8500.0, 0.1)
	assert_eq(mark["color"], Factions.HOSTILE_COLOR)
	assert_true(f.items.has(HudSurface.CAPITALS), "drawn on the window")


func test_close_up_its_hull_reads_and_the_marker_hides() -> void:
	assert_eq(_marks(_hud_input([_capital(5, Vector3(0.0, 0.0, -2000.0))])).size(), 0, "at 2 km the hull is big enough to read")
	var f: HudFrame = HudLayout.compute(_hud_input([_capital(5, Vector3(0.0, 0.0, -2000.0))]))
	assert_false(f.items.has(HudSurface.CAPITALS), "nothing to draw")


func test_the_threshold_scales_with_the_window() -> void:
	# At 1080p a radius of 82 m reaches 14 px at about 4.4 km; the threshold is 1080p pixels, so any window agrees.
	for size: Vector2 in [VIEW, VIEW * 0.5]:
		var near: HudInput = _hud_input([_capital(5, Vector3(0.0, 0.0, -4000.0))])
		near.viewport_size = size
		assert_eq(_marks(near).size(), 0, "4 km at %s: readable" % size)
		var far: HudInput = _hud_input([_capital(5, Vector3(0.0, 0.0, -5000.0))])
		far.viewport_size = size
		assert_eq(_marks(far).size(), 1, "5 km at %s: marked" % size)


func test_beyond_its_range_no_marker() -> void:
	assert_eq(_marks(_hud_input([_capital(5, Vector3(0.0, 0.0, -31000.0))])).size(), 0)


func test_the_selected_target_or_the_waypoint_gets_no_second_label() -> void:
	var input: HudInput = _hud_input([_capital(5, Vector3(0.0, 0.0, -8500.0))])
	input.selected_id = 5
	var t := TargetReadout.new()
	t.id = 5
	t.display_name = "RAIDER CARRIER 1"
	t.faction = Factions.RAIDERS
	t.position = Vector3(0.0, 0.0, -8500.0)
	t.range_m = 8500.0
	input.target = t
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.capital_marks.size(), 0, "the target's own mark names it")
	assert_true(f.target_present)
	var waypoint: HudInput = _hud_input([_capital(5, Vector3(0.0, 0.0, -8500.0))])
	waypoint.has_waypoint = true
	waypoint.waypoint_id = 5
	waypoint.waypoint_position = Vector3(0.0, 0.0, -8500.0)
	waypoint.waypoint_label = "DESTROY THE CARRIER"
	assert_eq(_marks(waypoint).size(), 0, "the waypoint's marker names it")


func test_only_the_listed_relations_are_marked() -> void:
	assert_eq(_marks(_hud_input([_capital(5, Vector3(0.0, 0.0, -8500.0), Factions.EARTH_ALLIANCE)])).size(), 0, "a friendly capital")


func test_off_screen_it_gets_an_edge_arrow() -> void:
	var f: HudFrame = HudLayout.compute(_hud_input([_capital(5, Vector3(0.0, 0.0, 8500.0))]))
	assert_eq(f.capital_marks.size(), 1, "behind the camera")
	assert_false(f.capital_marks[0]["on_screen"])
	assert_true(HudLayout.on_screen(_hud_input([]), f.capital_marks[0]["pos"]), "on the border")
	var input: HudInput = _hud_input([_capital(5, Vector3(0.0, 0.0, 8500.0))])
	input.capital_rules.edge_arrows = false
	assert_eq(_marks(input).size(), 0, "edge arrows off")


func test_the_nearest_few_only() -> void:
	var many: Array[Dictionary] = []
	for i: int in 6:
		many.append(_capital(10 + i, Vector3(float(i) * 200.0, 0.0, -9000.0 - float(i) * 1000.0)))
	var marks: Array[Dictionary] = _marks(_hud_input(many))
	assert_eq(marks.size(), 4)
	for k: int in range(1, marks.size()):
		assert_gt(float(marks[k]["range_m"]), float(marks[k - 1]["range_m"]), "nearest first")


func test_the_shipped_rules() -> void:
	var rules: CapitalMarkerRules = CapitalMarkerRules.shared()
	assert_eq(rules.relations, [Factions.Relation.HOSTILE] as Array[Factions.Relation])
	assert_gt(rules.max_range_m, 21000.0, "a station raid's carrier stands off about 21 km out")
	assert_gt(rules.hide_above_px, 0.0)
	assert_gt(rules.max_markers, 0)
	assert_true(rules.edge_arrows)


func test_the_console_text() -> void:
	var f: HudFrame = HudLayout.compute(_hud_input([_capital(5, Vector3(0.0, 0.0, -8500.0))]))
	assert_eq(Hud.capital_marks_text(f), "STRIKE CARRIER 8.50 km screen")
	assert_eq(Hud.capital_marks_text(HudFrame.new()), "none")
