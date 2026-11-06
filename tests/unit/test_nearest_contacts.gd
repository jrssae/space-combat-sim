extends GutTest
## `ContactScan.nearest_for` (M4-T04): the nearest k of the contacts `contacts_for` gives, in scan order; when that leaves
## any out, the nearest hostile ship and whatever the keeper names join them. Scans are filled by hand (no scene), so seeded crowds of any size are cheap.

const OWN_BODY: int = 1000


# A scan of `positions`: body i has body id 1000 + i, contact id 5000 + i and name "SHIP i"; body 0 is the perceiving ship.
static func _scan(positions: PackedVector3Array) -> ContactScan:
	var scan := ContactScan.new()
	for i: int in positions.size():
		scan._body_ids.append(OWN_BODY + i)
		scan._ids.append(5000 + i)
		scan._names.append("SHIP %d" % i)
		scan._factions.append(Factions.RAIDERS if i % 2 == 0 else Factions.EARTH_ALLIANCE)  # body 0 is a raider
		scan._positions.append(positions[i])
		scan._velocities.append(Vector3.ZERO)
		scan._forwards.append(Vector3.FORWARD)
		scan._ups.append(Vector3.UP)
		scan._radii.append(10.0)
		scan._is_ship.append(1)
		scan._hulls.append(1.0)
		scan._target_ids.append(-1)
	return scan


static func _ids(list: Array[Contact]) -> Array[int]:
	var out: Array[int] = []
	for c: Contact in list:
		out.append(c.id)
	return out


func test_with_k_or_fewer_in_range_it_is_the_contacts_for_list() -> void:
	var scan := _scan(PackedVector3Array([Vector3.ZERO, Vector3(300, 0, 0), Vector3(0, 0, -6000), Vector3(-100, 0, 0),
			Vector3(0, 900, 0)]))
	var all: Array[Contact] = scan.contacts_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS)
	var nearest: Array[Contact] = scan.nearest_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS, 3)
	assert_eq(_ids(nearest), _ids(all), "three in range, k = 3: the same list in the same order")
	for i: int in all.size():
		assert_same(nearest[i], all[i], "the same shared contact objects")


func test_it_keeps_the_nearest_k_in_scan_order() -> void:
	var scan := _scan(PackedVector3Array([Vector3.ZERO, Vector3(800, 0, 0), Vector3(100, 0, 0), Vector3(400, 0, 0),
			Vector3(0, 200, 0), Vector3(0, 0, 4900)]))
	assert_eq(_ids(scan.nearest_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS, 2)), [5002, 5003, 5004],
			"100 m and 200 m, in scan order, and the nearest hostile ship (400 m) as two were left out")
	assert_eq(_ids(scan.nearest_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS, 3)), [5002, 5003, 5004])


func test_equal_ranges_go_to_the_earlier_body() -> void:
	var scan := _scan(PackedVector3Array([Vector3.ZERO, Vector3(500, 0, 0), Vector3(0, 500, 0), Vector3(0, 0, 500),
			Vector3(-500, 0, 0)]))
	assert_eq(_ids(scan.nearest_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS, 2)), [5001, 5002])


func test_kept_ids_and_names_join_the_set_but_only_within_range() -> void:
	var scan := _scan(PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0), Vector3(200, 0, 0), Vector3(4000, 0, 0),
			Vector3(0, 4500, 0), Vector3(0, 0, 7000), Vector3(0, 0, 300)]))
	var keeper := func() -> Array:
		return [PackedInt64Array([5003, 5005, 5001, 0, -1, 999]), PackedStringArray(["ship 4"])]
	var kept: Array[Contact] = scan.nearest_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS, 2, keeper)
	assert_eq(_ids(kept), [5001, 5002, 5003, 5004],
			"the far target and the named ship within 5 km, not the one at 7 km (5001 is the nearest hostile ship)")


func test_the_keeper_is_asked_only_when_the_cut_leaves_something_out() -> void:
	var scan := _scan(PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0), Vector3(200, 0, 0), Vector3(0, 0, 7000)]))
	var asked: Array[int] = [0]
	var keeper := func() -> Array:
		asked[0] += 1
		return [PackedInt64Array(), PackedStringArray()]
	scan.nearest_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS, 2, keeper)
	assert_eq(asked[0], 0, "two in range, k 2: nothing left out")
	scan.nearest_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS, 1, keeper)
	assert_eq(asked[0], 1, "k 1 leaves one out")


func test_a_crowd_of_friends_never_hides_the_nearest_hostile_ship() -> void:
	# Even bodies are raiders (the perceiving ship's friends), odd ones Earth Alliance (hostile to raiders).
	var scan := _scan(PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 3000), Vector3(100, 0, 0), Vector3(0, 0, 2500),
			Vector3(200, 0, 0), Vector3(-100, 0, 0)]))
	assert_eq(_ids(scan.nearest_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS, 2)), [5002, 5005],
			"the two nearest (a friend and a hostile at 100 m) and no more: the nearest hostile is among them")
	scan = _scan(PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 3000), Vector3(100, 0, 0), Vector3(0, 0, 2500),
			Vector3(200, 0, 0), Vector3(0, 0, 4000), Vector3(-100, 0, 0)]))
	assert_eq(_ids(scan.nearest_for(OWN_BODY, Vector3.ZERO, Factions.RAIDERS, 2)), [5002, 5003, 5006],
			"two friends nearest; the hostile at 2.5 km joins them")


func test_seeded_crowds_match_a_full_sort() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for crowd: int in 30:
		var positions := PackedVector3Array()
		var n: int = rng.randi_range(2, 150)
		for i: int in n:
			# Coarse positions so equal ranges happen and the tie rule is exercised.
			positions.append(Vector3(rng.randi_range(-12, 12), rng.randi_range(-12, 12), rng.randi_range(-12, 12)) * 400.0)
		var scan := _scan(positions)
		var own_at: Vector3 = positions[0]
		var k: int = rng.randi_range(1, 20)
		# The reference: every contact in range, sorted by range then scan index, the first k, back in scan order.
		var ranked: Array = []
		for i: int in range(1, n):
			var d_sq: float = positions[i].distance_squared_to(own_at)
			if d_sq <= ContactScan.SENSOR_RANGE_M * ContactScan.SENSOR_RANGE_M:
				ranked.append([d_sq, i])
		ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		var chosen: Array[int] = []
		for entry: Array in ranked.slice(0, k):
			chosen.append(5000 + int(entry[1]))
		# Left something out: the nearest hostile (odd index), first by range then index, joins them.
		if ranked.size() > k:
			for entry: Array in ranked:
				if int(entry[1]) % 2 == 1:
					if not chosen.has(5000 + int(entry[1])):
						chosen.append(5000 + int(entry[1]))
					break
		chosen.sort()
		assert_eq(_ids(scan.nearest_for(OWN_BODY, own_at, Factions.RAIDERS, k)), chosen, "crowd %d: %d bodies, k %d" % [crowd, n, k])
