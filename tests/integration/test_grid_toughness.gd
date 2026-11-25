extends GutTest
## The station grid on the shared battery model (M10-T13, Q81): a tough shot takes as many of the grid's pulses as its toughness
## (a heavy bolt two), each meeting shown, only the last bringing it down; a plain bolt still one.

var scene: TurretScene
var station: Station


func after_each() -> void:
	if scene != null:
		await scene.free_scene(get_tree())
	scene = null
	station = null


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func test_a_heavy_bolt_takes_two_of_the_grids_pulses_and_a_plain_one_one() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	scene = TurretScene.build(self, &"threaded", 1)
	station = Station.new()
	station.name = "Station"
	if not station.build():
		station.free()
		station = null
		pending("the babylon5_station asset is not generated")
		return
	scene.world.spawn(station, scene.world.to_universe(Vector3.ZERO))
	station.set_spinning(false)
	scene.attach()
	TurretMount.rebind_all()
	await _ticks(2)
	var entry: Dictionary = station.hardpoints.mount("I5")
	var over: Vector3 = station.to_world((entry["position"] as Vector3) + (entry["up"] as Vector3).normalized() * 1100.0, entry["body"])
	var meetings: Array[int] = [0]
	for m: TurretMount in station.grid.of_kind(StationGrid.Kind.INTERCEPTOR):
		m.intercepted.connect(func(_at: Vector3, _color: Color) -> void: meetings[0] += 1)
	var sim: SimCore = scene.sim
	var weapon := WeaponSpec.new()
	weapon.damage = 6.0
	weapon.lifetime_s = 8.0
	var heavy: int = sim.add_bolt(over, Vector3(0.0, -350.0, 0.0), Factions.RAIDERS, 1, weapon, SimClock.now())
	assert_true(sim.set_bolt_hits(heavy, 2))
	assert_eq(sim.bolt_hits(heavy), 2)
	var took_one: Array[bool] = [false]
	for t: int in 200:
		await get_tree().physics_frame
		took_one[0] = took_one[0] or sim.bolt_hits(heavy) == 1
		if sim.bolt_hits(heavy) == 0:
			break
	assert_true(took_one[0], "a first pulse leaves it flying with one hit left")
	assert_eq(sim.bolt_hits(heavy), 0, "a second brings it down before it reaches the hull")
	assert_eq(station.grid.readouts()[2], 1, "one shot down")
	assert_gte(meetings[0], 2, "two meetings shown")
	var plain: int = sim.add_bolt(over + Vector3(20.0, 0.0, 0.0), Vector3(0.0, -350.0, 0.0), Factions.RAIDERS, 1, weapon,
			SimClock.now())
	var met_before: int = meetings[0]
	await _ticks(200)
	assert_eq(sim.bolt_hits(plain), 0, "the plain bolt is down")
	assert_eq(station.grid.readouts()[2], 2)
	assert_eq(meetings[0] - met_before, 1, "with one pulse")
