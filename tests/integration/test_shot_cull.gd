extends GutTest
## Flashes and shot sounds culled by range, and the flash pool's ring (M5-T37, review L6): a flash or a gun's sound beyond
## `ShotCull` range of the camera is not made (counted, not played); the pool is a ring with a lit counter, so a full pool
## drops its oldest without shifting arrays and the frame's pass visits only the ring's span.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"

var world: WorldFrame
var camera: Camera3D
var pool: MuzzleFlashPool
var ship: Node3D


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var c: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE, ShipAssembly.OPT_DISPLAY_NAME: "S", ShipAssembly.OPT_LEAN: true})
	world.spawn(c.ship, world.to_universe(Vector3(0.0, 0.0, -100.0)))
	ship = c.ship
	pool = MuzzleFlashPool.attach(world)
	await get_tree().physics_frame


func test_a_flash_beyond_range_is_not_made_and_one_in_range_is() -> void:
	pool.trigger(ship, Transform3D.IDENTITY)
	assert_eq(pool.active_count(), 1, "in range: flashes")
	ship.global_position = Vector3(0.0, 0.0, -(ShotCull.FLASH_RANGE_M + 100.0))
	var started: int = pool.started
	assert_false(pool.trigger(ship, Transform3D.IDENTITY))
	assert_eq(pool.started, started, "nothing started")
	assert_eq(pool.culled, 1, "counted as culled")
	assert_eq(pool.active_count(), 1)


func test_a_full_ring_drops_the_oldest_and_keeps_its_count() -> void:
	for i: int in MuzzleFlashPool.CAPACITY + 40:
		pool.trigger(ship, Transform3D(Basis.IDENTITY, Vector3(float(i), 0.0, 0.0)))
	assert_eq(pool.active_count(), MuzzleFlashPool.CAPACITY, "capped at the ring's size")
	assert_lte(pool.lit_count(), MuzzleFlashPool.LIGHTS, "the lit counter holds the light cap")
	pool.advance(0.0)
	assert_eq(pool.drawn, MuzzleFlashPool.CAPACITY, "every live flash drawn")
	assert_eq(pool.advance_work, MuzzleFlashPool.CAPACITY, "the pass visits the ring's span")


func test_the_pass_follows_the_live_flashes_not_the_capacity() -> void:
	for i: int in 3:
		pool.trigger(ship, Transform3D.IDENTITY)
	pool.advance(0.01)
	assert_eq(pool.advance_work, 3)
	pool.advance(0.1)  # all expired
	assert_eq(pool.active_count(), 0)
	assert_eq(pool.lit_count(), 0, "their lights ended with them")
	pool.advance(0.01)
	assert_eq(pool.advance_work, 0, "an empty ring costs nothing")


func test_clearing_a_ship_leaves_the_ring_consistent() -> void:
	pool.trigger(ship, Transform3D.IDENTITY)
	pool.trigger(ship, Transform3D.IDENTITY)
	pool.clear_for(ship)
	assert_eq(pool.active_count(), 0)
	assert_eq(pool.lit_count(), 0)
	pool.trigger(ship, Transform3D.IDENTITY)
	pool.advance(0.0)
	assert_eq(pool.drawn, 1, "the ring keeps working after a clear")


func test_the_cull_maths() -> void:
	assert_true(ShotCull.within(Vector3.ZERO, Vector3(0.0, 0.0, 2999.0), ShotCull.SOUND_RANGE_M))
	assert_false(ShotCull.within(Vector3.ZERO, Vector3(0.0, 0.0, 3001.0), ShotCull.SOUND_RANGE_M))
