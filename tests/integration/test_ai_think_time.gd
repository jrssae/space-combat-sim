extends GutTest
## AC13, AI half (M3-T06): the AI think time of 13 ships (four Starfuries on the `ally_starfury` profile and nine raiders on
## the `raider` profile, AC19's mix, in one fight with bolts flying), headless, at the game's 60 Hz step. `ai.think_us` is the
## wall-clock time of every `AiPilotDriver.step` in a tick: contact scan, perception, retarget, brain, avoidance filter.
##
## Paired: the same 13 ships fly alternating blocks on `AiPilot` and on M2's `AttackBrain` in one process, so both brains see
## the same fight and the same machine; `AiPilot`'s median tick must stay within `PILOT_SHARE_US` of the M2 brains' (T05 left
## `AiPilot` about 0.5 ms of AC13's 1.5 ms). On the development desktop the speed of the whole frame swings by up to 2x over
## seconds whatever flies the ships, so the blocks are short and many, and the statistic is the median over the block
## pairs (an AiPilot block and the M2 block right after it) of the difference of their medians: a pair that straddles one
## of those swings is off by about a millisecond either way, and the median of six pairs is not moved by one or two. The first
## seconds after 13 ships spawn are slow whatever flies them, so the fight warms up for `WARM_UP_TICKS`, and each block
## settles for `SETTLE_TICKS` after the brains change.
##
## There is no absolute assertion: the quiet median of the whole path is about 2 ms for both brains on that desktop, over
## AC13's 1.5 ms (recorded in the M3-T06 as-built notes, with the cost by component, for the maintainer to rebaseline).

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const PILOT_SHARE_US: float = 500.0
const WARM_UP_TICKS: int = 240
const SETTLE_TICKS: int = 15
const BLOCK_TICKS: int = 60
## Blocks per brain, alternating AiPilot, M2, AiPilot, M2, ...
const BLOCKS: int = 6

var world: WorldFrame
var ships: Array[Combatant] = []


class Sampler extends Node:
	var samples: PackedInt64Array = PackedInt64Array()

	func _init() -> void:
		process_physics_priority = 500

	func _physics_process(_delta: float) -> void:
		samples.append(AiPilotDriver.think_us())


func before_each() -> void:
	ContactScan.invalidate()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	add_child_autofree(HitResolver.new())
	ships.clear()
	for i: int in 4:
		ships.append(_ship(STARFURY_SPEC, Factions.EARTH_ALLIANCE, "ALPHA %d" % (i + 1), projectiles,
				Vector3(float(i) * 120.0 - 180.0, 0.0, 0.0), Basis.IDENTITY))
	for i: int in 9:
		ships.append(_ship(RAIDER_SPEC, Factions.RAIDERS, "RAIDER %d" % (i + 1), projectiles,
				Vector3(float(i) * 100.0 - 400.0, float(i % 3) * 60.0 - 60.0, -1500.0), Basis(Vector3.UP, PI)))


func after_each() -> void:
	ContactScan.invalidate()


func _ship(spec_path: String, faction: StringName, ship_name: String, projectiles: Node3D, at: Vector3,
		basis: Basis) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(spec_path) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: ship_name,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(c.ship, world.to_universe(at), basis)
	c.damageable.hull = HullHealth.new(1.0e6)  # all 13 stay in the fight for the whole measurement
	return c


static func _median(samples: PackedInt64Array) -> float:
	var sorted: Array = Array(samples)
	sorted.sort()
	return float(sorted[sorted.size() / 2])


static func _mean(samples: PackedInt64Array) -> float:
	var total: int = 0
	for us: int in samples:
		total += us
	return float(total) / float(maxi(samples.size(), 1))


func test_ai_pilots_cost_at_most_half_a_millisecond_more_than_m2_brains_in_the_same_fight() -> void:
	var pilots: Array[PilotBrain] = []
	var m2: Array[PilotBrain] = []
	for i: int in ships.size():
		var profile: String = "ally_starfury" if ships[i].faction == Factions.EARTH_ALLIANCE else "raider"
		pilots.append(BrainFactory.from_behaviour({"type": "ai", "profile": profile}, UniversePos.new(), i)["brain"])
		m2.append(AttackBrain.new(load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics, i))
	var sampler := Sampler.new()
	add_child_autofree(sampler)
	var ai_samples := PackedInt64Array()
	var m2_samples := PackedInt64Array()
	var block_medians: Array[String] = []
	var pair_differences := PackedFloat64Array()
	var last_pilot_median: float = 0.0
	for block: int in 2 * BLOCKS + 1:  # block 0 is the warm-up, on AiPilot
		var on_pilots: bool = block % 2 == 1 or block == 0
		var brains: Array[PilotBrain] = pilots if on_pilots else m2
		for i: int in ships.size():
			ships[i].driver.brain = brains[i]
		var skip: int = WARM_UP_TICKS if block == 0 else SETTLE_TICKS
		var start: int = sampler.samples.size() + skip
		while sampler.samples.size() < start + (BLOCK_TICKS if block > 0 else 0):
			await get_tree().physics_frame
		if block == 0:
			continue
		var samples: PackedInt64Array = sampler.samples.slice(start, start + BLOCK_TICKS)
		(ai_samples if on_pilots else m2_samples).append_array(samples)
		var block_median: float = _median(samples)
		block_medians.append("%s %.0f" % ["AiPilot" if on_pilots else "M2", block_median])
		if on_pilots:
			last_pilot_median = block_median
		else:
			pair_differences.append(last_pilot_median - block_median)
	var ai_median: float = _median(ai_samples)
	var m2_median: float = _median(m2_samples)
	var sorted_differences: Array = Array(pair_differences)
	sorted_differences.sort()
	var paired: float = (float(sorted_differences[BLOCKS / 2 - 1]) + float(sorted_differences[BLOCKS / 2])) / 2.0
	gut.p("AI think time, 13 ships in one fight, %d alternating blocks of %d ticks: AiPilot median %.0f us (mean %.0f), M2 AttackBrain median %.0f us (mean %.0f); paired difference (median over the block pairs) %+.0f us, difference of the medians %+.0f us; block medians %s; %d bolts in flight" % [
			2 * BLOCKS, BLOCK_TICKS, ai_median, _mean(ai_samples), m2_median, _mean(m2_samples), paired,
			ai_median - m2_median, ", ".join(block_medians), get_tree().get_nodes_in_group(Projectile.GROUP).size()])
	assert_lte(paired, PILOT_SHARE_US, "AiPilot within its 0.5 ms share over the M2 brains")
