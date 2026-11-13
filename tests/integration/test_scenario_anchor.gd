extends GutTest
## A World anchored where a scenario says (M6-T09, D64): on the station's rail with the scenario's origin beside it, the
## bodies, the scaled-space layer and the HUD's station reference all see the station where the scenario put it, at the
## scenario's epoch, through a position rebase and off the anchor after a velocity rebase; on an orbit, the anchor falls from
## the scenario's state.

const PLANET: StringName = &"epsilon_iii"
const STATION: StringName = &"babylon5"
const AT := Vector3(5500.0, -1200.0, -6000.0)
const EPOCH_S: float = 540148.0

var world: WorldFrame
var system: StarSystem
var _clock_backup: float


func before_each() -> void:
	_clock_backup = SimClock.now()
	SimClock.reset(0.0)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	system = StarSystem.load_system(&"local")
	assert_true(system.is_valid(), "; ".join(system.errors))


func after_each() -> void:
	SimClock.reset(_clock_backup)


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _anchor_beside_the_station() -> Dictionary:
	var spec: Variant = ScenarioFrame.parse({"place": "babylon5", "at": [AT.x, AT.y, AT.z]}, EPOCH_S, "t")
	var frame: Dictionary = ScenarioFrame.resolve(spec, system, 0, PackedFloat64Array([0, 0, 0]), Vector3.FORWARD)
	assert_true(frame["ok"], frame["error"])
	world.epoch_s = frame["epoch_s"]
	assert_true(world.anchor_on_rail(system, frame["id"], frame["offset"]))
	return frame


# A body or place's centre in the scenario's coordinates, from the World's core (64-bit).
func _in_scene(id: StringName) -> PackedFloat64Array:
	var local: PackedFloat64Array = world.body_state(id)
	return PackedFloat64Array([local[0] + world.origin.x, local[1] + world.origin.y, local[2] + world.origin.z])


static func _v(a: PackedFloat64Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func test_the_core_sees_the_station_where_the_scenario_put_it_at_the_epoch() -> void:
	var frame: Dictionary = _anchor_beside_the_station()
	assert_eq(world.anchor_text(), "rail babylon5")
	assert_almost_eq(world.system_time(), EPOCH_S, 1.0e-9, "the system time starts at the epoch; the sim clock at 0")
	assert_almost_eq(_v(_in_scene(STATION)), AT, Vector3.ONE * 1.0e-3, "the station where the scenario says")
	var planet: Vector3 = _v(ScenarioFrame.place_in_scene(frame, system, PLANET, EPOCH_S))
	assert_almost_eq(_v(_in_scene(PLANET)), planet, Vector3.ONE * 1.0, "the planet at the epoch's place")
	world.epoch_s = 0.0
	world.sample_gravity(world.system_time())
	assert_gt(_v(_in_scene(PLANET)).distance_to(planet), 1.0e7, "another epoch, another place: the epoch is used")
	world.epoch_s = EPOCH_S
	world.sample_gravity(world.system_time())
	assert_false(world.gravity_active(), "the station's orbit is outside the planet's zone: nothing pulls")


func test_a_position_rebase_and_a_velocity_rebase_keep_the_station_in_place() -> void:
	_anchor_beside_the_station()
	world.rebase(Vector3(3000.0, 0.0, -2000.0))
	assert_almost_eq(_v(_in_scene(STATION)), AT, Vector3.ONE * 1.0e-3, "after a position rebase")
	assert_almost_eq(world.universe_to_local(UniversePos.new(AT.x, AT.y, AT.z)), AT - Vector3(3000.0, 0.0, -2000.0),
			Vector3.ONE * 1.0e-3)
	world.apply_boost(Vector3(2500.0, 0.0, 0.0))
	await _ticks(20)
	assert_false(world.riding())
	var moved: Vector3 = UniversePos.new(3000.0, 0.0, -2000.0).offset_to(world.origin)
	assert_gt(moved.x, 700.0, "the local origin flew on with the frame")
	assert_almost_eq(_v(_in_scene(STATION)), AT, Vector3.ONE * 0.05, "the station stays where the scenario put it")
	world.apply_boost_to_anchor()
	await _ticks(2)
	assert_almost_eq(_v(_in_scene(STATION)), AT, Vector3.ONE * 0.05, "and back on the anchor")


func test_the_layer_and_the_reference_see_the_station_beside_the_origin() -> void:
	var frame: Dictionary = _anchor_beside_the_station()
	var planet: Vector3 = _v(ScaledSpace.body_from_anchor(world, PLANET, EPOCH_S))
	assert_almost_eq(planet, _v(ScenarioFrame.place_in_scene(frame, system, PLANET, EPOCH_S)), Vector3.ONE * 1.0e-3,
			"the scaled-space layer measures from the scenario's origin")
	var reference := FlightReference.new()
	reference.world = world
	autofree(reference)
	var places: Array[ReferenceFrame.Candidate] = reference.places(Vector3.ZERO)
	assert_eq(places[0].id, STATION)
	assert_almost_eq(places[0].position, AT, Vector3.ONE * 1.0e-3, "the HUD's station reference is at the station")


func test_an_orbit_anchor_falls_from_the_scenario_state() -> void:
	var spec: Variant = ScenarioFrame.parse({"body": "epsilon_iii", "altitude_m": 400000, "phase_deg": 40}, 1000.0, "t")
	var frame: Dictionary = ScenarioFrame.resolve(spec, system, 0, PackedFloat64Array([0, 0, 0]), Vector3.FORWARD)
	assert_true(frame["ok"], frame["error"])
	world.epoch_s = frame["epoch_s"]
	assert_true(world.anchor_in_orbit(system, frame["id"], frame["state"]))
	assert_eq(world.anchor_text(), "orbit epsilon_iii")
	assert_eq(_v(world.anchor_offset), Vector3.ZERO, "on an orbit the scenario's origin is the anchor")
	var state: PackedFloat64Array = world.anchor_state()
	assert_almost_eq(_v(state), _v(frame["state"]), Vector3.ONE * 1.0, "the anchor where the scenario's orbit puts it")
	assert_true(world.gravity_active(), "400 km up, the planet pulls")
	assert_almost_eq(_v(_in_scene(PLANET)), -_v(frame["state"]), Vector3.ONE * 1.0, "the planet below")
