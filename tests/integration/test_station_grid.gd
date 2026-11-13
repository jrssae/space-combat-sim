extends GutTest
## The station's defence grid (M7-T07, D75, AC6) through the native core: D75's 23 mounts bind to the turret rows with their
## kinds; the drum's mounts turn with the drum; the guns never fire first and open on the side that fired on the station or on
## a friend near it; the station's own hull hides a target from a gun; the interceptors take hostile bolts and missiles aimed
## at the hull at a capped rate and never a beam; a bolt of the station's own side stops on its hull without harm. Places come
## from the station's hardpoints.

const RAIDER: StringName = &"raider_fighter"
const ALLY: StringName = &"starfury_ally"

var scene: TurretScene
var station: Station


func after_each() -> void:
	if scene != null:
		await scene.free_scene(get_tree())
	scene = null
	station = null


# A scene with the station at the origin, built and in the world; false (pending) without the asset.
func _start(spin: bool = false) -> bool:
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
	if not spin:
		station.set_spinning(false)
	return true


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _at_mount(mount_name: String, out_m: float) -> Vector3:
	var entry: Dictionary = station.hardpoints.mount(mount_name)
	var body: String = entry["body"]
	var tip: Vector3 = (entry["position"] as Vector3) + (entry["up"] as Vector3).normalized() * out_m
	return station.to_world(tip, body)


func _raider(at: Vector3, label: String = "RAIDER") -> Combatant:
	return scene.ship(RAIDER, Factions.RAIDERS, label, at)


func _shots() -> PackedInt64Array:
	return station.grid.readouts()


func _bolt(at: Vector3, velocity: Vector3, faction: StringName, kind: StringName = Projectile.KIND_BOLT) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	scene.bolts.add_child(bolt)
	var weapon := WeaponSpec.new()
	weapon.damage = 6.0
	weapon.lifetime_s = 8.0
	bolt.configure(weapon)
	if kind != Projectile.KIND_BOLT:
		bolt.set_kind(kind)
	bolt.shooter_id = 1
	bolt.faction = faction
	bolt.launch(at, velocity, SimClock.now())
	return bolt


func _health_total() -> float:
	var sum: float = 0.0
	for h: float in station.sections.health:
		sum += h
	return sum


func test_the_23_mounts_bind_to_the_turret_rows_with_their_kinds() -> void:
	if not await _start():
		return
	scene.attach()
	TurretMount.rebind_all()
	await _ticks(2)
	var grid: StationGrid = station.grid
	assert_eq(grid.mounts.size(), 23, "D75's mounts")
	assert_eq(grid.of_kind(StationGrid.Kind.LIGHT).size(), 12)
	assert_eq(grid.of_kind(StationGrid.Kind.HEAVY).size(), 2)
	assert_eq(grid.of_kind(StationGrid.Kind.INTERCEPTOR).size(), 9)
	assert_eq(grid.bound_count(), 23, "every mount holds a core slot")
	for m: TurretMount in grid.mounts:
		assert_eq(int(scene.sim.core.turret_kind(m.slot())), m.grid_kind, "%s's kind in the core" % m.mount_name)
		var on_drum: bool = station.hardpoints.mount(m.mount_name)["body"] == StationHardpoints.DRUM
		assert_eq(m.host, station.drum_body if on_drum else station, "%s binds to its body" % m.mount_name)
	assert_eq(grid.free_sides().size(), 0, "holding fire at the start")


func test_the_drums_mounts_turn_with_the_drum_and_fire_from_where_it_put_them() -> void:
	if not await _start(true):
		return
	var l1: TurretMount = station.grid.mount("L1")
	_raider(_at_mount("L1", 900.0))
	scene.attach()
	TurretMount.rebind_all()
	await _ticks(2)
	# Each drum gun's shot, with where the drum put that gun's pivot in the same tick.
	var starts: Array = []
	for m: TurretMount in station.grid.of_kind(StationGrid.Kind.LIGHT):
		if m.host == station.drum_body:
			m.shot_fired.connect(func(at: Vector3) -> void:
				starts.append([at, _at_mount(m.mount_name, 0.0), m.barrel_m]))
	var before: Vector3 = l1.global_position
	var angle_before: float = station.drum_angle
	station.grid.set_free(Factions.RAIDERS, true)
	await _ticks(300)
	assert_gt(absf(station.drum_angle - angle_before), 0.2, "the drum turned")
	assert_gt(l1.global_position.distance_to(before), 50.0, "the mount went round with it")
	assert_almost_eq(l1.global_position.distance_to(_at_mount("L1", 0.0)), 0.0, 1.0, "the mount sits on its pivot")
	assert_gt(starts.size(), 0, "the drum's guns fired at the raider over them")
	for s: Array in starts:
		assert_lt((s[0] as Vector3).distance_to(s[1] as Vector3), float(s[2]) + 5.0,
				"a shot leaves the barrel where the drum put the gun")


func test_the_guns_never_fire_first_and_open_on_the_side_that_fired() -> void:
	if not await _start():
		return
	var raider: Combatant = _raider(_at_mount("H1", 1200.0))
	var far_friend: Combatant = scene.ship(ALLY, Factions.EARTH_ALLIANCE, "FAR", Vector3(0.0, 40000.0, 0.0))
	var near_friend: Combatant = scene.ship(ALLY, Factions.EARTH_ALLIANCE, "NEAR", _at_mount("L9", 600.0))
	scene.attach()
	TurretMount.rebind_all()
	await _ticks(180)
	assert_eq(_shots()[0] + _shots()[1], 0, "a hostile in range is not fired on before it fires")
	assert_eq(station.grid.free_sides().size(), 0)
	var raider_id: int = raider.ship.get_instance_id()
	scene.sim.note_hit(far_friend.ship.get_instance_id(), raider_id)
	await _ticks(2)
	assert_eq(station.grid.free_sides().size(), 0, "a friend hit far from the grid does not free it")
	scene.sim.note_hit(near_friend.ship.get_instance_id(), raider_id)
	await _ticks(2)
	assert_eq(station.grid.free_sides(), PackedStringArray([String(Factions.RAIDERS)]), "a friend hit near it does")
	await _ticks(240)
	assert_gt(_shots()[0] + _shots()[1], 0, "the grid engages the raider once weapons free")
	station.grid.set_free(&"", false)
	await _ticks(2)
	var held: int = _shots()[0] + _shots()[1]
	await _ticks(180)
	assert_eq(_shots()[0] + _shots()[1], held, "grid hold stops the guns")
	scene.sim.note_hit(station.get_instance_id(), raider_id)
	await _ticks(2)
	assert_eq(station.grid.free_sides().size(), 1, "a hit on the station itself frees it")


func test_the_stations_hull_hides_a_target_from_a_gun() -> void:
	if not await _start():
		return
	# Under the drum, straight below the dorsal spine's third station: L11 on the spine's top cannot see it.
	var l11_at: Vector3 = _at_mount("L11", 0.0)
	var below: Combatant = _raider(Vector3(l11_at.x, -900.0, l11_at.z), "BELOW")
	scene.attach()
	TurretMount.rebind_all()
	station.grid.set_free(Factions.RAIDERS, true)
	var l11: TurretMount = station.grid.mount("L11")
	await _ticks(180)
	assert_eq(int(scene.state(l11)["target"]), 0, "L11 never picks a raider its hull hides")
	assert_eq(int(scene.state(l11)["shots"]), 0)
	var above: Combatant = _raider(_at_mount("L11", 1200.0), "ABOVE")
	await _ticks(60)
	assert_eq(int(scene.state(l11)["target"]), above.ship.get_instance_id(), "it picks the one in its view")
	assert_true(below.damageable.hull.fraction() >= 0.0)


func test_a_bolt_of_the_stations_side_stops_on_its_hull_without_harm() -> void:
	if not await _start():
		return
	scene.attach()
	TurretMount.rebind_all()
	await _ticks(2)
	var whole: float = _health_total()
	# Aft, out of every interceptor's reach, straight down onto the hull.
	var friendly: Projectile = _bolt(Vector3(0.0, 1200.0, 3600.0), Vector3(0.0, -1000.0, 0.0), Factions.EARTH_ALLIANCE)
	await _ticks(90)
	assert_eq(scene.resolver.friendly_stops, 1, "the friendly bolt stopped on the hull")
	assert_false(is_instance_valid(friendly) and not friendly.is_spent(), "and is gone")
	assert_eq(_health_total(), whole, "without harm")
	assert_eq(scene.hits.size(), 0, "no hit was resolved")
	_bolt(Vector3(0.0, 1200.0, 3600.0), Vector3(0.0, -1000.0, 0.0), Factions.RAIDERS)
	await _ticks(90)
	assert_lt(_health_total(), whole, "a raider's bolt there harms a section")


func test_interceptors_take_bolts_and_missiles_at_the_hull_at_a_capped_rate_and_never_a_beam() -> void:
	if not await _start():
		return
	scene.attach()
	TurretMount.rebind_all()
	await _ticks(2)
	var over: Vector3 = _at_mount("I5", 1100.0)
	var down := Vector3(0.0, -350.0, 0.0)
	_bolt(over, down, Factions.RAIDERS)
	_bolt(over + Vector3(15.0, 0.0, 0.0), down, Factions.RAIDERS, Projectile.KIND_MISSILE)
	await _ticks(3)
	assert_eq(_shots()[2], 2, "the bolt and the missile shot down")
	assert_eq(_shots()[3], 1, "one of them the missile")
	assert_eq(station.grid.free_sides(), PackedStringArray([String(Factions.RAIDERS)]),
			"a shot at the station frees the grid against its side before it lands")
	# A volley once every battery is ready again: none takes more than one in its interval.
	await _ticks(60)
	for i: int in 30:
		_bolt(over + Vector3(-60.0 + 4.0 * i, 0.0, 0.0), down, Factions.RAIDERS)
	var batteries: Array[TurretMount] = station.grid.of_kind(StationGrid.Kind.INTERCEPTOR)
	var shots_before: Array[int] = []
	for m: TurretMount in batteries:
		shots_before.append(int(scene.state(m)["shots"]))
	var before: int = _shots()[2]
	await _ticks(20)
	assert_gt(_shots()[2] - before, 0, "the volley is engaged")
	for k: int in batteries.size():
		assert_lte(int(scene.state(batteries[k])["shots"]) - shots_before[k], 1,
				"%s takes at most one in its half second" % batteries[k].mount_name)
	# A beam gets through: the batteries never take one.
	await _ticks(120)
	var whole: float = _health_total()
	var taken: int = _shots()[2]
	var beam := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	scene.bolts.add_child(beam)
	beam.configure(BeamStandin.weapon())
	beam.shooter_id = 1
	beam.faction = Factions.RAIDERS
	beam.fire_beam(over, over + Vector3(0.0, -2500.0, 0.0), SimClock.now())
	await _ticks(3)
	assert_eq(_shots()[2], taken, "no beam shot down")
	assert_lt(_health_total(), whole, "the beam reached the hull")
