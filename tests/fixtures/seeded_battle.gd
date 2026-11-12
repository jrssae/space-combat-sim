class_name SeededBattle
extends RefCounted
## Test fixture (M6-T18): the bench's seeded battle (`BenchLayout.BATTLE`, its fighters only, four sides) in a physics space
## of its own with the clock reset, shared by the files that fly it and compare digests (`test_core_state`, `test_core_threads`,
## `test_driver_step`, `test_row_commands`, `test_bolt_rows`, `test_core_snapshot`). The build order is the one the parity
## recordings were taken with: keep it, or their digests move.
##
##     Settings.set_value(&"perf_threads", 6)  # the caller sets the settings first
##     var fight: Dictionary = await SeededBattle.start(self, {SeededBattle.OPT_RAMS: true})
##     for t: int in 240:
##         await get_tree().physics_frame
##         rows.append(int((fight["sim"] as SimCore).core.rows_digest()))
##     await SeededBattle.finish(fight)
##
## `start` returns `space`, `world`, `bolts`, `resolver`, `rams` (or null), `ships`, `player` (or null), `sim`, and the ships'
## places in the battle by id: `index_of` (body and `Targetable` ids) and `targetable_index` (`Targetable` ids only).

const SHIPS: int = 120
const SEED: int = 1
## Options of `start`: the bench plan's ship count (fighters are about half of it).
const OPT_SHIPS: String = "ships"
## A `RamResolver` beside the hit resolver.
const OPT_RAMS: String = "rams"
## A lean player ship 300 m from the first fighter, so the fighters near it think every tick and the rest at the far rate.
const OPT_PLAYER: String = "player"
## Every core pass in parallel whatever its size (default on), so a 1-vs-6 comparison covers the brains and the flight step.
const OPT_PARALLEL: String = "parallel"


## A space of its own under `host` with a `World` and its `Projectiles`.
static func space(host: Node) -> SubViewport:
	var out := SubViewport.new()
	out.own_world_3d = true
	out.world_3d = World3D.new()
	host.add_child(out)
	var world := WorldFrame.new()
	world.name = "World"
	out.add_child(world)
	var bolts := Node3D.new()
	bolts.name = "Projectiles"
	world.add_child(bolts)
	return out


## Builds the battle under `host` with the bench's session table, ready for its first tick (see the header).
static func start(host: Node, options: Dictionary = {}) -> Dictionary:
	var tree: SceneTree = host.get_tree()
	Factions.reset()
	Factions.use_table(BenchLayout.faction_table(BenchLayout.BATTLE))
	ContactScan.invalidate()
	await tree.process_frame
	await tree.physics_frame
	SimClock.reset()
	var made: SubViewport = space(host)
	var world := made.get_node("World") as WorldFrame
	var bolts := world.get_node("Projectiles") as Node3D
	var resolver := HitResolver.new()
	resolver.name = "HitResolver"
	made.add_child(resolver)
	var rams: RamResolver = null
	if options.get(OPT_RAMS, false):
		rams = RamResolver.new()
		rams.name = "RamResolver"
		rams.world = world
		made.add_child(rams)
	var anchor: UniversePos = world.to_universe(Vector3.ZERO)
	var numbers: Dictionary = {}
	var ships: Array[Combatant] = []
	for e: Dictionary in BenchLayout.plan(BenchLayout.BATTLE, int(options.get(OPT_SHIPS, SHIPS)), SEED):
		if StringName(e["kind"]) != BenchLayout.KIND_FIGHTER:
			continue
		var type: StringName = e["type"]
		numbers[type] = int(numbers.get(type, 0)) + 1
		var c: Combatant = ShipAssembly.build(ShipCatalog.spec_for(type), world, bolts, {
			ShipAssembly.OPT_FACTION: StringName(e["faction"]), ShipAssembly.OPT_DISPLAY_NAME: "%s %d" % [type, int(numbers[type])],
			ShipAssembly.OPT_FORCE_ASSIST: true, ShipAssembly.OPT_AI: true, ShipAssembly.OPT_LEAN: true})
		world.spawn(c.ship, anchor.plus_local(e["offset"]), e["basis"])
		c.ship.linear_velocity = e["velocity"]
		c.driver.brain = BrainFactory.from_behaviour(e["behaviour"], anchor, int(e["seed"]))["brain"] as PilotBrain
		ships.append(c)
	var player: Combatant = null
	if options.get(OPT_PLAYER, false):
		player = ShipAssembly.build(ShipCatalog.spec_for(ships[0].ship.spec.asset_id), world, bolts, {
			ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE, ShipAssembly.OPT_DISPLAY_NAME: "PLAYER", ShipAssembly.OPT_IS_PLAYER: true,
			ShipAssembly.OPT_LEAN: true})
		world.spawn(player.ship, anchor.plus_local(ships[0].ship.position + Vector3(300.0, 0.0, 0.0)))
		player.ship.linear_velocity = ships[0].ship.linear_velocity
	var index_of: Dictionary = {}
	var targetable_index: Dictionary = {}
	for i: int in ships.size():
		index_of[ships[i].ship.get_instance_id()] = i
		index_of[ships[i].targetable.get_instance_id()] = i
		targetable_index[ships[i].targetable.get_instance_id()] = i
	var sim: SimCore = SimCore.attach(world)
	if options.get(OPT_PARALLEL, true):
		sim.core.set_parallel_min(2)
		sim.core.set_flight_parallel_min(2)
	return {"space": made, "world": world, "bolts": bolts, "resolver": resolver, "rams": rams, "ships": ships, "player": player,
			"sim": sim, "index_of": index_of, "targetable_index": targetable_index}


## Frees the battle's space and gives the tree two ticks to let it go.
static func finish(fight: Dictionary) -> void:
	var made: SubViewport = fight["space"]
	var tree: SceneTree = made.get_tree()
	made.queue_free()
	await tree.physics_frame
	await tree.physics_frame
	Factions.reset()


## Appends each hit (and each ram, with rams on) of the battle to `into` as it lands, the ships by their place in the battle,
## so a tick's hits compare across runs; the caller clears `into` before each tick.
static func log_hits(fight: Dictionary, into: Array) -> void:
	var index_of: Dictionary = fight["index_of"]
	(fight["resolver"] as HitResolver).hit_resolved.connect(func(info: HitInfo) -> void:
		into.append([index_of.get(info.target_id, -2), index_of.get(info.shooter_id, -2), info.damage, info.applied, info.point]))
	if fight["rams"] != null:
		(fight["rams"] as RamResolver).ram_resolved.connect(func(info: HitInfo) -> void:
			into.append(["ram", index_of.get(info.target_id, -2), index_of.get(info.shooter_id, -2), info.damage, info.point]))


## The battle's first `ships` plan entries' fighters, named `SHIP n`, flown a few ticks so every pilot has its native slot and
## most drivers are hosted. No hit resolver: these fights check the brains' and drivers' handover, not the combat.
static func small_fight(host: Node, ships: int = 60, settle_ticks: int = 8) -> Dictionary:
	var tree: SceneTree = host.get_tree()
	Factions.reset()
	Factions.use_table(BenchLayout.faction_table(BenchLayout.BATTLE))
	ContactScan.invalidate()
	await tree.physics_frame
	SimClock.reset()
	var made: SubViewport = space(host)
	var world := made.get_node("World") as WorldFrame
	var bolts := world.get_node("Projectiles") as Node3D
	var anchor: UniversePos = world.to_universe(Vector3.ZERO)
	var fighters: Array[Combatant] = []
	for e: Dictionary in BenchLayout.plan(BenchLayout.BATTLE, ships, SEED):
		if StringName(e["kind"]) != BenchLayout.KIND_FIGHTER:
			continue
		var c: Combatant = ShipAssembly.build(ShipCatalog.spec_for(e["type"]), world, bolts, {
			ShipAssembly.OPT_FACTION: StringName(e["faction"]), ShipAssembly.OPT_DISPLAY_NAME: "SHIP %d" % fighters.size(),
			ShipAssembly.OPT_FORCE_ASSIST: true, ShipAssembly.OPT_AI: true, ShipAssembly.OPT_LEAN: true})
		world.spawn(c.ship, anchor.plus_local(e["offset"]), e["basis"])
		c.ship.linear_velocity = e["velocity"]
		c.driver.brain = BrainFactory.from_behaviour(e["behaviour"], anchor, int(e["seed"]))["brain"] as PilotBrain
		fighters.append(c)
	var sim: SimCore = SimCore.attach(world)
	for i: int in settle_ticks:
		await tree.physics_frame
	return {"space": made, "sim": sim, "ships": fighters}


## What the game reads of a hosted pilot, readable: the behaviour in control, the wanted target's place, dwell, switches,
## the dodge, the scores and the desired velocity (the driver step's pilot digest is its hash).
static func pilot_parts(c: Combatant, index_of: Dictionary) -> Array:
	var pilot := c.driver.brain as AiPilot
	var scores := PackedFloat64Array()
	for id: StringName in AiPilot.TIE_ORDER:
		scores.append(pilot.score_of(id))
		scores.append(pilot.raw_score_of(id))
	var wanted: int = pilot.wanted_target_id
	return [String(pilot.current.id) if pilot.current != null else "none", index_of.get(wanted, -2) if wanted > 0 else -1,
			pilot.dwell_s, pilot.switches, c.driver.avoiding, c.driver.avoiding_urgent, scores, pilot.desired_velocity,
			pilot.has_desired_velocity]


## `pilot_parts` hashed, 0 for a ship without an `AiPilot`.
static func pilot_digest(c: Combatant, index_of: Dictionary) -> int:
	return hash(pilot_parts(c, index_of)) if c.driver.brain is AiPilot else 0


## What a battle on the hosted driver step is held to (`driver_step.json`, M4-T37): its thinks, its held ticks (a hosted
## driver's are counted when its job is joined, one tick behind, so they are read `shift` ticks later) and digests of every
## tick's rows, commands and hits and of the pilots at the end. `battle` holds those under the keys used here.
static func hosted_digest(battle: Dictionary, shift: int) -> Dictionary:
	var held: PackedInt64Array = battle["held_ticks"]
	var held_sum: int = 0
	for t: int in held.size() - 1:
		held_sum += held[t + shift]
	return {"native_thinks": battle["native_thinks"], "held": held_sum, "hits_total": battle["hits_total"],
			"rows": ParityFixture.digest(battle["rows"]), "commands": ParityFixture.digest(battle["commands"]),
			"hits": ParityFixture.digest(battle["hits"]), "pilots": ParityFixture.digest(battle["pilots"])}


## The first index where the two lists differ (or where one ends early), -1 when they are equal.
static func first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())
