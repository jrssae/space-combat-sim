extends GutTest
## Wing (M3-T07, architecture §16 D36): who flies in which slot, the order and the acknowledgement lines, and how the
## orders gate the behaviours. Pure: members are `Combatant` handles without ships.


func _member(callsign: String) -> Combatant:
	var c := Combatant.new()
	c.display_name = callsign
	c.faction = Factions.EARTH_ALLIANCE
	return c


func test_a_new_wing_is_alpha_covering_its_leader_in_a_finger_four() -> void:
	var leader := _member("PLAYER")
	var wing := Wing.new(Wing.DEFAULT_NAME, leader)
	assert_eq(wing.name, "ALPHA")
	assert_eq(wing.leader, leader)
	assert_eq(wing.order, AiContext.Order.COVER_ME, "the planner's default order")
	assert_eq(wing.engage_radius_m, 2000.0)
	assert_eq(wing.formation.shape, Formation.Shape.FINGER_FOUR)
	assert_eq(wing.size, 3, "three wingmen (maintainer Q4)")
	assert_eq(wing.members(), [] as Array[Combatant])
	assert_eq(wing.empty_slots(), PackedInt32Array([1, 2, 3]))


func test_members_take_the_first_free_slot_or_the_one_asked_for() -> void:
	var wing := Wing.new()
	var a := _member("ALPHA 2")
	var b := _member("ALPHA 3")
	var c := _member("ALPHA 4")
	assert_eq(wing.add_member(c, 3), 3)
	assert_eq(wing.add_member(a), 1, "the first free slot")
	assert_eq(wing.add_member(b), 2)
	assert_eq(wing.members(), [a, b, c] as Array[Combatant], "in slot order")
	assert_eq(wing.slot_of(b), 2)
	assert_eq(wing.member_at(3), c)
	assert_null(wing.member_at(0), "slot 0 is the leader's")
	assert_true(wing.empty_slots().is_empty())
	assert_true(wing.is_full())


func test_a_full_wing_a_taken_slot_a_bad_slot_and_a_second_add_are_refused() -> void:
	var wing := Wing.new()
	var a := _member("ALPHA 2")
	assert_eq(wing.add_member(a, 2), 2)
	assert_eq(wing.add_member(_member("X"), 2), -1, "slot 2 is taken")
	assert_eq(wing.add_member(a), -1, "already a member")
	assert_eq(wing.add_member(_member("Y"), 0), -1, "slot 0 is the leader's")
	assert_eq(wing.add_member(_member("Z"), 4), -1, "a finger-four has three member slots")
	assert_eq(wing.add_member(null), -1)
	wing.add_member(_member("B"))
	wing.add_member(_member("C"))
	assert_eq(wing.add_member(_member("D")), -1, "full")
	assert_eq(wing.slot_of(_member("nobody")), -1)


func test_resize_grows_the_slots_and_never_cuts_a_flown_one() -> void:
	var wing := Wing.new()
	var a := _member("ALPHA 2")
	var d := _member("ALPHA 4")
	wing.add_member(a, 1)
	wing.add_member(d, 3)
	wing.mark_lost(2)
	assert_true(wing.resize(11), "a station launch makes room for the rest of Alpha (M7-T58)")
	assert_eq(wing.size, 11)
	assert_eq(wing.slot_of(a), 1, "members keep their slots")
	assert_eq(wing.slot_of(d), 3)
	assert_true(wing.is_lost(2), "a lost slot stays lost")
	assert_false(wing.is_lost(4), "a new slot is not")
	assert_eq(wing.empty_slots(), PackedInt32Array([2, 4, 5, 6, 7, 8, 9, 10, 11]))
	var e := _member("ALPHA 12")
	assert_eq(wing.add_member(e, 11), 11)
	assert_false(wing.resize(3), "slot 11 is flown")
	assert_eq(wing.size, 11, "a refused resize changes nothing")
	wing.remove_member(e)
	assert_true(wing.resize(3), "back to the finger-four once the slots past it are empty")
	assert_eq(wing.empty_slots(), PackedInt32Array([2]))


func test_removing_a_member_frees_its_slot() -> void:
	var wing := Wing.new()
	var a := _member("ALPHA 2")
	var b := _member("ALPHA 3")
	wing.add_member(a)
	wing.add_member(b)
	assert_true(wing.remove_member(a))
	assert_false(wing.remove_member(a), "only once")
	assert_eq(wing.slot_of(a), -1)
	assert_eq(wing.empty_slots(), PackedInt32Array([1, 3]))
	assert_eq(wing.members(), [b] as Array[Combatant])


func test_callsigns_number_the_slots_from_the_leader() -> void:
	var wing := Wing.new()
	assert_eq(wing.callsign(0), "ALPHA 1", "the leader")
	assert_eq(wing.callsign(1), "ALPHA 2")
	assert_eq(wing.callsign(3), "ALPHA 4")


func test_while_the_leader_is_dead_the_wing_engages_at_will() -> void:
	var wing := Wing.new()
	wing.order = AiContext.Order.FORM_ON_ME
	assert_eq(wing.effective_order(true), AiContext.Order.FORM_ON_ME)
	assert_eq(wing.effective_order(false), AiContext.Order.ENGAGE_AT_WILL)
	assert_eq(wing.order, AiContext.Order.FORM_ON_ME, "and resumes its order when the leader is back")


func test_the_first_member_acknowledges_every_order_with_one_line() -> void:
	var wing := Wing.new()
	wing.add_member(_member("ALPHA 3"), 2)
	wing.add_member(_member("ALPHA 4"), 3)
	assert_eq(wing.speaker(), "ALPHA 3", "the lowest slot that is filled")
	assert_eq(wing.ack_for(AiContext.Order.FORM_ON_ME), "ALPHA 3: COPY, FORMING UP")
	assert_eq(wing.ack_for(AiContext.Order.COVER_ME), "ALPHA 3: COPY, COVERING YOU")
	assert_eq(wing.ack_for(AiContext.Order.ENGAGE_AT_WILL), "ALPHA 3: COPY, ENGAGING AT WILL")
	assert_eq(wing.ack_for(AiContext.Order.ATTACK_MY_TARGET, "RAIDER 3"), "ALPHA 3: COPY, ATTACKING RAIDER 3")
	assert_eq(wing.refusal_no_hostile(), "ALPHA 3: UNABLE, NO HOSTILE SELECTED")


func test_a_wing_without_members_says_so() -> void:
	var wing := Wing.new()
	assert_eq(wing.speaker(), "ALPHA")
	assert_eq(wing.ack_for(AiContext.Order.FORM_ON_ME), "ALPHA: NO WINGMEN")
	assert_eq(wing.refusal_no_hostile(), "ALPHA: UNABLE, NO HOSTILE SELECTED")


func test_slot_offsets_follow_the_wings_formation() -> void:
	var wing := Wing.new()
	assert_eq(wing.slot_offset(3), Formation.new().offset(3))
	wing.formation.shape = Formation.Shape.WEDGE
	assert_eq(wing.slot_offset(3), Formation.new(Formation.Shape.WEDGE).offset(3))


# --- orders gate the behaviours -------------------------------------------------------------------------------------


# A wing of `size` slots with a member in each of `slots`.
func _wing_with(size: int, slots: Array[int]) -> Wing:
	var wing := Wing.new(Wing.DEFAULT_NAME, _member("PLAYER"), size)
	for slot: int in slots:
		wing.add_member(_member("ALPHA %d" % (slot + 1)), slot)
	return wing


func test_a_big_wing_fills_in_slot_order_and_its_centre_last() -> void:
	# M7-T74: Alpha grown to eleven around the player's three wingmen takes its launched ships in slot order, the arms even.
	var alpha: Wing = _wing_with(11, [1, 2, 3])
	assert_eq(alpha.fill_order(), PackedInt32Array([4, 5, 6, 7, 8, 9, 10, 11]))
	assert_eq(_wing_with(11, []).fill_order(), PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]))
	assert_eq(_wing_with(3, []).fill_order(), PackedInt32Array([1, 2, 3]), "a finger-four as before")
	var joining := Wing.new()
	for n: int in 3:
		assert_eq(joining.add_member(_member("ALPHA %d" % (n + 2))), n + 1, "the scenario's wingmen keep their slots")


func test_a_newcomer_takes_the_slot_that_evens_the_arms() -> void:
	# Full but for ALPHA 3 (slot 2, right) and ALPHA 5 (slot 4, left) shot down, and one more gone on the right (slot 7).
	var wing: Wing = _wing_with(11, [1, 3, 5, 6, 8, 9, 10, 11])
	assert_eq(wing.fill_order(), PackedInt32Array([2, 4, 7]), "the short right arm first, then the nearest")
	var c := _member("NEW")
	assert_eq(wing.add_member(c), 2)
	for slot: int in range(1, 12):
		if wing.member_at(slot) != null:
			assert_eq(wing.slot_offset(slot), wing.formation.offset(slot, 11), "slot %d stays put" % slot)


func test_a_wing_growing_for_a_launch_moves_none_of_its_wingmen() -> void:
	var wing: Wing = _wing_with(3, [1, 2, 3])
	var before: Array[Vector3] = [wing.slot_offset(1), wing.slot_offset(2), wing.slot_offset(3)]
	assert_true(wing.resize(11))
	for slot: int in range(1, 4):
		assert_eq(wing.slot_offset(slot), before[slot - 1], "slot %d" % slot)
	assert_eq(wing.slot_offset(11).x, 0.0, "the twelfth on the centreline")


# --- closing the gaps losses leave (M8-T13) --------------------------------------------------------------------------
# A finger-four's arms, nearest the leader first: left 1, 4, 5, 8, 9; right 2, 3, 6, 7, 10; an eleven-slot wing's centre 11.


# Shoots down the members in `slots`: they leave the wing and their slots read lost under their callsigns.
func _lose(wing: Wing, slots: Array[int]) -> void:
	for slot: int in slots:
		var member: Combatant = wing.member_at(slot)
		wing.remove_member(member)
		wing.mark_lost(slot, member.display_name)


# The callsigns by slot, "-" for an empty one.
func _names(wing: Wing) -> Array[String]:
	var out: Array[String] = []
	for slot: int in range(1, wing.size + 1):
		out.append(wing.member_at(slot).display_name if wing.member_at(slot) != null else "-")
	return out


# How many ships fly on the left arm, the right arm and the centre slot.
func _arms(wing: Wing) -> Vector3i:
	var count := Vector3i.ZERO
	for slot: int in range(1, wing.size + 1):
		if wing.member_at(slot) != null:
			count[wing.formation.side(slot, wing.size) + 1] += 1
	return Vector3i(count.x, count.z, count.y)


# The wing flies a shape with no hole: each arm filled from the leader out, the arms within one ship of each other, and the
# centre slot flown only when both arms are full.
func _assert_no_holes(wing: Wing, what: String) -> void:
	var open_arm_slot: bool = false
	for arm_side: int in [-1, 1]:
		var slots: Array[int] = []
		for slot: int in range(1, wing.size + 1):
			if wing.formation.side(slot, wing.size) == arm_side:
				slots.append(slot)
		slots.sort_custom(func(a: int, b: int) -> bool:
			return wing.slot_offset(a).length_squared() < wing.slot_offset(b).length_squared())
		var seen_empty: bool = false
		for slot: int in slots:
			if wing.member_at(slot) == null:
				seen_empty = true
			elif seen_empty:
				fail_test("%s: slot %d is flown behind an empty slot of its arm (%s)" % [what, slot, _names(wing)])
				return
		open_arm_slot = open_arm_slot or seen_empty
	var arms: Vector3i = _arms(wing)
	assert_lte(absi(arms.x - arms.y), 1, "%s: the arms are within one ship (%s)" % [what, _names(wing)])
	assert_false(arms.z > 0 and open_arm_slot, "%s: the centre slot is flown beside an open arm slot (%s)" % [what, _names(wing)])


func test_a_finger_four_closes_up_behind_each_of_its_losses() -> void:
	var front: Wing = _wing_with(3, [1, 2, 3])
	_lose(front, [1])
	assert_eq(front.close_gaps(), [Vector2i(3, 1)] as Array[Vector2i], "the left arm is empty and the right two deep: its last crosses")
	assert_eq(_names(front), ["ALPHA 4", "ALPHA 3", "-"] as Array[String])
	var middle: Wing = _wing_with(3, [1, 2, 3])
	_lose(middle, [2])
	assert_eq(middle.close_gaps(), [Vector2i(3, 2)] as Array[Vector2i], "ALPHA 4 moves up its own arm")
	assert_eq(_names(middle), ["ALPHA 2", "ALPHA 4", "-"] as Array[String])
	var back: Wing = _wing_with(3, [1, 2, 3])
	_lose(back, [3])
	assert_eq(back.close_gaps(), [] as Array[Vector2i], "nobody flew behind it")
	assert_eq(_names(back), ["ALPHA 2", "ALPHA 3", "-"] as Array[String])


func test_the_wingmen_behind_a_loss_each_move_up_one_place_on_their_arm() -> void:
	var front: Wing = _wing_with(10, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	_lose(front, [1])
	assert_eq(front.close_gaps(), [Vector2i(4, 1), Vector2i(5, 4), Vector2i(8, 5), Vector2i(9, 8)] as Array[Vector2i],
			"the left arm moves up; the right arm, now one longer, stays")
	assert_eq(front.empty_slots(), PackedInt32Array([9]), "the hole is at the back of the arm")
	_assert_no_holes(front, "front")
	var middle: Wing = _wing_with(10, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	_lose(middle, [6])
	assert_eq(middle.close_gaps(), [Vector2i(7, 6), Vector2i(10, 7)] as Array[Vector2i])
	assert_eq(middle.member_at(1).display_name, "ALPHA 2", "the other arm is left alone")
	_assert_no_holes(middle, "middle")
	var back: Wing = _wing_with(10, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	_lose(back, [10])
	assert_eq(back.close_gaps(), [] as Array[Vector2i], "the last of an arm leaves no hole")


func test_several_losses_at_once_close_up_and_even_the_arms() -> void:
	var wing: Wing = _wing_with(10, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	_lose(wing, [1, 4, 6])
	assert_eq(wing.close_gaps(), [Vector2i(5, 1), Vector2i(8, 4), Vector2i(9, 5), Vector2i(7, 6), Vector2i(10, 7)] as Array[Vector2i])
	assert_eq(_arms(wing), Vector3i(3, 4, 0), "three left, four right: even enough, nobody crosses")
	_assert_no_holes(wing, "three down")
	_lose(wing, [1, 4])
	var moves: Array[Vector2i] = wing.close_gaps()
	assert_eq(moves, [Vector2i(5, 1), Vector2i(7, 4)] as Array[Vector2i], "the left moves up, then the right arm's last evens them")
	assert_eq(_arms(wing), Vector3i(2, 3, 0))
	_assert_no_holes(wing, "five down")
	assert_eq(wing.members().size(), 5, "nobody is dropped")
	assert_eq(wing.close_gaps(), [] as Array[Vector2i], "closed up, it stays as it is")


func test_the_centre_ship_moves_out_to_an_arm_that_has_room() -> void:
	# The centre slot is the last a newcomer takes, so ten ships fly five a side with nobody behind the leader.
	var wing: Wing = _wing_with(11, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
	_lose(wing, [5])
	assert_eq(wing.close_gaps(), [Vector2i(8, 5), Vector2i(9, 8), Vector2i(11, 9)] as Array[Vector2i])
	assert_eq(_arms(wing), Vector3i(5, 5, 0))
	assert_eq(wing.member_at(9).display_name, "ALPHA 12")
	_assert_no_holes(wing, "eleven less one")


func test_arms_that_are_already_even_send_nobody_across() -> void:
	var pair: Wing = _wing_with(2, [1, 2])
	_lose(pair, [1])
	assert_eq(pair.close_gaps(), [] as Array[Vector2i], "a flight of three's last wingman keeps its side")
	assert_eq(pair.slot_of(pair.members()[0]), 2)
	var wedge: Wing = _wing_with(4, [1, 2, 3, 4])
	wedge.formation.shape = Formation.Shape.WEDGE
	_lose(wedge, [1])
	assert_eq(wedge.close_gaps(), [Vector2i(3, 1)] as Array[Vector2i], "a wedge's left arm is slots 1 and 3")
	assert_eq(_arms(wedge), Vector3i(1, 2, 0))


func test_a_lost_callsign_goes_to_the_back_with_the_hole() -> void:
	var wing: Wing = _wing_with(3, [1, 2, 3])
	_lose(wing, [1])
	assert_eq(wing.lost_callsign(1), "ALPHA 2")
	wing.close_gaps()
	assert_false(wing.is_lost(1), "ALPHA 4 flies there now")
	assert_true(wing.is_lost(3), "the hole it left is the lost one")
	assert_eq(wing.lost_callsign(3), "ALPHA 2", "still under the downed pilot's callsign")
	assert_eq(wing.lost_callsign(2), "", "a flown slot has none")
	var big: Wing = _wing_with(10, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	_lose(big, [1, 5])
	big.close_gaps()
	# The left arm closes up to three; the right arm's last (slot 10) crosses to even them, leaving its place as a hole.
	assert_eq(big.empty_slots(), PackedInt32Array([9, 10]))
	assert_eq(big.lost_callsign(9), "ALPHA 6", "each hole keeps the callsign of one of the two that went down")
	assert_eq(big.lost_callsign(10), "ALPHA 2")
	# A member released, not shot down, leaves a hole that closes the same way and marks nothing lost.
	var released: Wing = _wing_with(3, [1, 2, 3])
	released.remove_member(released.member_at(2))
	assert_eq(released.close_gaps(), [Vector2i(3, 2)] as Array[Vector2i])
	assert_false(released.is_lost(2) or released.is_lost(3))
	assert_eq(released.lost_callsign(0) + released.lost_callsign(4), "", "out of range")


func test_a_newcomer_after_a_loss_takes_the_place_at_the_back() -> void:
	var wing: Wing = _wing_with(10, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	_lose(wing, [4])
	wing.close_gaps()
	var before: Array[String] = _names(wing)
	var fresh := _member("ALPHA 5")
	assert_eq(wing.add_member(fresh), 9, "the open slot at the end of the left arm")
	assert_false(wing.is_lost(9))
	assert_eq(wing.close_gaps(), [] as Array[Vector2i], "a newcomer moves nobody")
	before[8] = "ALPHA 5"
	assert_eq(_names(wing), before)


func test_any_losses_in_any_shape_leave_no_hole_and_keep_every_survivor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8013
	for shape: int in Formation.NAMES.size():
		for size: int in range(1, 13):
			for _round: int in 12:
				var all: Array[int] = []
				all.assign(range(1, size + 1))
				var wing: Wing = _wing_with(size, all)
				wing.formation.shape = shape as Formation.Shape
				var what: String = "%s of %d" % [Formation.NAMES[shape], size]
				assert_eq(wing.close_gaps(), [] as Array[Vector2i], "%s: a full wing has nothing to close" % what)
				var left: Array[Combatant] = wing.members()
				for _wave: int in 3:  # losses in several goes, closing up after each
					var down: Array[int] = []
					for slot: int in range(1, size + 1):
						if wing.member_at(slot) != null and rng.randf() < 0.3:
							down.append(slot)
							left.erase(wing.member_at(slot))
					_lose(wing, down)
					var lost_before: int = _lost_count(wing)
					var sides: Dictionary = _sides(wing)
					var uneven: bool = absi(_arms(wing).x - _arms(wing).y) > 1 or _arms(wing).z > 0
					var moves: Array[Vector2i] = wing.close_gaps()
					_assert_no_holes(wing, "%s less %s" % [what, down])
					assert_eq(wing.members().size(), left.size(), "%s: every survivor still flies" % what)
					for member: Combatant in left:
						assert_gt(wing.slot_of(member), 0, "%s: %s still flies" % [what, member.display_name])
						if not uneven:
							assert_eq(wing.formation.side(wing.slot_of(member), size), sides[member],
									"%s: %s keeps its side while the arms are even" % [what, member.display_name])
					assert_eq(_lost_count(wing), lost_before, "%s: every loss still reads lost" % what)
					assert_lte(moves.size(), size, "%s: no ship moves twice over" % what)
					assert_eq(wing.close_gaps(), [] as Array[Vector2i], "%s: closed up, it stays" % what)
					assert_eq(_shape_of_newcomers(wing), _sorted_arms(wing), "%s: the shape that many newcomers would build" % what)


func test_a_change_of_shape_closes_up_again() -> void:
	# A wedge's arms are the odd and the even slots, a finger-four's are not: what is even in one may not be in the other.
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for _round: int in 40:
		var all: Array[int] = []
		all.assign(range(1, 12))
		var wing: Wing = _wing_with(11, all)
		var down: Array[int] = []
		for slot: int in range(1, 12):
			if rng.randf() < 0.4:
				down.append(slot)
		_lose(wing, down)
		wing.close_gaps()
		for shape: Formation.Shape in [Formation.Shape.WEDGE, Formation.Shape.LINE_ABREAST, Formation.Shape.FINGER_FOUR]:
			wing.formation.shape = shape
			wing.close_gaps()
			_assert_no_holes(wing, "%s after %s went down" % [Formation.NAMES[shape], down])


func _lost_count(wing: Wing) -> int:
	var n: int = 0
	for slot: int in range(1, wing.size + 1):
		n += 1 if wing.is_lost(slot) else 0
	return n


# Each member's side of the leader.
func _sides(wing: Wing) -> Dictionary:
	var out: Dictionary = {}
	for member: Combatant in wing.members():
		out[member] = wing.formation.side(wing.slot_of(member), wing.size)
	return out


# The arms' counts, the shorter first, and the centre's: a shape and its mirror read the same.
func _sorted_arms(wing: Wing) -> Vector3i:
	var arms: Vector3i = _arms(wing)
	return Vector3i(mini(arms.x, arms.y), maxi(arms.x, arms.y), arms.z)


# `_sorted_arms` of a wing of the same size and shape that as many ships joined one by one.
func _shape_of_newcomers(wing: Wing) -> Vector3i:
	var built := Wing.new(wing.name, wing.leader, wing.size)
	built.formation.shape = wing.formation.shape
	for n: int in wing.members().size():
		built.add_member(_member("N %d" % n))
	return _sorted_arms(built)


func _ctx(order: AiContext.Order, hull: float, contacts: Array[Contact]) -> AiContext:
	var p := Perception.new()
	p.faction = Factions.EARTH_ALLIANCE
	p.hull_fraction = hull
	p.contacts = contacts
	p.self_id = 1
	var ctx := AiContext.new()
	ctx.order = order
	ctx.refresh(p)
	return ctx


func _raider() -> Contact:
	var c := Contact.new()
	c.id = 20
	c.relation = Factions.Relation.HOSTILE
	c.faction = Factions.RAIDERS
	c.position = Vector3(0.0, 0.0, -800.0)
	c.is_ship = true
	return c


func test_form_on_me_allows_no_retreat_but_still_an_evasion() -> void:
	var profile := AiProfile.new()
	profile.retreat_below = 0.25
	var retreat := BehaviourRetreat.new(profile)
	assert_gt(retreat.score(_ctx(AiContext.Order.COVER_ME, 0.1, [_raider()])), 0.0, "cover me: a hurt ship retreats")
	var form: AiContext = _ctx(AiContext.Order.FORM_ON_ME, 0.1, [_raider()])
	assert_eq(retreat.score(form), 0.0, "form on me: formation only")
	assert_false(form.may_retreat())
	form.perception.last_hit_s = form.perception.now_s
	assert_gt(BehaviourEvade.new(1).score(form), 0.0, "evade is still allowed")


func test_clear_wing_gives_the_pilot_back_its_own_orders() -> void:
	var ctx: AiContext = _ctx(AiContext.Order.FORM_ON_ME, 1.0, [])
	ctx.leader_id = 30
	ctx.leader_target_id = 20
	ctx.engage_radius_m = 500.0
	ctx.has_slot = true
	ctx.slot_offset = Vector3(-40.0, 0.0, 40.0)
	ctx.leader_link_position = UniversePos.new()
	ctx.leader_link_velocity = Vector3.ONE
	ctx.clear_wing()
	assert_eq(ctx.order, AiContext.Order.ENGAGE_AT_WILL)
	assert_eq([ctx.leader_id, ctx.leader_target_id], [0, 0])
	assert_eq(ctx.engage_radius_m, AiContext.DEFAULT_ENGAGE_RADIUS_M)
	assert_false(ctx.has_slot)
	assert_eq(ctx.slot_offset, Vector3.ZERO)
	assert_null(ctx.leader_link_position)
	assert_eq(ctx.leader_link_velocity, Vector3.ZERO)


func test_has_attackable_follows_the_order_gate() -> void:
	var raider: Contact = _raider()
	assert_true(_ctx(AiContext.Order.ENGAGE_AT_WILL, 1.0, [raider]).has_attackable())
	assert_false(_ctx(AiContext.Order.ENGAGE_AT_WILL, 1.0, []).has_attackable(), "nothing in sight")
	assert_false(_ctx(AiContext.Order.FORM_ON_ME, 1.0, [raider]).has_attackable())
	var ordered: AiContext = _ctx(AiContext.Order.ATTACK_MY_TARGET, 1.0, [raider])
	assert_false(ordered.has_attackable(), "the leader has no target")
	ordered.leader_target_id = 20
	assert_true(ordered.has_attackable())


func test_a_downed_members_slot_stays_lost_until_someone_takes_it() -> void:
	var wing := Wing.new(Wing.DEFAULT_NAME, _member("PLAYER"))
	var two := _member("ALPHA 2")
	assert_eq(wing.add_member(two), 1)
	wing.mark_lost(1)
	assert_false(wing.is_lost(1), "a flown slot is not lost")
	wing.remove_member(two)
	wing.mark_lost(1)
	assert_true(wing.is_lost(1), "shot down: the slot reads DOWN")
	assert_false(wing.is_lost(2), "a slot never flown is not lost")
	assert_false(wing.is_lost(0) or wing.is_lost(4), "out of range")
	assert_eq(wing.add_member(_member("ALPHA 2")), 1)
	assert_false(wing.is_lost(1), "a replacement clears it")
