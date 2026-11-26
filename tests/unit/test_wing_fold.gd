extends GutTest
## Atmospheric shuttles fold their wings for a bay (M10-T17, Q73, Q93): the Kestrel's turn up 90 degrees about their root joints,
## the Centauri shuttle's likewise; the body stays put (`WingFold`).

const KESTREL: String = "ea_atmo_shuttle"


func _kestrel_chunks() -> Array:
	return Hardpoints.load_file(ShipSpec.ASSET_ROOT.path_join(KESTREL).path_join("hardpoints.json")).raw.get("chunks", []) as Array


func test_the_folds_are_data() -> void:
	assert_almost_eq(float(WingFold.of_asset(KESTREL)["fold_deg"]), 90.0, 1e-6, "the Kestrel's wings stand up (T22's bay pose)")
	assert_false(WingFold.of_asset("centauri_shuttle").is_empty(), "the Centauri shuttle folds too (Q93)")
	assert_true(WingFold.of_asset("starfury_aurora").is_empty(), "a fighter does not")


func test_the_kestrels_wings_are_their_own_chunks() -> void:
	var chunks: Array = _kestrel_chunks()
	if chunks.is_empty():
		pending("the Kestrel is not generated (scripts/gen_assets.sh)")
		return
	assert_true(WingFold.has_wings(chunks))
	assert_false(WingFold.has_wings([{"name": "body", "joint": [0, 0, 0]}]))


func test_a_wing_turns_up_about_its_joint_and_the_body_stays() -> void:
	var joint := [10.0, -1.0, -2.0]
	var wing_r: Dictionary = {"name": "wing_r", "offset": [18.0, 0.8, 3.0], "joint": joint}
	var wing_l: Dictionary = {"name": "wing_l", "offset": [-18.0, 0.8, 3.0], "joint": [-10.0, -1.0, -2.0]}
	var body: Dictionary = {"name": "body", "offset": [0.0, -0.8, -7.0], "joint": [0.0, -1.0, -4.0]}
	var tip := Vector3(8.0, 0.0, 0.0)  # a point 8 m out from the chunk's centre: 26 m out on the starboard side
	assert_true((WingFold.chunk_transform(wing_r, 0.0, 90.0) * tip).is_equal_approx(Vector3(26.0, 0.8, 3.0)), "spread: as built")
	var up: Vector3 = WingFold.chunk_transform(wing_r, 1.0, 90.0) * tip
	assert_almost_eq(up.x, 10.0 - 1.8, 1e-3, "folded: over its joint")
	assert_almost_eq(up.y, -1.0 + 16.0, 1e-3, "its tip high above it")
	assert_almost_eq(up.z, 3.0, 1e-4, "about the hull's length")
	var port: Vector3 = WingFold.chunk_transform(wing_l, 1.0, 90.0) * Vector3(-8.0, 0.0, 0.0)
	assert_almost_eq(port.y, up.y, 1e-3, "the port wing goes up too, its mirror")
	assert_almost_eq(port.x, -up.x, 1e-3)
	assert_true(WingFold.chunk_transform(body, 1.0, 90.0).is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.8, -7.0))),
			"the body does not move")
	var joint_at: Vector3 = WingFold.chunk_transform(wing_r, 0.6, 90.0) * (Vector3(10.0, -1.0, -2.0) - Vector3(18.0, 0.8, 3.0))
	assert_true(joint_at.is_equal_approx(Vector3(10.0, -1.0, -2.0)), "the joint stays where it is all the way")


func test_the_fold_eases_over_its_time() -> void:
	var a: float = 0.0
	for k: int in 20:
		a = WingFold.advance(a, 1.0, 0.1, 4.0)
	assert_almost_eq(a, 0.5, 1e-6, "half its 4 s")
	assert_almost_eq(WingFold.eased(0.5), 0.5, 1e-6)
	assert_lt(WingFold.eased(0.1), 0.1, "slow at the start")
	assert_eq(WingFold.advance(1.0, 1.0, 0.1, 4.0), 1.0)
