extends GutTest
## ApproachCue (M8-T18, D84, AC14): the cue on a navigation target with an interaction, over approach speeds, offsets and
## brake strengths. The target sits at the origin; the ship comes in along +Z unless a test says otherwise.

const REACH: float = 2000.0
const DECEL: float = 30.0


func _head_on(distance: float, speed: float, decel: float = DECEL) -> ApproachCue:
	return ApproachCue.read(Vector3(0.0, 0.0, -distance), Vector3(0.0, 0.0, -speed), REACH, decel)


func test_a_slow_ship_far_out_is_on_course() -> void:
	var cue: ApproachCue = _head_on(10000.0, 100.0)
	assert_eq(cue.state, ApproachCue.State.ON_COURSE)
	assert_almost_eq(cue.closing_mps, 100.0, 1e-3)
	assert_almost_eq(cue.entry_m, 8000.0, 1e-2, "8 km to the reach's edge")
	assert_almost_eq(cue.time_to_reach_s, 80.0, 1e-2)
	assert_almost_eq(cue.closest_m, 0.0, 1e-2, "dead on: the course passes through the target")
	assert_almost_eq(cue.stopping_m, StoppingDistance.distance_m(100.0, DECEL, ApproachCue.REACTION_S), 1e-3)


func test_the_cue_says_brake_once_the_stopping_distance_reaches_the_room_left() -> void:
	# 1 km/s at 30 m/s^2 stops in about 17.7 km with the reaction: brake at 19 km out (17 km to the reach), not yet at 40 km.
	assert_eq(_head_on(40000.0, 1000.0).state, ApproachCue.State.ON_COURSE)
	var cue: ApproachCue = _head_on(19000.0, 1000.0)
	assert_eq(cue.state, ApproachCue.State.BRAKE)
	assert_lt(cue.stopping_m, cue.exit_m, "it can still stop inside the reach")


func test_a_ship_that_cannot_stop_inside_the_reach_overshoots() -> void:
	var cue: ApproachCue = _head_on(5000.0, 1000.0)
	assert_eq(cue.state, ApproachCue.State.OVERSHOOT)
	assert_gt(cue.stopping_m, cue.exit_m)


func test_stronger_brakes_turn_an_overshoot_into_a_brake_or_on_course() -> void:
	assert_eq(_head_on(5000.0, 400.0, 10.0).state, ApproachCue.State.OVERSHOOT, "weak brakes: 8 km to stop")
	assert_eq(_head_on(5000.0, 400.0, 30.0).state, ApproachCue.State.BRAKE, "30 m/s^2: about 3 km, brake now")
	assert_eq(_head_on(5000.0, 400.0, 200.0).state, ApproachCue.State.ON_COURSE, "strong brakes: room to spare")


func test_the_states_over_speeds_run_on_course_brake_overshoot() -> void:
	var last: int = ApproachCue.State.ON_COURSE
	for speed: float in [50.0, 200.0, 400.0, 600.0, 900.0, 1500.0, 3000.0]:
		var state: int = _head_on(8000.0, speed).state
		assert_true(state >= last, "%.0f m/s: the state never steps back as the speed grows" % speed)
		assert_ne(state, ApproachCue.State.ADJUST_COURSE, "a head-on course always meets the reach")
		last = state
	assert_eq(_head_on(8000.0, 50.0).state, ApproachCue.State.ON_COURSE)
	assert_eq(_head_on(8000.0, 3000.0).state, ApproachCue.State.OVERSHOOT)


func test_a_course_that_misses_the_reach_needs_adjusting() -> void:
	# 3 km to the side, flying parallel to the line through the target: it passes 3 km off, outside the 2 km reach.
	var cue: ApproachCue = ApproachCue.read(Vector3(3000.0, 0.0, -10000.0), Vector3(0.0, 0.0, -200.0), REACH, DECEL)
	assert_eq(cue.state, ApproachCue.State.ADJUST_COURSE)
	assert_almost_eq(cue.closest_m, 3000.0, 1e-2, "the closest approach on the present course")
	assert_eq(cue.time_to_reach_s, INF)
	var grazing: ApproachCue = ApproachCue.read(Vector3(1500.0, 0.0, -10000.0), Vector3(0.0, 0.0, -200.0), REACH, DECEL)
	assert_ne(grazing.state, ApproachCue.State.ADJUST_COURSE, "1.5 km off still passes through the reach")
	assert_almost_eq(grazing.closest_m, 1500.0, 1e-2)


func test_flying_away_or_drifting_needs_adjusting() -> void:
	assert_eq(_head_on(10000.0, -200.0).state, ApproachCue.State.ADJUST_COURSE, "opening")
	assert_eq(_head_on(10000.0, 0.0).state, ApproachCue.State.ADJUST_COURSE, "at rest out of reach")
	assert_almost_eq(_head_on(10000.0, -200.0).closest_m, 10000.0, 1e-2, "it is as close now as it will get")


func test_inside_the_reach_at_rest_is_on_course_and_flying_through_fast_overshoots() -> void:
	var resting: ApproachCue = _head_on(1500.0, 0.0)
	assert_eq(resting.state, ApproachCue.State.ON_COURSE)
	assert_eq(resting.entry_m, 0.0)
	assert_eq(resting.time_to_reach_s, 0.0)
	assert_eq(_head_on(1500.0, 600.0).state, ApproachCue.State.OVERSHOOT, "3.5 km of room, 6 km to stop")
	assert_eq(_head_on(1500.0, 50.0).state, ApproachCue.State.ON_COURSE, "a crawl stops well inside")


func test_speeds_are_read_against_the_targets_rest() -> void:
	var rest := Vector3(5000.0, 0.0, 0.0)
	var cue: ApproachCue = ApproachCue.between(Vector3(0.0, 0.0, 10000.0), rest + Vector3(0.0, 0.0, -100.0), Vector3.ZERO, rest,
			REACH, DECEL)
	assert_almost_eq(cue.closing_mps, 100.0, 1e-3, "the frame's own motion is not closing speed")
	assert_eq(cue.state, ApproachCue.State.ON_COURSE)


func test_a_bays_lane_must_be_approached_from_its_front() -> void:
	# The lane runs in along -Z (into the bay): ships come in from +Z.
	var lane := Vector3(0.0, 0.0, -1.0)
	var front: ApproachCue = ApproachCue.read(Vector3(0.0, 0.0, -6000.0), Vector3(0.0, 0.0, -100.0), REACH, DECEL, lane)
	assert_eq(front.state, ApproachCue.State.ON_COURSE, "down the lane")
	var side: ApproachCue = ApproachCue.read(Vector3(-6000.0, 0.0, 0.0), Vector3(-100.0, 0.0, 0.0), REACH, DECEL, lane)
	assert_eq(side.state, ApproachCue.State.ADJUST_COURSE, "square to the lane: come round to its front")
	var inside: ApproachCue = ApproachCue.read(Vector3(-1000.0, 0.0, 0.0), Vector3.ZERO, REACH, DECEL, lane)
	assert_eq(inside.state, ApproachCue.State.ON_COURSE, "within reach the docking autopilot takes it from any side")


func test_the_bar_fills_to_its_brake_mark_as_braking_becomes_due() -> void:
	var early: ApproachCue = _head_on(40000.0, 1000.0)
	assert_lt(early.bar_fill(), early.bar_mark(), "on course: the stopping distance is short of the mark")
	var due: ApproachCue = _head_on(19000.0, 1000.0)
	assert_gt(due.bar_fill(), due.bar_mark() - 0.2, "brake: the fill is at the mark")
	assert_between(due.bar_mark(), 0.0, 1.0)
	var miss: ApproachCue = ApproachCue.read(Vector3(3000.0, 0.0, -10000.0), Vector3(0.0, 0.0, -200.0), REACH, DECEL)
	assert_lt(miss.bar_mark(), 0.0, "no mark while the course misses")


func test_the_texts_name_the_state_and_the_brake_button() -> void:
	assert_eq(_head_on(10000.0, 100.0).readout_text(), "+100 m/s  ON COURSE")
	assert_eq(_head_on(19000.0, 1000.0).status_suffix("S"), " — +1000 m/s  BRAKE: HOLD S")
	assert_eq(_head_on(5000.0, 1000.0).status_suffix("S"), " — +1000 m/s  OVERSHOOT")
	assert_eq(_head_on(10000.0, 0.0).status_suffix("S"), "", "at rest the status line stays as it was")
	assert_eq(ApproachCue.STATE_NAMES[ApproachCue.State.ADJUST_COURSE], "ADJUST COURSE")
