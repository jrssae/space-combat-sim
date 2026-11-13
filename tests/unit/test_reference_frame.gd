extends GutTest
## `ReferenceFrame` (M6-T08, D67, Q4 to Q6): Q6's pick with its hysteresis and the mission's word, the circular orbit's rest
## velocity against a body (a steady orbit reads about 0), what a reference falls with, and the altitude rule.

const GM: float = 3.986e14
const RADIUS_M: float = 6.371e6
const ORBIT_M: float = RADIUS_M + 4.0e5
const Candidate := ReferenceFrame.Candidate


func _station(at: Vector3 = Vector3.ZERO, range_m: float = 1.0e6) -> Candidate:
	return Candidate.place(&"babylon5", "BABYLON 5", at, Vector3(1.0, 2.0, 3.0), Vector3(0.0, -0.001, 0.0), range_m)


func _gate(at: Vector3, range_m: float = 1.0e6) -> Candidate:
	return Candidate.place(&"jumpgate", "JUMPGATE", at, Vector3(1.0, 2.0, 3.0), Vector3.ZERO, range_m)


# A planet whose centre is `ORBIT_M` below the ship (the ship at the local origin), moving at `velocity`, pulling it fully.
func _planet(velocity: Vector3 = Vector3.ZERO) -> Candidate:
	var pull: float = GM / (ORBIT_M * ORBIT_M)
	return Candidate.body(&"terra", "TERRA", Vector3(-ORBIT_M, 0.0, 0.0), velocity, RADIUS_M, 1.0e5, Vector3(-pull, 0.0, 0.0))


func test_the_nearest_place_whose_broadcast_holds_the_ship_is_picked() -> void:
	var places: Array[Candidate] = [_station(Vector3(0.0, 0.0, -50000.0)), _gate(Vector3(0.0, 0.0, 20000.0))]
	assert_eq(ReferenceFrame.pick(&"", &"", places, _planet(), Vector3.ZERO).id, &"jumpgate", "the gate is nearer")
	places = [_station(Vector3(0.0, 0.0, -50000.0)), _gate(Vector3(0.0, 0.0, 20000.0), 10000.0)]
	assert_eq(ReferenceFrame.pick(&"", &"", places, _planet(), Vector3.ZERO).id, &"babylon5", "the gate's range does not reach")
	places = [_station(Vector3(0.0, 0.0, -50000.0), 10000.0)]
	assert_eq(ReferenceFrame.pick(&"", &"", places, _planet(), Vector3.ZERO).id, &"terra", "no place: the dominant body")
	assert_null(ReferenceFrame.pick(&"", &"", places, null, Vector3.ZERO), "nothing at all: none")


func test_a_place_stays_the_reference_a_tenth_beyond_its_range() -> void:
	var places: Array[Candidate] = [_station(Vector3.ZERO, 100000.0)]
	var at := Vector3(105000.0, 0.0, 0.0)
	assert_eq(ReferenceFrame.pick(&"", &"", places, _planet(), at).id, &"terra", "a new pick needs the range itself")
	assert_eq(ReferenceFrame.pick(&"babylon5", &"", places, _planet(), at).id, &"babylon5", "the current one holds to 110 km")
	at.x = 111000.0
	assert_eq(ReferenceFrame.pick(&"babylon5", &"", places, _planet(), at).id, &"terra", "and lets go beyond it")


func test_the_missions_reference_wins_when_it_names_a_candidate() -> void:
	var places: Array[Candidate] = [_station(Vector3(0.0, 0.0, -50000.0)), _gate(Vector3(0.0, 0.0, 20000.0))]
	assert_eq(ReferenceFrame.pick(&"", &"babylon5", places, _planet(), Vector3.ZERO).id, &"babylon5")
	assert_eq(ReferenceFrame.pick(&"", &"terra", places, _planet(), Vector3.ZERO).id, &"terra")
	assert_eq(ReferenceFrame.pick(&"", &"nowhere", places, _planet(), Vector3.ZERO).id, &"jumpgate", "unknown: Q6's own pick")


func test_against_a_place_the_rest_is_the_places_motion() -> void:
	var frame := ReferenceFrame.new()
	var places: Array[Candidate] = [_station(Vector3(0.0, 0.0, -3000.0))]
	frame.update(Vector3.ZERO, Vector3(1.0, 2.0, 103.0), Vector3(0.0, -0.5, 0.0), places, null)
	assert_eq(frame.kind, ReferenceFrame.Kind.PLACE)
	assert_eq(frame.label, "BABYLON 5")
	assert_eq(frame.rest_velocity, Vector3(1.0, 2.0, 3.0))
	assert_eq(frame.rest_accel, Vector3(0.0, -0.001, 0.0), "what the place falls with, not the ship's pull")
	assert_almost_eq(frame.speed_of(Vector3(1.0, 2.0, 103.0)), 100.0, 1e-4)
	assert_true(is_nan(frame.altitude_m), "no body near")


func test_a_ship_in_a_steady_circular_orbit_reads_about_zero() -> void:
	var frame := ReferenceFrame.new()
	var circular: float = sqrt(GM / ORBIT_M)
	var planet: Candidate = _planet(Vector3(0.0, 0.0, circular))  # the planet seen from a frame falling with the ship
	var pull := Vector3(1e-4, 0.0, 0.0)
	frame.update(Vector3.ZERO, Vector3.ZERO, pull, [] as Array[Candidate], planet)
	assert_eq(frame.kind, ReferenceFrame.Kind.BODY)
	assert_lt(frame.speed_of(Vector3.ZERO), 0.01, "at rest beside the orbit's point: about 0 (%.4f m/s)" % frame.speed_of(Vector3.ZERO))
	assert_eq(frame.rest_accel, pull, "a circular orbit falls with the ship's own pull")
	assert_almost_eq(frame.altitude_m, 4.0e5, 1.0, "400 km up")
	assert_eq(frame.altitude_body, "TERRA")


func test_the_orbit_is_in_the_plane_of_the_ships_motion_at_the_circular_speed() -> void:
	var offset := Vector3(ORBIT_M, 0.0, 0.0)
	var pull: float = GM / (ORBIT_M * ORBIT_M)
	var circular: float = sqrt(GM / ORBIT_M)
	var v: Vector3 = ReferenceFrame.orbit_velocity(offset, Vector3(-300.0, 4000.0, 0.0), pull)
	assert_almost_eq(v.length(), circular, 1e-3)
	assert_almost_eq(v.normalized().dot(Vector3.UP), 1.0, 1e-6, "prograde along the ship's motion across the radius")
	v = ReferenceFrame.orbit_velocity(offset, Vector3(-300.0, 0.0, 0.0), pull)
	assert_almost_eq(v.normalized().dot(Vector3.FORWARD), 1.0, 1e-6, "no motion across: the equator, eastward (-Z here)")
	assert_eq(ReferenceFrame.orbit_velocity(offset, Vector3.ZERO, 0.0), Vector3.ZERO, "no pull, no orbit")


func test_the_altitude_shows_near_a_body_even_when_a_place_is_the_reference() -> void:
	var frame := ReferenceFrame.new()
	var places: Array[Candidate] = [_station(Vector3(0.0, 0.0, -3000.0))]
	frame.update(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, places, _planet())
	assert_eq(frame.kind, ReferenceFrame.Kind.PLACE)
	assert_almost_eq(frame.altitude_m, 4.0e5, 1.0, "within one radius of the surface")
	frame.update(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, places, _planet(), &"", 0.05)
	assert_true(is_nan(frame.altitude_m), "beyond the rule's reach and a place the reference: no altitude")


func test_with_nothing_to_read_against_the_reference_is_none() -> void:
	var frame := ReferenceFrame.new()
	frame.update(Vector3.ZERO, Vector3(5.0, 0.0, 0.0), Vector3.ZERO, [] as Array[Candidate], null)
	assert_false(frame.is_set())
	assert_eq(frame.rest_velocity, Vector3.ZERO)
	assert_eq(frame.label, "")
