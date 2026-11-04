extends GutTest
## The battle's stand-ins (M4-T07, Q19 and Q22): capitals with turrets and interceptors, the asteroid field and the gravity
## source. They put the load of features the game does not have yet on the tick: a turret aims and fires only inside its gate
## at hostiles within 4 km, an interceptor removes only hostile bolts within 1.5 km, rocks are static rows in the contact scan
## that bolts hit, a rebase moves them all, and the moon bends a coasting path.
##
## Turrets and interceptors are stepped by hand with a scan built for the step, as `StandinDirector` does once per tick.

const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"
const DT: float = 1.0 / 60.0

var world: WorldFrame
var projectiles: Node3D
var standins: StandinDirector
var now_s: float = 0.0


func before_each() -> void:
	ContactScan.invalidate()
	StaticRows.clear()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	standins = StandinDirector.new()
	standins.name = "Standins"
	standins.world = world
	standins.projectiles = projectiles
	world.add_child(standins)
	standins.set_physics_process(false)  # stepped by hand
	now_s = SimClock.now() + 100.0  # ahead of the clock projectiles expire by, however long the suite has run


func after_each() -> void:
	StaticRows.clear()
	ContactScan.invalidate()
	Factions.reset()


func _drone(at: Vector3, faction: StringName = Factions.RAIDERS) -> TargetDrone:
	var drone := (load(DRONE_SCENE) as PackedScene).instantiate() as TargetDrone
	drone.faction = faction
	drone.set_physics_process(false)
	world.spawn(drone, world.to_universe(at))
	return drone


func _capital(at: Vector3, faction: StringName = Factions.EARTH_ALLIANCE, cls: StringName = &"cruiser") -> CapitalStandin:
	return standins.add_capital(cls, faction, "TEST %s" % cls, world.to_universe(at), Basis.IDENTITY, Vector3.ZERO)


func _bolts(faction: StringName = &"") -> Array[Projectile]:
	var out: Array[Projectile] = []
	for node: Node in projectiles.get_children():
		var bolt := node as Projectile
		if bolt != null and not bolt.is_spent() and (faction == &"" or bolt.faction == faction):
			out.append(bolt)
	return out


# One stand-in tick at `now_s` with a fresh scan; returns how many bolts the turrets fired.
func _step() -> int:
	var before: int = _bolts().size()
	standins.step(DT, now_s, ContactScan.from_tree(get_tree()))
	now_s += DT
	return _bolts().size() - before


func _hostile_bolt(at: Vector3, faction: StringName = Factions.RAIDERS) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	bolt.configure(WeaponSpec.new())
	bolt.faction = faction
	bolt.launch(at, Vector3(0.0, 0.0, 500.0), now_s)
	bolt.set_physics_process(false)
	return bolt


func test_a_capital_carries_its_class_turrets_hull_and_kind() -> void:
	var carrier: CapitalStandin = _capital(Vector3.ZERO, Factions.EARTH_ALLIANCE, &"carrier")
	var spec: Dictionary = CapitalStandin.CLASSES[&"carrier"]
	assert_eq(carrier.guns().size(), int(spec["turrets"]), "12 gun turrets on a carrier")
	assert_eq(carrier.interceptors().size(), CapitalStandin.INTERCEPTORS_PER_CAPITAL)
	assert_eq(carrier.targetable.kind, Targetable.Kind.CAPITAL)
	assert_eq(carrier.targetable.faction, Factions.EARTH_ALLIANCE)
	assert_almost_eq(carrier.length_m(), 1200.0, 1e-3)
	assert_gt(carrier.damageable.bounding_radius, 600.0, "the hull's sphere holds the whole box")
	assert_eq(carrier.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "Newtonian: no damping")
	assert_eq(carrier.linear_damp, 0.0)
	assert_eq(carrier.angular_damp, 0.0)
	var scan := ContactScan.from_tree(get_tree())
	var seen: Array[Contact] = scan.contacts_for(-1, Vector3(0.0, 0.0, 3000.0), Factions.RAIDERS)
	assert_eq(seen.size(), 1, "the capital is one contact")
	assert_true(seen[0].is_ship, "a capital is a body that flies")
	assert_eq(seen[0].relation, Factions.Relation.HOSTILE)


func test_a_turret_fires_only_at_hostiles_within_four_km() -> void:
	var cap: CapitalStandin = _capital(Vector3.ZERO)
	_drone(Vector3(0.0, 2000.0, -4500.0))  # a hostile out of reach of every turret
	_drone(Vector3(0.0, 2000.0, 2500.0), Factions.EARTH_ALLIANCE)  # a friend within reach
	_drone(Vector3(2500.0, 0.0, 0.0), Factions.NEUTRAL)  # a neutral within reach
	var fired: int = 0
	for i: int in 240:
		fired += _step()
	assert_eq(fired, 0, "nothing hostile within 4 km: no shot")
	for gun: TurretStandin in cap.guns():
		assert_eq(gun.target_id, 0, "no target taken")
	_drone(Vector3(0.0, 1500.0, -2500.0))  # a hostile within reach of every turret
	for i: int in 240:
		fired += _step()
	assert_gt(fired, 0, "a hostile within 4 km draws fire")
	for bolt: Projectile in _bolts():
		assert_eq(bolt.faction, Factions.EARTH_ALLIANCE, "the capital's bolts")
		assert_eq(bolt.shooter_id, cap.get_instance_id(), "never hit their own hull")


func test_a_turret_fires_only_inside_its_gate() -> void:
	_capital(Vector3.ZERO)
	var target: TargetDrone = _drone(Vector3(3000.0, 300.0, 0.0))  # abeam: every gun must turn first
	var shots: int = 0
	var outside: int = 0
	var cap := standins.capitals()[0] as CapitalStandin
	var fastest_turn: float = 0.0
	for i: int in 600:
		var axes: Dictionary = {}
		var shots_before: Dictionary = {}
		for gun: TurretStandin in cap.guns():
			axes[gun] = gun.axis
			shots_before[gun] = gun.shots
		_step()
		for gun: TurretStandin in cap.guns():
			fastest_turn = maxf(fastest_turn, (axes[gun] as Vector3).angle_to(gun.axis))
			var fired: int = gun.shots - int(shots_before[gun])
			shots += fired
			# The gate is judged on the axis it fired along.
			if fired > 0 and gun.aim_error_rad() > TurretStandin.GATE_RAD:
				outside += 1
	assert_gt(shots, 0, "the guns came round and fired")
	assert_eq(outside, 0, "no gun fired with its aim outside the gate")
	assert_gt(fastest_turn, 0.0, "the guns turned")
	assert_lte(fastest_turn, TurretStandin.TURN_RATE_RAD_S * DT + 1e-5, "at a limited rate")
	assert_eq(target.damageable.hull.destroyed, false)


func test_an_interceptor_removes_only_hostile_bolts_within_one_and_a_half_km() -> void:
	_capital(Vector3.ZERO)
	var near: Projectile = _hostile_bolt(Vector3(0.0, 200.0, 1000.0))
	var far: Projectile = _hostile_bolt(Vector3(0.0, 2000.0, 2200.0))
	var friendly: Projectile = _hostile_bolt(Vector3(0.0, 100.0, 500.0), Factions.EARTH_ALLIANCE)
	for i: int in roundi(2.0 * TurretStandin.INTERCEPT_INTERVAL_S / DT) + 2:
		_step()
	assert_true(near.is_spent(), "a hostile bolt within 1.5 km is shot down")
	assert_false(far.is_spent(), "one beyond 1.5 km is not")
	assert_false(friendly.is_spent(), "nor a friendly one")
	assert_gt(standins.intercepts, 0, "counted")


func test_the_asteroid_field_is_static_rows_in_the_scan_and_bolts_hit_it() -> void:
	var rocks: Array[Dictionary] = [{"offset": Vector3(0.0, 0.0, -1000.0), "radius": 50.0},
			{"offset": Vector3(400.0, 0.0, -2000.0), "radius": 120.0}]
	var field: AsteroidField = standins.add_asteroids(rocks, world.to_universe(Vector3.ZERO))
	assert_eq(field.count(), 2)
	assert_eq(field.body_rids().size(), 2, "one static physics body per rock, by RID")
	assert_eq(field.get_child_count(), 1, "one multimesh: no mesh, physics or marker node per rock (M4-T29)")
	var scan := ContactScan.from_tree(get_tree())
	assert_eq(scan.contacts_for(-1, Vector3.ZERO, Factions.RAIDERS).size(), 0, "a rock is never a contact (M4-T29)")
	var seen: Array[Contact] = scan.statics_for(-1, Vector3.ZERO, Factions.RAIDERS, 4)
	assert_eq(seen.size(), 2, "every rock is a static row, an obstacle for every side")
	for c: Contact in seen:
		assert_false(c.is_ship, "a rock is a static row, not a ship")
		assert_eq(c.kind, BodyKind.STATIC)
		assert_eq(c.velocity, Vector3.ZERO)
		assert_true(c.bounding_radius == 50.0 or c.bounding_radius == 120.0, "with its own size")
	var resolver := HitResolver.new()
	add_child_autofree(resolver)
	resolver.set_physics_process(false)
	var hits: Array[HitInfo] = []
	resolver.hit_resolved.connect(func(info: HitInfo) -> void: hits.append(info))
	var bolt: Projectile = _hostile_bolt(Vector3(0.0, 0.0, -800.0))
	bolt.velocity = Vector3(0.0, 0.0, -1000.0)
	for i: int in 30:
		if bolt.is_spent():
			break
		bolt._physics_process(DT)
		resolver.resolve(DT)
	assert_eq(hits.size(), 1, "the bolt hit the rock in its path")
	if not hits.is_empty():
		assert_eq(hits[0].target_id, field.row_id(0))
		assert_almost_eq(hits[0].point.z, -950.0, 1.0, "on the rock's face")
		assert_eq(hits[0].applied, 0.0, "rocks do not break")


func test_a_rebase_shifts_every_rock_and_the_capitals() -> void:
	var rocks: Array[Dictionary] = [{"offset": Vector3(100.0, 0.0, -1000.0), "radius": 40.0},
			{"offset": Vector3(-300.0, 50.0, -2000.0), "radius": 80.0}]
	var field: AsteroidField = standins.add_asteroids(rocks, world.to_universe(Vector3.ZERO))
	var cap: CapitalStandin = _capital(Vector3(0.0, 0.0, 3000.0))
	var offset := Vector3(1000.0, -200.0, 500.0)
	var row_before: Vector3 = StaticRows.position_of(field.row_id(1))
	var cap_before: Vector3 = cap.global_position
	world.rebase(offset)
	assert_almost_eq(StaticRows.position_of(field.row_id(1)).distance_to(row_before - offset), 0.0, 1e-3, "the row moved")
	assert_almost_eq(cap.global_position.distance_to(cap_before - offset), 0.0, 1e-3, "the capital moved")
	for i: int in rocks.size():
		var xform: Transform3D = PhysicsServer3D.body_get_state(field.body_rids()[i], PhysicsServer3D.BODY_STATE_TRANSFORM)
		assert_almost_eq(xform.origin.distance_to((rocks[i]["offset"] as Vector3) - offset), 0.0, 1e-3, "rock %d's body moved" % i)
	# Headless rendering keeps no instance data, so the drawing is checked by what carries it: one multimesh of every rock,
	# inside the field node the rebase moved.
	assert_eq(field.multimesh().instance_count, rocks.size(), "one multimesh draws every rock")
	assert_true(field.is_ancestor_of(field.get_child(0)) and field.get_child(0) is MultiMeshInstance3D, "and it moves with the field")


func test_the_gravity_source_bends_a_coasting_path_over_thirty_seconds() -> void:
	assert_eq(world.environment_accel(Vector3.ZERO), Vector3.ZERO, "no field before the harness installs one")
	var gravity: GravityStandin = standins.add_gravity(world.to_universe(Vector3(0.0, -400000.0, 0.0)), 4.8e9)
	var a: Vector3 = world.environment_accel(Vector3.ZERO)
	assert_almost_eq(a.length(), 0.03, 1e-6, "0.03 m/s^2 at 400 km")
	assert_almost_eq(a.normalized().dot(Vector3.DOWN), 1.0, 1e-6, "toward the moon")
	# A bolt-like coasting point, stepped as a ship's force step would: 30 s of ticks.
	var p := Vector3.ZERO
	var v := Vector3(0.0, 0.0, -1000.0)
	for i: int in 1800:
		v += world.environment_accel(p) * DT
		p += v * DT
	var bend: float = Vector2(p.x, p.y).length()
	assert_between(bend, 10.0, 16.0, "about 0.5 a t^2 = 13.5 m off the straight line (%.2f m)" % bend)
	world.rebase(Vector3(0.0, 0.0, -30000.0))
	assert_almost_eq(world.environment_accel(Vector3.ZERO).length(), 4.8e9 / (400000.0 * 400000.0 + 30000.0 * 30000.0), 1e-7,
			"the source stays put in the universe across a rebase")
	standins.remove_gravity()
	assert_eq(world.environment_accel(Vector3.ZERO), Vector3.ZERO, "uninstalled")
	assert_false(is_instance_valid(gravity) and gravity.is_inside_tree(), "and gone")


func test_a_capital_holds_its_cruise_and_falls_with_the_moon_only_through_its_engines() -> void:
	var cap: CapitalStandin = standins.add_capital(&"destroyer", Factions.RAIDERS, "TEST", world.to_universe(Vector3.ZERO),
			Basis.IDENTITY, Vector3(0.0, 0.0, -CapitalStandin.CRUISE_MPS))
	standins.add_gravity(world.to_universe(Vector3(0.0, -400000.0, 0.0)), 4.8e9)
	var force: Vector3 = cap.cruise_force(DT)
	assert_almost_eq(force.y / cap.mass, 0.03, 1e-4, "at cruise its engines only hold off the moon's pull")
	cap.linear_velocity = Vector3.ZERO
	assert_lt(cap.cruise_force(DT).z, 0.0, "below cruise it thrusts along its nose")


# --- missiles, beams, interceptors against missiles, mines (M4-T12) ---------------------------------------------------


func _missile(at: Vector3, faction: StringName = Factions.RAIDERS) -> Projectile:
	var missile := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(missile)
	missile.configure(WeaponSpec.new())
	missile.set_kind(Projectile.KIND_MISSILE)
	missile.faction = faction
	missile.launch(at, Vector3(0.0, 0.0, MissileStandin.SPEED_MPS), now_s)
	missile.set_physics_process(false)
	return missile


func _missiles() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for bolt: Projectile in _bolts():
		if bolt.kind == Projectile.KIND_MISSILE:
			out.append(bolt)
	return out


func _resolver(hits: Array[HitInfo]) -> HitResolver:
	var resolver := HitResolver.new()
	add_child_autofree(resolver)
	resolver.set_physics_process(false)
	resolver.hit_resolved.connect(func(info: HitInfo) -> void: hits.append(info))
	return resolver


# A capital whose guns are taken off, so only the weapon under test fires.
func _quiet_capital(at: Vector3, faction: StringName = Factions.EARTH_ALLIANCE) -> CapitalStandin:
	var cap: CapitalStandin = _capital(at, faction)
	cap.guns().clear()
	return cap


func test_a_capital_carries_two_beam_emitters_and_the_counters_report_every_weapon() -> void:
	var cap: CapitalStandin = _capital(Vector3.ZERO)
	assert_eq(cap.beams().size(), CapitalStandin.BEAMS_PER_CAPITAL, "two beam emitters")
	standins.add_mines([{"offset": Vector3(0.0, 0.0, 3000.0), "faction": Factions.EARTH_ALLIANCE},
			{"offset": Vector3(0.0, 0.0, 3200.0), "faction": Factions.EARTH_ALLIANCE}], world.to_universe(Vector3.ZERO))
	_missile(Vector3(0.0, 0.0, 4000.0))
	_step()
	assert_eq(standins.counts[StandinDirector.Count.BEAMS], CapitalStandin.BEAMS_PER_CAPITAL)
	assert_eq(standins.counts[StandinDirector.Count.MINES], 2)
	assert_eq(standins.counts[StandinDirector.Count.MISSILES], 1, "the missile in flight")


func test_a_beam_hits_the_first_hull_along_its_segment_and_none_behind_it() -> void:
	var cap: CapitalStandin = _quiet_capital(Vector3.ZERO)
	var emitter: BeamStandin = cap.beams()[0]
	var from: Vector3 = emitter.global_position
	var dir: Vector3 = (Vector3(0.0, 300.0, -1200.0) - from).normalized()
	var front: TargetDrone = _drone(from + dir * 1200.0)
	var behind: TargetDrone = _drone(from + dir * 2000.0)
	var beyond: TargetDrone = _drone(from + dir * (BeamStandin.RANGE_M + 200.0))
	var hits: Array[HitInfo] = []
	var resolver: HitResolver = _resolver(hits)
	var beam: Projectile = emitter.fire(front.global_position, now_s, projectiles)
	assert_eq(beam.kind, Projectile.KIND_BEAM)
	assert_almost_eq(beam.last_step.length(), BeamStandin.RANGE_M, 1e-2, "the whole segment in its one tick")
	resolver.resolve(DT)
	assert_eq(hits.size(), 1, "one hit")
	if not hits.is_empty():
		assert_eq(hits[0].target_id, front.get_instance_id(), "on the first hull along it")
		assert_almost_eq(hits[0].point.distance_to(from), 1200.0, 10.0, "at its face")
	assert_eq(behind.damageable.hull.hp, behind.damageable.hull.max_hp, "none behind it")
	assert_eq(beyond.damageable.hull.hp, beyond.damageable.hull.max_hp)
	assert_true(beam.is_spent(), "a beam lives one tick")


func test_a_beam_that_hits_nothing_is_gone_after_its_tick() -> void:
	var cap: CapitalStandin = _quiet_capital(Vector3.ZERO)
	var hits: Array[HitInfo] = []
	var resolver: HitResolver = _resolver(hits)
	var beam: Projectile = cap.beams()[0].fire(Vector3(0.0, 0.0, -5000.0), now_s, projectiles)
	beam._physics_process(DT)  # the projectile's own tick leaves a beam where it was fired
	assert_almost_eq(beam.last_step.length(), BeamStandin.RANGE_M, 1e-2)
	resolver.resolve(DT)
	assert_eq(hits.size(), 0)
	assert_true(beam.is_spent())


func test_beams_fire_at_half_a_hertz_each_only_at_a_hostile_within_three_km() -> void:
	var cap: CapitalStandin = _quiet_capital(Vector3.ZERO)
	_drone(Vector3(0.0, 0.0, -3500.0))  # hostile, beyond a beam's reach
	_drone(Vector3(0.0, 0.0, 2000.0), Factions.EARTH_ALLIANCE)
	for i: int in 240:
		_step()
	var shots: int = 0
	for emitter: BeamStandin in cap.beams():
		shots += emitter.shots
	assert_eq(shots, 0, "nothing hostile within 3 km")
	_drone(Vector3(0.0, 400.0, -2000.0))
	for i: int in StandinDirector.STRIKE_RETARGET_TICKS:
		_step()  # the capital takes the new hostile as its strike target
	var before: Dictionary = {}
	for emitter: BeamStandin in cap.beams():
		before[emitter] = emitter.shots
	for i: int in 240:
		_step()
	for emitter: BeamStandin in cap.beams():
		assert_eq(emitter.shots - int(before[emitter]), 2, "one shot every 2 s")


func test_an_interceptor_removes_a_missile_inside_one_and_a_half_km_first_and_never_a_bolt_outside() -> void:
	_quiet_capital(Vector3.ZERO)
	var bolt_near: Projectile = _hostile_bolt(Vector3(0.0, 100.0, 600.0))
	var missile: Projectile = _missile(Vector3(0.0, 200.0, 1200.0))
	var missile_far: Projectile = _missile(Vector3(0.0, 0.0, 2400.0))
	var bolt_far: Projectile = _hostile_bolt(Vector3(0.0, 2000.0, 2200.0))
	var friendly: Projectile = _missile(Vector3(0.0, 100.0, 500.0), Factions.EARTH_ALLIANCE)
	for i: int in 60:
		_step()
		if standins.intercepts > 0:
			break
	assert_eq(standins.intercepts, 1, "one shot so far")
	assert_true(missile.is_spent(), "the missile inside 1.5 km went first")
	assert_false(bolt_near.is_spent(), "before the nearer bolt")
	for i: int in roundi(2.0 * TurretStandin.INTERCEPT_INTERVAL_S / DT) + 2:
		_step()
	assert_true(bolt_near.is_spent(), "then the bolt")
	assert_false(missile_far.is_spent(), "never a missile beyond 1.5 km")
	assert_false(bolt_far.is_spent(), "nor a bolt")
	assert_false(friendly.is_spent(), "nor a friendly missile")
	assert_eq(standins.missile_intercepts, 1)


func test_a_missile_launched_at_a_crossing_fighter_hits_it_through_the_resolver() -> void:
	_quiet_capital(Vector3.ZERO).beams().clear()
	var target: TargetDrone = _drone(Vector3(0.0, 500.0, -2500.0))
	var crossing := Vector3(120.0, 0.0, 0.0)
	target.linear_velocity = crossing
	standins.missile_target = 1
	var hits: Array[HitInfo] = []
	var resolver: HitResolver = _resolver(hits)
	_step()
	var flying: Array[Projectile] = _missiles()
	assert_eq(flying.size(), 1, "one missile launched")
	if flying.is_empty():
		return
	var missile: Projectile = flying[0]
	assert_eq(missile.faction, Factions.EARTH_ALLIANCE)
	assert_eq(standins.missile_target_of(missile), target.get_instance_id(), "at the fighter")
	standins.missile_target = 0  # no more launches
	var ticks: int = 0
	while not missile.is_spent() and ticks < roundi(MissileStandin.LIFETIME_S / DT):
		missile._physics_process(DT)
		resolver.resolve(DT)
		target.global_position += crossing * DT
		_step()
		ticks += 1
	assert_eq(hits.size(), 1, "it hit")
	if not hits.is_empty():
		assert_eq(hits[0].target_id, target.get_instance_id(), "the fighter")
	assert_lt(float(ticks) * DT, MissileStandin.LIFETIME_S, "within its lifetime (%.1f s)" % (float(ticks) * DT))


func test_the_missiles_in_flight_hold_the_count_asked() -> void:
	_quiet_capital(Vector3.ZERO)
	for i: int in 4:
		_drone(Vector3(float(i) * 200.0, 300.0, -3000.0))
	_drone(Vector3(0.0, 0.0, -MissileStandin.RANGE_M - 500.0))
	standins.missile_target = 5
	for i: int in 10:
		_step()
	assert_eq(standins.counts[StandinDirector.Count.MISSILES], 5, "five in flight")
	assert_eq(_missiles().size(), 5)
	_missiles()[0].spend()
	_step()
	assert_eq(standins.counts[StandinDirector.Count.MISSILES], 5, "a spent one is replaced")
	assert_eq(standins.missile_launches, 6)


func test_no_missile_without_a_hostile_fighter_in_range() -> void:
	_quiet_capital(Vector3.ZERO)
	_drone(Vector3(0.0, 0.0, -MissileStandin.RANGE_M - 500.0))
	_drone(Vector3(0.0, 0.0, -1000.0), Factions.EARTH_ALLIANCE)
	_capital(Vector3(0.0, 0.0, -2000.0), Factions.RAIDERS)  # a hostile capital is not a missile's target
	standins.missile_target = 3
	for i: int in 60:
		_step()
	for m: Projectile in _missiles():
		assert_ne(m.faction, Factions.EARTH_ALLIANCE, "no launch at what is not a hostile fighter in range")


func test_a_mine_detonates_on_a_hostile_never_a_friend_hurts_every_hull_in_its_blast_and_is_gone() -> void:
	var mines: MineStandin = standins.add_mines([{"offset": Vector3(0.0, 0.0, -1000.0), "faction": Factions.EARTH_ALLIANCE},
			{"offset": Vector3(0.0, 0.0, -2000.0), "faction": Factions.EARTH_ALLIANCE}], world.to_universe(Vector3.ZERO))
	assert_eq(mines.count(), 2)
	assert_eq(mines.alive_count(), 2)
	var friend: TargetDrone = _drone(Vector3(30.0, 0.0, -1000.0), Factions.EARTH_ALLIANCE)
	for i: int in 2 * MineStandin.TRIGGER_TICKS:
		_step()
	assert_eq(mines.alive_count(), 2, "a friend inside the trigger sets nothing off")
	var hostile: TargetDrone = _drone(Vector3(0.0, 40.0, -1000.0))
	var far: TargetDrone = _drone(Vector3(0.0, 0.0, -1300.0))
	var ticks: int = 0
	while mines.is_alive(0) and ticks < 10:
		_step()
		ticks += 1
	assert_false(mines.is_alive(0), "the hostile set it off")
	assert_lte(ticks, MineStandin.TRIGGER_TICKS, "within one trigger cadence")
	assert_true(mines.is_alive(1), "the other mine is untouched")
	assert_lt(hostile.damageable.hull.hp, hostile.damageable.hull.max_hp, "the hostile is hurt")
	assert_lt(friend.damageable.hull.hp, friend.damageable.hull.max_hp, "and so is the friend in the blast")
	assert_eq(far.damageable.hull.hp, far.damageable.hull.max_hp, "but not a hull beyond it")
	assert_eq(standins.detonations, 1)
	assert_eq(standins.counts[StandinDirector.Count.MINES], 1, "the row is removed")
	var hp: float = hostile.damageable.hull.hp
	for i: int in 2 * MineStandin.TRIGGER_TICKS:
		_step()
	assert_eq(hostile.damageable.hull.hp, hp, "a mine goes off once")


func test_a_mine_checks_every_third_tick_and_is_laid_again_after_a_while() -> void:
	var rows: Array[Dictionary] = []
	for i: int in 30:
		rows.append({"offset": Vector3(float(i) * 300.0, 0.0, -1000.0), "faction": Factions.EARTH_ALLIANCE})
	var mines: MineStandin = standins.add_mines(rows, world.to_universe(Vector3.ZERO))
	_step()
	assert_eq(mines.checked_last_tick, 10, "a third of the mines each tick")
	var hostile: TargetDrone = _drone(Vector3(0.0, 0.0, -1010.0))
	for i: int in MineStandin.TRIGGER_TICKS:
		_step()
	assert_false(mines.is_alive(0))
	hostile.global_position = Vector3(0.0, 0.0, 5000.0)
	for i: int in roundi(MineStandin.RELAY_S / DT) + MineStandin.TRIGGER_TICKS:
		_step()
	assert_true(mines.is_alive(0), "laid again in its place, so the belt holds the mix")
	assert_eq(mines.alive_count(), 30)


func test_a_rebase_shifts_the_mines() -> void:
	var mines: MineStandin = standins.add_mines([{"offset": Vector3(100.0, 0.0, -1000.0), "faction": Factions.RAIDERS}],
			world.to_universe(Vector3.ZERO))
	var before: Vector3 = mines.position_of(0)
	var offset := Vector3(1000.0, -200.0, 500.0)
	world.rebase(offset)
	assert_almost_eq(mines.position_of(0).distance_to(before - offset), 0.0, 1e-3)
	assert_eq(mines.kind, Targetable.Kind.MINE, "a row of kind mine for the body registry")
