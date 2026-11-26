class_name MissionApi
extends RefCounted
## Everything a mission script sees (architecture §18 D51), and the mission's bookkeeping behind it: the objectives, the
## result rules and the per-tick evaluation. Pure apart from the optional `MissionStage`, which carries world changes into the
## game; without one (tests) they land in the `MissionWorld` snapshot only.
##
## Script surface (`m` in `step_<name>(m)`):
##     await m.say(line_id [, interrupt]) a comms line (D53): shown by the comms panel; resolves when it has finished showing
##     await m.wait(seconds)           sim time, from physics ticks only
##     await m.until(trigger)          a `Trigger` (TriggerSpec builders) or its JSON dictionary
##     await m.until_objective(id)     until the objective is done or failed
##     await m.player_did(action)      an `input_performed` trigger (`PlayerActions.NAMES`), for M8's tutorial
##     await m.cinematic(shot_id)      a camera shot from the scenario's `cinematics` (D55): until it ends or the player skips it
##     await m.check(check_id)         one control check (M8 D80): the instructor's hint, repeated and then demonstrated while the
##                                     player misses it; it never fails
##     await m.run_checks([ids])       several, one after the other
##     m.spawn(spawn)                  a ship from a pool, by the scenario's spawn rules; `arrival: "jump"` with `via: "carrier"`
##                                     brings it out of a carrier's jump point (M6-T23: only a jump-capable ship opens its own),
##                                     `arrival: "gate"` (or `via: "gate"`) out of the jumpgate's blue vortex (M6-T14; null now, in
##                                     play by its name once through)
##     m.depart(ship)                  an AI ship flies out through the jumpgate's orange vortex and leaves play (M6-T14)
##     m.send(ship, target)            the ship's pilot objective (D39)
##     m.fly_route(ship, route)        on along another of the scenario's routes (M8-T26)
##     m.hold_route_end(ship)          it goes back to its route's end whenever it is taken away after flying it (M8-T08)
##     m.transient(names)              ships that only matter while the step plays: a skipped step releases them (M5-T30)
##     m.objective_add(id [, text, primary]) / m.objective_complete(id) / m.objective_fail(id)
##     m.waypoint(name or null)        the HUD's waypoint marker on an actor
##     m.show_hull(name)               the HUD shows that ship's name and hull as a bar while the mission runs (M7-T54)
##     m.lock_controls(on)             the player's flight and combat commands held at zero; the ship flies on (D55)
##     await m.launch_from(wing, door) the player launches from a Cobra bay (M7-T08, D76: "alpha" and 1 to 6), its wingmen from the
##                                     arm's other doors in the wave order; resolves at the player's hand-off
##     m.end(success [, reason])
##     m.time_s(), m.alive(name), m.objective_state(id)
##     m.filled(text)                  `text` with the scenario's placeholders filled in ("{civilian}" -> the drawn ship's name)
## Station missions (M8 D79):
##     await m.launch_squadron(wing, door, flights)   the squadron-launch cinematic, then the player's own launch (M8-T03)
##     await m.tour(stop [, captions]) one stop of the station tour on the cinematic camera (M7-T12); `captions` false
##                                     leaves its caption out when the mission talks over it
##     m.put(ship, at, facing)         a ship at a place (Vector3 from the origin), at rest: a cut between scenes
##     m.dismiss(names)                ships taken out of play with no explosion (recalled drones)
##     m.player_target()               the name of the player's selected target ("" none); wait on one with
##                                     `TriggerSpec.targeted(actor)`
##     m.traffic(on)                   the station's run of civilians between the gate and the bays
##     m.scramble(wing, count)         more Starfuries of the station's wing launch from its Cobra arm
##     m.fly(ship, points, cruise_mps [, paced]) / m.demo(ship, name)   an AI ship's route; a `Manoeuvres` move flown where it is
##     m.pilot(ship, profile)          another pilot for an AI ship (`AiProfile.PATHS`); "" gives its own back
##     m.join_flight(ship) / m.leave_flight(ship)     an AI ship into, and out of, the player's flight
##     m.gather(names, at)             in a skipped step, puts those ships at `at` (where flying the step would have left them)
##     m.fact(name)                    a number the game counts (`MissionFacts.NAMES`); wait on one with `TriggerSpec.fact`
##     m.when(trigger, action)         runs `action` once, whenever `trigger` first holds, while the steps go on
##     m.note(key, value) / m.noted(key [, default])   the script's own facts; kept by a checkpoint restart
##     m.checkpoint(step, label)       from now on a lost mission's debrief offers a restart from `step`
##     m.debrief_line(text) / m.award_rank(rank)       a line on the debrief; the rank the mission earns (`Career`)
##     m.needs_station = false         the station may fall: by default losing Babylon 5 ends the mission as lost
##                                     ("station destroyed", M10-T65, Q72: no flag makes it indestructible)
##
## Lines (D53): `dialog_book` holds the mission's dialog file and `dialog` is the queue the comms panel shows; a line is recorded
## in the `MissionWorld` as finished when it ends, shown out or cut (an interrupt, a skip, the mission's end). Without a book
## (a mission with no dialog file) `say` is logged and finished at once; a line the book lacks is an error and also finishes.
## Ending cuts what is showing; a closing line for the result (`closing_lines`, T10) is then said and runs out its hold while the
## runner holds the debrief for it, so a mission lost at a stroke (the buoy, the player) still gets its last word.
##
## Cinematics (D55): the stage plays a shot on the camera rig, which hides the HUD and zeroes the player's commands; `cinematic`
## resolves when the shot ends, when the player skips it (A or Start), and at once in a skipped step. Without a stage a shot lasts
## its length of sim time. A mission that ends during a shot cuts it.
##
## Control checks (M8 D80): `check_book` holds the checks (`data/checks/controls.json`) and `checks` runs them on the sample the
## runner measures each tick (`check_sample`; tests set it). A hint is said as its dialog line when the book has it, without
## holding the check up; a demo is announced on `demo_requested` for whoever flies the instructor. In a skipped step every check
## passes at once. A check none of whose actions is bound is left out with a note, so it cannot hold the mission up.
##
## Skipping (D51): in a skipped step every wait returns at once; `until` first makes its trigger true (`Trigger.make_true`),
## `until_objective` completes the objective through its forced success trigger, and the objectives are evaluated right after,
## so the world ends where the step would have left it. World changes still run. Nothing runs once the mission has ended: a
## step that waits after `end` never resumes. Scripts wait with `until`, never poll: a skipped step that keeps waiting
## (`SKIP_SPIN_LIMIT` returns in one skip) is reported and then waits a tick at a time instead of spinning.
##
## Runner side: `begin`, `tick` (once per physics tick, after the world moved), `skip`, `goto`, `is_skipping`,
## `opening_skippable`, `skip_opening`, `player_destroyed`, `release`.
##
## The opening (M7-T54): a script that names where its opening ends (`MissionScript.opening_until`) lets the player hold X
## through it while the controls are held; the hold skips every step before that one, as `goto` does.

## The mission is over: `result` holds how.
signal ended(result: Dictionary)
## The player missed check `check_id` twice: the instructor should fly `demo` (a `Manoeuvres` name).
signal demo_requested(check_id: StringName, demo: StringName)

## Slack when comparing summed tick times with a wait's end (120 ticks of 1/60 s must reach 2 s).
const TIME_EPS_S: float = 1e-6
## Waits that may return at once in one skip before the step counts as polling (a script that waits in a loop).
const SKIP_SPIN_LIMIT: int = 1000
## Ticks a skipped squadron launch may take to hand the player over.
const SKIP_LAUNCH_TICKS: int = 240

var world: MissionWorld = null
var book: ObjectiveBook = null
## The game side, or null.
var stage: MissionStage = null
var scenario_id: StringName = &""
var title: String = ""
## Every world change the script made, in order (`spawn RAIDER 1 raider_fighter`, `objective raiders done`...). The console
## prints it; tests compare a skipped run's with a played one's.
var journal: PackedStringArray = PackedStringArray()
## `{success, reason, scenario_id, title, objectives, time_s}` once ended; empty before.
var result: Dictionary = {}
## Units of work (`MissionWorld.work`) in the last tick: snapshot refresh, objective triggers and the awaited trigger.
var tick_work: int = 0
## The actor the HUD's waypoint marks ("" for none).
var waypoint_name: String = ""
## Counts the script's `waypoint` calls (M5-T25): the HUD shows the later of the script's waypoint and the pilot's own pick.
var waypoint_serial: int = 0
## `lock_controls` asked for the player's controls to be held: `Main` zeroes their commands while it is set.
var controls_locked: bool = false
## Losing the station fails the mission (M10-T65, Q72); a script whose story lets it fall sets this false.
var needs_station: bool = true
## The scenario's camera shots by id (`load_cinematics`).
var cinematics: Dictionary = {}  # StringName -> CinematicShot
## The mission's dialog file (the runner loads it), or null: `say` then resolves at once.
var dialog_book: DialogBook = null
## The comms lines in play: the comms panel reads and draws it, `tick` moves it on sim time.
var dialog: DialogQueue = DialogQueue.new()
## The line said as the mission ends: by the result's reason ("player destroyed", "objective failed: protect"), else by
## "success" or "failure" (the scenario's `mission.closing_lines`).
var closing_lines: Dictionary = {}  # String -> StringName
## The scenario's placeholders (`ScenarioLoader.resolve_random_civilian`): "{civilian}" -> the drawn civilian's name.
var placeholders: Dictionary = {}  # String -> String
## The ships whose hull the HUD shows as a bar (`show_hull`), in the order the script named them.
var hull_bars: PackedStringArray = PackedStringArray()
## The step the opening ends at (`MissionScript.opening_until`), or &"" for none.
var opening_until: StringName = &""
## The control checks a script may run, or null (the runner loads them), and the runner of the open ones.
var check_book: ControlCheckBook = null
var checks: ControlCheckRunner = ControlCheckRunner.new()
## This tick's measured state for the open check: the runner fills it before `tick` while `checks.is_active()`.
var check_sample: ControlCheckSample = null

## The script's own facts (`note`); a checkpoint restart starts with the ones the checkpoint held.
var notes: Dictionary = {}
## `{step, label, notes}` once the script set one (`checkpoint`); empty before.
var checkpoint_data: Dictionary = {}
## Lines the script adds to the debrief, and the rank the mission earns (&"" for none).
var debrief_lines: PackedStringArray = PackedStringArray()
var rank: StringName = &""
## `{from, to, label}` when the script offers a skip of some of its steps from the pause menu (`MissionScript.skip_block`).
var skip_block: Dictionary = {}

var _seq: MissionSequencer = MissionSequencer.new()
# `when`: {trigger, action}, each dropped once it has run.
var _reactions: Array[Dictionary] = []
# The shot `cinematic` is waiting on, or null.
var _shot: CinematicShot = null
var _live: Array[Trigger] = []
var _started: bool = false


func _init(p_world: MissionWorld = null, p_book: ObjectiveBook = null, p_stage: MissionStage = null) -> void:
	world = p_world if p_world != null else MissionWorld.new()
	book = p_book if p_book != null else ObjectiveBook.new()
	stage = p_stage
	world.stage = stage


# --- awaits ------------------------------------------------------------------------------------------------------------


## Shows the comms line `line_id` (D53) and waits until it has finished showing. With `interrupt` it cuts the line showing and
## takes its place. In a skipped step, or when the book lacks the line, it is logged and not shown.
func say(line_id: StringName, interrupt: bool = false) -> void:
	if has_ended():
		return
	journal.append("say %s" % line_id)
	if _seq.skipping and not _seq.stopped and _spinning():
		await _seq.wake
	var line: DialogBook.Line = dialog_book.line(line_id) if dialog_book != null else null
	if dialog_book != null and line == null:
		push_error("Mission: say: no line '%s' in the dialog (%d lines)" % [line_id, dialog_book.line_count()])
	if line == null or _seq.skipping:
		print("[mission] %ssay %s" % ["(skipped) " if _seq.skipping else "", line_id])
		world.finish_line(line_id)
		return
	var ticket: int = dialog.say(line, interrupt)
	_record_finished_lines()
	while not _seq.stopped and not _seq.skipping and dialog.is_pending(ticket):
		await _seq.wake
	if dialog.cancel(ticket):  # skipped or ended while showing: the line is cut, not shown out
		_record_finished_lines()
	while _seq.stopped:
		await _seq.wake  # ended meanwhile: this step goes no further


## Waits `seconds` of sim time.
func wait(seconds: float) -> void:
	var until_s: float = world.time_s + seconds
	if _seq.skipping and not _seq.stopped and _spinning():
		await _seq.wake
	while not _seq.stopped and not _seq.skipping and world.time_s < until_s - TIME_EPS_S:
		await _seq.wake
	while _seq.stopped:
		await _seq.wake  # ended meanwhile: this step goes no further


## Waits until `condition` holds: a `Trigger`, or its JSON dictionary (`TriggerSpec`). In a skipped step it is made true.
func until(condition: Variant) -> void:
	var trigger: Trigger = _trigger_of(condition)
	if trigger == null:
		return
	trigger.arm(world)
	_live.append(trigger)
	if stage != null:
		stage.refresh(world, trigger.actors())
	while not _seq.stopped and not trigger.check(world):
		if _seq.skipping:
			if _spinning():
				await _seq.wake
				continue
			trigger.make_true(world)
			print("[mission] skip: forced %s" % trigger.describe())
			settle()
			break
		await _seq.wake
	_live.erase(trigger)
	while _seq.stopped:
		await _seq.wake


## Waits until objective `id` is done or failed. In a skipped step its success trigger is made true and it completes.
func until_objective(id: StringName) -> void:
	if not book.has(id):
		push_error("Mission: until_objective: no objective '%s'" % id)
		return
	if book.state_of(id) == ObjectiveBook.HIDDEN:
		push_warning("Mission: until_objective: '%s' is hidden; it waits until it is shown (objective_add) and finished" % id)
	while not _seq.stopped and _open(id):
		if _seq.skipping:
			if _spinning():
				await _seq.wake
				continue
			book.force_success(id, world)
			journal.append("objective %s %s" % [id, book.state_of(id)])
			print("[mission] skip: forced objective %s" % id)
			settle()
			break
		await _seq.wake
	while _seq.stopped:
		await _seq.wake


## Waits until the player performs `action` (a `PlayerActions.NAMES` word).
func player_did(action: StringName) -> void:
	if not PlayerActions.NAMES.has(action):
		push_error("Mission: player_did: unknown action '%s'" % action)
		return
	await until(TriggerSpec.input_performed(action))


## Plays the scenario's shot `shot_id` and waits until it ends or the player skips it. In a skipped step it is logged, not shown.
func cinematic(shot_id: StringName) -> void:
	if has_ended():
		return
	journal.append("cinematic %s" % shot_id)
	var shot: CinematicShot = cinematics.get(shot_id)
	if shot == null:
		push_error("Mission: cinematic: no shot '%s' in the scenario's cinematics" % shot_id)
		return
	if _seq.skipping and not _seq.stopped and _spinning():
		await _seq.wake
	if _seq.skipping:
		print("[mission] (skipped) cinematic %s" % shot_id)
		return
	if stage == null:
		await wait(shot.duration_s)
		return
	_shot = shot
	stage.play_cinematic(shot)
	while not _seq.stopped and not _seq.skipping and stage.cinematic_playing(shot):
		await _seq.wake
	stage.stop_cinematic(shot)  # a skip cuts it
	_shot = null
	while _seq.stopped:
		await _seq.wake


## Runs control check `check_id` and waits until the player has passed it.
func check(check_id: StringName) -> void:
	await run_checks([check_id])


## Runs the control checks `ids` in order and waits until the last has passed. In a skipped step they pass at once.
func run_checks(ids: Array) -> void:
	if has_ended():
		return
	var list: Array[ControlCheck] = []
	for raw: Variant in ids:
		var made: ControlCheck = check_book.make(StringName(str(raw))) if check_book != null else null
		if made == null:
			push_error("Mission: run_checks: no control check '%s'" % raw)
		elif not ControlHintText.is_bound(made):
			journal.append("check %s left out: not bound" % made.id)
			print("[mission] check %s left out: none of its actions is bound" % made.id)
		else:
			list.append(made)
	if _seq.skipping and not _seq.stopped and _spinning():
		await _seq.wake
	checks.start(list)
	while not _seq.stopped and not _seq.skipping and checks.is_active():
		await _seq.wake
	if not _seq.stopped and checks.is_active():  # skipped: the step ends where the player would have left it
		checks.pass_all()
		_serve_checks()
	while _seq.stopped:
		await _seq.wake


# --- world changes -----------------------------------------------------------------------------------------------------


## Takes a ship from its pool: a scenario spawn (`type`, `name`, `anchor`, `offset`, `velocity`, `behaviour`, `wing`) plus
## `arrival` ("none", "jump" or "gate"), `via` ("gate" or "carrier", M6-T23), `carrier` ({"class", "then"}, and for the raiders' strike carrier, M12-T19, `"arrival"`: "docked" on its cradles or "beside" it, `"standoff_m"`, `"retreat_hull"`, `"wait_s"`, `"raid_s"`, `"fighter_return_hull"`, `"recall_left"`, `"flee_mps"` and, M8-T08, `"name"`: what the carrier is called, which makes it an actor a `destroyed` trigger can name; `CarrierTactics.DEFAULTS`) and `invulnerable`. Returns the ship, or null (with an error when the pool is spent); a
## gate arrival returns null with no error, as the ship comes through once the vortex has opened.
func spawn(entry: Dictionary) -> Combatant:
	if has_ended():
		return null
	var parsed: Variant = ScenarioLoader.parse_spawn(entry, "spawn", world.system_id)
	if parsed is String:
		push_error("Mission: %s" % parsed)
		return null
	var spawn_entry: Dictionary = parsed
	var arrival: Variant = entry.get("arrival", "none")
	if not (arrival is String) or not MissionStage.ARRIVALS.has(StringName(arrival as String)):
		push_error("Mission: spawn.arrival must be one of %s, got %s" % [MissionStage.ARRIVALS, JSON.stringify(arrival)])
		return null
	spawn_entry["arrival"] = StringName(arrival as String)
	var via: Variant = entry.get("via", "")
	if not (via is String) or not MissionStage.VIAS.has(StringName(via as String)):
		push_error("Mission: spawn.via must be \"gate\" or \"carrier\", got %s" % JSON.stringify(via))
		return null
	spawn_entry["via"] = StringName(via as String)
	if spawn_entry["via"] == MissionStage.VIA_GATE:
		spawn_entry["arrival"] = &"gate"
	var carrier: Variant = entry.get("carrier", {})
	spawn_entry["carrier"] = carrier if carrier is Dictionary else {}
	var invulnerable: Variant = entry.get("invulnerable", false)
	spawn_entry["invulnerable"] = invulnerable is bool and invulnerable as bool
	var placed: Combatant = null
	var ship_name: String = String(spawn_entry["name"])
	if stage != null and spawn_entry["arrival"] == &"gate":
		ship_name = stage.spawn_through_gate(spawn_entry)
		if ship_name.is_empty():
			return null  # the stage said why
		journal.append("spawn %s %s through the gate" % [ship_name, spawn_entry["type"]])
		return null  # in play once the vortex has opened; known by its name from then on
	if stage != null:
		placed = stage.spawn(spawn_entry)
		if placed == null:
			return null  # the stage said why
		ship_name = placed.display_name
		stage.refresh(world, PackedStringArray([ship_name]))  # seen in play from now, even if lost before the next tick
	else:
		if ship_name.is_empty():
			push_error("Mission: spawn needs a name without a stage")
			return null
		world.set_actor(ship_name, _anchor(spawn_entry).plus_local(spawn_entry["offset"]))
	journal.append("spawn %s %s" % [ship_name, spawn_entry["type"]])
	return placed


## Sends the AI ship `ship_name` out through the scene's jumpgate (M6-T14): the orange vortex opens as it nears and it leaves play
## once through. False when it cannot go.
func depart(ship_name: String) -> bool:
	if has_ended():
		return false
	if stage != null and not stage.depart(ship_name):
		return false
	journal.append("depart %s through the gate" % ship_name)
	return true


## Sends `ship_name`'s pilot at `target_name` (D39's objective: it flies there from any broadcast range and attacks).
func send(ship_name: String, target_name: String) -> bool:
	if has_ended():
		return false
	if stage != null and not stage.send(ship_name, target_name):
		return false
	journal.append("send %s -> %s" % [ship_name, target_name])
	return true


## Ships that only matter while this step plays (a wave, M5-T30): in a skipped step they leave play at once, as a forced
## `destroyed` would release them, so a skip leaves no wave behind (D62). Played, it does nothing.
func transient(names: PackedStringArray) -> void:
	if has_ended() or not _seq.skipping:
		return
	var gone: TriggerDestroyed = TriggerSpec.destroyed(names)
	if stage != null:
		stage.refresh(world, names)
	gone.make_true(world)
	journal.append("transient %s" % ", ".join(names))
	settle()


## Shows objective `id`: a declared one, or a new one when `text` is given.
func objective_add(id: StringName, text: String = "", primary: bool = true) -> bool:
	if has_ended():
		return false
	if not book.has(id) and (text.is_empty() or not book.add(id, text, primary)):
		push_error("Mission: objective_add: no objective '%s' declared (give a text to add one)" % id)
		return false
	if not book.activate(id, world):
		push_error("Mission: objective_add: %s" % book.error)
		return false
	journal.append("objective_add %s" % id)
	_refresh_objective(id)
	return true


func objective_complete(id: StringName) -> bool:
	return _finish_objective(id, true)


func objective_fail(id: StringName) -> bool:
	return _finish_objective(id, false)


## Sends the AI ship `ship_name` on along the scenario's route `route_name` (M8-T26, `MissionStage.fly_route`).
func fly_route(ship_name: String, route_name: String) -> bool:
	if has_ended():
		return false
	if stage != null and not stage.fly_route(ship_name, route_name):
		return false
	journal.append("fly_route %s %s" % [ship_name, route_name])
	return true


## From now on the AI ship `ship_name` goes back to the end of its route whenever it has flown it and something has taken
## it away since (M8-T08, `MissionStage.hold_route_end`).
func hold_route_end(ship_name: String) -> bool:
	if has_ended():
		return false
	if stage != null and not stage.hold_route_end(ship_name):
		return false
	journal.append("hold_route_end %s" % ship_name)
	return true


## Marks an actor with the HUD's waypoint (its name), or clears it (null or "").
func waypoint(target: Variant) -> void:
	if has_ended():
		return
	waypoint_name = "" if target == null else String(target).strip_edges()
	waypoint_serial += 1
	journal.append("waypoint %s" % (waypoint_name if not waypoint_name.is_empty() else "none"))


## Launches the player from wing `wing`'s Cobra bay door `door` (M7-T08, D76) and waits for the hand-off: its door opens, it drops
## from its rack with the launch camera's shots and is let go with the drum's surface velocity; its wingmen take the arm's other
## racks. In a skipped step the player's part jumps to the hand-off (the wingmen go on with theirs) and it returns at once.
func launch_from(wing: String, door: int) -> void:
	if has_ended():
		return
	journal.append("launch_from %s %d" % [wing, door])
	if stage == null:
		return
	var why: String = stage.launch_from(wing, door)
	if not why.is_empty():
		push_error("Mission: launch_from: %s" % why)
		return
	if _seq.skipping:
		stage.skip_launch()
		return
	while not _seq.stopped and not _seq.skipping and stage.launching():
		await _seq.wake
	if _seq.skipping:
		stage.skip_launch()
	while _seq.stopped:
		await _seq.wake


## Plays the squadron-launch cinematic (M8-T03, D81) and waits for the player's hand-off: the squadron's flights launch from
## wing `wing`'s arm (empty: the player's wing, else alpha), flip and form up filmed from outside, then the player launches alone
## from door `door` (0: the data's). In a skipped step it lands in the end state at once and returns.
func launch_squadron(wing: String = "", door: int = 0, flights: int = 0) -> void:
	if has_ended():
		return
	journal.append("launch_squadron %s %d" % [wing, door])
	if stage == null:
		return
	var why: String = stage.launch_squadron(wing, door, flights)
	if not why.is_empty():
		push_error("Mission: launch_squadron: %s" % why)
		return
	while not _seq.stopped and not _seq.skipping and stage.launching():
		await _seq.wake
	await _skip_launch()
	while _seq.stopped:
		await _seq.wake


# A skipped squadron launch is over before its step goes on: a later step may place the player, and a launch still holding the
# ship would take it back to the station (M8-T05: a restart from the raid's checkpoint). It takes the launch's few ticks.
func _skip_launch() -> void:
	var ticks: int = 0
	while _seq.skipping and not _seq.stopped and stage != null and stage.launching() and ticks < SKIP_LAUNCH_TICKS:
		stage.skip_launch()
		ticks += 1
		await _seq.wake


## Plays the station tour's stop `stop` on the cinematic camera (M7-T12; "" for the whole tour) and waits until it ends or the
## player skips it. In a skipped step it is logged, not shown.
func tour(stop: String = "", captions: bool = true) -> void:
	if has_ended():
		return
	journal.append("tour %s" % stop)
	if stage == null or _seq.skipping:
		return
	var why: String = stage.tour(stop, captions)
	if not why.is_empty():
		push_error("Mission: tour: %s" % why)
		return
	while not _seq.stopped and not _seq.skipping and stage.touring():
		await _seq.wake
	stage.stop_tour()
	while _seq.stopped:
		await _seq.wake


## Puts the ship `ship_name` at `at` (metres from the scenario's origin), nose along `facing`, at rest: a cut between scenes,
## made as a cinematic ends or with the controls held. Played or skipped, the ship ends there.
func put(ship_name: String, at: Vector3, facing: Vector3 = Vector3.FORWARD) -> void:
	journal.append("put %s at %s" % [ship_name, at])
	_report("put", stage.put(ship_name, UniversePos.new(at.x, at.y, at.z, world.system_id), facing) if stage != null else "")


## Takes the ships `names` out of play with no explosion and no kill credit (drones recalled when a drill is over). Do it
## where the player is not looking: they vanish.
func dismiss(names: Array) -> void:
	journal.append("dismiss %s" % ", ".join(PackedStringArray(names)))
	if stage != null:
		stage.refresh(world, PackedStringArray(names))
	for ship_name: Variant in names:
		world.release(String(ship_name))


## The name of the player's selected target ("" for none, or without a stage).
func player_target() -> String:
	return stage.player_target() if stage != null else ""


## Starts or stops the station's run of civilians between the jumpgate and the bays (M7-T56).
func traffic(on: bool) -> void:
	journal.append("traffic %s" % ("on" if on else "off"))
	_report("traffic", stage.traffic(on) if stage != null else "")


## Launches `count` more Starfuries of the station's wing `wing` (the places not flown, at most). False when the arm cannot
## launch now (another launch of the wing is still running): the caller may ask again later.
func scramble(wing: String, count: int = 12) -> bool:
	var why: String = stage.scramble(wing, count) if stage != null else ""
	journal.append("scramble %s %d%s" % [wing, count, "" if why.is_empty() else " refused: %s" % why])
	return why.is_empty()


## Sends the AI ship `ship_name` along `points` (Vector3, metres from the scenario's origin) at `cruise_mps`; `paced`, it waits
## for the player as an instructor does.
func fly(ship_name: String, points: Array, cruise_mps: float, paced: bool = false) -> void:
	journal.append("fly %s %d points" % [ship_name, points.size()])
	_report("fly", stage.fly(ship_name, points, cruise_mps, paced) if stage != null else "")


## The AI ship `ship_name` flies the demo `demo_name` (`Manoeuvres.NAMES`) where it is.
func demo(ship_name: String, demo_name: StringName) -> void:
	journal.append("demo %s %s" % [ship_name, demo_name])
	_report("demo", stage.fly(ship_name, [], Route.DEFAULT_CRUISE_MPS, false, demo_name) if stage != null else "")


## Gives the AI ship `ship_name` a pilot of `profile` (`AiProfile.PATHS`); "" gives it back the pilot it had (M8-T33).
func pilot(ship_name: String, profile: String = "") -> void:
	journal.append("pilot %s %s" % [ship_name, profile if not profile.is_empty() else "own"])
	_report("pilot", stage.pilot(ship_name, profile) if stage != null else "")


## Puts the AI ship `ship_name` in the player's flight, where it takes the player's wing orders (M8-T33).
func join_flight(ship_name: String) -> void:
	journal.append("join_flight %s" % ship_name)
	_report("join_flight", stage.join_flight(ship_name, true) if stage != null else "")


## Takes the AI ship `ship_name` out of the player's flight: its slot is free and it flies for itself again.
func leave_flight(ship_name: String) -> void:
	journal.append("leave_flight %s" % ship_name)
	_report("leave_flight", stage.join_flight(ship_name, false) if stage != null else "")


## Control's docking offer (M8-T06) is this mission's to say (`TriggerSpec.fact(&"dock_offers")`): the HUD's own line stays off.
func own_dock_offer() -> void:
	if stage != null:
		stage.own_dock_offer()


## The place `ahead_m` in front of the scene's jumpgate, where its arrivals come out; null with no gate (or no stage).
func gate_point(ahead_m: float) -> UniversePos:
	return stage.gate_point(ahead_m) if stage != null else null


## Where a step that was flown leaves these ships together (the player and its flight at the jumpgate): in a skipped step
## they are put at `at`, `spacing_m` apart, their velocity kept. Played, it does nothing: they flew there.
func gather(names: Array, at: UniversePos, spacing_m: float = 150.0) -> void:
	if at == null or not _seq.skipping or has_ended():
		return
	journal.append("gather %d at %s" % [names.size(), at])
	if stage != null:
		stage.refresh(world, PackedStringArray(names))  # only a ship the snapshot knows alive is moved
	for i: int in names.size():
		world.place(String(names[i]), at.plus_local(Vector3(spacing_m * i, 0.0, 0.0)))


## A number the game counts about the run (`MissionFacts.NAMES`), as of the last tick.
func fact(fact_name: StringName) -> float:
	return world.fact(fact_name)


## Runs `action` once, at the first tick `condition` holds (a `Trigger` or its dictionary), while the steps go on: for what may
## happen at any time (a docking offer, the first shot of a raid). It does not hold a step up and a skip does not force it.
func when(condition: Variant, action: Callable) -> void:
	var trigger: Trigger = _trigger_of(condition)
	if trigger == null or has_ended():
		return
	trigger.arm(world)
	_reactions.append({"trigger": trigger, "action": action})


## Keeps one of the script's own facts (a course time, a rating): `noted` reads it back, and a checkpoint restart keeps it.
func note(key: StringName, value: Variant) -> void:
	notes[key] = value
	journal.append("note %s %s" % [key, value])


func noted(key: StringName, fallback: Variant = null) -> Variant:
	return notes.get(key, fallback)


## From now on, a lost mission's debrief offers a restart from step `step` (`label` names it: "the raid's start"): the same
## seed, every step before it skipped, the notes as they are now.
func checkpoint(step: StringName, label: String) -> void:
	checkpoint_data = {"step": step, "label": label, "notes": notes.duplicate(true)}
	journal.append("checkpoint %s" % step)


## Adds a line to the debrief's panel.
func debrief_line(text: String) -> void:
	debrief_lines.append(text)


## The rank this mission earns (`Career.RANKS`); the game saves it when the mission ends in success.
func award_rank(p_rank: StringName) -> void:
	rank = p_rank
	journal.append("rank %s" % p_rank)


## Whether the pause menu may offer the script's skip now: one of the block's steps is running.
func skip_offered() -> bool:
	if skip_block.is_empty() or not is_running() or _seq.skipping:
		return false
	var from: int = _seq.steps.find(skip_block["from"])
	return _seq.index >= from and _seq.index < _seq.steps.find(skip_block["to"])


## Takes the pause menu's skip: straight to the step after the block. Returns "" or why not.
func take_skip() -> String:
	if not skip_offered():
		return "nothing to skip now"
	journal.append("skip block to %s" % skip_block["to"])
	return goto(skip_block["to"])


## Sends `count` raiders at the station (M7-T10): they come out of the scene's jumpgate when it has one and go for the grid's
## mounts and whoever fires at them; `scramble` launches the station's wings named in `data/station/traffic.json` against them.
func raid_station(count: int, scramble: bool = true) -> void:
	if has_ended():
		return
	journal.append("raid_station %d" % count)
	if stage == null:
		return
	var why: String = stage.raid_station(count, scramble)
	if not why.is_empty():
		push_error("Mission: raid_station: %s" % why)


## Lays a minefield (M10-T15, Q20): `entry` is a `MineFieldPlan` entry (`faction`, `kind`, `pattern` and its numbers, `seed`) plus
## `anchor` ("origin", the scenario's, or "player", where the player is now) and `at` ([x, y, z] metres from the anchor, default
## 0). Its mines never hurt `faction`'s side and its friends. Returns whether it was laid.
func lay_minefield(entry: Dictionary) -> bool:
	if has_ended():
		return false
	journal.append("lay_minefield %s" % entry.get("id", entry.get("pattern", "")))
	if stage == null:
		return true  # a pure script run: the field is only noted
	var why: String = stage.lay_minefield(entry)
	if not why.is_empty():
		push_error("Mission: lay_minefield: %s" % why)
	return why.is_empty()


## Puts `ship_name`'s name and hull on the HUD as a bar while the mission runs (the ship being escorted).
func show_hull(ship_name: String) -> void:
	if has_ended() or ship_name.strip_edges().is_empty() or hull_bars.has(ship_name):
		return
	hull_bars.append(ship_name)
	journal.append("show_hull %s" % ship_name)


## Holds or frees the player's controls: while held, `Main` zeroes their flight and combat commands and the ship flies on.
func lock_controls(on: bool) -> void:
	if has_ended():
		return
	controls_locked = on
	journal.append("lock_controls %s" % ("on" if on else "off"))


## Ends the mission now.
func end(success: bool, reason: String = "") -> void:
	if has_ended():
		return
	result = {"success": success, "reason": reason, "scenario_id": scenario_id, "title": title,
			"objectives": book.snapshot(), "time_s": world.time_s, "debrief_lines": debrief_lines.duplicate(),
			"checkpoint": checkpoint_data.duplicate(true), "rank": rank if success else &"", "notes": notes.duplicate(true)}
	_reactions.clear()
	_seq.stop()
	_live.clear()
	checks.stop()
	dialog.clear()  # nothing keeps talking over the debrief but the closing line
	if _shot != null and stage != null:
		stage.stop_cinematic(_shot)  # the result shows on the HUD, not under a shot
	_shot = null
	_record_finished_lines()
	journal.append("end %s%s" % ["success" if success else "failure", ": " + reason if not reason.is_empty() else ""])
	print("[mission] ended: %s" % GameFlow.describe_result(result))
	_say_closing_line()
	ended.emit(result)


## The closing line for `result` in `lines`: its reason's, else its outcome's ("success" or "failure"), else none. Pure.
static func closing_line_for(lines: Dictionary, result: Dictionary) -> StringName:
	var reason: String = str(result.get("reason", ""))
	if lines.has(reason):
		return StringName(lines[reason])
	var outcome: String = "success" if bool(result.get("success", false)) else "failure"
	return StringName(lines.get(outcome, &""))


## Reads the scenario's `cinematics` (shot id -> shot). Returns "" or why a shot is not one.
func load_cinematics(raw: Dictionary) -> String:
	cinematics.clear()
	for shot_id: Variant in raw:
		var made: Dictionary = CinematicShot.from_dict(StringName(str(shot_id)), raw[shot_id])
		if not bool(made["ok"]):
			cinematics.clear()
			return String(made["error"])
		cinematics[StringName(str(shot_id))] = made["shot"]
	return ""


# --- reads -------------------------------------------------------------------------------------------------------------


## Sim seconds since the mission began.
func time_s() -> float:
	return world.time_s


func alive(actor: String) -> bool:
	if stage != null:
		stage.refresh(world, PackedStringArray([actor]))
	return world.is_alive(actor)


func objective_state(id: StringName) -> StringName:
	return book.state_of(id)


func filled(text: String) -> String:
	return String(ScenarioLoader.fill_placeholders(text, placeholders))


# --- runner side -------------------------------------------------------------------------------------------------------


## Starts the script's first step. Returns "" or why it cannot run.
func begin(script: MissionScript) -> String:
	if script == null:
		return "no mission script"
	var problem: String = script.check_steps()
	if not problem.is_empty():
		return problem
	if script.steps().is_empty():
		return "the mission script has no steps"
	_started = true
	opening_until = script.opening_until()
	skip_block = script.skip_block()
	_seq.start(script, self)
	return ""


## One physics tick, after the world moved: time, the player's actions, the snapshot, the objectives, the result, then the
## waiting step looks at its trigger.
func tick(delta: float, actions: Dictionary) -> void:
	if _started and has_ended():
		dialog.tick(delta)  # the closing line runs out
		_record_finished_lines()
		return
	if not _started:
		return
	world.work = 0
	world.time_s += delta
	world.set_actions(actions)
	dialog.tick(delta)
	_record_finished_lines()
	settle()
	if not has_ended() and checks.is_active():
		checks.tick(delta, check_sample)
		_serve_checks()
	if not has_ended():
		_seq.tick()
	_react()
	tick_work = world.work


## Brings the snapshot up to date for every watched name, evaluates the objectives and applies the result rules.
func settle() -> void:
	if stage != null:
		stage.refresh(world, watched())
	for id: StringName in book.evaluate(world):
		journal.append("objective %s %s" % [id, book.state_of(id)])
		print("[mission] objective %s %s" % [id, book.state_of(id)])
	_check_result()


## Fast-forwards the current step. Returns "" or why not.
func skip() -> String:
	if has_ended():
		return "the mission has ended"
	return _seq.skip()


## The current step is being skipped (the console; not for scripts, which must not branch on a skip).
func is_skipping() -> bool:
	return _seq.skipping


## Skips every step before `step`. Returns "" or why not.
func goto(step: StringName) -> String:
	if has_ended():
		return "the mission has ended"
	return _seq.goto(step)


## The player may skip the opening now: it runs, with the controls held, before the step it ends at, and no skip is under way.
func opening_skippable() -> bool:
	if opening_until == &"" or not controls_locked or not is_running() or _seq.skipping:
		return false
	var until: int = _seq.steps.find(opening_until)
	return until > _seq.index


## Skips the rest of the opening (the player's hold of X). Returns "" or why not.
func skip_opening() -> String:
	if not opening_skippable():
		return "no opening to skip now"
	journal.append("skip opening to %s" % opening_until)
	print("[mission] opening skipped to %s" % opening_until)
	return goto(opening_until)


## The player's ship was destroyed: the mission is lost (D51).
func player_destroyed() -> void:
	end(false, "player destroyed")


## The station was destroyed (M10-T65, Q72: Babylon 5 is always destructible): a mission that needs it (`needs_station`, the
## default) is lost.
func station_destroyed() -> void:
	if needs_station:
		end(false, "station destroyed")


## Drops the waiting step and the links back to the game (the runner leaves the tree).
func release() -> void:
	_seq.release()
	_live.clear()
	# A script's own listeners and `when` actions hold this API (a lambda that captures `m`): let go, or it is never freed.
	_reactions.clear()
	for connection: Dictionary in demo_requested.get_connections():
		demo_requested.disconnect(connection["callable"] as Callable)
	world.stage = null
	stage = null


func has_ended() -> bool:
	return not result.is_empty()


func is_running() -> bool:
	return _started and not has_ended() and _seq.is_running()


func step_name() -> StringName:
	return _seq.step_name()


func step_index() -> int:
	return _seq.index


func steps() -> Array[StringName]:
	return _seq.steps


## Triggers evaluated each tick: the one the step awaits and those of the active objectives.
func live_trigger_count() -> int:
	return _live.size() + book.live_triggers().size()


## The actor names the live triggers read (lower case, once each), plus the waypoint's.
func watched() -> PackedStringArray:
	var seen: Dictionary = {}
	var out := PackedStringArray()
	var triggers: Array[Trigger] = book.live_triggers()
	triggers.append_array(_live)
	for reaction: Dictionary in _reactions:
		triggers.append(reaction["trigger"])
	for trigger: Trigger in triggers:
		for actor: String in trigger.actors():
			var k: String = MissionWorld.key(actor)
			if not seen.has(k):
				seen[k] = true
				out.append(k)
	if not waypoint_name.is_empty() and not seen.has(MissionWorld.key(waypoint_name)):
		out.append(MissionWorld.key(waypoint_name))
	return out


# --- internals ---------------------------------------------------------------------------------------------------------


# The mission's last word: its closing line for the result, if it has one.
func _say_closing_line() -> void:
	var line_id: StringName = closing_line_for(closing_lines, result)
	if line_id == &"":
		return
	var line: DialogBook.Line = dialog_book.line(line_id) if dialog_book != null else null
	if line == null:
		push_error("Mission: closing line '%s' is not in the dialog" % line_id)
		return
	journal.append("say %s" % line_id)
	dialog.say(line)


# Carries out what the open checks asked for: the hint's line, the demo, the journal.
func _serve_checks() -> void:
	for request: Dictionary in checks.take_requests():
		var check_id: StringName = request["check"]
		match request["kind"] as StringName:
			ControlCheckRunner.HINT:
				journal.append("check %s hint" % check_id)
				var line: DialogBook.Line = dialog_book.line(request["line"]) if dialog_book != null else null
				if line != null:
					dialog.say(line)
			ControlCheckRunner.DEMO:
				journal.append("check %s demo %s" % [check_id, request["demo"]])
				demo_requested.emit(check_id, request["demo"])
			ControlCheckRunner.PASSED:
				journal.append("check %s passed" % check_id)
				print("[mission] check %s passed" % check_id)


# The lines that ended since the last look are finished in the world, so `dialog_finished` triggers see them this tick.
func _record_finished_lines() -> void:
	for line_id: StringName in dialog.take_finished():
		world.finish_line(line_id)


func _trigger_of(condition: Variant) -> Trigger:
	if condition is Trigger:
		return condition as Trigger
	var made: Dictionary = TriggerSpec.from_dict(condition, world.system_id)
	if not bool(made["ok"]):
		push_error("Mission: until: %s" % made["error"])
		return null
	return made["trigger"] as Trigger


# A skipped step that keeps waiting is polling: it is reported once and from then on waits a tick at a time.
func _spinning() -> bool:
	_seq.skip_returns += 1
	if _seq.skip_returns == SKIP_SPIN_LIMIT + 1:
		push_error("Mission: step %s waited %d times in one skip: it polls; wait with until instead" % [step_name(),
				SKIP_SPIN_LIMIT])
	return _seq.skip_returns > SKIP_SPIN_LIMIT


func _open(id: StringName) -> bool:
	var state: StringName = book.state_of(id)
	return state == ObjectiveBook.HIDDEN or state == ObjectiveBook.ACTIVE


func _finish_objective(id: StringName, done: bool) -> bool:
	if has_ended():
		return false
	if not (book.complete(id) if done else book.fail(id)):
		push_error("Mission: objective_%s: %s" % ["complete" if done else "fail", book.error])
		return false
	journal.append("objective_%s %s" % ["complete" if done else "fail", id])
	_check_result()
	return true


# The snapshot learns about an objective's actors as soon as it shows, not a tick later.
func _refresh_objective(_id: StringName) -> void:
	if stage != null:
		stage.refresh(world, watched())


func _anchor(entry: Dictionary) -> UniversePos:
	var origin := UniversePos.new(0.0, 0.0, 0.0, world.system_id)
	if StringName(entry["anchor"]) != &"player":
		return origin
	var player: UniversePos = world.position_of("player")
	return player if player != null else origin


# Runs the `when` actions whose trigger holds now, each once.
func _react() -> void:
	var i: int = 0
	while i < _reactions.size() and not has_ended():
		var reaction: Dictionary = _reactions[i]
		if (reaction["trigger"] as Trigger).check(world):
			_reactions.remove_at(i)
			(reaction["action"] as Callable).call()
		else:
			i += 1


func _report(what: String, why: String) -> void:
	if not why.is_empty():
		push_error("Mission: %s: %s" % [what, why])


func _check_result() -> void:
	if has_ended():
		return
	var failed: StringName = book.failed_primary()
	if failed != &"":
		end(false, "objective failed: %s" % failed)
	elif book.all_primaries_done():
		end(true, "every primary objective done")
