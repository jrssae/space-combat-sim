extends TestSteps
## The low-attention tier's brains and fire (M4-T22, architecture §17.14): a tier fighter thinks at `tier_brain_hz` in the
## AI step's job, fires through its cannon's own gate and resolves each shot as a seeded to-hit roll from the shot's
## geometry and the shooter's skill, the damage landing through the target's `Damageable` with no bolt row; a near ship's
## bolt hits a tier row; a tier kill goes through the destruction director (pool release, the event with its blast); a far
## capital's guns and beams roll once a second, its interceptors remove hostile missiles in reach and its launches resolve
## at launch. Every test runs on the threaded step (M4-T37 ended Q54's both-schedules rule).

const SCHEDULES: Array[StringName] = [&"threaded"]  # M4-T37: the inline step and Q54's both-schedules rule are gone
const RADIUS_M: float = 10000.0

var w: TierWorld
var _saved: Dictionary = {}


func before_each() -> void:
	_saved = TierWorld.save_settings()
	TierWorld.set_tier(RADIUS_M)
	Settings.set_value(&"tier_hz", 20.0)
	Settings.set_value(&"tier_brain_hz", 4.0)
	Settings.set_value(&"friendly_fire", false)
	Factions.reset()
	ContactScan.invalidate()
	SimClock.reset()


func after_each() -> void:
	if w != null:
		w.free_world()
	w = null
	TierWorld.restore_settings(_saved)
	Factions.reset()
	ContactScan.invalidate()
	await get_tree().physics_frame


func _world(raiders: int, allies: int) -> void:
	if w != null:
		w.free_world()
	await get_tree().physics_frame  # every world starts a frame after the last settings change, so seeded runs line up
	ContactScan.invalidate()
	w = TierWorld.new()
	w.build(self, raiders, allies)
	await get_tree().physics_frame


func _use_schedule(schedule: StringName) -> void:
	Settings.set_value(&"sim_step", schedule)
	assert_eq(BrainBatch.step_mode(), BrainBatch.step_mode_of(schedule), "the batch steps on %s" % schedule)


func _tiered(c: Combatant) -> bool:
	return c.ship.is_tier_parked() and w.sim.core.tier_has(c.ship.get_instance_id())


# --- the roll's chance ----------------------------------------------------------------------------------------------------


func test_the_hit_chance_follows_the_range_the_size_and_the_skill() -> void:
	await _world(1, 0)
	var core: Object = w.sim.core
	# range, target radius, hit radius, muzzle speed, aim error (rad), the gate's miss distance (m), the bolt's reach (m)
	var base: float = float(core.tier_hit_chance(600.0, 8.0, 0.25, 1000.0, 0.0, deg_to_rad(1.0), 12.0, 4000.0, 0.0))
	assert_between(base, 0.01, 0.99, "a fighter at 600 m is neither sure nor hopeless (%.3f)" % base)
	assert_gt(float(core.tier_hit_chance(300.0, 8.0, 0.25, 1000.0, 0.0, deg_to_rad(1.0), 12.0, 4000.0, 0.0)), base, "closer hits more")
	assert_gt(float(core.tier_hit_chance(600.0, 16.0, 0.25, 1000.0, 0.0, deg_to_rad(1.0), 12.0, 4000.0, 0.0)), base, "bigger hits more")
	assert_gt(float(core.tier_hit_chance(600.0, 8.0, 0.25, 1000.0, 0.0, deg_to_rad(0.3), 12.0, 4000.0, 0.0)), base, "a better shot hits more")
	assert_gt(float(core.tier_hit_chance(600.0, 8.0, 0.25, 2000.0, 0.0, deg_to_rad(1.0), 12.0, 4000.0, 0.0)), base, "a faster bolt hits more")
	assert_eq(float(core.tier_hit_chance(5000.0, 8.0, 0.25, 1000.0, 0.0, deg_to_rad(1.0), 12.0, 4000.0, 0.0)), 0.0, "past the bolt's reach, never")
	assert_lt(float(core.tier_hit_chance(600.0, 8.0, 0.25, 1000.0, 0.0, deg_to_rad(1.0), 12.0, 4000.0, 20.0)), base,
			"a shot leaving outside its gate hits less")


# --- tier brains ----------------------------------------------------------------------------------------------------------


func test_a_tier_fighter_thinks_at_tier_brain_hz_in_the_step() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(2, 0)
		_use_schedule(schedule)
		var a: Combatant = w.fighter(ShipPool.DEFAULT_TYPE, "THINKER", Vector3(0.0, 0.0, -20000.0), 7)
		await _ticks(6)
		assert_true(_tiered(a), "%s: 20 km out, the fighter is a tier row" % schedule)
		var host: Object = NativeBrains.host(get_tree())
		var slot: int = (a.driver.brain as AiPilot).native_slot_index()
		var before: int = int(host.slot_think_count(slot))
		await _ticks(60)
		var thinks: int = int(host.slot_think_count(slot)) - before
		assert_between(thinks, 3, 5, "%s: about four thinks in a second at tier_brain_hz 4 (%d)" % [schedule, thinks])
		Settings.set_value(&"tier_brain_hz", 2.0)
		before = int(host.slot_think_count(slot))
		await _ticks(60)
		thinks = int(host.slot_think_count(slot)) - before
		assert_between(thinks, 1, 3, "%s: about two at tier_brain_hz 2 (%d)" % [schedule, thinks])
		Settings.set_value(&"tier_brain_hz", 4.0)


func test_a_tier_fighter_steers_by_its_brain() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(1, 1)
		_use_schedule(schedule)
		# A raider and an allied Starfury 1.5 km apart, flung apart: their brains turn them back into the fight.
		var a: Combatant = w.fighter(ShipPool.DEFAULT_TYPE, "A", Vector3(0.0, 0.0, -20000.0), 3, Basis.IDENTITY, Vector3(0.0, 0.0, 40.0))
		var b: Combatant = w.fighter(ShipPool.ALLY_TYPE, "ALPHA 2", Vector3(0.0, 0.0, -21500.0), 4, Basis.IDENTITY,
				Vector3(0.0, 0.0, -40.0))
		await _ticks(6)
		assert_true(_tiered(a) and _tiered(b), "%s: both fly as tier rows" % schedule)
		var cmd_before: PackedFloat64Array = w.sim.core.row_command(a.ship.get_instance_id())
		await _ticks(90)
		var cmd_after: PackedFloat64Array = w.sim.core.row_command(a.ship.get_instance_id())
		assert_ne(cmd_after, cmd_before, "%s: the tier brain wrote new commands" % schedule)


# --- the roll ---------------------------------------------------------------------------------------------------------------


func test_a_tier_fighter_rolls_its_shots_and_hurts_its_target_through_its_damageable() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(1, 1)
		_use_schedule(schedule)
		var raider: Combatant = w.fighter(ShipPool.DEFAULT_TYPE, "RAIDER", Vector3(0.0, 0.0, -20000.0), 5,
				Basis.IDENTITY, Vector3.ZERO, "raider")
		var ally: Combatant = w.fighter(ShipPool.ALLY_TYPE, "ALPHA 2", Vector3(0.0, 0.0, -20800.0), 6,
				Basis(Vector3.UP, PI), Vector3.ZERO, "ally_starfury")
		raider.damageable.invulnerable = true
		ally.damageable.invulnerable = true
		await _ticks(6)
		assert_true(_tiered(raider) and _tiered(ally), "%s: both fight as tier rows" % schedule)
		var bolts_before: int = int(w.sim.cannons.shots_total())
		var shots_before: int = int(w.sim.core.tier_shots())
		await _ticks(600)
		var shots: int = int(w.sim.core.tier_shots()) - shots_before
		assert_gt(shots, 0, "%s: the tier fighters fired (%d shots rolled)" % [schedule, shots])
		assert_eq(int(w.sim.cannons.shots_total()), bolts_before, "%s: no bolt row from a tier shot" % schedule)
		var landed: int = int(w.hits_by_target.get(raider.ship.get_instance_id(), 0)) \
				+ int(w.hits_by_target.get(ally.ship.get_instance_id(), 0))
		assert_gt(landed, 0, "%s: rolled hits landed on the hulls through hit_taken (%d of %d)" % [schedule, landed, shots])
		assert_lt(landed, shots, "%s: and not every shot hit" % schedule)


func test_the_rolls_are_seeded_one_thread_and_six_roll_the_same_hits() -> void:
	for schedule: StringName in SCHEDULES:
		var runs: Array = []
		for threads: int in [1, 6]:
			Settings.set_value(&"perf_threads", threads)
			SimClock.reset()
			await _world(4, 4)
			_use_schedule(schedule)
			for i: int in 4:
				w.fighter(ShipPool.DEFAULT_TYPE, "R%d" % i, Vector3(float(i) * 120.0, 0.0, -20000.0), 10 + i)
				w.fighter(ShipPool.ALLY_TYPE, "ALPHA %d" % (i + 2), Vector3(float(i) * 120.0, 0.0, -20900.0), 20 + i,
						Basis(Vector3.UP, PI))
			for c: Combatant in w.pool.alive():
				c.damageable.invulnerable = true
			await _ticks(480)
			var summary: Array = []
			for h: Array in w.hits:
				summary.append([HitResolver.name_of(h[0]), HitResolver.name_of(h[1]), h[2]])
			runs.append([int(w.sim.core.tier_shots()), summary])
		assert_gt(int(runs[0][0]), 0, "%s: shots were rolled" % schedule)
		assert_eq(runs[0][0], runs[1][0], "%s: one thread and six roll the same shots" % schedule)
		assert_eq(runs[0][1], runs[1][1], "%s: and land the same hits in the same order" % schedule)


# --- hits from near ships, kills ------------------------------------------------------------------------------------------


func test_a_near_ships_bolt_hits_a_tier_row() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(1, 0)
		_use_schedule(schedule)
		var target: Combatant = w.pool.acquire("TARGET", w.world.to_universe(Vector3(0.0, 0.0, -12000.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new())
		await _ticks(6)
		assert_true(_tiered(target), "%s: 12 km out, the target is a tier row (no body in Jolt)" % schedule)
		var hp: float = target.damageable.hull.hp
		var at: Vector3 = w.sim.core.tier_state(target.ship.get_instance_id())["position"]
		var from: Vector3 = at + Vector3(0.0, 0.0, 300.0)
		assert_true(w.sim.bolt_rows_on(), "%s: the core owns the bolts" % schedule)
		w.sim.add_bolt(from, Vector3(0.0, 0.0, -1000.0), Factions.EARTH_ALLIANCE, w.player.ship.get_instance_id(),
				w.player.cannon.weapon, SimClock.now())
		await _ticks(30)
		assert_lt(target.damageable.hull.hp, hp, "%s: the tier row took the bolt's damage (%.1f to %.1f)" % [schedule, hp,
				target.damageable.hull.hp])
		assert_almost_eq(float(w.sim.core.tier_state(target.ship.get_instance_id())["hull_fraction"]),
				target.damageable.hull.fraction(), 1e-6, "%s: and its row reads the hull it has left" % schedule)


func test_a_tier_kill_goes_through_the_destruction_director_with_its_blast() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(1, 0)
		_use_schedule(schedule)
		var target: Combatant = w.pool.acquire("DOOMED", w.world.to_universe(Vector3(0.0, 0.0, -12000.0)), Basis.IDENTITY,
				Vector3(0.0, 0.0, -50.0), IdleBrain.new())
		target.damageable.hull.apply(target.damageable.hull.hp - 1.0)
		var events: Array = []
		w.destruction.ship_destroyed.connect(func(c: Combatant, info: HitInfo) -> void: events.append([c, info]))
		await _ticks(30)
		assert_true(_tiered(target), "%s: the doomed ship flies as a tier row" % schedule)
		var body_id: int = target.ship.get_instance_id()
		var at: Vector3 = w.sim.core.tier_state(body_id)["position"]
		var parked_at: Vector3 = target.ship.global_position
		assert_gt(at.distance_to(parked_at), 10.0, "%s: its row has flown on from where its node was parked" % schedule)
		w.sim.add_bolt(at + Vector3(0.0, 0.0, 200.0), Vector3(0.0, 0.0, -1050.0), Factions.EARTH_ALLIANCE,
				w.player.ship.get_instance_id(), w.player.cannon.weapon, SimClock.now())
		await _ticks(30)
		assert_eq(events.size(), 1, "%s: one ship_destroyed for the tier kill" % schedule)
		if events.size() == 1:
			var info: HitInfo = events[0][1]
			assert_eq(events[0][0], target, "%s: for the doomed ship" % schedule)
			assert_gt(info.blast_energy_j, 0.0, "%s: the event carries the blast's energy" % schedule)
			assert_gt(info.blast_radius_m, 0.0, "%s: and its radius" % schedule)
			assert_lt(info.blast_point.distance_to(at), 200.0,
					"%s: and the blast is where the row was, not where the node was parked" % schedule)
		assert_false(w.pool.alive().has(target), "%s: the ship went back to the pool" % schedule)
		assert_false(bool(w.sim.core.tier_has(body_id)), "%s: and its row with it" % schedule)


func test_a_near_death_carries_its_blast_too() -> void:
	await _world(1, 0)
	var target: Combatant = w.pool.acquire("NEAR", w.world.to_universe(Vector3(0.0, 0.0, -500.0)), Basis.IDENTITY,
			Vector3.ZERO, IdleBrain.new())
	var events: Array = []
	w.destruction.ship_destroyed.connect(func(_c: Combatant, info: HitInfo) -> void: events.append(info))
	await _ticks(2)
	target.damageable.kill()
	assert_eq(events.size(), 1, "the near kill raised ship_destroyed")
	if events.size() == 1:
		var info: HitInfo = events[0]
		assert_gt(info.blast_energy_j, 0.0, "with the blast's energy")
		assert_gt(info.blast_radius_m, 0.0, "and its radius")
		assert_lt(info.blast_point.distance_to(Vector3(0.0, 0.0, -500.0)), 5.0, "where the ship was")


# --- far capitals ---------------------------------------------------------------------------------------------------------


func test_a_tier_capitals_guns_and_beams_roll_once_a_second_against_fighters_in_range() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(2, 0)
		_use_schedule(schedule)
		var cap: CapitalStandin = w.cruiser(Factions.EARTH_ALLIANCE, "CRUISER", Vector3(0.0, 0.0, -20000.0))
		cap.damageable.invulnerable = true
		var raider: Combatant = w.pool.acquire("PREY", w.world.to_universe(Vector3(0.0, 300.0, -21500.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new())
		raider.damageable.invulnerable = true
		await _ticks(6)
		assert_true(cap.is_tier_parked() and _tiered(raider), "%s: the cruiser and its prey are tier rows" % schedule)
		var rolls_before: int = w.standins.tier_group_rolls
		await _ticks(240)
		var rolls: int = w.standins.tier_group_rolls - rolls_before
		assert_between(rolls, 3, 5, "%s: about one group roll a second (%d in 4 s)" % [schedule, rolls])
		assert_gt(int(w.hits_by_target.get(raider.ship.get_instance_id(), 0)), 0,
				"%s: the guns and beams landed hits on a still fighter 1.5 km off" % schedule)
		assert_eq(_turret_shots(cap), 0, "%s: no turret fired a bolt" % schedule)
		w.standins.clear()


func test_a_tier_capitals_launch_resolves_at_launch_and_counts_in_flight() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(2, 0)
		_use_schedule(schedule)
		var cap: CapitalStandin = w.cruiser(Factions.EARTH_ALLIANCE, "CRUISER", Vector3(0.0, 0.0, -20000.0))
		cap.damageable.invulnerable = true
		w.standins.missile_target = 2
		var raider: Combatant = w.pool.acquire("PREY", w.world.to_universe(Vector3(0.0, 0.0, -23000.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new())
		raider.damageable.invulnerable = true
		await _ticks(6)
		assert_true(cap.is_tier_parked() and _tiered(raider), "%s: the cruiser and its prey are tier rows" % schedule)
		var nodes_before: int = w.projectiles.get_child_count()
		await _ticks(30)
		assert_eq(w.standins.missile_launches, 2, "%s: two missiles launched, resolved at launch" % schedule)
		assert_eq(w.standins.counts[StandinDirector.Count.MISSILES], 2, "%s: and counted in flight" % schedule)
		assert_eq(w.projectiles.get_child_count(), nodes_before, "%s: with no missile node" % schedule)
		await _ticks(600)
		var landed: int = int(w.hits_by_target.get(raider.ship.get_instance_id(), 0))
		assert_gt(landed, 0, "%s: a missile's hit landed on arrival (about 8.6 s for 3 km at 350 m/s)" % schedule)
		w.standins.clear()


func test_a_tier_capitals_interceptors_remove_hostile_missiles_in_reach() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(0, 1)
		_use_schedule(schedule)
		var cap: CapitalStandin = w.cruiser(Factions.EARTH_ALLIANCE, "CRUISER", Vector3(0.0, 0.0, -20000.0))
		cap.damageable.invulnerable = true
		var bait: Combatant = w.pool.acquire("ALPHA 2", w.world.to_universe(Vector3(0.0, 0.0, -20400.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new(), ShipPool.ALLY_TYPE)
		bait.damageable.invulnerable = true
		await _ticks(6)
		assert_true(cap.is_tier_parked(), "%s: the cruiser is a tier row" % schedule)
		var missile: Projectile = MissileStandin.launch(w.projectiles, Vector3(0.0, 0.0, -18700.0), bait.ship, 0,
				Factions.RAIDERS, SimClock.now())
		var intercepts: int = w.standins.missile_intercepts
		await _ticks(90)
		assert_eq(w.standins.missile_intercepts, intercepts + 1, "%s: the tier cruiser's interceptors shot it down" % schedule)
		assert_true(not is_instance_valid(missile) or missile.is_spent(), "%s: the missile is spent" % schedule)
		w.standins.clear()


func _turret_shots(cap: CapitalStandin) -> int:
	var n: int = 0
	for gun: TurretStandin in cap.guns():
		n += gun.shots
	return n


# --- fix round 1 ------------------------------------------------------------------------------------------------------------


func _host() -> Object:
	return NativeBrains.host(get_tree())


func test_tier_thinks_are_counted_and_timed() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(4, 0)
		_use_schedule(schedule)
		for i: int in 4:
			w.fighter(ShipPool.DEFAULT_TYPE, "R%d" % i, Vector3(float(i) * 300.0, 0.0, -20000.0), 40 + i)
		await _ticks(10)
		var thinks: int = 0
		var us: float = 0.0
		for t: int in 60:
			await _ticks(1)
			thinks += int(_host().tier_thinks())
			us += float(_host().tier_think_us())
		assert_between(thinks, 12, 20, "%s: four tier fighters think about four times a second each (%d)" % [schedule, thinks])
		assert_gt(us, 0.0, "%s: and their thinks are timed (%.1f us)" % [schedule, us])


func test_a_hit_does_not_wake_a_tier_think_outside_its_beat() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(1, 1)
		_use_schedule(schedule)
		var target: Combatant = w.fighter(ShipPool.DEFAULT_TYPE, "TARGET", Vector3(0.0, 0.0, -20000.0), 3)
		var shooter: Combatant = w.fighter(ShipPool.ALLY_TYPE, "ALPHA 2", Vector3(0.0, 0.0, -21000.0), 4, Basis(Vector3.UP, PI))
		target.damageable.invulnerable = true
		shooter.damageable.invulnerable = true
		await _ticks(30)
		var slot: int = (target.driver.brain as AiPilot).native_slot_index()
		var before: int = int(_host().slot_think_count(slot))
		var id: int = target.ship.get_instance_id()
		for t: int in 60:
			TierDirector.land_hits(PackedInt64Array([id]), PackedInt64Array([shooter.ship.get_instance_id()]),
					PackedFloat64Array([1.0]), PackedVector3Array([Vector3.ZERO]))
			await _ticks(1)
		var thinks: int = int(_host().slot_think_count(slot)) - before
		assert_between(thinks, 3, 5, "%s: hit every tick, a tier ship still thinks on its beat only (%d in a second)" % [schedule, thinks])


func test_a_far_capitals_missile_is_shot_down_by_its_targets_interceptors() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(2, 0)
		_use_schedule(schedule)
		var cap: CapitalStandin = w.cruiser(Factions.EARTH_ALLIANCE, "CRUISER", Vector3(0.0, 0.0, -20000.0))
		var guard: CapitalStandin = w.cruiser(Factions.RAIDERS, "GUARD", Vector3(0.0, 400.0, -23000.0))
		cap.damageable.invulnerable = true
		guard.damageable.invulnerable = true
		var raider: Combatant = w.pool.acquire("PREY", w.world.to_universe(Vector3(0.0, 0.0, -22000.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new())
		raider.damageable.invulnerable = true
		await _ticks(10)
		assert_true(cap.is_tier_parked() and guard.is_tier_parked() and _tiered(raider), "%s: all three are tier rows" % schedule)
		w.standins.missile_target = 2  # from now on every launch is the far cruiser's, resolved at launch
		var intercepts: int = w.standins.missile_intercepts
		var launches: int = w.standins.missile_launches
		await _ticks(900)
		assert_gt(w.standins.missile_launches - launches, 0, "%s: the far cruiser launched" % schedule)
		assert_gt(w.standins.missile_intercepts - intercepts, 0, "%s: the guard's interceptors shot its missiles down" % schedule)
		var missile_hits: int = 0
		for h: Array in w.hits:
			if int(h[0]) == raider.ship.get_instance_id() and is_equal_approx(float(h[2]), 40.0):
				missile_hits += 1
		assert_eq(missile_hits, 0, "%s: none landed on the guarded fighter" % schedule)
		w.standins.clear()


func test_a_far_missile_does_not_land_on_a_respawned_target_or_a_hulk() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(1, 0)
		_use_schedule(schedule)
		var cap: CapitalStandin = w.cruiser(Factions.EARTH_ALLIANCE, "CRUISER", Vector3(0.0, 0.0, -20000.0))
		cap.damageable.invulnerable = true
		var raider: Combatant = w.pool.acquire("PREY", w.world.to_universe(Vector3(0.0, 0.0, -25000.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new())
		raider.damageable.invulnerable = true
		await _ticks(10)
		w.standins.missile_target = 1
		await _ticks(20)
		assert_gt(w.standins.missile_launches, 0, "%s: a missile is out" % schedule)
		w.standins.missile_target = 0
		# The target goes back to the pool and comes out again as somebody new, in the same place, before the missile lands.
		w.pool.release(raider)
		await _ticks(2)
		var again: Combatant = w.pool.acquire("NEW", w.world.to_universe(Vector3(0.0, 0.0, -25000.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new())
		again.damageable.invulnerable = true
		assert_eq(again, raider, "%s: the same pooled ship" % schedule)
		var hits_before: int = w.hits.size()
		await _ticks(1000)
		assert_eq(w.hits.size(), hits_before, "%s: the old missile did not land on the new pilot" % schedule)
		w.standins.clear()


func test_a_committed_rammer_in_the_tier_lands_ram_damage() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(1, 1)
		_use_schedule(schedule)
		var rams: Array = []
		# As test_ai_ram flies it: a reckless raider at 20 % hull, committed to the ram.
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider", "aggression": "reckless"},
				w.world.to_universe(Vector3(0.0, 0.0, -20000.0)), 5)
		var rammer: Combatant = w.pool.acquire("RAMMER", w.world.to_universe(Vector3(0.0, 0.0, -20000.0)), Basis.IDENTITY,
				Vector3.ZERO, made["brain"] as PilotBrain, ShipPool.DEFAULT_TYPE)
		rammer.damageable.apply_hit(HitInfo.new(rammer.ship.get_instance_id(), 0, &"", rammer.damageable.hull.max_hp * 0.8,
				Vector3.ZERO, Vector3.ZERO, 0.0, HitInfo.CAUSE_CONSOLE))
		var target: Combatant = w.pool.acquire("ALPHA 9", w.world.to_universe(Vector3(0.0, 0.0, -21200.0)), Basis.IDENTITY,
				Vector3(60.0, 0.0, 0.0), null, ShipPool.ALLY_TYPE)
		target.damageable.hull = HullHealth.new(1.0e6)
		for c: Combatant in [rammer, target]:
			c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
				if info.cause == HitInfo.CAUSE_RAM:
					rams.append(info))
		await _ticks(10)
		assert_true(_tiered(rammer) and _tiered(target), "%s: both are tier rows" % schedule)
		var pilot := rammer.driver.brain as AiPilot
		var ram := pilot.behaviour(&"ram") as BehaviourRam
		assert_true(ram.commit(pilot.context), "%s: the rammer committed in the tier" % schedule)
		var t: int = 0
		while rams.is_empty() and t < 1800:
			await _ticks(1)
			t += 1
		assert_false(rams.is_empty(), "%s: the tier rammer rammed its tier target (%d ticks)" % [schedule, t])


func test_the_rolls_follow_the_seed() -> void:
	var runs: Array = []
	for seed_value: int in [7, 7, 8]:
		await _world(4, 4)
		w.tier.seed_value = seed_value
		for i: int in 4:
			w.fighter(ShipPool.DEFAULT_TYPE, "R%d" % i, Vector3(float(i) * 120.0, 0.0, -20000.0), 10 + i)
			w.fighter(ShipPool.ALLY_TYPE, "ALPHA %d" % (i + 2), Vector3(float(i) * 120.0, 0.0, -20900.0), 20 + i,
					Basis(Vector3.UP, PI))
		for c: Combatant in w.pool.alive():
			c.damageable.invulnerable = true
		await _ticks(360)
		var summary: Array = []
		for h: Array in w.hits:
			summary.append([HitResolver.name_of(h[0]), HitResolver.name_of(h[1])])
		runs.append(summary)
	assert_eq(runs[0], runs[1], "the same seed rolls the same hits")
	assert_ne(runs[0], runs[2], "another seed rolls others")


func test_a_rolled_hit_lands_on_a_hulk_and_a_shooters_pending_hits_land_after_its_promotion() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(2, 0)
		_use_schedule(schedule)
		var hulk: Combatant = w.pool.acquire("HULK", w.world.to_universe(Vector3(0.0, 0.0, -20000.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new())
		var shooter: Combatant = w.pool.acquire("SHOOTER", w.world.to_universe(Vector3(0.0, 0.0, -21000.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new())
		await _ticks(6)
		var hid: int = hulk.ship.get_instance_id()
		w.sim.core.tier_set_hulk(hid, true)
		var hp: float = hulk.damageable.hull.hp
		# A hit rolled this tick, then its shooter promoted before the director lands it.
		w.sim.core.tier_push_hit(hid, shooter.ship.get_instance_id(), 5.0, Vector3.ZERO)
		w.tier.promote_body(shooter.ship.get_instance_id())
		await _ticks(2)
		assert_almost_eq(hulk.damageable.hull.hp, hp - 5.0, 1e-3, "%s: the hit landed on the hulk after its shooter's promotion" % schedule)
		assert_true(bool(w.sim.core.tier_state(hid).get("hulk", false)), "%s: and the hulk stays a hulk row" % schedule)


func test_a_near_rammer_lands_ram_damage_on_a_tier_target() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(1, 1)
		_use_schedule(schedule)
		var rams: Array = []
		var target: Combatant = w.pool.acquire("ALPHA 9", w.world.to_universe(Vector3(0.0, 0.0, -12000.0)), Basis.IDENTITY,
				Vector3(40.0, 0.0, 0.0), null, ShipPool.ALLY_TYPE)
		target.damageable.hull = HullHealth.new(1.0e6)
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider", "aggression": "reckless"},
				w.world.to_universe(Vector3(0.0, 0.0, -10600.0)), 6)
		var rammer: Combatant = w.pool.acquire("RAMMER", w.world.to_universe(Vector3(0.0, 0.0, -10600.0)), Basis.IDENTITY,
				Vector3.ZERO, made["brain"] as PilotBrain, ShipPool.DEFAULT_TYPE)
		rammer.damageable.apply_hit(HitInfo.new(rammer.ship.get_instance_id(), 0, &"", rammer.damageable.hull.max_hp * 0.8,
				Vector3.ZERO, Vector3.ZERO, 0.0, HitInfo.CAUSE_CONSOLE))
		for c: Combatant in [rammer, target]:
			c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
				if info.cause == HitInfo.CAUSE_RAM:
					rams.append(info))
		await _ticks(10)
		w.tier.handovers_per_tick = 0  # the rammer stays near and the target in the tier from here on
		assert_true(_tiered(target) and not rammer.ship.is_tier_parked(), "%s: a near rammer and a tier target" % schedule)
		var pilot := rammer.driver.brain as AiPilot
		assert_true((pilot.behaviour(&"ram") as BehaviourRam).commit(pilot.context), "%s: committed" % schedule)
		var t: int = 0
		while rams.is_empty() and t < 1200:
			await _ticks(1)
			t += 1
		assert_false(rams.is_empty(), "%s: the near rammer rammed the tier target (%d ticks)" % [schedule, t])


func test_a_tier_kill_by_a_roll_frees_its_wing_slot_raises_the_kill_and_the_slot_is_refilled() -> void:
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.ally_pool_size = 4
	add_child_autofree(main)
	await _ticks(2)
	var wing: Wing = main.wings.player_wing()
	main.wings.replenish(wing)
	await _ticks(2)
	var member: Combatant = wing.members()[0]
	var slot: int = wing.slot_of(member)
	member.damageable.invulnerable = false
	var kills: Array = []
	main.director.ship_destroyed.connect(func(c: Combatant, info: HitInfo) -> void: kills.append([c, info]))
	member.ship.global_position = main.ship.global_position + Vector3(0.0, 0.0, -20000.0)
	member.ship.reset_physics_interpolation()
	await _ticks(10)
	var sim: SimCore = SimCore.for_tree(get_tree())
	var id: int = member.ship.get_instance_id()
	assert_true(member.ship.is_tier_parked() and bool(sim.core.tier_has(id)), "the wingman 20 km out flies as a tier row")
	sim.core.tier_push_hit(id, main.ship.get_instance_id(), member.damageable.hull.hp + 1.0, Vector3.ZERO)
	await _ticks(3)
	assert_eq(kills.size(), 1, "the rolled kill raised ship_destroyed (what the score counts)")
	assert_false(main.ships.alive().has(member), "the ship went back to the pool")
	assert_false(wing.members().has(member), "and left its wing")
	assert_true(wing.empty_slots().has(slot), "its slot is owed")
	var refilled: Array[Combatant] = main.wings.replenish(wing)
	assert_eq(refilled.size(), 1, "the slot is refilled by a new pilot")


# --- fix round 2: the lean tier think --------------------------------------------------------------------------------------


func test_a_tier_think_skips_the_avoidance_a_tier_row_cannot_use() -> void:
	for schedule: StringName in SCHEDULES:
		for tier_on: bool in [false, true]:
			await _world(2, 0)
			_use_schedule(schedule)
			Settings.set_value(&"tier_radius_m", RADIUS_M if tier_on else 0.0)
			# Two raiders of one side flying head on, 300 m apart: a near pilot swerves; a tier row cannot collide.
			var a: Combatant = w.fighter(ShipPool.DEFAULT_TYPE, "A", Vector3(0.0, 0.0, -20000.0), 61, Basis.IDENTITY,
					Vector3(0.0, 0.0, -60.0))
			var b: Combatant = w.fighter(ShipPool.DEFAULT_TYPE, "B", Vector3(0.0, 0.0, -20600.0), 62, Basis(Vector3.UP, PI),
					Vector3(0.0, 0.0, 60.0))
			# Only the thinks after the handover count (both start near enough to think on their bodies for a few ticks).
			var waited: int = 0
			while tier_on and not (_tiered(a) and _tiered(b)) and waited < 30:
				await _ticks(1)
				waited += 1
			var thinks_at: Dictionary = {}
			for c: Combatant in [a, b]:
				thinks_at[c] = int(_host().slot_think_count((c.driver.brain as AiPilot).native_slot_index()))
			var avoided: bool = false
			for t: int in 120:
				await _ticks(1)
				for c: Combatant in [a, b]:
					var slot: int = (c.driver.brain as AiPilot).native_slot_index()
					if int(_host().slot_think_count(slot)) <= int(thinks_at[c]):
						continue
					var out: PackedFloat64Array = _host().slot_output(slot)
					avoided = avoided or (out.size() > 13 and out[13] != 0.0)
			if tier_on:
				assert_true(_tiered(a) and _tiered(b), "%s: both fly as tier rows" % schedule)
				assert_false(avoided, "%s: a tier think does not steer round what a tier row cannot hit" % schedule)
			else:
				assert_true(avoided, "%s: near, the pilots swerve (the check sees avoidance when it runs)" % schedule)
