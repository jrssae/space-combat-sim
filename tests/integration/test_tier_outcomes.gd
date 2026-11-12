extends TestSteps
## The low-attention tier's fairness (M4-T22, architecture §17.14): a fight out of view wins or loses at the rate one in view
## does. Every comparison is the tier against full fidelity on held-out seeds (fix round 1; the Cycle log has the fit): the
## hit model's constants by maximum likelihood over full-fidelity melee shots (seeds 11 to 16) and duel rounds (seeds from
## 50 000), the per-hull terms (`ShipSpec.tier_hit_scale`) from the even fight below on seeds 101 to 103, on the threaded step;
## never on the seeds tested here.
## - The duel: rounds of head-on engagements (the first build's steady chase, where Starfuries hit 73 % at 450 m, is a known
##   limit the model under-scores), 1 000 shots or more: the model's expected to-hit rate over the same shots, with each shot's
##   gate excess, within 10 % of full fidelity's (the seeded roll printed beside it). The per-hull term (`ShipSpec.
##   tier_hit_scale`) is not in it: it corrects how a tier fight's flight differs (more and closer shots), which a comparison
##   over the same shots has no part of, and the even fight holds it.
## - An even fight (the maintainer's Q63): 12 Starfuries against 40 raiders at the same skill and temperament (regular,
##   balanced), the count the full-fidelity sweep found nearest an even fight (seeds 201 to 203: 32 raiders lose every
##   seed, 40 win one in three, 42 two in three, 44 every one; the Cycle log has the table), 30 s, seeds 1 to 3: for each
##   side the hits it lands and the mean hull loss it takes, pooled over the three seeds, recorded against 15 % but not
##   checked (the maintainer's Q64: full fidelity differs from itself by 36 to 38 % a side between the two schedules on these
##   seeds); the tier's win share
##   (the side with the larger share of its hull left after 30 s) within one seed in three of full fidelity's, the spread the
##   sweep showed between neighbouring counts; each seed's hits within a factor of two.
## - A cruiser with 8 guns and 2 beams against 12 invulnerable fighters, 30 s: their hull loss (damage over hull) within 15 %.
## - Far missiles: a cruiser launching at fighters about a hostile guard cruiser with interceptors, 30 s: the share shot
##   down within 15 %.
## Real pooled ships, drivers, Jolt, the hit resolver and the core, on the threaded step (M4-T37 ended Q54's both-schedules rule).

const SCHEDULES: Array[StringName] = [&"threaded"]  # M4-T37: the inline step and Q54's both-schedules rule are gone
const SEEDS: Array[int] = [1, 2, 3]
const FIGHT_TICKS: int = 1800
const DUEL_SHOTS: int = 1000
const DUEL_PAIRS: int = 12
const DUEL_MAX_TICKS: int = 9000
const DUEL_ROUND_TICKS: int = 600
const DUEL_TOLERANCE: float = 0.10
const FIGHT_TOLERANCE: float = 0.15
const SEED_FACTOR: float = 2.0
const ALLIES: int = 12
const RAIDERS: int = 40
const EVEN: Dictionary = {"skill": "regular", "aggression": "balanced"}
## How far the tier's win share may sit from full fidelity's over the three seeds: one seed (the sweep's spread).
const WIN_SHARE_SPREAD: float = 1.0 / 3.0
const TIER_RADIUS_M: float = 10000.0
## Where the fights sit: far enough out that every ship is a tier row with the tier on.
const FIGHT_AT := Vector3(0.0, 0.0, -20000.0)

var w: TierWorld
var _saved: Dictionary = {}


# A slow file (M4-T36, Q58): runs with GUT_SLOW=1 (the full run and CI), skipped in focused runs.
@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


func before_each() -> void:
	_saved = TierWorld.save_settings()
	TierWorld.set_tier(0.0)
	Settings.set_value(&"tier_hz", 20.0)
	Settings.set_value(&"tier_brain_hz", float(SettingsSchema.ENTRIES[&"tier_brain_hz"]["default"]))  # the game's rate
	Settings.set_value(&"friendly_fire", false)
	Factions.reset()
	ContactScan.invalidate()


func after_each() -> void:
	if w != null:
		w.free_world()
	w = null
	TierWorld.restore_settings(_saved)
	Factions.reset()
	ContactScan.invalidate()
	await get_tree().physics_frame


func _world(raiders: int, allies: int, tier_on: bool, schedule: StringName) -> void:
	if w != null:
		w.free_world()
	await get_tree().physics_frame  # every world starts a frame after the last settings change, so seeded runs line up
	Settings.set_value(&"sim_step", schedule)
	Settings.set_value(&"tier_radius_m", TIER_RADIUS_M if tier_on else 0.0)
	Factions.reset()
	ContactScan.invalidate()
	SimClock.reset()
	w = TierWorld.new()
	w.build(self, raiders, allies)
	await get_tree().physics_frame


# --- the duel: the roll against full fidelity, shot for shot ---------------------------------------------------------------


func test_the_to_hit_roll_matches_a_seeded_full_fidelity_duel_within_ten_percent() -> void:
	for schedule: StringName in SCHEDULES:
		await _world(DUEL_PAIRS, DUEL_PAIRS, false, schedule)
		# Rounds of duels: in each, a raider and an allied Starfury meet head on from 1.8 km (each pair 31 km from the next,
		# out of each other's sensors) and fight for `DUEL_ROUND_TICKS`; then every pair starts again, until 1 000 shots.
		var shots: Array = []
		var round_index: int = 0
		var ticks: int = 0
		while shots.size() < DUEL_SHOTS and ticks < DUEL_MAX_TICKS:
			for c: Combatant in w.pool.alive():
				_unwatch_duel(c)
				w.pool.release(c)
			await _ticks(2)
			for i: int in DUEL_PAIRS:
				var centre := Vector3(cos(TAU * i / DUEL_PAIRS), 0.0, sin(TAU * i / DUEL_PAIRS)) * 60000.0
				var raider: Combatant = w.fighter(ShipPool.DEFAULT_TYPE, "RAIDER %d" % (i + 1), centre + Vector3(0.0, 0.0, 900.0),
						1000 * round_index + 100 + i, Basis.IDENTITY, Vector3(0.0, 0.0, -40.0))
				var ally: Combatant = w.fighter(ShipPool.ALLY_TYPE, "ALPHA %d" % (i + 2), centre + Vector3(0.0, 0.0, -900.0),
						1000 * round_index + 200 + i, Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 40.0))
				raider.damageable.invulnerable = true
				ally.damageable.invulnerable = true
				_watch_duel(raider, ally, shots)
				_watch_duel(ally, raider, shots)
			for t: int in DUEL_ROUND_TICKS:
				await get_tree().physics_frame
			ticks += DUEL_ROUND_TICKS
			round_index += 1
		await _ticks(300)  # the last bolts land (a raider's plasma takes up to 4 s)
		for c: Combatant in w.pool.alive():
			_unwatch_duel(c)
		assert_gte(shots.size(), DUEL_SHOTS, "%s: %d shots fired in %d rounds" % [schedule, shots.size(), round_index])
		var landed: int = w.hits.size()
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var rolled: int = 0
		var expected: float = 0.0
		for shot: Array in shots:
			var chance: float = float(w.sim.core.tier_hit_chance(shot[0], shot[1], shot[2], shot[3], shot[4], shot[5], shot[6],
					shot[7], shot[8]))
			expected += chance
			if rng.randf() < chance:
				rolled += 1
		var rate_full: float = float(landed) / float(shots.size())
		var rate_tier: float = expected / float(shots.size())
		gut.p("%s duel: %d shots in %d rounds, full fidelity %d hits (%.3f), the model expects %.1f (%.3f), a seeded roll %d" % [
				schedule, shots.size(), round_index, landed, rate_full, expected, rate_tier, rolled])
		assert_lte(absf(rate_tier - rate_full), DUEL_TOLERANCE * rate_full,
				"%s: the model's to-hit rate within 10 %% of full fidelity's (%.3f against %.3f)" % [schedule, rate_tier, rate_full])


# Records every shot `shooter` fires at `target` with the geometry the tier's roll takes.
func _watch_duel(shooter: Combatant, target: Combatant, shots: Array) -> void:
	var watch: Callable = _on_duel_shot.bind(shooter, target, shots)
	shooter.cannon.shot_fired.connect(watch)
	shooter.set_meta(&"_duel_watch", watch)


func _unwatch_duel(c: Combatant) -> void:
	if c.has_meta(&"_duel_watch"):
		var watch: Callable = c.get_meta(&"_duel_watch")
		if c.cannon.shot_fired.is_connected(watch):
			c.cannon.shot_fired.disconnect(watch)
		c.remove_meta(&"_duel_watch")


# Each shot's geometry as the tier's roll takes it: the range, the target's radius, the bolt's hit radius and speed, the
# closing speed, the shooter's aim error and miss gate, the bolt's reach, and how far outside its gate the nose was.
# A shooter released since stops recording.
func _on_duel_shot(_muzzle: int, at: Vector3, shooter: Combatant, target: Combatant, shots: Array) -> void:
	var pilot := shooter.driver.brain as AiPilot
	if pilot == null or pilot.profile == null or not w.pool.alive().has(target):
		return
	var weapon: WeaponSpec = shooter.cannon.weapon
	var line: Vector3 = target.ship.global_position - at
	var closing: float = -(target.ship.linear_velocity - shooter.ship.linear_velocity).dot(line.normalized())
	var excess: float = float(w.sim.core.tier_gate_excess(at, shooter.ship.linear_velocity, -shooter.ship.global_basis.z,
			target.ship.global_position, target.ship.linear_velocity, weapon.muzzle_speed_mps,
			deg_to_rad(pilot.profile.tactics.fire_cone_deg), pilot.profile.tactics.fire_miss_m))
	shots.append([line.length(), target.damageable.bounding_radius, weapon.hit_radius_m, weapon.muzzle_speed_mps, closing,
			deg_to_rad(pilot.profile.aim_error_deg), pilot.profile.tactics.fire_miss_m, weapon.muzzle_speed_mps * weapon.lifetime_s,
			excess])


# --- an even fight: 12 against 40 ---------------------------------------------------------------------------------------


func test_an_even_fight_in_the_tier_ends_as_it_does_at_full_fidelity_for_each_side() -> void:
	for schedule: StringName in SCHEDULES:
		var pool: Dictionary = {}
		for key: String in ["full_hits_a", "tier_hits_a", "full_hits_r", "tier_hits_r", "full_loss_a", "tier_loss_a",
				"full_loss_r", "tier_loss_r", "full_wins", "tier_wins"]:
			pool[key] = 0.0
		for seed_value: int in SEEDS:
			var full: Dictionary = await _fight(seed_value, false, schedule)
			var tier: Dictionary = await _fight(seed_value, true, schedule)
			var label: String = "%s seed %d" % [schedule, seed_value]
			gut.p("%s: full fidelity %s; the tier %s" % [label, full, tier])
			assert_gt(int(tier["tier_rows"]), ALLIES + RAIDERS - 4, "%s: the tier fight flew in the tier (%d rows)" % [label, int(tier["tier_rows"])])
			assert_eq(int(full["tier_rows"]), 0, "%s: the full-fidelity fight did not" % label)
			var full_hits: float = float(full["hits_a"]) + float(full["hits_r"])
			var tier_hits: float = float(tier["hits_a"]) + float(tier["hits_r"])
			assert_between(tier_hits, full_hits / SEED_FACTOR, full_hits * SEED_FACTOR,
					"%s: the seed's hits within a factor of two (%d against %d)" % [label, int(tier_hits), int(full_hits)])
			for side: String in ["a", "r"]:
				for what: String in ["hits", "loss"]:
					pool["full_%s_%s" % [what, side]] += float(full["%s_%s" % [what, side]])
					pool["tier_%s_%s" % [what, side]] += float(tier["%s_%s" % [what, side]])
			pool["full_wins"] += 1.0 if float(full["margin"]) > 0.0 else 0.0
			pool["tier_wins"] += 1.0 if float(tier["margin"]) > 0.0 else 0.0
		gut.p("%s seeds 1 to 3, the tier against full fidelity: %s" % [schedule, pool])
		# The per-side bound is a recorded measurement, not a check (the maintainer's Q64): on these seeds full fidelity
		# differs from itself by 36 to 38 % a side between the two schedules, so three pooled fights cannot hold 15 %.
		var misses: PackedStringArray = []
		for side: String in ["a", "r"]:
			var name: String = "the Starfuries" if side == "a" else "the raiders"
			for what: String in ["hits", "loss"]:
				var t: float = pool["tier_%s_%s" % [what, side]]
				var f: float = pool["full_%s_%s" % [what, side]]
				if absf(t - f) > FIGHT_TOLERANCE * f:
					misses.append("%s's %s %.3f against %.3f" % [name, "hits landed" if what == "hits" else "hull loss taken", t, f])
		gut.p("%s: per side over seeds 1 to 3 (recorded, Q64): %s" % [schedule,
				"all within 15 %" if misses.is_empty() else "outside 15 %: " + ", ".join(misses)])
		var share_full: float = pool["full_wins"] / float(SEEDS.size())
		var share_tier: float = pool["tier_wins"] / float(SEEDS.size())
		assert_lte(absf(share_tier - share_full), WIN_SHARE_SPREAD + 1e-6,
				"%s: the Starfuries' win share within one seed in three (%.2f against %.2f)" % [schedule, share_tier, share_full])


## One 30 s fight of 12 allied Starfuries against 40 raiders at `FIGHT_AT`, the same temperament on both sides, seeded, in
## the tier or not. Returns per side (`a` the Starfuries, `r` the raiders) the bolt hits it landed, the mean hull loss it
## took (a ship destroyed counts 1) and its survivors, the margin (the Starfuries' share of hull left minus the raiders'),
## and the tier rows seen after the first second.
func _fight(seed_value: int, tier_on: bool, schedule: StringName) -> Dictionary:
	await _world(RAIDERS, ALLIES, tier_on, schedule)
	w.tier.seed_value = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var allies: Array[Combatant] = []
	var raiders: Array[Combatant] = []
	for i: int in maxi(ALLIES, RAIDERS):
		var jitter := Vector3(rng.randf_range(-150.0, 150.0), rng.randf_range(-100.0, 100.0), rng.randf_range(-150.0, 150.0))
		var lane := Vector3(float(i % 4) * 150.0 - 225.0, float(i / 4) * 120.0 - 120.0, 0.0)
		if i < ALLIES:
			allies.append(w.fighter(ShipPool.ALLY_TYPE, "ALPHA %d" % (i + 2), FIGHT_AT + lane + jitter + Vector3(0.0, 0.0, 900.0),
					seed_value * 100 + i, Basis.IDENTITY, Vector3(0.0, 0.0, -40.0), "", EVEN))
		if i < RAIDERS:
			raiders.append(w.fighter(ShipPool.DEFAULT_TYPE, "RAIDER %d" % (i + 1), FIGHT_AT + lane - jitter - Vector3(0.0, 0.0, 900.0),
					seed_value * 100 + 50 + i, Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 40.0), "", EVEN))
	var ally_ids: Dictionary = {}
	for c: Combatant in allies:
		ally_ids[c.ship.get_instance_id()] = true
	await _ticks(60)
	var tier_rows: int = int(w.sim.core.tier_count())
	await _ticks(FIGHT_TICKS - 60)
	var hits_a: int = 0
	var hits_r: int = 0
	for h: Array in w.hits:
		if ally_ids.has(int(h[1])):
			hits_a += 1
		else:
			hits_r += 1
	var survivors_a: int = 0
	var survivors_r: int = 0
	for c: Combatant in allies:
		survivors_a += 0 if c.damageable.hull.destroyed else 1
	for c: Combatant in raiders:
		survivors_r += 0 if c.damageable.hull.destroyed else 1
	return {"hits_a": hits_a, "hits_r": hits_r, "loss_a": snappedf(TierWorld.mean_hull_loss(allies), 0.001),
			"loss_r": snappedf(TierWorld.mean_hull_loss(raiders), 0.001), "survivors_a": survivors_a, "survivors_r": survivors_r,
			"margin": snappedf(TierWorld.hull_left(allies) / ALLIES - TierWorld.hull_left(raiders) / RAIDERS, 0.001),
			"tier_rows": tier_rows}


# --- a cruiser against 12 fighters -------------------------------------------------------------------------------------------


func test_a_cruiser_against_twelve_fighters_in_the_tier_hurts_them_as_at_full_fidelity() -> void:
	for schedule: StringName in SCHEDULES:
		var full: Dictionary = await _cruiser_fight(false, schedule)
		var tier: Dictionary = await _cruiser_fight(true, schedule)
		gut.p("%s cruiser: full fidelity %s; the tier %s" % [schedule, full, tier])
		assert_true(bool(tier["capital_tiered"]), "%s: the cruiser fought as a tier row" % schedule)
		assert_gt(float(full["loss"]), 0.0, "%s: the cruiser hurt the fighters at full fidelity" % schedule)
		assert_lte(absf(float(tier["loss"]) - float(full["loss"])), FIGHT_TOLERANCE * float(full["loss"]),
				"%s: the fighters' hull loss within 15 %% (%.3f against %.3f)" % [schedule, float(tier["loss"]), float(full["loss"])])


func _cruiser_fight(tier_on: bool, schedule: StringName) -> Dictionary:
	await _world(12, 0, tier_on, schedule)
	var cap: CapitalStandin = w.cruiser(Factions.EARTH_ALLIANCE, "CRUISER", FIGHT_AT, Vector3(0.0, 0.0, -30.0))
	cap.damageable.invulnerable = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var raiders: Array[Combatant] = []
	var hull: float = 0.0
	for i: int in 12:
		var at: Vector3 = FIGHT_AT + Vector3(rng.randf_range(-600.0, 600.0), rng.randf_range(-300.0, 300.0), -2500.0 - rng.randf_range(0.0, 600.0))
		var c: Combatant = w.fighter(ShipPool.DEFAULT_TYPE, "RAIDER %d" % (i + 1), at, 300 + i, Basis.IDENTITY, Vector3(0.0, 0.0, 40.0))
		c.damageable.invulnerable = true
		hull += c.damageable.hull.max_hp
		raiders.append(c)
	await _ticks(60)
	var capital_tiered: bool = cap.is_tier_parked()
	await _ticks(FIGHT_TICKS - 60)
	var damage: float = 0.0
	for h: Array in w.hits:
		damage += float(h[2])
	w.standins.clear()
	return {"loss": damage / hull, "hits": w.hits.size(), "capital_tiered": capital_tiered}


# --- far missiles ------------------------------------------------------------------------------------------------------------


func test_far_missiles_are_shot_down_at_the_rate_near_ones_are() -> void:
	for schedule: StringName in SCHEDULES:
		var full: Dictionary = await _missile_fight(false, schedule)
		var tier: Dictionary = await _missile_fight(true, schedule)
		gut.p("%s missiles: full fidelity %s; the tier %s" % [schedule, full, tier])
		assert_true(bool(tier["tiered"]), "%s: the capitals fought as tier rows" % schedule)
		assert_gt(int(full["launched"]), 10, "%s: missiles flew at full fidelity" % schedule)
		var share_full: float = float(full["shot_down"]) / float(full["launched"])
		var share_tier: float = float(tier["shot_down"]) / maxf(float(tier["launched"]), 1.0)
		assert_lte(absf(share_tier - share_full), FIGHT_TOLERANCE * share_full,
				"%s: the share shot down within 15 %% (%.3f against %.3f)" % [schedule, share_tier, share_full])


# A cruiser keeping four missiles in the air at 12 invulnerable raiders spread round a hostile guard cruiser with its
# interceptors, 30 s: what was launched (after the first second) and shot down.
func _missile_fight(tier_on: bool, schedule: StringName) -> Dictionary:
	await _world(12, 0, tier_on, schedule)
	w.tier.seed_value = 5
	var cap: CapitalStandin = w.cruiser(Factions.EARTH_ALLIANCE, "CRUISER", FIGHT_AT)
	var guard: CapitalStandin = w.cruiser(Factions.RAIDERS, "GUARD", FIGHT_AT + Vector3(0.0, 300.0, -4000.0))
	cap.damageable.invulnerable = true
	guard.damageable.invulnerable = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i: int in 12:
		var off := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-1.0, 1.0)).normalized()
		var at: Vector3 = FIGHT_AT + Vector3(0.0, 0.0, -4000.0) + off * rng.randf_range(400.0, 3000.0)
		var c: Combatant = w.pool.acquire("RAIDER %d" % (i + 1), w.world.to_universe(at), Basis.IDENTITY, Vector3.ZERO, IdleBrain.new())
		c.damageable.invulnerable = true
	await _ticks(60)
	var tiered: bool = cap.is_tier_parked() and guard.is_tier_parked()
	w.standins.missile_target = 4
	var launched0: int = w.standins.missile_launches
	var down0: int = w.standins.missile_intercepts
	await _ticks(FIGHT_TICKS)
	var out: Dictionary = {"launched": w.standins.missile_launches - launched0, "shot_down": w.standins.missile_intercepts - down0,
			"tiered": tiered}
	w.standins.clear()
	return out
