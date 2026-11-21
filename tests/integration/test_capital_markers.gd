extends GutTest
## Far capitals' HUD markers in the real main scene (M8-T08, the maintainer's play-test of 2026-11-21: "the carrier jumped in but
## there was no visible model"). A free-flight raid's strike carrier stands off 6-12 km out, a few dark pixels; the HUD marks it
## there with its class and range, hides the marker once the hull reads, gives no second label while it is the target, and its
## fighters get no capital marker.

const SEED: int = 5
## Ticks per real tick: the physics rate and the time scale raised together, so each step is still 1/60 s of sim time.
const SPEED_UP: float = 4.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = SEED
	main.encounters = true
	main.encounter_pools_path = EncounterDirector.pools_file(&"free_flight")
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


# A raid at the player, its fighters docked on its carrier; returns the run once the carrier stands off with them launched.
func _raid() -> CarrierRun:
	var director: EncounterDirector = main.encounter_director
	var e: EncounterEvent = null
	for i: int in 200:
		e = director.plan.event(EncounterDirector.FORCED_INDEX + 500 + i, &"raid")
		if e.count() >= 3:
			break
	e.at_civilian = false
	e.at_station = false
	assert_true(director.start(e))
	var carriers: CarrierJumps = CarrierJumps.attach(main.world)
	var run: CarrierRun = carriers.runs()[0]
	await _fly(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	assert_eq(run.state, CarrierRun.State.STANDOFF, "out of its point, its fighters launched")
	return run


# Faces the player's ship at `cap` from `range_m` (keeping its distance when 0), then lets the HUD draw a frame.
func _look_at(cap: Node3D, range_m: float = 0.0) -> void:
	var at: Vector3 = main.ship.global_position
	if range_m > 0.0:
		at = cap.global_position + (at - cap.global_position).normalized() * range_m
	main.ship.reset_to(Transform3D(Basis.looking_at((cap.global_position - at).normalized(), Vector3.UP), at))
	main.ship.linear_velocity = (cap as RigidBody3D).linear_velocity
	await wait_process_frames(3)


func test_the_carrier_is_marked_at_its_stand_off_and_hides_close_up() -> void:
	var run: CarrierRun = await _raid()
	var cap: CapitalStandin = run.carrier
	await _look_at(cap)
	var range_m: float = cap.global_position.distance_to(main.ship.global_position)
	assert_gt(range_m, 6000.0, "it stands off kilometres out")
	var marks: Array[Dictionary] = main.hud.frame.capital_marks
	assert_eq(marks.size(), 1, "one marker: %s" % Hud.capital_marks_text(main.hud.frame))
	assert_eq(marks[0]["label"], "STRIKE CARRIER", "its class")
	assert_true(marks[0]["on_screen"], "where it is")
	assert_almost_eq(float(marks[0]["range_m"]), range_m, 100.0)
	assert_true(main.hud.frame.items.has(HudSurface.CAPITALS))
	var state: ConsoleResult = DebugConsole.registry.execute_tokens(PackedStringArray(["get", "hud.capital_marks"]))
	assert_string_contains("\n".join(state.lines), "STRIKE CARRIER", "the console reads it")
	await _look_at(cap, 1500.0)
	assert_eq(main.hud.frame.capital_marks.size(), 0, "close up its hull reads: no marker (%s)" % Hud.capital_marks_text(main.hud.frame))


func test_targeted_it_has_one_label() -> void:
	var run: CarrierRun = await _raid()
	await _look_at(run.carrier)
	assert_true(main.ship.targeting.select_id(run.carrier.targetable.get_instance_id()))
	await wait_process_frames(3)
	assert_true(main.hud.frame.target_present, "the target's own mark names it")
	assert_eq(main.hud.frame.capital_marks.size(), 0, "and no capital marker beside it")


func test_its_fighters_get_no_capital_marker() -> void:
	var run: CarrierRun = await _raid()
	var capitals: Array[Dictionary] = CapitalContacts.gather(get_tree(), main.ship, 50000.0)
	assert_eq(capitals.size(), 1, "the carrier alone, not its %d launched fighters" % run.fighters.size())
	assert_eq(int(capitals[0]["id"]), run.carrier.targetable.get_instance_id())
	for body: RigidBody3D in run.fighters:
		await _look_at(body)
		for mark: Dictionary in main.hud.frame.capital_marks:
			assert_eq(mark["label"], "STRIKE CARRIER", "only the carrier is marked")
