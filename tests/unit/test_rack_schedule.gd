extends GutTest
## A capital's missile racks' timing (M8-T09, `RackSchedule`): each rack holds its cells and reloads after a shot, the ship
## keeps a gap between any two launches, and the rack that faces the target fires.


func _schedule() -> RackSchedule:
	return RackSchedule.create(4, {"cells": 2, "reload_s": 10.0, "gap_s": 2.0, "retry_s": 0.5, "range_m": 3000.0})


func test_every_rack_starts_full_and_ready() -> void:
	var s: RackSchedule = _schedule()
	assert_eq(s.missiles_left(), 8)
	assert_true(s.due(0.0))
	assert_eq(s.ready(0.0), PackedInt32Array([0, 1, 2, 3]))
	assert_eq(RackSchedule.create(4).cells, 6, "the defaults when the data names nothing")
	assert_eq(RackSchedule.create(4, {"range_m": 1200.0}).range_m, 1200.0)


func test_a_shot_empties_a_cell_reloads_its_rack_and_holds_the_others_for_the_gap() -> void:
	var s: RackSchedule = _schedule()
	s.fired(1, 100.0)
	assert_eq(s.missiles_left(), 7)
	assert_false(s.due(101.9), "the ship's gap")
	assert_true(s.due(102.0))
	assert_eq(s.ready(102.0), PackedInt32Array([0, 2, 3]), "rack 1 is reloading")
	assert_eq(s.ready(110.0), PackedInt32Array([0, 1, 2, 3]), "ready again after its reload")


func test_an_empty_rack_fires_no_more_until_restocked() -> void:
	var s: RackSchedule = _schedule()
	for rack: int in 4:
		s.fired(rack, 0.0)
		s.fired(rack, 20.0)
	assert_eq(s.missiles_left(), 0)
	assert_false(s.due(1000.0), "nothing left to fire")
	s.restock()
	assert_eq(s.missiles_left(), 8)
	assert_true(s.due(1000.0))


func test_with_nothing_to_fire_at_it_looks_again_after_its_retry() -> void:
	var s: RackSchedule = _schedule()
	s.missed(50.0)
	assert_false(s.due(50.4))
	assert_true(s.due(50.5))
	assert_eq(s.missiles_left(), 8, "a miss spends nothing")


func test_the_rack_that_faces_the_target_fires() -> void:
	var forwards := PackedVector3Array([Vector3(1, 1, -1).normalized(), Vector3(1, -1, -1).normalized(), Vector3(-1, -1, -1).normalized(),
			Vector3(-1, 1, -1).normalized()])
	assert_eq(RackSchedule.best_facing(PackedInt32Array([0, 1, 2, 3]), forwards, Vector3(-500.0, -400.0, -900.0)), 2)
	assert_eq(RackSchedule.best_facing(PackedInt32Array([0, 1, 3]), forwards, Vector3(-500.0, -400.0, -900.0)), 3, "of those ready")
	assert_eq(RackSchedule.best_facing(PackedInt32Array(), forwards, Vector3.FORWARD), -1)
