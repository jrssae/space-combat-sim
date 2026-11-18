extends GutTest
## DockKeepOut (M8-T06): the way round the station to the docking lane. From anywhere within the bay's reach the next target is
## reached in a straight line that meets no solid, and following the targets ends on the lane.

const MOUTH := Vector3(0.0, 0.0, -2519.6)
const STEP_M: float = 8.0


func _game_boxes() -> Array[AABB]:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DockingDirector.DATA_PATH))
	return DockKeepOut.boxes_from(data["keep_out"])


func _game() -> DockKeepOut:
	return DockKeepOut.build(_game_boxes(), MOUTH + Vector3(0.0, 0.0, -400.0), 35.0, 60.0)


func _in_solid(point: Vector3, boxes: Array[AABB]) -> bool:
	for box: AABB in boxes:
		if box.has_point(point):
			return true
	return false


# Follows the targets from `start`; returns the steps taken, or -1 when it entered a solid or never arrived.
func _fly(keep: DockKeepOut, start: Vector3, boxes: Array[AABB]) -> int:
	var at: Vector3 = start
	for step: int in 1500:
		if at.distance_to(keep.goal) < STEP_M:
			return step
		at = at.move_toward(keep.next_target(at), STEP_M)
		if _in_solid(at, boxes):
			return -1
	return -1


func test_a_clear_line_goes_straight_to_the_goal() -> void:
	var keep: DockKeepOut = _game()
	var start := Vector3(60.0, -40.0, -3200.0)
	assert_false(keep.blocked(start, keep.goal))
	assert_eq(keep.next_target(start), keep.goal)
	assert_almost_eq(keep.distance_left(start), start.distance_to(keep.goal), 1e-3)


func test_a_ship_beside_the_drum_is_led_round_to_the_bow() -> void:
	var keep: DockKeepOut = _game()
	var start := Vector3(900.0, 0.0, -1500.0)
	assert_true(keep.blocked(start, keep.goal), "the drum is in the way")
	var first: Vector3 = keep.next_target(start)
	assert_ne(first, keep.goal)
	assert_false(keep.blocked(start, first), "the first leg is clear")
	assert_gt(keep.distance_left(start), start.distance_to(keep.goal), "the way round is longer than the straight line")


func test_every_start_within_the_bays_reach_arrives_without_touching_the_station() -> void:
	var boxes: Array[AABB] = _game_boxes()
	var keep: DockKeepOut = _game()
	var flown: int = 0
	var failed := PackedStringArray()
	for x: int in range(-1800, 1801, 450):
		for y: int in range(-1800, 1801, 450):
			for z: int in range(-1900, 1901, 380):
				var start: Vector3 = MOUTH + Vector3(float(x), float(y), float(z))
				if start.distance_to(MOUTH) > 2000.0 or _in_solid(start, boxes):
					continue
				flown += 1
				if _fly(keep, start, boxes) < 0:
					failed.append(str(start))
	assert_gt(flown, 300, "a grid of starts through the 2 km sphere")
	assert_eq(failed.size(), 0, "starts that hit the station or never arrived: %s" % ", ".join(failed.slice(0, 6)))


func test_a_ship_inside_a_margin_is_sent_out_of_it_first() -> void:
	var keep: DockKeepOut = _game()
	var hugging := Vector3(450.0, 0.0, -1000.0)  # 20 m off the drum's box, inside its 35 m margin
	assert_gte(keep.inside(hugging), 0)
	var out: Vector3 = keep.next_target(hugging)
	assert_gt(out.x, hugging.x, "straight out through the nearest face")
	assert_eq(keep.inside(out), -1)


func test_a_turning_point_reached_hands_on_to_the_next() -> void:
	var keep: DockKeepOut = _game()
	assert_gt(keep.nodes.size(), 8)
	for i: int in keep.nodes.size():
		var onward: Vector3 = keep.next_target(keep.nodes[i])
		assert_false(onward.is_equal_approx(keep.nodes[i]), "a ship standing on turning point %d is sent on" % i)


func test_boxes_from_data_skip_what_is_not_a_box() -> void:
	var boxes: Array[AABB] = DockKeepOut.boxes_from([{"min": [0, 0, 0], "max": [10, 20, 30]}, {"min": [1, 2]}, "nonsense",
			{"min": [5, 5, 5], "max": [-5, -5, -5]}])
	assert_eq(boxes.size(), 2)
	assert_eq(boxes[0].size, Vector3(10.0, 20.0, 30.0))
	assert_eq(boxes[1].size, Vector3(10.0, 10.0, 10.0), "min and max the wrong way round still make a box")
	assert_eq(DockKeepOut.boxes_from(null).size(), 0)


func test_with_no_boxes_every_line_is_clear() -> void:
	var keep := DockKeepOut.build([] as Array[AABB], Vector3(0.0, 0.0, -100.0), 35.0, 60.0)
	assert_eq(keep.next_target(Vector3(500.0, 0.0, 0.0)), keep.goal)
