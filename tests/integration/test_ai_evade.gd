extends GutTest
## AC9, evade (M3-T06, architecture §16 D34): an M2 attack raider (`AttackBrain`, the M2 tactics, a fixed seed) starts 2 km
## behind a Starfury flown by an `AiPilot` that cannot fight back (attack weight 0) and does not retreat. The same seeded
## setup is flown twice: with evade weight 0 the Starfury only holds position; with evade weight 1 it jinks. Evading must cut
## the raider's hits on it at least in half. The real ships in Jolt, the real drivers (avoidance included) and the real
## `HitResolver`; sim time sped up with `Engine.time_scale` (0.1 s steps; the same holds at 60 Hz, see the M3-T06 notes).
##
## Both setups fly at once in one world, 10 km apart (beyond the 5 km sensor range and any bolt's reach, so neither sees the
## other), at mirrored positions so both get the same float precision. That halves the wall-clock time of the test.

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
## `Engine.time_scale` scales the physics step: 6 makes each 60 Hz tick 0.1 s of sim time.
const SPEED_UP: float = 6.0
## Sim seconds: about three of the raider's gun runs.
const RUN_S: float = 120.0
const RAIDER_SEED: int = 4242
const PILOT_SEED: int = 99
const APART_M: float = 10000.0

var _scale_backup: float = 1.0


## Calls `on_tick` at the end of every physics tick, so a run lasts exactly `RUN_S` of sim time.
class Ticker extends Node:
	var ticks: int = 0
	var on_tick: Callable = Callable()

	func _init() -> void:
		process_physics_priority = 500

	func _physics_process(_delta: float) -> void:
		ticks += 1
		on_tick.call()


func before_each() -> void:
	_scale_backup = Engine.time_scale
	ContactScan.invalidate()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	ContactScan.invalidate()


func _profile(evade_weight: float) -> AiProfile:
	var profile := AiProfile.new()
	profile.weights = {&"attack": 0.0, &"evade": evade_weight, &"retreat": 0.0, &"idle": 1.0}
	profile.retreat_below = 0.0
	profile.idle_hold = true
	profile.tactics = load(AiProfile.STARFURY_TACTICS_PATH) as RaiderTactics
	return profile


## A Starfury flown by an `AiPilot` with this evade weight at `at`, nose -Z, and an attack raider 2 km behind it.
## Returns the counters the ticker fills in.
func _setup(world: WorldFrame, projectiles: Node3D, resolver: HitResolver, at: Vector3, evade_weight: float,
		tag: String) -> Dictionary:
	var evader: Combatant = ShipAssembly.build(load(STARFURY_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "ALPHA %s" % tag,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(evader.ship, world.to_universe(at))
	evader.damageable.hull = HullHealth.new(1.0e6)  # it must live through every hit of the run without evading
	var raider: Combatant = ShipAssembly.build(load(RAIDER_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS,
		ShipAssembly.OPT_DISPLAY_NAME: "RAIDER %s" % tag,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(raider.ship, world.to_universe(at + Vector3(0.0, 0.0, 2000.0)), Basis.IDENTITY)  # behind, nose on it
	raider.driver.brain = AttackBrain.new(load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics, RAIDER_SEED)
	var pilot := AiPilot.new(_profile(evade_weight), PILOT_SEED)
	evader.driver.brain = pilot
	var run: Dictionary = {"hits": 0, "evade_ticks": 0, "max_jinks": 0, "raider_fire_ticks": 0, "pilot": pilot,
			"raider": raider.driver.brain, "evader": evader}
	var evader_id: int = evader.ship.get_instance_id()
	resolver.hit_resolved.connect(func(info: HitInfo) -> void:
		if info.target_id == evader_id:
			run["hits"] = int(run["hits"]) + 1)
	return run


func _count(run: Dictionary) -> void:
	var pilot: AiPilot = run["pilot"]
	if pilot.current != null and pilot.current.id == &"evade":
		run["evade_ticks"] = int(run["evade_ticks"]) + 1
		run["max_jinks"] = maxi(int(run["max_jinks"]), (pilot.current as BehaviourEvade).jinks)
	if (run["raider"] as AttackBrain).firing:
		run["raider_fire_ticks"] = int(run["raider_fire_ticks"]) + 1


func test_evading_cuts_an_attack_raiders_hits_at_least_in_half() -> void:
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var resolver := HitResolver.new()
	add_child_autofree(resolver)
	var still: Dictionary = _setup(world, projectiles, resolver, Vector3(-APART_M / 2.0, 0.0, 0.0), 0.0, "A")
	var evading: Dictionary = _setup(world, projectiles, resolver, Vector3(APART_M / 2.0, 0.0, 0.0), 1.0, "B")
	var ticker := Ticker.new()
	ticker.on_tick = func() -> void:
		_count(still)
		_count(evading)
	add_child_autofree(ticker)
	Engine.time_scale = SPEED_UP
	var ticks: int = roundi(RUN_S * float(Engine.physics_ticks_per_second) / SPEED_UP)
	while ticker.ticks < ticks:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	gut.p("evade: %d hits holding position (raider on the trigger %d ticks); %d hits evading (%d ticks evading, up to %d jinks, raider on the trigger %d ticks)" % [
			still["hits"], still["raider_fire_ticks"], evading["hits"], evading["evade_ticks"], evading["max_jinks"],
			evading["raider_fire_ticks"]])
	assert_eq(still["evade_ticks"], 0, "evade weight 0: it never evades")
	assert_gt(int(still["hits"]), 20, "the raider lands a fair number of hits on a ship that holds still")
	assert_gt(int(evading["evade_ticks"]), 0, "it evaded")
	assert_gt(int(evading["max_jinks"]), 1, "with reversals")
	assert_lte(int(evading["hits"]) * 2, int(still["hits"]), "evading at least halves the hits")
