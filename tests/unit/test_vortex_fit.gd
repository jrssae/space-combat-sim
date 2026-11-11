extends GutTest
## The jump vortex's fit (M6-T19): at a gate, from its markers, the rim a few metres inside the arms' inner tips, the funnel as
## deep as an arm is long, the mouth in the gate's front plane; at a ship-made point, sized for the ship coming through.

const HARDPOINTS_PATH: String = "res://assets/generated/jumpgate/hardpoints.json"
const MANIFEST_PATH: String = "res://assets/generated/jumpgate/manifest.json"


# Markers shaped as the generator writes them: 1 200 m arms whose inner ends are 800 m out, lenses 790.5 m out.
func _hardpoints(arm_m: float = 1200.0, inner_m: float = 800.0, lens_m: float = 790.4878) -> Dictionary:
	var arms: Array = []
	var emitters: Array = []
	for axis: Vector2 in [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]:
		arms.append({"inner": [axis.x * inner_m, axis.y * inner_m, 0.0]})
		emitters.append({"position": [axis.x * lens_m, axis.y * lens_m, 0.0]})
	return {"arm_length_m": arm_m, "arms": arms, "emitters": emitters}


func test_the_rim_stops_a_few_metres_short_of_the_inner_tips() -> void:
	var fit: VortexFit = VortexFit.for_gate(_hardpoints(), {"aabb_min": [-2000.0, -2000.0, -49.75]})
	assert_lt(fit.mouth_radius_m, 790.4878, "inside the nearest tip (the lens)")
	assert_gt(fit.mouth_radius_m, 790.4878 - 20.0, "only a few metres short")
	assert_almost_eq(fit.mouth_radius_m, 790.4878 - VortexFit.RIM_CLEARANCE_M, 0.01)


func test_the_depth_is_the_arm_length_and_the_mouth_is_in_the_front_plane() -> void:
	var fit: VortexFit = VortexFit.for_gate(_hardpoints(), {"aabb_min": [-2000.0, -2000.0, -49.75]})
	assert_almost_eq(fit.depth_m, 1200.0, 0.01)
	assert_almost_eq(fit.mouth_z_m, -49.75, 0.01, "the gate faces -Z: its front plane is its lowest z")


func test_the_fit_follows_the_markers_not_constants() -> void:
	var fit: VortexFit = VortexFit.for_gate(_hardpoints(600.0, 400.0, 395.0), {"aabb_min": [-1000.0, -1000.0, -25.0]})
	assert_almost_eq(fit.mouth_radius_m, 395.0 - VortexFit.RIM_CLEARANCE_M, 0.01, "a half-size gate")
	assert_almost_eq(fit.depth_m, 600.0, 0.01)
	assert_almost_eq(fit.mouth_z_m, -25.0, 0.01)
	var no_lens: VortexFit = VortexFit.for_gate({"arm_length_m": 1200.0, "arms": _hardpoints()["arms"]}, {})
	assert_almost_eq(no_lens.mouth_radius_m, 800.0 - VortexFit.RIM_CLEARANCE_M, 0.01, "the arms' inner ends alone")
	assert_eq(no_lens.mouth_z_m, 0.0, "no manifest: the mid plane")


func test_the_built_gate_fits_its_own_markers() -> void:
	if not FileAccess.file_exists(HARDPOINTS_PATH) or not FileAccess.file_exists(MANIFEST_PATH):
		pending("the jumpgate asset is not built (scripts/gen_assets.sh)")
		return
	var hp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HARDPOINTS_PATH))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var fit: VortexFit = VortexFit.for_gate(hp, manifest)
	var tip: float = INF
	for e: Dictionary in hp["emitters"]:
		tip = minf(tip, Vector2(float(e["position"][0]), float(e["position"][1])).length())
	assert_between(fit.mouth_radius_m, tip - 20.0, tip - 1.0, "just under the arms' inner tips (about 800 m)")
	assert_almost_eq(fit.depth_m, float(hp["arm_length_m"]), 0.01, "as deep as an arm is long")
	assert_almost_eq(fit.mouth_z_m, float(manifest["aabb_min"][2]), 0.01, "in the front plane")


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
