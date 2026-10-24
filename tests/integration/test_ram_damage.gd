extends GutTest
## Ram damage in Jolt (M3-T04, AC4, architecture §16 D32): two Starfuries meeting at 4 m/s closing take no damage; at 30 m/s
## each loses at least half its hull, once per contact; at 600 m/s (10 m per tick) both are destroyed and neither passes through
## the other unhurt, over 50 seeded offsets where the hulls overlap by at least 0.3 m on the pass; a ship ramming a buoy at
## 40 m/s destroys it and is not hurt itself; with `god on` the player takes nothing and still bounces; `HitInfo.cause` is
## `ram`; the setting `ram_damage` switches it off. Above the tunnelling threshold, a pass 0.3 m clear of a hull is no ram, and
## a pair that survives a swept ram takes it once, not again when Jolt bounces them. The inner class runs the real main scene:
## the resolver's place in the tick, and ram kills count.
##
## The ships fly in real physics ticks (Jolt, the real `RamResolver` at priority 210). ALPHA 1 is the player (god mode applies to
## it), at the origin with its nose along -z; ALPHA 2 faces it from -z.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_SPEC_PATH: String = "res://assets/ships/raider_delta_v.tres"
const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"
const FACING_ALPHA := Basis(Vector3.UP, PI)
## Origin to origin at the start of a slow head-on: the gun mounts touch at about 10 m.
const SLOW_GAP_M: float = 12.0
const SEED: int = 20261022
const TRIALS: int = 50
## AC4's "inside the hull overlap" (controller ruling): a point of one hull at least this deep inside the other. Written out
## here rather than read from RamMath.RAM_DEPTH_M, so the oracle shares nothing with the code under test.
const OVERLAP_M: float = 0.3
const SAMPLE_M: float = 0.1
const DZ_STEP_M: float = 0.25

var world: WorldFrame
var projectiles: Node3D
var rams: RamResolver
var alpha: Combatant
var bravo: Combatant
var infos: Array[HitInfo] = []
var ram_damage_backup: bool = true


func before_each() -> void:
	DebugConsole.flags.invulnerable = false
	ram_damage_backup = bool(Settings.get_value(&"ram_damage"))
	Settings.set_value(&"ram_damage", true)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	rams = RamResolver.new()
	rams.name = "RamResolver"
	add_child_autofree(rams)
	var spec := load(SPEC_PATH) as ShipSpec
	alpha = _starfury(spec, "ALPHA 1", true, Vector3.ZERO)
	bravo = _starfury(spec, "ALPHA 2", false, Vector3(0.0, 0.0, -500.0))
	infos.clear()
	rams.ram_resolved.connect(func(info: HitInfo) -> void: infos.append(info))
	await _ticks(2)


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	Settings.set_value(&"ram_damage", ram_damage_backup)


func _starfury(spec: ShipSpec, display: String, is_player: bool, at: Vector3) -> Combatant:
	var combatant: Combatant = ShipAssembly.build(spec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: display,
		ShipAssembly.OPT_IS_PLAYER: is_player,
	})
	world.spawn(combatant.ship, world.to_universe(at), Basis.IDENTITY if is_player else FACING_ALPHA)
	return combatant


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _place(combatant: Combatant, position: Vector3, basis: Basis, velocity: Vector3) -> void:
	combatant.ship.reset_to(Transform3D(basis, position))
	combatant.ship.linear_velocity = velocity


## ALPHA 1 at the origin and ALPHA 2 `gap` metres ahead of it (plus a lateral `offset`), nose to nose, closing at `closing`.
func _head_on(closing: float, gap: float = SLOW_GAP_M, offset: Vector2 = Vector2.ZERO) -> void:
	_place(alpha, Vector3.ZERO, Basis.IDENTITY, Vector3(0.0, 0.0, -0.5 * closing))
	_place(bravo, Vector3(offset.x, offset.y, -gap), FACING_ALPHA, Vector3(0.0, 0.0, 0.5 * closing))


func _info_for(combatant: Combatant) -> HitInfo:
	for info: HitInfo in infos:
		if info.target_id == combatant.ship.get_instance_id():
			return info
	return null


# --- ordinary speeds: Jolt resolves the bounce --------------------------------------------------------------------


func test_a_four_mps_bump_does_no_damage() -> void:
	_head_on(4.0)
	await _ticks(60)
	assert_lt(alpha.ship.linear_velocity.length(), 0.5, "they met and stopped (zero restitution)")
	assert_eq(alpha.damageable.hull.fraction(), 1.0)
	assert_eq(bravo.damageable.hull.fraction(), 1.0)
	assert_eq(infos.size(), 0, "a bump under the safe velocity change is no ram")
	assert_eq(rams.events, 0)


func test_a_thirty_mps_head_on_costs_each_ship_at_least_half_its_hull_once() -> void:
	_head_on(30.0)
	await _ticks(15)
	assert_lt(alpha.ship.linear_velocity.length(), 2.0, "the ships stopped each other")
	for combatant: Combatant in [alpha, bravo]:
		var hull: HullHealth = combatant.damageable.hull
		assert_lte(hull.fraction(), 0.5, "%s lost at least half its hull (%.0f %% left)" % [combatant.display_name, 100.0 * hull.fraction()])
		assert_false(hull.destroyed, "but a 30 m/s head-on wrecks, it does not destroy")
	assert_eq(infos.size(), 2, "one ram per ship")
	var on_alpha: HitInfo = _info_for(alpha)
	var on_bravo: HitInfo = _info_for(bravo)
	assert_not_null(on_alpha)
	assert_not_null(on_bravo)
	if on_alpha == null or on_bravo == null:
		return
	assert_eq(on_alpha.cause, HitInfo.CAUSE_RAM)
	assert_eq(on_bravo.cause, HitInfo.CAUSE_RAM)
	assert_eq(on_alpha.shooter_id, bravo.ship.get_instance_id(), "the other ship is the 'shooter'")
	assert_eq(on_bravo.shooter_id, alpha.ship.get_instance_id())
	assert_eq(on_alpha.faction, Factions.EARTH_ALLIANCE, "the other ship's faction: rams ignore relations")
	assert_almost_eq(on_alpha.relative_speed_mps, 30.0, 0.5)
	assert_gt(on_alpha.applied, 0.0)
	# The ships stay in contact for a while: no damage every tick of a resting contact.
	var hp_after: float = alpha.damageable.hull.hp
	await _ticks(45)
	assert_eq(infos.size(), 2, "still one ram per ship")
	assert_eq(alpha.damageable.hull.hp, hp_after)
	assert_eq(rams.events, 2)


func test_god_mode_spares_the_player_and_the_bounce_still_happens() -> void:
	DebugConsole.flags.invulnerable = true
	_head_on(30.0)
	await _ticks(15)
	assert_eq(alpha.damageable.hull.fraction(), 1.0, "god mode: the player takes nothing")
	assert_lt(alpha.ship.linear_velocity.length(), 2.0, "and still bounces: its 15 m/s are gone")
	assert_lte(bravo.damageable.hull.fraction(), 0.5, "the other ship is not protected")
	var on_alpha: HitInfo = _info_for(alpha)
	assert_not_null(on_alpha, "the ram still reaches the player's hull (hit_taken)")
	if on_alpha != null:
		assert_gt(on_alpha.damage, 0.0)
		assert_eq(on_alpha.applied, 0.0)


func test_with_ram_damage_off_the_ships_bounce_and_take_nothing() -> void:
	Settings.set_value(&"ram_damage", false)
	_head_on(30.0)
	await _ticks(15)
	assert_lt(alpha.ship.linear_velocity.length(), 2.0, "Jolt still bounces them")
	assert_eq(alpha.damageable.hull.fraction(), 1.0)
	assert_eq(bravo.damageable.hull.fraction(), 1.0)
	assert_eq(infos.size(), 0)
	Settings.set_value(&"ram_damage", true)
	await _ticks(5)
	assert_eq(infos.size(), 0, "switching it back on does not ram a contact that began while it was off")


# --- tunnelling speeds: the swept test ----------------------------------------------------------------------------


## Whether ALPHA 2, flown along z at lateral `offset`, puts a point of either hull at least OVERLAP_M inside the other somewhere
## along the pass: "inside the hull overlap" as the controller ruled for AC4. Real geometry only, nothing the sweep under test
## uses. Points on a SAMPLE_M grid inside a volume of one ship are tested with `HitShape.contains` against a volume of the other
## shrunk by OVERLAP_M, at every DZ_STEP_M of the pass and both ways round. A sampled point can only be really inside, so an
## offset this accepts truly overlaps; a thin overlap the grid misses only makes the oracle stricter.
func _hulls_overlap(offset: Vector2) -> bool:
	var shapes: Array[HitShape] = alpha.damageable.shapes  # both ships are Starfuries
	var abreast := Transform3D(FACING_ALPHA, Vector3(offset.x, offset.y, 0.0))  # ALPHA 2 in ALPHA 1's frame, origins level
	for mine: HitShape in shapes:
		for theirs: HitShape in shapes:
			var mine_at: Vector3 = mine.transform.origin
			var theirs_at: Vector3 = abreast * theirs.transform.origin
			var reach: float = _reach(mine) + _reach(theirs) - OVERLAP_M
			var lateral: float = Vector2(mine_at.x - theirs_at.x, mine_at.y - theirs_at.y).length()
			if lateral > reach:
				continue  # never near each other on this pass
			var half_range: float = sqrt(reach * reach - lateral * lateral)
			var dz: float = mine_at.z - theirs_at.z - half_range
			while dz <= mine_at.z - theirs_at.z + half_range:
				var bravo_pose := Transform3D(FACING_ALPHA, Vector3(offset.x, offset.y, dz))
				if (_deep_point(mine, Transform3D.IDENTITY, theirs, bravo_pose)
						or _deep_point(theirs, bravo_pose, mine, Transform3D.IDENTITY)):
					return true
				dz += DZ_STEP_M
	return false


## Radius of a sphere round a volume's centre that holds it.
static func _reach(shape: HitShape) -> float:
	return shape.half_extents.length() if shape.kind == HitShape.Kind.BOX else shape.half_segment + shape.radius


## Whether a grid point inside `a` (its body placed by `a_pose`) is at least OVERLAP_M inside `b` (its body placed by `b_pose`).
## The grid covers `a`'s own box, cut down to where `b` (shrunk) can be.
static func _deep_point(a: HitShape, a_pose: Transform3D, b: HitShape, b_pose: Transform3D) -> bool:
	var a_local: Transform3D = a_pose * a.transform  # a's own frame -> the shared frame
	var to_a: Transform3D = a_local.affine_inverse()
	var to_b_body: Transform3D = b_pose.affine_inverse()
	var a_half: Vector3 = a.half_extents if a.kind == HitShape.Kind.BOX else Vector3(a.radius, a.half_segment + a.radius, a.radius)
	var b_half: Vector3 = b.half_extents if b.kind == HitShape.Kind.BOX else Vector3(b.radius, b.half_segment + b.radius, b.radius)
	b_half -= Vector3.ONE * OVERLAP_M
	if b_half.x < 0.0 or b_half.y < 0.0 or b_half.z < 0.0:
		return false  # too thin to hold a point that deep
	var b_frame: Transform3D = b_pose * b.transform
	var low := Vector3.INF
	var high := -Vector3.INF
	for corner: int in 8:
		var c := Vector3(b_half.x * (1.0 if corner & 1 else -1.0), b_half.y * (1.0 if corner & 2 else -1.0),
				b_half.z * (1.0 if corner & 4 else -1.0))
		var in_a: Vector3 = to_a * (b_frame * c)
		low = low.min(in_a)
		high = high.max(in_a)
	low = low.max(-a_half)
	high = high.min(a_half)
	if low.x > high.x or low.y > high.y or low.z > high.z:
		return false
	var x: float = low.x
	while x <= high.x:
		var y: float = low.y
		while y <= high.y:
			var z: float = low.z
			while z <= high.z:
				var shared: Vector3 = a_local * Vector3(x, y, z)
				if a.contains(a.transform * Vector3(x, y, z)) and b.contains(to_b_body * shared, -OVERLAP_M):
					return true
				z += SAMPLE_M
			y += SAMPLE_M
		x += SAMPLE_M
	return false


func test_a_six_hundred_mps_head_on_destroys_both_for_fifty_seeded_offsets() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var survivors: Array[String] = []
	var tried: int = 0
	var rejected: int = 0
	while tried < TRIALS:
		var offset := Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-8.0, 8.0))
		if not _hulls_overlap(offset):
			rejected += 1
			continue
		tried += 1
		alpha.damageable.restore()
		bravo.damageable.restore()
		# A new encounter: the last trial's swept ram, a few ticks ago, must not count as this one (its grace ticks).
		rams.tracker.reset()
		# 600 m/s closing is 10 m per tick; the start gap's phase moves where in a tick the hulls meet.
		_head_on(600.0, 40.0 + rng.randf_range(0.0, 10.0), offset)
		for i: int in 12:
			await _ticks(1)
			if alpha.damageable.hull.destroyed and bravo.damageable.hull.destroyed:
				break
		if not (alpha.damageable.hull.destroyed and bravo.damageable.hull.destroyed):
			survivors.append("(%.2f, %.2f): alpha %.0f %%, bravo %.0f %%" % [offset.x, offset.y,
					100.0 * alpha.damageable.hull.fraction(), 100.0 * bravo.damageable.hull.fraction()])
	assert_eq(survivors, [] as Array[String], "both destroyed at every offset (%d tried, %d outside the overlap)" % [tried, rejected])
	assert_gt(rejected, 0, "the sampled square reaches past the overlap, so its edges are exercised")
	assert_eq(infos[infos.size() - 1].cause, HitInfo.CAUSE_RAM)


func _raider(at: Vector3) -> Combatant:
	var combatant: Combatant = ShipAssembly.build(load(RAIDER_SPEC_PATH) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS,
	})
	world.spawn(combatant.ship, world.to_universe(at))
	return combatant


## The test drone (a 1 m capsule along its z, a thin 4 m wing) at `at` with orientation `basis`, flying at `velocity`. It has
## no Jolt shapes, so only the swept test can find it.
func _drone(at: Vector3, basis: Basis, velocity: Vector3) -> TargetDrone:
	var drone := (load(DRONE_SCENE) as PackedScene).instantiate() as TargetDrone
	drone.velocity = velocity
	world.spawn(drone, world.to_universe(at), basis)
	return drone


## Flies `drone` past for `ticks` and returns whether anything was rammed.
func _fly_past(ticks: int) -> int:
	for i: int in ticks:
		await _ticks(1)
	return infos.size()


func test_a_pass_under_a_raiders_belly_with_a_hand_of_clearance_is_no_ram() -> void:
	# The raider's origin sits 0.26 m above its hump's floor and 0.43 m above its lowest wing: a sphere round it as thick as
	# its nacelles (0.78 m) would stick 0.35 m out of the belly. The drone's top passes 0.3 m under the lowest point.
	var raider: Combatant = _raider(Vector3(300.0, 0.0, 0.0))
	await _ticks(2)
	_drone(Vector3(285.0, -0.431 - 0.3 - 1.0, 0.0), Basis.IDENTITY, Vector3(40.0, 0.0, 0.0))
	assert_true(RamMath.is_tunnelling(40.0, 1.0 / 60.0, raider.damageable.core_radius, 1.0), "the swept test's speed")
	assert_eq(await _fly_past(50), 0, "0.3 m clear is a near miss")
	assert_eq(raider.damageable.hull.fraction(), 1.0)


func test_a_pass_behind_a_starfurys_tail_with_a_hand_of_clearance_is_no_ram() -> void:
	# The fuselage's aft face is 0.84 m behind the Starfury's origin, its fuselage 1.24 m thick: a sphere that thick round the
	# origin would stick 0.4 m out aft. The drone, its capsule upright, passes 0.3 m behind the aft face.
	_drone(Vector3(0.0, -15.0, 0.83746 + 0.3 + 1.0), Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 40.0, 0.0))
	assert_true(RamMath.is_tunnelling(40.0, 1.0 / 60.0, alpha.damageable.core_radius, 1.0), "the swept test's speed")
	assert_eq(await _fly_past(50), 0, "0.3 m clear is a near miss")
	assert_eq(alpha.damageable.hull.fraction(), 1.0)


func test_a_pair_that_survives_a_swept_ram_takes_it_once() -> void:
	# Two raiders, one dropping belly first onto the other at 29 m/s: past the tunnelling threshold, so the sweep finds it; each
	# changes velocity by 14.5 m/s (the momentum split), under the raider's lethal 15. Jolt then bounces them for real.
	var lower: Combatant = _raider(Vector3(300.0, 0.0, 0.0))
	var upper: Combatant = _raider(Vector3(300.0, 3.0, 0.0))
	await _ticks(2)
	lower.ship.linear_velocity = Vector3(0.0, 14.5, 0.0)
	upper.ship.linear_velocity = Vector3(0.0, -14.5, 0.0)
	await _ticks(40)
	assert_lt((upper.ship.linear_velocity - lower.ship.linear_velocity).length(), 5.0, "Jolt stopped them against each other")
	assert_eq(infos.size(), 2, "one ram each: the bounce after the swept ram is the same collision")
	assert_string_contains(rams.last_ram, "tunnelling", false)
	var expected: float = RamMath.damage(14.5, 5.0, 15.0, 60.0)
	for combatant: Combatant in [lower, upper]:
		assert_false(combatant.damageable.hull.destroyed)
		assert_almost_eq(combatant.damageable.hull.hp, 60.0 - expected, 0.01, "%s took one ram" % combatant.ship.name)


# --- props without a body: the momentum split ---------------------------------------------------------------------


func test_ramming_a_buoy_at_forty_mps_destroys_it_and_spares_the_ship() -> void:
	var buoy: NavBuoy = NavBuoy.create("NAV TEST")
	world.spawn(buoy, world.to_universe(Vector3(0.0, 0.0, -30.0)))
	_place(alpha, Vector3.ZERO, Basis.IDENTITY, Vector3(0.0, 0.0, -40.0))
	for i: int in 60:
		await _ticks(1)
		if buoy.damageable.hull.destroyed:
			break
	assert_true(buoy.damageable.hull.destroyed, "the 2 t buoy's own velocity change is 38.4 m/s")
	assert_eq(alpha.damageable.hull.fraction(), 1.0, "the 48 t Starfury's is 1.6 m/s: no damage")
	assert_eq(infos.size(), 1)
	if infos.size() == 1:
		assert_eq(infos[0].cause, HitInfo.CAUSE_RAM)
		assert_eq(infos[0].target_id, buoy.get_instance_id())
		assert_eq(infos[0].shooter_id, alpha.ship.get_instance_id())


# --- console -----------------------------------------------------------------------------------------------------


func test_the_console_reports_the_rams() -> void:
	_head_on(30.0)
	await _ticks(15)
	var results: Array[ConsoleResult] = DebugConsole.registry.execute("get ram.events; get ram.last; get ram.resolve_us")
	assert_eq(results.size(), 3)
	assert_true(results.all(func(r: ConsoleResult) -> bool: return r.ok))
	assert_eq(results[0].lines, PackedStringArray(["ram.events = 2"]))
	assert_string_contains(results[1].lines[0], "contact")
	assert_string_contains(results[1].lines[0], "ALPHA")


func test_the_ram_damage_setting_is_a_bool_that_defaults_on() -> void:
	var schema := SettingsSchema.new()
	assert_true(schema.has_key(&"ram_damage"))
	assert_eq(schema.get_type(&"ram_damage"), TYPE_BOOL)
	assert_eq(schema.get_default(&"ram_damage"), true)


# --- the real main scene ------------------------------------------------------------------------------------------


class TestInTheMainScene extends GutTest:
	var main: Main
	var source: FakeInputSource

	func before_each() -> void:
		get_tree().paused = false
		DebugConsole.flags.invulnerable = false
		source = FakeInputSource.new()
		main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
		main.input_source = source
		main.waves_auto_start = false
		add_child_autofree(main)
		for i: int in 2:
			await get_tree().physics_frame

	func after_each() -> void:
		DebugConsole.flags.invulnerable = false

	func test_the_ram_resolver_runs_after_the_hit_resolver_and_before_the_waves() -> void:
		var rams := main.get_node_or_null(^"Combat/RamResolver") as RamResolver
		assert_not_null(rams)
		if rams == null:
			return
		var hits := main.get_node(^"Combat/HitResolver") as HitResolver
		var waves := main.get_node(^"Combat/WaveDirector") as WaveDirector
		assert_eq(rams.process_physics_priority, RamResolver.LATE_PRIORITY)
		assert_gt(rams.process_physics_priority, hits.process_physics_priority)
		assert_lt(rams.process_physics_priority, waves.process_physics_priority)
		# The contact maths reads Ship.applied_force as this tick's: every ship must apply its forces before the resolver runs.
		assert_lt(main.ship.process_physics_priority, rams.process_physics_priority, "the player's ship")
		for combatant: Combatant in main.ships.all_ships():
			assert_lt(combatant.ship.process_physics_priority, rams.process_physics_priority, "a pooled ship")

	func test_a_raider_destroyed_by_a_ram_counts_as_a_kill() -> void:
		var rams := main.get_node(^"Combat/RamResolver") as RamResolver
		var infos: Array[HitInfo] = []
		rams.ram_resolved.connect(func(info: HitInfo) -> void: infos.append(info))
		assert_true(DebugConsole.registry.execute("spawn raider 40")[0].ok)
		var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
		raider.driver.process_mode = Node.PROCESS_MODE_DISABLED  # a sitting duck: no brain steers it out of the way
		raider.damageable.hull.apply(raider.damageable.hull.max_hp - 10.0)
		main.ship.linear_velocity = main.ship.forward() * 20.0  # Jolt's speed: a contact, not a swept ram
		for i: int in 180:
			await get_tree().physics_frame
			if main.waves.kills > 0:
				break
		assert_eq(main.waves.kills, 1, "a ram kill counts")
		assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 0, "the raider is back in the pool")
		var on_raider: HitInfo = null
		for info: HitInfo in infos:
			if info.target_id == raider.ship.get_instance_id():
				on_raider = info
		assert_not_null(on_raider)
		if on_raider != null:
			assert_eq(on_raider.cause, HitInfo.CAUSE_RAM)
			assert_eq(on_raider.shooter_id, main.ship.get_instance_id())
		assert_true(main.player_alive, "a 20 m/s ram on a 20 t raider costs the player little")
