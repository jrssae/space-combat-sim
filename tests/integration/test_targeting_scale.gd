extends GutTest
## Targeting at scale (M4-T02, cycle 1): only the player's targeting computer, whose list the HUD and the radar read every
## frame, builds a `TargetInfo` for every targetable each tick. Other ships keep their selection checked every tick and build
## a list only when something asks for one, so the work per tick grows with the ship count, not with its square.
##
## The rest pins what an AI ship's targeting does, whatever it builds: a selection that leaves its reach, turns inactive or
## is freed clears in the tick's refresh and says so; a broadcast stretches the reach; an id out of reach is refused and the
## selection kept; the nearest hostile wins over a nearer neutral, ties go to the lower id, and with none in reach the
## selection clears.

const STARFURY_PATH: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_PATH: String = "res://assets/ships/raider_delta_v.tres"
## AI ships in the work-count fight, half on each side.
const FLEET: int = 24
const SETTLE_TICKS: int = 5
const MEASURED_TICKS: int = 30

var world: WorldFrame
var projectiles: Node3D
var player: Combatant


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	player = _ship("PLAYER", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, 3000.0), true, false)
	ContactScan.invalidate()


func _ship(label: String, faction: StringName, at: Vector3, is_player: bool, ai: bool,
		basis: Basis = Basis.IDENTITY) -> Combatant:
	var path: String = RAIDER_PATH if faction == Factions.RAIDERS else STARFURY_PATH
	var combatant: Combatant = ShipAssembly.build(load(path) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: label,
		ShipAssembly.OPT_CONSOLE_OWNER: is_player,
		ShipAssembly.OPT_FORCE_ASSIST: not is_player,
		ShipAssembly.OPT_AI: ai,
	})
	world.spawn(combatant.ship, world.to_universe(at), basis)
	combatant.damageable.invulnerable = true
	return combatant


## A targetable without a body or a hull, at `at` (World frame): a marker the tests can put anywhere, exactly.
func _marker(label: String, faction: StringName, at: Vector3, broadcast_m: float = 0.0) -> Targetable:
	var holder := Node3D.new()
	holder.name = label.replace(" ", "_")
	world.add_child(holder)
	holder.position = at
	var targetable := Targetable.new()
	targetable.name = "Targetable"
	targetable.display_name = label
	targetable.faction = faction
	targetable.broadcast_range_m = broadcast_m
	holder.add_child(targetable)
	return targetable


func _watch(targeting: TargetingController) -> Array[int]:
	var seen: Array[int] = []
	targeting.target_changed.connect(func(id: int) -> void: seen.append(id))
	return seen


# --- the work per tick ----------------------------------------------------------------------------------------------


func test_ai_ships_do_not_build_a_target_list_every_tick() -> void:
	var fleet: Array[Combatant] = []
	for i: int in FLEET:
		var ally: bool = i % 2 == 0
		var slot: int = i / 2
		var at := Vector3(float(slot % 4) * 150.0 - 225.0, float(slot / 4) * 150.0 - 75.0, 700.0 if ally else -700.0)
		var label: String = ("ALPHA %d" if ally else "RAIDER %d") % (slot + 1)
		var basis: Basis = Basis.IDENTITY if ally else Basis(Vector3.UP, PI)  # the sides face each other
		var c: Combatant = _ship(label, Factions.EARTH_ALLIANCE if ally else Factions.RAIDERS, at, false, true, basis)
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury" if ally else "raider"},
				world.to_universe(at), 100 + i)
		assert_true(made["ok"], made["error"])
		c.driver.brain = made["brain"] as PilotBrain
		fleet.append(c)
	for i: int in SETTLE_TICKS:
		await get_tree().physics_frame
	var before: int = TargetInfo.built_count
	for i: int in MEASURED_TICKS:
		await get_tree().physics_frame
	var per_tick: float = float(TargetInfo.built_count - before) / float(MEASURED_TICKS)
	var ships: int = FLEET + 1
	assert_lt(per_tick, 3.0 * float(ships),
			"%.0f TargetInfos per tick for %d ships: linear, not a list per ship (that would be about %d)" % [
			per_tick, ships, ships * (ships - 1)])
	var listed: Array[TargetInfo] = player.ship.targeting.candidates()
	assert_eq(listed.size(), FLEET, "the player's list (the HUD's and the radar's) still holds every other ship")
	var selecting: int = 0
	for c: Combatant in fleet:
		var targeting: TargetingController = c.ship.targeting
		if not targeting.system.has_selection():
			continue
		selecting += 1
		var target := instance_from_id(targeting.selected_id()) as Targetable
		assert_not_null(target, "%s holds a live selection" % c.display_name)
		if target != null:
			assert_true(target.is_active(), "%s: its selection is in play" % c.display_name)
			assert_true(Factions.is_hostile(c.faction, target.faction), "%s: its selection is hostile" % c.display_name)
	assert_gt(selecting, 0, "the pilots picked targets")


# --- what an AI ship's targeting does ----------------------------------------------------------------------------


func test_a_selection_that_leaves_the_sensor_range_clears_and_says_so() -> void:
	var raider: Combatant = _ship("RAIDER 1", Factions.RAIDERS, Vector3.ZERO, false, false)
	var prey: Targetable = _marker("PREY", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -2000.0))
	var targeting: TargetingController = raider.ship.targeting
	assert_true(targeting.select_id(prey.get_instance_id()))
	var seen: Array[int] = _watch(targeting)
	(prey.get_parent() as Node3D).position = Vector3(0.0, 0.0, -24000.0)
	targeting.refresh()
	assert_eq(targeting.selected_id(), prey.get_instance_id(), "still inside the 25 km sensors")
	assert_eq(seen, [] as Array[int])
	(prey.get_parent() as Node3D).position = Vector3(0.0, 0.0, -26000.0)
	targeting.refresh()
	assert_false(targeting.system.has_selection(), "beyond them")
	assert_eq(seen, [TargetingSystem.NO_TARGET])


func test_a_broadcast_keeps_a_target_selectable_beyond_the_sensors() -> void:
	var raider: Combatant = _ship("RAIDER 1", Factions.RAIDERS, Vector3.ZERO, false, false)
	var loud: Targetable = _marker("LOUD", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -60000.0), 100000.0)
	var targeting: TargetingController = raider.ship.targeting
	assert_true(targeting.select_id(loud.get_instance_id()), "heard at 60 km")
	targeting.refresh()
	assert_eq(targeting.selected_id(), loud.get_instance_id())
	(loud.get_parent() as Node3D).position = Vector3(0.0, 0.0, -101000.0)
	targeting.refresh()
	assert_false(targeting.system.has_selection(), "past its own broadcast range")


func test_a_selection_that_turns_inactive_or_is_freed_clears_and_says_so() -> void:
	var raider: Combatant = _ship("RAIDER 1", Factions.RAIDERS, Vector3.ZERO, false, false)
	var first: Targetable = _marker("FIRST", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -1000.0))
	var second: Targetable = _marker("SECOND", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -1500.0))
	var targeting: TargetingController = raider.ship.targeting
	var seen: Array[int] = _watch(targeting)
	assert_true(targeting.select_id(first.get_instance_id()))
	(first.get_parent() as Node3D).visible = false
	targeting.refresh()
	assert_false(targeting.system.has_selection(), "a hidden target is out of play")
	var second_id: int = second.get_instance_id()
	assert_true(targeting.select_id(second_id))
	var holder: Node = second.get_parent()
	holder.get_parent().remove_child(holder)
	holder.free()
	targeting.refresh()
	assert_false(targeting.system.has_selection(), "a freed one too")
	assert_eq(seen, [first.get_instance_id(), TargetingSystem.NO_TARGET, second_id, TargetingSystem.NO_TARGET])


func test_select_id_refuses_a_target_out_of_reach_and_keeps_the_selection() -> void:
	var raider: Combatant = _ship("RAIDER 1", Factions.RAIDERS, Vector3.ZERO, false, false)
	var near: Targetable = _marker("NEAR", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -1000.0))
	var far: Targetable = _marker("FAR", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -30000.0))
	var targeting: TargetingController = raider.ship.targeting
	assert_true(targeting.select_id(near.get_instance_id()))
	assert_false(targeting.select_id(far.get_instance_id()), "30 km, and it does not broadcast")
	assert_eq(targeting.selected_id(), near.get_instance_id(), "the selection stays")
	assert_false(targeting.select_id(raider.targetable.get_instance_id()), "never itself")
	assert_eq(targeting.selected_id(), near.get_instance_id())


func test_the_nearest_hostile_wins_over_a_nearer_neutral_and_none_clears() -> void:
	player.ship.visible = false  # out of play, so the markers are the only hostiles
	var raider: Combatant = _ship("RAIDER 1", Factions.RAIDERS, Vector3.ZERO, false, false)
	_marker("NAV NEAR", Factions.NEUTRAL, Vector3(0.0, 0.0, -100.0))
	_marker("MATE", Factions.RAIDERS, Vector3(0.0, 0.0, -200.0))
	var near: Targetable = _marker("NEAR", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -1000.0))
	var far: Targetable = _marker("FAR", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -2000.0))
	var targeting: TargetingController = raider.ship.targeting
	assert_true(targeting.select_nearest_hostile())
	assert_eq(targeting.selected_id(), near.get_instance_id(), "not the buoy, not a raider")
	assert_eq(targeting.selected_name(), "NEAR")
	(near.get_parent() as Node3D).visible = false
	assert_true(targeting.select_nearest_hostile())
	assert_eq(targeting.selected_id(), far.get_instance_id(), "the next one in play")
	(far.get_parent() as Node3D).position = Vector3(0.0, 0.0, -40000.0)
	assert_false(targeting.select_nearest_hostile(), "no hostile in reach")
	assert_false(targeting.system.has_selection(), "and the selection clears")


func test_two_hostiles_at_the_same_range_go_to_the_lower_id() -> void:
	var raider: Combatant = _ship("RAIDER 1", Factions.RAIDERS, Vector3.ZERO, false, false)
	raider.ship.global_position = Vector3.ZERO
	var east: Targetable = _marker("EAST", Factions.EARTH_ALLIANCE, Vector3(1500.0, 0.0, 0.0))
	var west: Targetable = _marker("WEST", Factions.EARTH_ALLIANCE, Vector3(-1500.0, 0.0, 0.0))
	assert_true(raider.ship.targeting.select_nearest_hostile())
	assert_eq(raider.ship.targeting.selected_id(), mini(east.get_instance_id(), west.get_instance_id()))


func test_an_ai_ships_candidates_are_current_when_asked() -> void:
	var raider: Combatant = _ship("RAIDER 1", Factions.RAIDERS, Vector3.ZERO, false, false)
	var first: Targetable = _marker("FIRST", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -1000.0))
	_marker("SECOND", Factions.NEUTRAL, Vector3(0.0, 0.0, -500.0))
	var names: PackedStringArray = PackedStringArray()
	for info: TargetInfo in raider.ship.targeting.candidates():
		names.append(info.display_name)
	assert_eq(names, PackedStringArray(["SECOND", "FIRST", "PLAYER"]), "nearest first, never itself")
	(first.get_parent() as Node3D).position = Vector3(0.0, 0.0, -100.0)
	assert_eq(raider.ship.targeting.candidates()[0].display_name, "FIRST", "as the targets are now")
