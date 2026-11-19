extends GutTest
## The gate jump's camera takes against the real gate (M8-T29): every take in the pools keeps its camera clear of the gate's arms
## and in sight of the ship, along the predicted run-in at several ways the line-up can hand the ship over (roll, offset from the
## axis, speed) and along the way back out; a camera inside an arm, or a planet over the gate, rules a take out; a whole jump is
## cut into takes under 3 s, never the same take twice in a row, the entry held by a take made for it, and the ring's flash ends
## the run-in's last take with a hard cut to the arrival side.

var main: Main
var gate: Jumpgate


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	if main != null and is_instance_valid(main):
		main.gates.jump_gate = null
	ContactScan.invalidate()


func _start() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 0
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	for i: int in 3:
		await get_tree().physics_frame
	gate = main.gates.gate()
	main.gates.jump_gate = gate


# The ship where the line-up hands it to the run-in: the departure point, `side_m` off the axis, rolled `roll_deg`, at `speed`.
func _hand_over(roll_deg: float, side_m: float, speed: float) -> Dictionary:
	var at: Vector3 = gate.global_transform * (gate.departure_point + Vector3(side_m, 0.0, 0.0))
	var axis: Vector3 = (gate.global_basis * gate.departure_forward).normalized()
	var nose := Basis.looking_at(axis, gate.global_basis.y).rotated(axis, deg_to_rad(roll_deg))
	main.ship.reset_to(Transform3D(nose, at))
	main.ship.linear_velocity = main.world.anchored_velocity() + axis * speed
	await get_tree().physics_frame
	main.ship.linear_velocity = main.world.anchored_velocity() + axis * speed
	return main.gates._shot_context(main.gates._predicted_arrival_s())


func test_every_take_keeps_clear_at_several_hand_overs() -> void:
	await _start()
	var pool: GateShotPool = main.gates.shots.pool
	for case: Array in [[0.0, 0.0, 250.0], [90.0, 0.0, 250.0], [180.0, 120.0, 80.0], [-45.0, -150.0, 300.0], [30.0, 60.0, 150.0]]:
		var ctx: Dictionary = await _hand_over(case[0], case[1], case[2])
		for slot: StringName in [GateShotPool.APPROACH, GateShotPool.MOUTH]:
			for id: String in pool.ids(slot):
				assert_true(main.gates.shots.is_clear(slot, id, ctx), "%s %s clear: roll %.0f, %.0f m off, %.0f m/s (arrival %.1f s)" % [
						slot, id, case[0], case[1], case[2], float(ctx["arrival_s"])])
	var back: Dictionary = main.gates._arrival_context()
	for slot: StringName in [GateShotPool.ARRIVAL_OPEN, GateShotPool.ARRIVAL_OUT]:
		for id: String in pool.ids(slot):
			assert_true(main.gates.shots.arrival_clear(slot, id, back), "%s %s clear" % [slot, id])


func test_a_camera_in_an_arm_or_a_planet_over_the_gate_rules_takes_out() -> void:
	await _start()
	var ctx: Dictionary = await _hand_over(0.0, 0.0, 250.0)
	var space: PhysicsDirectSpaceState3D = ctx["space"]
	var arm: CollisionShape3D = null
	for child: Node in gate.collision_body.get_children():
		if child is CollisionShape3D:
			arm = child
			break
	assert_not_null(arm, "the gate's arms collide")
	assert_true(GateShotDirector._inside(space, arm.global_position, main.ship), "a camera in an arm is inside")
	assert_false(GateShotDirector._inside(space, gate.global_transform * Vector3(0.0, 0.0, -3000.0), main.ship), "in front is clear")
	var planet := ReferenceFrame.Candidate.new()
	planet.position = gate.global_position
	planet.radius_m = 6000.0
	var under: Dictionary = ctx.duplicate()
	under["planet"] = planet
	for id: String in main.gates.shots.pool.ids(GateShotPool.APPROACH):
		assert_false(main.gates.shots.is_clear(GateShotPool.APPROACH, id, under), "%s inside a planet: ruled out" % id)


# A whole jump's cutting, from the predicted run-in to control's return, on the director's clock: every take under 3 s.
func test_a_jump_is_cut_into_short_takes_that_never_repeat_back_to_back() -> void:
	await _start()
	var ctx: Dictionary = await _hand_over(0.0, 0.0, 250.0)
	var back: Dictionary = main.gates._arrival_context()
	var arrival: float = ctx["arrival_s"]
	var director := GateShotDirector.new()
	var features := PackedStringArray()  # shot ids allowed up to 5 s
	for slot: StringName in GateShotPool.SLOTS:
		for id: String in director.pool.ids(slot):
			if director.pool.is_feature(slot, id):
				features.append("gate_%s_%s" % [slot, id])
	var openings: Array[String] = []
	for jump: int in 8:
		var starts: Array[float] = []
		var limits: Array[float] = []
		var play: Callable = func(shot: CinematicShot) -> void:
			starts.append(director.clock_s)
			limits.append(5.0 if String(shot.id) in features else 3.0)
		var dt: float = 1.0 / 60.0
		openings.append(director.begin(ctx, play))
		while director.clock_s < arrival + GateShotDirector.FUNNEL_S:
			director.tick(dt, play)
		var takes_before_ring: int = director.played.size()
		director.on_through(play)
		for i: int in roundi(GateJump.RING_HOLD_S / dt):
			director.tick(dt, play)
		assert_eq(director.played.size(), takes_before_ring, "jump %d: no cut during the ring's flash" % jump)
		_assert_short(starts, limits, director.clock_s, "jump %d run-in" % jump)
		starts.clear()
		limits.clear()
		director.begin_arrival(back, play)
		for i: int in roundi(GateShotDirector.OPEN_S / dt):
			director.tick(dt, play)
		_assert_short(starts, limits, director.clock_s, "jump %d opening" % jump)
		starts.clear()
		limits.clear()
		for i: int in roundi(12.0 / dt):
			director.on_placed(play)  # the host asks every tick once the ship is out; it cuts when the take on screen has had 1 s
			director.tick(dt, play)
		_assert_short(starts, limits, director.clock_s, "jump %d way out" % jump)
		var takes: PackedStringArray = director.sequence()
		for i: int in range(1, takes.size()):
			assert_ne(takes[i], takes[i - 1], "jump %d: %s twice in a row" % [jump, takes[i]])
		var mouth_at: float = -1.0
		var entry_take: String = ""
		for take: Dictionary in director.played:
			if take["slot"] == GateShotPool.MOUTH and mouth_at < 0.0:
				mouth_at = take["at_s"]
			if take["slot"] == GateShotPool.MOUTH and float(take["at_s"]) <= arrival:
				entry_take = take["id"]
		assert_almost_eq(mouth_at, director.pool.cut_s(arrival), 0.05, "jump %d: the mouth takes start on the predicted arrival's clock" % jump)
		assert_eq(director.pool.when(GateShotPool.MOUTH, entry_take), GateShotPool.ENTRY, "jump %d: the entry held by %s" % [jump, entry_take])
		if jump > 0:
			assert_ne(openings[jump], openings[jump - 1], "jump %d opens as the last did" % jump)
	var stopped: Array[bool] = [false]
	director.begin(ctx, func(_s: CinematicShot) -> void: pass)
	director.stop(func() -> void: stopped[0] = true)
	var count: int = director.played.size()
	director.tick(5.0, func(_s: CinematicShot) -> void: pass)
	director.on_placed(func(_s: CinematicShot) -> void: pass)
	assert_true(stopped[0], "one call stops the takes")
	assert_eq(director.played.size(), count, "and nothing more plays")


func _assert_short(starts: Array[float], limits: Array[float], end_s: float, label: String) -> void:
	assert_gt(starts.size(), 0, "%s: takes played" % label)
	for i: int in starts.size():
		var until: float = starts[i + 1] if i + 1 < starts.size() else end_s
		assert_lt(until - starts[i], limits[i], "%s: take %d lasts %.2f s" % [label, i, until - starts[i]])
		if i + 1 < starts.size():
			assert_gte(until - starts[i], GateShotPool.MIN_HOLD_S - 1e-3, "%s: take %d only %.2f s (no take under 1 s)" % [label, i,
					until - starts[i]])
