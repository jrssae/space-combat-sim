extends GutTest
## Friendly fire and factions as data in the hit resolver (M3-T02, AC2 and AC3, architecture §16 D30, D31).
##
## Off (the default) nothing changes from M2: only hostile hulls take hits (and buoys, from anyone else's bolts). On
## (`settings.friendly_fire`, read every tick), a bolt hits any active hull except its shooter's: allies, the player (god
## mode still protects its hull), neutral props. A console `relation` change decides who is hostile at once. The AI half of
## AC3 (an AI never fires with a friend in its lane) is M3-T05.
##
## The world is stepped by hand as in test_hit_resolver: bolts move, the resolver runs. Each ship sits in its own lane (x)
## and bolts fly along +z at 400 m/s, 100 m out.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"
const DT: float = 1.0 / 60.0
const BOLT_SPEED: float = 400.0
const LANE_PLAYER: float = 0.0
const LANE_ALLY: float = 200.0
const LANE_BUOY: float = 400.0
const LANE_RAIDER: float = -200.0

var world: WorldFrame
var projectiles: Node3D
var resolver: HitResolver
var player: Combatant
var ally: Combatant
var buoy: TargetDrone  # a neutral prop that any bolt hurts, like a nav buoy
var raider: TargetDrone
var hits: Array[HitInfo] = []
var friendly_fire_backup: bool = false


func before_each() -> void:
	DebugConsole.flags.invulnerable = false
	Factions.reset()
	friendly_fire_backup = bool(Settings.get_value(&"friendly_fire"))
	Settings.set_value(&"friendly_fire", false)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	resolver = HitResolver.new()
	add_child_autofree(resolver)
	resolver.set_physics_process(false)  # the tests call resolve() themselves
	var spec := load(SPEC_PATH) as ShipSpec
	player = _build(spec, "PLAYER", Vector3(LANE_PLAYER, 0.0, 0.0), true)
	ally = _build(spec, "ALPHA 2", Vector3(LANE_ALLY, 0.0, 0.0), false)
	buoy = _drone(Vector3(LANE_BUOY, 0.0, 0.0), Factions.NEUTRAL)
	buoy.damageable.hit_by_anyone = true
	raider = _drone(Vector3(LANE_RAIDER, 0.0, 0.0), Factions.RAIDERS)
	hits.clear()
	resolver.hit_resolved.connect(func(info: HitInfo) -> void: hits.append(info))


func after_each() -> void:
	Settings.set_value(&"friendly_fire", friendly_fire_backup)
	DebugConsole.flags.invulnerable = false
	Factions.reset()


func _build(spec: ShipSpec, display: String, at: Vector3, is_player: bool) -> Combatant:
	var combatant: Combatant = ShipAssembly.build(spec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: display,
		ShipAssembly.OPT_IS_PLAYER: is_player,
	})
	world.spawn(combatant.ship, world.to_universe(at))
	return combatant


func _drone(at: Vector3, p_faction: StringName) -> TargetDrone:
	var drone := (load(DRONE_SCENE) as PackedScene).instantiate() as TargetDrone
	drone.faction = p_faction
	drone.set_physics_process(false)
	world.spawn(drone, world.to_universe(at))
	return drone


## A bolt of `p_faction` fired by `shooter_id`, 100 m before the lane's ship, flying +z.
func _bolt(lane: float, p_faction: StringName, shooter_id: int, start_z: float = -100.0) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	bolt.configure(ally.ship.spec.weapon)
	bolt.shooter_id = shooter_id
	bolt.faction = p_faction
	bolt.launch(Vector3(lane, 0.0, start_z), Vector3(0.0, 0.0, BOLT_SPEED), SimClock.now())
	bolt.set_physics_process(false)
	return bolt


func _ally_bolt(lane: float, start_z: float = -100.0) -> Projectile:
	return _bolt(lane, Factions.EARTH_ALLIANCE, ally.ship.get_instance_id(), start_z)


func _fly(ticks: int) -> void:
	for i: int in ticks:
		for node: Node in projectiles.get_children():
			var bolt := node as Projectile
			if bolt != null and not bolt.is_spent():
				bolt._physics_process(DT)
		resolver.resolve(DT)


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


# --- the setting and the filter ---------------------------------------------------------------------------------


func test_friendly_fire_is_a_setting_that_defaults_off() -> void:
	var schema := SettingsSchema.new()
	assert_true(schema.has_key(&"friendly_fire"))
	assert_eq(schema.get_type(&"friendly_fire"), TYPE_BOOL)
	assert_eq(schema.get_default(&"friendly_fire"), false, "forgiving by default (maintainer Q2)")
	assert_eq(DebugConsole.registry.format_path("settings.friendly_fire"), "settings.friendly_fire = false")


func test_can_be_hit_by_with_and_without_friendly_fire() -> void:
	var hull := Damageable.new()
	add_child_autofree(hull)
	hull.setup([] as Array[Dictionary], 100.0, Factions.RAIDERS)
	# Off: the M2 rule (hostile bolts only).
	assert_true(hull.can_be_hit_by(Factions.EARTH_ALLIANCE))
	assert_true(hull.can_be_hit_by(Factions.EARTH_ALLIANCE, false))
	assert_false(hull.can_be_hit_by(Factions.RAIDERS), "own faction")
	assert_false(hull.can_be_hit_by(Factions.NEUTRAL))
	assert_false(hull.can_be_hit_by(&"nobody_knows"))
	# On: any bolt.
	for bolt_faction: StringName in [Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.NEUTRAL, &"nobody_knows", &""]:
		assert_true(hull.can_be_hit_by(bolt_faction, true), "friendly fire: " + str(bolt_faction))
	# A buoy-like hull: hit by anyone but its own faction, until friendly fire lets that through too.
	hull.setup([] as Array[Dictionary], 100.0, Factions.NEUTRAL)
	hull.hit_by_anyone = true
	assert_true(hull.can_be_hit_by(Factions.RAIDERS))
	assert_false(hull.can_be_hit_by(Factions.NEUTRAL), "its own faction passes through (M2)")
	assert_true(hull.can_be_hit_by(Factions.NEUTRAL, true))


# --- off: M2 unchanged --------------------------------------------------------------------------------------------


func test_off_allied_bolts_pass_through_allies_and_the_player() -> void:
	_ally_bolt(LANE_PLAYER)
	_fly(60)
	assert_eq(hits.size(), 0)
	assert_eq(player.damageable.hull.hp, player.damageable.hull.max_hp)
	assert_false(resolver.friendly_fire)


func test_off_allied_bolts_still_hurt_raiders() -> void:
	_ally_bolt(LANE_RAIDER)
	_fly(60)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].target_id, raider.get_instance_id())
	assert_eq(hits[0].applied, 10.0)


func test_off_a_raider_bolt_hurts_the_player_and_the_ally_but_not_raiders() -> void:
	_bolt(LANE_PLAYER, Factions.RAIDERS, raider.get_instance_id())
	_bolt(LANE_ALLY, Factions.RAIDERS, raider.get_instance_id())
	_bolt(LANE_RAIDER, Factions.RAIDERS, 0)
	_fly(60)
	assert_eq(hits.size(), 2)
	assert_eq(player.damageable.hull.hp, player.damageable.hull.max_hp - 10.0)
	assert_eq(ally.damageable.hull.hp, ally.damageable.hull.max_hp - 10.0)
	assert_eq(raider.damageable.hull.hp, raider.damageable.hull.max_hp)


func test_off_a_buoy_is_hurt_by_foreign_bolts_but_not_its_own_faction() -> void:
	_ally_bolt(LANE_BUOY)
	_bolt(LANE_BUOY, Factions.NEUTRAL, 0, -90.0)
	_fly(60)
	assert_eq(hits.size(), 1, "the neutral bolt passed through the neutral buoy")
	assert_eq(hits[0].faction, Factions.EARTH_ALLIANCE)


# --- on: any hull but the shooter's -------------------------------------------------------------------------------


func test_on_a_bolt_hits_an_ally() -> void:
	Settings.set_value(&"friendly_fire", true)
	var other_ally: TargetDrone = _drone(Vector3(-400.0, 0.0, 0.0), Factions.EARTH_ALLIANCE)
	_ally_bolt(-400.0)
	_fly(60)
	assert_true(resolver.friendly_fire)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].target_id, other_ally.get_instance_id())
	assert_eq(hits[0].shooter_id, ally.ship.get_instance_id())
	assert_eq(other_ally.damageable.hull.hp, other_ally.damageable.hull.max_hp - 10.0)


func test_on_a_bolt_hits_the_player() -> void:
	Settings.set_value(&"friendly_fire", true)
	_ally_bolt(LANE_PLAYER)
	_fly(60)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].target_id, player.ship.get_instance_id())
	assert_eq(player.damageable.hull.hp, player.damageable.hull.max_hp - 10.0)


func test_on_god_mode_still_protects_the_player() -> void:
	Settings.set_value(&"friendly_fire", true)
	DebugConsole.flags.invulnerable = true
	var taken: Array[HitInfo] = []
	player.damageable.hit_taken.connect(func(info: HitInfo) -> void: taken.append(info))
	_ally_bolt(LANE_PLAYER)
	_fly(60)
	assert_eq(taken.size(), 1, "the hit lands (flash, sound)")
	assert_eq(taken[0].applied, 0.0)
	assert_eq(player.damageable.hull.hp, player.damageable.hull.max_hp, "and does no damage")
	assert_eq(ally.damageable.hull.hp, ally.damageable.hull.max_hp, "god mode is the player's alone")
	_bolt(LANE_ALLY, Factions.EARTH_ALLIANCE, player.ship.get_instance_id())
	_fly(60)
	assert_eq(ally.damageable.hull.hp, ally.damageable.hull.max_hp - 10.0, "an ally is hurt by the player's bolt")


func test_on_a_bolt_hits_a_buoy_even_of_its_own_faction_and_a_neutral_prop() -> void:
	Settings.set_value(&"friendly_fire", true)
	_ally_bolt(LANE_BUOY)
	_bolt(LANE_BUOY, Factions.NEUTRAL, 0, -90.0)
	_fly(60)
	assert_eq(hits.size(), 2)
	assert_eq(buoy.damageable.hull.hp, buoy.damageable.hull.max_hp - 20.0)


func test_on_raiders_shoot_each_other() -> void:
	Settings.set_value(&"friendly_fire", true)
	_bolt(LANE_RAIDER, Factions.RAIDERS, ally.ship.get_instance_id())
	_fly(60)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].target_id, raider.get_instance_id())


func test_on_a_bolt_never_hits_its_shooter() -> void:
	Settings.set_value(&"friendly_fire", true)
	# The ally's own bolt flies through the ally's hull (the shooter) and on to a second ally behind it.
	var behind: TargetDrone = _drone(Vector3(LANE_ALLY, 0.0, 150.0), Factions.EARTH_ALLIANCE)
	_ally_bolt(LANE_ALLY)
	_fly(90)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].target_id, behind.get_instance_id(), "the shooter was skipped, the next hull was not")
	assert_eq(ally.damageable.hull.hp, ally.damageable.hull.max_hp)


func test_on_the_player_never_shoots_himself() -> void:
	Settings.set_value(&"friendly_fire", true)
	_bolt(LANE_PLAYER, Factions.EARTH_ALLIANCE, player.ship.get_instance_id())
	_fly(60)
	assert_eq(hits.size(), 0)
	assert_eq(player.damageable.hull.hp, player.damageable.hull.max_hp)


func test_the_setting_is_read_every_tick() -> void:
	_ally_bolt(LANE_PLAYER)
	_fly(3)  # still 100 m out, friendly fire off
	assert_eq(hits.size(), 0)
	Settings.set_value(&"friendly_fire", true)
	_fly(60)
	assert_eq(hits.size(), 1, "turned on mid-flight, the same bolt hits")
	Settings.set_value(&"friendly_fire", false)
	_ally_bolt(LANE_PLAYER)
	_fly(60)
	assert_eq(hits.size(), 1, "and off again, the next one passes")
	assert_false(resolver.friendly_fire)


func test_console_sets_the_setting_for_the_session() -> void:
	assert_true(_console("set settings.friendly_fire on").ok)
	_ally_bolt(LANE_PLAYER)
	_fly(60)
	assert_eq(hits.size(), 1)
	assert_eq(DebugConsole.registry.format_path("factions.friendly_fire"), "factions.friendly_fire = true")
	assert_true(_console("toggle settings.friendly_fire").ok)
	assert_eq(DebugConsole.registry.format_path("factions.friendly_fire"), "factions.friendly_fire = false")


# --- factions as data: the relation command ------------------------------------------------------------------------


func test_the_resolver_registers_the_faction_provider_and_command_and_drops_them() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_true(registry.has_provider(&"factions"))
	assert_true(registry.has_command(&"relation"))
	assert_eq(registry.format_path("factions.ids"), "factions.ids = [earth_alliance, raiders, neutral]")
	resolver.free()
	assert_false(registry.has_provider(&"factions"), "owned by the resolver")
	assert_false(registry.has_command(&"relation"))


func test_relation_decides_who_gets_shot() -> void:
	_ally_bolt(LANE_RAIDER)
	_fly(60)
	assert_eq(hits.size(), 1, "hostile by the file")

	var result: ConsoleResult = _console("relation earth_alliance raiders neutral")
	assert_true(result.ok, result.error)
	assert_eq(DebugConsole.registry.format_path("factions.relations"), "factions.relations = [earth_alliance raiders neutral]")
	_ally_bolt(LANE_RAIDER)
	_fly(60)
	assert_eq(hits.size(), 1, "neutral now: the bolt passes")

	_console("relation earth_alliance raiders friendly")
	_ally_bolt(LANE_RAIDER)
	_fly(60)
	assert_eq(hits.size(), 1, "friendly: still safe with friendly fire off")

	_console("relation reset")
	_ally_bolt(LANE_RAIDER)
	_fly(60)
	assert_eq(hits.size(), 2, "reset reloads the file: hostile again")


func test_a_new_enemy_by_console_can_be_shot_without_friendly_fire() -> void:
	# neutral vs earth_alliance is not hostile by default; the console makes it so for the session.
	var neutral_ship: TargetDrone = _drone(Vector3(-400.0, 0.0, 0.0), Factions.NEUTRAL)
	_ally_bolt(-400.0)
	_fly(60)
	assert_eq(hits.size(), 0)
	_console("relation earth_alliance neutral hostile")
	_ally_bolt(-400.0)
	_fly(60)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].target_id, neutral_ship.get_instance_id())


func test_hud_colours_follow_the_console() -> void:
	var own: StringName = Factions.EARTH_ALLIANCE
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.RAIDERS)), Factions.HOSTILE_COLOR)
	_console("relation earth_alliance raiders neutral")
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.RAIDERS)), Factions.NEUTRAL_COLOR)
	_console("relation earth_alliance raiders friendly")
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.RAIDERS)), Factions.FRIENDLY_COLOR)
	_console("relation reset")
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.RAIDERS)), Factions.HOSTILE_COLOR)
