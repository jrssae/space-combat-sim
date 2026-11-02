extends GutTest
## Silhouette: every damage zone of a layout is drawn (the X fighter as a wireframe, the delta as outlines), inside the unit
## square, the X fighter's arms where they are on the ship.


func test_the_delta_has_a_polygon_for_every_zone_inside_the_unit_square() -> void:
	var seen: Dictionary = {}
	for entry: Dictionary in Silhouette.polygons(DamageZones.Layout.DELTA):
		seen[int(entry["zone"])] = true
		var points: PackedVector2Array = entry["points"]
		assert_gte(points.size(), 3, "a polygon has at least three corners")
		for p: Vector2 in points:
			assert_between(p.x, -0.5, 0.5)
			assert_between(p.y, -0.5, 0.5)
	assert_eq(seen.size(), DamageZones.zone_count(DamageZones.Layout.DELTA))
	assert_eq(Silhouette.wireframe(DamageZones.Layout.DELTA).size(), 0, "the delta is not a wireframe")


func test_the_x_fighter_wireframe_covers_every_zone_inside_the_unit_square() -> void:
	for aspect: float in [150.0 / 112.0, 1.0, 0.5, 3.0]:
		var seen: Dictionary = {}
		for entry: Dictionary in Silhouette.wireframe(DamageZones.Layout.X_FIGHTER, aspect):
			seen[int(entry["zone"])] = true
			var segments: PackedVector2Array = entry["segments"]
			assert_gt(segments.size(), 20, "zone %d is a low-poly model, not a stroke" % int(entry["zone"]))
			assert_eq(segments.size() % 2, 0, "line pairs")
			for p: Vector2 in segments:
				assert_between(p.x, -0.5, 0.5)
				assert_between(p.y, -0.5, 0.5)
		assert_eq(seen.size(), DamageZones.zone_count(DamageZones.Layout.X_FIGHTER), "aspect %.2f" % aspect)
	assert_eq(Silhouette.polygons(DamageZones.Layout.X_FIGHTER).size(), 0, "the X fighter is not outlines")


func test_the_wireframe_fills_the_rect_without_distortion() -> void:
	var aspect: float = 150.0 / 112.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for entry: Dictionary in Silhouette.wireframe(DamageZones.Layout.X_FIGHTER, aspect):
		for p: Vector2 in entry["segments"]:
			lo = lo.min(p)
			hi = hi.max(p)
	# Scaled into a 150 x 112 rect, one axis spans the fill share and the drawing is centred.
	var size: Vector2 = (hi - lo) * Vector2(150.0, 112.0)
	assert_almost_eq(maxf(size.x / 150.0, size.y / 112.0), Silhouette.WIRE_FILL, 1e-4)
	assert_almost_eq(((lo + hi) * 0.5).length(), 0.0, 1e-4)
	# The same ship at another aspect keeps its on-screen proportions.
	var lo2 := Vector2(INF, INF)
	var hi2 := Vector2(-INF, -INF)
	for entry: Dictionary in Silhouette.wireframe(DamageZones.Layout.X_FIGHTER, 1.0):
		for p: Vector2 in entry["segments"]:
			lo2 = lo2.min(p)
			hi2 = hi2.max(p)
	var size2: Vector2 = (hi2 - lo2) * Vector2(100.0, 100.0)
	assert_almost_eq(size.x / size.y, size2.x / size2.y, 1e-3)


func test_no_layout_has_no_drawing() -> void:
	assert_eq(Silhouette.polygons(DamageZones.Layout.NONE).size(), 0)
	assert_eq(Silhouette.wireframe(DamageZones.Layout.NONE).size(), 0)


func test_left_arms_are_on_the_left_and_upper_arms_are_up() -> void:
	var cabin := Vector2.ZERO
	var arms: Dictionary = {}
	for entry: Dictionary in Silhouette.wireframe(DamageZones.Layout.X_FIGHTER, 150.0 / 112.0):
		var centre := Vector2.ZERO
		var segments: PackedVector2Array = entry["segments"]
		for p: Vector2 in segments:
			centre += p
		centre /= float(segments.size())
		if int(entry["zone"]) == DamageZones.CABIN:
			cabin = centre
		else:
			arms[int(entry["zone"])] = centre
	# Seen from behind and a little to the left, an arm sits left or right of the cabin, and above or below it.
	assert_lt(arms[DamageZones.UPPER_LEFT].x, cabin.x)
	assert_lt(arms[DamageZones.LOWER_LEFT].x, cabin.x)
	assert_gt(arms[DamageZones.UPPER_RIGHT].x, cabin.x)
	assert_gt(arms[DamageZones.LOWER_RIGHT].x, cabin.x)
	assert_lt(arms[DamageZones.UPPER_LEFT].y, arms[DamageZones.LOWER_LEFT].y, "y grows downward")
	assert_lt(arms[DamageZones.UPPER_RIGHT].y, arms[DamageZones.LOWER_RIGHT].y, "y grows downward")
