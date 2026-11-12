extends TestSteps
## Damage and god mode (M2-T03, AC8, architecture §15.4): ships built by `ShipAssembly` carry a `Damageable` with the
## hull from `ShipSpec.hull_max`; a raider's bolt that reaches the player emits `hit_taken` and an impact flash, and
## removes hull points unless `god on`; raiders always take damage; `damage` and `heal` work from the console.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const DT: float = 1.0 / 60.0
const BOLT_SPEED: float = 400.0

var world: WorldFrame
var projectiles: Node3D
var resolver: HitResolver
var player: Combatant
var raider: Combatant
var taken: Array[HitInfo] = []
var damaged_log: Array[float] = []
var destroyed_count: int = 0


func before_each() -> void:
	DebugConsole.flags.invulnerable = false
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	resolver = HitResolver.new()
	add_child_autofree(resolver)
	resolver.set_physics_process(false)
	var spec := load(SPEC_PATH) as ShipSpec
	player = _build(spec, Factions.EARTH_ALLIANCE, Vector3.ZERO, true)
	raider = _build(spec, Factions.RAIDERS, Vector3(0.0, 0.0, -200.0), false)
	taken.clear()
	damaged_log.clear()
	destroyed_count = 0
	player.damageable.hit_taken.connect(func(info: HitInfo) -> void: taken.append(info))
	player.damageable.damaged.connect(func(_info: HitInfo, applied: float) -> void: damaged_log.append(applied))
	player.damageable.destroyed.connect(func(_info: HitInfo) -> void: destroyed_count += 1)


func after_each() -> void:
	DebugConsole.flags.invulnerable = false


func _build(spec: ShipSpec, faction: StringName, at: Vector3, is_player: bool) -> Combatant:
	var combatant: Combatant = ShipAssembly.build(spec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER" if is_player else "RAIDER",
		ShipAssembly.OPT_CONSOLE_OWNER: is_player,
	})
	world.spawn(combatant.ship, world.to_universe(at))
	return combatant


## A bolt from `shooter` (its faction and id) flying at `velocity` from `at`.
func _bolt(shooter: Combatant, at: Vector3, velocity: Vector3) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	bolt.configure(shooter.ship.spec.weapon)
	bolt.shooter_id = shooter.ship.get_instance_id()
	bolt.faction = shooter.faction
	bolt.launch(at, velocity, SimClock.now())
	bolt.set_physics_process(false)
	return bolt


func _fly(ticks: int) -> void:
	for i: int in ticks:
		for node: Node in projectiles.get_children():
			var bolt := node as Projectile
			if bolt != null and not bolt.is_spent():
				bolt._physics_process(DT)
		resolver.resolve(DT)


## A raider bolt straight at the player's fuselage.
func _shoot_player() -> void:
	_bolt(raider, Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, BOLT_SPEED))
	_fly(60)


# --- the hull ------------------------------------------------------------------------------------------------


func test_ships_carry_a_damageable_with_the_spec_hull_and_their_hit_volumes() -> void:
	var spec := load(SPEC_PATH) as ShipSpec
	for combatant: Combatant in [player, raider]:
		var damageable: Damageable = combatant.damageable
		assert_not_null(damageable)
		assert_eq(damageable.hull.max_hp, spec.hull_max)
		assert_eq(damageable.hull.hp, spec.hull_max)
		assert_eq(damageable.faction, combatant.faction)
		assert_eq(damageable.shapes.size(), combatant.ship.get_hardpoints().collision.size(), "one volume per collision primitive")
		assert_true(damageable.bounding_radius > 3.0, "holds the whole hull")
		assert_true(damageable.is_in_group(Damageable.GROUP))
		assert_true(damageable.is_active())
	assert_true(player.damageable.respects_god_mode, "the player's hull")
	assert_false(raider.damageable.respects_god_mode)
	assert_eq(Damageable.of(player.ship), player.damageable)


func test_a_raider_bolt_hurts_the_player_and_leaves_a_flash() -> void:
	_shoot_player()
	assert_eq(taken.size(), 1)
	assert_eq(damaged_log, [10.0])
	assert_eq(player.damageable.hull.hp, 290.0)
	var flashes: Array[ImpactFlash] = []
	for child: Node in player.ship.get_children():
		if child is ImpactFlash:
			flashes.append(child as ImpactFlash)
	assert_eq(flashes.size(), 1, "an impact flash rides on the hit ship")
	assert_eq(flashes[0].get_child_count(true), 0, "one node: the sparks are the particle pool's (M4-T36)")
	assert_eq(taken[0].applied, 10.0)


func test_a_starfury_bolt_hurts_a_raider_and_the_player_does_not_shoot_himself() -> void:
	_bolt(player, Vector3(0.0, 0.0, -50.0), Vector3(0.0, 0.0, -BOLT_SPEED))
	_bolt(player, Vector3(0.0, 0.0, 100.0), Vector3(0.0, 0.0, BOLT_SPEED))  # starts behind the player's own hull
	_fly(120)
	assert_eq(raider.damageable.hull.hp, 290.0, "the raider took the bolt")
	assert_eq(player.damageable.hull.hp, 300.0, "the shooter's own hull and its allies are never hit")


func test_destroyed_is_emitted_once_even_with_more_hits_in_the_same_tick() -> void:
	for i: int in 40:
		_bolt(raider, Vector3(0.1 * float(i % 5), 0.1 * float(i / 5), -100.0 - 0.5 * float(i)), Vector3(0.0, 0.0, BOLT_SPEED))
	_fly(120)
	assert_true(player.damageable.hull.destroyed)
	assert_eq(player.damageable.hull.hp, 0.0)
	assert_eq(destroyed_count, 1, "once")
	assert_eq(damaged_log.size(), 30, "30 hits of 10 emptied a 300 hull; later bolts found a dead ship")
	assert_false(player.damageable.is_active(), "a destroyed hull cannot be hit again")


func test_a_dead_hull_hit_while_invulnerable_does_not_die_again() -> void:
	# Code review 2026-11-12: a lethal hit, then god mode, then more hits must not announce the death again.
	var info := HitInfo.new(player.ship.get_instance_id(), raider.ship.get_instance_id(), Factions.RAIDERS, 10000.0,
			player.ship.global_position, Vector3.UP, 1000.0)
	player.damageable.apply_hit(info)
	assert_eq(destroyed_count, 1)
	player.damageable.invulnerable = true
	player.damageable.apply_hit(info)
	player.damageable.apply_hit(info)
	assert_eq(destroyed_count, 1, "one death, however many hits follow")
	player.damageable.invulnerable = false


# --- god mode (AC8) ------------------------------------------------------------------------------------------


func test_god_mode_blocks_the_damage_but_not_the_hit() -> void:
	_console("god on")
	assert_true(DebugConsole.flags.invulnerable)
	_shoot_player()
	assert_eq(taken.size(), 1, "hit_taken still fires")
	assert_eq(damaged_log.size(), 0, "damaged does not")
	assert_eq(player.damageable.hull.hp, 300.0)
	var flashes: int = 0
	for child: Node in player.ship.get_children():
		flashes += 1 if child is ImpactFlash else 0
	assert_eq(flashes, 1, "the flash still plays")
	assert_eq(taken[0].applied, 0.0)


func test_god_off_restores_the_damage() -> void:
	_console("god on")
	_shoot_player()
	_console("god off")
	_shoot_player()
	assert_eq(player.damageable.hull.hp, 290.0)


func test_the_player_cannot_die_under_god_mode() -> void:
	_console("god on")
	_console("damage 100000")
	assert_false(player.damageable.hull.destroyed)
	assert_eq(destroyed_count, 0)
	assert_eq(player.damageable.hull.hp, 300.0)


func test_raiders_always_take_damage() -> void:
	_console("god on")
	_bolt(player, Vector3(0.0, 0.0, -50.0), Vector3(0.0, 0.0, -BOLT_SPEED))
	_fly(120)
	assert_eq(raider.damageable.hull.hp, 290.0)


# --- console -----------------------------------------------------------------------------------------------------


func test_hull_provider_keys() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_true(registry.has_provider(&"hull"))
	assert_eq(registry.format_path("hull.max_hp"), "hull.max_hp = 300.00")
	assert_eq(registry.format_path("hull.fraction"), "hull.fraction = 1.00")
	assert_eq(registry.format_path("hull.destroyed"), "hull.destroyed = false")
	assert_eq(registry.format_path("hull.invulnerable"), "hull.invulnerable = false")
	_console("set hull.invulnerable on")
	assert_true(DebugConsole.flags.invulnerable, "mirrors debug.invulnerable")
	assert_eq(registry.format_path("debug.invulnerable"), "debug.invulnerable = true")


func test_only_the_players_hull_is_in_the_console() -> void:
	assert_eq(DebugConsole.registry.provider_names().count(&"hull"), 1)
	player.ship.targeting.refresh()
	assert_eq(DebugConsole.registry.format_path("hull.hp"), "hull.hp = 300.00")
	raider.damageable.hull.apply(100.0)
	assert_eq(DebugConsole.registry.format_path("hull.hp"), "hull.hp = 300.00", "the raider's hull is not `hull`")


func test_damage_and_heal_on_the_selected_target() -> void:
	player.ship.targeting.refresh()
	var cmd := CombatCommand.new()
	cmd.target_next = true
	player.ship.targeting.apply(cmd)
	assert_eq(player.ship.targeting.selected_name(), "RAIDER")
	assert_true(_console("damage 40 target").ok)
	assert_eq(raider.damageable.hull.hp, 260.0)
	assert_eq(player.damageable.hull.hp, 300.0)
	assert_true(_console("heal target").ok)
	assert_eq(raider.damageable.hull.hp, 300.0)


func test_damage_to_a_missing_target_is_an_error_not_a_crash() -> void:
	var result: ConsoleResult = _console("damage 10 target")
	assert_false(result.ok)


func test_heal_all_restores_every_hull() -> void:
	_console("damage 100 player")
	raider.damageable.hull.apply(50.0)
	assert_true(_console("heal all").ok)
	assert_eq(player.damageable.hull.hp, 300.0)
	assert_eq(raider.damageable.hull.hp, 300.0)


func test_destroying_the_player_through_the_console_is_logged_and_signalled() -> void:
	_console("damage 400 player")
	assert_true(player.damageable.hull.destroyed)
	assert_eq(destroyed_count, 1)


# --- the impact flash ----------------------------------------------------------------------------------------


func test_an_impact_flash_plays_then_leaves_the_ship_for_the_pool() -> void:
	var holder := Node3D.new()
	add_child_autofree(holder)
	var flash: ImpactFlash = ImpactFlash.create(Color(3.0, 1.0, 0.5), 7)
	holder.add_child(flash)
	assert_true(flash.is_flash_visible())
	flash.advance(ImpactFlash.FLASH_S * 0.5)
	assert_true(flash.is_flash_visible())
	flash.advance(ImpactFlash.FLASH_S)
	assert_false(flash.is_flash_visible(), "the flash is over after 80 ms")
	assert_false(holder.is_ancestor_of(flash), "it left the ship")
	assert_true(flash.get_parent() is FramePasses or flash.is_queued_for_deletion(), "kept for the next hit, or freed")


func test_a_finished_flash_is_handed_out_again_fresh() -> void:
	var holder := Node3D.new()
	add_child_autofree(holder)
	var first: ImpactFlash = ImpactFlash.create(Color.WHITE, 99)
	holder.add_child(first)
	first.advance(ImpactFlash.FLASH_S * 2.0)
	var built: int = ImpactFlash.built_count
	var again: ImpactFlash = ImpactFlash.create(Color(3.0, 1.0, 0.5), 3)
	assert_same(again, first, "the pool's flash")
	assert_eq(ImpactFlash.built_count, built, "nothing built")
	assert_null(again.get_parent(), "ready to be added to the hit ship")
	assert_true(again.is_flash_visible(), "showing from its start")
	assert_eq(again.age_s(), 0.0)
	assert_eq(again.transparency, 0.0)
	holder.add_child(again)
