extends GutTest
## The evasion's leash (M8-T06; maintainer, 2026-11-18), on the GDScript reference `BehaviourEvade` with scripted contexts: a
## wingman evading farther than `AiContext.leash_m` from its lead breaks toward the lead instead of on away, is let off only
## well inside, follows the wing's link when the lead is out of sight, and without a leash evades as it always did. The
## native brain's twin is in `brain_behaviours/tests.rs` and `test_brain_think_parity`.

const DT: float = 1.0 / 60.0
const LEADER_ID: int = 2
const OWN_VELOCITY := Vector3(0.0, 0.0, -100.0)


func _contact(id: int, relation: Factions.Relation, at: Vector3, velocity: Vector3) -> Contact:
	var c := Contact.new()
	c.id = id
	c.name = "C%d" % id
	c.relation = relation
	c.faction = Factions.RAIDERS if relation == Factions.Relation.HOSTILE else Factions.EARTH_ALLIANCE
	c.position = at
	c.velocity = velocity
	c.forward = Vector3.FORWARD
	c.is_ship = true
	c.bounding_radius = 8.0
	return c


# The pilot at the origin flying -z, its lead `lead_off` away (null: out of sight), a hostile 600 m astern with its nose on it.
func _ctx(lead_off: Variant, leash_m: float, now_s: float) -> AiContext:
	var p := Perception.new()
	p.faction = Factions.EARTH_ALLIANCE
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 15.0
	cap.a_rcs = Vector2(10.0, 10.0)
	p.capability = cap
	p.velocity = OWN_VELOCITY
	p.now_s = now_s
	p.self_id = 1
	var contacts: Array[Contact] = [_contact(9, Factions.Relation.HOSTILE, Vector3(0.0, 0.0, 600.0), OWN_VELOCITY)]
	if lead_off != null:
		contacts.append(_contact(LEADER_ID, Factions.Relation.FRIENDLY, lead_off as Vector3, Vector3(0.0, 0.0, -80.0)))
	p.contacts = contacts
	var ctx := AiContext.new()
	ctx.leader_id = LEADER_ID
	ctx.leash_m = leash_m
	ctx.refresh(p)
	return ctx


# A second of evading in the situation `_ctx` describes; returns the last think's wish.
func _evade(evade: BehaviourEvade, lead_off: Variant, leash_m: float, from_s: float = 0.0, link: UniversePos = null) -> Vector3:
	for k: int in 60:
		var ctx: AiContext = _ctx(lead_off, leash_m, from_s + float(k) * DT)
		if link != null:
			ctx.leader_link_position = link
			ctx.leader_link_velocity = Vector3(0.0, 0.0, -80.0)
		assert_gt(evade.score(ctx), 0.0, "a hostile on its tail")
		evade.think(ctx, DT)
	return evade.desired_velocity


func test_past_the_leash_the_evasion_breaks_toward_the_lead() -> void:
	var evade := BehaviourEvade.new(11)
	var wish: Vector3 = _evade(evade, Vector3(-3000.0, 0.0, 0.0), 2500.0)
	assert_true(evade.leashed, "3 km from its lead on a 2.5 km leash")
	# The lead's own motion (-z 80), 150 m/s toward it (-x) and a 100 m/s jink across the line of fire (in x and y).
	assert_lt(wish.x, -45.0, "toward its lead")
	assert_almost_eq(wish.z, -80.0, 0.5, "riding on the lead's motion, not its own way off")


func test_without_a_leash_or_inside_it_the_evasion_is_as_it_was() -> void:
	var free := BehaviourEvade.new(11)
	var wish: Vector3 = _evade(free, Vector3(-3000.0, 0.0, 0.0), 0.0)
	assert_false(free.leashed)
	assert_almost_eq(wish.z, OWN_VELOCITY.z, 0.5, "the course it had when the evasion began")
	assert_lte(absf(wish.x), 100.5, "only the jink across it")
	var inside := BehaviourEvade.new(11)
	wish = _evade(inside, Vector3(-2000.0, 0.0, 0.0), 2500.0)
	assert_false(inside.leashed, "2 km out on a 2.5 km leash")
	assert_almost_eq(wish.z, OWN_VELOCITY.z, 0.5)
	# The same seed jinks the same way with and without the leash: the leash changes the course under it, nothing else.
	assert_eq(inside.side, free.side)
	assert_eq(inside.jinks, free.jinks)


func test_the_leash_lets_go_only_well_inside() -> void:
	var evade := BehaviourEvade.new(11)
	_evade(evade, Vector3(-3000.0, 0.0, 0.0), 2500.0)
	assert_true(evade.leashed)
	_evade(evade, Vector3(-2000.0, 0.0, 0.0), 2500.0, 1.0)
	assert_true(evade.leashed, "not let off at the leash's edge: it would be dragged straight out again")
	var wish: Vector3 = _evade(evade, Vector3(-1000.0, 0.0, 0.0), 2500.0, 2.0)
	assert_false(evade.leashed, "under half the leash: let off")
	assert_almost_eq(wish.z, -80.0, 0.5, "it stays with its lead's motion")
	assert_lte(absf(wish.x), 100.5, "only the jink again")


func test_a_lead_out_of_sight_is_followed_on_the_wings_link() -> void:
	var evade := BehaviourEvade.new(11)
	var wish: Vector3 = _evade(evade, null, 2500.0, 0.0, UniversePos.new(-7000.0, 0.0, 0.0))
	assert_true(evade.leashed, "7 km from where the link puts its lead")
	assert_lt(wish.x, -45.0, "toward the link")
	var lost := BehaviourEvade.new(11)
	_evade(lost, null, 2500.0)
	assert_false(lost.leashed, "no lead and no link: nothing to come back to")


func test_a_new_evasion_starts_off_the_leash() -> void:
	var evade := BehaviourEvade.new(11)
	_evade(evade, Vector3(-3000.0, 0.0, 0.0), 2500.0)
	evade.enter()
	assert_false(evade.leashed)
	evade.reset()
	assert_false(evade.leashed)
