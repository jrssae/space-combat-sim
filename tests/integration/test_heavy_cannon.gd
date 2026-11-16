extends GutTest
## The station's heavy cannons (M7-T43): each wears the oval gun in its recess, fires from its trunnion (so its own recess never
## stops a low shot) in bursts of three 0.35 s apart, a new burst 12 s after the last began, 300 a shot (today's 900 every
## 12 s), a large green pulse with a large green flash at the muzzle. Places come from the station's hardpoints. M7-T51: the pulse
## leaves the drawn muzzle at any yoke angle, drawn no bigger than the muzzle at the chase view's bolt size, and strikes with a
## flash that can be seen.

const RAIDER: StringName = &"raider_fighter"
const WEAPON: WeaponSpec = preload("res://assets/weapons/grid_heavy_cannon.tres")
const LIGHT: WeaponSpec = preload("res://assets/weapons/grid_light_pulse.tres")
## The oval muzzle's reach down the barrel from the trunnion (`grid_heavy_cannon`'s manifest).
const WEAPON_BARREL_M: float = StationGrid.HEAVY_BARREL_M

var scene: TurretScene
var station: Station
var shot_times: Array[float] = []
var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = Projectile.visual_scale


func after_each() -> void:
	Projectile.visual_scale = _saved_scale
	if scene != null:
		await scene.free_scene(get_tree())
	scene = null
	station = null
	shot_times.clear()


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


# A point `range_m` from H1's trunnion at the gun's azimuth `az_deg` (from the bow toward port, as the core counts it) and
# `el_deg` up, in the World frame.
func _from_h1(range_m: float, az_deg: float, el_deg: float) -> Vector3:
	var entry: Dictionary = station.hardpoints.mount("H1")
	var trunnion: Vector3 = (entry["position"] as Vector3) + Vector3(0.0, 9.5, 0.0)
	var a: float = deg_to_rad(az_deg)
	var e: float = deg_to_rad(el_deg)
	return station.to_world(trunnion + Vector3(-sin(a) * cos(e), sin(e), -cos(a) * cos(e)) * range_m, entry["body"])


# A point `ahead_m` toward the bow of H1's trunnion and `up_deg` above it, in the World frame.
func _ahead_of_h1(ahead_m: float, up_deg: float) -> Vector3:
	var entry: Dictionary = station.hardpoints.mount("H1")
	var trunnion: Vector3 = (entry["position"] as Vector3) + Vector3(0.0, 9.5, 0.0)
	var local: Vector3 = trunnion + Vector3(0.0, ahead_m * tan(deg_to_rad(up_deg)), -ahead_m)
	return station.to_world(local, entry["body"])


# H1 alone: every other mount knocked out, its shots timed in sim time.
func _h1_alone(target_at: Vector3) -> TurretMount:
	var raider: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "TARGET", target_at)
	raider.damageable.invulnerable = true
	scene.attach()
	TurretMount.rebind_all()
	var h1: TurretMount = station.grid.mount("H1")
	for m: TurretMount in station.grid.mounts:
		m.knocked_out = m != h1
	h1.shot_fired.connect(func(_at: Vector3) -> void: shot_times.append(SimClock.now()))
	station.grid.set_free(Factions.RAIDERS, true)
	return h1


func test_the_heavy_cannons_wear_the_oval_gun_on_a_raised_trunnion() -> void:
	if not await _start():
		return
	scene.attach()
	TurretMount.rebind_all()
	await _ticks(2)
	var heavy: int = 0
	for m: TurretMount in station.grid.mounts:
		if m.grid_kind != StationGrid.Kind.HEAVY:
			continue
		heavy += 1
		assert_not_null(m.pedestal, "%s stands on its bearing ring" % m.mount_name)
		assert_not_null(m.yaw.get_node_or_null(^"Yoke"), "%s has its yoke" % m.mount_name)
		assert_not_null(m.pitch.get_node_or_null(^"Barrels"), "%s has its barrel" % m.mount_name)
		assert_almost_eq(m.basis.get_scale().x, 1.0, 1e-4, "%s at the model's own size" % m.mount_name)
		assert_almost_eq(m.trunnion_m.y, 9.5, 1e-3, "%s's trunnion over its recess floor" % m.mount_name)
		assert_almost_eq(m.barrel_m, 22.5, 1e-3, "%s fires from its oval muzzle" % m.mount_name)
		var state: Dictionary = scene.state(m)
		assert_almost_eq(float(state["lift_m"]), 9.5, 1e-6, "the core starts its line and shots at the trunnion")
		assert_eq(int(state["burst_shots"]), 3, "the core fires it in threes")
	assert_eq(heavy, 2, "D75's two heavy cannons")


func test_a_heavy_cannon_fires_bursts_of_three_then_waits_out_its_cycle() -> void:
	if not await _start():
		return
	var h1: TurretMount = _h1_alone(_ahead_of_h1(1500.0, 20.0))
	await _ticks(60 * 18)
	assert_gte(shot_times.size(), 4, "a burst and the next one began: %s" % [shot_times])
	if shot_times.size() < 4:
		return
	assert_almost_eq(shot_times[1] - shot_times[0], WEAPON.burst_spacing_s, 0.02, "the burst's shots 0.35 s apart")
	assert_almost_eq(shot_times[2] - shot_times[1], WEAPON.burst_spacing_s, 0.02)
	assert_almost_eq(shot_times[3] - shot_times[0], WEAPON.shot_interval_s, 0.02, "the next burst 12 s after the first began")
	assert_eq(int(scene.state(h1)["shots"]), shot_times.size())
	assert_eq(int(station.grid.readouts()[1]), shot_times.size(), "counted as heavy shots")


func test_the_grids_own_numbers_match_the_guns_manifest() -> void:
	# StationGrid falls back on these when the asset is missing; they must be the model's.
	var entry: Dictionary = MeshAssets.read_manifest("grid_heavy_cannon").get("turret", {})
	if entry.is_empty():
		pending("the grid_heavy_cannon asset is not generated")
		return
	assert_almost_eq(float((entry["trunnion"] as Array)[1]), StationGrid.HEAVY_TRUNNION_M, 1e-4, "the trunnion's height")
	assert_almost_eq(float(entry["barrel_m"]), StationGrid.HEAVY_BARREL_M, 1e-4, "the barrel's reach")


func test_a_cycle_does_what_the_old_shot_did() -> void:
	# The maintainer: three shots of 300 every 12 s keep today's 900 every 12 s.
	assert_eq(WEAPON.burst_shots, 3)
	assert_almost_eq(WEAPON.burst_spacing_s, 0.35, 1e-6)
	assert_almost_eq(WEAPON.shot_interval_s, 12.0, 1e-6)
	assert_almost_eq(WEAPON.damage, 300.0, 1e-6)
	assert_almost_eq(WEAPON.damage * WEAPON.burst_shots / WEAPON.shot_interval_s, 900.0 / 12.0, 1e-6, "damage a second kept")


func test_the_pulse_is_large_green_and_elongated() -> void:
	assert_gt(WEAPON.bolt_length_m, 8.0 * LIGHT.bolt_length_m, "far longer than a light pulse turret's")
	assert_gt(WEAPON.bolt_radius_m, 8.0 * LIGHT.bolt_radius_m, "and far thicker")
	assert_gt(WEAPON.bolt_length_m, 10.0 * WEAPON.bolt_radius_m, "elongated")
	var glow: Color = (WEAPON.bolt_material as StandardMaterial3D).emission
	assert_gt(glow.g, 2.0 * maxf(glow.r, glow.b), "a green bolt")
	assert_gt(WEAPON.bolt_color.g, 2.0 * maxf(WEAPON.bolt_color.r, WEAPON.bolt_color.b), "green sparks where it lands")
	assert_ne(BoltMesh.look_for(WEAPON), BoltMesh.look_for(LIGHT), "drawn as its own look")
	assert_gt(StationGrid.HEAVY_GLOW.g, 2.0 * maxf(StationGrid.HEAVY_GLOW.r, StationGrid.HEAVY_GLOW.b), "a green muzzle flash")
	assert_gte(StationGrid.HEAVY_FLASH_SCALE, 5.0, "as big as its muzzle")


func test_its_recess_does_not_stop_a_low_shot_and_the_flash_is_at_the_muzzle() -> void:
	if not await _start():
		return
	# Five degrees over the deck straight ahead: from the recess floor the pit's front wall would be in the way.
	var h1: TurretMount = _h1_alone(_ahead_of_h1(2500.0, 5.0))
	var blocked_before: int = int(station.grid.readouts()[4])
	await _ticks(60 * 8)
	assert_gt(shot_times.size(), 0, "H1 fires low over its recess")
	assert_eq(int(station.grid.readouts()[4]), blocked_before, "and the hull never stopped a shot")
	var pool := WorldFrame.of(station).get_node_or_null(NodePath(MuzzleFlashPool.NODE_NAME)) as MuzzleFlashPool
	assert_not_null(pool, "its shots flash")
	if pool != null:
		assert_gt(pool.started, 0)
	assert_true(h1.pitch.get_node_or_null(^"Barrels") != null)


func test_the_deck_still_stops_a_shot_aimed_down_through_it() -> void:
	if not await _start():
		return
	# Ahead and well below the deck: inside H1's arc (10 degrees down), but the spine is in the way.
	var h1: TurretMount = _h1_alone(_ahead_of_h1(1500.0, -8.0))
	await _ticks(60 * 6)
	assert_eq(shot_times.size(), 0, "no shot leaves through the deck")
	assert_eq(int(scene.state(h1)["shots"]), 0)


func test_its_pulse_leaves_the_drawn_muzzle_at_every_yoke_angle() -> void:
	# M7-T51: the maintainer saw the big guns' pulses start outside the gun. At several yoke angles the shot starts at the
	# drawn oval muzzle, flies down the drawn barrel, and at the chase view's bolt size (the maintainer's 4.5) is drawn no
	# wider than the muzzle and no longer than its true 40 m, so it neither swallows the gun nor reaches back through it.
	if not await _start():
		return
	var h1: TurretMount = _h1_alone(_from_h1(1500.0, 0.0, 10.0))
	var raider: Combatant = scene.ships[0]
	var look: int = BoltMesh.look_for(WEAPON)
	var muzzle_half_height: float = 2.0  # the oval muzzle is 9 x 4 m
	Projectile.visual_scale = 4.5
	var checked: int = 0
	for angles: Vector2 in [Vector2(0.0, 10.0), Vector2(55.0, 30.0), Vector2(-35.0, 50.0)]:
		raider.ship.reset_to(Transform3D(Basis.IDENTITY, _from_h1(1500.0, angles.x, angles.y)))
		var before: int = shot_times.size()
		var starts: Array[Vector3] = []  # a lambda cannot assign the caller's local
		h1.shot_fired.connect(func(at: Vector3) -> void: starts.append(at), CONNECT_ONE_SHOT)
		for i: int in 60 * 25:
			await get_tree().physics_frame
			if shot_times.size() > before:
				break
		assert_gt(shot_times.size(), before, "H1 fires at azimuth %s, elevation %s" % [angles.x, angles.y])
		if starts.is_empty():
			continue
		var born: Vector3 = starts[0]
		h1.turn_to(float(scene.state(h1)["azimuth"]), float(scene.state(h1)["elevation"]))  # the model as the next frame shows it
		var drawn_muzzle: Vector3 = h1.pitch.global_transform * Vector3(0.0, 0.0, -WEAPON_BARREL_M)
		var barrel: Vector3 = -h1.pitch.global_transform.basis.z.normalized()
		assert_lt(born.distance_to(drawn_muzzle), 0.25, "born at the drawn muzzle (az %s, el %s)" % [angles.x, angles.y])
		scene.sim._bolt_mesh.update()
		var drawn: Array = _drawn_near(scene.sim._bolt_mesh.drawn_buffer(look), born)
		assert_false(drawn.is_empty(), "the pulse is drawn at the muzzle")
		if drawn.is_empty():
			continue
		var basis: Basis = drawn[1]
		var size: float = basis.get_scale().x
		assert_lt(rad_to_deg((basis * scene.sim._bolt_mesh.flight_axis()).angle_to(barrel)), 0.3, "it flies down the drawn barrel")
		assert_lte(WEAPON.bolt_radius_m * size, muzzle_half_height, "drawn no wider than the muzzle, not %.1f m" % [
				2.0 * WEAPON.bolt_radius_m * size])
		assert_lte(WEAPON.bolt_length_m * size, WEAPON.bolt_length_m + 1e-3, "and its true length, not %.0f m" % [
				WEAPON.bolt_length_m * size])
		checked += 1
	assert_eq(checked, 3, "every yoke angle checked")


func test_a_heavy_pulse_strikes_with_a_flash_that_can_be_seen() -> void:
	# M7-T51: a hit flashed 1.6 m for 0.08 s whatever struck, lost against a 40 m pulse or a capital's hull.
	if not await _start():
		return
	var h1: TurretMount = _h1_alone(_ahead_of_h1(1500.0, 10.0))
	var raider: Combatant = scene.ships[0]
	var biggest: float = 0.0
	for i: int in 60 * 12:
		await get_tree().physics_frame
		for child: Node in raider.ship.get_children():
			var flash := child as ImpactFlash
			if flash != null and flash.is_playing():
				biggest = maxf(biggest, flash.scale.x)
		if biggest > 0.0 and scene.hits_on(raider) > 0:
			break
	assert_gt(scene.hits_on(raider), 0, "H1 strikes the still raider")
	assert_gte(biggest, 0.6 * ImpactFlash.FLASH_SIZE_M * 5.0, "a heavy hit flashes at least five times the usual size")
	assert_eq(ImpactFlash.size_for(LIGHT.damage), 1.0, "a light pulse's hit keeps the usual flash")
	assert_eq(ImpactFlash.size_for(25.0), 1.0, "and a beam's")


func test_the_chase_view_still_enlarges_small_bolts() -> void:
	var interceptor: WeaponSpec = load("res://assets/weapons/grid_interceptor.tres") as WeaponSpec
	assert_almost_eq(BoltMesh.drawn_scale(BoltMesh.look_for(LIGHT), 4.5), 4.5, 1e-6, "a light pulse by the whole setting")
	assert_almost_eq(BoltMesh.drawn_scale(BoltMesh.look_for(interceptor), 10.0), 10.0, 1e-6, "an interceptor pulse even at the most")
	assert_almost_eq(BoltMesh.drawn_scale(BoltMesh.look_for(WEAPON), 4.5), 1.0, 1e-6, "the heavy pulse at its true size")
	assert_almost_eq(BoltMesh.drawn_scale(BoltMesh.look_for(LIGHT), 1.0), 1.0, 1e-6, "the cockpit view draws true size")


# The drawn instance in `buffer` nearest `at`: `[origin, basis]`, or empty when none is within a tick's flight (40 m).
func _drawn_near(buffer: PackedFloat32Array, at: Vector3) -> Array:
	var best: Array = []
	var best_d: float = 40.0
	for b: int in range(0, buffer.size() - 11, 12):
		var origin := Vector3(buffer[b + 3], buffer[b + 7], buffer[b + 11])
		var basis := Basis(Vector3(buffer[b], buffer[b + 4], buffer[b + 8]), Vector3(buffer[b + 1], buffer[b + 5], buffer[b + 9]),
				Vector3(buffer[b + 2], buffer[b + 6], buffer[b + 10]))
		if basis.x.is_zero_approx() or origin.distance_to(at) >= best_d:
			continue
		best_d = origin.distance_to(at)
		best = [origin, basis]
	return best
