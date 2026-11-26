extends TestSteps
## Mines in flight with threads (M10-T15, architecture §17.13): the rows' step and the shots that meet a mine run on the main
## thread over the tick's rows, so an energy mine sent at a capital, the interceptors' pulses on it and three hostile bolts on it
## play out the same, tick by tick, with one thread and six.

const CRUISER: StringName = &"capital_test_cruiser"
const OMEGA: StringName = &"ea_omega"
const TICKS: int = 900

var _threads_backup: Variant = null


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # its capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)
	Factions.reset()


func test_a_mine_in_flight_met_by_pulses_and_bolts_goes_the_same_with_one_thread_and_six() -> void:
	var one: Dictionary = await _run(1, false)
	var six: Dictionary = await _run(6, false)
	assert_eq(one["digests"], six["digests"], "every mine's state and place each tick")
	assert_eq(one["events"], six["events"], "the same mines shot down, set off and laid, on the same ticks")
	assert_gt(int(one["laid"]), 0, "a mine was laid")
	var shots_one: Dictionary = await _run(1, true)
	var shots_six: Dictionary = await _run(6, true)
	assert_eq(int(shots_one["shots"]), 3, "three bolts met the mine")
	assert_eq(shots_one["digests"], shots_six["digests"], "with bolts on it: the same each tick")
	assert_eq(shots_one["events"], shots_six["events"])


# One run: an energy-mine launcher and a target Omega (its interceptors held), the mine's flight watched for `TICKS`; with `shoot`
# three hostile bolts are put on the mine at tick 40.
func _run(threads: int, shoot: bool) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.ally_pool_size = 8
	add_child(main)
	await _ticks(2)
	SimClock.reset()  # the layers' clocks and the digests read the sim time: the same start in every run
	DebugConsole.flags.invulnerable = true
	var world: WorldFrame = main.world
	var ea: StringName = Factions.EARTH_ALLIANCE
	Factions.table().set_relation(&"drakh", ea, Factions.Relation.HOSTILE)
	var rest: Vector3 = world.rest_velocity()
	var cruiser: CapitalShip = CapitalShip.create(CRUISER, &"drakh", "LAYER", rest)
	var omega: CapitalShip = CapitalShip.create(OMEGA, ea, "TARGET", rest)
	var basis: Basis = main.ship.global_basis
	var turned: Basis = basis.rotated(basis.y, 0.5 * PI)
	var at: Vector3 = main.ship.global_position - basis.z * 300.0 + basis.x * 600.0
	world.spawn(omega, world.to_universe(at), basis)
	world.spawn(cruiser, world.to_universe(at + basis.x * 6300.0), turned)
	for cap: CapitalShip in [cruiser, omega]:
		cap.set_course(-cap.global_basis.z, rest)
		CapitalBeams.of(world).hold(cap, true)
		CapitalGuns.of(world).hold(cap, true)
		cap.damageable.invulnerable = true
		CapitalGuns.of(world).hold_interceptors(cap, cap == cruiser or shoot)
	var field: MineField = MineField.battle(world)
	field.add_layer(cruiser.get_instance_id(), Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, -1.0), MineKinds.ENERGY,
			MineKinds.laying(MineKinds.ENERGY))
	var events: Array = []
	var tick: Array[int] = [0]
	field.laid.connect(func(slot: int) -> void: events.append([tick[0], "laid", slot]))
	field.shot_down.connect(func(slot: int) -> void: events.append([tick[0], "down", slot]))
	field.detonated.connect(func(slot: int, _k: int, _at: Vector3) -> void: events.append([tick[0], "off", slot]))
	var digests: Array[int] = []
	var weapon := WeaponSpec.new()
	weapon.lifetime_s = 10.0
	var sim: SimCore = SimCore.for_tree(get_tree())
	for t: int in TICKS:
		tick[0] = t
		await get_tree().physics_frame
		digests.append(int(field.rows.digest()))
		if shoot and t >= 40 and t < 46 and (t - 40) % 2 == 0 and field.alive_count() > 0:
			var info: Array = field.rows.info(0)
			if not info.is_empty():
				sim.add_bolt(field.global_position + (info[4] as Vector3), Vector3.ZERO, ea, main.ship.get_instance_id(), weapon,
						SimClock.now())
	var out: Dictionary = {"digests": digests, "events": events, "laid": field.mines_laid, "shots": field.shots_on_flight()}
	DebugConsole.flags.invulnerable = false
	remove_child(main)
	main.queue_free()
	await get_tree().physics_frame
	return out
