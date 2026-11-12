extends GutTest
## The engine voices' ship query on the core (M5-T28, D60): `ScsSimCore.ships_near` lists the ships with a node within a
## radius of the listener, nearest first, from the rows the main thread holds after the tick's sync. Tier rows, other kinds
## and parked ships are never listed, a rebase moves the answer with the ships, and 300 ships far away leave the answer (and
## so the re-rank's work) as it was. Light bodies stand in for ships (a rigid body with a marker and a hull).

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const LAYOUT_PATH: String = "res://tests/fixtures/hardpoints_nominal.json"

var world: WorldFrame
var projectiles: Node3D


func before_each() -> void:
	Factions.reset()
	ContactScan.invalidate()
	ContactScan.clear_statics()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func after_each() -> void:
	ContactScan.clear_statics()
	ContactScan.invalidate()
	Factions.reset()


func _core() -> SimCore:
	var sim: SimCore = SimCore.attach(world)
	assert_not_null(sim, "a core attaches to the world")
	return sim


func _sync(sim: SimCore) -> void:
	sim.sync_now()


# A ship's stand-in: a frozen rigid body with a marker of `kind` and a hull.
func _ship(at: Vector3, kind: Targetable.Kind = Targetable.Kind.SHIP) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	world.add_child(body)
	body.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	body.global_position = at
	var hull := Damageable.new()
	hull.faction = Factions.RAIDERS
	hull.bounding_radius = 12.0
	body.add_child(hull)
	var marker := Targetable.new()
	marker.name = "Targetable"
	marker.display_name = "S%d" % body.get_instance_id()
	marker.faction = Factions.RAIDERS
	marker.kind = kind
	body.add_child(marker)
	return body


func _starfury_type(sim: SimCore) -> int:
	var spec: ShipSpec = load(SPEC_PATH) as ShipSpec
	var layout: ThrusterLayout = ThrusterLayout.load_file(LAYOUT_PATH)
	var a: Array = FlightBatch.type_arrays(spec, layout)
	return int(sim.core.tier_register_type(a[0], a[1], a[2], a[3], a[4], a[5], layout.center_of_mass))


func _tier_row(sim: SimCore, type_ix: int, body_id: int, at: Vector3) -> void:
	sim.core.tier_add(SimCore.KIND_SHIP, body_id, 0, type_ix, at, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO)
	sim.core.tier_set_attrs(body_id, body_id + 500000, Factions.RAIDERS, "TIER %d" % body_id, 12.0, 0.0, 1.0)
	sim.core.tier_set_control(body_id, Vector3.ZERO, PackedFloat64Array(), 0.0, false)


func _near(sim: SimCore, radius: float = EngineVoices.AUDIBLE_RANGE_M) -> Array:
	return sim.ships_near(Vector3.ZERO, radius)


func test_ships_in_earshot_come_back_nearest_first_with_their_squared_distance() -> void:
	var far: RigidBody3D = _ship(Vector3(0.0, 0.0, -900.0))
	var close: RigidBody3D = _ship(Vector3(30.0, 40.0, 0.0))
	var mid: RigidBody3D = _ship(Vector3(0.0, 400.0, 0.0))
	_ship(Vector3(0.0, 0.0, EngineVoices.AUDIBLE_RANGE_M + 100.0))
	var sim: SimCore = _core()
	_sync(sim)
	var found: Array = _near(sim)
	var ids: PackedInt64Array = found[0]
	var distances: PackedFloat64Array = found[1]
	assert_eq(ids, PackedInt64Array([close.get_instance_id(), mid.get_instance_id(), far.get_instance_id()]))
	assert_eq(distances, PackedFloat64Array([2500.0, 160000.0, 810000.0]))


func test_other_kinds_parked_ships_and_tier_rows_are_never_listed() -> void:
	var live: RigidBody3D = _ship(Vector3(0.0, 0.0, 100.0))
	_ship(Vector3(0.0, 0.0, 110.0), Targetable.Kind.CAPITAL)
	var parked: RigidBody3D = _ship(Vector3(0.0, 0.0, 120.0))
	parked.visible = false
	parked.process_mode = Node.PROCESS_MODE_DISABLED
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	assert_gte(type_ix, 0)
	for i: int in 5:
		_tier_row(sim, type_ix, 900000 + i, Vector3(0.0, 0.0, 50.0 + float(i)))  # nearer than any ship, in range
	_sync(sim)
	assert_eq(sim.rows(), 7, "the ship, the capital and the five tier rows have rows; the parked ship has none")
	assert_eq(_near(sim)[0], PackedInt64Array([live.get_instance_id()]), "only the live ship with a node")


func test_ships_far_away_leave_the_answer_as_it_was() -> void:
	var near: Array[RigidBody3D] = [_ship(Vector3(0.0, 0.0, 100.0)), _ship(Vector3(0.0, 0.0, 200.0)), _ship(Vector3(0.0, 0.0, 300.0))]
	var sim: SimCore = _core()
	_sync(sim)
	var before: Array = _near(sim)
	for i: int in 300:
		_ship(Vector3(60000.0 + float(i), 0.0, 0.0))
	_sync(sim)
	assert_eq(sim.rows(), 303, "the rows grew by 300")
	var after: Array = _near(sim)
	assert_eq((after[0] as PackedInt64Array).size(), 3, "three ships in earshot, 303 in play")
	assert_eq(after, before)
	assert_eq((after[0] as PackedInt64Array)[0], near[0].get_instance_id())


func test_a_rebase_moves_the_answer_with_the_ships() -> void:
	var ship: RigidBody3D = _ship(Vector3(0.0, 0.0, 5000.0))
	var sim: SimCore = _core()
	_sync(sim)
	assert_eq((_near(sim)[0] as PackedInt64Array).size(), 0, "out of earshot")
	sim.core.shift(Vector3(0.0, 0.0, -4500.0))
	assert_eq(_near(sim)[0], PackedInt64Array([ship.get_instance_id()]), "the rows moved with the world")


func test_the_library_without_a_core_answers_empty() -> void:
	var sim := SimCore.new()  # never attached: no core object
	var found: Array = sim.ships_near(Vector3.ZERO, 1500.0)
	assert_eq((found[0] as PackedInt64Array).size(), 0)
	assert_eq((found[1] as PackedFloat64Array).size(), 0)
	sim.free()
