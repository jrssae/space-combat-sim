extends GutTest
## AI ships at the station's surface (M7-T10, AC9): raiders whose targets lie beyond the hull go round it, in a crowd too,
## without touching it or hanging beside it (T07's stall); and a raid ordered at the station wears down a grid mount first.
## Flown headless through the native core with the physics rate and the time scale raised together.

const RAIDER: StringName = &"raider_fighter"
const ALLY: StringName = &"starfury_ally"
const SPEED_UP: float = 8.0
const HANG_MPS: float = 8.0

var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func test_raiders_in_a_crowd_go_round_the_spine_to_their_targets_without_touching_it() -> void:
	var scene: TurretScene = await _scene()
	if scene == null:
		pending("the babylon5_station asset is not generated")
		return
	var station: Station = scene.get_meta(&"station")
	# The spine's second station (L10): allies parked 700 m to port of it, the raid 900 m to starboard, level with the spine's
	# upper half, so the straight way is through the hull. Sixteen raiders: more than the nearest-12 cut keeps.
	var mid: Vector3 = station.to_world(station.hardpoints.mount("L10")["position"], StationHardpoints.FRAME) + Vector3.DOWN * 120.0
	var allies: Array[Combatant] = []
	for i: int in 2:
		allies.append(scene.ship(ALLY, Factions.EARTH_ALLIANCE, "ALLY %d" % (i + 1), mid + Vector3(-700.0, 0.0, 90.0 * i)))
	var raiders: Array[Combatant] = []
	var rams: Array[int] = [0]
	for i: int in 16:
		var at: Vector3 = mid + Vector3(900.0 + 45.0 * float(i % 4), -60.0 + 40.0 * float(i / 4), -70.0 + 45.0 * float(i % 4))
		var c: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "RAIDER %d" % (i + 1), at, {"type": "ai", "profile": "raider"},
				50 + i, false, Basis.looking_at(Vector3.LEFT, Vector3.UP))
		c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
			rams[0] += 1 if info != null and info.cause == HitInfo.CAUSE_RAM else 0)
		raiders.append(c)
	_add_rams(scene)
	scene.attach()
	TurretMount.rebind_all()
	for m: TurretMount in station.grid.mounts:
		m.knocked_out = true  # the hull alone: no gun thins the raid
	var crossed: Dictionary = {}
	var hang: int = 0
	var flown: int = 0
	var nearest: float = INF
	_speed_up()
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < 45.0:
		await get_tree().physics_frame
		for c: Combatant in raiders:
			if c.damageable.hull.destroyed:
				continue
			var at: Vector3 = c.ship.global_position
			flown += 1
			hang += 1 if c.ship.linear_velocity.length() < HANG_MPS else 0
			nearest = minf(nearest, scene.sim.core.surface_distance(station.get_instance_id(), at))
			if at.x < mid.x - 150.0:
				crossed[c] = true
	after_each()
	var hits: int = 0
	for a: Combatant in allies:
		hits += scene.hits_on(a)
	gut.p("station avoidance: %d of 16 round the spine, %d hits on the allies, nearest %.0f m, hanging %.1f %%, rams %d" % [
			crossed.size(), hits, nearest, 100.0 * float(hang) / float(maxi(flown, 1)), rams[0]])
	assert_eq(rams[0], 0, "no raider touched the station")
	assert_gt(crossed.size(), 11, "the raid got round the spine to its targets (%d of 16)" % crossed.size())
	assert_gt(hits, 0, "and fired on them")
	assert_lt(float(hang) / float(maxi(flown, 1)), 0.05, "none hung beside the hull")
	await scene.free_scene(get_tree())


func test_a_raid_ordered_at_the_station_goes_for_a_grid_mount_first() -> void:
	var scene: TurretScene = await _scene()
	if scene == null:
		pending("the babylon5_station asset is not generated")
		return
	var station: Station = scene.get_meta(&"station")
	var over: Vector3 = station.to_world(station.hardpoints.mount("L10")["position"], StationHardpoints.FRAME)
	var raiders: Array[Combatant] = []
	var rams: Array[int] = [0]
	for i: int in 6:
		var at: Vector3 = over + Vector3(-250.0 + 100.0 * float(i), 1100.0, -300.0)
		var c: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "RAIDER %d" % (i + 1), at,
				{"type": "ai", "profile": "raider", "orders": "attack", "objective": Station.DISPLAY_NAME}, 70 + i, false,
				Basis.looking_at(Vector3.DOWN, Vector3.FORWARD))
		c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
			rams[0] += 1 if info != null and info.cause == HitInfo.CAUSE_RAM else 0)
		raiders.append(c)
	_add_rams(scene)
	scene.attach()
	TurretMount.rebind_all()
	var grid: StationGrid = station.grid
	_speed_up()
	var t0: float = SimClock.now()
	var worn: int = -1
	while SimClock.now() - t0 < 40.0 and worn < 0:
		await get_tree().physics_frame
		for k: int in grid.health.count():
			if grid.health.health[k] < grid.health.max_health[k]:
				worn = k
	after_each()
	assert_gt(worn, -1, "a mount took the raid's fire inside 40 s")
	if worn >= 0:
		gut.p("the raid's first mount: %s after %.1f s" % [grid.health.names[worn], SimClock.now() - t0])
	assert_eq(rams[0], 0, "no raider touched the station")
	await scene.free_scene(get_tree())


# A threaded scene with the station at the origin (kept in the scene's meta), or null without the asset.
func _scene() -> TurretScene:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, &"threaded", 6)
	var station := Station.new()
	station.name = "Station"
	if not station.build():
		station.free()
		await scene.free_scene(get_tree())
		return null
	scene.world.spawn(station, scene.world.to_universe(Vector3.ZERO))
	scene.set_meta(&"station", station)
	return scene


static func _add_rams(scene: TurretScene) -> void:
	var rams := RamResolver.new()
	rams.name = "RamResolver"
	rams.world = scene.world
	scene.space.add_child(rams)


func _speed_up() -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
