extends GutTest
## The low-attention tier's brains and fire (M4-T22, architecture §17.14): a tier fighter thinks at `tier_brain_hz` in the
## AI step's job, fires through its cannon's own gate and resolves each shot as a seeded to-hit roll from the shot's
## geometry and the shooter's skill, the damage landing through the target's `Damageable` with no bolt row; a near ship's
## bolt hits a tier row; a tier kill goes through the destruction director (pool release, the event with its blast); a far
## capital's guns and beams roll once a second, its interceptors remove hostile missiles in reach and its launches resolve
## at launch. Every test runs on both of T24's schedules (Q54). Skips, saying why, when the library is not built.

const SCHEDULES: Array[StringName] = [&"threaded", &"inline"]
const RADIUS_M: float = 10000.0

var w: TierWorld
var _saved: Dictionary = {}


func before_each() -> void:
	_saved = TierWorld.save_settings()
	TierWorld.use_native(RADIUS_M)
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


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no tier to fight in")
	return true


func _world(raiders: int, allies: int) -> void:
	if w != null:
		w.free_world()
		await get_tree().physics_frame
	ContactScan.invalidate()
	w = TierWorld.new()
	w.build(self, raiders, allies)
	await get_tree().physics_frame


func _use_schedule(schedule: StringName) -> void:
	Settings.set_value(&"sim_step", schedule)
	assert_eq(BrainBatch.step_mode(), BrainBatch.step_mode_of(schedule), "the batch steps on %s" % schedule)


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _tiered(c: Combatant) -> bool:
	return c.ship.is_tier_parked() and w.sim.core.tier_has(c.ship.get_instance_id())


# --- the roll's chance ----------------------------------------------------------------------------------------------------


func test_the_hit_chance_follows_the_range_the_size_and_the_skill() -> void:
	if _skipped():
		return
	await _world(1, 0)
	var core: Object = w.sim.core
	# range, target radius, hit radius, muzzle speed, aim error (rad), the gate's miss distance (m), the bolt's reach (m)
	var base: float = float(core.tier_hit_chance(600.0, 8.0, 0.25, 1000.0, deg_to_rad(1.0), 12.0, 4000.0))
	assert_between(base, 0.01, 0.99, "a fighter at 600 m is neither sure nor hopeless (%.3f)" % base)
	assert_gt(float(core.tier_hit_chance(300.0, 8.0, 0.25, 1000.0, deg_to_rad(1.0), 12.0, 4000.0)), base, "closer hits more")
	assert_gt(float(core.tier_hit_chance(600.0, 16.0, 0.25, 1000.0, deg_to_rad(1.0), 12.0, 4000.0)), base, "bigger hits more")
	assert_gt(float(core.tier_hit_chance(600.0, 8.0, 0.25, 1000.0, deg_to_rad(0.3), 12.0, 4000.0)), base, "a better shot hits more")
	assert_gt(float(core.tier_hit_chance(600.0, 8.0, 0.25, 2000.0, deg_to_rad(1.0), 12.0, 4000.0)), base, "a faster bolt hits more")
	assert_eq(float(core.tier_hit_chance(5000.0, 8.0, 0.25, 1000.0, deg_to_rad(1.0), 12.0, 4000.0)), 0.0, "past the bolt's reach, never")


# --- tier brains ----------------------------------------------------------------------------------------------------------


func test_a_tier_fighter_thinks_at_tier_brain_hz_in_the_step() -> void:
	if _skipped():
		return
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
	if _skipped():
		return
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
	if _skipped():
		return
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
		var bolts_before: int = int(w.sim.core.owned_bolts())
		var shots_before: int = int(w.sim.core.tier_shots())
		await _ticks(600)
		var shots: int = int(w.sim.core.tier_shots()) - shots_before
		assert_gt(shots, 0, "%s: the tier fighters fired (%d shots rolled)" % [schedule, shots])
		assert_eq(int(w.sim.core.owned_bolts()), bolts_before, "%s: no bolt row from a tier shot" % schedule)
		var landed: int = int(w.hits_by_target.get(raider.ship.get_instance_id(), 0)) \
				+ int(w.hits_by_target.get(ally.ship.get_instance_id(), 0))
		assert_gt(landed, 0, "%s: rolled hits landed on the hulls through hit_taken (%d of %d)" % [schedule, landed, shots])
		assert_lt(landed, shots, "%s: and not every shot hit" % schedule)


func test_the_rolls_are_seeded_one_thread_and_six_roll_the_same_hits() -> void:
	if _skipped():
		return
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
	if _skipped():
		return
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
		var id: int = w.sim.add_bolt(from, Vector3(0.0, 0.0, -1000.0), Factions.EARTH_ALLIANCE, w.player.ship.get_instance_id(),
				w.player.cannon.weapon, SimClock.now())
		assert_ne(id, -1, "%s: a near bolt row is out" % schedule)
		await _ticks(30)
		assert_lt(target.damageable.hull.hp, hp, "%s: the tier row took the bolt's damage (%.1f to %.1f)" % [schedule, hp,
				target.damageable.hull.hp])
		assert_almost_eq(float(w.sim.core.tier_state(target.ship.get_instance_id())["hull_fraction"]),
				target.damageable.hull.fraction(), 1e-6, "%s: and its row reads the hull it has left" % schedule)


func test_a_tier_kill_goes_through_the_destruction_director_with_its_blast() -> void:
	if _skipped():
		return
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
	if _skipped():
		return
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
	if _skipped():
		return
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
	if _skipped():
		return
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
	if _skipped():
		return
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
