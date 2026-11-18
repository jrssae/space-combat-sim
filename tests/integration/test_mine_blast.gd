extends GutTest
## A mine that goes off explodes (M7-T64 follow-up): each detonation, shot, touched, triggered or chained, is drawn once at the
## mine's place by `DestructionDirector`, at the death explosions' level of detail (the full effect near, a reduced one farther,
## a point flash far away), with its fireball as big as the blast and a cap on the explosions alive at once.

const DT: float = 1.0 / 60.0

var world: WorldFrame
var effects: Node3D
var standins: StandinDirector
var director: DestructionDirector
var camera: Camera3D
var sim: SimCore
var now_s: float = 0.0
var sounds: Array[Vector3] = []


func before_each() -> void:
	ContactScan.invalidate()
	StaticRows.clear()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	effects = Node3D.new()
	effects.name = "Effects"
	world.add_child(effects)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	director = DestructionDirector.new()
	director.world = world
	director.effects = effects
	world.add_child(director)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	standins = StandinDirector.new()
	standins.name = "Standins"
	standins.world = world
	standins.projectiles = projectiles
	world.add_child(standins)
	standins.set_physics_process(false)  # stepped by hand
	sim = SimCore.for_tree(get_tree())
	now_s = SimClock.now() + 100.0
	sounds.clear()
	director.mine_exploded.connect(func(at: Vector3) -> void: sounds.append(at))


func after_each() -> void:
	StaticRows.clear()
	ContactScan.invalidate()
	Factions.reset()


func _step() -> void:
	sim.sync_now()
	standins.step(DT, now_s)
	now_s += DT


func _mines(offsets: Array[Vector3]) -> MineStandin:
	var rows: Array[Dictionary] = []
	for at: Vector3 in offsets:
		rows.append({"offset": at, "faction": Factions.RAIDERS})
	return standins.add_mines(rows, world.to_universe(Vector3.ZERO))


func _explosions() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in effects.get_children():
		if child is Explosion and not child.is_queued_for_deletion():
			out.append(child as Explosion)
	return out


func _flash_count() -> int:
	var flashes: FarFlashes = FarFlashes.of(world)
	return flashes.flash_count() if flashes != null else 0


func _radius() -> float:
	return MineStandin.BLAST_RADIUS_M / Explosion.FIREBALL_FINAL_SCALE


# Where a mine's fireball is `px` pixels in radius on this picture, m.
func _switch_m(px: float) -> float:
	return ExplosionLod.switch_distance_m(_radius(), ExplosionLod.picture_lines(get_viewport()), camera.fov, px)


func test_a_mine_that_goes_off_shows_one_explosion_at_its_place() -> void:
	var mines: MineStandin = _mines([Vector3(30.0, 0.0, -1000.0)])
	assert_true(mines.strike(0))
	_step()
	assert_false(mines.is_alive(0), "(it went off)")
	var made: Array[Explosion] = _explosions()
	assert_eq(made.size(), 1, "one explosion")
	assert_false(made[0].reduced, "the full effect near")
	assert_almost_eq(made[0].global_position.distance_to(mines.position_of(0)), 0.0, 0.5, "at the mine")
	assert_almost_eq(made[0].radius_m * Explosion.FIREBALL_FINAL_SCALE, MineStandin.BLAST_RADIUS_M, 1e-3,
			"its fireball as big as the blast")
	assert_eq(director.mine_blasts, PackedInt32Array([1, 0, 0]))
	assert_eq(sounds.size(), 1, "and a sound")
	assert_eq(_flash_count(), 0, "no far flash")


func test_a_chain_draws_one_explosion_per_mine_and_sounds_once() -> void:
	var mines: MineStandin = _mines([Vector3(0.0, 0.0, -1000.0), Vector3(80.0, 0.0, -1000.0), Vector3(160.0, 0.0, -1000.0),
			Vector3(400.0, 0.0, -1000.0)])
	assert_true(mines.strike(0))
	_step()
	var made: Array[Explosion] = _explosions()
	assert_eq(made.size(), 3, "one per mine of the chain")
	for i: int in 3:
		var nearest: float = INF
		for explosion: Explosion in made:
			nearest = minf(nearest, explosion.global_position.distance_to(mines.position_of(i)))
		assert_lt(nearest, 0.5, "mine %d has its explosion" % i)
	assert_true(mines.is_alive(3), "(the far one stays)")
	assert_eq(sounds.size(), 1, "the chain sounds as one blast")


func test_a_mine_between_is_a_reduced_explosion() -> void:
	var at: float = 0.5 * (_switch_m(ExplosionLod.FULL_PX) + _switch_m(ExplosionLod.REDUCED_PX))
	var mines: MineStandin = _mines([Vector3(0.0, 0.0, -at)])
	assert_true(mines.strike(0))
	_step()
	var made: Array[Explosion] = _explosions()
	assert_eq(made.size(), 1)
	assert_true(made[0].reduced, "the reduced effect")
	assert_eq(sounds.size(), 0, "too far to hear")


func test_a_far_mine_is_a_point_flash_with_no_node() -> void:
	var mines: MineStandin = _mines([Vector3(0.0, 0.0, -1.3 * _switch_m(ExplosionLod.REDUCED_PX))])
	assert_true(mines.strike(0))
	var nodes_before: int = effects.get_child_count()
	_step()
	assert_false(mines.is_alive(0), "(it went off)")
	assert_eq(effects.get_child_count(), nodes_before, "no explosion node")
	assert_eq(_flash_count(), 1, "one far flash")
	assert_lt(FarFlashes.of(world).flash_position(0).distance_to(mines.position_of(0)), 1.0, "at the mine")
	assert_eq(director.mine_blasts, PackedInt32Array([0, 0, 1]))


func test_past_the_cap_a_mine_blast_is_a_point_flash() -> void:
	var offsets: Array[Vector3] = []
	var count: int = DestructionDirector.MINE_BLASTS_MAX + 3
	for i: int in count:
		offsets.append(Vector3(300.0 * i - 2000.0, 0.0, -1500.0))  # 300 m apart: no chain
	var mines: MineStandin = _mines(offsets)
	for i: int in count:
		assert_true(mines.strike(i))
	_step()
	assert_eq(mines.alive_count(), 0, "(all went off)")
	assert_eq(_explosions().size(), DestructionDirector.MINE_BLASTS_MAX, "explosions up to the cap")
	assert_eq(_flash_count(), 3, "the rest are far flashes")


func test_the_console_sets_off_the_nearest_mine_and_it_explodes() -> void:
	var drone := (load("res://tests/fixtures/target_drone.tscn") as PackedScene).instantiate() as TargetDrone
	drone.set_physics_process(false)
	world.spawn(drone, world.to_universe(Vector3.ZERO))
	drone.damageable.respects_god_mode = true  # stands in for the player
	var mines: MineStandin = _mines([Vector3(0.0, 0.0, -3000.0), Vector3(0.0, 0.0, -1000.0)])
	assert_true(DebugConsole.registry.execute("mines set_off")[0].ok)
	_step()
	assert_false(mines.is_alive(1), "the nearest went off")
	assert_true(mines.is_alive(0), "the other stays")
	assert_eq(_explosions().size(), 1, "and explodes")
