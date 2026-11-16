extends GutTest
## The grid's aim where the turret rows call it (M7-T14, council round 3): a heavy cannon on its raised trunnion hits a crossing
## fighter at 2 km, and an interceptor battery shows the line of the pulse it fires. The kernels have their own tests; these
## fail when `step_turrets` or `step_interceptors` hands them the wrong frame or stores the wrong angles.

const RAIDER: StringName = &"raider_fighter"
## The heavy cannon's trunnion over its recess floor, m (the model's; `StationGrid.HEAVY_TRUNNION_M`).
const TRUNNION_M: float = 9.5
## A pulse leaves within its spread (0.22 degrees) of the line the battery shows.
const SHOWN_TOLERANCE_DEG: float = 0.3

var scene: TurretScene
var station: Station


func after_each() -> void:
	if scene != null:
		await scene.free_scene(get_tree())
	scene = null
	station = null


# A scene with the station still at the origin; false (pending) without the asset.
func _start() -> bool:
	await get_tree().process_frame
	await get_tree().physics_frame
	scene = TurretScene.build(self, &"threaded", 1)
	station = Station.new()
	station.name = "Station"
	if not station.build():
		station.free()
		station = null
		pending("the babylon5_station asset is not generated")
		return false
	scene.world.spawn(station, scene.world.to_universe(Vector3.ZERO))
	station.set_spinning(false)
	return true


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# Every mount but `keep` knocked out, so only it fires.
func _alone(keep: TurretMount) -> void:
	for m: TurretMount in station.grid.mounts:
		m.knocked_out = m != keep


func test_a_lifted_heavy_cannon_hits_a_crossing_fighter_at_2_km() -> void:
	if not await _start():
		return
	# Ahead of H1's trunnion, 2 km out and 12 degrees up, crossing at 40 m/s: aimed from the recess floor instead of the
	# trunnion, every shot passes about 9 m over a hull 1.5 m tall.
	var entry: Dictionary = station.hardpoints.mount("H1")
	var body: String = entry["body"]
	var trunnion: Vector3 = (entry["position"] as Vector3) + Vector3(0.0, TRUNNION_M, 0.0)
	var local: Vector3 = trunnion + Vector3(-300.0, 2000.0 * tan(deg_to_rad(12.0)), -2000.0)
	var at: Vector3 = station.to_world(local, body)
	var velocity: Vector3 = station.to_world(local + Vector3(40.0, 0.0, 0.0), body) - at
	var raider: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "TARGET", at)
	raider.damageable.invulnerable = true
	raider.ship.linear_velocity = velocity
	scene.attach()
	TurretMount.rebind_all()
	var h1: TurretMount = station.grid.mount("H1")
	_alone(h1)
	station.grid.set_free(Factions.RAIDERS, true)
	await _ticks(60 * 30)
	var shots: int = int(scene.state(h1)["shots"])
	var hits: int = scene.hits_on(raider)
	var drift: float = (raider.ship.linear_velocity - velocity).length()
	var up_deg: float = rad_to_deg(asin((raider.ship.global_position - station.to_world(trunnion, body)).normalized().y))
	gut.p("H1: %d shots, %d hits; the target's speed drifted %.2f m/s, %.1f degrees up" % [shots, hits, drift, up_deg])
	assert_lt(drift, 1.0, "the target kept crossing at its speed")
	assert_between(up_deg, 10.0, 30.0, "10 to 30 degrees up")
	assert_gte(shots, 6, "two bursts and more")
	# Led from its trunnion 6 of 9 shots land; led from the recess floor 1 does (the spread's luck).
	assert_gte(hits * 2, shots, "half the cannon's shots and more meet the fighter it led from its trunnion")


func test_a_battery_shows_the_line_of_the_pulse_it_fires() -> void:
	if not await _start():
		return
	scene.attach()
	TurretMount.rebind_all()
	await _ticks(2)
	var i5: TurretMount = station.grid.mount("I5")
	_alone(i5)
	var entry: Dictionary = station.hardpoints.mount("I5")
	var body: String = entry["body"]
	var base: Vector3 = entry["position"]
	var up: Vector3 = (entry["up"] as Vector3).normalized()
	var across: Vector3 = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var fired: Array = []
	var checked: Array[float] = []
	var parallax: Array[float] = []
	i5.shot_fired.connect(func(from: Vector3) -> void:
		var s: Dictionary = scene.state(i5)
		i5.turn_to(float(s["azimuth"]), float(s["elevation"]))
		fired.append([from, -i5.pitch.global_basis.z.normalized(), i5.pitch.global_position]))
	i5.intercepted.connect(func(point: Vector3, _color: Color) -> void:
		var last: Array = fired.back()
		var flown: Vector3 = (point - (last[0] as Vector3)).normalized()
		checked.append(rad_to_deg((last[1] as Vector3).angle_to(flown)))
		parallax.append(rad_to_deg((point - (last[2] as Vector3)).normalized().angle_to(flown))))
	# Bolts at the battery's base from 45 degrees up on four sides, one at a time, met a few hundred metres out: close enough
	# that the line from the trunnion and the line from the barrel that fires differ by far more than the pulse's spread.
	for k: int in 4:
		var side: Vector3 = across.rotated(up, k * PI / 2.0)
		var toward: Vector3 = (up + side).normalized()
		var start: Vector3 = station.to_world(base + toward * 260.0, body)
		var velocity: Vector3 = station.to_world(base - toward * 350.0, body) - station.to_world(base, body)
		_bolt(start, velocity)
		await _ticks(90)
	gut.p("I5: shown vs flown %s deg; trunnion line vs flown %s deg" % [checked, parallax])
	assert_gte(checked.size(), 2, "the battery met the bolts")
	for k: int in checked.size():
		assert_lt(checked[k], SHOWN_TOLERANCE_DEG, "the barrels lie along the pulse that met")
		assert_gt(parallax[k], 2.0 * SHOWN_TOLERANCE_DEG, "close enough that the trunnion's line would not")


func _bolt(at: Vector3, velocity: Vector3) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	scene.bolts.add_child(bolt)
	var weapon := WeaponSpec.new()
	weapon.damage = 6.0
	weapon.lifetime_s = 8.0
	bolt.configure(weapon)
	bolt.shooter_id = 1
	bolt.faction = Factions.RAIDERS
	bolt.launch(at, velocity, SimClock.now())
	return bolt
