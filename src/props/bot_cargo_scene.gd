class_name BotCargoScene
extends Node
## The cargo scene (M7-T11, the maintainer's request): a Saturn 3 holding at the cargo bay's hold point **stern toward the bay**
## (it backs in; its nose points away from the station, its cargo pods nearest the bay) and a cluster of ferry bots shuttling
## between its pods and the bay, some going out while others come back. Loaded and removed from the console (`bots cargo`).
##
## **The freighter** is a pooled `saturn_3_freighter` taken out of the ship pool (the way every civilian is: the encounter director,
## M5's pool) with an `IdleBrain` that holds the brake, so nothing flies it away; it is ambient for this scene. It has no seam of
## its own to T10 beyond this: `freighter` is the ship, `place_freighter` takes any `PilotBrain`, and `plan` says where the hold point
## is and which way a freighter must face there; T10's freighters arrive stern first, hold, and leave nose first.
## **The bots** are `BotFerryMotion`s on the fleet's frame, one `CargoFerryPlan` route pair each, staggered round the trip.

const FREIGHTER_TYPE: StringName = &"saturn_3_freighter"
const FREIGHTER_NAME: String = "SATURN 3"
const HARDPOINTS: String = "res://assets/generated/saturn_3_freighter/hardpoints.json"
const DEFAULT_BOTS: int = 5
const MAX_BOTS: int = 12
## Where `view` puts the player, from the hold point toward the bay (m), to the right and up: close to the lane, looking at the
## pods' end, so the bots fly past on their way out and back. `bayview` is from just behind the Saturn, looking down the lane at the bay.
const VIEW_BACK_M: float = 220.0
const VIEW_SIDE_M: float = 110.0
const VIEW_UP_M: float = 40.0
const VIEW_LOOK_M: float = 45.0
const BAYVIEW_BACK_M: float = 110.0
const BAYVIEW_SIDE_M: float = 55.0
const BAYVIEW_UP_M: float = 30.0

var fleet: BotFleet = null
var station: Station = null
var plan: CargoFerryPlan = null
## The Saturn, null until loaded.
var freighter: Combatant = null
## This scene's ferry bots (a traffic freighter's crew is not the scene's).
var own_bots: Array[MaintenanceBot] = []


func loaded() -> bool:
	return freighter != null or not own_bots.is_empty()


## `bots cargo [n|off|view]`.
func command(arg: String) -> ConsoleResult:
	if station == null or station.main == null:
		return ConsoleResult.failure("bots cargo: no station in play")
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
		return ConsoleResult.failure("bots cargo [n|off|view|bayview]")
	return load_scene(int(arg) if arg.is_valid_int() else DEFAULT_BOTS)


## Backs a Saturn 3 in at the hold point and sets `n` ferry bots going; replaces a scene already loaded.
func load_scene(n: int) -> ConsoleResult:
	unload()
	plan = CargoFerryPlan.build(station.hardpoints.cargo_bay, Hardpoints.load_collision_only(HARDPOINTS))
	if not plan.valid:
		return ConsoleResult.failure("bots cargo: %s (run scripts/gen_assets.sh, then import)" % plan.error)
	var made: String = place_freighter(IdleBrain.new(true))
	if not made.is_empty():
		return ConsoleResult.failure("bots cargo: %s" % made)
	n = clampi(n, 1, MAX_BOTS)
	var cycle_s: float = trip_seconds(plan)
	for lane: int in n:
		var routes: Array[BotRoute] = plan.routes_for(lane)
		var motion := BotFerryMotion.new()
		motion.setup(routes[0], routes[1], Vector3.UP, 0.0)
		warm(motion, cycle_s * float(lane) / float(n))
		own_bots.append(fleet.add_ferry_bot(motion))
	return ConsoleResult.line("%s backed in at the cargo bay's hold point, %d ferry bots (a trip takes %.0f s)" % [FREIGHTER_NAME, n, cycle_s])


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


## Removes the ferry bots and sends the Saturn back to the pool.
func unload() -> void:
	for bot: MaintenanceBot in own_bots:
		fleet.remove_ferry_bot(bot)
	own_bots.clear()
	if freighter != null and station != null and station.main != null:
		station.main.ships.release(freighter)
	freighter = null


## Puts the player toward the bay from the Saturn, to one side and above, looking at its pods' end (the bots fly past in front of
## it), or with `down_the_lane` from just behind the Saturn looking along the lane at the bay.
func view(down_the_lane: bool) -> ConsoleResult:
	var main: Main = station.main
	if not main.player_alive:
		return ConsoleResult.failure("bots cargo view: no player to move")
	if plan == null or not plan.valid:
		plan = CargoFerryPlan.build(station.hardpoints.cargo_bay, Hardpoints.load_collision_only(HARDPOINTS))
		if not plan.valid:
			return ConsoleResult.failure("bots cargo view: %s" % plan.error)
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


## How long one bot's whole trip takes (out, the wait, back, hidden), seconds, at cruise on lane 0.
static func trip_seconds(for_plan: CargoFerryPlan) -> float:
	var routes: Array[BotRoute] = for_plan.routes_for(0)
	var cruise: float = BotFerryMotion.CRUISE_MPS
	return (routes[0].length_m + routes[1].length_m) / cruise + BotFerryMotion.WAIT_AT_PODS_S + BotFerryMotion.HIDDEN_S + 2.0 * cruise / BotFerryMotion.ACCEL_MPS2


## Runs `motion` on `seconds` with nothing to fear, so a bot starts part way round its trip (the stagger).
static func warm(motion: BotFerryMotion, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		motion.step(0.1, false)
		t += 0.1
