extends GutTest
## Maintenance bots carrying cargo (M7-T30): `CargoFerryJob`, `FerryPod` and `BotFerryMotion`'s carrying, stepped by hand. A pod
## only moves while its bots hold it, and they hold it at fixed places; the job goes pod by pod; loading is the trip reversed;
## fighting near makes the bots let go away from the bay and come back for the pod after the quiet, and nearer the bay carry it on
## inside (or back inside when loading).

const DT: float = 0.05
const BAY: Dictionary = {
	"cargo_bay_hold": Vector3(0.0, 339.0, -4700.0), "cargo_bay_entry": Vector3(0.0, 339.0, -3534.0),
	"cargo_bay_clear_min": Vector3(-32.1, 327.5, -3580.0), "cargo_bay_clear_max": Vector3(32.1, 354.2, -3512.0),
}
const LIMIT_S: float = 3600.0

var held_violations: int = 0
var offset_error: float = 0.0


func _job(hull: String, loading: bool) -> CargoFerryJob:
	var plan: CargoFerryPlan = CargoFerryPlan.for_freighter(BAY, FreighterCargo.chunk_boxes_of(hull),
			Hardpoints.load_collision_only(ShipSpec.ASSET_ROOT.path_join(hull).path_join("hardpoints.json")))
	assert_true(plan.valid, plan.error)
	return CargoFerryJob.create(plan, loading)


# Steps the crew `seconds` (or until `until` is true), checking each tick that the pod moved only while held and that every bot
# holding it sits at its place.
func _run(job: CargoFerryJob, seconds: float, alarm: bool = false, until: Callable = Callable(), dt: float = DT) -> float:
	var t: float = 0.0
	while t < seconds:
		if until.is_valid() and until.call():
			break
		var pod: FerryPod = job.current()
		var before: float = pod.s if pod != null else 0.0
		for m: BotFerryMotion in job.crew:
			m.step(dt, alarm)
		if pod != null:
			if absf(pod.s - before) > 1e-6:
				for k: int in pod.trip.bot_count():
					if pod.needs(k) and pod.holding[k] == 0:
						held_violations += 1
			for k: int in pod.trip.bot_count():
				if pod.holding[k] != 0:
					offset_error = maxf(offset_error, job.crew[k].position.distance_to(pod.trip.bot_position(k, pod.s)))
		job.update()
		t += dt
	return t


func before_each() -> void:
	held_violations = 0
	offset_error = 0.0


func test_a_saturn_3_is_unloaded_pod_by_pod_by_one_bot() -> void:
	var job: CargoFerryJob = _job("saturn_3_freighter", false)
	assert_eq(job.pods.size(), 3)
	assert_true(job.crew[1].idle, "a Saturn 3 pod has one bot; the other stays in")
	var first: FerryPod = job.current()
	var t: float = _run(job, LIMIT_S, false, func() -> bool: return first.state == FerryPod.State.MOVING)
	assert_eq(first.holding[0], 1, "its bot holds it")
	assert_lt(t, 120.0, "the bot flew out and took it (%.0f s)" % t)
	var bot: BotFerryMotion = job.crew[0]
	assert_eq(bot.phase, BotFerryMotion.Phase.CARRY)
	t = _run(job, LIMIT_S, false, func() -> bool: return job.done())
	assert_true(job.done(), "all three in the bay (%.0f s)" % t)
	assert_eq(job.pods_done(), 3)
	for pod: FerryPod in job.pods:
		assert_true(pod.inside_wall(), "%s is inside the back wall" % pod.trip.pod_name)
	assert_true(job.crew_inside(), "the bots are inside too")
	assert_eq(held_violations, 0, "no pod moved by itself")
	assert_lt(offset_error, 1e-3, "a held pod and its bot move together")
	assert_eq(bot.trips, 3, "one bot, three trips")


func test_a_long_pod_or_a_tank_has_two_bots_front_and_back() -> void:
	for hull: String in ["saturn_4_transport", "saturn_4_tanker", "saturn_8_transport", "saturn_8_tanker"]:
		held_violations = 0
		offset_error = 0.0
		var job: CargoFerryJob = _job(hull, false)
		var pod: FerryPod = job.current()
		assert_eq(pod.trip.bot_count(), 2)
		var both_held: Array[bool] = [false]
		var turned: Array[float] = [0.0]
		_run(job, LIMIT_S, false, func() -> bool:
			var p: FerryPod = job.current()
			if p != null and p.holding[0] == 1 and p.holding[1] == 1:
				both_held[0] = true
			if p != null:
				turned[0] = maxf(turned[0], p.trip.roll_angle(p.pose().origin.z))
			return job.done())
		assert_true(job.done(), "%s unloaded" % hull)
		assert_true(both_held[0], "%s: both bots held a pod at once" % hull)
		assert_eq(held_violations, 0, "%s: no pod moved by itself" % hull)
		assert_lt(offset_error, 1e-3, "%s: the bots keep their places" % hull)
		if hull.contains("tanker"):
			assert_almost_eq(turned[0], PI * 0.5, 1e-3, "the tanks turn onto their side")


func test_loading_is_the_trip_reversed() -> void:
	var job: CargoFerryJob = _job("saturn_4_transport", true)
	var first: FerryPod = job.current()
	assert_eq(first.trip.pod_name, "pods_r", "loading starts with the last pod unloaded")
	assert_true(first.inside_wall(), "the pod starts in the bay")
	_run(job, LIMIT_S, false, func() -> bool: return job.done())
	assert_true(job.done())
	for pod: FerryPod in job.pods:
		assert_almost_eq(pod.s, 0.0, 1e-6, "%s is on the hull" % pod.trip.pod_name)
		assert_almost_eq(pod.pose().origin, pod.trip.centre_at(0.0), Vector3.ONE * 1e-3)
	assert_true(job.crew_inside(), "the bots flew home empty")
	assert_eq(held_violations, 0)


func test_fighting_away_from_the_bay_drops_the_pod_and_the_bots_come_back_for_it() -> void:
	var job: CargoFerryJob = _job("saturn_4_transport", false)
	var pod: FerryPod = job.current()
	_run(job, LIMIT_S, false, func() -> bool: return pod.state == FerryPod.State.MOVING and pod.s > pod.trip.unberth_s + 150.0)
	var dropped_at: float = pod.s
	_run(job, 1.0, true)
	assert_eq(pod.state, FerryPod.State.DROPPED, "let go")
	assert_almost_eq(pod.s, dropped_at, 30.0, "where it was")
	var lie: float = pod.s
	_run(job, 90.0, true)
	assert_almost_eq(pod.s, lie, 1e-6, "the pod waits where it was let go")
	assert_true(job.crew_inside(), "both bots went home")
	assert_eq(pod.holding.count(1), 0)
	var t: float = _run(job, 300.0, false, func() -> bool: return pod.state == FerryPod.State.MOVING)
	assert_eq(pod.state, FerryPod.State.MOVING, "after the quiet they came back and took it again (%.0f s)" % t)
	assert_almost_eq(pod.s, lie, 2.0, "from where it lay")
	_run(job, LIMIT_S, false, func() -> bool: return job.done())
	assert_true(job.done(), "and the job finished")
	assert_eq(pod.drops, 1)
	assert_eq(held_violations, 0)
	assert_lt(offset_error, 1e-3)


func test_fighting_with_the_pod_at_the_bays_mouth_carries_it_on_inside() -> void:
	var job: CargoFerryJob = _job("saturn_3_freighter", false)
	var pod: FerryPod = job.current()
	_run(job, LIMIT_S, false, func() -> bool: return pod.s > pod.trip.commit_s + 5.0)
	_run(job, 60.0, true, func() -> bool: return pod.done())
	assert_true(pod.done(), "carried on into the bay")
	assert_eq(pod.drops, 0)


func test_fighting_while_loading_near_the_bay_takes_the_pod_back_inside() -> void:
	var job: CargoFerryJob = _job("saturn_3_freighter", true)
	var pod: FerryPod = job.current()
	_run(job, LIMIT_S, false, func() -> bool: return pod.state == FerryPod.State.MOVING and not pod.inside_wall())
	_run(job, 120.0, true)
	assert_eq(pod.retreats, 1, "it went back")
	assert_true(pod.inside_wall(), "inside the wall")
	assert_eq(pod.state, FerryPod.State.WAITING)
	_run(job, LIMIT_S, false, func() -> bool: return job.done())
	assert_true(job.done(), "and the loading finished after the quiet")


func test_bots_sent_early_wait_for_the_freighter_and_take_the_plan_from_where_it_stopped() -> void:
	var job: CargoFerryJob = _job("saturn_3_freighter", false)
	for pod: FerryPod in job.pods:
		pod.berthed = false
	var first: FerryPod = job.current()
	_run(job, 30.0)
	var bot: BotFerryMotion = job.crew[0]
	assert_eq(bot.phase, BotFerryMotion.Phase.OUT, "on its way before the freighter is there")
	var s_before: float = bot.s
	# The freighter stopped 3 m short of the hold point.
	var stopped: Vector3 = Vector3(BAY["cargo_bay_hold"]) + Vector3(0.0, 0.0, -3.0)
	var plan: CargoFerryPlan = CargoFerryPlan.for_freighter(BAY, FreighterCargo.chunk_boxes_of("saturn_3_freighter"),
			Hardpoints.load_collision_only(ShipSpec.ASSET_ROOT.path_join("saturn_3_freighter").path_join("hardpoints.json")), stopped)
	assert_true(job.replan(plan), "planned again before any pod moved")
	assert_ne(job.current(), first)
	assert_almost_eq(bot.s, s_before, 1e-6, "the bot goes on from where it was")
	assert_almost_eq(job.current().trip.centre_at(0.0).z, first.trip.centre_at(0.0).z - 3.0, 1e-3, "the pod is where it sits now")
	_run(job, 120.0)
	assert_eq(job.current().state, FerryPod.State.WAITING, "held, but not moved before the freighter berths")
	assert_almost_eq(job.current().s, 0.0, 1e-6)
	job.berth()
	_run(job, 60.0)
	assert_gt(job.current().s, 0.0, "then it goes")
	assert_false(job.replan(plan), "too late to plan again once a pod moved")
	assert_eq(held_violations, 0)


func test_at_small_time_steps_a_pod_still_stops_for_its_second_bot() -> void:
	# The main scene's tests step at 1/480 s: a pod creeping into a stop must not slip past it.
	var job: CargoFerryJob = _job("saturn_8_transport", false)
	var pod: FerryPod = job.current()
	assert_gt(pod.trip.grab_s[1], 0.0, "its far bot takes hold after the lift")
	_run(job, 400.0, false, func() -> bool: return pod.s > pod.trip.unberth_s + 50.0, 1.0 / 480.0)
	assert_eq(pod.holding[1], 1, "both bots hold it past the lift")
	assert_eq(held_violations, 0)
