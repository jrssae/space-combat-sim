extends GutTest
## FORM ON ME fires while keeping formation; FORM UP, HOLD FIRE never shoots (M8-T13; maintainer's play-test, 2026-11-21), on the
## real main scene: two wingmen in their slots and a hostile off to the player's side, within the data's engage radius
## (data/wings/flights.json): under FORM ON ME they turn their guns on it and fire, their slots never slipping past the leash;
## under FORM UP, HOLD FIRE not one shot; a hostile beyond the radius is not chased.

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const WATCH_S: float = 12.0

var main: Main
var wing: Wing
var shots: Array[int] = [0]


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	shots = [0]


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 1
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	main.combatant.damageable.invulnerable = true
	wing = main.wings.player_wing()


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _slot_of(c: Combatant) -> Vector3:
	var basis: Basis = main.ship.global_basis
	return Formation.slot_point(main.ship.global_position, -basis.z, basis.y, wing.slot_offset(wing.slot_of(c)))


func _wingmen(order: String) -> Array[Combatant]:
	var out: Array[Combatant] = []
	var basis: Basis = main.ship.global_basis
	for slot: int in [1, 2]:
		var ally: Combatant = ShipAssembly.build(load(STARFURY_SPEC) as ShipSpec, main.world, main.projectiles, {
			ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
			ShipAssembly.OPT_DISPLAY_NAME: wing.callsign(slot),
			ShipAssembly.OPT_FORCE_ASSIST: true,
			ShipAssembly.OPT_AI: true,
		})
		var at: Vector3 = Formation.slot_point(main.ship.global_position, -basis.z, basis.y, wing.slot_offset(slot))
		main.world.spawn(ally.ship, main.world.to_universe(at), basis)
		ally.ship.linear_velocity = main.ship.linear_velocity
		ally.driver.brain = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury"}, UniversePos.new(),
				hash(wing.callsign(slot)))["brain"] as AiPilot
		ally.ship.tier_exempt = true
		assert_eq(main.wings.add_member(wing, ally), slot)
		ally.cannon.shot_fired.connect(func(_muzzle: int, _at: Vector3) -> void: shots[0] += 1)
		out.append(ally)
	assert_true(DebugConsole.registry.execute("wing order %s" % order)[0].ok)
	await _ticks(20)
	return out


# A raider sitting `side_m` off the player's right, doing nothing (so the fight is the wingmen's to start).
func _hostile(side_m: float) -> Combatant:
	var at: Vector3 = main.ship.global_position + main.ship.global_basis.x * side_m
	var made: Dictionary = BrainFactory.from_behaviour({"type": "idle"}, main.world.to_universe(at), 3)
	var raider: Combatant = main.ships.acquire("BANDIT", main.world.to_universe(at), main.ship.global_basis,
			main.world.rest_velocity(), made["brain"] as PilotBrain, &"raider_fighter")
	assert_not_null(raider)
	raider.driver.in_passage = true  # held still: a target, not a fight
	raider.damageable.invulnerable = true
	raider.ship.tier_exempt = true
	return raider


# Watches `WATCH_S` seconds: the farthest any wingman's slot slipped.
func _watch(wingmen: Array[Combatant]) -> float:
	var slipped: float = 0.0
	for i: int in roundi(WATCH_S * 60.0):
		await get_tree().physics_frame
		for c: Combatant in wingmen:
			slipped = maxf(slipped, c.ship.global_position.distance_to(_slot_of(c)))
	return slipped


func test_under_form_on_me_wingmen_fire_at_a_hostile_beside_the_player_and_keep_their_slots() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _wingmen("form")
	_hostile(700.0)
	var slipped: float = await _watch(wingmen)
	assert_gt(shots[0], 0, "they fired (%d shots)" % shots[0])
	assert_lt(slipped, FlightRules.shared().form_leash_m + 50.0, "their slots slipped at most the leash (%.0f m)" % slipped)
	gut.p("form on me: %d shots, slots slipped at most %.0f m" % [shots[0], slipped])


func test_under_form_up_hold_fire_the_same_wingmen_never_shoot() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _wingmen("form_hold")
	_hostile(700.0)
	var slipped: float = await _watch(wingmen)
	assert_eq(shots[0], 0, "not one shot")
	assert_lt(slipped, 150.0, "and they stayed in formation (%.0f m)" % slipped)


func test_a_hostile_beyond_the_radius_is_not_chased() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _wingmen("form")
	_hostile(FlightRules.shared().form_engage_m + 900.0)
	var slipped: float = await _watch(wingmen)
	assert_eq(shots[0], 0, "out of reach and beyond the radius: no shot")
	assert_lt(slipped, 150.0, "nobody left the formation for it (%.0f m)" % slipped)
