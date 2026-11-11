extends GutTest
## The jump vortex's fit (M6-T19): at a gate, from its markers (the four arms run parallel to the vortex's axis round it): the rim
## a few metres short of the arms, the funnel as deep as an arm is long, the mouth at the arms' front ends; at a ship-made point,
## sized for the ship coming through.

const HARDPOINTS_PATH: String = "res://assets/generated/jumpgate/hardpoints.json"


func test_a_gate_takes_its_rim_depth_and_mouth_from_the_vortex_marker() -> void:
	var fit: VortexFit = VortexFit.for_gate({"arm_length_m": 1200.0,
			"vortex": {"center": [0.0, 0.0, 0.0], "radius_m": 751.0, "depth_m": 1200.0}})
	assert_almost_eq(fit.mouth_radius_m, 751.0, 0.01)
	assert_almost_eq(fit.depth_m, 1200.0, 0.01)
	assert_eq(fit.mouth_z_m, 0.0)


func test_the_fit_follows_the_markers_not_constants() -> void:
	var half: VortexFit = VortexFit.for_gate({"vortex": {"center": [0.0, 0.0, -5.0], "radius_m": 375.0, "depth_m": 600.0}})
	assert_almost_eq(half.mouth_radius_m, 375.0, 0.01, "a half-size gate")
	assert_almost_eq(half.depth_m, 600.0, 0.01)
	assert_almost_eq(half.mouth_z_m, -5.0, 0.01)
	var old: VortexFit = VortexFit.for_gate({"arm_length_m": 900.0, "vortex": {"radius_m": 500.0}})
	assert_almost_eq(old.depth_m, 900.0, 0.01, "no depth marker: the arm's length")
	var none: VortexFit = VortexFit.for_gate({})
	assert_almost_eq(none.mouth_radius_m, VortexFit.FALLBACK_RIM_M, 0.01, "no markers: the generator's values")


func test_the_built_gate_fits_inside_its_arms() -> void:
	if not FileAccess.file_exists(HARDPOINTS_PATH):
		pending("the jumpgate asset is not built (scripts/gen_assets.sh)")
		return
	var hp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HARDPOINTS_PATH))
	var fit: VortexFit = VortexFit.for_gate(hp)
	var arm_radius: float = INF
	var front_z: float = INF
	for arm: Dictionary in hp["arms"]:
		arm_radius = minf(arm_radius, Vector2(float(arm["front"][0]), float(arm["front"][1])).length())
		front_z = minf(front_z, float(arm["front"][2]))
	# The arms' trusses and fins reach about 50 m in toward the axis; the rim stops a few metres short of them.
	assert_between(fit.mouth_radius_m, arm_radius - 70.0, arm_radius - 1.0, "just under the arms' distance from the axis")
	var nearest: float = INF
	for box: Dictionary in hp["collision"]:
		nearest = minf(nearest, Vector2(float(box["position"][0]), float(box["position"][1])).length())
	assert_lt(fit.mouth_radius_m, nearest, "inside every collision box's centre")
	assert_almost_eq(fit.depth_m, float(hp["arm_length_m"]), 0.01, "as deep as an arm is long")
	assert_almost_eq(fit.mouth_z_m, front_z, 0.01, "at the arms' front ends")


func test_a_ship_made_point_is_sized_for_its_ship() -> void:
	var fighter: VortexFit = VortexFit.for_ship(12.0)
	assert_eq(fighter.mouth_radius_m, VortexFit.MIN_POINT_RADIUS_M, "a fighter gets the smallest point")
	var capital: VortexFit = VortexFit.for_ship(400.0)
	assert_almost_eq(capital.mouth_radius_m, 1600.0, 0.01, "four bounding radii: room to spare")
	assert_almost_eq(capital.depth_m, 1600.0 * VortexFit.POINT_DEPTH_RATIO, 0.01, "the gate's proportions")
	assert_eq(capital.mouth_z_m, 0.0)


func test_a_group_widens_its_point() -> void:
	var fit: VortexFit = VortexFit.for_ship(12.0)
	fit.widen_for(0.0, 12.0)
	assert_eq(fit.mouth_radius_m, VortexFit.MIN_POINT_RADIUS_M, "a wingman on the axis fits already")
	fit.widen_for(300.0, 12.0)
	assert_almost_eq(fit.mouth_radius_m, 300.0 + VortexFit.MIN_POINT_RADIUS_M, 0.01, "one 300 m out: its whole point inside")
	assert_almost_eq(fit.depth_m, fit.mouth_radius_m * VortexFit.POINT_DEPTH_RATIO, 0.01)
	fit.widen_for(50.0, 12.0)
	assert_almost_eq(fit.mouth_radius_m, 360.0, 0.01, "never narrows")
