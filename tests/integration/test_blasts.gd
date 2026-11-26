extends TestSteps
## The blast model in play (M10-T09, D12.6, AC8's blast clause), in the real main scene: a death hurts and pushes what is near
## by the falloff to each hull's nearest hit volume and nothing past its radius; a death it causes blows in turn in the same
## tick; a capital's magazine blows from its section's centre with its class's row; a blast near a capital lands on its
## nearest section; a tier row is pushed through the core; a missile's warhead blasts where it strikes; the console sets off
## a test blast and the provider counts it. The 1-vs-6-thread identity is `test_blast_threads`.

const OMEGA: StringName = &"ea_omega"

var main: Main


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # its capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true  # the player sits near the test blasts
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.ally_pool_size = 8  # the sandbox's own allies take three
	add_child_autofree(main)
	await _ticks(2)
	BlastResolver.reset_stats()


func after_each() -> void:
	DebugConsole.flags.invulnerable = false


func _spawn(kind: String, distance_m: float) -> Combatant:
	var type: StringName = ShipPool.DEFAULT_TYPE if kind == "raider" else ShipPool.ALLY_TYPE
	var before: Array[Combatant] = main.ships.alive(type).duplicate()
	assert_true(DebugConsole.registry.execute("spawn %s idle %s" % [kind, distance_m])[0].ok)
	for c: Combatant in main.ships.alive(type):
		if not before.has(c):
			return c
	return null


# Puts `c` at `at` (World frame) at the frame's rest, turned as the player is.
func _place(c: Combatant, at: Vector3) -> void:
	c.ship.global_transform = Transform3D(main.ship.global_basis, at)
	c.ship.linear_velocity = main.world.rest_velocity()
	c.ship.angular_velocity = Vector3.ZERO


# How far World point `at` is from `c`'s nearest hit volume, measured here from its shapes.
static func _gap(c: Combatant, at: Vector3) -> float:
	var local: Vector3 = c.ship.global_transform.affine_inverse() * at
	var best: float = INF
	for shape: HitShape in c.damageable.shapes:
		best = minf(best, shape.nearest_point(local).distance_to(local))
	return best


# The blast hits `damageable` takes from now on (the native batch's summaries, M10-T76).
static func _blast_hits(damageable: Damageable) -> Array[HitInfo]:
	return BlastHits.of(damageable)


func _sync() -> void:
	SimCore.for_tree(get_tree()).sync_now()


func test_a_death_hurts_and_pushes_what_is_near_by_the_falloff_and_nothing_past_its_radius() -> void:
	var dying: Combatant = _spawn("raider", 600.0)
	var near: Combatant = _spawn("ally", 700.0)
	var far: Combatant = _spawn("ally", 800.0)
	var centre: Vector3 = main.ship.global_position - main.ship.global_basis.z * 600.0
	var side: Vector3 = main.ship.global_basis.x
	_place(dying, centre)
	_place(near, centre + side * 50.0)
	_place(far, centre - side * 150.0)
	await _ticks(1)
	_place(dying, centre)
	_place(near, centre + side * 50.0)
	_place(far, centre - side * 150.0)
	_sync()
	var near_hits: Array[HitInfo] = _blast_hits(near.damageable)
	var far_hits: Array[HitInfo] = _blast_hits(far.damageable)
	var hp: float = near.damageable.hull.hp
	var v0: Vector3 = near.ship.linear_velocity
	var deaths: Array[HitInfo] = []
	main.director.ship_destroyed.connect(func(_c: Combatant, info: HitInfo) -> void: deaths.append(info))
	assert_true(dying.damageable.kill())
	var spec: BlastSpec = BlastTable.hull_death("raider_fighter")
	assert_eq(spec.source, &"raider_death")
	assert_eq(deaths.size(), 1)
	assert_true(deaths[0].blast_point.is_equal_approx(centre), "the raider's blast is at its centre")
	assert_eq(deaths[0].blast_radius_m, spec.radius_m, "and its radius is on the event")
	assert_eq(near_hits.size(), 1, "the wingman 50 m away is hurt once")
	var gap: float = _gap(near, centre)
	assert_between(gap, 30.0, 50.0, "(measured to its hit volumes, not its centre)")
	assert_almost_eq(near_hits[0].damage, spec.damage_at(gap), 0.05, "by the falloff to its nearest hit volume")
	assert_almost_eq(hp - near.damageable.hull.hp, near_hits[0].damage, 1e-3)
	assert_eq(near_hits[0].shooter_id, 0, "no shooter: no kill credit, no one to answer")
	var kick: Vector3 = near.ship.linear_velocity - v0
	var area: float = BlastSpec.mean_face_area(near.damageable.ram_bounds.size)
	assert_almost_eq(kick.length(), spec.push_at(gap, area, near.ship.mass), 1e-3, "pushed by the falloff")
	assert_gt(kick.normalized().dot(side), 0.99, "away from the blast")
	assert_eq(far_hits.size(), 0, "150 m away is past its 80 m")
	assert_eq(BlastResolver.blasts, 1)
	assert_eq(BlastResolver.last_reached, 1, "the dead raider itself is not reached")


func test_a_death_the_blast_causes_blows_in_turn_in_the_same_tick() -> void:
	var first: Combatant = _spawn("raider", 600.0)
	var second: Combatant = _spawn("raider", 650.0)
	var third: Combatant = _spawn("ally", 700.0)
	var centre: Vector3 = main.ship.global_position - main.ship.global_basis.z * 600.0
	var side: Vector3 = main.ship.global_basis.x
	await _ticks(1)
	_place(first, centre)
	_place(second, centre + side * 60.0)
	_place(third, centre + side * 115.0)
	_sync()
	second.damageable.hull.hp = 1.0
	var third_hits: Array[HitInfo] = _blast_hits(third.damageable)
	var deaths: Array[Combatant] = []
	main.director.ship_destroyed.connect(func(c: Combatant, _info: HitInfo) -> void: deaths.append(c))
	assert_true(first.damageable.kill())
	assert_eq(deaths, [first, second] as Array[Combatant], "the second raider died of the first's blast, after it")
	assert_eq(BlastResolver.blasts, 2, "and blew in turn")
	assert_eq(third_hits.size(), 1, "its blast reached the ally the first one could not")


func test_a_capitals_magazine_blows_from_its_section_with_its_classs_row() -> void:
	var cap: CapitalShip = _omega(3000.0)
	if cap == null:
		return
	var section: CapitalSection = cap.damage.sections["magazine"]
	var centre: Vector3 = cap.global_transform * section.box.get_center()
	var raider: Combatant = _spawn("raider", 900.0)
	await _ticks(1)
	_place(raider, centre + cap.global_basis.y * (section.box.size.y * 0.5 + 250.0))
	_sync()
	var hits: Array[HitInfo] = _blast_hits(raider.damageable)
	var events: Array[HitInfo] = []
	main.director.capital_destroyed.connect(func(_c: CapitalBody, info: HitInfo) -> void: events.append(info))
	assert_true(DebugConsole.registry.execute("capital damage magazine 100000")[0].ok)
	assert_eq(cap.damage.blown, "magazine")
	assert_eq(events.size(), 1, "the director took the death")
	var spec: BlastSpec = BlastTable.spec(&"capital_magazine")
	assert_eq(events[0].blast_radius_m, spec.radius_m, "an Omega's magazine (capital class)")
	assert_almost_eq(events[0].blast_energy_j, spec.energy_j(), 1.0)
	assert_true(events[0].blast_point.is_equal_approx(centre), "from the magazine's centre")
	assert_eq(hits.size(), 1, "the raider above it was caught")
	assert_almost_eq(hits[0].damage, spec.damage_at(_gap_from(raider, centre)), 0.5)
	assert_true(raider.damageable.hull.destroyed, "and killed")


func test_a_blast_near_a_capital_lands_on_its_nearest_section() -> void:
	var cap: CapitalShip = _omega(3000.0)
	if cap == null:
		return
	await _ticks(2)
	var half: Vector3 = cap.half_extents()
	var at: Vector3 = cap.global_transform * Vector3(0.0, 0.0, -(half.z + 20.0))
	var local: Vector3 = cap.global_transform.affine_inverse() * at
	var expected: String = cap.sections.section_at(CapitalSections.HULL, local)
	var gap: float = INF
	for entry: Dictionary in cap.sections.on(CapitalSections.HULL):
		for v: HitShape in entry["hit_volumes"]:
			gap = minf(gap, CapitalSections.distance(v, local))
	var landed: Array[HitSummary] = []
	cap.damageable.hits_landed.connect(func(s: HitSummary) -> void: landed.append(s))
	var spec: BlastSpec = BlastSpec.make(&"test", 500.0, gap + 100.0, 1.0e4)
	var points_before: float = cap.damage.sections[expected].hp
	_sync()
	BlastResolver.set_off(spec, at)
	assert_eq(landed.size(), 1, "the ship hears of the blast once")
	if landed.is_empty():
		return
	assert_eq(landed[0].cause, HitInfo.CAUSE_BLAST)
	assert_eq(landed[0].hits, 1, "one hit for the whole ship, rotors and all")
	assert_eq(cap.damage.section_name(landed[0].sections[0]), expected, "on the section nearest the blast")
	assert_almost_eq(landed[0].damage, spec.damage_at(gap), 0.05, "by the falloff to its nearest volume")
	assert_lt(cap.damage.sections[expected].hp, points_before, "its points went down")


func test_a_hull_flying_in_the_tier_is_hurt_and_pushed_on_its_row() -> void:
	var raider: Combatant = _spawn("ally", 15000.0)
	await _ticks(70)
	assert_true(raider.ship.is_tier_parked(), "(15 km: a tier row)")
	var pose: Array = TierDirector.row_pose(raider.ship)
	var at: Vector3 = (pose[0] as Transform3D).origin + Vector3(40.0, 0.0, 0.0)
	var v0: Vector3 = pose[1]
	var hp: float = raider.damageable.hull.hp
	var spec: BlastSpec = BlastTable.spec(&"fighter_death")
	_sync()
	BlastResolver.set_off(spec, at)
	assert_lt(raider.damageable.hull.hp, hp, "hurt where its row flies")
	var kick: Vector3 = (TierDirector.row_pose(raider.ship)[1] as Vector3) - v0
	assert_gt(kick.length(), 0.01, "its row was pushed")
	assert_gt(kick.normalized().dot(Vector3.LEFT), 0.99, "away from the blast (-x)")
	assert_eq(BlastResolver.pushed, 1)


func test_a_missiles_warhead_blasts_where_it_strikes() -> void:
	var target: Combatant = _spawn("ally", 500.0)
	var beside: Combatant = _spawn("ally", 520.0)
	var centre: Vector3 = main.ship.global_position - main.ship.global_basis.z * 500.0
	await _ticks(1)
	_place(target, centre)
	_place(beside, centre + main.ship.global_basis.x * 14.0)
	_sync()
	var target_hits: Array[HitInfo] = BlastHits.of(target.damageable, true)
	var beside_hits: Array[HitInfo] = _blast_hits(beside.damageable)
	var from: Vector3 = centre + main.ship.global_basis.z * 120.0
	MissileStandin.launch(main.projectiles, from, target.ship, main.ship.get_instance_id(), Factions.RAIDERS, SimClock.now())
	for i: int in 60:
		await _ticks(1)
		if not target_hits.is_empty():
			break
	assert_eq(target_hits.size(), 2, "the impact and the warhead's blast: %s" % [target_hits])
	if target_hits.size() < 2:
		return
	assert_eq(target_hits[0].cause, HitInfo.CAUSE_BOLT)
	assert_eq(target_hits[0].damage, MissileStandin.DAMAGE)
	assert_eq(target_hits[1].cause, HitInfo.CAUSE_BLAST)
	var warhead: BlastSpec = BlastTable.spec(&"missile")
	var reach: float = Projectile.hit_radius_for(Projectile.KIND_MISSILE)
	assert_between(target_hits[1].damage, warhead.damage_at(reach + 0.01), warhead.d0,
			"the warhead where it struck: within the missile's hit radius of the hull")
	assert_eq(target_hits[1].shooter_id, main.ship.get_instance_id(), "the missile's shooter fired it")
	assert_lte(beside_hits.size(), 1, "the hull beside it inside the 20 m, or just outside")


func test_the_console_sets_off_a_test_blast_and_the_provider_counts_it() -> void:
	var ally: Combatant = _spawn("ally", 400.0)
	await _ticks(1)
	_place(ally, main.ship.global_position - main.ship.global_basis.z * 90.0)
	_sync()
	var hp: float = ally.damageable.hull.hp
	var result: ConsoleResult = DebugConsole.registry.execute("blast fighter_death 60")[0]
	assert_true(result.ok, result.error)
	assert_string_contains("\n".join(result.lines), "fighter_death 60 m ahead")
	assert_lt(ally.damageable.hull.hp, hp, "the ally 30 m beyond it is hurt")
	assert_eq(DebugConsole.registry.read("blasts.blasts").get("value"), 1)
	assert_gte(int(DebugConsole.registry.read("blasts.hulls_hurt").get("value")), 1)
	assert_false(DebugConsole.registry.execute("blast nothing")[0].ok, "an unknown row is refused")


# --- helpers ------------------------------------------------------------------------------------------------------


func _omega(range_m: float) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(OMEGA, Factions.EARTH_ALLIANCE, "EAS Agamemnon", rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - main.ship.global_basis.z * range_m), main.ship.global_basis)
	cap.set_course(Vector3.ZERO, rest)
	return cap


static func _gap_from(c: Combatant, at: Vector3) -> float:
	return _gap(c, at)
