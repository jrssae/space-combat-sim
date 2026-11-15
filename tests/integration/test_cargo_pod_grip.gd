extends GutTest
## The cargo pod's hands where the cargo plan puts them (M7-T34): the drawn rig's grip points with the arms out lie where
## `CargoFerryPlan` expects them (ahead of the craft's centre and below it), and a `CargoPodCraft` holding a block has both hands
## on the block's end face, its jaws shut, all along the block's way, a tank's roll included.

const BAY: Dictionary = {
	"cargo_bay_hold": Vector3(0.0, 339.0, -4700.0), "cargo_bay_entry": Vector3(0.0, 339.0, -3534.0),
	"cargo_bay_clear_min": Vector3(-32.1, 327.5, -3580.0), "cargo_bay_clear_max": Vector3(32.1, 354.2, -3512.0),
}


func test_the_rigs_grip_points_with_the_arms_out_are_the_plans() -> void:
	var rig := CargoPodRig.new()
	add_child_autofree(rig)
	if not rig.build():
		fail_test("no cargo_pod_craft asset (run scripts/gen_assets.sh, then import)")
		return
	rig.set_pose(1.0, 0.0, 0.0)
	var middle: Vector3 = (rig.grip_point("r") + rig.grip_point("l")) * 0.5
	assert_almost_eq(middle, Vector3(0.0, -CargoFerryPlan.GRIP_BELOW_M, -CargoFerryPlan.GRIP_AHEAD_M), Vector3.ONE * 0.01,
			"the hands' middle with the arms out")
	rig.set_pose(1.0, 0.0, 1.0)
	assert_almost_eq((rig.grip_point("r") + rig.grip_point("l")) * 0.5, middle, Vector3.ONE * 1e-4, "the jaws do not move the grip")


func test_a_pod_holding_a_tank_keeps_its_hands_on_the_face_as_the_tank_rolls() -> void:
	var plan: CargoFerryPlan = CargoFerryPlan.for_freighter(BAY, FreighterCargo.chunk_boxes_of("saturn_4_tanker"),
			Hardpoints.load_collision_only(ShipSpec.ASSET_ROOT.path_join("saturn_4_tanker").path_join("hardpoints.json")))
	assert_true(plan.valid, plan.error)
	if not plan.valid:
		return
	var job: CargoFerryJob = CargoFerryJob.create(plan, false)
	var parent := Node3D.new()
	add_child_autofree(parent)
	var crafts: Array[CargoPodCraft] = []
	for m: CargoPodMotion in job.crew:
		var craft := CargoPodCraft.new()
		craft.setup("Pod", m)
		parent.add_child(craft)
		crafts.append(craft)
	var pod: FerryPod = job.current()
	var worst: float = 0.0
	var rolled: float = 0.0
	var held: int = 0
	var t: float = 0.0
	while t < 3600.0 and not pod.done():
		for craft: CargoPodCraft in crafts:
			craft.advance(0.05, false)
		t += 0.05
		if pod.state != FerryPod.State.MOVING:
			continue
		rolled = maxf(rolled, pod.trip.roll_angle(pod.pose().origin.z))
		for k: int in pod.trip.bot_count():
			var face: Vector3 = pod.pose().origin + pod.trip.offsets[k].normalized() * (pod.trip.size.z * 0.5 + CargoFerryPlan.GRIP_GAP_M)
			var hands: Vector3 = (crafts[k].grip_point("r") + crafts[k].grip_point("l")) * 0.5
			worst = maxf(worst, hands.distance_to(face))
			held += 1
	assert_true(pod.done(), "the tank went into the bay")
	assert_gt(held, 100)
	assert_almost_eq(rolled, PI * 0.5, 0.01, "it turned onto its side on the way")
	assert_lt(worst, 0.02, "both pods' hands stay on its faces (%.3f m at worst)" % worst)
