extends GutTest
## DamageZones: which main component a hit lands in, and how bad each one is.


func test_the_x_fighter_has_a_cabin_and_four_arms() -> void:
	var layout := DamageZones.Layout.X_FIGHTER
	assert_eq(DamageZones.zone_count(layout), 5)
	assert_eq(DamageZones.zone_for(layout, Vector3(0.0, 0.0, -3.0)), DamageZones.CABIN, "the fuselage")
	assert_eq(DamageZones.zone_for(layout, Vector3(1.9, 1.0, 0.0)), DamageZones.CABIN, "still inside the cabin width")
	assert_eq(DamageZones.zone_for(layout, Vector3(5.5, 2.2, 0.6)), DamageZones.UPPER_RIGHT, "the upper right pod")
	assert_eq(DamageZones.zone_for(layout, Vector3(-5.5, 2.2, 0.6)), DamageZones.UPPER_LEFT)
	assert_eq(DamageZones.zone_for(layout, Vector3(5.5, -2.2, 0.6)), DamageZones.LOWER_RIGHT)
	assert_eq(DamageZones.zone_for(layout, Vector3(-3.0, -1.0, 0.0)), DamageZones.LOWER_LEFT, "a lower strut")


func test_the_delta_has_a_centre_and_two_wings() -> void:
	var layout := DamageZones.Layout.DELTA
	assert_eq(DamageZones.zone_count(layout), 3)
	assert_eq(DamageZones.zone_for(layout, Vector3(0.5, 0.4, -1.0)), DamageZones.DELTA_CENTRE)
	assert_eq(DamageZones.zone_for(layout, Vector3(6.0, -0.2, 0.6)), DamageZones.DELTA_RIGHT)
	assert_eq(DamageZones.zone_for(layout, Vector3(-6.0, -0.2, 0.6)), DamageZones.DELTA_LEFT)


func test_no_layout_has_no_zones() -> void:
	assert_eq(DamageZones.zone_count(DamageZones.Layout.NONE), 0)
	assert_eq(DamageZones.zone_for(DamageZones.Layout.NONE, Vector3.ONE), -1)
	var zones := DamageZones.new()
	zones.record(Vector3.ONE, 10.0)  # nowhere to put it: no error
	assert_eq(zones.severities(300.0).size(), 0)


func test_layout_names() -> void:
	assert_eq(DamageZones.layout_from_name(&"x_fighter"), DamageZones.Layout.X_FIGHTER)
	assert_eq(DamageZones.layout_from_name(&"delta"), DamageZones.Layout.DELTA)
	assert_eq(DamageZones.layout_from_name(&"nonsense"), DamageZones.Layout.NONE)


func test_severity_rises_with_damage_and_caps_at_one() -> void:
	var zones := DamageZones.new(DamageZones.Layout.X_FIGHTER)
	assert_eq(zones.severities(300.0)[DamageZones.UPPER_LEFT], 0.0, "untouched")
	zones.record(Vector3(-5.0, 2.0, 0.0), 60.0)  # a wrecking dose is 0.4 * 300 = 120
	assert_almost_eq(zones.severities(300.0)[DamageZones.UPPER_LEFT], 0.5, 1e-6)
	assert_eq(zones.severities(300.0)[DamageZones.CABIN], 0.0, "only the zone that was hit")
	zones.record(Vector3(-5.0, 2.0, 0.0), 500.0)
	assert_eq(zones.severities(300.0)[DamageZones.UPPER_LEFT], 1.0)


func test_non_positive_amounts_are_ignored_and_reset_clears() -> void:
	var zones := DamageZones.new(DamageZones.Layout.DELTA)
	zones.record(Vector3.ZERO, 0.0)
	zones.record(Vector3.ZERO, -5.0)
	assert_eq(zones.severities(100.0)[DamageZones.DELTA_CENTRE], 0.0)
	zones.record(Vector3.ZERO, 10.0)
	assert_gt(zones.severities(100.0)[DamageZones.DELTA_CENTRE], 0.0)
	zones.reset()
	assert_eq(zones.severities(100.0)[DamageZones.DELTA_CENTRE], 0.0)
