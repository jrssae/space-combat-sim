extends GutTest
## Formation slots (M3-T07, architecture §16 D36) and the formation behaviour on scripted `AiContext`s: no ship, no physics.
## Offsets are in the leader's body frame: x right, y up, +z behind (the nose is -Z).

const S: float = Formation.DEFAULT_SPACING_M
const TOL: float = 1e-4
const DT: float = 1.0 / 60.0


# --- Formation ---------------------------------------------------------------------------------------------------


func test_the_default_is_a_finger_four_at_40_m() -> void:
	var f := Formation.new()
	assert_eq(f.shape, Formation.Shape.FINGER_FOUR)
	assert_eq(f.shape_name(), &"finger_four")
	assert_eq(f.spacing_m, 40.0)


func test_finger_four_two_left_and_behind_three_right_and_behind_four_right_of_three_and_further_back() -> void:
	var f := Formation.new()
	assert_eq(f.offset(0), Vector3.ZERO, "the leader sits at the origin")
	var two: Vector3 = f.offset(1)
	var three: Vector3 = f.offset(2)
	var four: Vector3 = f.offset(3)
	assert_lt(two.x, 0.0, "#2 left")
	assert_gt(two.z, 0.0, "#2 behind")
	assert_gt(three.x, 0.0, "#3 right")
	assert_gt(three.z, 0.0, "#3 behind")
	assert_gt(four.x, three.x, "#4 right of #3")
	assert_gt(four.z, three.z, "#4 further back than #3")
	for v: Vector3 in [two, three, four]:
		assert_eq(v.y, 0.0, "level")
	assert_eq(two, Vector3(-S, 0.0, S))
	assert_eq(three, Vector3(S, 0.0, S))
	assert_eq(four, Vector3(2.0 * S, 0.0, 2.0 * S))


func test_offsets_scale_with_the_spacing() -> void:
	var f := Formation.new(Formation.Shape.FINGER_FOUR, 60.0)
	assert_eq(f.offset(3), Vector3(120.0, 0.0, 120.0))
	f.spacing_m = 40.0
	assert_eq(f.offset(3), Vector3(80.0, 0.0, 80.0))


func test_wedge_is_a_v_with_four_on_the_left() -> void:
	var f := Formation.new(Formation.Shape.WEDGE)
	assert_eq(f.offset(1), Vector3(-S, 0.0, S))
	assert_eq(f.offset(2), Vector3(S, 0.0, S))
	assert_eq(f.offset(3), Vector3(-2.0 * S, 0.0, 2.0 * S), "#4 left of #2, further back")
	assert_eq(f.offset(4), Vector3(2.0 * S, 0.0, 2.0 * S))


func test_line_abreast_is_the_finger_four_on_the_leaders_line() -> void:
	var f := Formation.new(Formation.Shape.LINE_ABREAST)
	var finger := Formation.new()
	for slot: int in range(1, 4):
		assert_eq(f.offset(slot).z, 0.0, "slot %d abreast" % slot)
		assert_eq(f.offset(slot).x, finger.offset(slot).x, "slot %d keeps its side and order" % slot)


func test_no_two_slots_are_closer_than_the_spacing() -> void:
	# Avoidance pushes ships closer than about 35 m apart (two bounding radii plus 15 m), so slots never ask for that.
	for shape: int in Formation.NAMES.size():
		var f := Formation.new(shape as Formation.Shape)
		for a: int in 4:
			for b: int in range(a + 1, 4):
				assert_gte(f.offset(a).distance_to(f.offset(b)), S - TOL, "%s slots %d and %d" % [Formation.NAMES[shape], a, b])


func test_names_round_trip_and_unknown_names_are_minus_one() -> void:
	for shape: int in Formation.NAMES.size():
		assert_eq(Formation.shape_from_name(String(Formation.NAMES[shape])), shape)
	assert_eq(Formation.shape_from_name("WEDGE"), Formation.Shape.WEDGE, "case-insensitive")
	assert_eq(Formation.shape_from_name("box"), -1)
	assert_eq(Formation.NAMES, [&"finger_four", &"wedge", &"line_abreast"] as Array[StringName])


func test_slot_point_rotates_the_offset_into_the_leaders_frame() -> void:
	var at := Vector3(100.0, 50.0, -20.0)
	var o := Vector3(-40.0, 0.0, 40.0)
	assert_true(Formation.slot_point(at, Vector3.FORWARD, Vector3.UP, o).is_equal_approx(at + o), "identity frame")
	# Nose along world +X (yawed 90 degrees right): the leader's left is world -Z, its back world -X.
	var turned: Vector3 = Formation.slot_point(at, Vector3.RIGHT, Vector3.UP, o)
	assert_true(turned.is_equal_approx(at + Vector3(-40.0, 0.0, -40.0)), "left = -Z, behind = -X, got %s" % turned)
	# Rolled onto its side (up = world -X, nose -Z): the leader's left is world -Y.
	var rolled: Vector3 = Formation.slot_point(at, Vector3.FORWARD, Vector3.LEFT, Vector3(-40.0, 0.0, 0.0))
	assert_true(rolled.is_equal_approx(at + Vector3(0.0, -40.0, 0.0)), "got %s" % rolled)


# --- BehaviourFormation --------------------------------------------------------------------------------------------


func _profile() -> AiProfile:
	var pr := AiProfile.new()
	pr.tactics = load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	pr.cruise_mps = 100.0
	return pr


func _capability() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 15.0
	cap.a_rcs = Vector2(10.0, 10.0)
	cap.rate_max_rad = Vector3(1.0, 1.0, 1.5)
	return cap


func _contact(id: int, relation: Factions.Relation, at: Vector3, velocity: Vector3 = Vector3.ZERO,
		forward: Vector3 = Vector3.FORWARD, up: Vector3 = Vector3.UP) -> Contact:
	var c := Contact.new()
	c.id = id
	c.name = "C%d" % id
	c.relation = relation
	c.faction = Factions.RAIDERS if relation == Factions.Relation.HOSTILE else Factions.EARTH_ALLIANCE
	c.position = at
	c.velocity = velocity
	c.forward = forward
	c.up = up
	c.bounding_radius = 10.0
	c.is_ship = true
	c.hull_fraction = 1.0
	return c


## A context for a member at `at` (velocity `velocity`, nose -Z) in slot 1 of a finger-four led by contact 30.
func _ctx(at: Vector3, velocity: Vector3, contacts: Array[Contact], order: AiContext.Order = AiContext.Order.COVER_ME,
		basis: Basis = Basis.IDENTITY) -> AiContext:
	var p := Perception.new()
	p.faction = Factions.EARTH_ALLIANCE
	p.capability = _capability()
	p.position = at
	p.velocity = velocity
	p.basis = basis
	p.contacts = contacts
	p.self_id = 1
	var ctx := AiContext.new()
	ctx.order = order
	ctx.leader_id = 30
	ctx.has_slot = true
	ctx.slot_offset = Formation.new().offset(1)
	ctx.refresh(p)
	return ctx


func test_formation_scores_nothing_without_a_slot_or_a_leader() -> void:
	var b := BehaviourFormation.new(_profile())
	var leader := _contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO)
	var ctx: AiContext = _ctx(Vector3(-40.0, 0.0, 40.0), Vector3.ZERO, [leader])
	assert_gt(b.score(ctx), 0.0, "a slot and the leader in sight")
	ctx.has_slot = false
	assert_eq(b.score(ctx), 0.0, "no slot: not in a wing")
	var alone: AiContext = _ctx(Vector3(-40.0, 0.0, 40.0), Vector3.ZERO, [])
	assert_eq(b.score(alone), 0.0, "the leader neither in sight nor on the wing's link")
	alone.leader_link_position = UniversePos.new(0.0, 0.0, -9000.0)
	assert_gt(b.score(alone), 0.0, "the wing's link says where the leader is")


func test_formation_beats_idle_and_stands_aside_whenever_the_orders_allow_an_attack() -> void:
	var b := BehaviourFormation.new(_profile())
	var leader := _contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO)
	var raider := _contact(20, Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -4500.0))
	var profile: AiProfile = _profile()
	var quiet: float = b.score(_ctx(Vector3.ZERO, Vector3.ZERO, [leader]))
	assert_gt(quiet, BehaviourIdle.SCORE + profile.stickiness, "takes over from idle")
	assert_eq(b.score(_ctx(Vector3.ZERO, Vector3.ZERO, [leader, raider], AiContext.Order.COVER_ME)), quiet,
			"cover me: a raider 4.5 km out may not be attacked")
	assert_eq(b.score(_ctx(Vector3.ZERO, Vector3.ZERO, [leader, raider], AiContext.Order.FORM_ON_ME)), quiet)
	var at_will: float = b.score(_ctx(Vector3.ZERO, Vector3.ZERO, [leader, raider], AiContext.Order.ENGAGE_AT_WILL))
	assert_lt(at_will + profile.stickiness, BehaviourAttack.SCORE_BASE, "any attack takes over from it")
	assert_gt(at_will, 0.0)
	var ordered: AiContext = _ctx(Vector3.ZERO, Vector3.ZERO, [leader, raider], AiContext.Order.ATTACK_MY_TARGET)
	assert_eq(b.score(ordered), quiet, "attack my target, but the leader has none")
	ordered.leader_target_id = 20
	assert_eq(b.score(ordered), at_will, "the leader's target is in sight")


func test_in_its_slot_it_matches_the_leaders_velocity_and_faces_its_nose() -> void:
	var b := BehaviourFormation.new(_profile())
	var v_l := Vector3(0.0, 0.0, -100.0)
	var leader := _contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO, v_l)
	var ctx: AiContext = _ctx(Vector3(-40.0, 0.0, 40.0), v_l, [leader])
	var cmd: PilotCommand = b.think(ctx, DT)
	assert_true(b.has_desired_velocity, "it seeks a velocity (the avoidance filter sees it)")
	assert_true(b.desired_velocity.is_equal_approx(v_l), "in the slot at the leader's velocity: %s" % b.desired_velocity)
	assert_eq(cmd.flight.rot, Vector3.ZERO, "already facing the leader's nose, level")
	assert_eq(cmd.flight.main_left + cmd.flight.retro_left, 0.0, "no thrust")
	assert_eq(b.describe()["state"], "in slot")


func test_when_the_rcs_cannot_keep_up_the_nose_leans_toward_the_acceleration() -> void:
	var b := BehaviourFormation.new(_profile())
	var v_l := Vector3(0.0, 0.0, -100.0)
	var leader := _contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO, v_l)
	# In the slot but sliding left at 20 m/s: the wish asks for 24 m/s^2 to the right, more than the 10 the RCS gives.
	var ctx: AiContext = _ctx(Formation.new().offset(1), v_l + Vector3(-20.0, 0.0, 0.0), [leader])
	var cmd: PilotCommand = b.think(ctx, DT)
	assert_gt(cmd.flight.rot.y, 0.0, "yaws right, toward the acceleration")
	assert_true(b.desired_all_axes, "and its mains work at the angle")
	assert_gt((cmd.flight.strafe as Vector2).x, 0.0)


func test_a_turning_leader_feeds_its_flight_paths_swing_forward() -> void:
	var b := BehaviourFormation.new(_profile())
	var slot: Vector3 = Formation.new().offset(1)
	var v_l := Vector3(0.0, 0.0, -100.0)
	var first: AiContext = _ctx(slot, v_l, [_contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO, v_l)])
	b.think(first, DT)
	assert_almost_eq(b.desired_velocity.x, 0.0, 1e-4, "one look at the leader: no turn known yet")
	# A tick later the leader's velocity has turned left at 10 degrees/s (17.5 m/s^2 toward -X).
	var rate: float = deg_to_rad(10.0)
	var v_turned: Vector3 = v_l.rotated(Vector3.UP, rate * DT)
	var leader := _contact(30, Factions.Relation.FRIENDLY, v_turned * DT, v_turned)
	var second: AiContext = _ctx(slot + v_l * DT, v_l, [leader])
	second.perception.now_s = DT
	b.think(second, DT)
	# The leader's 17.5 m/s^2 over the 1 s horizon, less the slot's swing to the right (w x arm: a slot behind a leader
	# turning left moves right, about 7 m/s here), plus the small error terms.
	assert_lt(b.desired_velocity.x, -5.0, "the wish leans into the turn: %s" % b.desired_velocity)
	b.enter()
	second.perception.now_s = 2.0 * DT
	b.think(second, DT)
	assert_gt(b.desired_velocity.x, -1.0, "control handed over afresh: the estimate starts again")


func test_a_slow_leaders_thrust_does_not_fling_the_far_slot() -> void:
	# A leader at 5 m/s pulling 20 m/s^2 at 30 degrees off its path: v x a / |v|^2 reads as a 2 rad/s turn, and on the
	# far slot's 113 m arm that would add some 230 m/s (and 450 m/s^2) to a wish for a slot that hardly moved.
	var b := BehaviourFormation.new(_profile())
	var slot: Vector3 = Formation.new().offset(3)
	var v_l := Vector3(0.0, 0.0, -5.0)
	var first: AiContext = _ctx(slot, v_l, [_contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO, v_l)])
	first.slot_offset = slot
	b.think(first, DT)
	var accel := Vector3(0.5, 0.0, -0.866) * 20.0
	var v_next: Vector3 = v_l + accel * DT
	var second: AiContext = _ctx(slot + v_l * DT, v_l, [_contact(30, Factions.Relation.FRIENDLY, v_next * DT, v_next)])
	second.slot_offset = slot
	second.perception.now_s = DT
	b.think(second, DT)
	# The leader's own 20 m/s^2 over the 1 s horizon, plus a few m/s of swing at most.
	assert_lt((b.desired_velocity - v_l).length(), 30.0, "the wish stays near the leader's: %s" % b.desired_velocity)


func test_the_error_closes_at_k_with_a_lead_on_both_ships() -> void:
	var b := BehaviourFormation.new(_profile())
	var v_l := Vector3(0.0, 0.0, -100.0)
	var leader := _contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO, v_l)
	# 50 m behind the slot, 10 m/s slower than the leader.
	var ctx: AiContext = _ctx(Vector3(-40.0, 0.0, 90.0), v_l + Vector3(0.0, 0.0, 10.0), [leader])
	b.think(ctx, DT)
	var error: Vector3 = Vector3(0.0, 0.0, -50.0) + Vector3(0.0, 0.0, -10.0) * BehaviourFormation.LEAD_S
	assert_true(b.desired_velocity.is_equal_approx(v_l + error * BehaviourFormation.K_PER_S),
			"v_des = v_L + k (slot error + lead x velocity error): %s" % b.desired_velocity)


func test_closure_is_capped_near_and_faster_beyond_a_kilometre_and_a_half() -> void:
	var b := BehaviourFormation.new(_profile())
	var leader := _contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO)
	var slot: Vector3 = Formation.new().offset(1)
	var near: AiContext = _ctx(slot + Vector3(0.0, 0.0, 600.0), Vector3.ZERO, [leader])
	b.think(near, DT)
	assert_almost_eq(b.desired_velocity.length(), BehaviourFormation.NEAR_CLOSURE_MPS, 1e-3, "600 m out: 60 m/s")
	assert_gt(b.desired_velocity.normalized().dot(Vector3.FORWARD), 0.999, "toward the slot")
	var far: AiContext = _ctx(slot + Vector3(0.0, 0.0, 2000.0), Vector3.ZERO, [leader])
	b.think(far, DT)
	assert_almost_eq(b.desired_velocity.length(), _profile().cruise_mps + BehaviourFormation.FAR_EXTRA_MPS, 1e-3,
			"2 km out: cruise + 100 m/s")
	assert_eq(b.describe()["state"], "joining")


func test_inside_150_m_it_faces_the_leaders_nose_and_rolls_to_its_up() -> void:
	var b := BehaviourFormation.new(_profile())
	var lean: Vector3 = Vector3(sin(deg_to_rad(20.0)), cos(deg_to_rad(20.0)), 0.0)  # rolled 20 degrees right
	var yawed: Vector3 = Vector3(sin(deg_to_rad(10.0)), 0.0, -cos(deg_to_rad(10.0)))  # nose 10 degrees right
	var leader := _contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO, Vector3.ZERO, yawed, lean.rotated(Vector3.UP,
			deg_to_rad(-10.0)))
	var ctx: AiContext = _ctx(Formation.slot_point(Vector3.ZERO, yawed, Vector3.UP, Formation.new().offset(1)),
			Vector3.ZERO, [leader])
	var cmd: PilotCommand = b.think(ctx, DT)
	assert_gt(cmd.flight.rot.y, 0.0, "yaws right onto the leader's nose")
	assert_gt(cmd.flight.rot.z, 0.0, "rolls right toward the leader's up")


func test_beyond_150_m_it_faces_the_way_it_needs_to_go_and_does_not_roll() -> void:
	var b := BehaviourFormation.new(_profile())
	var leader := _contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD,
			Vector3(1.0, 1.0, 0.0).normalized())
	# 400 m to the right of the slot, at rest: it has to go left.
	var ctx: AiContext = _ctx(Formation.new().offset(1) + Vector3(400.0, 0.0, 0.0), Vector3.ZERO, [leader])
	var cmd: PilotCommand = b.think(ctx, DT)
	assert_lt(cmd.flight.rot.y, 0.0, "yaws left toward the slot")
	assert_eq(cmd.flight.rot.z, 0.0, "no roll until it is close")
	# Overshot: 400 m ahead of the slot at the leader's speed, it slows with the retros rather than flipping round.
	var v_l := Vector3(0.0, 0.0, -100.0)
	var moving := _contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO, v_l)
	var ahead: AiContext = _ctx(Formation.new().offset(1) + Vector3(0.0, 0.0, -400.0), v_l, [moving])
	var braking: PilotCommand = b.think(ahead, DT)
	assert_almost_eq(braking.flight.rot.length(), 0.0, 1e-6, "keeps its nose along its travel")
	assert_gt(braking.flight.retro_left, 0.0, "and brakes")


func test_out_of_sight_it_flies_to_the_leaders_position_on_the_link() -> void:
	var b := BehaviourFormation.new(_profile())
	var ctx: AiContext = _ctx(Vector3.ZERO, Vector3.ZERO, [])
	ctx.leader_link_position = UniversePos.new(0.0, 0.0, -9000.0)
	ctx.leader_link_velocity = Vector3(0.0, 0.0, -100.0)
	b.think(ctx, DT)
	var v: Vector3 = b.desired_velocity
	assert_gt(v.normalized().dot(Vector3.FORWARD), 0.999, "toward the leader 9 km ahead: %s" % v)
	assert_almost_eq(v.length(), 100.0 + _profile().cruise_mps + BehaviourFormation.FAR_EXTRA_MPS, 1e-3,
			"its velocity plus the far closure")


func test_the_pilot_forwards_the_formation_wish_to_the_driver() -> void:
	var pilot := AiPilot.new(_profile(), 1)
	pilot.add_behaviour(BehaviourFormation.new(pilot.profile))
	pilot.context.leader_id = 30
	pilot.context.has_slot = true
	pilot.context.slot_offset = Formation.new().offset(1)
	pilot.context.order = AiContext.Order.FORM_ON_ME
	var v_l := Vector3(0.0, 0.0, -100.0)
	var p := Perception.new()
	p.faction = Factions.EARTH_ALLIANCE
	p.capability = _capability()
	p.position = Vector3(-40.0, 0.0, 300.0)
	p.velocity = v_l
	p.contacts = [_contact(30, Factions.Relation.FRIENDLY, Vector3.ZERO, v_l)] as Array[Contact]
	pilot.think(p, DT)
	assert_eq(pilot.current.id, &"formation")
	assert_true(pilot.has_desired_velocity)
	assert_gt((pilot.desired_velocity - v_l).dot(Vector3.FORWARD), 0.0, "closing on the slot ahead")
	assert_eq(pilot.wanted_target_id, PilotBrain.TARGET_NONE, "shows no target")
