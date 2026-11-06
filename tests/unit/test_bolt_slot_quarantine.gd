extends GutTest
## M4-T38 (T35's re-review): a bolt draw slot whose occupant is new since the last drawn frame is drawn collapsed for that
## frame, so the renderer's previous-frame transform for the slot never belongs to another bolt (a motion-vector smear) or
## to an empty slot (a vector to the world origin, NaN at the camera). Freed slots are thus never reused in the frame that
## freed them.

const FORWARD := Vector3(0, 0, -1)

var q: BoltSlotQuarantine


func before_each() -> void:
	q = BoltSlotQuarantine.new(FORWARD)


# One slot's 12 floats: basis rows and origin, as the multimesh buffer holds them.
func _slot(basis: Basis, origin: Vector3) -> PackedFloat32Array:
	return PackedFloat32Array([basis.x.x, basis.y.x, basis.z.x, origin.x, basis.x.y, basis.y.y, basis.z.y, origin.y,
			basis.x.z, basis.y.z, basis.z.z, origin.z])


func _buffer(slots: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for s: Variant in slots:
		out.append_array(s if s != null else PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	return out


func _drawn(buffer: PackedFloat32Array, slot: int) -> bool:
	return buffer[slot * 12] != 0.0 or buffer[slot * 12 + 1] != 0.0 or buffer[slot * 12 + 2] != 0.0


func _origin(buffer: PackedFloat32Array, slot: int) -> Vector3:
	return Vector3(buffer[slot * 12 + 3], buffer[slot * 12 + 7], buffer[slot * 12 + 11])


func test_a_new_bolt_is_collapsed_at_its_own_place_for_its_first_frame_then_drawn() -> void:
	var b := Basis.IDENTITY * 3.0
	var out: PackedFloat32Array = q.filter(0, _buffer([_slot(b, Vector3(1, 2, 3))]))
	assert_false(_drawn(out, 0), "first frame collapsed")
	assert_eq(_origin(out, 0), Vector3(1, 2, 3), "collapsed where it is, not at the origin")
	assert_eq(q.collapsed, 1)
	out = q.filter(0, _buffer([_slot(b, Vector3(1, 2, -7))]))
	assert_true(_drawn(out, 0), "drawn from its second frame")
	assert_eq(q.collapsed, 0)


func test_a_steady_bolt_is_drawn_every_frame() -> void:
	var b := Basis(Vector3.UP, 0.4) * 3.0
	var forward: Vector3 = (b * FORWARD).normalized()
	q.filter(0, _buffer([_slot(b, Vector3.ZERO)]))
	for f: int in range(1, 6):
		var out: PackedFloat32Array = q.filter(0, _buffer([_slot(b, forward * 16.0 * f)]))
		assert_true(_drawn(out, 0), "frame %d" % f)


func test_a_slot_freed_and_taken_by_another_bolt_between_frames_is_not_drawn_that_frame() -> void:
	var a := Basis(Vector3.UP, 0.4) * 3.0
	var other := Basis(Vector3.RIGHT, 1.1) * 3.0
	q.filter(0, _buffer([_slot(a, Vector3.ZERO)]))
	q.filter(0, _buffer([_slot(a, (a * FORWARD).normalized() * 10.0)]))
	var out: PackedFloat32Array = q.filter(0, _buffer([_slot(other, Vector3(500, 0, 0))]))
	assert_false(_drawn(out, 0), "a new occupant does not inherit the old bolt's last frame")


func test_the_same_cannons_next_shot_in_the_old_slot_counts_as_new() -> void:
	# Same direction, so the same basis, but it starts behind where the old bolt was: not the old bolt moving on.
	var a := Basis(Vector3.UP, 0.4) * 3.0
	var forward: Vector3 = (a * FORWARD).normalized()
	q.filter(0, _buffer([_slot(a, forward * 300.0)]))
	q.filter(0, _buffer([_slot(a, forward * 316.0)]))
	var out: PackedFloat32Array = q.filter(0, _buffer([_slot(a, Vector3.ZERO)]))
	assert_false(_drawn(out, 0))


func test_a_bolt_in_line_ahead_but_too_far_counts_as_new() -> void:
	# Review M1: the same basis and a forward move, but further than any bolt flies between two frames.
	var a := Basis(Vector3.UP, 0.4) * 3.0
	var forward: Vector3 = (a * FORWARD).normalized()
	q.filter(0, _buffer([_slot(a, Vector3.ZERO)]))
	var out: PackedFloat32Array = q.filter(0, _buffer([_slot(a, forward * (BoltSlotQuarantine.MAX_STEP_M + 50.0))]))
	assert_false(_drawn(out, 0))


func test_a_parallel_bolt_ahead_and_to_the_side_counts_as_new() -> void:
	# Review M1: a wingman's bolt flying the same way, a little ahead and 20 m to the side.
	var a := Basis(Vector3.UP, 0.4) * 3.0
	var forward: Vector3 = (a * FORWARD).normalized()
	var side: Vector3 = (a * Vector3.RIGHT).normalized()
	q.filter(0, _buffer([_slot(a, Vector3.ZERO)]))
	var out: PackedFloat32Array = q.filter(0, _buffer([_slot(a, forward * 15.0 + side * 20.0)]))
	assert_false(_drawn(out, 0))


func test_an_empty_slot_stays_empty_and_looks_are_kept_apart() -> void:
	var b := Basis.IDENTITY
	q.filter(0, _buffer([_slot(b, Vector3.ZERO), null]))
	var out: PackedFloat32Array = q.filter(1, _buffer([_slot(b, Vector3.ZERO)]))
	assert_false(_drawn(out, 0), "look 1's slot 0 is new even though look 0's slot 0 is not")
	out = q.filter(0, _buffer([_slot(b, Vector3.ZERO), null]))
	assert_true(_drawn(out, 0))
	assert_false(_drawn(out, 1))
	assert_eq(q.collapsed, 0)


func test_the_input_buffer_is_left_as_the_core_wrote_it() -> void:
	var input := _buffer([_slot(Basis.IDENTITY, Vector3.ONE)])
	var copy := input.duplicate()
	q.filter(0, input)
	assert_eq(input, copy)


func test_a_grown_buffer_treats_the_new_slots_as_new() -> void:
	var b := Basis.IDENTITY
	q.filter(0, _buffer([_slot(b, Vector3.ZERO)]))
	var out: PackedFloat32Array = q.filter(0, _buffer([_slot(b, Vector3.ZERO), _slot(b, Vector3.ONE)]))
	assert_true(_drawn(out, 0))
	assert_false(_drawn(out, 1))


func test_reset_forgets_every_slot() -> void:
	var b := Basis.IDENTITY
	q.filter(0, _buffer([_slot(b, Vector3.ZERO)]))
	q.reset()
	var out: PackedFloat32Array = q.filter(0, _buffer([_slot(b, Vector3.ZERO)]))
	assert_false(_drawn(out, 0))
