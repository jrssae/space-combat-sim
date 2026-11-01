extends GutTest
## AC30: `LightPicker` keeps the 7 highest-scoring emitters (the key star is the rig's slot 0 and never competes), by priority class
## x energy x range / distance to the camera^2, and does not swap within the 20 % margin an incumbent enjoys.

const CAMERA: Vector3 = Vector3(100.0, -20.0, 40.0)

var picker: LightPicker


func before_each() -> void:
	picker = LightPicker.new()


## An emitter whose score at `CAMERA` is exactly `wanted` (class 1, range 1, 1 m away).
func _scored(wanted: float, label: String = "") -> LightEmitter:
	var emitter := LightEmitter.new(label, LightEmitter.PRIORITY_CABIN, Color.WHITE, wanted, 1.0)
	emitter.position = CAMERA + Vector3(1.0, 0.0, 0.0)
	return emitter


func _picked(slots: Array[LightEmitter]) -> Array[LightEmitter]:
	var out: Array[LightEmitter] = []
	for emitter: LightEmitter in slots:
		if emitter != null:
			out.append(emitter)
	return out


func test_there_are_seven_slots_beside_the_key_star() -> void:
	assert_eq(LightPicker.SLOT_COUNT, 7)
	assert_eq(picker.pick([], CAMERA).size(), 7, "always one entry per slot")
	assert_eq(_picked(picker.pick([], CAMERA)).size(), 0, "nothing to light")


func test_the_score_is_class_times_energy_times_range_over_distance_squared() -> void:
	var emitter := LightEmitter.new("x", LightEmitter.PRIORITY_NOZZLE, Color.WHITE, 3.0, 5.0)
	emitter.position = CAMERA + Vector3(0.0, 0.0, 10.0)
	assert_almost_eq(LightPicker.score(emitter, CAMERA), LightEmitter.PRIORITY_NOZZLE * 3.0 * 5.0 / 100.0, 1e-5)


func test_an_emitter_at_the_camera_scores_as_if_it_were_a_metre_away() -> void:
	var emitter := _scored(2.0)
	emitter.position = CAMERA
	assert_almost_eq(LightPicker.score(emitter, CAMERA), 2.0, 1e-5, "finite: no blow-up at the camera itself")


func test_the_priority_classes_rank_as_planned() -> void:
	assert_gt(LightEmitter.PRIORITY_PLAYER_OWN, LightEmitter.PRIORITY_EXPLOSION)
	assert_gt(LightEmitter.PRIORITY_EXPLOSION, LightEmitter.PRIORITY_MUZZLE_FLASH)
	assert_gt(LightEmitter.PRIORITY_MUZZLE_FLASH, LightEmitter.PRIORITY_NOZZLE)
	assert_gt(LightEmitter.PRIORITY_NOZZLE, LightEmitter.PRIORITY_CABIN)


func test_a_few_emitters_are_all_picked() -> void:
	var candidates: Array[LightEmitter] = [_scored(1.0), _scored(2.0), _scored(3.0)]
	assert_eq(_picked(picker.pick(candidates, CAMERA)).size(), 3)


func test_it_keeps_the_seven_highest() -> void:
	var candidates: Array[LightEmitter] = []
	for i: int in 12:
		candidates.append(_scored(1.0 + i, str(i)))
	candidates.shuffle()
	var labels: Array[int] = []
	for emitter: LightEmitter in _picked(picker.pick(candidates, CAMERA)):
		labels.append(int(emitter.label))
	labels.sort()
	assert_eq(labels, [5, 6, 7, 8, 9, 10, 11] as Array[int])


func test_a_dark_emitter_is_never_picked_and_frees_its_slot() -> void:
	var lamp := _scored(1.0)
	var dark := _scored(0.0)
	var candidates: Array[LightEmitter] = [lamp, dark]
	assert_eq(_picked(picker.pick(candidates, CAMERA)), [lamp] as Array[LightEmitter])
	lamp.energy = 0.0
	assert_eq(_picked(picker.pick(candidates, CAMERA)).size(), 0)


func test_an_emitter_that_left_the_candidates_frees_its_slot() -> void:
	var a := _scored(1.0)
	var b := _scored(2.0)
	var candidates: Array[LightEmitter] = [a, b]
	picker.pick(candidates, CAMERA)
	candidates = [b]
	assert_eq(_picked(picker.pick(candidates, CAMERA)), [b] as Array[LightEmitter])


func test_an_incumbent_stays_within_the_margin() -> void:
	var candidates: Array[LightEmitter] = []
	for i: int in 7:
		candidates.append(_scored(1.0, "seat %d" % i))
	var before: Array[LightEmitter] = picker.pick(candidates, CAMERA).duplicate()
	candidates.append(_scored(1.15, "challenger"))
	assert_eq(picker.pick(candidates, CAMERA), before, "15 % better is inside the 20 % bonus: no swap")


func test_a_challenger_past_the_margin_takes_the_weakest_seat() -> void:
	var candidates: Array[LightEmitter] = []
	for i: int in 6:
		candidates.append(_scored(2.0, "seat %d" % i))
	var weakest := _scored(1.0, "weakest")
	candidates.append(weakest)
	picker.pick(candidates, CAMERA)
	var challenger := _scored(1.25, "challenger")
	candidates.append(challenger)
	var picked: Array[LightEmitter] = _picked(picker.pick(candidates, CAMERA))
	assert_true(picked.has(challenger))
	assert_false(picked.has(weakest))


func test_the_margin_only_helps_the_incumbent() -> void:
	# Between two newcomers the higher score wins, whichever comes first.
	var candidates: Array[LightEmitter] = []
	for i: int in 6:
		candidates.append(_scored(5.0))
	var low := _scored(1.0, "low")
	var high := _scored(1.05, "high")
	candidates.append(low)
	candidates.append(high)
	var picked: Array[LightEmitter] = _picked(picker.pick(candidates, CAMERA))
	assert_true(picked.has(high))
	assert_false(picked.has(low))


func test_an_emitter_keeps_its_slot_while_others_come_and_go() -> void:
	var a := _scored(4.0, "a")
	var b := _scored(3.0, "b")
	var c := _scored(2.0, "c")
	var candidates: Array[LightEmitter] = [a, b, c]
	var slot_of_c: int = picker.pick(candidates, CAMERA).find(c)
	candidates = [c, _scored(9.0, "new")]
	assert_eq(picker.pick(candidates, CAMERA).find(c), slot_of_c, "a slot's light does not move for no reason")


func test_small_changes_cause_no_swap() -> void:
	# Twenty similar emitters drifting by a few percent: the seven in the slots stay in them, in the same slots.
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var candidates: Array[LightEmitter] = []
	var base: Array[float] = []
	for i: int in 20:
		base.append(10.0 + 2.0 * i)
		candidates.append(_scored(base[i], str(i)))
	var before: Array[LightEmitter] = picker.pick(candidates, CAMERA).duplicate()
	for frame: int in 200:
		for i: int in 20:
			candidates[i].energy = base[i] * rng.randf_range(0.97, 1.03)
		assert_eq(picker.pick(candidates, CAMERA), before, "frame %d" % frame)


func test_the_same_input_gives_the_same_picks() -> void:
	var candidates: Array[LightEmitter] = []
	for i: int in 12:
		candidates.append(_scored(3.0))
	var first: Array[LightEmitter] = picker.pick(candidates, CAMERA).duplicate()
	assert_eq(picker.pick(candidates, CAMERA), first)
	assert_eq(LightPicker.new().pick(candidates, CAMERA), first, "ties resolve the same way for a fresh picker")
