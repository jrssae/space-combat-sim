extends GutTest
## The station's raids and wings take their ships from pools built at load (M7-T13 fix, maintainer 2026-11-15): no raid, scramble or
## wing launch grows a pool in the middle of a fight; a wing still out takes a new raid instead of a second wing launching; a
## wing below half strength lets the next one go; and the first hit and volley of a session find their flashes built.

const SCENARIO: String = "res://data/scenarios/station_launch.json"
const SPEED_UP: float = 8.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> bool:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if main.far_props.station == null:
		return false
	main.combatant.damageable.invulnerable = true
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	return true


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


# The allied Starfuries of wing `wing` in play.
func _wing_ships(wing: String) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in main.ships.alive(ShipPool.ALLY_TYPE):
		if c.display_name.begins_with(wing.to_upper() + " ") and not main.combatant == c:
			out.append(c)
	return out


func test_the_load_builds_the_ships_a_raid_and_a_scramble_take() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var raiders: int = main.ships.pool_size(ShipPool.DEFAULT_TYPE)
	var allies: int = main.ships.pool_size(ShipPool.ALLY_TYPE)
	assert_gte(main.ships.free_count(ShipPool.DEFAULT_TYPE), StationTraffic.MAX_RAID, "a raid of the largest size is built")
	assert_gte(main.ships.free_count(ShipPool.ALLY_TYPE), LaunchDirector.WING_SIZE, "a full wing is built beside the wingmen")
	assert_gt(main.traffic.reserved_ms, 0.0, "the cost of it is on record")
	var result: ConsoleResult = _run("traffic raid 12")
	assert_true(result.ok, "\n".join(result.lines))
	assert_eq(main.traffic.alive_of(&"raid"), 12, "twelve raiders flew out of the pool")
	assert_eq(main.launches.launches.size(), 1, "alpha scrambled")
	assert_eq(main.ships.pool_size(ShipPool.DEFAULT_TYPE), raiders, "no raider was built for the raid")
	assert_eq(main.ships.pool_size(ShipPool.ALLY_TYPE), allies, "no Starfury was built for the wing")


func test_a_wing_launch_in_a_station_scenario_builds_nothing() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var allies: int = main.ships.pool_size(ShipPool.ALLY_TYPE)
	var result: ConsoleResult = _run("launch wing beta")
	assert_true(result.ok, "\n".join(result.lines))
	assert_eq(main.ships.pool_size(ShipPool.ALLY_TYPE), allies, "no Starfury was built for the wing")


func test_a_second_raid_while_the_wing_is_out_launches_nothing_and_the_wing_engages() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	main.traffic.scramble_wings = PackedStringArray(["beta"])
	assert_true(_run("traffic raid 4").ok)
	var out: int = main.ships.alive(ShipPool.ALLY_TYPE).size()
	var squadron: Wing = main.wings.wing_named("BETA")
	assert_not_null(squadron, "the wing the station scrambled")
	squadron.order = AiContext.Order.COVER_ME  # as if something had told it to hold
	assert_true(await _until(func() -> bool: return main.launches.launches.is_empty(), 120.0), "the wing is away")
	assert_true(_run("traffic raid 4").ok)
	assert_true(_run("traffic raid 4").ok)
	assert_eq(main.launches.launches.size(), 0, "nothing launched for the later raids")
	assert_eq(main.ships.alive(ShipPool.ALLY_TYPE).size(), out, "the allies did not pile up")
	assert_eq(squadron.order, AiContext.Order.ENGAGE_AT_WILL, "the wing out engages the raid")
	assert_eq(main.launches.wing_strength("beta"), LaunchDirector.WING_SIZE)


func test_a_wing_below_half_strength_is_refilled() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	main.traffic.scramble_wings = PackedStringArray(["beta"])
	assert_true(_run("traffic raid 4").ok)
	assert_true(await _until(func() -> bool: return main.launches.launches.is_empty(), 120.0), "the wing is away")
	var ships: Array[Combatant] = _wing_ships("beta")
	assert_eq(ships.size(), LaunchDirector.WING_SIZE)
	for i: int in 6:
		ships[i].damageable.kill()  # six of twelve is still half
	await get_tree().physics_frame
	assert_eq(main.launches.wing_strength("beta"), 6)
	assert_true(_run("traffic raid 4").ok)
	assert_eq(main.launches.launches.size(), 0, "half strength still holds the raid")
	ships[6].damageable.kill()  # five of twelve
	await get_tree().physics_frame
	assert_eq(main.launches.wing_strength("beta"), 5)
	var pool: int = main.ships.pool_size(ShipPool.ALLY_TYPE)
	assert_true(_run("traffic raid 4").ok)
	assert_eq(main.launches.launches.size(), 1, "below half the wing is refilled")
	assert_eq(main.launches.wing_strength("beta"), LaunchDirector.WING_SIZE, "with the seven it lacked")
	assert_eq(main.ships.pool_size(ShipPool.ALLY_TYPE), pool, "from the pool")


func test_the_next_wing_goes_when_the_first_is_gone() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	main.traffic.scramble_wings = PackedStringArray(["beta", "delta"])
	assert_true(_run("traffic raid 4").ok)
	assert_true(await _until(func() -> bool: return main.launches.launches.is_empty(), 120.0), "beta is away")
	assert_false(main.launches.has_flown("delta"), "delta waits while beta is out")
	assert_true(_run("traffic raid 4").ok)
	assert_false(main.launches.has_flown("delta"), "and for a second raid too")
	for c: Combatant in _wing_ships("beta"):
		c.damageable.kill()
	await get_tree().physics_frame
	assert_eq(main.launches.wing_strength("beta"), 0)
	assert_true(_run("traffic raid 4").ok)
	assert_true(main.launches.is_launching("delta"), "beta is gone: delta scrambles")


func test_the_first_hit_and_volley_find_their_flashes_built() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	for color: Color in WeaponSpec.known_bolt_colors():
		assert_true(ImpactFlash.is_warm(color), "the flash of %s is made" % color)
	assert_gte(FramePasses.current().impact_pool_size(), 1, "and finished flashes wait in the pool")
	var flashes: MuzzleFlashPool = MuzzleFlashPool.attach(main.world)
	assert_gte(flashes.spare_count(), 1, "the muzzle flashes' lights are made")
