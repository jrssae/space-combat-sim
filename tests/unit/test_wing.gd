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
