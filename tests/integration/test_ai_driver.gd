extends GutTest
## AiPilotDriver (M2-T07, architecture §15.3, §15.8): a brain writes only a `PilotCommand` through
## `Combatant.apply_commands`, the very call the player's input goes through; the ship applies it in the same tick;
## the driver keeps the ship's targeting on the nearest hostile and builds a fresh perception every tick.

const SPEC_PATH: String = "res://assets/ships/raider_delta_v.tres"
const DT: float = 1.0 / 60.0

var world: WorldFrame
var projectiles: Node3D
var raider: Combatant
var player: Combatant


## A brain that records the perceptions it is shown and returns a scripted command.
class ScriptedBrain extends PilotBrain:
	var seen: Array[Perception] = []
	var command_for_tick: Callable = Callable()

	func think(p: Perception, _dt: float) -> PilotCommand:
		seen.append(p)
		var cmd := PilotCommand.new()
		if command_for_tick.is_valid():
			command_for_tick.call(cmd, seen.size())
		return cmd


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	raider = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS,
		ShipAssembly.OPT_DISPLAY_NAME: "RAIDER 1",
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(raider.ship, world.to_universe(Vector3.ZERO))
	player = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(player.ship, world.to_universe(Vector3(0.0, 0.0, -800.0)))


func _buoy(label: String, at: Vector3) -> NavBuoy:
	var buoy: NavBuoy = NavBuoy.create(label)
	world.spawn(buoy, world.to_universe(at))
	return buoy


func test_ai_ships_have_a_driver_that_runs_before_the_ship() -> void:
	assert_not_null(raider.driver)
	assert_eq(raider.driver.process_physics_priority, -10)
	assert_eq(raider.driver.get_parent(), raider.ship)
	assert_null(player.driver, "the player has none")


func test_a_driver_without_a_brain_does_nothing() -> void:
	raider.apply_commands(FlightCommand.new(), CombatCommand.new())
	var cmd := FlightCommand.new()
	cmd.main_left = 1.0
	cmd.main_right = 1.0
	raider.ship.set_flight_command(cmd)
	raider.driver.step(DT)
	assert_eq(raider.ship._flight.main_left, 1.0, "the ship keeps the command it had")


func test_the_brains_command_reaches_the_ship_and_the_cannon_through_apply_commands() -> void:
	var brain := ScriptedBrain.new()
	brain.command_for_tick = func(cmd: PilotCommand, _n: int) -> void:
		cmd.flight.main_left = 0.7
		cmd.flight.main_right = 0.7
		cmd.flight.rot = Vector3(0.1, -0.2, 0.0)
		cmd.combat.fire = true
	raider.driver.brain = brain
	raider.driver.step(DT)
	assert_eq(raider.ship._flight.main_left, 0.7)
	assert_eq(raider.ship._flight.rot, Vector3(0.1, -0.2, 0.0))
	assert_true(raider.ship._combat.fire)
	assert_true(raider.cannon._command.fire, "and the cannon")


func test_the_ship_applies_the_command_in_the_same_tick() -> void:
	var brain := ScriptedBrain.new()
	brain.command_for_tick = func(cmd: PilotCommand, _n: int) -> void:
		cmd.flight.main_left = 1.0
		cmd.flight.main_right = 1.0
	raider.driver.brain = brain
	raider.ship.assist_on = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(raider.ship.linear_velocity.length(), 0.01, "thrust within a couple of ticks")
	assert_gt(brain.seen.size(), 1, "the brain was asked every tick")


func test_the_perception_is_fresh_and_complete() -> void:
	raider.ship.linear_velocity = Vector3(3.0, 0.0, -20.0)
	raider.ship.global_transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(10.0, 2.0, 5.0))
	raider.damageable.hull.apply(15.0)
	var p: Perception = raider.driver.perceive()
	assert_eq(p.position, raider.ship.global_position)
	assert_eq(p.velocity, Vector3(3.0, 0.0, -20.0))
	assert_almost_eq(p.hull_fraction, 0.75, 1e-6)
	assert_eq(p.faction, Factions.RAIDERS)
	assert_eq(p.muzzle_speed_mps, 350.0)
	assert_eq(p.weapon_lifetime_s, 4.0)
	assert_almost_eq(p.capability.a_main, 25.0, 1e-3, "2 x 250 kN / 20 000 kg")
	assert_eq(p.frame_origin.system_id, &"local")
	assert_null(p.target, "nothing selected yet")


func test_waypoints_survive_a_rebase_through_the_perception() -> void:
	var waypoint := UniversePos.new(0.0, 0.0, -1000.0)
	var before: Vector3 = raider.driver.perceive().to_local(waypoint)
	world.rebase(Vector3(4000.0, 0.0, 0.0))
	var after: Vector3 = raider.driver.perceive().to_local(waypoint)
	assert_almost_eq(after - raider.driver.perceive().position, before - Vector3.ZERO, Vector3.ONE * 1e-3, "the same offset from the ship")


func test_the_driver_keeps_the_ships_targeting_on_the_nearest_hostile() -> void:
	_buoy("NAV NEAR", Vector3(0.0, 0.0, -100.0))  # nearer, but neutral
	var brain := ScriptedBrain.new()
	raider.driver.brain = brain
	raider.driver.step(DT)
	assert_eq(raider.ship.targeting.selected_name(), "PLAYER", "the hostile, not the nearer buoy")
	var p: Perception = brain.seen[0]
	assert_not_null(p.target)
	assert_true(p.target_hostile)
	assert_almost_eq(p.target.position, player.ship.global_position, Vector3.ONE * 1e-3)
	assert_almost_eq(p.target.velocity, Vector3.ZERO, Vector3.ONE * 1e-6)


func test_the_perceived_target_is_current_not_last_ticks() -> void:
	var brain := ScriptedBrain.new()
	raider.driver.brain = brain
	raider.driver.step(DT)
	player.ship.global_position += Vector3(0.0, 0.0, -50.0)  # moved since the targeting list was last gathered
	raider.driver.step(DT)
	assert_almost_eq(brain.seen[1].target.position, player.ship.global_position, Vector3.ONE * 1e-3)


func test_the_driver_retargets_when_the_selection_disappears() -> void:
	var brain := ScriptedBrain.new()
	raider.driver.brain = brain
	raider.driver.step(DT)
	assert_eq(raider.ship.targeting.selected_name(), "PLAYER")
	player.ship.visible = false  # the player's ship is gone from play
	raider.driver.step(DT)
	assert_false(raider.ship.targeting.system.has_selection())
	assert_null(brain.seen[1].target)
	player.ship.visible = true
	raider.driver.step(DT)
	assert_eq(raider.ship.targeting.selected_name(), "PLAYER", "and picks it up again")


func test_select_nearest_hostile_prefers_the_nearer_of_two_enemies() -> void:
	var second: Combatant = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "WINGMAN",
	})
	world.spawn(second.ship, world.to_universe(Vector3(0.0, 0.0, -300.0)))
	assert_true(raider.ship.targeting.select_nearest_hostile())
	assert_eq(raider.ship.targeting.selected_name(), "WINGMAN")


func test_select_nearest_hostile_clears_with_only_neutrals_around() -> void:
	player.ship.visible = false
	_buoy("NAV A", Vector3(0.0, 0.0, -100.0))
	raider.ship.targeting.refresh()
	assert_false(raider.ship.targeting.select_nearest_hostile())
	assert_false(raider.ship.targeting.system.has_selection())


func test_setting_a_brain_resets_it() -> void:
	var brain := AttackBrain.new(null, 3)
	brain.state = AttackBrain.State.EXTEND
	raider.driver.brain = brain
	assert_eq(brain.state, AttackBrain.State.APPROACH)


func test_an_idle_raider_coasts_at_constant_velocity() -> void:
	raider.driver.brain = IdleBrain.new()
	raider.ship.linear_velocity = Vector3(0.0, 0.0, -25.0)
	await get_tree().physics_frame
	var start: Vector3 = raider.ship.linear_velocity
	for i: int in 120:
		await get_tree().physics_frame
	assert_almost_eq(raider.ship.linear_velocity, start, Vector3.ONE * 1e-3, "constant velocity for 2 s")
	assert_lt(raider.ship.angular_velocity.length(), 1e-3)


func test_an_idle_raider_with_hold_comes_to_rest() -> void:
	raider.driver.brain = IdleBrain.new(true)
	raider.ship.linear_velocity = Vector3(0.0, 0.0, -25.0)
	for i: int in 600:
		await get_tree().physics_frame
	assert_lt(raider.ship.linear_velocity.length(), 0.6, "the brake stopped it")


# --- M3-T06: the perception wiring AiPilot relies on, the brain's target, the `ai` console ---------------------------


func test_the_perception_carries_the_friendly_fire_setting() -> void:
	var before: bool = bool(Settings.get_value(&"friendly_fire"))
	Settings.set_value(&"friendly_fire", false)
	assert_false(raider.driver.perceive().friendly_fire)
	Settings.set_value(&"friendly_fire", true)
	assert_true(raider.driver.perceive().friendly_fire, "read every tick from settings.friendly_fire")
	Settings.set_value(&"friendly_fire", before)


func test_the_perception_carries_the_last_hit_and_its_own_target_id() -> void:
	raider.driver.brain = IdleBrain.new()
	assert_eq(raider.driver.perceive().last_hit_s, -INF, "no hit yet")
	assert_eq(raider.driver.perceive().self_id, raider.targetable.get_instance_id())
	raider.damageable.apply_hit(HitInfo.new(raider.ship.get_instance_id(), player.ship.get_instance_id(),
			Factions.EARTH_ALLIANCE, 1.0, raider.ship.global_position))
	assert_eq(raider.driver.perceive().last_hit_s, SimClock.now(), "from Damageable.hit_taken")
	raider.driver.brain = IdleBrain.new()
	assert_eq(raider.driver.perceive().last_hit_s, -INF, "a new brain starts with no hit")


## A brain that wants a given target selected.
class WantsBrain extends PilotBrain:
	var want: int = 0
	var seen: Array[Perception] = []

	func think(p: Perception, _dt: float) -> PilotCommand:
		seen.append(p)
		wanted_target_id = want
		return PilotCommand.new()


func test_the_brains_wanted_target_is_selected_and_kept() -> void:
	var near: Combatant = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "WINGMAN",
	})
	world.spawn(near.ship, world.to_universe(Vector3(0.0, 0.0, -300.0)))
	var brain := WantsBrain.new()
	brain.want = player.targetable.get_instance_id()  # the farther one
	raider.driver.brain = brain
	raider.driver.step(DT)
	assert_eq(raider.ship.targeting.selected_name(), "PLAYER", "selected after the brain's think")
	for i: int in 90:  # past the 0.5 s nearest-hostile refresh
		raider.driver.step(DT)
	assert_eq(raider.ship.targeting.selected_name(), "PLAYER", "the nearest-hostile rule leaves it alone")
	assert_eq(brain.seen.back().target.id, brain.want, "and the brain perceives it as its target")
	brain.want = 0
	for i: int in 40:
		raider.driver.step(DT)
	assert_eq(raider.ship.targeting.selected_name(), "WINGMAN", "no preference: back to the nearest hostile")


func test_an_ai_pilot_attacks_the_hostile_through_the_driver() -> void:
	raider.driver.brain = BrainFactory.from_behaviour({"type": "ai", "profile": "raider"}, UniversePos.new(), 5)["brain"]
	ContactScan.invalidate()
	raider.driver.step(DT)
	var pilot: AiPilot = raider.driver.brain
	assert_eq(pilot.current.id, &"attack")
	assert_eq(raider.ship.targeting.selected_name(), "PLAYER")
	assert_true(pilot.has_desired_velocity, "the attack's wish reaches the avoidance filter")


func test_the_ai_console_lists_ships_and_describes_one() -> void:
	raider.driver.brain = BrainFactory.from_behaviour({"type": "ai", "profile": "raider"}, UniversePos.new(), 5)["brain"]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_true(registry.has_provider(&"ai"))
	assert_true(registry.has_command(&"ai"))
	assert_eq(registry.format_path("ai.ships"), "ai.ships = [RAIDER 1 attack (approach)]")
	assert_eq(registry.format_path("ai.by_behaviour"), "ai.by_behaviour = {attack: 1}")
	assert_gt(int(registry.read("ai.think_us")["value"]), 0, "the drivers' wall-clock time last tick")
	var results: Array[ConsoleResult] = registry.execute("ai raider 1")
	assert_true(results[0].ok, results[0].text())
	var text: String = results[0].text()
	assert_string_starts_with(text, "RAIDER 1: attack (approach)")
	assert_string_contains(text, "target PLAYER")
	assert_string_contains(text, "scores: retreat 0.00, evade 0.00, attack ")
	assert_string_contains(text, " *, idle 0.05")
	var unknown: ConsoleResult = registry.execute("ai RAIDER 9")[0]
	assert_false(unknown.ok)
	assert_string_contains(unknown.error, "no AI ship named 'RAIDER 9' (AI ships: RAIDER 1)")
	assert_false(registry.execute("ai")[0].ok, "a name is required")


func test_the_ai_console_goes_with_the_last_driver() -> void:
	assert_true(DebugConsole.registry.has_provider(&"ai"))
	var other: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS,
		ShipAssembly.OPT_DISPLAY_NAME: "RAIDER 2",
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(other.ship, world.to_universe(Vector3(500.0, 0.0, 0.0)))
	other.ship.get_parent().remove_child(other.ship)  # the newest driver (the owner) leaves first
	assert_true(DebugConsole.registry.has_provider(&"ai"), "handed to the driver still in the tree")
	other.ship.free()
	raider.ship.get_parent().remove_child(raider.ship)
	assert_false(DebugConsole.registry.has_provider(&"ai"), "gone with the last one")
	raider.ship.free()
