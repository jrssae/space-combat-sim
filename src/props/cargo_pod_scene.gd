class_name CargoPodScene
extends Node
## The cargo scene (M7-T11, the maintainer's request; M7-T34: cargo pods instead of maintenance bots): a Saturn 3 holding at the
## cargo bay's hold point **stern toward the bay** (it backs in; its nose points away from the station, its cargo nearest the bay)
## and a cluster of cargo pods shuttling between its blocks and the bay, some going out while others come back. Loaded and removed
## from the console (`pods cargo`, or `bots cargo` as before).
##
## **The freighter** is a pooled `saturn_3_freighter` taken out of the ship pool (the way every civilian is: the encounter director,
## M5's pool) with an `IdleBrain` that holds the brake, so nothing flies it away; it is ambient for this scene. `freighter` is the
## ship, `place_freighter` takes any `PilotBrain`, and `plan` says where the hold point is and which way a freighter must face there.
## **The pods** are `CargoPodMotion`s in the pod fleet, one `CargoFerryPlan` route pair each, staggered round the trip.

const FREIGHTER_TYPE: StringName = &"saturn_3_freighter"
const FREIGHTER_NAME: String = "SATURN 3"
const HARDPOINTS: String = "res://assets/generated/saturn_3_freighter/hardpoints.json"
const DEFAULT_PODS: int = 5
const MAX_PODS: int = 12
## Where `view` puts the player, from the hold point toward the bay (m), to the right and up: close to the lane, looking at the
## blocks' end, so the pods fly past on their way out and back. `bayview` is from just behind the Saturn, looking down the lane at the bay.
const VIEW_BACK_M: float = 220.0
const VIEW_SIDE_M: float = 110.0
const VIEW_UP_M: float = 40.0
const VIEW_LOOK_M: float = 45.0
const BAYVIEW_BACK_M: float = 110.0
const BAYVIEW_SIDE_M: float = 55.0
const BAYVIEW_UP_M: float = 30.0

var fleet: CargoPodFleet = null
var station: Station = null
var plan: CargoFerryPlan = null
## The Saturn, null until loaded.
var freighter: Combatant = null
## This scene's cargo pods (a traffic freighter's crew is not the scene's).
var own_pods: Array[CargoPodCraft] = []


func loaded() -> bool:
	return freighter != null or not own_pods.is_empty()


## `pods cargo [n|off|view|bayview]` (and `bots cargo`, the same).
func command(arg: String) -> ConsoleResult:
	if station == null or station.main == null:
		return ConsoleResult.failure("pods cargo: no station in play")
	match arg:
		"off":
			var had: bool = loaded()
			unload()
			return ConsoleResult.line("cargo scene removed" if had else "no cargo scene loaded")
		"view":
			return view(false)
		"bayview":
			return view(true)
	if not (arg.is_empty() or arg.is_valid_int()):
		return ConsoleResult.failure("pods cargo [n|off|view|bayview]")
	return load_scene(int(arg) if arg.is_valid_int() else DEFAULT_PODS)


## Backs a Saturn 3 in at the hold point and sets `n` cargo pods going; replaces a scene already loaded.
func load_scene(n: int) -> ConsoleResult:
	unload()
	plan = CargoFerryPlan.build(station.hardpoints.cargo_bay, Hardpoints.load_collision_only(HARDPOINTS))
	if not plan.valid:
		return ConsoleResult.failure("pods cargo: %s (run scripts/gen_assets.sh, then import)" % plan.error)
	var made: String = place_freighter(IdleBrain.new(true))
	if not made.is_empty():
		return ConsoleResult.failure("pods cargo: %s" % made)
	n = clampi(n, 1, MAX_PODS)
	var cycle_s: float = trip_seconds(plan)
	for lane: int in n:
		var routes: Array[BotRoute] = plan.routes_for(lane)
		var motion := CargoPodMotion.new()
		motion.setup(routes[0], routes[1], Vector3.UP, 0.0)
		warm(motion, cycle_s * float(lane) / float(n))
		own_pods.append(fleet.add_pod(motion))
	return ConsoleResult.line("%s backed in at the cargo bay's hold point, %d cargo pods (a trip takes %.0f s)" % [FREIGHTER_NAME, n, cycle_s])


## Takes the Saturn out of the pool, at the hold point stern toward the bay, flown by `brain` (T10 brings its own). "" or why not.
func place_freighter(brain: PilotBrain) -> String:
	var main: Main = station.main
	if main.ensure_pool(FREIGHTER_TYPE, 1) < 0 or main.ships.free_count(FREIGHTER_TYPE) < 1:
		return "no %s is free in the ship pool" % FREIGHTER_TYPE
	var pose: Transform3D = station.global_transform * plan.freighter_transform()
	var world: WorldFrame = main.world
	freighter = main.ships.acquire(FREIGHTER_NAME, world.to_universe(pose.origin), pose.basis, world.rest_velocity(), brain, FREIGHTER_TYPE)
	if freighter == null:
		return "the ship pool gave no %s" % FREIGHTER_TYPE
	return ""


## Removes the scene's cargo pods and sends the Saturn back to the pool.
func unload() -> void:
	for craft: CargoPodCraft in own_pods:
		fleet.remove_pod(craft)
	own_pods.clear()
	if freighter != null and station != null and station.main != null:
		station.main.ships.release(freighter)
	freighter = null


## Puts the player toward the bay from the Saturn, to one side and above, looking at its blocks' end (the pods fly past in front of
## it), or with `down_the_lane` from just behind the Saturn looking along the lane at the bay.
func view(down_the_lane: bool) -> ConsoleResult:
	var main: Main = station.main
	if not main.player_alive:
		return ConsoleResult.failure("pods cargo view: no player to move")
	if plan == null or not plan.valid:
		plan = CargoFerryPlan.build(station.hardpoints.cargo_bay, Hardpoints.load_collision_only(HARDPOINTS))
		if not plan.valid:
			return ConsoleResult.failure("pods cargo view: %s" % plan.error)
	var at: Vector3 = station.to_global(plan.hold + plan.axis * VIEW_BACK_M + Vector3(VIEW_SIDE_M, VIEW_UP_M, 0.0))
	var look: Vector3 = station.to_global(plan.hold + plan.axis * VIEW_LOOK_M)
	if down_the_lane:
		at = station.to_global(plan.hold + plan.axis * BAYVIEW_BACK_M + Vector3(BAYVIEW_SIDE_M, BAYVIEW_UP_M, 0.0))
		look = station.to_global(plan.entry)
	var forward: Vector3 = (look - at).normalized()
	main.ship.reset_to(Transform3D(Basis.looking_at(forward, Vector3.UP), at))
	main.ship.linear_velocity = main.world.rest_velocity()
	main.ship.angular_velocity = Vector3.ZERO
	return ConsoleResult.line("%s: %.0f m from the %s" % ["looking down the lane at the bay" if down_the_lane else "looking at its pods", at.distance_to(station.to_global(plan.hold)), FREIGHTER_NAME])


## How long one pod's whole trip takes (out, the wait, back, hidden), seconds, at cruise on lane 0.
static func trip_seconds(for_plan: CargoFerryPlan) -> float:
	var routes: Array[BotRoute] = for_plan.routes_for(0)
	var cruise: float = CargoPodMotion.CRUISE_MPS
	return (routes[0].length_m + routes[1].length_m) / cruise + CargoPodMotion.WAIT_AT_PODS_S + CargoPodMotion.HIDDEN_S + 2.0 * cruise / CargoPodMotion.ACCEL_MPS2


## Runs `motion` on `seconds` with nothing to fear, so a pod starts part way round its trip (the stagger).
static func warm(motion: CargoPodMotion, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		motion.step(0.1, false)
		t += 0.1
