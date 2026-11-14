class_name CargoFerryJob
extends RefCounted
## A freighter's cargo carried between it and the cargo bay by the station's maintenance bots (M7-T30): one pod at a time, in the
## plan's order (loading in the reverse), by a crew of two bots that go on from pod to pod (a short pod takes one of them). Pure:
## `FreighterCargo` draws the pods and `BotFleet` steps the bots.

const CREW: int = 2
## The second bot of a crew leaves the wall this long after the first, s.
const STAGGER_S: float = 3.0

var plan: CargoFerryPlan = null
var loading: bool = false
var pods: Array[FerryPod] = []
var crew: Array[BotFerryMotion] = []
## The pod being carried now (`pods.size()` once all are done).
var index: int = 0


## The job for `p_plan` (valid), unloading or loading; its crew starts on the first pod, hidden in the wall.
static func create(p_plan: CargoFerryPlan, p_loading: bool) -> CargoFerryJob:
	var job := CargoFerryJob.new()
	job.plan = p_plan
	job.loading = p_loading
	var order: Array[CargoTrip] = p_plan.trips.duplicate()
	if p_loading:
		order.reverse()
	for trip: CargoTrip in order:
		job.pods.append(FerryPod.new(trip, p_loading))
	var first: CargoTrip = order[0]
	for k: int in CREW:
		var m := BotFerryMotion.new()
		m.setup(first.out_routes[0], first.out_routes[0], Vector3.UP, 0.0)
		job.crew.append(m)
	job._assign()
	return job


func current() -> FerryPod:
	return pods[index] if index < pods.size() else null


func done() -> bool:
	return index >= pods.size()


## Pods carried all the way (into the bay, or onto the hull).
func pods_done() -> int:
	var n: int = 0
	for p: FerryPod in pods:
		n += 1 if p.done() else 0
	return n


## Moves on to the next pod once the current one is done and its crew is back inside. True when the whole job is done.
func update() -> bool:
	var pod: FerryPod = current()
	if pod == null:
		return true
	if not pod.done() or not crew_inside():
		return false
	index += 1
	if done():
		for m: BotFerryMotion in crew:
			m.carry(null, 0)
		return true
	_assign()
	return false


## Whether no pod has moved yet (so the job can still be planned again).
func untouched() -> bool:
	return index == 0 and pods[0].state == FerryPod.State.WAITING and (pods[0].s == 0.0 or loading)


## Plans the job again from `p_plan` (the freighter where it stopped) while no pod has moved; the bots on their way switch to the
## new routes where they are (the lanes out of the bay are the same). False when too late.
func replan(p_plan: CargoFerryPlan) -> bool:
	if not untouched() or p_plan.trips.size() != pods.size():
		return false
	var order: Array[CargoTrip] = p_plan.trips.duplicate()
	if loading:
		order.reverse()
	for i: int in pods.size():
		var fresh := FerryPod.new(order[i], loading)
		fresh.take_over(pods[i])
		fresh.berthed = pods[i].berthed
		pods[i] = fresh
	plan = p_plan
	for k: int in CREW:
		if not crew[k].idle:
			crew[k].retarget(pods[0])
	return true


## Lets every pod move: the freighter is at its hold point.
func berth() -> void:
	for p: FerryPod in pods:
		p.berthed = true


func crew_inside() -> bool:
	for m: BotFerryMotion in crew:
		if m.phase != BotFerryMotion.Phase.HIDDEN:
			return false
	return true


func _assign() -> void:
	var pod: FerryPod = pods[index]
	for k: int in CREW:
		if k < pod.trip.bot_count():
			crew[k].carry(pod, k, STAGGER_S * float(k))
		else:
			crew[k].carry(null, 0)
