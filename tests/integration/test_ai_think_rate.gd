extends GutTest
## The AI think rate and nearest-k contacts (M4-T04, cycle 3; architecture §17.4). AI ships within `ai_think_near_m` of
## the player think every tick; farther ones (all of them with no player alive) think at `ai_think_far_hz` on staggered
## ticks and hold their last command between, while their physics still steps every tick. A ship scores, avoids and checks
## its fire lane against its nearest `ai_nearest_k` contacts plus its selected target and its latest attacker.
##
## Work counts, never milliseconds: thinks per tick against the near ships plus a third of the far ones, and the contacts
## handed to a brain against k. Real ships from `ShipAssembly`, real physics frames.

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const SETTINGS: Array[StringName] = [&"ai_think_rate", &"ai_think_near_m", &"ai_think_far_hz", &"ai_nearest_k"]

var world: WorldFrame
var projectiles: Node3D
var player: Combatant
var _saved: Dictionary = {}


## Counts its thinks and the time it was given; seeks a fixed velocity (or coasts), so ships stay where they are put.
class CountingBrain extends PilotBrain:
	var thinks: int = 0
	var dt_sum: float = 0.0
	var last_dt: float = 0.0
	var last_contacts: Array[Contact] = []
	var thrust: float = 0.0
	var keep: PackedInt64Array = PackedInt64Array()

	func think(p: Perception, dt: float) -> PilotCommand:
		thinks += 1
		dt_sum += dt
		last_dt = dt
		last_contacts = p.contacts
		var cmd := PilotCommand.new()
		cmd.flight.main_left = thrust
		cmd.flight.main_right = thrust
		return cmd

	func keep_ids() -> PackedInt64Array:
		return keep


## Records the work counts of every tick, after the drivers.
class Sampler extends Node:
	var near: PackedInt32Array = PackedInt32Array()
	var far: PackedInt32Array = PackedInt32Array()
	var contacts: PackedInt32Array = PackedInt32Array()

	func _init() -> void:
		process_physics_priority = 500

	func _physics_process(_delta: float) -> void:
		near.append(AiPilotDriver.thinks_near())
		far.append(AiPilotDriver.thinks_far())
		contacts.append(AiPilotDriver.contacts_max())


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
		Settings.reset(key)
	ContactScan.invalidate()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	player = ShipAssembly.build(load(STARFURY_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(player.ship, world.to_universe(Vector3.ZERO))


func after_each() -> void:
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	ContactScan.invalidate()


func _raider(display_name: String, at: Vector3, brain: PilotBrain, faction: StringName = Factions.RAIDERS) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(RAIDER_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: display_name,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(c.ship, world.to_universe(at))
	c.damageable.hull = HullHealth.new(1.0e6)
	c.driver.brain = brain
	return c


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# Six ships within 1 km of the player and 24 between 3 and 4.3 km out, all inside one another's 5 km.
func _near_and_far(near_brains: Array[CountingBrain], far_brains: Array[CountingBrain]) -> void:
	for i: int in 6:
		var brain := CountingBrain.new()
		near_brains.append(brain)
		_raider("NEAR %d" % i, Vector3(float(i) * 150.0 - 375.0, 0.0, -600.0), brain)
	for i: int in 24:
		var brain := CountingBrain.new()
		far_brains.append(brain)
		_raider("FAR %d" % i, Vector3(float(i) * 120.0 - 1380.0, 200.0, -3200.0), brain)


func _thinks(brains: Array[CountingBrain]) -> int:
	var total: int = 0
	for b: CountingBrain in brains:
		total += b.thinks
	return total


func test_far_ships_think_at_a_third_of_the_ticks_and_near_ones_every_tick() -> void:
	var near_brains: Array[CountingBrain] = []
	var far_brains: Array[CountingBrain] = []
	_near_and_far(near_brains, far_brains)
	await _ticks(3)  # every ship's first think, then the stagger
	var sampler := Sampler.new()
	add_child_autofree(sampler)
	await _ticks(60)
	var worst_far: int = 0
	var far_total: int = 0
	for i: int in sampler.far.size():
		assert_eq(sampler.near[i], 6, "every near ship thinks every tick (tick %d)" % i)
		worst_far = maxi(worst_far, sampler.far[i])
		far_total += sampler.far[i]
	gut.p("far thinks per tick: worst %d, mean %.2f of 24 ships" % [worst_far, float(far_total) / sampler.far.size()])
	assert_lte(worst_far, 24 / 3 + 1, "far ships: about a third of them per tick")


func test_contacts_scored_and_avoided_per_ship_stay_within_k() -> void:
	var brains: Array[CountingBrain] = []
	for i: int in 25:
		var brain := CountingBrain.new()
		brains.append(brain)
		_raider("RAIDER %d" % i, Vector3(float(i % 5) * 150.0, float(i / 5) * 150.0, -500.0), brain,
				Factions.RAIDERS if i % 2 == 0 else Factions.EARTH_ALLIANCE)
	var sampler := Sampler.new()
	add_child_autofree(sampler)
	await _ticks(10)
	var k: int = int(Settings.get_value(&"ai_nearest_k"))
	var worst: int = 0
	for n: int in sampler.contacts:
		worst = maxi(worst, n)
	gut.p("contacts per ship: worst %d with k = %d (25 ships and the player in sight)" % [worst, k])
	assert_lte(worst, k + 2, "the nearest k, plus the selected target and the latest attacker")


func test_a_near_ship_thinks_every_tick() -> void:
	var brain := CountingBrain.new()
	_raider("NEAR", Vector3(0.0, 0.0, -1500.0), brain)
	await _ticks(1)
	var before: int = brain.thinks
	await _ticks(30)
	assert_eq(brain.thinks - before, 30)
	assert_almost_eq(brain.dt_sum, (brain.thinks) / 60.0, 1e-9, "each think is given one tick")


func test_a_far_ship_holds_its_decision_and_its_physics_still_steps() -> void:
	var brain := CountingBrain.new()
	brain.thrust = 1.0
	var raider: Combatant = _raider("FAR", Vector3(0.0, 0.0, -3000.0), brain)
	await _ticks(2)  # its first think (a new pilot thinks at once); a frame's signal comes before its drivers run
	var before: int = brain.thinks
	var speeds: PackedFloat64Array = PackedFloat64Array()
	for i: int in 30:
		await _ticks(1)
		speeds.append(raider.ship.linear_velocity.length())
	assert_eq(brain.thinks - before, 10, "a far ship thinks every third tick at 20 Hz")
	assert_almost_eq(brain.last_dt, 3.0 / 60.0, 1e-9, "each think is given the time since the last")
	for i: int in range(1, speeds.size()):
		assert_gt(speeds[i], speeds[i - 1], "the held thrust still pushes every tick (tick %d)" % i)


func test_staggering_spreads_the_far_thinks_evenly() -> void:
	var far_brains: Array[CountingBrain] = []
	for i: int in 24:
		var brain := CountingBrain.new()
		far_brains.append(brain)
		_raider("FAR %d" % i, Vector3(float(i) * 120.0 - 1380.0, 0.0, -3500.0), brain)
	await _ticks(3)
	var sampler := Sampler.new()
	add_child_autofree(sampler)
	await _ticks(30)
	for i: int in sampler.far.size():
		assert_between(sampler.far[i], 7, 9, "tick %d carries about a third of the 24 far ships" % i)


func test_a_ship_crossing_the_line_changes_rate() -> void:
	var brain := CountingBrain.new()
	var raider: Combatant = _raider("CROSSER", Vector3(0.0, 0.0, -3000.0), brain)
	await _ticks(4)
	assert_false(raider.driver.near_player)
	raider.ship.global_position = Vector3(0.0, 0.0, -1500.0)
	await _ticks(1)
	var before: int = brain.thinks
	await _ticks(12)
	assert_true(raider.driver.near_player)
	assert_eq(brain.thinks - before, 12, "inside 2 km: every tick")
	raider.ship.global_position = Vector3(0.0, 0.0, -2600.0)
	await _ticks(1)
	before = brain.thinks
	await _ticks(12)
	assert_false(raider.driver.near_player)
	assert_eq(brain.thinks - before, 4, "outside again: every third tick")


func test_a_hit_wakes_a_far_ship_within_one_period() -> void:
	var brain := CountingBrain.new()
	var raider: Combatant = _raider("FAR", Vector3(0.0, 0.0, -3000.0), brain)
	await _ticks(7)
	# Find a tick right after its think, so it would wait two more ticks without the wake.
	var guard: int = 0
	var last: int = brain.thinks
	while guard < 6:
		await _ticks(1)
		guard += 1
		if brain.thinks != last:
			break
	var info := HitInfo.new(raider.ship.get_instance_id(), player.ship.get_instance_id(), Factions.EARTH_ALLIANCE, 1.0,
			raider.ship.global_position, Vector3.UP, 400.0, HitInfo.CAUSE_BOLT)
	raider.damageable.apply_hit(info)
	var at_hit: int = brain.thinks
	await _ticks(1)
	assert_eq(brain.thinks, at_hit + 1, "the next tick thinks, not two ticks later")


func test_the_selected_target_and_the_attacker_stay_in_the_nearest_k_set() -> void:
	Settings.set_value(&"ai_nearest_k", 8)
	var brain := CountingBrain.new()
	var own: Combatant = _raider("OWN", Vector3(0.0, 0.0, -500.0), brain)
	for i: int in 16:
		_raider("CROWD %d" % i, Vector3(float(i % 4) * 60.0 - 90.0, float(i / 4) * 60.0 - 90.0, -700.0), IdleBrain.new(),
				Factions.EARTH_ALLIANCE)
	var target: Combatant = _raider("FAR TARGET", Vector3(0.0, 0.0, -4400.0), IdleBrain.new(), Factions.EARTH_ALLIANCE)
	var attacker: Combatant = _raider("FAR SHOOTER", Vector3(0.0, 4000.0, -500.0), IdleBrain.new(), Factions.EARTH_ALLIANCE)
	brain.keep = PackedInt64Array([target.targetable.get_instance_id()])
	own.driver.last_attacker_id = attacker.targetable.get_instance_id()
	own.driver.last_hit_s = SimClock.now()
	ContactScan.invalidate()
	var p: Perception = own.driver.perceive()
	var ids: Array[int] = []
	for c: Contact in p.contacts:
		ids.append(c.id)
	assert_lte(p.contacts.size(), 8 + 2)
	assert_has(ids, target.targetable.get_instance_id(), "the brain's target is kept though 4.4 km out")
	assert_has(ids, attacker.targetable.get_instance_id(), "and the latest attacker")


func test_with_both_settings_off_every_ship_thinks_every_tick_against_every_contact() -> void:
	Settings.set_value(&"ai_think_rate", false)
	Settings.set_value(&"ai_nearest_k", 0)
	var near_brains: Array[CountingBrain] = []
	var far_brains: Array[CountingBrain] = []
	_near_and_far(near_brains, far_brains)
	await _ticks(2)
	var before: int = _thinks(far_brains)
	await _ticks(12)
	assert_eq(_thinks(far_brains) - before, 24 * 12, "far ships think every tick")
	assert_eq(far_brains[0].last_contacts.size(), 30, "and see every ship within 5 km: 29 AI ships and the player")


func test_with_no_player_alive_every_ship_thinks_at_the_far_rate() -> void:
	player.damageable.kill()
	var brain := CountingBrain.new()
	var raider: Combatant = _raider("NEAR A DEAD PLAYER", Vector3(0.0, 0.0, -300.0), brain)
	await _ticks(2)
	var before: int = brain.thinks
	await _ticks(12)
	assert_false(raider.driver.near_player)
	assert_eq(brain.thinks - before, 4, "no player: the far rate")
