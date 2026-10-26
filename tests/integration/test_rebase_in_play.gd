extends GutTest
## Position rebase in play (M3-T14, AC21, maintainer Q13, architecture §14.1): the main scene keeps the World's local origin
## within 5 km of the player, so far from the launch point the ship moves as smoothly as near it. A bare `WorldFrame` keeps the
## rebase off (`test_world_frame`).

## Ticks of full main thrust measured, after `SETTLE_TICKS` for the pods to spool up.
const SETTLE_TICKS: int = 20
const MEASURE_TICKS: int = 60
## The low-threshold sandbox fight: sim time is `SPEED_UP` x wall time (each physics step is SPEED_UP / 60 s).
const SPEED_UP: float = 4.0
const FIGHT_S: float = 240.0
const FIGHT_WAVES: int = 2

var main: Main
var source: FakeInputSource
var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	ContactScan.invalidate()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false
	ContactScan.invalidate()


func _launch(scenario: String = ScenarioLoader.FREE_FLIGHT_PATH) -> void:
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	if not scenario.is_empty():
		main.scenario_path = scenario
	add_child_autofree(main)
	await _ticks(2)


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


## The player's universe position at the start of each of `n` ticks (before anything moves in it), under full main thrust.
func _thrust_track(n: int) -> Array[UniversePos]:
	var track: Array[UniversePos] = []
	for i: int in n:
		await get_tree().physics_frame  # resumes at the start of a tick, after Jolt's last step was synced
		track.append(main.world.to_universe(main.ship.global_position))
	return track


## The tick-to-tick change of step of a universe track, `(u[k] - u[k-1]) - (u[k-1] - u[k-2])`, summed in 64-bit: under constant
## thrust it is constant (a dt^2), so its spread around the mean is the float32 jitter. {max_m, rms_m, mean_m}.
static func change_of_step(track: Array[UniversePos]) -> Dictionary:
	var c: Array[PackedFloat64Array] = []
	for k: int in range(2, track.size()):
		var a: UniversePos = track[k - 2]
		var b: UniversePos = track[k - 1]
		var d: UniversePos = track[k]
		c.append(PackedFloat64Array([d.x - 2.0 * b.x + a.x, d.y - 2.0 * b.y + a.y, d.z - 2.0 * b.z + a.z]))
	var mean := PackedFloat64Array([0.0, 0.0, 0.0])
	for v: PackedFloat64Array in c:
		for i: int in 3:
			mean[i] += v[i] / float(c.size())
	var worst: float = 0.0
	var sum_sq: float = 0.0
	for v: PackedFloat64Array in c:
		var dx: float = v[0] - mean[0]
		var dy: float = v[1] - mean[1]
		var dz: float = v[2] - mean[2]
		var e: float = sqrt(dx * dx + dy * dy + dz * dz)
		worst = maxf(worst, e)
		sum_sq += e * e
	return {"max_m": worst, "rms_m": sqrt(sum_sq / float(c.size())),
			"mean_m": sqrt(mean[0] * mean[0] + mean[1] * mean[1] + mean[2] * mean[2])}


## Every ship in play, prop and bolt in flight: instance id -> {name, u (UniversePos), v (World-frame velocity)}.
func _snapshot() -> Dictionary:
	var out: Dictionary = {}
	var ships: Array[Combatant] = main.ships.alive()
	ships.append(main.combatant)
	for c: Combatant in ships:
		out[c.ship.get_instance_id()] = {"name": c.display_name, "u": main.world.to_universe(c.ship.global_position),
				"v": c.ship.linear_velocity}
	for buoy: NavBuoy in main.buoys:
		out[buoy.get_instance_id()] = {"name": buoy.name, "u": main.world.to_universe(buoy.global_position), "v": buoy.velocity}
	for node: Node in get_tree().get_nodes_in_group(Projectile.GROUP):
		var bolt := node as Projectile
		if bolt != null and not bolt.is_spent() and not bolt.is_queued_for_deletion():
			out[bolt.get_instance_id()] = {"name": "bolt", "u": main.world.to_universe(bolt.global_position), "v": bolt.velocity}
	return out


## The largest change of universe position and of velocity from `before` to `after`, over what both hold: {du, dv, count}.
static func _largest_change(before: Dictionary, after: Dictionary) -> Dictionary:
	var du: float = 0.0
	var dv: float = 0.0
	var count: int = 0
	for id: int in before:
		if not after.has(id):
			continue
		count += 1
		du = maxf(du, (before[id]["u"] as UniversePos).distance_to(after[id]["u"] as UniversePos))
		dv = maxf(dv, ((before[id]["v"] as Vector3) - (after[id]["v"] as Vector3)).length())
	return {"du": du, "dv": dv, "count": count}


func test_rebase_900_km_out_comes_back_on_the_next_tick_with_every_universe_position_kept() -> void:
	await _launch(ScenarioLoader.SANDBOX_PATH)
	assert_true(_exec("wing replenish").ok, "three wingmen 1 500 m astern")
	assert_true(_exec("spawn raider ai 1500").ok)
	assert_true(_exec("spawn raider idle 900 30 10").ok)
	main.ship.linear_velocity = Vector3(40.0, -10.0, -120.0)
	source.hold(InputAdapter.FIRE)
	await _ticks(30)
	source.release(InputAdapter.FIRE)
	var at_rebase: Array[Dictionary] = []
	main.world.rebased.connect(func(_offset: Vector3) -> void:
		# Inside the rebase, before anything in its tick has moved.
		at_rebase.append({"snapshot": _snapshot(), "player_local": main.ship.global_position}))
	var rebases_before: int = main.world.rebases
	await get_tree().physics_frame  # the start of a tick: Jolt's last step is in, nothing of this tick has run
	var before_command: Dictionary = _snapshot()
	assert_true(_exec("rebase -900000 0 0").ok)
	var after_command: Dictionary = _snapshot()
	assert_gt(main.ship.global_position.length(), 899000.0, "the console put everything 900 km from the local origin")
	assert_eq(at_rebase.size(), 1)
	await _ticks(1)
	assert_eq(main.world.rebases, rebases_before + 2, "the console's rebase and, in the same tick, the automatic one")
	assert_eq(at_rebase.size(), 2)
	var back: Dictionary = at_rebase[1]
	assert_lt((back["player_local"] as Vector3).length(), 5000.0, "the player is back near the local origin")
	assert_lt((back["player_local"] as Vector3).length(), 1e-3, "on it, in fact: the rebase re-centres on the player")
	var change: Dictionary = _largest_change(after_command, back["snapshot"])
	var rounding: Dictionary = _largest_change(before_command, after_command)
	var bolts: int = 0
	for id: int in after_command:
		bolts += 1 if after_command[id]["name"] == "bolt" else 0
	gut.p("rebase -900000 0 0: %d ships, props and bolts (%d bolts); the automatic rebase back moved them by at most %.6f mm and %.6f mm/s; the console's own shift to 900 km rounded them by up to %.1f mm (float32 at 900 km); rebase cost %d us" % [
			change["count"], bolts, float(change["du"]) * 1000.0, float(change["dv"]) * 1000.0, float(rounding["du"]) * 1000.0,
			main.world.last_rebase_us])
	assert_gt(bolts, 0, "bolts in flight")
	assert_eq(int(change["count"]), after_command.size(), "the same things before and after")
	assert_gt(int(change["count"]), 10, "the player, three wingmen, two raiders, five buoys and the bolts")
	assert_lt(float(change["du"]), 1e-3, "every universe position kept to 1 mm")
	assert_lt(float(change["dv"]), 1e-3, "every velocity kept to 1 mm/s")
	# From inside the rebase to the start of the tick after next, two steps: the ship flew on at its velocity, in universe terms.
	var player_back: Dictionary = (back["snapshot"] as Dictionary)[main.ship.get_instance_id()]
	await _ticks(1)
	var flown: float = (player_back["u"] as UniversePos).distance_to(main.world.to_universe(main.ship.global_position))
	assert_almost_eq(flown, 2.0 * (player_back["v"] as Vector3).length() / float(Engine.physics_ticks_per_second), 0.01,
			"two ticks of its own motion, no jump")
	assert_lt(main.ship.global_position.length(), 5000.0)


func test_a_sandbox_fight_with_wingmen_rebasing_every_second_clears_its_waves() -> void:
	await _launch(ScenarioLoader.SANDBOX_PATH)
	assert_true(_exec("wing order engage").ok, "the wingmen hunt the raiders")
	assert_true(_exec("wave start 1").ok, "the wingmen launch when it starts")
	source.hold(InputAdapter.FIRE)
	Engine.time_scale = SPEED_UP
	var fight: RebaseFight = await RebaseFight.run(self, main, FIGHT_S,
			func() -> bool: return main.waves.plan.wave_number >= FIGHT_WAVES + 1)
	Engine.time_scale = 1.0
	source.release(InputAdapter.FIRE)
	gut.p("sandbox fight, rebase threshold 40 m: " + fight.summary())
	assert_gt(main.waves.plan.wave_number, FIGHT_WAVES, "waves 1 to %d cleared through the rebases" % FIGHT_WAVES)
	assert_gt(fight.kills, 0, "raiders shot down")
	assert_gt(fight.hits, 10, "bolts still hit")
	assert_gt(fight.hits_in_rebase_ticks, 0, "some of them in the very tick of a rebase")
	assert_eq(main.wings.player_wing().members().size(), 3, "the wing flew the whole fight")
	# AC21: one rebase of the full sandbox (pools, wing, raiders, bolts, debris, voices) under 0.5 ms. Wall clock, so the median
	# over the fight is asserted and the spread recorded.
	assert_lt(fight.median_rebase_us(), 500, "a rebase of the full sandbox costs %d us (median; min %d, max %d)" % [
			fight.median_rebase_us(), fight.min_rebase_us(), fight.max_rebase_us()])


func test_flying_at_full_speed_through_5_km_rebases_leaves_nothing_behind() -> void:
	# The main scene's own threshold, crossed every 1.25 s at 4 000 m/s, with an explosion, debris and bolts in flight: a node
	# left interpolating across a 5 km jump would be drawn kilometres from where it is.
	await _launch(ScenarioLoader.SANDBOX_PATH)
	assert_true(_exec("wave stop").ok)
	assert_true(_exec("spawn raider idle 80").ok)
	assert_true(_exec('set targeting.selected "RAIDER 1"').ok)
	assert_true(_exec("kill target").ok, "an explosion and its debris")
	source.hold(InputAdapter.FIRE)
	Engine.time_scale = SPEED_UP
	var fight: RebaseFight = await RebaseFight.run(self, main, 6.0, Callable(), main.world.auto_rebase_distance_m, 4000.0)
	Engine.time_scale = 1.0
	source.release(InputAdapter.FIRE)
	gut.p("4 000 m/s through 5 km rebases: " + fight.summary())
	assert_gte(fight.rebases, 4)
	assert_gt(fight.snaps_checked, 0, "frames after a rebase were checked")
	assert_eq(main.world.auto_rebase_distance_m, 5000.0, "the fixture put the threshold back")


func test_the_main_scene_rebases_at_5_km() -> void:
	await _launch()
	assert_eq(main.world.auto_rebase_distance_m, 5000.0, "main.tscn turns the rebase on at 5 km")
	assert_eq(main.world.focus, main.ship, "on the player")
	var bare := WorldFrame.new()
	assert_eq(bare.auto_rebase_distance_m, 0.0, "a bare WorldFrame keeps it off")
	bare.free()


func test_thrusting_900_km_out_has_no_float32_jitter() -> void:
	await _launch()
	# Today's build (Q13): the threshold at 0, so `rebase -900000 0 0` leaves the ship 900 km from the local origin.
	var threshold: float = main.world.auto_rebase_distance_m
	main.world.auto_rebase_distance_m = 0.0
	# The nose off every axis, so the thrust moves the coordinate that is 900 km long too ("in any direction", AC22).
	main.ship.reset_to(Transform3D(Basis.looking_at(Vector3(1.0, 0.5, -1.0).normalized()), main.ship.global_position))
	await get_tree().physics_frame
	assert_true(_exec("rebase -900000 0 0").ok)
	main.debug_throttle = 1.0
	await _ticks(SETTLE_TICKS)
	assert_gt(main.ship.global_position.length(), 899000.0, "without the rebase the ship stays 900 km out")
	var without: Dictionary = change_of_step(await _thrust_track(MEASURE_TICKS))
	# The main scene's own threshold: the next tick brings the ship back near the origin, and it thrusts on.
	main.world.auto_rebase_distance_m = threshold
	await _ticks(2)
	assert_lt(main.ship.global_position.length(), 5000.0, "back within 5 km of the local origin")
	var with_rebase: Dictionary = change_of_step(await _thrust_track(MEASURE_TICKS))
	main.debug_throttle = 0.0
	gut.p("change of step under full main thrust 900 km out: without the rebase max %.2f mm (rms %.2f), with it max %.4f mm (rms %.4f); a dt^2 = %.2f mm" % [
			float(without["max_m"]) * 1000.0, float(without["rms_m"]) * 1000.0, float(with_rebase["max_m"]) * 1000.0,
			float(with_rebase["rms_m"]) * 1000.0, float(with_rebase["mean_m"]) * 1000.0])
	assert_gt(float(without["max_m"]), 0.02, "the float32 jitter the maintainer saw (about 5 cm)")
	assert_lt(float(with_rebase["max_m"]), 0.002, "under 2 mm with the rebase")
