extends GutTest
## UniversePos: 64-bit storage and arithmetic (architecture §14.1, AC9).

const ONE_AU_M: float = 1.5e11


func test_defaults() -> void:
	var p := UniversePos.new()
	assert_eq(p.x, 0.0)
	assert_eq(p.y, 0.0)
	assert_eq(p.z, 0.0)
	assert_eq(p.system_id, &"local")


func test_init_sets_fields() -> void:
	var p := UniversePos.new(1.0, -2.0, 3.5, &"epsilon")
	assert_eq(p.x, 1.0)
	assert_eq(p.y, -2.0)
	assert_eq(p.z, 3.5)
	assert_eq(p.system_id, &"epsilon")


func test_from_array_accepts_ints_and_floats() -> void:
	var p: UniversePos = UniversePos.from_array([1, 2.5, -3])
	assert_not_null(p)
	assert_eq(p.x, 1.0)
	assert_eq(p.y, 2.5)
	assert_eq(p.z, -3.0)
	assert_eq(p.system_id, &"local")


func test_from_array_keeps_64_bit_values() -> void:
	# JSON parses to 64-bit floats; 1e11 + 0.5 is exactly representable in double but not in float32.
	var p: UniversePos = UniversePos.from_array([1e11 + 0.5, 0.0, 0.0])
	assert_eq(p.x, 1e11 + 0.5)


func test_from_array_rejects_wrong_size() -> void:
	assert_null(UniversePos.from_array([1.0, 2.0]))
	assert_push_error("expected 3 elements")
	assert_null(UniversePos.from_array([1.0, 2.0, 3.0, 4.0]))
	assert_push_error("expected 3 elements")


func test_from_array_rejects_non_numbers() -> void:
	assert_null(UniversePos.from_array([1.0, "two", 3.0]))
	assert_push_error("non-numeric")


func test_plus_local_returns_new_object_in_same_system() -> void:
	var p := UniversePos.new(10.0, 20.0, 30.0, &"epsilon")
	var q: UniversePos = p.plus_local(Vector3(1.0, -2.0, 4.0))
	assert_ne(q, p, "a new object")
	assert_eq(p.x, 10.0, "original untouched")
	assert_eq(q.x, 11.0)
	assert_eq(q.y, 18.0)
	assert_eq(q.z, 34.0)
	assert_eq(q.system_id, &"epsilon")


func test_offset_to_is_antisymmetric() -> void:
	var a := UniversePos.new(100.0, 200.0, 300.0)
	var b := UniversePos.new(103.0, 196.0, 300.5)
	assert_eq(a.offset_to(b), Vector3(3.0, -4.0, 0.5))
	assert_eq(b.offset_to(a), -a.offset_to(b))


func test_distance_to() -> void:
	var a := UniversePos.new(1.0, 2.0, 3.0)
	assert_almost_eq(a.distance_to(UniversePos.new(4.0, 6.0, 3.0)), 5.0, 1e-12)
	assert_eq(a.distance_to(a), 0.0)


func test_precision_survives_at_1e11_m() -> void:
	# At 1e11 m a float32 spacing is 8192 m, a double's is 1.5e-5 m. A 0.25 m step must survive exactly.
	var p := UniversePos.new(1e11, -1e11, 1e11)
	var q: UniversePos = p.plus_local(Vector3(0.25, -0.5, 0.125))
	assert_eq(q.x, 1e11 + 0.25)
	assert_eq(q.y, -1e11 - 0.5)
	assert_eq(q.z, 1e11 + 0.125)
	assert_eq(p.offset_to(q), Vector3(0.25, -0.5, 0.125))
	assert_almost_eq(p.distance_to(q), sqrt(0.25 * 0.25 + 0.5 * 0.5 + 0.125 * 0.125), 1e-12)


func test_a_vector3_cannot_hold_what_universe_pos_holds() -> void:
	# Why UniversePos exists: the same 0.25 m step vanishes in float32 at 1e11 m.
	assert_eq(Vector3(1e11 + 0.25, 0.0, 0.0).x, Vector3(1e11, 0.0, 0.0).x)
	var p := UniversePos.new(1e11, 0.0, 0.0)
	assert_ne(p.plus_local(Vector3(0.25, 0.0, 0.0)).x, p.x)


func test_round_trip_at_one_au_within_a_millimetre() -> void:
	# AC9: positions at 1.5e11 m round-trip with < 1 mm error. Offsets are float32 values, as they would be in play.
	var base := UniversePos.new(ONE_AU_M, -ONE_AU_M, 0.5 * ONE_AU_M)
	for local: Vector3 in [Vector3(1234.567, -89.01, 4.5), Vector3(-9999.9, 8000.1, 0.001), Vector3(0.3, 0.2, 0.1)]:
		var there: UniversePos = base.plus_local(local)
		var back: Vector3 = base.offset_to(there)
		assert_almost_eq(back, local, Vector3(1e-3, 1e-3, 1e-3), "round trip of %s" % local)
		assert_almost_eq(there.distance_to(base), local.length(), 1e-3)


func test_distance_between_far_apart_positions_keeps_64_bit_precision() -> void:
	var a := UniversePos.new(0.0, 0.0, 0.0)
	var b := UniversePos.new(ONE_AU_M, 0.0, 0.0)
	assert_eq(a.distance_to(b), ONE_AU_M)
	# Two points one AU out whose separation is a 3-4-5 triangle.
	var c := UniversePos.new(ONE_AU_M + 3.0, 4.0, 0.0)
	assert_almost_eq(b.distance_to(c), 5.0, 1e-6)


func test_to_string_names_system_and_coordinates() -> void:
	var text: String = str(UniversePos.new(1.0, 2.0, 3.0, &"epsilon"))
	assert_string_contains(text, "epsilon")
	assert_string_contains(text, "1.000")
