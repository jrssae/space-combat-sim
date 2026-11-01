extends GutTest
## BehaviourRam (M3-T13, Q12, AC20) on scripted contexts: only a reckless pilot under 25 % hull with at most a quarter of the
## friends it saw left may ram; a seeded roll every 5 s commits it; it takes its attack target or the nearest hostile ship
## (never a prop), outranks everything, leaves that contact out of the avoidance, ignores hits, and lets go once the target is
## gone.

const DT: float = 1.0 / 60.0


func _contact(id: int, relation: Factions.Relation, at: Vector3, is_ship: bool = true) -> Contact:
	var c := Contact.new()
	c.id = id
	c.name = "C%d" % id
	c.relation = relation
	c.faction = Factions.RAIDERS if relation == Factions.Relation.HOSTILE else Factions.EARTH_ALLIANCE
	c.position = at
	c.forward = Vector3.BACK
	c.is_ship = is_ship
	c.bounding_radius = 8.0
	return c


func _p(contacts: Array[Contact], hull: float, now_s: float = 0.0) -> Perception:
	var p := Perception.new()
	p.faction = Factions.EARTH_ALLIANCE
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 15.0
	cap.a_rcs = Vector2(10.0, 10.0)
	p.capability = cap
	p.hull_fraction = hull
	p.contacts = contacts
	p.now_s = now_s
	p.self_id = 1
	return p


func _ram(aggression: float, seed_value: int = 7) -> BehaviourRam:
	var ram := BehaviourRam.new(seed_value)
	ram.retune(AiProfile.new(), AiTemperament.new(0.45, aggression))
	return ram


func _ctx(p: Perception) -> AiContext:
	var ctx := AiContext.new()
	ctx.refresh(p)
	return ctx


## Seconds of scoring until it commits (INF within `limit_s`).
func _time_to_commit(ram: BehaviourRam, contacts: Array[Contact], hull: float, limit_s: float = 120.0) -> float:
	var t: float = 0.0
	while t < limit_s:
		if ram.score(_ctx(_p(contacts, hull, t))) > 0.0:
			return t
		t += DT
	return INF


func test_below_reckless_it_never_rams() -> void:
	var enemy := _contact(20, Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -500.0))
	for a: float in [0.0, 0.5, 0.75, 0.99]:
		assert_eq(_time_to_commit(_ram(a), [enemy] as Array[Contact], 0.05, 60.0), INF, "aggression %.2f" % a)


func test_a_reckless_ship_alone_and_badly_hurt_commits_on_a_seeded_roll() -> void:
	var enemy := _contact(20, Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -500.0))
	var ram := _ram(1.0)
	var t: float = _time_to_commit(ram, [enemy] as Array[Contact], 0.2)
	assert_lt(t, INF, "it committed")
	assert_true(ram.committed)
	assert_eq(ram.target_id(), 20)
	var phase: float = fmod(t + 2.0 * DT, BehaviourRam.ROLL_EVERY_S)
	assert_lt(phase, 4.0 * DT, "on a roll, every 5 s from the moment it was eligible (a tick of rounding either way)")
	var again := _ram(1.0)
	assert_eq(_time_to_commit(again, [enemy] as Array[Contact], 0.2), t, "the same seed rolls the same")
	var hits: int = 0
	for s: int in 200:
		var r := _ram(1.0, s)
		r.score(_ctx(_p([enemy] as Array[Contact], 0.2, 0.0)))
		hits += 1 if r.committed else 0
	assert_between(hits, 50, 90, "about 35 %% of first rolls commit (%d of 200)" % hits)


func test_it_needs_a_low_hull_and_few_friends_left() -> void:
	var enemy := _contact(20, Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -500.0))
	var friends: Array[Contact] = [enemy]
	for i: int in 4:
		friends.append(_contact(30 + i, Factions.Relation.FRIENDLY, Vector3(100.0 * i, 0.0, 0.0)))
	assert_eq(_time_to_commit(_ram(1.0), [enemy] as Array[Contact], 0.3, 60.0), INF, "hull 30 %: no")
	var ram := _ram(1.0)
	ram.score(_ctx(_p(friends, 0.2)))  # it has seen four friends
	assert_eq(ram.max_friends_seen, 4)
	var two_left: Array[Contact] = [enemy, friends[1], friends[2]]
	assert_eq(_time_to_commit(ram, two_left, 0.2, 60.0), INF, "two of four left: more than a quarter")
	var one_left: Array[Contact] = [enemy, friends[1]]
	assert_lt(_time_to_commit(ram, one_left, 0.2), INF, "one of four left: eligible")


func test_it_takes_the_attack_target_else_the_nearest_ship_never_a_prop() -> void:
	var near := _contact(20, Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -300.0))
	var far := _contact(21, Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -900.0))
	var buoy := _contact(22, Factions.Relation.HOSTILE, Vector3(0.0, 0.0, -50.0), false)
	var ctx := _ctx(_p([buoy, far, near] as Array[Contact], 0.2))
	var ram := _ram(1.0)
	assert_true(ram.commit(ctx))
	assert_eq(ram.target_id(), 20, "the nearest hostile ship, not the nearer prop")
	ctx.current_target_id = 21
	var second := _ram(1.0)
	assert_true(second.commit(ctx))
	assert_eq(second.target_id(), 21, "the one it was attacking")


func test_a_committed_rammer_flies_at_its_target_ignores_hits_and_lets_go_when_it_is_gone() -> void:
	var enemy := _contact(20, Factions.Relation.HOSTILE, Vector3(400.0, 0.0, -1000.0))
	var profile := AiProfile.load_named(&"raider")
	var pilot := AiPilot.new(profile, 11, [] as Array[AiBehaviour], AiTemperament.new(0.45, 1.0))
	var p := _p([enemy] as Array[Contact], 0.2)
	pilot.think(p, DT)
	var ram := pilot.behaviour(&"ram") as BehaviourRam
	assert_true(ram.commit(pilot.context))
	for i: int in 90:  # past the attack's dwell
		p.now_s += DT
		pilot.think(p, DT)
	assert_eq(pilot.current.id, &"ram")
	assert_eq(pilot.avoid_exempt_id, 20, "the driver leaves the target out of the avoidance")
	assert_eq(pilot.wanted_target_id, 20)
	var aim: Vector3 = (pilot.desired_velocity - enemy.velocity).normalized()
	assert_almost_eq(aim.dot((enemy.position - p.position).normalized()), 1.0, 1e-6, "straight at it")
	p.last_bolt_hit_s = p.now_s
	for i: int in 30:
		p.now_s += DT
		pilot.think(p, DT)
	assert_eq(pilot.current.id, &"ram", "a hit does not break the commitment")
	p.contacts = [] as Array[Contact]  # destroyed
	p.now_s += DT
	pilot.think(p, DT)
	assert_false(ram.committed)
	assert_ne(pilot.current.id, &"ram")
	assert_eq(pilot.avoid_exempt_id, 0)
