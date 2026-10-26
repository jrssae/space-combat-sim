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
	var snapshot_us: PackedInt64Array = PackedInt64Array([0])  # this handler's own time, which the rebase cost counts
	main.world.rebased.connect(func(_offset: Vector3) -> void:
		# Inside the rebase, before anything in its tick has moved.
		var started_us: int = Time.get_ticks_usec()
		at_rebase.append({"snapshot": _snapshot(), "player_local": main.ship.global_position})
		snapshot_us[0] = Time.get_ticks_usec() - started_us)
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
	gut.p("rebase -900000 0 0: %d ships, props and bolts (%d bolts); the automatic rebase back moved them by at most %.6f mm and %.6f mm/s; the console's own shift to 900 km rounded them by up to %.1f mm (float32 at 900 km); rebase cost %d us (without this test's snapshot in its handler)" % [
			change["count"], bolts, float(change["du"]) * 1000.0, float(change["dv"]) * 1000.0, float(rounding["du"]) * 1000.0,
			main.world.last_rebase_us - snapshot_us[0]])
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


## Every rendered frame, after the cameras and the HUD: the player, one of its bolts and NAV ALPHA as drawn (interpolated) in the
## chase camera's frame, and NAV ALPHA where the HUD puts it (its tick position through the HUD's camera).
class ViewSampler extends Node:
	var main: Main = null
	var bolt: Projectile = null
	var buoy: NavBuoy = null
	var rows: Array[Dictionary] = []

	func _init() -> void:
		process_priority = 3000

	func _process(_delta: float) -> void:
		if bolt == null or not is_instance_valid(bolt) or bolt.is_queued_for_deletion():
			return
		var view: Transform3D = main.camera_rig.chase_camera.global_transform.affine_inverse()
		var hud_view: Transform3D = (main.hud.input_provider.call() as HudInput).camera_transform.affine_inverse()
		var ship_drawn: Vector3 = main.ship.get_global_transform_interpolated().origin
		rows.append({"tick": Engine.get_physics_frames(), "f": Engine.get_physics_interpolation_fraction(),
				"ship_u": main.world.to_universe(ship_drawn), "speed": main.ship.linear_velocity.length(),
				"v_rel": view.basis * (bolt.velocity - main.ship.linear_velocity), "ship": view * ship_drawn,
				"bolt": view * bolt.get_global_transform_interpolated().origin,
				"buoy": view * buoy.get_global_transform_interpolated().origin, "buoy_hud": hud_view * buoy.global_position,
				"pivot": view * main.camera_rig.cockpit_pivot.get_global_transform_interpolated().origin})


func test_through_a_rebase_at_full_speed_the_view_keeps_the_ship_its_bolts_and_the_hud_together() -> void:
	# AC22 at 5 000 m/s, nose up (clear of the buoys): a 5 km rebase every second. Every rendered frame, the rebase ticks
	# included: the chase camera stays on the drawn ship (1 cm); a bolt flying ahead keeps its motion relative to the ship (its
	# offset from the ship in the view changes by its relative velocity times the time the ship was drawn to advance, to 1 m);
	# and the HUD's camera sees NAV ALPHA where it is drawn (1 m).
	await _launch()
	var speed: float = 5000.0
	main.ship.reset_to(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), main.ship.position))
	main.ship.linear_velocity = main.ship.forward() * speed
	main.camera_rig.snap_chase()
	source.hold(InputAdapter.FIRE)
	await _ticks(3)
	source.release(InputAdapter.FIRE)
	var sampler := ViewSampler.new()
	sampler.main = main
	sampler.buoy = main.buoys[0]
	for node: Node in get_tree().get_nodes_in_group(Projectile.GROUP):
		sampler.bolt = node as Projectile  # the newest one
	assert_not_null(sampler.bolt, "a bolt flies alongside")
	var rebase_ticks: Array[int] = []
	var on_rebased := func(_offset: Vector3) -> void: rebase_ticks.append(Engine.get_physics_frames())
	main.world.rebased.connect(on_rebased)
	add_child_autofree(sampler)
	await _ticks(90)
	sampler.bolt = null
	main.world.rebased.disconnect(on_rebased)
	assert_gte(rebase_ticks.size(), 1, "the run crossed a 5 km rebase")
	var worst_rel: float = 0.0
	var worst_rel_rebase: float = 0.0
	var worst_camera: float = 0.0
	var worst_cockpit: float = 0.0
	var worst_hud: float = 0.0
	var worst_hud_rebase: float = 0.0
	var frames_in_rebase_ticks: int = 0
	var lines: PackedStringArray = []
	for k: int in range(1, sampler.rows.size()):
		var a: Dictionary = sampler.rows[k - 1]
		var b: Dictionary = sampler.rows[k]
		var drawn_s: float = (a["ship_u"] as UniversePos).distance_to(b["ship_u"] as UniversePos) / float(b["speed"])
		var rel_change: Vector3 = ((b["bolt"] as Vector3) - (b["ship"] as Vector3)) - ((a["bolt"] as Vector3) - (a["ship"] as Vector3))
		var expected: Vector3 = ((a["v_rel"] as Vector3) + (b["v_rel"] as Vector3)) * 0.5 * drawn_s
		var rel_error: float = rel_change.distance_to(expected)
		var hud_error: float = (b["buoy_hud"] as Vector3).distance_to(b["buoy"] as Vector3)
		var camera: float = (b["ship"] as Vector3).distance_to(a["ship"] as Vector3)
		worst_rel = maxf(worst_rel, rel_error)
		worst_hud = maxf(worst_hud, hud_error)
		worst_camera = maxf(worst_camera, camera)
		worst_cockpit = maxf(worst_cockpit, ((b["pivot"] as Vector3) - (b["ship"] as Vector3)).distance_to(
				(a["pivot"] as Vector3) - (a["ship"] as Vector3)))
		var in_rebase_tick: bool = rebase_ticks.has(int(b["tick"]))
		if in_rebase_tick:
			frames_in_rebase_ticks += 1
			worst_rel_rebase = maxf(worst_rel_rebase, rel_error)
			worst_hud_rebase = maxf(worst_hud_rebase, hud_error)
		if (in_rebase_tick or rebase_ticks.has(int(a["tick"]))) and lines.size() < 16:
			lines.append("tick %d f %.2f%s: ship drawn on %.1f m, bolt offset changed %.2f m (expected %.2f m, off by %.2f m), HUD off %.2f m" % [
					b["tick"], b["f"], " (rebase tick)" if in_rebase_tick else "", drawn_s * float(b["speed"]), rel_change.length(),
					expected.length(), rel_error, hud_error])
	gut.p("%d frames, %d rebases (ticks %s), %d frames drawn after a rebase tick; bolt off its relative motion: worst %.3f m (%.3f m after a rebase tick); HUD vs drawn NAV ALPHA: worst %.3f m (%.3f m); chase camera drift %.4f m; cockpit pivot drift from the drawn ship %.4f m" % [
			sampler.rows.size(), rebase_ticks.size(), str(rebase_ticks), frames_in_rebase_ticks, worst_rel, worst_rel_rebase, worst_hud,
			worst_hud_rebase, worst_camera, worst_cockpit])
	for line: String in lines:
		gut.p("  " + line)
	assert_gt(sampler.rows.size(), 60, "frames were sampled")
	assert_gt(frames_in_rebase_ticks, 0, "frames were drawn between a rebase tick and the next")
	assert_lt(worst_camera, 0.01, "the chase camera stays locked to the drawn ship")
	assert_lt(worst_cockpit, 0.01, "so does the cockpit camera's pivot")
	assert_lt(worst_rel, 1.0, "the bolt keeps its motion relative to the ship through the rebase")
	assert_lt(worst_hud, 1.0, "the HUD projects NAV ALPHA where it is drawn")


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


func test_thrusting_through_an_automatic_5_km_rebase_keeps_the_step_smooth() -> void:
	# One change-of-step window that spans the main scene's own rebase: nose and velocity along +x, 4 800 m out along it, under
	# full main thrust, so the ship crosses 5 km inside the window. A rebase that moved anything in universe terms would show as
	# a jump in the step.
	await _launch()
	main.ship.reset_to(Transform3D(Basis.looking_at(Vector3.RIGHT), main.ship.global_position))
	await get_tree().physics_frame
	assert_true(_exec("rebase -4800 0 0").ok, "everything 4 800 m out along +x")
	main.ship.linear_velocity = Vector3.RIGHT * 300.0
	main.debug_throttle = 1.0
	await _ticks(SETTLE_TICKS)
	var rebases_before: int = main.world.rebases
	assert_lt(main.ship.global_position.length(), 5000.0, "not across yet")
	var change: Dictionary = change_of_step(await _thrust_track(MEASURE_TICKS))
	main.debug_throttle = 0.0
	gut.p("change of step under full main thrust across the 5 km rebase: max %.4f mm (rms %.4f); a dt^2 = %.2f mm" % [
			float(change["max_m"]) * 1000.0, float(change["rms_m"]) * 1000.0, float(change["mean_m"]) * 1000.0])
	assert_eq(main.world.rebases, rebases_before + 1, "the window spans one automatic rebase")
	assert_lt(main.ship.global_position.length(), 5000.0)
	assert_lt(float(change["max_m"]), 0.002, "under 2 mm across it")


func test_a_still_player_rebases_on_the_fixture_timer() -> void:
	# For scenes whose player sits still (T09's routes, T10's guard posts): `rebase_every_s` forces the rebases.
	await _launch(ScenarioLoader.SANDBOX_PATH)
	assert_true(_exec("wave stop").ok)
	assert_true(_exec("spawn raider idle 600").ok, "something else in the world")
	main.ship.linear_velocity = Vector3.ZERO
	Engine.time_scale = SPEED_UP
	var fight: RebaseFight = await RebaseFight.run(self, main, 4.0, Callable(), 40.0, 0.0, 0.5)
	Engine.time_scale = 1.0
	gut.p("a still player, a rebase forced every 0.5 s: " + fight.summary())
	assert_gte(fight.forced_rebases, 6, "forced every 0.5 s of sim time")
	assert_lt(fight.max_gap_s, 0.6)
	assert_lt(main.ship.linear_velocity.length(), 1e-3, "the player sat still")
