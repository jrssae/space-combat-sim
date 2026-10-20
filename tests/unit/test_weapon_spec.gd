extends GutTest
## WeaponSpec (M2-T02): the defaults are the Starfury's M1 numbers, the shipped pulse cannon resource agrees with
## them, and the capacitor it builds is sized from the spec.

const PULSE_CANNON_PATH: String = "res://assets/weapons/pulse_cannon_ef.tres"


func test_defaults_are_the_m1_numbers() -> void:
	var spec := WeaponSpec.new()
	assert_eq(spec.muzzle_speed_mps, 400.0)
	assert_eq(spec.shot_interval_s, PulseCannonGate.ALTERNATING_INTERVAL_S)
	assert_eq(spec.damage, 10.0)
	assert_eq(spec.lifetime_s, 4.0)
	assert_eq(spec.hit_radius_m, 0.25)
	assert_eq(spec.bolt_length_m, 1.5)
	assert_eq(spec.bolt_radius_m, 0.05)


func test_capacitor_defaults_match_the_capacitor_class() -> void:
	var spec := WeaponSpec.new()
	assert_eq(spec.capacitor_capacity, WeaponCapacitor.DEFAULT_CAPACITY)
	assert_eq(spec.capacitor_cost_per_shot, WeaponCapacitor.DEFAULT_COST_PER_SHOT)
	assert_eq(spec.capacitor_recharge_per_s, WeaponCapacitor.DEFAULT_RECHARGE_PER_S)


func test_make_capacitor_takes_the_spec_numbers() -> void:
	var spec := WeaponSpec.new()
	spec.capacitor_capacity = 50.0
	spec.capacitor_cost_per_shot = 5.0
	spec.capacitor_recharge_per_s = 2.0
	var cap: WeaponCapacitor = spec.make_capacitor()
	assert_eq(cap.capacity, 50.0)
	assert_eq(cap.cost_per_shot, 5.0)
	assert_eq(cap.recharge_per_s, 2.0)
	assert_eq(cap.charge_at(0.0), 50.0, "starts full")


func test_the_shipped_pulse_cannon_reproduces_the_defaults() -> void:
	var shipped := load(PULSE_CANNON_PATH) as WeaponSpec
	assert_not_null(shipped)
	var defaults := WeaponSpec.new()
	for property: Dictionary in defaults.get_property_list():
		var usage: int = property["usage"]
		var key: String = property["name"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and key != "bolt_material":
			assert_eq(shipped.get(key), defaults.get(key), "resource agrees with the code default for %s" % key)
	assert_not_null(shipped.bolt_material, "the Starfury's bolt keeps the pulse bolt material")
