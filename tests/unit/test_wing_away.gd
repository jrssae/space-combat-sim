extends GutTest
## A docked wingman is away, not lost (M8-T06, D82): it keeps its slot while it is inside the station.


func _member(callsign: String) -> Combatant:
	var c := Combatant.new()
	c.display_name = callsign
	c.faction = Factions.EARTH_ALLIANCE
	return c


func test_an_away_member_keeps_its_slot() -> void:
	var wing := Wing.new()
	var a := _member("ALPHA 2")
	var b := _member("ALPHA 3")
	wing.add_member(a, 1)
	wing.add_member(b, 2)
	wing.set_away(a, true)
	assert_true(wing.is_away(a))
	assert_false(wing.is_away(b))
	assert_eq(wing.slot_of(a), 1, "the slot is kept")
	assert_eq(wing.empty_slots(), PackedInt32Array([3]), "and nobody else is offered it")
	assert_false(wing.is_lost(1), "away is not lost")
	wing.set_away(a, false)
	assert_false(wing.is_away(a))


func test_only_a_member_can_be_away() -> void:
	var wing := Wing.new()
	var stranger := _member("BETA 2")
	wing.set_away(stranger, true)
	assert_false(wing.is_away(stranger))
	var a := _member("ALPHA 2")
	wing.add_member(a, 1)
	wing.set_away(a, true)
	wing.remove_member(a)
	assert_false(wing.is_away(a), "out of the wing, it is nobody's away member")


func test_a_member_on_its_way_to_the_bay_reads_docking_and_inside_it_reads_docked() -> void:
	var wing := Wing.new()
	var a := _member("ALPHA 2")
	var b := _member("ALPHA 3")
	wing.add_member(a, 1)
	wing.add_member(b, 2)
	assert_eq(wing.dock_status(a), "")
	wing.set_docking(a, true)
	assert_true(wing.is_docking(a))
	assert_false(wing.is_away(a), "still in play, flying in")
	assert_eq(wing.dock_status(a), "docking")
	assert_eq(wing.dock_status(b), "", "the others read as they did")
	wing.set_away(a, true)
	assert_false(wing.is_docking(a), "inside, it is no longer on its way")
	assert_eq(wing.dock_status(a), "docked")
	wing.set_away(a, false)
	assert_eq(wing.dock_status(a), "", "launched again: its own readout")


func test_the_docking_marks_end_with_the_membership() -> void:
	var wing := Wing.new()
	var a := _member("ALPHA 2")
	wing.set_docking(a, true)
	assert_false(wing.is_docking(a), "only a member can be docking")
	wing.add_member(a, 1)
	wing.set_docking(a, true)
	wing.remove_member(a)
	wing.add_member(a, 1)
	assert_eq(wing.dock_status(a), "", "shot down on its way in and back from the pool: no stale mark")
	wing.set_away(a, true)
	wing.remove_member(a)
	wing.add_member(a, 2)
	assert_eq(wing.dock_status(a), "")


func _wing_with(size: int) -> Wing:
	var wing := Wing.new(Wing.DEFAULT_NAME, _member("PLAYER"), size)
	for slot: int in range(1, size + 1):
		wing.add_member(_member("ALPHA %d" % (slot + 1)), slot)
	return wing


func _lose(wing: Wing, slots: Array[int]) -> void:
	for slot: int in slots:
		var member: Combatant = wing.member_at(slot)
		wing.remove_member(member)
		wing.mark_lost(slot, member.display_name)


func test_closing_gaps_leaves_an_away_members_place_alone() -> void:
	# M8-T13 closes the holes losses leave; a docked wingman's place is no hole and it is not moved (M8-T06).
	var wing: Wing = _wing_with(3)
	var docked: Combatant = wing.member_at(3)
	wing.set_away(docked, true)
	_lose(wing, [2])
	assert_eq(wing.close_gaps(), [] as Array[Vector2i], "the only ship behind the hole is away: nobody moves")
	assert_eq(wing.slot_of(docked), 3, "it keeps the slot it left")
	assert_true(wing.is_lost(2), "the loss is still a loss")
	# Back from the bay it is a wingman like any other: now it moves up.
	wing.set_away(docked, false)
	assert_eq(wing.close_gaps(), [Vector2i(3, 2)] as Array[Vector2i])
	assert_eq(wing.slot_of(docked), 2)


func test_the_ships_behind_an_away_member_move_up_past_it() -> void:
	var wing: Wing = _wing_with(10)
	var docked: Combatant = wing.member_at(5)
	var eight: Combatant = wing.member_at(8)
	var nine: Combatant = wing.member_at(9)
	wing.set_away(docked, true)
	_lose(wing, [1, 4])
	var moves: Array[Vector2i] = wing.close_gaps()
	assert_eq(wing.slot_of(docked), 5, "the away member's place is kept")
	for move: Vector2i in moves:
		assert_ne(move.x, 5, "it is never moved")
		assert_ne(move.y, 5, "and nobody is put in its place")
	assert_eq(wing.slot_of(eight), 1, "the ships behind it on its arm close the holes ahead of it")
	assert_eq(wing.slot_of(nine), 4)
	assert_eq(wing.members().size(), 8, "nobody is dropped")
	assert_eq(wing.close_gaps(), [] as Array[Vector2i], "closed up, it stays as it is")


func test_an_away_member_is_never_the_one_sent_across_to_even_the_arms() -> void:
	var wing: Wing = _wing_with(3)
	var docked: Combatant = wing.member_at(3)
	wing.set_away(docked, true)
	_lose(wing, [1])
	wing.close_gaps()
	assert_eq(wing.slot_of(docked), 3, "the arm's last ship would cross, but it is away: it stays")


func test_a_wing_whose_leader_is_away_keeps_its_orders_meaning() -> void:
	# Maintainer, 2026-11-20: while the player docks its wingmen follow their last order, hold fire or fight.
	var wing := Wing.new()
	assert_false(wing.leader_away)
	for order: AiContext.Order in [AiContext.Order.FORM_HOLD_FIRE, AiContext.Order.HOLD_POSITION]:
		wing.order = order
		assert_true(wing.holds_fire())
		assert_eq(wing.away_order(), AiContext.Order.FORM_HOLD_FIRE, "%s: still no shot" % AiContext.order_word(order))
	for order: AiContext.Order in [AiContext.Order.FORM_ON_ME, AiContext.Order.ATTACK_MY_TARGET, AiContext.Order.ENGAGE_AT_WILL,
			AiContext.Order.COVER_ME]:
		wing.order = order
		assert_false(wing.holds_fire())
		assert_eq(wing.away_order(), AiContext.Order.ENGAGE_AT_WILL, "%s: they fight on their own" % AiContext.order_word(order))
