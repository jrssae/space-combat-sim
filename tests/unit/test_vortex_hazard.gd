extends GutTest
## Jump points kill (M8-T17, maintainer 2026-11-19): the space a vortex forms in is its funnel, from the mouth's plane to its base,
## as wide as the funnel at each depth, a hull counting from its edge.

var fit: VortexFit


func before_each() -> void:
	fit = VortexFit.new()
	fit.mouth_radius_m = 750.0
	fit.mouth_half_width_m = 1000.0
	fit.depth_m = 1200.0


func test_the_funnel_is_the_space_from_the_mouth_to_the_base() -> void:
	assert_true(VortexHazard.inside(fit, Vector3(0.0, 0.0, 600.0)), "on the axis halfway down")
	assert_true(VortexHazard.inside(fit, Vector3(0.0, 0.0, 5.0)), "just past the mouth's plane")
	assert_false(VortexHazard.inside(fit, Vector3(0.0, 0.0, -50.0)), "in front of the mouth")
	assert_false(VortexHazard.inside(fit, Vector3(0.0, 0.0, 1300.0)), "behind the base")
	assert_true(VortexHazard.inside(fit, Vector3(900.0, 0.0, 1.0)), "at the mouth the funnel is the mouth's width")
	assert_false(VortexHazard.inside(fit, Vector3(1100.0, 0.0, 1.0)), "outside the rim")
	assert_false(VortexHazard.inside(fit, Vector3(700.0, 0.0, 1100.0)), "the funnel narrows to its base")
	assert_true(VortexHazard.inside(fit, Vector3(0.0, 0.0, -50.0), 60.0), "a hull reaching back across the plane is in it")
	var none := VortexFit.new()
	none.depth_m = 0.0
	assert_false(VortexHazard.inside(none, Vector3.ZERO), "no funnel, nothing inside")
