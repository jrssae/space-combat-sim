extends GutTest
## The station's pure parts (M7-T06): the drum's angle from the clock, the damage sections (a hit lowers its section only, a
## loss is said once, Q5), the target box's station zones, and the hit volumes and hulls packed for the core.


func _hardpoints() -> StationHardpoints:
	return StationHardpoints.from_manifest({"hardpoints": {"spin_rad_s": 0.148, "cobra_bays": [], "grid_mounts": [],
		"lights": [], "tour_points": [], "main_docking_bay": {"name": "main_docking_bay", "body": "drum"}, "cargo_bay": {"name": "cargo_bay", "body": "frame"},
		"damage_sections": [
			{"name": "command", "body": "frame", "sections": ["bow"], "aabb_min": [-100, -100, -4000], "aabb_max": [100, 400, -2700]},
			{"name": "green_zone", "body": "drum", "sections": ["green_1"], "aabb_min": [-350, -350, -650], "aabb_max": [350, 350, 1780]},
			{"name": "reactor", "body": "frame", "sections": ["reactor"], "aabb_min": [-260, -260, 2360], "aabb_max": [260, 260, 4000]},
		]}})


func test_the_drum_angle_comes_from_the_clock_alone() -> void:
	var spin := StationSpin.new(0.148)
	assert_almost_eq(spin.angle_at(0.0), 0.0, 1e-12)
	assert_almost_eq(spin.angle_at(10.0), 1.48, 1e-12)
	assert_almost_eq(spin.angle_at(540148.0), fposmod(0.148 * 540148.0, TAU), 1e-9, "a scenario's epoch: the same angle every run")
	assert_eq(StationSpin.new(0.148).angle_at(123456.789), spin.angle_at(123456.789), "two drums at one time agree")
	assert_between(spin.angle_at(1.0e7), 0.0, TAU)
	assert_almost_eq(spin.surface_speed(417.0), 61.716, 1e-3, "about 62 m/s at the bands' skin (Q9)")


func test_a_hit_lowers_the_section_it_lands_in_and_no_other() -> void:
	var hp: StationHardpoints = _hardpoints()
	assert_true(hp.valid, hp.error)
	var s: StationSections = StationSections.from_hardpoints(hp, 1000.0)
	assert_eq(s.count(), 3)
	assert_eq(s.section_at("frame", Vector3(0.0, 300.0, -3000.0)), 0, "inside the command section's box")
	assert_eq(s.section_at("drum", Vector3(0.0, 300.0, 0.0)), 1, "the drum's box, in the drum's frame")
	assert_eq(s.section_at("frame", Vector3(0.0, 0.0, 0.0)), -1, "nowhere near a frame section")
	assert_eq(s.section_at("frame", Vector3(0.0, 420.0, -3000.0)), 0, "just off the box's top: snapped to it")
	assert_false(s.damage(0, 300.0))
	assert_eq(s.health, PackedFloat64Array([700.0, 1000.0, 1000.0]), "only the command section")
	assert_almost_eq(s.fraction(0), 0.7, 1e-9)
	var lost: Array[int] = []
	s.lost.connect(func(i: int) -> void: lost.append(i))
	assert_true(s.damage(0, 800.0), "this hit loses it")
	assert_false(s.damage(0, 10.0), "already lost")
	assert_eq(lost, [0] as Array[int], "said once")
	assert_eq(s.health[0], 0.0, "never below zero")
	assert_true(s.is_lost(0))
	assert_false(s.damage(7, 10.0), "a section out of range takes nothing")
	assert_string_contains(s.describe(), "command 0/1000 LOST")
	s.restore()
	assert_eq(s.health, PackedFloat64Array([1000.0, 1000.0, 1000.0]))


func test_the_station_zones_show_each_sections_own_damage() -> void:
	var zones := DamageZones.new(DamageZones.layout_from_name(&"station"))
	assert_eq(zones.layout, DamageZones.Layout.STATION)
	zones.set_capacities(PackedFloat64Array([100.0, 400.0]))
	zones.record_zone(1, 100.0)
	zones.record_zone(5, 100.0)  # out of range: nothing
	zones.record(Vector3(0.0, 0.0, -10.0), 50.0)  # no point rule for the station
	assert_eq(zones.severities(1.0e9), PackedFloat32Array([0.0, 0.25]))
	Silhouette.set_station_sections([{"zone": 0, "aabb": AABB(Vector3(-100, -100, -4000), Vector3(200, 500, 1300))},
			{"zone": 1, "aabb": AABB(Vector3(-350, -350, -1650), Vector3(700, 700, 2430))}] as Array[Dictionary])
	var drawn: Array[Dictionary] = Silhouette.polygons(DamageZones.Layout.STATION)
	assert_eq(drawn.size(), 2)
	for entry: Dictionary in drawn:
		for p: Vector2 in entry["points"]:
			assert_between(p.x, -0.5, 0.5, "inside the unit square")
			assert_between(p.y, -0.5, 0.5)
	assert_lt((drawn[0]["points"] as PackedVector2Array)[0].x, (drawn[1]["points"] as PackedVector2Array)[0].x, "bow on the left")


func test_volumes_and_hulls_pack_as_the_core_reads_them() -> void:
	var box := HitShape.make_box(Transform3D(Basis(Vector3.UP, 0.5), Vector3(1.0, 2.0, 3.0)), Vector3(4.0, 6.0, 8.0), "bow/a")
	var capsule := HitShape.make_capsule(Transform3D(Basis.IDENTITY, Vector3(0.0, 10.0, 0.0)), 2.0, 10.0, "bow/b")
	var packed: PackedFloat64Array = Station.pack_volumes([box, capsule] as Array[HitShape])
	assert_eq(packed.size(), 32, "16 numbers a volume")
	assert_eq(packed[0], 0.0, "a box")
	assert_almost_eq(Vector3(packed[1], packed[2], packed[3]), box.transform.basis.x, Vector3.ONE * 1e-6, "its x axis")
	assert_eq(Vector3(packed[10], packed[11], packed[12]), Vector3(1.0, 2.0, 3.0), "its centre")
	assert_eq(Vector3(packed[13], packed[14], packed[15]), Vector3(2.0, 3.0, 4.0), "half extents")
	assert_eq(packed[16], 1.0, "a capsule")
	assert_eq(Vector3(packed[29], packed[30], packed[31]), Vector3(3.0, 2.0, 0.0), "half segment, radius")
	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)])
	var shapes: Array[Dictionary] = [{"name": "bow/a", "type": "hull", "shape": hull, "transform": Transform3D.IDENTITY},
			{"name": "bow/x", "type": "hull", "shape": hull, "transform": Transform3D.IDENTITY}]
	var hulls: PackedFloat64Array = Station.pack_hulls(shapes, [box, capsule] as Array[HitShape])
	assert_eq(hulls.size(), 2 + 12, "the first shape's hull, by its volume's index; the second's name does not match")
	assert_eq(hulls[0], 0.0)
	assert_eq(hulls[1], 4.0)
