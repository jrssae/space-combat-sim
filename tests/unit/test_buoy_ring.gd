extends GutTest
## BuoyRing (architecture §18, M5-T10, Q21): Buoy defence's 16 nav buoys sit evenly on a 20 000 km ring in one plane, named
## NAV ALPHA onwards, and with every buoy broadcasting to 10 000 km a ship on the ring, or near it, always hears at least two.

const RADIUS_M: float = 2.0e7
const COUNT: int = 16
## Where the two-buoy rule holds in every direction from the ring (the outward side near a buoy is the tight one).
const RULE_REACH_M: float = 4.9e6

var centre := UniversePos.new(0.0, 0.0, 2.0e7)
var ring: Array[UniversePos] = []


func before_each() -> void:
	ring = BuoyRing.positions(centre, RADIUS_M, COUNT, Vector3.UP, Vector3.FORWARD)


# Every unit direction on a coarse sphere (poles and 12 x 7 others).
func _directions() -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3.UP, Vector3.DOWN]
	for i: int in 12:
		for j: int in range(1, 8):
			var yaw: float = TAU * i / 12.0
			var pitch: float = PI * j / 8.0 - PI * 0.5
			out.append(Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw)))
	return out


# A point on the ring `angle` radians on from the first buoy (the ring turns the way the buoys are numbered).
func _on_ring(angle: float) -> UniversePos:
	var a: UniversePos = ring[0]
	var b: UniversePos = ring[1]
	var step: float = TAU / COUNT
	# The first buoy's and the second's directions from the centre span the plane: rotate between them.
	var u := Vector3((a.x - centre.x) / RADIUS_M, (a.y - centre.y) / RADIUS_M, (a.z - centre.z) / RADIUS_M)
	var w := Vector3((b.x - centre.x) / RADIUS_M, (b.y - centre.y) / RADIUS_M, (b.z - centre.z) / RADIUS_M)
	var v: Vector3 = (w - u * cos(step)) / sin(step)
	var d: Vector3 = u * cos(angle) + v * sin(angle)
	return UniversePos.new(centre.x + RADIUS_M * d.x, centre.y + RADIUS_M * d.y, centre.z + RADIUS_M * d.z)


func test_sixteen_buoys_sit_on_the_ring_evenly_spaced() -> void:
	assert_eq(ring.size(), COUNT)
	for i: int in COUNT:
		assert_almost_eq(ring[i].distance_to(centre), RADIUS_M, 1.0, "buoy %d on the ring" % i)
		assert_almost_eq(ring[i].y, centre.y, 1.0, "in the plane the normal sets")
		var next: UniversePos = ring[(i + 1) % COUNT]
		assert_almost_eq(ring[i].distance_to(next), 2.0 * RADIUS_M * sin(PI / COUNT), 1.0, "neighbours a chord apart")
	assert_almost_eq(ring[0].distance_to(ring[1]), 7.8036e6, 100.0, "about 7 800 km apart (7 850 km along the arc)")


func test_the_first_buoy_lies_along_first_from_the_centre() -> void:
	assert_almost_eq(ring[0].x, 0.0, 1e-6)
	assert_almost_eq(ring[0].z, 0.0, 1e-6, "centre 20 000 km behind, so the first buoy is at the origin")
	var tilted: Array[UniversePos] = BuoyRing.positions(centre, RADIUS_M, 4, Vector3(0.0, 1.0, 1.0), Vector3(1.0, 0.0, 0.0))
	assert_almost_eq(tilted[0].x - centre.x, RADIUS_M, 1.0, "first is kept when it already lies in the plane")
	for p: UniversePos in tilted:
		var off := Vector3(p.x - centre.x, p.y - centre.y, p.z - centre.z)
		assert_almost_eq(off.dot(Vector3(0.0, 1.0, 1.0).normalized()), 0.0, 4.0, "every buoy in the tilted plane")


func test_first_is_projected_into_the_plane() -> void:
	var leaning: Array[UniversePos] = BuoyRing.positions(centre, RADIUS_M, 8, Vector3.UP, Vector3(0.0, 0.5, -1.0))
	assert_almost_eq(leaning[0].y, centre.y, 1.0)
	assert_almost_eq(leaning[0].z, centre.z - RADIUS_M, 1.0)


func test_names_follow_the_phonetic_alphabet() -> void:
	var names: PackedStringArray = BuoyRing.names(COUNT)
	assert_eq(names.size(), COUNT)
	assert_eq(names[0], "NAV ALPHA")
	assert_eq(names[1], "NAV BRAVO")
	assert_eq(names[15], "NAV PAPA")
	assert_eq(BuoyRing.names(2, "RELAY ")[1], "RELAY BRAVO")


func test_bad_rings_are_refused_with_a_reason() -> void:
	assert_eq(BuoyRing.problem(RADIUS_M, COUNT, Vector3.UP, Vector3.FORWARD), "")
	assert_string_contains(BuoyRing.problem(0.0, COUNT, Vector3.UP, Vector3.FORWARD), "radius")
	assert_string_contains(BuoyRing.problem(RADIUS_M, 2, Vector3.UP, Vector3.FORWARD), "count")
	assert_string_contains(BuoyRing.problem(RADIUS_M, BuoyRing.PHONETIC.size() + 1, Vector3.UP, Vector3.FORWARD), "count")
	assert_string_contains(BuoyRing.problem(RADIUS_M, COUNT, Vector3.ZERO, Vector3.FORWARD), "normal")
	assert_string_contains(BuoyRing.problem(RADIUS_M, COUNT, Vector3.UP, Vector3.UP * 2.0), "first")


func test_on_the_ring_two_buoys_are_always_in_broadcast_range() -> void:
	for k: int in 721:
		var angle: float = TAU * k / 720.0
		var heard: int = BuoyRing.count_in_range(_on_ring(angle), ring, NavBuoy.BROADCAST_RANGE_M)
		assert_true(heard >= 2, "%.2f deg round the ring hears %d" % [rad_to_deg(angle), heard])
		if heard < 2:
			return


func test_near_the_ring_two_buoys_are_always_in_broadcast_range() -> void:
	# The ring repeats every buoy, and mirrors half way between two: one half gap covers it.
	var failures: int = 0
	for k: int in 25:
		var at: UniversePos = _on_ring(PI / COUNT * k / 24.0)
		for dir: Vector3 in _directions():
			for reach: float in [1.0e6, 2.5e6, RULE_REACH_M]:
				var p: UniversePos = at.plus_local(dir * reach)
				if BuoyRing.count_in_range(p, ring, NavBuoy.BROADCAST_RANGE_M) < 2:
					failures += 1
	assert_eq(failures, 0, "within %.0f km of the ring, in any direction" % (RULE_REACH_M / 1000.0))


func test_off_the_plane_and_inward_the_rule_reaches_six_thousand_km() -> void:
	for k: int in 25:
		var at: UniversePos = _on_ring(PI / COUNT * k / 24.0)
		var inward := Vector3(centre.x - at.x, centre.y - at.y, centre.z - at.z).normalized()
		for dir: Vector3 in [Vector3.UP, Vector3.DOWN, inward]:
			var p: UniversePos = at.plus_local(dir * 6.0e6)
			assert_true(BuoyRing.count_in_range(p, ring, NavBuoy.BROADCAST_RANGE_M) >= 2)


func test_the_rules_edge_is_outward_beside_a_buoy() -> void:
	# Straight out from a buoy both neighbours draw away: about 4 900 km is where the second one drops out.
	var outward := Vector3(ring[0].x - centre.x, ring[0].y - centre.y, ring[0].z - centre.z).normalized()
	assert_eq(BuoyRing.count_in_range(ring[0].plus_local(outward * 4.9e6), ring, NavBuoy.BROADCAST_RANGE_M), 3)
	assert_eq(BuoyRing.count_in_range(ring[0].plus_local(outward * 5.0e6), ring, NavBuoy.BROADCAST_RANGE_M), 1)


func test_count_in_range_counts_the_edge_as_in() -> void:
	var near: Array[UniversePos] = [UniversePos.new(0.0, 0.0, 0.0), UniversePos.new(10.0, 0.0, 0.0)]
	assert_eq(BuoyRing.count_in_range(UniversePos.new(), near, 10.0), 2)
	assert_eq(BuoyRing.count_in_range(UniversePos.new(), near, 9.99), 1)
