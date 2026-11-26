extends GutTest
## A capital's break-up plan (M10-T11, D12.8: `BreakupPlan.for_sections`, `StagedWreck` with turned chunks): the section that
## blew goes at once, the others walk outward from it nearest first on the class's step, the reactors last after their own
## pause; each blows as it goes (its explosive kind, else structure; a section that already blew with none; the ancients' death
## one blast). Seeded, so the same seed gives the same plan. Pure; nothing here reads a clock.

# A line of sections along the keel: bow, magazine, spine, fuel, reactor, engines.
const CENTRES: Array[Vector3] = [
	Vector3(0.0, 0.0, -600.0), Vector3(0.0, 0.0, -400.0), Vector3(0.0, 0.0, -200.0), Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 200.0), Vector3(0.0, 0.0, 400.0),
]
const KINDS: Array[String] = ["structure", "magazine", "structure", "fuel", "reactor", "engine"]
const NUMBERS: Dictionary = {"step_s": [0.5, 1.0], "reactor_after_s": 2.0, "kick_mps": [1.0, 4.0], "spin_deg_s": 2.0,
		"fire_s": [3.0, 6.0]}


func _plan(first: int, seed_value: int = 11, numbers: Dictionary = NUMBERS, spent := PackedByteArray()) -> BreakupPlan:
	return BreakupPlan.for_sections(PackedVector3Array(CENTRES), PackedStringArray(KINDS), first, spent, numbers, seed_value)


func test_the_section_that_blew_goes_first_and_the_rest_walk_outward_with_the_reactor_last() -> void:
	var plan: BreakupPlan = _plan(1)
	assert_eq(plan.count, 6)
	assert_eq(plan.order[0], 1, "the magazine that blew")
	assert_eq(plan.release_s[1], 0.0, "at the instant of death")
	assert_eq(plan.order[plan.order.size() - 1], 4, "the reactor last")
	var last_d: float = -1.0
	for rank: int in range(1, plan.order.size() - 1):
		var d: float = CENTRES[plan.order[rank]].distance_to(CENTRES[1])
		assert_gte(d, last_d, "nearest first (rank %d)" % rank)
		last_d = d


func test_each_step_follows_the_last_by_the_classs_step_and_the_reactor_waits_its_own_pause() -> void:
	var plan: BreakupPlan = _plan(0)
	for rank: int in range(1, plan.order.size()):
		var gap: float = plan.release_s[plan.order[rank]] - plan.release_s[plan.order[rank - 1]]
		if KINDS[plan.order[rank]] == "reactor":
			assert_almost_eq(gap, 2.0, 1e-9, "the reactor's pause")
		else:
			assert_between(gap, 0.5, 1.0, "the step (rank %d)" % rank)
	assert_almost_eq(plan.span_s(), plan.release_s[4], 1e-9, "the reactor ends it")


func test_each_section_blows_with_its_kind_or_structure_and_a_spent_one_with_none() -> void:
	var spent := PackedByteArray([0, 0, 0, 1, 0, 0])
	var plan: BreakupPlan = _plan(1, 11, NUMBERS, spent)
	assert_eq(plan.blast_kind[1], "magazine")
	assert_eq(plan.blast_kind[0], BlastTable.STRUCTURE)
	assert_eq(plan.blast_kind[5], BlastTable.STRUCTURE, "an engine section has no row of its own")
	assert_eq(plan.blast_kind[4], "reactor")
	assert_eq(plan.blast_kind[3], "", "the fuel that already blew")


func test_the_first_blows_even_when_spent_it_is_what_killed_the_ship() -> void:
	var plan: BreakupPlan = _plan(3, 11, NUMBERS, PackedByteArray([0, 0, 0, 1, 0, 0]))
	assert_eq(plan.blast_kind[3], "fuel")


func test_the_ancients_death_is_one_blast() -> void:
	var numbers: Dictionary = NUMBERS.duplicate()
	numbers["one_blast"] = true
	var plan: BreakupPlan = _plan(0, 11, numbers)
	assert_eq(plan.blast_kind[0], BlastTable.DEFAULT_KIND, "a structure section that goes first blows with the reactor's row")
	for i: int in range(1, plan.count):
		assert_eq(plan.blast_kind[plan.order[i]], "", "the rest come apart with no blast")


func test_a_reactor_that_goes_first_leaves_the_rest_in_order() -> void:
	var plan: BreakupPlan = _plan(4)
	assert_eq(plan.order[0], 4)
	assert_eq(plan.order.size(), 6)
	assert_eq(plan.order.count(4), 1, "once")


func test_same_seed_same_plan_other_seed_other_draws() -> void:
	var a: BreakupPlan = _plan(1, 5)
	var b: BreakupPlan = _plan(1, 5)
	var c: BreakupPlan = _plan(1, 6)
	assert_eq(a.order, b.order)
	assert_eq(a.release_s, b.release_s)
	assert_eq(a.kick_mps, b.kick_mps)
	assert_eq(a.spin, b.spin)
	assert_eq(a.fire_s, b.fire_s)
	assert_ne(a.release_s, c.release_s, "the steps are drawn from the seed")


func test_kicks_spins_and_fires_stay_in_the_classs_ranges() -> void:
	var plan: BreakupPlan = _plan(1)
	for i: int in plan.count:
		assert_between(plan.kick_mps[i], 1.0, 4.0)
		assert_lte(plan.spin[i].length(), deg_to_rad(2.0) + 1e-9)
		assert_between(plan.fire_s[i], 3.0, 6.0)


func test_a_wreck_holds_turned_chunks_turned_and_moves_them_rigidly() -> void:
	var plan: BreakupPlan = _plan(1)
	var offsets: Array[Vector3] = []
	var poses: Array[Transform3D] = []
	for c: Vector3 in CENTRES:
		offsets.append(c)
		poses.append(Transform3D(Basis.IDENTITY, c))
	poses[5] = Transform3D(Basis(Vector3.BACK, 0.8), Vector3(0.0, 30.0, 400.0))  # a rotor's chunk stopped mid-turn
	var xform := Transform3D(Basis(Vector3.UP, 0.3), Vector3(1000.0, 0.0, 0.0))
	var wreck := StagedWreck.new(plan, offsets, offsets, xform, Vector3(0.0, 0.0, -50.0), Vector3(0.0, 0.01, 0.0))
	wreck.set_local_poses(poses)
	assert_almost_eq(wreck.offset_of(5), Vector3(0.0, 30.0, 400.0), Vector3.ONE * 1e-6, "its offset is its pose's origin")
	var held: Transform3D = wreck.chunk_transform(5)
	assert_almost_eq(held.origin, xform * Vector3(0.0, 30.0, 400.0), Vector3.ONE * 1e-3)
	assert_almost_eq(held.basis.get_euler(), (xform.basis * Basis(Vector3.BACK, 0.8)).get_euler(), Vector3.ONE * 1e-5,
			"turned as the rotor stopped")
	var due: PackedInt32Array = wreck.advance(0.0)
	assert_eq(due, PackedInt32Array([1]), "the first goes at once")
	wreck.advance(1.0)
	assert_almost_eq(wreck.origin, xform.origin + Vector3(0.0, 0.0, -50.0), Vector3.ONE * 1e-6, "the wreck drifts on")
