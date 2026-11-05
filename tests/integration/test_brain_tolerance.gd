extends GutTest
## Q16's tolerance for the native brains (M4-T17b, architecture §17.13): a seeded 30 s fight (the bench's `furball` and
## `spread` layouts at 50 ships, seeds 1 to 3, every fighter on its layout profile and invulnerable as the bench flies them)
## with the native brains against the same fight on the GDScript brains gives bolt hits within 10 %, a behaviour mix within
## 5 points, and no ship more than 50 m from its twin at 10 s. The real ships, drivers, resolver and Jolt, each fight in a
## space of its own. Skips, saying why, when the library is not built.

const LAYOUTS: Array[StringName] = [BenchLayout.FURBALL, BenchLayout.SPREAD]
const SHIPS: int = 50
const SEEDS: Array[int] = [1, 2, 3]
const TICKS: int = 1800
const COMPARE_AT_TICK: int = 600
const SAMPLE_EVERY: int = 5
const HITS_TOLERANCE: float = 0.10
const MIX_TOLERANCE: float = 0.05
const TWIN_DISTANCE_M: float = 50.0
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"sim_step"]

var _saved: Dictionary = {}


# A slow file (M4-T36, Q58): runs with GUT_SLOW=1 (the full run and CI), skipped in focused runs.
@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"perf_native_core", true)
	# The GDScript twin thinks in the same tick, so the native fight is paired on the inline step (the one-tick handover is
	# test_core_snapshot's; M4-T24).
	Settings.set_value(&"sim_step", &"inline")
	Factions.reset()
	ContactScan.invalidate()


func after_each() -> void:
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	Factions.reset()
	ContactScan.invalidate()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no native brains to test")
	return true


func test_native_brains_stay_within_q16s_tolerance_on_every_seed() -> void:
	if _skipped():
		return
	for layout: StringName in LAYOUTS:
		for seed_value: int in SEEDS:
			var native: Dictionary = await _fight(layout, seed_value, true)
			var reference: Dictionary = await _fight(layout, seed_value, false)
			var label: String = "%s %d seed %d" % [layout, SHIPS, seed_value]
			assert_gt(int(native["native_thinks"]), 0, "%s: the native brains thought" % label)
			assert_eq(int(native["native_thinks"]), int(native["thinks"]), "%s: every think of the native fight was native" % label)
			assert_eq(int(native["fallbacks"]), 0, "%s: the host declined no think" % label)
			assert_eq(int(reference["native_thinks"]), 0, "%s: the reference never did" % label)
			var hits_n: int = native["hits"]
			var hits_g: int = reference["hits"]
			var mix_n: Dictionary = native["mix"]
			var mix_g: Dictionary = reference["mix"]
			var worst_mix: float = 0.0
			var worst_id: String = ""
			for id: String in AiPilot.TIE_ORDER:
				var d: float = absf(float(mix_n.get(id, 0.0)) - float(mix_g.get(id, 0.0)))
				if d > worst_mix:
					worst_mix = d
					worst_id = id
			var twins: PackedVector3Array = native["at_10s"]
			var twins_g: PackedVector3Array = reference["at_10s"]
			var farthest: float = 0.0
			for i: int in mini(twins.size(), twins_g.size()):
				farthest = maxf(farthest, twins[i].distance_to(twins_g[i]))
			gut.p("%s: hits native %d against %d; mix native %s against %s (worst %s %.3f); farthest twin at 10 s %.2f m; %d native thinks" % [
					label, hits_n, hits_g, mix_n, mix_g, worst_id, worst_mix, farthest, int(native["native_thinks"])])
			assert_lte(absf(float(hits_n - hits_g)), HITS_TOLERANCE * float(maxi(hits_g, 1)), "%s: hits within 10 %% (%d against %d)" % [label, hits_n, hits_g])
			assert_lte(worst_mix, MIX_TOLERANCE, "%s: the behaviour mix within 5 points (%s differs by %.3f)" % [label, worst_id, worst_mix])
			assert_lte(farthest, TWIN_DISTANCE_M, "%s: no ship more than 50 m from its twin at 10 s (%.2f m)" % [label, farthest])
			assert_eq(twins.size(), SHIPS, "%s: every ship compared" % label)


## The seeded fight: `layout` at `SHIPS` ships for `seed_value`, 30 s, with the native brains on or off. Returns the bolt hits,
## the behaviour mix (shares of ship-samples by behaviour), every ship's position at 10 s (in plan order) and the native
## thinks counted.
func _fight(layout: StringName, seed_value: int, native: bool) -> Dictionary:
	Settings.set_value(&"perf_native_brains", native)
	Factions.reset()
	ContactScan.invalidate()
	await get_tree().process_frame
	await get_tree().physics_frame
	SimClock.reset()  # the same clock for both fights: a hit's reaction edge rounds with the absolute time
	var space := SubViewport.new()
	space.own_world_3d = true
	space.world_3d = World3D.new()
	add_child(space)
	var world := WorldFrame.new()
	world.name = "World"
	space.add_child(world)
	var bolts := Node3D.new()
	bolts.name = "Projectiles"
	world.add_child(bolts)
	var resolver := HitResolver.new()
	resolver.name = "HitResolver"
	space.add_child(resolver)
	var hits: Array[int] = [0]
	resolver.hit_resolved.connect(func(_info: HitInfo) -> void: hits[0] += 1)
	var anchor: UniversePos = world.to_universe(Vector3.ZERO)
	var plan: Array[Dictionary] = BenchLayout.plan(layout, SHIPS, seed_value)
	var ships: Array[Combatant] = []
	var numbers: Dictionary = {ShipPool.ALLY_TYPE: ShipPool.ALLY_FIRST_NUMBER, ShipPool.DEFAULT_TYPE: 1}
	for e: Dictionary in plan:
		if StringName(e["kind"]) != BenchLayout.KIND_FIGHTER:
			continue
		var type: StringName = e["type"]
		var prefix: String = ShipPool.ALLY_NAME_PREFIX if type == ShipPool.ALLY_TYPE else ShipPool.NAME_PREFIX
		var ship_name: String = "%s %d" % [prefix, int(numbers[type])]
		numbers[type] = int(numbers[type]) + 1
		var c: Combatant = ShipAssembly.build(ShipCatalog.spec_for(type), world, bolts, {
			ShipAssembly.OPT_FACTION: StringName(e["faction"]), ShipAssembly.OPT_DISPLAY_NAME: ship_name,
			ShipAssembly.OPT_FORCE_ASSIST: true, ShipAssembly.OPT_AI: true, ShipAssembly.OPT_LEAN: true})
		world.spawn(c.ship, anchor.plus_local(e["offset"]), e["basis"])
		c.ship.linear_velocity = e["velocity"]
		if type == ShipPool.ALLY_TYPE:
			c.targetable.broadcast_range_m = ShipPool.ALLY_BROADCAST_RANGE_M
		var made: Dictionary = BrainFactory.from_behaviour(e["behaviour"], anchor, int(e["seed"]))
		assert_true(bool(made["ok"]), "%s: a brain for %s" % [layout, ship_name])
		c.driver.brain = made["brain"] as PilotBrain
		c.damageable.invulnerable = true
		ships.append(c)
	var samples: Dictionary = {}
	var sampled: int = 0
	var at_10s := PackedVector3Array()
	var native_thinks: int = 0
	var thinks: int = 0
	var fallbacks: int = 0
	for tick: int in TICKS:
		await get_tree().physics_frame
		native_thinks += AiPilotDriver.thinks_native()
		thinks += AiPilotDriver.thinks_near() + AiPilotDriver.thinks_far()
		fallbacks += AiPilotDriver.thinks_fallback()
		if tick % SAMPLE_EVERY == 0:
			for c: Combatant in ships:
				var pilot := c.driver.brain as AiPilot
				var id: String = String(pilot.current.id) if pilot != null and pilot.current != null else "none"
				samples[id] = int(samples.get(id, 0)) + 1
				sampled += 1
		if tick == COMPARE_AT_TICK - 1:
			for c: Combatant in ships:
				at_10s.append(c.ship.global_position)
	var mix: Dictionary = {}
	for id: String in samples:
		mix[id] = float(samples[id]) / float(maxi(sampled, 1))
	space.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return {"hits": hits[0], "mix": mix, "at_10s": at_10s, "native_thinks": native_thinks, "thinks": thinks, "fallbacks": fallbacks}
