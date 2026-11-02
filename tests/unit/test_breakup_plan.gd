extends GutTest
## BreakupPlan and StagedWreck (M3-T28, AC38): the seeded release schedule of a Starfury's break-up and the rigid wreck the
## chunks ride until their turn. Pure; nothing here reads a clock.

const OFFSETS: Array[Vector3] = [
	Vector3(0.0, -0.4, -2.15), Vector3(3.98, 1.92, 0.4), Vector3(4.03, -1.81, 0.41), Vector3(-3.98, 1.92, 0.4),
	Vector3(-4.03, -1.81, 0.41),
]
const JOINTS: Array[Vector3] = [
	Vector3(0.0, -0.2, -1.4), Vector3(0.98, 0.67, -1.37), Vector3(1.0, -1.1, -1.26), Vector3(-0.98, 0.67, -1.37),
	Vector3(-1.0, -1.1, -1.26),
]
const DT: float = 1.0 / 60.0


func _wreck(first: int = 2, seed_value: int = 7, velocity: Vector3 = Vector3(5.0, -2.0, -30.0),
		spin: Vector3 = Vector3(0.3, -0.9, 0.5)) -> StagedWreck:
	var xform := Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, -0.4), Vector3(100.0, 20.0, -300.0))
	return StagedWreck.new(BreakupPlan.make(OFFSETS.size(), first, seed_value), OFFSETS, JOINTS, xform, velocity, spin)


# --- the plan ----------------------------------------------------------------------------------------------------


func test_the_part_hit_last_leaves_first_at_the_instant_of_death() -> void:
	for first: int in 5:
		var plan := BreakupPlan.make(5, first, 3)
		assert_eq(plan.order[0], first)
		assert_eq(plan.release_s[first], 0.0)


func test_every_chunk_is_released_once_one_at_a_time_inside_1_2_seconds() -> void:
	for seed_value: int in 40:
		var plan := BreakupPlan.make(5, seed_value % 5, seed_value)
		var seen: Array[int] = []
		var last: float = -1.0
		for rank: int in plan.order.size():
			var chunk: int = plan.order[rank]
			assert_false(seen.has(chunk), "released once")
			seen.append(chunk)
			assert_gt(plan.release_s[chunk], last, "strictly one after another")
			last = plan.release_s[chunk]
		assert_eq(seen.size(), 5)
		assert_lt(last, 1.2 - DT, "all gone inside 1.2 s with a tick to spare")
		assert_gt(plan.release_s[plan.order[1]], 0.1, "the others stay with the wreck for a moment")


func test_same_seed_same_plan_other_seed_other_order() -> void:
	var a := BreakupPlan.make(5, 0, 11)
	var b := BreakupPlan.make(5, 0, 11)
	assert_eq(a.order, b.order)
	assert_eq(a.release_s, b.release_s)
	assert_eq(a.kick_mps, b.kick_mps)
	assert_eq(a.spin, b.spin)
	var orders: Dictionary = {}
	for seed_value: int in 30:
		orders[BreakupPlan.make(5, 0, seed_value).order] = true
	assert_gt(orders.size(), 5, "the order of the rest depends on the seed")


func test_without_a_hit_point_the_whole_order_is_seeded() -> void:
	var firsts: Dictionary = {}
	for seed_value: int in 40:
		var plan := BreakupPlan.make(5, -1, seed_value)
		assert_eq(plan.release_s[plan.order[0]], 0.0)
		firsts[plan.order[0]] = true
		assert_eq(BreakupPlan.make(5, -1, seed_value).order, plan.order, "same seed, same order")
	assert_gt(firsts.size(), 2, "any part may go first")


func test_kicks_stay_inside_the_old_range_and_the_first_is_at_the_top_of_it() -> void:
	for seed_value: int in 30:
		var plan := BreakupPlan.make(5, 1, seed_value)
		for i: int in 5:
			assert_between(plan.kick_mps[i], BreakupPlan.KICK_MPS.x, BreakupPlan.KICK_MPS.y)
			assert_lte(rad_to_deg(plan.spin[i].length()), DebrisPool.MAX_SPIN_DEG_S + 1e-3)
			assert_between(plan.vent_roll[i], 0.0, 1.0)
			assert_almost_eq(plan.direction_hint[i].length(), 1.0, 1e-4)
		assert_gte(plan.kick_mps[1], BreakupPlan.FIRST_KICK_MPS.x, "the first part goes hard")


func test_a_plan_of_one_or_two_chunks_still_works() -> void:
	assert_eq(BreakupPlan.make(1, 0, 1).order, PackedInt32Array([0]))
	var two := BreakupPlan.make(2, 1, 1)
	assert_eq(two.order, PackedInt32Array([1, 0]))
	assert_lt(two.release_s[0], 1.2)
	assert_eq(BreakupPlan.make(0, -1, 1).order.size(), 0)


# --- the wreck ---------------------------------------------------------------------------------------------------


func test_the_wreck_integrates_rigidly_and_exactly() -> void:
	var wreck := _wreck()
	var start := Transform3D(wreck.basis, wreck.origin)
	var velocity: Vector3 = wreck.velocity
	var spin: Vector3 = wreck.spin
	for i: int in 55:  # before the first of the others is released
		wreck.advance(DT)
	var t: float = 55.0 * DT
	var expected_basis := Basis(spin.normalized(), spin.length() * t) * start.basis
	for i: int in 5:
		if wreck.is_released(i):
			continue
		var expected: Vector3 = start.origin + velocity * t + expected_basis * OFFSETS[i]
		assert_almost_eq(wreck.chunk_transform(i).origin, expected, Vector3.ONE * 1e-3)
		assert_almost_eq(wreck.chunk_transform(i).basis.get_euler(), expected_basis.get_euler(), Vector3.ONE * 1e-4)


func test_the_first_chunk_is_released_by_the_first_advance_and_the_rest_on_schedule() -> void:
	var wreck := _wreck(3, 9)
	assert_eq(wreck.advance(0.0), PackedInt32Array([3]))
	var released: Array[int] = [3]
	var t: float = 0.0
	while not wreck.finished():
		t += DT
		for i: int in wreck.advance(DT):
			assert_false(released.has(i))
			assert_gte(t, wreck.plan.release_s[i] - 1e-6, "not before its time")
			assert_lt(t, wreck.plan.release_s[i] + DT + 1e-6, "and on the first tick after it")
			released.append(i)
	assert_eq(released.size(), 5)
	assert_eq(released.slice(0, 5), Array(wreck.plan.order).slice(0, 5), "in the plan's order")
	assert_lt(t, 1.2)


func test_a_released_chunk_leaves_at_the_wrecks_motion_at_its_point_plus_its_kick() -> void:
	var wreck := _wreck(2, 5)
	for i: int in 20:
		wreck.advance(DT)
	var chunk: int = wreck.plan.order[1]
	while not wreck.is_released(chunk):
		wreck.advance(DT)
	var r: Vector3 = wreck.basis * OFFSETS[chunk]
	var rigid: Vector3 = wreck.velocity + wreck.spin.cross(r)
	var kick: Vector3 = wreck.release_velocity(chunk) - rigid
	assert_almost_eq(kick.length(), wreck.plan.kick_mps[chunk], 1e-3)
	assert_gt(kick.normalized().dot(r.normalized()), 0.999, "the kick is straight outward from the wreck's centre")


func test_a_shift_moves_the_wreck_and_nothing_inside_it() -> void:
	var a := _wreck(0, 4)
	var b := _wreck(0, 4)
	for i: int in 30:
		a.advance(DT)
		b.advance(DT)
	var offset := Vector3(5000.0, -20.0, 300.0)
	b.shift(offset)
	for i: int in 5:
		if a.is_released(i):
			continue
		assert_almost_eq(b.chunk_transform(i).origin - b.origin, a.chunk_transform(i).origin - a.origin, Vector3.ONE * 1e-3)
		assert_almost_eq(b.joint_position(i) - b.origin, a.joint_position(i) - a.origin, Vector3.ONE * 1e-3)
	for i: int in 10:
		a.advance(DT)
		b.advance(DT)
	assert_almost_eq(b.origin, a.origin - offset, Vector3.ONE * 5e-3)
