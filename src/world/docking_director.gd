class_name DockingDirector
extends Node
## Docking for repair in the main docking bay (M8-T06, D82, AC5). Main's child; the node side of `DockVisit`.
##
## - **The player** holds X on the bay's navigation target within its reach: the controls are held, `DockAutopilot` flies the
##   ship round the station (`DockKeepOut`) to the lane and along it through the mouth and the inner doors, slowing it from
##   whatever speed it had. Behind the doors the ship leaves play (hidden, sheltered, touching nothing), `DockRepair`'s clock runs
##   (an AI wingman's, a fixed time; the player does not wait), the hull, the guns' charge and the tank are restored, and it
##   launches from a Cobra bay through `LaunchDirector` (its exterior shots, M8-T03; its skip, its hand-off). The cinematic's skip jumps a
##   stage ahead: to the bay and its launch, then to the hand-off.
## - **Wingmen** of the player's wing dock on the wing order (key 6, the comms menu's DOCK) and by themselves below the hull
##   threshold. A docking wingman flies a docking pilot (`assets/ai/docking.tres`) on routes the native brains fly: to a
##   waiting point off the bow with avoidance on, then `DockingPlan`'s lane (the roster reads DOCKING). Inside it is away (`Wing.set_away`: its slot is
##   kept, it is not lost), then it launches from a Cobra bay, gets its own pilot back and rejoins.
## - **Home docks** (maintainer, 2026-11-18): a fighter docks only at its own home (`Combatant.home`), found among the nav
##   points that offer `dock`, and only with that dock's bay within `dock_range_m`. Otherwise it stays and fights, the bay
##   offers the player nothing and the wing's order cannot be given (`order_available`).
## - **One at a time** through the tunnel, with the station's traffic: a fighter waits off the bow while a civilian or another
##   fighter has the lane, and the traffic starts nothing while a fighter is on it.
##
## Console: provider and command `dock`.

signal player_docked
signal player_repaired
signal player_relaunched
signal wingman_docked(ship_name: String)
signal wingman_rejoined(ship_name: String)
## Control offered the bay to a damaged player (D79 beat 13); a mission that speaks its own line turns `offer_line` off.
signal dock_offered
signal noticed(line: String)

const NODE_NAME: StringName = &"DockingDirector"
const DATA_PATH: String = "res://data/station/docking.json"
const PROFILE_PATH: String = "res://assets/ai/docking.tres"
const PROVIDER: StringName = &"dock"
const ACTIONS: Array[StringName] = [&"status", &"player", &"wing", &"cancel", &"skip"]
## After the launches (-45), before the tier (-12) and the core's sync (-11).
const PRIORITY: int = -44
const NOTICE_S: float = 4.0
## The route a wingman flies to its stand-off while the player docks.
const STAND_OFF_ROUTE: String = "STANDING OFF"
## A fighter through the inner doors waits at most this long for them to shut behind it, seconds.
const DOORS_WAIT_S: float = 20.0
## The docking shots, a pool per stage (M8-T31).
const SHOTS_PATH: String = "res://data/station/docking_shots.json"
## The player's ship holds this far short of the mouth until it turns with the drum (M8-T31), metres.
const ROLL_GATE_M: float = 300.0
## And it must turn with the drum this long before it goes on, seconds, and wait at the hold point at least `ROLL_SHOW_S`, so the
## match is always seen, however early it came (the maintainer asked to see it).
const ROLL_HOLD_S: float = 0.5
const ROLL_SHOW_S: float = 3.5
## Within this of the hold point the ship counts as holding there, metres.
const ROLL_AT_GATE_M: float = 15.0
## A docking camera keeps this clear of the station's hull, metres; a take may lose sight of the ship for at most this share.
const SHOT_CLEAR_M: float = 12.0
const SHOT_MAX_BLOCKED: float = 0.2

var main: Main = null
var plan: DockingPlan = null
var keep_out: DockKeepOut = null
var repair: DockRepair = DockRepair.new()
## Whether Control's offer is posted on the HUD's line (the signal is sent either way).
var offer_line: bool = true
var docked_count: int = 0
var relaunched_count: int = 0
## Recalled fighters that docked and stayed inside (M8-T34).
var stowed_count: int = 0
var last_notice: String = ""
## The latest visit that ended, for the console and the tests.
var last_visit: DockVisit = null

var join_out_m: float = 400.0
## Fighters first at the bay (maintainer, 2026-11-19; `data/station/docking.json`'s `priority`): a fighter claims the bay on
## the lane, or on its approach within `claim_within_m` of the mouth; a civilian on the lane farther out than `commit_out_m`
## then moves `yield_off_m` aside; a fighter that must wait does so `wait_off_m` below the lane, never on it.
var claim_within_m: float = 3000.0
var commit_out_m: float = 700.0
var yield_off_m: float = 300.0
var wait_off_m: float = 150.0
## Where the player's wingmen stand off while the player docks (`wing_wait`): to their side of the lane, below it and off the
## mouth, one `stand_spacing_m` farther per slot, flown at `stand_cruise_mps`.
var stand_side_m: float = 1500.0
var stand_below_m: float = 700.0
var stand_out_m: float = 800.0
var stand_spacing_m: float = 150.0
var stand_cruise_mps: float = 120.0
var corridor_m: float = 35.0
var approach_mps: float = 140.0
var via_mps: float = 45.0
var lane_mps: float = 40.0
var inner_mps: float = 20.0
var join_max_mps: float = 70.0
var clear_m: float = 35.0
var via_m: float = 60.0
var timeout_s: float = 240.0
var wingman_auto: bool = true
var wingman_hull_below: float = 0.25
## A fighter docks only at its home dock (`Combatant.home`), and only with that dock's bay within this range of it, metres.
var dock_range_m: float = 60000.0
var wingman_cruise_mps: float = 120.0
var entry_out_m: float = 500.0
## A wingman flying faster than `peel_above_mps` first swings `peel_out_m` out of its formation, `peel_ahead_s` on along its
## course at the speed it has, and only then turns for the bay: braking where it flew would put it in the way of the ships behind.
var peel_above_mps: float = 50.0
var peel_out_m: float = 250.0
var peel_ahead_s: float = 3.0
var queue_spacing_m: float = 250.0
var offer_hull_below: float = 0.5
var offer_text: String = ""
var relaunch_wing: String = "alpha"
var relaunch_door: int = 1
var retry_s: float = 0.5
var give_up_s: float = 90.0
## How far short of the mouth the player's last visit turned with the drum, metres (-1: not yet).
var roll_matched_at_m: float = -1.0

# One entry a ship: {visit, combatant, kept, reach, key, brain, docker, stage, queue, retry_in_s}.
var _entries: Array[Dictionary] = []
var _boxes: Array[AABB] = []
## The player's docking shots (M8-T31): short takes from `SHOTS_PATH`, a stage each part of the visit.
var shots: ShotSequencer = ShotSequencer.new(ShotPool.load_file(SHOTS_PATH), "docking")
var _my_shot: CinematicShot = null
var _key_light: CinematicKeyLight = CinematicKeyLight.new()
var _wired: Station = null
var _capability: ShipCapability = null
var _notice_left_s: float = 0.0
# The stand-off route each wingman was given while the player docks, by the wingman's instance id.
var _stand_offs: Dictionary = {}
var _offer_armed: bool = true
var _started: int = 0
var _player_pose: Variant = null


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	_load_data()
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func station() -> Station:
	if main == null or main.far_props == null:
		return null
	var s: Station = main.far_props.station
	return s if s != null and is_instance_valid(s) and s.hardpoints != null else null


# --- asking ------------------------------------------------------------------------------------------------------------


## The player's visit under way, or null.
func player_visit() -> DockVisit:
	var entry: Dictionary = _player_entry()
	return entry["visit"] if not entry.is_empty() else null


## The visit of the ship called `ship_name`, or null.
func visit_of(ship_name: String) -> DockVisit:
	for entry: Dictionary in _entries:
		if (entry["visit"] as DockVisit).ship_name.to_lower() == ship_name.to_lower():
			return entry["visit"]
	return null


func visits() -> Array[DockVisit]:
	var out: Array[DockVisit] = []
	for entry: Dictionary in _entries:
		out.append(entry["visit"])
	return out


## The docking holds the player's controls (`Main.controls_locked`).
func locks_controls() -> bool:
	return not _player_entry().is_empty()


## A fighter is cleared to dock (maintainer, 2026-11-19): on the lane or through the doors, or on its way in within
## `claim_within_m` of the mouth. The station's civilians keep off the lane meanwhile and go again afterwards.
func claims_bay() -> bool:
	var s: Station = station()
	if s == null or plan == null:
		return false
	for entry: Dictionary in _entries:
		var visit: DockVisit = entry["visit"]
		if visit.state == DockVisit.State.LANE or visit.state == DockVisit.State.INSIDE:
			return true
		var c: Combatant = entry["combatant"]
		if visit.state == DockVisit.State.APPROACH and is_instance_valid(c.ship) \
				and c.ship.global_position.distance_to(s.global_transform * plan.mouth) <= claim_within_m:
			return true
	return false


## A fighter is on the lane or through the doors: the station's traffic starts nothing in the bay meanwhile.
func holds_bay() -> bool:
	for entry: Dictionary in _entries:
		var state: DockVisit.State = (entry["visit"] as DockVisit).state
		if state == DockVisit.State.LANE or state == DockVisit.State.INSIDE:
			return true
	return false


## The HUD's line for a few seconds after something was said ("" otherwise).
func notice_text() -> String:
	return last_notice if _notice_left_s > 0.0 else ""


## Why the player cannot dock now, or "".
func player_refusal() -> String:
	if main == null or not main.player_alive:
		return "the player's ship is lost"
	if not _player_entry().is_empty():
		return "docking is under way (%s)" % player_visit().state_name()
	if main.launches != null and main.launches.locks_controls():
		return "the player is launching"
	if main.gates != null and main.gates.jump.is_active():
		return "a jump is under way"
	var plan_problem: String = _ready_plan()
	return plan_problem if not plan_problem.is_empty() else dock_refusal(main.combatant)


## The dock `c` belongs to (M8-T06): the nav point that offers `dock` under the id `c.home` names, wherever it is; null with
## no home or when its home is gone. Any docking bay in `NavPoint.DOCKS_GROUP` counts, a later station's or a carrier's too.
func home_dock(c: Combatant) -> NavPoint:
	if c == null or c.home == &"" or not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group(NavPoint.DOCKS_GROUP):
		var point := node as NavPoint
		if point != null and point.home_id == c.home and point.is_inside_tree():
			return point
	return null


## Why `c` cannot dock for repair now, or "": it needs a home dock, within `dock_range_m`, that this director flies ships into.
func dock_refusal(c: Combatant) -> String:
	if c == null or not is_instance_valid(c.ship):
		return "no such ship"
	if c.home == &"":
		return "%s has no home dock" % c.display_name
	var dock: NavPoint = home_dock(c)
	if dock == null:
		return "%s's home dock (%s) is not here" % [c.display_name, c.home]
	if c.ship.global_position.distance_to(dock.global_position) > dock_range_m:
		return "%s's home dock is out of range (%.0f km)" % [c.display_name, dock_range_m / 1000.0]
	var s: Station = station()
	if s == null or dock != s.docking_bay:
		return "%s's home dock (%s) takes its ships in itself" % [c.display_name, c.home]
	return ""


## Whether the wing's DOCK order can be given (M8-T06; maintainer, 2026-11-18): a wingman of the player's wing has its home dock
## in range. Otherwise the comms menu leaves the entry out and the key does nothing.
func order_available() -> bool:
	var wing: Wing = main.wings.player_wing() if main != null and main.wings != null else null
	if wing == null or not _ready_plan().is_empty():
		return false
	for member: Combatant in wing.members():
		if dock_refusal(member).is_empty():
			return true
	return false


## Starts the player's docking: the controls are held and the autopilot takes the ship in. Returns "" or why not.
func start_player(why: StringName = DockVisit.WHY_HOLD) -> String:
	var refused: String = player_refusal()
	if not refused.is_empty():
		return refused
	var ship: Ship = main.ship
	var visit := DockVisit.new(main.combatant.display_name, true, why)
	var entry: Dictionary = _new_entry(visit, main.combatant)
	entry["assist"] = ship.assist_on
	ship.assist_on = true
	_capability = ShipCapability.from_spec(ship.spec, ship.get_layout())
	_entries.append(entry)
	_started += 1
	_player_pose = null
	shots.usable = _take_clear
	shots.begin(&"approach", _play_shot, roundi(SimClock.now() * 10.0))
	_break_wing_off()
	_say("%s: DOCKING, AUTOPILOT ENGAGED" % Station.DOCKING_BAY_NAME)
	return ""


## Sends `member` (a wingman in play flying an `AiPilot`) to the bay. Returns "" or why not.
func start_wingman(member: Combatant, why: StringName = DockVisit.WHY_ORDER) -> String:
	var refused: String = _ready_plan()
	if not refused.is_empty():
		return refused
	if member == null or not is_instance_valid(member.ship) or member.is_player:
		return "no such wingman"
	if member.driver == null or not (member.driver.brain is AiPilot):
		return "%s flies no AI pilot" % member.display_name
	if member.damageable == null or not member.damageable.is_active():
		return "%s is not in play" % member.display_name
	if visit_of(member.display_name) != null:
		return "%s is docking already" % member.display_name
	refused = dock_refusal(member)
	if not refused.is_empty():
		return refused
	var profile: AiProfile = load(PROFILE_PATH) as AiProfile
	if profile == null:
		return "the docking pilot's profile is missing (%s)" % PROFILE_PATH
	# A flight's lead hands the flight to its first wingman and docks as one of its wingmen, so the flight flies on.
	var led: Wing = _wing_led_by(member)
	if led != null and not led.members().is_empty():
		main.wings.hand_lead(led)
	var visit := DockVisit.new(member.display_name, false, why)
	var entry: Dictionary = _new_entry(visit, member)
	entry["brain"] = member.driver.brain
	entry["exempt"] = member.ship.tier_exempt
	entry["queue"] = _waiting_wingmen()
	var docker := AiPilot.new(profile, hash([member.display_name, "dock", _started]), [] as Array[AiBehaviour],
			AiTemperament.new(profile.skill, profile.aggression))
	entry["docker"] = docker
	var peel: Route = _peel_route(member)
	entry["stage"] = &"peel" if peel != null else &"transit"
	BehaviourFollowPath.attach(docker, peel if peel != null else _transit_route(entry))
	member.driver.brain = docker
	member.ship.tier_exempt = true  # the lane is flown in full, wherever the player is
	var wing: Wing = _wing_of(member)
	if wing != null:
		wing.set_docking(member, true)  # the roster reads DOCKING until it is inside
	_entries.append(entry)
	_started += 1
	return ""


## The wing order (key 6, the comms menu's DOCK): every damaged wingman of the player's wing docks. Returns `{ok, line}`.
func order_wing() -> Dictionary:
	var wing: Wing = main.wings.player_wing() if main != null and main.wings != null else null
	if wing == null or wing.members().is_empty():
		return _answer(false, "%s: NO WINGMEN" % (wing.name if wing != null else Wing.DEFAULT_NAME))
	var speaker: String = wing.speaker()
	if not order_available():
		return _answer(false, "%s: NEGATIVE, NO DOCK IN RANGE" % speaker)  # the console's answer: the key and the menu never ask
	var sent := PackedStringArray()
	var busy: int = 0
	for member: Combatant in wing.members():
		if visit_of(member.display_name) != null:
			busy += 1
		elif member.damageable != null and member.damageable.hull.fraction() < 1.0 \
				and start_wingman(member, DockVisit.WHY_ORDER).is_empty():
			sent.append(member.display_name)
	if sent.is_empty():
		return _answer(false, "%s: %s" % [speaker, "ALREADY DOCKING" if busy > 0 else "NEGATIVE, NO DAMAGE TO REPAIR"])
	return _answer(true, "%s: COPY, DOCKING FOR REPAIRS" % sent[0])


## Control's recall (M8-T34): every fighter whose home is this station, AI wings and the player's wingmen alike, flies home and
## docks, and stays inside (back to its pool) so the wings launch whole again. Returns how many were sent or turned for home.
func recall_all() -> int:
	if main == null or main.wings == null or not _ready_plan().is_empty():
		return 0
	var n: int = 0
	for wing: Wing in main.wings.wings.duplicate():
		var ships: Array[Combatant] = wing.members()
		if wing.leader != null and not wing.leader.is_player:
			ships.append(wing.leader)
		for member: Combatant in ships:
			var visit: DockVisit = visit_of(member.display_name)
			if visit != null:
				visit.why = DockVisit.WHY_RECALL  # already on its way in: it stays inside too
				n += 1
			elif start_wingman(member, DockVisit.WHY_RECALL).is_empty():
				n += 1
	return n


## Calls off the visit of `ship_name` (default: the player's) while the ship is still outside the inner doors. "" or why not.
func cancel(ship_name: String = "", reason: String = "cancelled") -> String:
	var entry: Dictionary = _player_entry() if ship_name.is_empty() else _entry_named(ship_name)
	if entry.is_empty():
		return "nothing is docking" if ship_name.is_empty() else "%s is not docking" % ship_name
	var visit: DockVisit = entry["visit"]
	if not visit.can_cancel():
		return "%s is inside the station already (%s)" % [visit.ship_name, visit.state_name()]
	_end(entry, reason)
	return ""


## Whether the pilot may abort the docking now (M8-T32): while the autopilot approaches and flies the lane, until the ship is
## through the inner doors.
func abort_offered() -> bool:
	var visit: DockVisit = player_visit()
	return visit != null and (visit.state == DockVisit.State.APPROACH or visit.state == DockVisit.State.LANE)


## The pilot's abort (`AutopilotAbort`): the ship flies on with its velocity, the shots stop and the controls come back. "" or
## why not.
func abort() -> String:
	if not abort_offered():
		return "no docking to abort, or the ship is through the inner doors"
	return cancel("", "aborted by the pilot")


## Ends the player's visit whatever its state (a respawn, the scene's own reset): the ship is in the pilot's hands again.
func cancel_player(reason: String) -> void:
	var entry: Dictionary = _player_entry()
	if not entry.is_empty():
		_end(entry, reason)


## The cinematic's skip (`Main`): the player's visit jumps ahead to the bay, and so straight to its launch.
func skip() -> void:
	var entry: Dictionary = _player_entry()
	if entry.is_empty():
		return
	var visit: DockVisit = entry["visit"]
	match visit.state:
		DockVisit.State.APPROACH, DockVisit.State.LANE, DockVisit.State.INSIDE:
			visit.skipped = true
			_dock_now(entry)
		DockVisit.State.REPAIR:
			visit.skipped = true
			visit.repair_left_s = 0.0


## The player's flight command while the autopilot flies it in (`Main` flies it as the gate jump's), a coasting command while
## the ship is inside, null with no visit and while the launch has it.
func step_player(_delta: float) -> FlightCommand:
	var entry: Dictionary = _player_entry()
	var s: Station = station()
	if entry.is_empty() or s == null or plan == null:
		return null
	var visit: DockVisit = entry["visit"]
	if visit.state == DockVisit.State.LAUNCHING:
		return null
	if visit.state != DockVisit.State.APPROACH and visit.state != DockVisit.State.LANE and visit.state != DockVisit.State.INSIDE:
		return FlightCommand.new()
	var ship: Ship = main.ship
	var xform: Transform3D = s.global_transform
	var velocity: Vector3 = ship.linear_velocity - main.world.anchored_velocity()
	var local: Vector3 = xform.affine_inverse() * ship.global_position
	if visit.state == DockVisit.State.APPROACH:
		var target: Vector3 = keep_out.next_target(local)
		# The last leg ends at rest on the lane; a turning point is passed at speed.
		var arrive: float = 0.0 if target.is_equal_approx(keep_out.goal) else via_mps
		if arrive == 0.0 and _bay_taken(entry):
			target += _below() * wait_off_m  # a ship it cannot ask aside has the lane: it waits beside the lane, never on it
		return DockAutopilot.approach(ship.global_position, velocity, ship.global_basis, xform * target, approach_mps, arrive,
				_capability)
	var axis: Vector3 = _axis()
	var along: float = (local - plan.mouth).dot(axis)
	var reach: Vector2 = entry["reach"]
	var lock: StationAirlock = s.airlock
	var stop_at: float = (plan.airlock - plan.mouth).dot(axis)
	if lock != null and not lock.doors.is_open():
		stop_at = (lock.doors_at - plan.mouth).dot(axis) - reach.x - 15.0  # short of the doors until they stand open
	if not bool(entry.get("rolled", false)):
		stop_at = minf(stop_at, -ROLL_GATE_M)  # short of the mouth until it turns with the drum (M8-T31)
	var cap: float = lane_mps if along < -reach.x else inner_mps
	var speed: float = DockAutopilot.lane_speed(stop_at - along, cap, _capability)
	# The match starts at the hold point, so it is seen: the ship comes down the lane at its own roll and turns with the drum there.
	var roll: float = 0.0
	if bool(entry.get("rolled", false)) or along >= -ROLL_GATE_M - ROLL_AT_GATE_M:
		roll = DockAutopilot.roll_with(ship.global_basis, _spin_world(s), _square_ups(s), _capability.rate_max_rad)
	return DockAutopilot.lane(ship.global_position, velocity, ship.global_basis, xform * plan.mouth, xform.basis * axis, speed,
			_capability, roll)


## Every visit's state, one line.
func describe() -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in _entries:
		parts.append((entry["visit"] as DockVisit).describe())
	return ", ".join(parts) if not parts.is_empty() else "nothing docking"


# --- each tick ---------------------------------------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_notice_left_s = maxf(_notice_left_s - delta, 0.0)
	var s: Station = station()
	_wire(s)
	if s == null:
		for entry: Dictionary in _entries.duplicate():
			_end(entry, "the station is gone")
		return
	for entry: Dictionary in _entries.duplicate():
		var visit: DockVisit = entry["visit"]
		visit.advance(delta)
		if visit.is_player:
			_step_player_visit(entry, s, delta)
		else:
			_step_wingman(entry, s, delta)
	_watch_wing()
	_watch_offer()
	_keep_wing_clear(s)


# The bay's `dock` interaction runs the player's docking (it answered "not available" before M8-T06).
func _wire(s: Station) -> void:
	if s == _wired:
		return
	_wired = s
	plan = null
	keep_out = null
	if s == null or s.docking_bay == null or s.docking_bay.targetable == null:
		return
	var interaction: TargetInteraction = s.docking_bay.targetable.interaction
	if interaction != null:
		interaction.action = func() -> String: return start_player(DockVisit.WHY_HOLD)
		interaction.offered = func() -> bool: return _player_entry().is_empty() and home_dock(main.combatant) == s.docking_bay


func _step_player_visit(entry: Dictionary, s: Station, delta: float) -> void:
	var visit: DockVisit = entry["visit"]
	if not main.player_alive:
		_end(entry, "the player's ship is lost")
		return
	var ship: Ship = main.ship
	var local: Vector3 = s.global_transform.affine_inverse() * ship.global_position
	match visit.state:
		DockVisit.State.APPROACH:
			if visit.state_s > timeout_s:
				visit.skipped = true
				_dock_now(entry)
			elif _in_corridor(ship, s, local) and not _bay_taken(entry):
				visit.enter(DockVisit.State.LANE)
				shots.to_stage(&"lane", _play_shot)
		DockVisit.State.LANE:
			_fly_in(entry, s, local)
			var along: float = (local - plan.mouth).dot(_axis())
			_watch_roll(entry, s, along, delta)
			if visit.state == DockVisit.State.LANE and along < 0.0 \
					and DockAutopilot.off_axis_m(local, plan.mouth, _axis()) > 2.0 * corridor_m:
				_let_doors_go(entry, s)
				visit.enter(DockVisit.State.APPROACH)  # pushed off the lane: line up again
			elif visit.state_s > timeout_s:
				visit.skipped = true
				_dock_now(entry)
		DockVisit.State.INSIDE:
			_fly_in(entry, s, local)
		DockVisit.State.REPAIR, DockVisit.State.RELAUNCH:
			_keep_away(entry, s, delta)
			if not entry.is_empty() and visit.is_away() and visit.state != DockVisit.State.LAUNCHING:
				if not shots.is_running():
					shots.begin(&"wait", _play_shot)  # a skip stopped the shots: the bay stays on screen until the launch's own
				else:
					shots.to_stage(&"wait", _play_shot)
		DockVisit.State.LAUNCHING:
			if shots.is_running():
				shots.stop()  # the launch's own shots take the camera
			if main.launches == null or main.launches.player_launch().is_empty():
				_finish(entry)
	if not entry.is_empty():
		shots.tick(delta, _play_shot)
		_light_player()


# The player's ship near the mouth: it holds and turns with the drum (a stage of its own, with its shots), then goes on in once it
# has turned with it for `ROLL_HOLD_S` and held at the hold point `ROLL_SHOW_S` (M8-T31, maintainer 2026-11-19).
func _watch_roll(entry: Dictionary, s: Station, along: float, delta: float) -> void:
	if bool(entry.get("rolled", false)) or along < -ROLL_GATE_M - 80.0:
		return
	shots.to_stage(&"roll", _play_shot)
	var ship: Ship = main.ship
	var turning: bool = DockAutopilot.rolls_with(ship.angular_velocity, ship.global_basis, _spin_world(s), _square_ups(s))
	entry["roll_s"] = float(entry.get("roll_s", 0.0)) + delta if turning else 0.0
	if along >= -ROLL_GATE_M - ROLL_AT_GATE_M:
		entry["at_gate_s"] = float(entry.get("at_gate_s", 0.0)) + delta
	if float(entry["roll_s"]) >= ROLL_HOLD_S and float(entry.get("at_gate_s", 0.0)) >= ROLL_SHOW_S:
		entry["rolled"] = true
		roll_matched_at_m = -along
		shots.to_stage(&"entry", _play_shot)


# The drum's turn, World, rad/s (zero while it is held still).
func _spin_world(s: Station) -> Vector3:
	return s.global_basis * plan.spin if s.spinning else Vector3.ZERO


# The bay's four square ups, World: the drum's sides about its axis, turning with it.
func _square_ups(s: Station) -> Array[Vector3]:
	var b: Basis = s.drum_body.global_basis.orthonormalized() if s.drum_body != null else s.global_basis
	return [b.y, b.x, -b.y, -b.x] as Array[Vector3]


# A fighter on the lane: sheltered once in the void, the inner doors asked ahead of it and let go behind it, docked when they
# have shut.
func _fly_in(entry: Dictionary, s: Station, local: Vector3) -> void:
	var visit: DockVisit = entry["visit"]
	var c: Combatant = entry["combatant"]
	var lock: StationAirlock = s.airlock
	if lock == null:
		if local.distance_to(plan.airlock) < 25.0:
			_dock_now(entry)
		return
	c.ship.inside_station = lock.holds(local)
	var depth: float = lock.depth_of(local)
	var reach: Vector2 = entry["reach"]
	if visit.state == DockVisit.State.LANE:
		if depth + reach.x > -lock.ask_ahead_m:
			lock.doors.ask(entry["key"])
		if depth - reach.y > lock.clear_m:
			lock.doors.release(entry["key"])
			visit.enter(DockVisit.State.INSIDE)
	elif lock.doors.is_shut() or visit.state_s > DOORS_WAIT_S:
		_dock_now(entry)


# The ship leaves play behind the inner doors and its repair clock starts.
func _dock_now(entry: Dictionary) -> void:
	var visit: DockVisit = entry["visit"]
	var c: Combatant = entry["combatant"]
	var s: Station = station()
	_let_doors_go(entry, s)
	var hull: float = c.damageable.hull.fraction() if c.damageable != null else 1.0
	_take_out(entry)
	visit.begin_repair(repair.time_s(visit.is_player), hull)
	if visit.is_player and visit.repair_s > 0.0:
		shots.to_stage(&"wait", _play_shot)  # inside: the bay until the launch (none when the repair is at once)
	docked_count += 1
	if not visit.is_player and visit.why == DockVisit.WHY_RECALL:
		wingman_docked.emit(visit.ship_name)
		_stow(entry)
		return
	if visit.is_player:
		player_docked.emit()
	else:
		var wing: Wing = _wing_of(c)
		if wing != null:
			wing.set_away(c, true)
		c.driver.in_passage = true  # nobody flies it while it is inside
		wingman_docked.emit(visit.ship_name)
	_hold(c.ship, s)
	if visit.repair_s <= 0.0 and s != null:
		_keep_away(entry, s, 0.0)  # no wait (the player): repaired on the way through, straight to a Cobra bay


# A recalled fighter is home for good: it leaves its wing and goes back to its pool, whole.
func _stow(entry: Dictionary) -> void:
	var c: Combatant = entry["combatant"]
	(entry["visit"] as DockVisit).enter(DockVisit.State.DONE)
	_bring_back(entry)
	_drop(entry)
	stowed_count += 1
	if is_instance_valid(c):
		main.ships.release(c)


# Hidden, touching nothing, unavailable to everyone outside: the state of a ship inside the station.
func _take_out(entry: Dictionary) -> void:
	var ship: Ship = (entry["combatant"] as Combatant).ship
	if not (entry["kept"] as Dictionary).is_empty():
		return
	entry["kept"] = {"layer": ship.collision_layer, "mask": ship.collision_mask}
	ship.collision_layer = 0
	ship.collision_mask = 0
	ship.custom_integrator = true
	ship.clamped = true
	ship.visible = false
	ship.inside_station = true
	ship.set_flight_command(FlightCommand.new())
	ship.set_combat_command(CombatCommand.new())


# Back in play as it was before `_take_out`.
func _bring_back(entry: Dictionary) -> void:
	var c: Combatant = entry["combatant"]
	var kept: Dictionary = entry["kept"]
	if kept.is_empty() or not is_instance_valid(c.ship):
		return
	c.ship.collision_layer = int(kept["layer"])
	c.ship.collision_mask = int(kept["mask"])
	c.ship.custom_integrator = false
	c.ship.clamped = false
	c.ship.visible = true
	c.ship.inside_station = false
	entry["kept"] = {}


# Where a docked ship waits: in the void behind the doors, at rest against the station.
func _hold(ship: Ship, s: Station) -> void:
	if s == null or plan == null:
		return
	ship.global_transform = Transform3D(s.global_basis.orthonormalized(), s.global_transform * plan.airlock)
	ship.linear_velocity = main.world.anchored_velocity()
	ship.angular_velocity = Vector3.ZERO


# A ship inside the station: held in the void while its repair runs, then sent to a Cobra bay.
func _keep_away(entry: Dictionary, s: Station, delta: float) -> void:
	var visit: DockVisit = entry["visit"]
	var c: Combatant = entry["combatant"]
	_hold(c.ship, s)
	if visit.state == DockVisit.State.REPAIR:
		if not visit.repair_tick(delta):
			return
		_restore(c)
		visit.enter(DockVisit.State.RELAUNCH)
		entry["retry_in_s"] = 0.0
		if visit.is_player:
			player_repaired.emit()
	entry["retry_in_s"] = float(entry["retry_in_s"]) - delta
	if float(entry["retry_in_s"]) > 0.0:
		return
	entry["retry_in_s"] = retry_s
	if _relaunch(entry):
		visit.enter(DockVisit.State.LAUNCHING)
	elif visit.state_s > give_up_s:
		_put_outside(entry, s)


# The repair: a whole hull, charged guns and a full tank.
func _restore(c: Combatant) -> void:
	if c.damageable != null:
		c.damageable.restore()
	if c.cannon != null:
		c.cannon.reset_gate()
	c.ship.get_fuel_tank().refuel()
	if c.thrusters != null:
		c.thrusters.reset()


# Hands the ship to a Cobra bay's launch: the arm the data names, or the next one that is not launching. False when none
# takes it now.
func _relaunch(entry: Dictionary) -> bool:
	var launches: LaunchDirector = main.launches
	if launches == null or launches.station() == null:
		return false
	var c: Combatant = entry["combatant"]
	var visit: DockVisit = entry["visit"]
	var arms := PackedStringArray([relaunch_wing])
	for wing: String in LaunchDirector.WINGS:
		if not arms.has(wing):
			arms.append(wing)
	for wing: String in arms:
		if launches.is_launching(wing):
			continue
		_bring_back(entry)
		if not visit.is_player:
			c.driver.in_passage = false
		var why: String = launches.launch_player(wing, relaunch_door, false, true) if visit.is_player \
				else launches.launch_ships(wing, relaunch_door, [c] as Array[Combatant])
		if why.is_empty():
			return true
		# The launch refused it: inside again until the next try.
		_take_out(entry)
		if not visit.is_player:
			c.driver.in_passage = true
	return false


# No Cobra bay took the ship in time: it is let out off the bow instead, at rest, so nobody stays inside for good.
func _put_outside(entry: Dictionary, s: Station) -> void:
	var c: Combatant = entry["combatant"]
	_bring_back(entry)
	var far: Vector3 = plan.dock_in[0]["at"]
	var out: Vector3 = -_axis()
	c.ship.global_transform = Transform3D(Basis.looking_at(s.global_basis * out, s.global_basis.y), s.global_transform * far)
	c.ship.linear_velocity = main.world.anchored_velocity()
	c.ship.angular_velocity = Vector3.ZERO
	c.ship.reset_physics_interpolation()
	push_warning("DockingDirector: no Cobra bay took %s; released off the bow" % c.display_name)
	_finish(entry)


# The visit is over with the ship flying again: the player has the controls, a wingman its own pilot and its slot.
func _finish(entry: Dictionary) -> void:
	var visit: DockVisit = entry["visit"]
	visit.enter(DockVisit.State.DONE)
	relaunched_count += 1
	_drop(entry)
	if visit.is_player:
		player_relaunched.emit()
	else:
		wingman_rejoined.emit(visit.ship_name)


# Calls a visit off: the doors are let go, a ship inside is brought back where it stands, and everyone gets their ship back.
func _end(entry: Dictionary, reason: String) -> void:
	var visit: DockVisit = entry["visit"]
	visit.cancel(reason)
	_let_doors_go(entry, station())
	var c: Combatant = entry["combatant"]
	if is_instance_valid(c) and is_instance_valid(c.ship):
		_bring_back(entry)
		if not visit.is_player or main.player_alive:
			c.ship.inside_station = false
	_drop(entry)


# Takes the entry off the list and gives the ship back to whoever flew it.
func _drop(entry: Dictionary) -> void:
	var visit: DockVisit = entry["visit"]
	var c: Combatant = entry["combatant"]
	_entries.erase(entry)
	last_visit = visit
	if visit.is_player:
		if main.player_alive and is_instance_valid(main.ship):
			main.ship.assist_on = bool(entry.get("assist", true))
		stop_shots()
		_key_light.detach()
		main.adapter.resync_edges(main.input_source)
		_call_wing_back()
		return
	if not is_instance_valid(c) or not is_instance_valid(c.ship):
		return
	var wing: Wing = _wing_of(c)
	if wing != null:
		wing.set_away(c, false)
		wing.set_docking(c, false)
	if c.driver != null and c.driver.brain == entry["docker"]:
		c.driver.brain = entry["brain"]  # its own pilot again: the wing briefs it at the next refresh
		c.ship.tier_exempt = bool(entry.get("exempt", false))


func _step_wingman(entry: Dictionary, s: Station, delta: float) -> void:
	var visit: DockVisit = entry["visit"]
	var c: Combatant = entry["combatant"]
	var ours: bool = is_instance_valid(c) and is_instance_valid(c.ship) and c.driver != null and c.driver.brain == entry["docker"]
	if not ours or (not visit.is_away() and not WingDirector.is_in_play(c)):
		_end(entry, "the ship is lost")
		return
	if visit.state == DockVisit.State.REPAIR or visit.state == DockVisit.State.RELAUNCH:
		_keep_away(entry, s, delta)
		return
	if visit.state == DockVisit.State.LAUNCHING:
		if not c.ship.clamped:
			_finish(entry)
		return
	if visit.total_s > 2.0 * timeout_s:
		visit.skipped = true
		_dock_now(entry)
		return
	var path := (entry["docker"] as AiPilot).behaviour(&"follow_path") as BehaviourFollowPath
	var done: bool = path != null and path.phase == BehaviourFollowPath.Phase.DONE
	var local: Vector3 = s.global_transform.affine_inverse() * c.ship.global_position
	match entry["stage"]:
		&"peel":
			if done:
				BehaviourFollowPath.attach(entry["docker"] as AiPilot, _transit_route(entry))
				entry["stage"] = &"transit"
		&"transit":
			if done:
				# Slowing into its waiting point on the lane's line, as the civilians do before they take the lane.
				var wait := Route.new()
				wait.name = "DOCK ENTRY"
				wait.pace = Route.PACE_NONE
				wait.lane = true
				wait.cruise_mps = wingman_cruise_mps
				wait.add_lane(main.world.to_universe(s.global_transform * _entry_point(int(entry["queue"]))), 1.0)
				BehaviourFollowPath.attach(entry["docker"] as AiPilot, wait)
				entry["stage"] = &"entry"
		&"entry":
			if done and not _bay_taken(entry) and not _player_goes_first():
				BehaviourFollowPath.attach(entry["docker"] as AiPilot, DockingPlan.route_of(plan.dock_in, s.global_transform,
						main.world, DockingPlan.DOCK_CRUISE_MPS, "DOCKING"))
				entry["stage"] = &"lane"
				visit.enter(DockVisit.State.LANE)
		&"lane":
			if not bool(entry.get("inner", false)) and path != null and path.index > DockingPlan.DOCK_INNER_FROM:
				entry["inner"] = true
				BehaviourFollowPath.attach(entry["docker"] as AiPilot, DockingPlan.route_of(
						plan.dock_in.slice(DockingPlan.DOCK_INNER_FROM + 1), s.global_transform, main.world,
						DockingPlan.DOCK_INNER_MPS, "DOCKING"))
			_fly_in(entry, s, local)
			if s.airlock == null and done and visit.state == DockVisit.State.LANE:
				_dock_now(entry)


# --- the player's wing while the player docks (maintainer, 2026-11-20) --------------------------------------------------


# The player's wing when the player leads it, or null.
func _own_wing() -> Wing:
	var wing: Wing = main.wings.player_wing() if main != null and main.wings != null else null
	return wing if wing != null and wing.leader == main.combatant else null


# The autopilot has the player's ship: its wingmen break off. They stop following it toward the bay and fly on their last
# order (`Wing.away_order`) until it is launched again.
func _break_wing_off() -> void:
	var wing: Wing = _own_wing()
	if wing == null:
		return
	wing.leader_away = true
	main.wings.refresh(wing)
	_keep_wing_clear(station())


# While the player docks, each wingman that is not docking itself has a stand-off beside the bow to go to: under a hold-fire
# order it holds there; under any other it fights what comes (the route stands aside for an attack) and waits there otherwise.
func _keep_wing_clear(s: Station) -> void:
	var wing: Wing = _own_wing()
	if s == null or plan == null or wing == null or not wing.leader_away or _player_entry().is_empty():
		return
	for member: Combatant in wing.members():
		var pilot: AiPilot = member.driver.brain as AiPilot if member.driver != null else null
		if pilot == null or not wing.dock_status(member).is_empty():
			continue  # docking itself: it keeps doing that
		var key: int = member.get_instance_id()
		if _stand_offs.has(key) and pilot.context.route == _stand_offs[key]:
			continue
		var route := Route.new()
		route.name = STAND_OFF_ROUTE
		route.pace = Route.PACE_NONE
		route.cruise_mps = stand_cruise_mps
		route.yield_to_attack = not wing.holds_fire()
		route.add(main.world.to_universe(s.global_transform * _stand_off_point(s, member, wing.slot_of(member))), &"", 1.0e9)
		BehaviourFollowPath.attach(pilot, route)
		_stand_offs[key] = route


# A wingman's stand-off in the station's frame: on its own side of the docking lane, below it and off the mouth.
func _stand_off_point(s: Station, member: Combatant, slot: int) -> Vector3:
	var axis: Vector3 = _axis()
	var side: Vector3 = axis.cross(Vector3.UP).normalized()
	var local: Vector3 = s.global_transform.affine_inverse() * member.ship.global_position
	var offset: float = (local - plan.mouth).dot(side)
	if absf(offset) < 1.0:
		offset = 1.0 if slot % 2 == 0 else -1.0  # on the lane's line: the slots part to both sides
	return plan.mouth - axis * stand_out_m + side * signf(offset) * (stand_side_m + stand_spacing_m * float(maxi(slot - 1, 0))) \
			+ _below() * stand_below_m


# The player is launched again, or its docking was called off: the wingmen leave their stand-offs and rejoin it under the
# wing's order, as before.
func _call_wing_back() -> void:
	var wing: Wing = _own_wing()
	if wing != null:
		wing.leader_away = false
	for member: Combatant in (wing.members() if wing != null else ([] as Array[Combatant])):
		var pilot: AiPilot = member.driver.brain as AiPilot if member.driver != null else null
		var key: int = member.get_instance_id()
		if pilot != null and _stand_offs.has(key) and pilot.context.route == _stand_offs[key]:
			pilot.context.route = null
	_stand_offs.clear()
	if wing != null:
		main.wings.refresh(wing)


# A wingman of the player's wing below the hull threshold docks by itself and says so.
func _watch_wing() -> void:
	if not wingman_auto or main.wings == null or plan == null and not _ready_plan().is_empty():
		return
	# The player's wingmen and every AI flight alike (maintainer, 2026-11-18): whoever has its home dock in range.
	var own: Wing = main.wings.player_wing()
	for wing: Wing in main.wings.wings.duplicate():
		var ships: Array[Combatant] = wing.members()
		if wing.leader != null and not wing.leader.is_player:
			ships.append(wing.leader)
		for member: Combatant in ships:
			if not is_instance_valid(member.ship) or member.damageable == null or not member.damageable.is_active() \
					or member.damageable.hull.fraction() >= wingman_hull_below:
				continue
			if visit_of(member.display_name) != null or not dock_refusal(member).is_empty():
				continue  # no home dock in range: it stays and fights
			if start_wingman(member, DockVisit.WHY_HULL).is_empty() and wing == own and own.leader != null and own.leader.is_player:
				_say("%s: HULL CRITICAL, DOCKING FOR REPAIRS" % member.display_name)


# Control offers the bay once to a player whose hull has fallen below the offer's threshold (D79 beat 13).
func _watch_offer() -> void:
	if main == null or not main.player_alive or main.combatant == null or not _ready_plan().is_empty():
		return  # no bay to offer (a station with no power takes nobody in)
	var hull: float = main.combatant.damageable.hull.fraction()
	if hull >= offer_hull_below:
		_offer_armed = true
		return
	if not _offer_armed or not _player_entry().is_empty() or not dock_refusal(main.combatant).is_empty():
		return
	_offer_armed = false
	dock_offered.emit()
	if offer_line and not offer_text.is_empty():
		_say(offer_text)


# --- helpers -----------------------------------------------------------------------------------------------------------


func _new_entry(visit: DockVisit, c: Combatant) -> Dictionary:
	return {"visit": visit, "combatant": c, "kept": {}, "reach": StationAirlock.hull_reach(c.ship),
			"key": c.ship.get_instance_id(), "retry_in_s": 0.0}


func _player_entry() -> Dictionary:
	for entry: Dictionary in _entries:
		if (entry["visit"] as DockVisit).is_player:
			return entry
	return {}


func _entry_named(ship_name: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if (entry["visit"] as DockVisit).ship_name.to_lower() == ship_name.to_lower():
			return entry
	return {}


# The lane's plan and the way round the station, made on first use; "" or why there is none.
func _ready_plan() -> String:
	var s: Station = station()
	if s == null:
		return "no station in this scenario"
	if not s.has_power():
		return "%s has no power" % Station.DISPLAY_NAME  # a hulk or a wreck takes nobody in (M10-T65)
	if plan == null or not plan.valid:
		plan = DockingPlan.build(s.hardpoints, s.drum_origin)
		keep_out = null
	if not plan.valid:
		return plan.error
	if keep_out == null:
		keep_out = DockKeepOut.build(_boxes, plan.mouth - _axis() * join_out_m, clear_m, via_m)
	return ""


## The lane's direction into the bay, World (M8-T18: the approach cue judges a bay's approach by it); zero with no lane.
func lane_axis() -> Vector3:
	if not _ready_plan().is_empty():
		return Vector3.ZERO
	return (station().global_basis * _axis()).normalized()


# The lane's direction into the bay, in the station's frame.
func _axis() -> Vector3:
	return (plan.mouth - (plan.dock_in[0]["at"] as Vector3)).normalized()


# Near the lane's line outside the mouth and slow enough to be taken along it.
func _in_corridor(ship: Ship, s: Station, local: Vector3) -> bool:
	var axis: Vector3 = _axis()
	var along: float = (local - plan.mouth).dot(axis)
	if along > -30.0 or along < -(join_out_m + 300.0) or DockAutopilot.off_axis_m(local, plan.mouth, axis) > corridor_m:
		return false
	var velocity: Vector3 = s.global_basis.inverse() * (ship.linear_velocity - main.world.anchored_velocity())
	var across: Vector3 = velocity - axis * velocity.dot(axis)
	return velocity.length() <= join_max_mps and across.length() <= 0.3 * join_max_mps


# The player is on its way in: a wingman still at its waiting point lets it take the lane first.
func _player_goes_first() -> bool:
	var entry: Dictionary = _player_entry()
	if entry.is_empty():
		return false
	var visit: DockVisit = entry["visit"]
	return visit.state == DockVisit.State.APPROACH or visit.state == DockVisit.State.LANE or visit.state == DockVisit.State.INSIDE


# Whether someone else has the tunnel: a civilian too far in to be asked aside or one coming out, or another fighter.
func _bay_taken(entry: Dictionary) -> bool:
	if main.traffic != null and main.traffic.bay_busy():
		return true
	for other: Dictionary in _entries:
		if is_same(other, entry):
			continue
		var state: DockVisit.State = (other["visit"] as DockVisit).state
		if state == DockVisit.State.LANE or state == DockVisit.State.INSIDE:
			return true
	return false


func _let_doors_go(entry: Dictionary, s: Station) -> void:
	if s != null and s.airlock != null:
		s.airlock.doors.release(entry["key"])


func _wing_of(c: Combatant) -> Wing:
	if main.wings == null:
		return null
	for wing: Wing in main.wings.wings:
		if wing.slot_of(c) > 0:
			return wing
	return null


# The wing `c` leads, or null.
func _wing_led_by(c: Combatant) -> Wing:
	if main.wings == null:
		return null
	for wing: Wing in main.wings.wings:
		if wing.leader == c:
			return wing
	return null


# Wingmen still on their way to the lane: each waits at its own point.
func _waiting_wingmen() -> int:
	var n: int = 0
	for entry: Dictionary in _entries:
		var visit: DockVisit = entry["visit"]
		n += 1 if not visit.is_player and visit.state == DockVisit.State.APPROACH else 0
	return n


# A wingman's waiting point off the bow on the lane's line, in the station's frame: one farther out per fighter waiting.
func _entry_point(queue: int) -> Vector3:
	# Below the lane's line: a ship coming out of the bay flies that line on past the lane's first point.
	return (plan.dock_in[0]["at"] as Vector3) - _axis() * (entry_out_m + queue_spacing_m * float(queue)) + _below() * wait_off_m


# Away from the spine, square to the lane, in the station's frame: where a fighter waits beside the lane.
func _below() -> Vector3:
	var axis: Vector3 = _axis()
	return (Vector3.DOWN - axis * Vector3.DOWN.dot(axis)).normalized()


# The way to the waiting point, flown with the brains' avoidance on (the station is in the way from most places).
func _transit_route(entry: Dictionary) -> Route:
	var route := Route.new()
	route.name = "TO THE DOCKING BAY"
	route.pace = Route.PACE_NONE
	route.cruise_mps = wingman_cruise_mps
	route.add(main.world.to_universe(station().global_transform * _entry_point(int(entry["queue"]))))
	return route


# The first leg of a wingman that leaves a formation at speed: on along its course and out to the side away from its leader,
# at the speed it has. Null for a slow ship, which turns for the bay where it is.
func _peel_route(member: Combatant) -> Route:
	var velocity: Vector3 = member.ship.linear_velocity - main.world.anchored_velocity()
	var speed: float = velocity.length()
	if speed <= peel_above_mps:
		return null
	var along: Vector3 = velocity / speed
	var wing: Wing = _wing_of(member)
	var out: Vector3 = member.ship.global_basis.y
	if wing != null and wing.leader != null and is_instance_valid(wing.leader.ship):
		var from_leader: Vector3 = member.ship.global_position - wing.leader.ship.global_position
		var side: Vector3 = from_leader - along * from_leader.dot(along)
		if side.length() > 1.0:
			out = side.normalized()
	out = (out - along * out.dot(along)).normalized()
	var route := Route.new()
	route.name = "LEAVING THE FORMATION"
	route.pace = Route.PACE_NONE
	route.cruise_mps = maxf(speed, wingman_cruise_mps)
	route.add(main.world.to_universe(member.ship.global_position + along * speed * peel_ahead_s + out * peel_out_m))
	return route


func _say(line: String) -> void:
	last_notice = line
	_notice_left_s = NOTICE_S
	noticed.emit(line)


func _answer(ok: bool, line: String) -> Dictionary:
	_say(line)
	return {"ok": ok, "line": line}


# --- the camera --------------------------------------------------------------------------------------------------------


## Ends the player's docking shots now, the ones still to come included: the one call an abort makes (M8-T32).
func stop_shots() -> void:
	shots.stop(func() -> void:
		if _my_shot != null and main.camera_rig.playing_shot() == _my_shot:
			main.camera_rig.stop_shot()
			main.camera_rig.snap_chase()
		_my_shot = null)


func _play_shot(shot: CinematicShot) -> void:
	if main == null or main.camera_rig == null:
		return
	_my_shot = shot
	main.camera_rig.play_shot(shot, _actor_pose, _origin_to_local)


# The shared key light on the player's ship while its docking shots play and it is in sight (M8-T29's `CinematicKeyLight`).
func _light_player() -> void:
	var lit: bool = shots.is_running() and main.ship != null and main.ship.visible and main.camera_rig.is_playing_shot()
	if not lit:
		_key_light.detach()
		return
	var to_sun: Vector3 = main.space_environment.key_star.global_basis.z if main.space_environment != null else Vector3.ZERO
	_key_light.attach(main.ship, to_sun)


# Whether a docking take keeps its camera off the station's hull and in sight of the ship over its length, the ship flying on
# as it flies now.
func _take_clear(stage: StringName, id: String) -> bool:
	var made: Dictionary = CinematicShot.from_dict(&"check", {"keys": shots.pool.keys(stage, id)})
	if not bool(made["ok"]) or main == null or main.ship == null:
		return false
	var shot: CinematicShot = made["shot"]
	var ship: Ship = main.ship
	# A take framed on the bay waits until the Fury is near enough to be in it (`near_m`).
	var bay: Variant = _actor_pose("bay")
	var near: float = shots.pool.number(stage, id, "near_m", INF)
	if bay != null and ship.global_position.distance_to((bay as Transform3D).origin) > near:
		return false
	var space: PhysicsDirectSpaceState3D = main.world.get_world_3d().direct_space_state
	var velocity: Vector3 = ship.linear_velocity - main.world.anchored_velocity()
	var blocked: int = 0
	var looked: int = 0
	var t: float = 0.0
	while t <= shots.pool.max_s(stage, id):
		var at: Transform3D = Transform3D(ship.global_basis, ship.global_position + velocity * t)
		var poses: Callable = func(actor: String) -> Variant: return at if actor == "player" else _actor_pose(actor)
		var camera: Vector3 = shot.pose_at(t, poses, _origin_to_local).transform.origin
		if _solid_near(space, camera, ship):
			return false
		if ship.visible:
			looked += 1
			var ray := PhysicsRayQueryParameters3D.create(camera, at.origin, CollisionLayers.ROCK | CollisionLayers.CAPITAL,
					[ship.get_rid()])
			if not space.intersect_ray(ray).is_empty():
				blocked += 1
		t += 0.5
	return looked == 0 or float(blocked) / float(looked) <= SHOT_MAX_BLOCKED


static func _solid_near(space: PhysicsDirectSpaceState3D, at: Vector3, ship: Ship) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SHOT_CLEAR_M
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = CollisionLayers.ROCK | CollisionLayers.CAPITAL
	query.exclude = [ship.get_rid()]
	return not space.intersect_shape(query, 1).is_empty()


# The shots' actors: `player` (where it was last seen once it is inside), `bay` (the mouth, in the station's frame) and `drum`
# (the mouth turning with the drum, M8-T31).
func _actor_pose(actor: String) -> Variant:
	if actor == "player":
		if main.ship == null:
			return null
		if main.ship.visible or _player_pose == null:
			_player_pose = main.ship.get_global_transform_interpolated()
		return _player_pose
	var s: Station = station()
	if actor == "bay" and s != null and plan != null:
		return s.get_global_transform_interpolated() * Transform3D(Basis.IDENTITY, plan.mouth)
	if actor == "drum" and s != null and plan != null and s.drum_body != null:
		var mouth: Vector3 = s.get_global_transform_interpolated() * plan.mouth
		return Transform3D(s.drum_body.global_basis.orthonormalized(), mouth)
	return null


func _origin_to_local(offset: PackedFloat64Array) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], main.world.origin.system_id))


# --- data --------------------------------------------------------------------------------------------------------------


func _load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	if not (parsed is Dictionary):
		push_warning("DockingDirector: %s is missing or not a JSON object; defaults" % DATA_PATH)
		return
	var d: Dictionary = parsed
	join_out_m = maxf(float(d.get("join_out_m", join_out_m)), 100.0)
	corridor_m = maxf(float(d.get("corridor_m", corridor_m)), 5.0)
	approach_mps = maxf(float(d.get("approach_mps", approach_mps)), 10.0)
	via_mps = clampf(float(d.get("via_mps", via_mps)), 5.0, approach_mps)
	lane_mps = maxf(float(d.get("lane_mps", lane_mps)), 5.0)
	inner_mps = clampf(float(d.get("inner_mps", inner_mps)), 2.0, lane_mps)
	join_max_mps = maxf(float(d.get("join_max_mps", join_max_mps)), lane_mps)
	clear_m = maxf(float(d.get("clear_m", clear_m)), 0.0)
	via_m = maxf(float(d.get("via_m", via_m)), clear_m + 1.0)
	timeout_s = maxf(float(d.get("timeout_s", timeout_s)), 10.0)
	repair = DockRepair.from_dict(d.get("repair"))
	var wingman: Dictionary = d.get("wingman", {})
	wingman_auto = bool(wingman.get("auto", wingman_auto))
	wingman_hull_below = clampf(float(wingman.get("hull_below", wingman_hull_below)), 0.0, 1.0)
	dock_range_m = maxf(float(d.get("dock_range_m", dock_range_m)), 0.0)
	wingman_cruise_mps = maxf(float(wingman.get("cruise_mps", wingman_cruise_mps)), 10.0)
	entry_out_m = maxf(float(wingman.get("entry_out_m", entry_out_m)), 0.0)
	queue_spacing_m = maxf(float(wingman.get("queue_spacing_m", queue_spacing_m)), 50.0)
	peel_above_mps = maxf(float(wingman.get("peel_above_mps", peel_above_mps)), 0.0)
	peel_out_m = maxf(float(wingman.get("peel_out_m", peel_out_m)), 0.0)
	peel_ahead_s = maxf(float(wingman.get("peel_ahead_s", peel_ahead_s)), 0.5)
	var offer: Dictionary = d.get("offer", {})
	offer_hull_below = clampf(float(offer.get("hull_below", offer_hull_below)), 0.0, 1.0)
	offer_text = str(offer.get("line", offer_text))
	var relaunch: Dictionary = d.get("relaunch", {})
	relaunch_wing = str(relaunch.get("wing", relaunch_wing)).to_lower()
	relaunch_door = maxi(int(relaunch.get("door", relaunch_door)), 1)
	retry_s = maxf(float(relaunch.get("retry_s", retry_s)), 0.1)
	give_up_s = maxf(float(relaunch.get("give_up_s", give_up_s)), 1.0)
	var priority: Dictionary = d.get("priority", {})
	claim_within_m = maxf(float(priority.get("claim_within_m", claim_within_m)), 0.0)
	commit_out_m = maxf(float(priority.get("commit_out_m", commit_out_m)), join_out_m)
	yield_off_m = maxf(float(priority.get("yield_off_m", yield_off_m)), 50.0)
	wait_off_m = maxf(float(priority.get("wait_off_m", wait_off_m)), 2.0 * corridor_m)
	var wing_wait: Dictionary = d.get("wing_wait", {})
	stand_side_m = maxf(float(wing_wait.get("side_m", stand_side_m)), 500.0)
	stand_below_m = maxf(float(wing_wait.get("below_m", stand_below_m)), 0.0)
	stand_out_m = maxf(float(wing_wait.get("out_m", stand_out_m)), 0.0)
	stand_spacing_m = maxf(float(wing_wait.get("spacing_m", stand_spacing_m)), 50.0)
	stand_cruise_mps = maxf(float(wing_wait.get("cruise_mps", stand_cruise_mps)), 10.0)
	_boxes = DockKeepOut.boxes_from(d.get("keep_out"))
	if not shots.pool.error.is_empty():
		push_warning("DockingDirector: %s" % shots.pool.error)


# --- console -----------------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"active": {"get": func() -> int: return _entries.size(), "type": TYPE_INT, "doc": "Ships docking, inside or relaunching (M8-T06)"},
		&"player": {"get": func() -> String: return player_visit().state_name() if player_visit() != null else "none",
				"doc": "The player's visit: approach, lane, inside, repair, relaunch, launching, or none"},
		&"visits": {"get": describe, "doc": "Every visit: the ship and its state"},
		&"roll_matched_at_m": {"get": func() -> float: return roll_matched_at_m, "unit": "m",
				"doc": "How far short of the mouth the player's last visit turned with the drum before going in (M8-T31; -1: not yet)"},
		&"shots": {"get": func() -> String: return " ".join(shots.sequence()) if not shots.played.is_empty() else "none",
				"doc": "The player's docking shots in order, stage/id, each under 3 s (a feature under 5 s; M8-T31)"},
		&"repair_left_s": {"get": func() -> float: return player_visit().repair_left_s if player_visit() != null else 0.0,
				"unit": "s", "doc": "Seconds of the player's repair left"},
		&"docked": {"get": func() -> int: return docked_count, "type": TYPE_INT, "doc": "Ships taken into the bay so far"},
		&"relaunched": {"get": func() -> int: return relaunched_count, "type": TYPE_INT, "doc": "Ships launched again after a repair"},
		&"range_km": {"get": func() -> float: return dock_range_m / 1000.0, "unit": "km",
				"doc": "A fighter docks only with its home dock's bay within this range (data/station/docking.json)"},
		&"order": {"get": func() -> String: return "available" if order_available() else "no home dock in range",
				"doc": "Whether the wing's DOCK order can be given: a wingman has its home dock in range"},
		&"homes": {"get": _homes_text, "doc": "The player's and each wingman's home dock, and why it cannot dock now if it cannot"},
		&"hull_threshold": {"get": func() -> float: return wingman_hull_below,
				"doc": "A wingman below this hull share docks by itself (data/station/docking.json)"},
		&"bay": {"get": func() -> String: return "taken" if holds_bay() or (main != null and main.traffic != null \
				and main.traffic.bay_busy()) else "free", "doc": "Whether a ship has the tunnel (a fighter or the station's traffic)"},
		&"last": {"get": func() -> String: return last_visit.describe() + (": " + last_visit.cancel_reason \
				if not last_visit.cancel_reason.is_empty() else "") if last_visit != null else "none",
				"doc": "The latest visit that ended, and why if it was called off"},
		&"notice": {"get": func() -> String: return last_notice, "doc": "The latest docking line on the HUD"},
	}), self)
	var rest := ConsoleArg.string_optional(&"name", "")
	rest.rest = true
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"Docking for repair in the main docking bay (M8-T06): status, player (dock the player from where it is), wing (the wing order: every damaged wingman docks), wing <name> (that wingman), cancel [name] (call off a ship still outside the inner doors; default the player), skip (as the cinematic's skip: to the bay, then to the end of the repair)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"), rest] as Array[ConsoleArg]), _cmd_dock, self)


func _cmd_dock(args: Dictionary) -> ConsoleResult:
	var who: String = str(args[&"name"]).strip_edges()
	match StringName(args[&"action"]):
		&"player":
			var why: String = start_player(DockVisit.WHY_CONSOLE)
			return ConsoleResult.failure("dock: %s" % why) if not why.is_empty() else ConsoleResult.line("docking: the autopilot has the ship")
		&"wing":
			if who.is_empty():
				var result: Dictionary = order_wing()
				return ConsoleResult.line(result["line"]) if bool(result["ok"]) else ConsoleResult.failure(result["line"])
			var member: Combatant = _wingman_named(who)
			var refused: String = start_wingman(member, DockVisit.WHY_CONSOLE) if member != null else "no wingman '%s'" % who
			return ConsoleResult.failure("dock: %s" % refused) if not refused.is_empty() \
					else ConsoleResult.line("%s is docking" % member.display_name)
		&"cancel":
			var stopped: String = cancel(who, "cancelled from the console")
			return ConsoleResult.failure("dock: %s" % stopped) if not stopped.is_empty() else ConsoleResult.line("docking cancelled")
		&"skip":
			if _player_entry().is_empty():
				return ConsoleResult.failure("dock skip: the player is not docking")
			skip()
			return ConsoleResult.line("skipped: %s" % player_visit().describe())
	return ConsoleResult.line(describe())


func _homes_text() -> String:
	var parts := PackedStringArray()
	var ships: Array[Combatant] = [main.combatant] if main != null and main.combatant != null else ([] as Array[Combatant])
	var wing: Wing = main.wings.player_wing() if main != null and main.wings != null else null
	if wing != null:
		ships.append_array(wing.members())
	for c: Combatant in ships:
		var why: String = dock_refusal(c)
		parts.append("%s %s%s" % [c.display_name, c.home if c.home != &"" else &"none", "" if why.is_empty() else " (%s)" % why])
	return ", ".join(parts)


func _wingman_named(ship_name: String) -> Combatant:
	if main == null or main.wings == null:
		return null
	for wing: Wing in main.wings.wings:
		for member: Combatant in wing.members():
			if member.display_name.to_lower() == ship_name.to_lower():
				return member
	return null
