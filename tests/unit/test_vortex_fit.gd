extends GutTest
## The jump vortex's fit (M6-T19): at a gate, from its markers (the four arms run parallel to the vortex's axis, the side arms
## further out): an elliptical rim within a metre of the arms, the funnel as deep as an arm is long, the mouth at the arms' front
## ends; at a ship-made point, round and sized for the ship coming through. The bright body fills less of a gate's mouth than of
## a point's (round 4).

const HARDPOINTS_PATH: String = "res://assets/generated/jumpgate/hardpoints.json"


func test_a_gate_takes_its_rim_depth_and_mouth_from_the_vortex_marker() -> void:
	var fit: VortexFit = VortexFit.for_gate({"arm_length_m": 1200.0,
			"vortex": {"center": [0.0, 0.0, 0.0], "radius_m": 755.0, "semi_axes_m": [1038.0, 755.0], "depth_m": 1200.0}})
	assert_almost_eq(fit.mouth_radius_m, 755.0, 0.01, "the half height")
	assert_almost_eq(fit.mouth_half_width_m, 1038.0, 0.01, "wider than tall")
	assert_eq(fit.semi_axes(), Vector2(1038.0, 755.0))
	assert_almost_eq(fit.aspect(), 1038.0 / 755.0, 1e-4)
	assert_almost_eq(fit.depth_m, 1200.0, 0.01)
	assert_eq(fit.mouth_z_m, 0.0)
	assert_eq(fit.body_share, VortexFit.GATE_BODY_SHARE, "the body ends inside the arms, as the still shows")


func test_the_fit_follows_the_markers_not_constants() -> void:
	var half: VortexFit = VortexFit.for_gate({"vortex": {"center": [0.0, 0.0, -5.0], "radius_m": 375.0, "depth_m": 600.0}})
	assert_almost_eq(half.mouth_radius_m, 375.0, 0.01, "a half-size gate")
	assert_almost_eq(half.mouth_half_width_m, 375.0, 0.01, "no semi-axes: a round mouth of that radius")
	assert_almost_eq(half.depth_m, 600.0, 0.01)
	assert_almost_eq(half.mouth_z_m, -5.0, 0.01)
	var old: VortexFit = VortexFit.for_gate({"arm_length_m": 900.0, "vortex": {"radius_m": 500.0}})
	assert_almost_eq(old.depth_m, 900.0, 0.01, "no depth marker: the arm's length")
	var none: VortexFit = VortexFit.for_gate({})
	assert_almost_eq(none.mouth_radius_m, VortexFit.FALLBACK_RIM_M, 0.01, "no markers: the generator's values")
	assert_almost_eq(none.mouth_half_width_m, VortexFit.FALLBACK_HALF_WIDTH_M, 0.01)


func test_the_mouth_holds_points_inside_its_ellipse() -> void:
	var fit := VortexFit.new(700.0, 1200.0, 0.0, 1000.0)
	assert_true(fit.contains(Vector2(990.0, 0.0)), "out along the wide axis")
	assert_false(fit.contains(Vector2(0.0, 990.0)), "the same distance up is outside")
	assert_true(fit.contains(Vector2(0.0, 690.0)))
	assert_false(fit.contains(Vector2(720.0, 500.0)), "outside the curve between the axes")
	assert_true(fit.contains(Vector2(0.0, 760.0), 1.1), "a margin grows the rim")
	var round := VortexFit.new(300.0, 480.0)
	assert_eq(round.semi_axes(), Vector2(300.0, 300.0), "a round mouth unless told otherwise")


func test_the_built_gate_fits_inside_its_arms() -> void:
	if not FileAccess.file_exists(HARDPOINTS_PATH):
		pending("the jumpgate asset is not built (scripts/gen_assets.sh)")
		return
	var hp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HARDPOINTS_PATH))
	var fit: VortexFit = VortexFit.for_gate(hp)
	var top: float = 0.0
	var side: float = 0.0
	var front_z: float = INF
	for arm: Dictionary in hp["arms"]:
		top = maxf(top, absf(float(arm["front"][1])))
		side = maxf(side, absf(float(arm["front"][0])))
		front_z = minf(front_z, float(arm["front"][2]))
	assert_gt(side, top, "the side arms stand further out: the mouth is wider than tall")
	# The arms' trusses and lamps reach about 45 m in toward the axis; the rim comes within a metre of them.
	assert_between(fit.mouth_radius_m, top - 50.0, top - 30.0, "just under the top and bottom arms")
	assert_between(fit.mouth_half_width_m, side - 50.0, side - 30.0, "just under the side arms")
	assert_almost_eq(fit.aspect(), side / top, 0.05, "the ellipse follows the arms")
	for box: Dictionary in hp["collision"]:
		assert_false(fit.contains(Vector2(float(box["position"][0]), float(box["position"][1]))),
				"%s is outside the rim" % box["name"])
	assert_almost_eq(fit.depth_m, float(hp["arm_length_m"]), 0.01, "as deep as an arm is long")
	assert_almost_eq(fit.mouth_z_m, front_z, 0.01, "at the arms' front ends")


func test_a_ship_made_point_is_sized_for_its_ship() -> void:
	var fighter: VortexFit = VortexFit.for_ship(12.0)
	assert_eq(fighter.mouth_radius_m, VortexFit.MIN_POINT_RADIUS_M, "a fighter gets the smallest point")
	var capital: VortexFit = VortexFit.for_ship(400.0)
	assert_almost_eq(capital.mouth_radius_m, 1600.0, 0.01, "four bounding radii: room to spare")
	assert_almost_eq(capital.depth_m, 1600.0 * VortexFit.POINT_DEPTH_RATIO, 0.01, "the gate's proportions")
	assert_eq(capital.aspect(), 1.0, "no arms shape it: round")
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
	assert_almost_eq(fit.mouth_half_width_m, 360.0, 0.01, "and stays round")


func test_the_body_fills_less_of_a_gates_mouth_than_of_a_points() -> void:
	# The still's visible edge lies on the arms' back ends, two thirds of the way out from the acceptance pose; a ship-made point
	# has no arms, so its body fills nearly the whole mouth and a widened group's ships come out of it, not the veil.
	assert_between(VortexFit.GATE_BODY_SHARE, 0.6, 0.72)
	assert_gt(VortexFit.POINT_BODY_SHARE, VortexFit.GATE_BODY_SHARE)
	assert_lt(VortexFit.POINT_BODY_SHARE, 1.0, "a veil still carries on to the rim")
	assert_eq(VortexFit.for_gate({}).body_share, VortexFit.GATE_BODY_SHARE, "a gate without markers too")
	var point: VortexFit = VortexFit.for_ship(12.0)
	assert_eq(point.body_share, VortexFit.POINT_BODY_SHARE)
	point.widen_for(300.0, 12.0)
	assert_eq(point.body_share, VortexFit.POINT_BODY_SHARE, "widening keeps it")
	assert_lt(300.0, point.mouth_radius_m * point.body_share, "a wingman 300 m out comes out of the body")
