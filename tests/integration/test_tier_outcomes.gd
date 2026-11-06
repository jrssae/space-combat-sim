extends GutTest
## The low-attention tier's fairness (M4-T22, architecture §17.14): a fight out of view wins or loses at the rate one in view
## does. The to-hit roll against a seeded full-fidelity duel (the same shots, 1 000 of them) within 10 %; a 12 against 12
## fight run 30 s in the tier and at full fidelity, seeds 1 to 3: hits within 15 %, the same side winning, the mean hull loss
## within 15 %; a cruiser with 8 turrets against 12 fighters, 30 s, in the tier and at full fidelity: the fighters' hull loss
## within 15 %. Real pooled ships, drivers, Jolt, the hit resolver and the core, on both of T24's schedules (Q54). Skips,
## saying why, when the library is not built.

const SCHEDULES: Array[StringName] = [&"threaded", &"inline"]
const SEEDS: Array[int] = [1, 2, 3]
const FIGHT_TICKS: int = 1800
const DUEL_SHOTS: int = 1000
const DUEL_PAIRS: int = 12
const DUEL_MAX_TICKS: int = 9000
const DUEL_TOLERANCE: float = 0.10
const FIGHT_TOLERANCE: float = 0.15
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
	TierWorld.use_native(0.0)
	Settings.set_value(&"tier_hz", 20.0)
	Settings.set_value(&"tier_brain_hz", 4.0)
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


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no tier to compare")
	return true


func _world(raiders: int, allies: int, tier_on: bool, schedule: StringName) -> void:
	if w != null:
		w.free_world()
		await get_tree().physics_frame
	Settings.set_value(&"sim_step", schedule)
	Settings.set_value(&"tier_radius_m", TIER_RADIUS_M if tier_on else 0.0)
	Factions.reset()
	ContactScan.invalidate()
	SimClock.reset()
	w = TierWorld.new()
	w.build(self, raiders, allies)
	await get_tree().physics_frame


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# --- the duel: the roll against full fidelity, shot for shot ---------------------------------------------------------------


func test_the_to_hit_roll_matches_a_seeded_full_fidelity_duel_within_ten_percent() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		await _world(DUEL_PAIRS, DUEL_PAIRS, false, schedule)
		# Pairs of a raider and an allied Starfury 800 m apart, each pair 40 km from the next (out of each other's sensors).
		var shots: Array = []
		var pairs: Array = []
		for i: int in DUEL_PAIRS:
			var centre := Vector3(cos(TAU * i / DUEL_PAIRS), 0.0, sin(TAU * i / DUEL_PAIRS)) * 60000.0
			var raider: Combatant = w.fighter(ShipPool.DEFAULT_TYPE, "RAIDER %d" % i, centre, 100 + i)
			var ally: Combatant = w.fighter(ShipPool.ALLY_TYPE, "ALPHA %d" % (i + 2), centre + Vector3(0.0, 0.0, -800.0),
					200 + i, Basis(Vector3.UP, PI))
			raider.damageable.invulnerable = true
			ally.damageable.invulnerable = true
			pairs.append([raider, ally])
			raider.cannon.shot_fired.connect(_on_duel_shot.bind(raider, ally, shots))
			ally.cannon.shot_fired.connect(_on_duel_shot.bind(ally, raider, shots))
		var ticks: int = 0
		while shots.size() < DUEL_SHOTS and ticks < DUEL_MAX_TICKS:
			await get_tree().physics_frame
			ticks += 1
		await _ticks(300)  # the last bolts land (a raider's plasma takes up to 4 s)
		assert_gte(shots.size(), DUEL_SHOTS, "%s: %d shots fired in %d ticks" % [schedule, shots.size(), ticks])
		var landed: int = 0
		for h: Array in w.hits:
			landed += 1
		var used: Array = shots.slice(0, shots.size())
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var rolled: int = 0
		var expected: float = 0.0
		for s: Array in used:
			var chance: float = float(w.sim.core.tier_hit_chance(s[0], s[1], s[2], s[3], s[4], s[5], s[6]))
			expected += chance
			if rng.randf() < chance:
				rolled += 1
		var rate_full: float = float(landed) / float(used.size())
		var rate_tier: float = float(rolled) / float(used.size())
		gut.p("%s duel: %d shots, full fidelity %d hits (%.3f), the roll %d (%.3f, expected %.1f)" % [schedule, used.size(),
				landed, rate_full, rolled, rate_tier, expected])
		assert_lte(absf(rate_tier - rate_full), DUEL_TOLERANCE * rate_full,
				"%s: the roll's to-hit rate within 10 %% of full fidelity's (%.3f against %.3f)" % [schedule, rate_tier, rate_full])


# Each shot's geometry as the tier's roll takes it: the range, the target's radius, the bolt's hit radius and speed, the
# shooter's aim error and miss gate, the bolt's reach.
func _on_duel_shot(_muzzle: int, at: Vector3, shooter: Combatant, target: Combatant, shots: Array) -> void:
	var pilot := shooter.driver.brain as AiPilot
	if pilot == null or pilot.profile == null:
		return
	var weapon: WeaponSpec = shooter.cannon.weapon
	shots.append([at.distance_to(target.ship.global_position), target.damageable.bounding_radius, weapon.hit_radius_m,
			weapon.muzzle_speed_mps, deg_to_rad(pilot.profile.aim_error_deg), pilot.profile.tactics.fire_miss_m,
			weapon.muzzle_speed_mps * weapon.lifetime_s])


# --- 12 against 12 ----------------------------------------------------------------------------------------------------------


func test_a_twelve_against_twelve_fight_in_the_tier_ends_as_it_does_at_full_fidelity() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		for seed_value: int in SEEDS:
			var full: Dictionary = await _fight(seed_value, false, schedule)
			var tier: Dictionary = await _fight(seed_value, true, schedule)
			var label: String = "%s seed %d" % [schedule, seed_value]
			gut.p("%s: full fidelity %s; the tier %s" % [label, full, tier])
			assert_gt(int(tier["tier_rows"]), 20, "%s: the tier fight flew in the tier (%d rows)" % [label, int(tier["tier_rows"])])
			assert_eq(int(full["tier_rows"]), 0, "%s: the full-fidelity fight did not" % label)
			assert_gt(int(full["hits"]), 0, "%s: the full-fidelity fight landed hits" % label)
			assert_lte(absf(float(tier["hits"]) - float(full["hits"])), FIGHT_TOLERANCE * float(full["hits"]),
					"%s: hits within 15 %% (%d against %d)" % [label, int(tier["hits"]), int(full["hits"])])
			assert_eq(tier["winner"], full["winner"], "%s: the same side wins (%s against %s)" % [label, tier["winner"], full["winner"]])
			assert_lte(absf(float(tier["loss"]) - float(full["loss"])), FIGHT_TOLERANCE * float(full["loss"]),
					"%s: the mean hull loss within 15 %% (%.3f against %.3f)" % [label, float(tier["loss"]), float(full["loss"])])


## One 30 s fight of 12 allied Starfuries against 12 raiders at `FIGHT_AT`, seeded, in the tier or not. Returns the bolt hits,
## the winner (the side with more hull left), the mean hull loss over all 24 and the tier rows seen at the end of the first second.
func _fight(seed_value: int, tier_on: bool, schedule: StringName) -> Dictionary:
	await _world(12, 12, tier_on, schedule)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var allies: Array[Combatant] = []
	var raiders: Array[Combatant] = []
	for i: int in 12:
		var jitter := Vector3(rng.randf_range(-150.0, 150.0), rng.randf_range(-100.0, 100.0), rng.randf_range(-150.0, 150.0))
		var lane := Vector3(float(i % 4) * 150.0 - 225.0, float(i / 4) * 120.0 - 120.0, 0.0)
		allies.append(w.fighter(ShipPool.ALLY_TYPE, "ALPHA %d" % (i + 2), FIGHT_AT + lane + jitter + Vector3(0.0, 0.0, 900.0),
				seed_value * 100 + i, Basis(Vector3.UP, 0.0), Vector3(0.0, 0.0, -40.0)))
		raiders.append(w.fighter(ShipPool.DEFAULT_TYPE, "RAIDER %d" % (i + 1), FIGHT_AT + lane - jitter - Vector3(0.0, 0.0, 900.0),
				seed_value * 100 + 50 + i, Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 40.0)))
	await _ticks(60)
	var tier_rows: int = int(w.sim.core.tier_count())
	await _ticks(FIGHT_TICKS - 60)
	var hits: int = w.hits.size()
	var ally_left: float = TierWorld.hull_left(allies)
	var raider_left: float = TierWorld.hull_left(raiders)
	var everyone: Array[Combatant] = []
	everyone.append_array(allies)
	everyone.append_array(raiders)
	return {"hits": hits, "winner": "allies" if ally_left >= raider_left else "raiders", "loss": TierWorld.mean_hull_loss(everyone),
			"ally_left": snappedf(ally_left, 0.01), "raider_left": snappedf(raider_left, 0.01), "tier_rows": tier_rows}


# --- a cruiser against 12 fighters -------------------------------------------------------------------------------------------


func test_a_cruiser_against_twelve_fighters_in_the_tier_hurts_them_as_at_full_fidelity() -> void:
	if _skipped():
		return
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
	for i: int in 12:
		var at: Vector3 = FIGHT_AT + Vector3(rng.randf_range(-600.0, 600.0), rng.randf_range(-300.0, 300.0), -2500.0 - rng.randf_range(0.0, 600.0))
		raiders.append(w.fighter(ShipPool.DEFAULT_TYPE, "RAIDER %d" % (i + 1), at, 300 + i, Basis.IDENTITY, Vector3(0.0, 0.0, 40.0)))
	await _ticks(60)
	var capital_tiered: bool = cap.is_tier_parked()
	await _ticks(FIGHT_TICKS - 60)
	var loss: float = TierWorld.mean_hull_loss(raiders)
	w.standins.clear()
	return {"loss": loss, "hits": w.hits.size(), "capital_tiered": capital_tiered}
