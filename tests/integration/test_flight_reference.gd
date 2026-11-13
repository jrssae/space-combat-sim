extends GutTest
## Flying against a reference (M6-T08, D67, AC5): the brake stops a ship against its reference, not the frame, on the batch's
## path and on its own model; the player's `FlightReference` picks the station, then the planet; a ship that drops below the
## planet's atmosphere is destroyed, the player's ship and an AI row alike; and the automatic velocity rebase fires in a fast
## flight with the HUD's speed unchanged across it. The low orbit held with assist on is `test_low_orbit_flight.gd` (standard).

const FreeFall: GDScript = preload("res://tests/integration/test_free_fall.gd")
const STARFURY: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER: String = "res://assets/ships/raider_delta_v.tres"
const DT: float = 1.0 / 60.0

var world: WorldFrame
var projectiles: Node3D
var _fuel_backup: bool


func before_each() -> void:
	_fuel_backup = bool(Settings.get_value(&"fuel_unlimited"))
	Settings.set_value(&"fuel_unlimited", true)
	DebugConsole.flags.invulnerable = false
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func after_each() -> void:
	Settings.set_value(&"fuel_unlimited", _fuel_backup)


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# A bare ship: the player's own model (`player`), or the flight batch's path.
func _ship(at: Vector3, player: bool) -> Ship:
	var ship: Ship = Ship.create(load(STARFURY) as ShipSpec, world)
	ship.console_owner = player
	world.spawn(ship, world.to_universe(at))
	ship.assist_on = true
	return ship


func _brake() -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.brake = true
	return cmd


func _combatant(spec_path: String, at: Vector3, player: bool) -> Combatant:
	var made: Combatant = ShipAssembly.build(load(spec_path) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE if player else Factions.RAIDERS,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER" if player else "RAIDER 1",
		ShipAssembly.OPT_CONSOLE_OWNER: player,
		ShipAssembly.OPT_FORCE_ASSIST: not player,
		ShipAssembly.OPT_AI: not player,
	})
	world.spawn(made.ship, world.to_universe(at))
	return made


func test_the_brake_stops_a_ship_against_its_reference_on_both_paths() -> void:
	var cruise := Vector3(0.0, 0.0, -300.0)
	var ships: Array[Ship] = [_ship(Vector3.ZERO, true), _ship(Vector3(200.0, 0.0, 0.0), false)]
	for ship: Ship in ships:
		ship.linear_velocity = cruise
		ship.set_reference_rest(cruise, Vector3.ZERO)
		ship.set_flight_command(_brake())
	await _ticks(30)
	for ship: Ship in ships:
		assert_almost_eq(ship.linear_velocity, cruise, Vector3.ONE * 1e-3,
				"%s: at rest against its reference, the brake leaves it be" % ship.flight_path())
		assert_almost_eq(ship.speed_against_rest(), 0.0, 1e-3)
	assert_eq(ships[0].flight_path(), &"gdscript")
	assert_eq(ships[1].flight_path(), &"native")
	for ship: Ship in ships:
		ship.clear_reference_rest()
	await _ticks(30)
	for ship: Ship in ships:
		assert_lt(ship.linear_velocity.length(), 300.0 - 10.0, "%s: against the frame it brakes" % ship.flight_path())


func test_the_reference_is_the_station_inside_its_range_and_the_planet_below_it() -> void:
	var system: StarSystem = FreeFall.fixture_system()
	var radius_m: float = FreeFall.RADIUS_TERRA_M + FreeFall.ALTITUDE_M
	assert_true(world.anchor_on_rail(system, &"post"))
	var ship: Ship = _ship(Vector3.ZERO, true)
	ship.set_flight_command(FlightCommand.new())
	var reference := FlightReference.new()
	reference.world = world
	reference.ship = ship
	add_child_autofree(reference)
	reference.update()
	assert_eq(reference.frame.kind, ReferenceFrame.Kind.PLACE, "beside the post: the place the World falls with")
	assert_eq(reference.frame.label, "POST")
	assert_almost_eq(reference.frame.altitude_m, FreeFall.ALTITUDE_M, 2.0, "400 km up: within one radius, so shown")
	assert_eq(ship.rest_velocity(), Vector3.ZERO, "the post is the anchor: at rest in the riding frame")
	var range_backup: Variant = Settings.get_value(&"reference_place_range_km")
	Settings.set_value(&"reference_place_range_km", 1.0)
	# 2 km along the track on the same circle: the circular velocity there is the post's turned by 2 km / r, and the frame
	# rides the post (its state from the anchor, so the clock's time does not matter).
	var state: PackedFloat64Array = world.anchor_state()
	var post := Vector3(state[0], state[1], state[2])
	var post_v := Vector3(state[3], state[4], state[5])
	var at: Vector3 = post_v.normalized() * 2000.0
	var normal: Vector3 = post.cross(post_v).normalized()
	var circular: float = sqrt(FreeFall.GM_TERRA / (post + at).length())
	var post_speed: float = post_v.length()
	ship.global_position = at
	ship.linear_velocity = normal.cross((post + at).normalized()) * circular - post_v
	reference.update()
	assert_eq(reference.frame.kind, ReferenceFrame.Kind.BODY, "beyond the post's range: the dominant body")
	assert_eq(reference.frame.label, "TERRA")
	assert_almost_eq(reference.speed_mps(), 0.0, 0.01,
			"on the circle 2 km along the track: the circular orbit reads about 0 (%.4f m/s; %.2f m/s against the frame, %.0f m/s round the planet)" % [
			reference.speed_mps(), ship.linear_velocity.length(), circular])
	assert_eq(ship.rest_accel(), world.gravity_residual(ship.global_position), "the orbit falls with the ship's own pull")
	ship.linear_velocity = Vector3.ZERO
	reference.update()
	assert_almost_eq(reference.speed_mps(), 2000.0 / radius_m * post_speed, 0.01,
			"at rest beside the post 2 km ahead is another orbit: it reads the post's velocity turned by 2 km / r")
	Settings.set_value(&"reference_place_range_km", range_backup)


func test_a_ship_below_the_atmospheres_top_is_destroyed_the_player_and_an_ai_row_alike() -> void:
	var system: StarSystem = FreeFall.fixture_system()
	var radius_m: float = FreeFall.RADIUS_TERRA_M + FreeFall.ALTITUDE_M
	assert_true(world.anchor_in_orbit(system, &"terra", FreeFall.circular_state(radius_m, FreeFall.GM_TERRA)))
	# The planet's centre lies along -X from the anchor: 330 km down is 70 km up, under the 100 km atmosphere.
	var player: Combatant = _combatant(STARFURY, Vector3(-330000.0, 0.0, 0.0), true)
	var raider: Combatant = _combatant(RAIDER, Vector3(-330000.0, 0.0, -600.0), false)
	var high: Combatant = _combatant(RAIDER, Vector3(-250000.0, 0.0, 0.0), false)
	player.damageable.invulnerable = true  # god mode does not hold a ship up
	var downed: Array[HitInfo] = []
	for c: Combatant in [player, raider, high]:
		c.damageable.destroyed.connect(func(info: HitInfo) -> void: downed.append(info))
	await _ticks(3)
	assert_true(player.damageable.hull.destroyed, "the player's ship 70 km up")
	assert_true(raider.damageable.hull.destroyed, "an AI ship's row 70 km up")
	assert_false(high.damageable.hull.destroyed, "150 km up, above the atmosphere")
	assert_eq(downed.size(), 2)
	for info: HitInfo in downed:
		assert_eq(info.cause, HitInfo.CAUSE_PLANET)
	assert_eq(world.impact.destroyed, 2)
	assert_string_contains(world.impact.last, "TERRA")


func test_the_automatic_velocity_rebase_leaves_the_speed_against_the_reference_unchanged() -> void:
	var system: StarSystem = StarSystem.load_system(StarSystemHost.DEFAULT_SYSTEM)
	assert_true(world.anchor_on_rail(system, StarSystemHost.DEFAULT_ANCHOR))
	world.auto_boost_speed_mps = 2000.0
	var ship: Ship = _ship(Vector3.ZERO, true)
	ship.assist_on = false
	ship.set_flight_command(FlightCommand.new())
	world.focus = ship
	var reference := FlightReference.new()
	reference.world = world
	reference.ship = ship
	add_child_autofree(reference)
	ship.linear_velocity = Vector3(30.0, 0.0, -2500.0)
	var expected: float = ship.linear_velocity.length()
	var speeds: PackedFloat64Array = PackedFloat64Array()
	for i: int in 12:
		await get_tree().physics_frame
		speeds.append(_hud_speed(reference, ship))
	assert_eq(world.boosts, 1, "one velocity rebase onto the ship")
	assert_false(world.riding())
	assert_lt(ship.linear_velocity.length(), 1.0, "the ship is about at rest in the boosted frame")
	assert_eq(reference.frame.label, "BABYLON 5")
	for speed: float in speeds:
		assert_almost_eq(speed, expected, 0.01, "the HUD's speed across the boost: %s" % speeds)
	ship.linear_velocity = world.rest_velocity() + Vector3(0.0, 0.0, -100.0)
	await _ticks(3)
	assert_true(world.riding(), "under half the threshold against the anchor: back onto it")
	assert_almost_eq(_hud_speed(reference, ship), 100.0, 0.01, "and the speed reads the same through the way back")


# The HUD's speed as `Main` builds its input: the ship's velocity against the reference's.
func _hud_speed(reference: FlightReference, ship: Ship) -> float:
	var input := HudInput.new()
	input.own_velocity = ship.linear_velocity
	input.own_basis = ship.global_basis
	input.has_reference = true
	input.reference_position = ship.global_position + reference.offset
	input.reference_velocity = reference.frame.rest_velocity
	input.reference_name = reference.frame.label
	return HudLayout.compute(input).speed_mps
