extends GutTest
## M2-T02 (AC2): more than one ship can exist. The player and AI ships are built by `ShipAssembly` and commanded by
## `Combatant.apply_commands`; only the player's components register console entries, and freeing the others leaves them
## alone; `target_next` cycles hostiles first; inactive targetables are never candidates.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
const DT: float = 1.0 / 60.0

var world: WorldFrame
var projectiles: Node3D
var spec: ShipSpec
var player: Combatant
var near_raider: Combatant
var far_raider: Combatant
var buoy: NavBuoy


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	spec = load(SPEC_PATH) as ShipSpec
	player = _spawn(&"PLAYER", Factions.EARTH_ALLIANCE, Vector3.ZERO, true)
	near_raider = _spawn(&"RAIDER 1", Factions.RAIDERS, Vector3(0.0, 0.0, -1000.0), false)
	far_raider = _spawn(&"RAIDER 2", Factions.RAIDERS, Vector3(0.0, 0.0, -3000.0), false)
	buoy = NavBuoy.create("NAV TEST")
	world.spawn(buoy, world.to_universe(Vector3(0.0, 0.0, -500.0)))


func _spawn(label: StringName, faction: StringName, at: Vector3, is_player: bool) -> Combatant:
	var combatant: Combatant = ShipAssembly.build(spec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: String(label),
		ShipAssembly.OPT_CONSOLE_OWNER: is_player,
		ShipAssembly.OPT_FORCE_ASSIST: not is_player,
	})
	world.spawn(combatant.ship, world.to_universe(at))
	return combatant


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


func _free_ship(combatant: Combatant) -> void:
	combatant.ship.get_parent().remove_child(combatant.ship)
	combatant.ship.free()


# --- assembly --------------------------------------------------------------------------------------------------


func test_build_returns_a_combatant_with_every_component() -> void:
	assert_true(near_raider.ship.is_inside_tree())
	assert_eq(near_raider.faction, Factions.RAIDERS)
	assert_eq(near_raider.display_name, "RAIDER 1")
	assert_false(near_raider.is_player)
	assert_true(player.is_player, "console_owner implies is_player")
	assert_not_null(near_raider.cannon)
	assert_not_null(near_raider.thrusters)
	assert_not_null(near_raider.targetable)
	assert_eq(near_raider.targetable.get_parent(), near_raider.ship)
	assert_eq(near_raider.targetable.display_name, "RAIDER 1")
	assert_eq(near_raider.targetable.faction, Factions.RAIDERS)
	assert_eq(near_raider.ship.targeting.system.own_faction, Factions.RAIDERS)


func test_components_are_wired_when_the_ship_enters_the_tree() -> void:
	var layout: ThrusterLayout = near_raider.ship.get_layout()
	assert_true(layout.valid, "ship has a valid thruster layout (%s)" % GEN_ASSETS_HINT)
	assert_eq(near_raider.thrusters.glow_count(), layout.nozzle_count() + layout.rcs_nozzles.size())
	assert_eq(near_raider.cannon.gate.muzzle_count, near_raider.ship.get_muzzles().size())
	assert_eq(near_raider.cannon.weapon, spec.weapon, "the cannon fires the ship's weapon")
	assert_eq(near_raider.cannon.muzzle_speed_mps, spec.weapon.muzzle_speed_mps)
	assert_eq(near_raider.cannon.gate.interval_s, spec.weapon.shot_interval_s)


func test_the_starfury_defaults_reproduce_m1() -> void:
	assert_eq(spec.weapon.muzzle_speed_mps, 1000.0)
	assert_eq(near_raider.cannon.gate.muzzle_count, 2)
	assert_eq(near_raider.cannon.gate.interval_s, PulseCannonGate.ALTERNATING_INTERVAL_S)
	assert_eq(near_raider.cannon.gate.linked_interval_s(), PulseCannonGate.LINKED_INTERVAL_S)
	assert_eq(near_raider.cannon.gate.capacitor.capacity, WeaponCapacitor.DEFAULT_CAPACITY)


func test_the_default_engine_glow_uses_the_shared_materials_and_another_colour_gets_its_own() -> void:
	assert_null(player.thrusters.cone(0).material_override, "the Starfury's blue-white is the shared material")
	var red := load(SPEC_PATH).duplicate() as ShipSpec
	red.engine_glow_color = Color(2.0, 0.5, 0.3, 1.0)
	var raider: Combatant = ShipAssembly.build(red, world, projectiles, {})
	world.spawn(raider.ship, world.to_universe(Vector3(500.0, 0.0, 0.0)))
	var cone_material := raider.thrusters.cone(0).material_override as StandardMaterial3D
	assert_not_null(cone_material, "its own copy")
	assert_eq(cone_material.albedo_color, red.engine_glow_color)
	var core_material := raider.thrusters.core(0).material_override as StandardMaterial3D
	assert_eq(core_material.emission, red.engine_glow_color)
	assert_eq(raider.thrusters.cone(1).material_override, cone_material, "one copy per ship, shared by its plumes")
	assert_null(player.thrusters.cone(0).material_override, "the Starfury is untouched")


func test_apply_commands_reaches_the_ship_and_the_cannon() -> void:
	var flight := FlightCommand.new()
	flight.main_left = 1.0
	flight.main_right = 1.0
	var combat := CombatCommand.new()
	combat.fire = true
	near_raider.apply_commands(flight, combat)
	for i: int in 30:
		await get_tree().physics_frame
	assert_true(near_raider.ship.linear_velocity.length() > 0.5, "the mains pushed the raider")
	assert_true(projectiles.get_child_count() > 0, "and the cannon fired")
	assert_eq(player.ship.linear_velocity, Vector3.ZERO, "the player was not commanded")


func test_force_assist_cannot_be_switched_off() -> void:
	assert_true(near_raider.ship.assist_on)
	near_raider.ship.set_assist(false)
	assert_true(near_raider.ship.assist_on, "refused")
	var flight := FlightCommand.new()
	flight.toggle_assist = true
	near_raider.apply_commands(flight, CombatCommand.new())
	await get_tree().physics_frame
	assert_true(near_raider.ship.assist_on, "the toggle edge is ignored too")
	player.ship.set_assist(false)
	assert_false(player.ship.assist_on, "the player may")


# --- console (D27) ---------------------------------------------------------------------------------------------


func test_exactly_one_set_of_player_providers_and_commands() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	for provider: StringName in [&"ship", &"targeting", &"weapons"]:
		assert_true(registry.has_provider(provider), "%s provider" % provider)
	assert_true(registry.has_command(&"assist"))
	assert_eq(registry.provider_names().count(&"ship"), 1)
	assert_eq(registry.provider_names().count(&"targeting"), 1)
	assert_eq(registry.provider_names().count(&"weapons"), 1)
	player.ship.linear_velocity = Vector3(3.0, 0.0, -4.0)
	near_raider.ship.linear_velocity = Vector3(100.0, 0.0, 0.0)
	assert_eq(registry.format_path("ship.speed"), "ship.speed = 5.00 m/s", "the player's, not a raider's")


func test_the_player_owns_the_weapons_provider() -> void:
	player.cannon.gate.cycle_mode()
	assert_eq(DebugConsole.registry.format_path("weapons.mode"), "weapons.mode = linked")
	assert_eq(near_raider.cannon.gate.mode, PulseCannonGate.Mode.ALTERNATING)
	_console("set weapons.mode alternating")
	assert_eq(player.cannon.gate.mode, PulseCannonGate.Mode.ALTERNATING)
	assert_eq(far_raider.cannon.gate.mode, PulseCannonGate.Mode.ALTERNATING)


func test_freeing_the_other_ships_leaves_the_players_entries_intact() -> void:
	_free_ship(near_raider)
	_free_ship(far_raider)
	var registry: ConsoleRegistry = DebugConsole.registry
	for provider: StringName in [&"ship", &"targeting", &"weapons"]:
		assert_true(registry.has_provider(provider), "%s survives" % provider)
	assert_true(registry.has_command(&"assist"), "assist survives")
	player.ship.linear_velocity = Vector3(0.0, 6.0, 8.0)
	assert_eq(registry.format_path("ship.speed"), "ship.speed = 10.00 m/s")
	assert_true(_console("assist off").ok)
	assert_false(player.ship.assist_on)


func test_freeing_the_player_removes_its_entries() -> void:
	_free_ship(player)
	for provider: StringName in [&"ship", &"targeting", &"weapons"]:
		assert_false(DebugConsole.registry.has_provider(provider), "%s left with the player" % provider)
	assert_false(DebugConsole.registry.has_command(&"assist"))


# --- targeting -------------------------------------------------------------------------------------------------


func _next(combatant: Combatant) -> void:
	var cmd := CombatCommand.new()
	cmd.target_next = true
	combatant.ship.targeting.apply(cmd)


func test_target_next_selects_hostiles_first_nearest_first_then_neutrals() -> void:
	var targeting: TargetingController = player.ship.targeting
	var order: PackedStringArray = PackedStringArray()
	for i: int in 4:
		_next(player)
		order.append(targeting.selected_name())
	assert_eq(order, PackedStringArray(["RAIDER 1", "RAIDER 2", "NAV TEST", "RAIDER 1"]),
			"the buoy is nearest, but hostiles come first; then it wraps")


func test_a_ship_never_targets_itself_and_raiders_target_the_player() -> void:
	var candidates: Array[TargetInfo] = near_raider.ship.targeting.candidates()
	var names: PackedStringArray = PackedStringArray()
	for info: TargetInfo in candidates:
		names.append(info.display_name)
	assert_false(names.has("RAIDER 1"), "not itself")
	assert_true(names.has("PLAYER"), "the player is a Targetable now")
	_next(near_raider)
	assert_eq(near_raider.ship.targeting.selected_name(), "PLAYER", "the hostile before the nearer buoy")


func test_the_player_does_not_list_itself() -> void:
	player.ship.targeting.refresh()  # the player was built first; its list has not seen the others yet
	var candidates: Array[TargetInfo] = player.ship.targeting.candidates()
	assert_eq(candidates.size(), 3, "two raiders and the buoy")
	for info: TargetInfo in candidates:
		assert_ne(info.display_name, "PLAYER")


func test_an_inactive_targetable_is_never_a_candidate() -> void:
	near_raider.ship.visible = false
	assert_false(near_raider.targetable.is_active())
	player.ship.targeting.refresh()
	var names: PackedStringArray = PackedStringArray()
	for info: TargetInfo in player.ship.targeting.candidates():
		names.append(info.display_name)
	assert_false(names.has("RAIDER 1"))
	_next(player)
	assert_eq(player.ship.targeting.selected_name(), "RAIDER 2")


func test_a_selection_that_turns_inactive_clears_and_says_so() -> void:
	_next(player)
	assert_eq(player.ship.targeting.selected_name(), "RAIDER 1")
	var seen: Array[int] = []
	player.ship.targeting.target_changed.connect(func(id: int) -> void: seen.append(id))
	near_raider.ship.visible = false
	player.ship.targeting.refresh()
	assert_false(player.ship.targeting.system.has_selection())
	assert_eq(seen, [TargetingSystem.NO_TARGET])
	near_raider.ship.visible = true
	player.ship.targeting.refresh()
	assert_false(player.ship.targeting.system.has_selection(), "it does not come back by itself")
	_next(player)
	assert_eq(player.ship.targeting.selected_name(), "RAIDER 1")


func test_a_parent_that_cannot_process_makes_a_targetable_inactive() -> void:
	assert_true(far_raider.targetable.is_active())
	far_raider.ship.process_mode = Node.PROCESS_MODE_DISABLED
	assert_false(far_raider.targetable.is_active(), "a parked pool ship")
	far_raider.ship.process_mode = Node.PROCESS_MODE_INHERIT
	assert_true(far_raider.targetable.is_active())


func test_a_targetable_outside_the_tree_is_inactive() -> void:
	var loose := Targetable.new()
	assert_false(loose.is_active())
	loose.free()
