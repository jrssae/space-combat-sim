extends GutTest
## RamMath (M3-T04, architecture §16 D32): severity from a ship's own velocity change, the momentum split for swept hits, the
## velocity change a contact caused, the tunnelling-speed rule and the core radius. The swept test itself is ConvexSweep's.

const EPS: float = 1e-6
const DT: float = 1.0 / 60.0
## The ruled starting values (tune in (H)): safe 5 m/s for every ship, lethal 18 m/s for the Starfury, 15 m/s for the raider.
const SAFE: float = 5.0
const STARFURY_LETHAL: float = 18.0
const RAIDER_LETHAL: float = 15.0
const STARFURY_HULL: float = 300.0
const STARFURY_KG: float = 48000.0
const BUOY_KG: float = 2000.0


# --- severity and damage -------------------------------------------------------------------------------------------


func test_a_change_up_to_the_safe_value_is_harmless() -> void:
	assert_eq(RamMath.severity(0.0, SAFE, STARFURY_LETHAL), 0.0)
	assert_eq(RamMath.severity(2.0, SAFE, STARFURY_LETHAL), 0.0, "a 4 m/s head-on between equals is 2 m/s each")
	assert_eq(RamMath.severity(SAFE, SAFE, STARFURY_LETHAL), 0.0)


func test_the_lethal_change_and_anything_above_take_the_whole_hull() -> void:
	assert_eq(RamMath.severity(STARFURY_LETHAL, SAFE, STARFURY_LETHAL), 1.0)
	assert_eq(RamMath.severity(300.0, SAFE, STARFURY_LETHAL), 1.0)
	assert_eq(RamMath.damage(300.0, SAFE, STARFURY_LETHAL, STARFURY_HULL), STARFURY_HULL)


func test_severity_is_quadratic_between_safe_and_lethal() -> void:
	assert_almost_eq(RamMath.severity(10.0, SAFE, RAIDER_LETHAL), 0.25, EPS, "half way is a quarter")
	assert_almost_eq(RamMath.severity(7.5, SAFE, RAIDER_LETHAL), 0.0625, EPS)
	var previous: float = 0.0
	for i: int in 41:
		var s: float = RamMath.severity(SAFE + 0.25 * float(i), SAFE, RAIDER_LETHAL)
		assert_true(s >= previous, "never decreases")
		previous = s


func test_a_thirty_mps_head_on_between_starfuries_wrecks_more_than_half_the_hull() -> void:
	# Equal masses, zero restitution: each ship's own velocity changes by half the closing speed.
	var dv: float = RamMath.split_dv(30.0, STARFURY_KG, STARFURY_KG)
	assert_almost_eq(dv, 15.0, EPS)
	var damage: float = RamMath.damage(dv, SAFE, STARFURY_LETHAL, STARFURY_HULL)
	assert_almost_eq(damage, STARFURY_HULL * pow(10.0 / 13.0, 2.0), 1e-4, "about 59 %")
	assert_gt(damage, 0.5 * STARFURY_HULL)


func test_lethal_at_or_below_safe_is_a_step() -> void:
	assert_eq(RamMath.severity(4.9, 5.0, 5.0), 0.0)
	assert_eq(RamMath.severity(5.1, 5.0, 5.0), 1.0)
	assert_eq(RamMath.severity(5.1, 5.0, 3.0), 1.0)


# --- velocity changes ----------------------------------------------------------------------------------------------


func test_the_momentum_split_gives_the_lighter_body_the_larger_change() -> void:
	assert_almost_eq(RamMath.split_dv(40.0, BUOY_KG, STARFURY_KG), 40.0 * 48.0 / 50.0, 1e-4, "the buoy: 38.4 m/s")
	assert_almost_eq(RamMath.split_dv(40.0, STARFURY_KG, BUOY_KG), 40.0 * 2.0 / 50.0, 1e-4, "the Starfury: 1.6 m/s")
	assert_eq(RamMath.split_dv(40.0, 0.0, 0.0), 0.0, "no mass, no change")
	assert_eq(RamMath.split_dv(40.0, STARFURY_KG, 0.0), 0.0, "a massless prop cannot push")


func test_a_buoy_rammed_at_forty_mps_is_destroyed_and_the_ship_is_not_hurt() -> void:
	var buoy_dv: float = RamMath.split_dv(40.0, BUOY_KG, STARFURY_KG)
	var ship_dv: float = RamMath.split_dv(40.0, STARFURY_KG, BUOY_KG)
	assert_eq(RamMath.severity(buoy_dv, SAFE, RAIDER_LETHAL), 1.0)
	assert_eq(RamMath.severity(ship_dv, SAFE, STARFURY_LETHAL), 0.0)


func test_contact_dv_is_what_the_ships_own_forces_do_not_explain() -> void:
	var v_before := Vector3(0.0, 0.0, -15.0)
	var thrust_dv := Vector3(0.0, 0.0, -30.0) * DT  # one tick of full mains: 1.44 MN on 48 t
	assert_almost_eq(RamMath.contact_dv(v_before + thrust_dv, v_before, thrust_dv), 0.0, EPS, "thrust alone is no ram")
	assert_almost_eq(RamMath.contact_dv(Vector3(0.0, 0.0, -0.077), v_before, Vector3.ZERO), 14.923, 1e-3)
	# Thrusting into the hit: the contact took the thrust's share away as well.
	assert_almost_eq(RamMath.contact_dv(Vector3.ZERO, v_before, thrust_dv), 15.5, 1e-4)
	assert_almost_eq(RamMath.contact_dv(Vector3(3.0, 4.0, 0.0), Vector3.ZERO, Vector3.ZERO), 5.0, EPS, "a vector change")
	# Over several ticks of contact, what the forces added is summed: three ticks of mains pressed against a wall.
	assert_almost_eq(RamMath.contact_dv(v_before, v_before, thrust_dv * 3.0), 1.5, 1e-4)


# --- tunnelling ----------------------------------------------------------------------------------------------------


func test_tunnelling_speed_is_one_tick_of_relative_motion_over_half_the_smaller_core() -> void:
	# Starfury core 1.235 m, raider core 0.78 m: half the smaller core per tick.
	assert_true(RamMath.is_tunnelling(600.0, DT, 1.235, 1.235), "600 m/s is 10 m per tick")
	assert_false(RamMath.is_tunnelling(30.0, DT, 1.235, 1.235), "0.5 m per tick against 0.62 m: Jolt resolves it")
	assert_false(RamMath.is_tunnelling(0.5 * 0.78 / DT - 0.01, DT, 1.235, 0.78))
	assert_true(RamMath.is_tunnelling(0.5 * 0.78 / DT + 0.01, DT, 1.235, 0.78), "the smaller core decides")
	assert_true(RamMath.is_tunnelling(1.0, DT, 0.0, 1.0), "a body with no core always needs the swept test")


# --- core radius ---------------------------------------------------------------------------------------------------


func test_core_radius_is_the_largest_sphere_inside_one_shape() -> void:
	var shapes: Array[HitShape] = [
		HitShape.make_box(Transform3D.IDENTITY, Vector3(3.07, 2.47, 5.2), "fuselage"),
		HitShape.make_capsule(Transform3D(Basis.IDENTITY, Vector3(5.5, 2.2, 0.6)), 0.82, 5.9, "pod"),
		HitShape.make_box(Transform3D.IDENTITY, Vector3(6.7, 0.68, 3.2), "strut"),
	] as Array[HitShape]
	assert_almost_eq(RamMath.core_radius(shapes), 1.235, EPS, "the fuselage's smallest half extent")
	assert_eq(RamMath.core_radius([] as Array[HitShape]), 0.0)
	var pods: Array[HitShape] = [HitShape.make_capsule(Transform3D.IDENTITY, 0.78, 5.2, "nacelle")] as Array[HitShape]
	assert_almost_eq(RamMath.core_radius(pods), 0.78, EPS, "a capsule's radius")
