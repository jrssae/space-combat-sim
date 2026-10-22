extends GutTest
## Silhouette: every damage zone of a layout has an outline, inside the unit square.


func test_every_zone_has_a_polygon_inside_the_unit_square() -> void:
	for layout: DamageZones.Layout in [DamageZones.Layout.X_FIGHTER, DamageZones.Layout.DELTA]:
		var seen: Dictionary = {}
		for entry: Dictionary in Silhouette.polygons(layout):
			seen[int(entry["zone"])] = true
			var points: PackedVector2Array = entry["points"]
			assert_gte(points.size(), 3, "a polygon has at least three corners")
			for p: Vector2 in points:
				assert_between(p.x, -0.5, 0.5)
				assert_between(p.y, -0.5, 0.5)
		assert_eq(seen.size(), DamageZones.zone_count(layout), "layout %d covers every zone" % layout)


func test_no_layout_has_no_outline() -> void:
	assert_eq(Silhouette.polygons(DamageZones.Layout.NONE).size(), 0)


func test_left_arms_are_on_the_left_and_upper_arms_are_up() -> void:
	for entry: Dictionary in Silhouette.polygons(DamageZones.Layout.X_FIGHTER):
		var zone: int = entry["zone"]
		var centre := Vector2.ZERO
		for p: Vector2 in entry["points"]:
			centre += p
		centre /= float((entry["points"] as PackedVector2Array).size())
		if zone == DamageZones.UPPER_LEFT or zone == DamageZones.LOWER_LEFT:
			assert_lt(centre.x, 0.0, "zone %d" % zone)
		if zone == DamageZones.UPPER_RIGHT or zone == DamageZones.LOWER_RIGHT:
			assert_gt(centre.x, 0.0, "zone %d" % zone)
		if zone == DamageZones.UPPER_LEFT or zone == DamageZones.UPPER_RIGHT:
			assert_lt(centre.y, 0.0, "zone %d (y grows downward)" % zone)
		if zone == DamageZones.LOWER_LEFT or zone == DamageZones.LOWER_RIGHT:
			assert_gt(centre.y, 0.0, "zone %d" % zone)
