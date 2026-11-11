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
##     m.spawn(spawn)                  a ship from a pool, by the scenario's spawn rules; `arrival: "jump"` opens a jump point,
##                                     `arrival: "gate"` brings it out of the jumpgate's blue vortex (M6-T14; null now, in play by
##                                     its name once through)
##     m.depart(ship)                  an AI ship flies out through the jumpgate's orange vortex and leaves play (M6-T14)
##     m.send(ship, target)            the ship's pilot objective (D39)
##     m.transient(names)              ships that only matter while the step plays: a skipped step releases them (M5-T30)
##     m.objective_add(id [, text, primary]) / m.objective_complete(id) / m.objective_fail(id)
##     m.waypoint(name or null)        the HUD's waypoint marker on an actor
##     m.lock_controls(on)             the player's flight and combat commands held at zero; the ship flies on (D55)
##     m.end(success [, reason])
##     m.time_s(), m.alive(name), m.objective_state(id)
##     m.filled(text)                  `text` with the scenario's placeholders filled in ("{civilian}" -> the drawn ship's name)
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
## Skipping (D51): in a skipped step every wait returns at once; `until` first makes its trigger true (`Trigger.make_true`),
## `until_objective` completes the objective through its forced success trigger, and the objectives are evaluated right after,
## so the world ends where the step would have left it. World changes still run. Nothing runs once the mission has ended: a
## step that waits after `end` never resumes. Scripts wait with `until`, never poll: a skipped step that keeps waiting
## (`SKIP_SPIN_LIMIT` returns in one skip) is reported and then waits a tick at a time instead of spinning.
##
## Runner side: `begin`, `tick` (once per physics tick, after the world moved), `skip`, `goto`, `is_skipping`,
## `player_destroyed`, `release`.

## The mission is over: `result` holds how.
signal ended(result: Dictionary)

## Slack when comparing summed tick times with a wait's end (120 ticks of 1/60 s must reach 2 s).
const TIME_EPS_S: float = 1e-6
## Waits that may return at once in one skip before the step counts as polling (a script that waits in a loop).
const SKIP_SPIN_LIMIT: int = 1000

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
## `lock_controls` asked for the player's controls to be held: `Main` zeroes their commands while it is set.
var controls_locked: bool = false
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

var _seq: MissionSequencer = MissionSequencer.new()
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


# --- world changes -----------------------------------------------------------------------------------------------------


## Takes a ship from its pool: a scenario spawn (`type`, `name`, `anchor`, `offset`, `velocity`, `behaviour`, `wing`) plus
## `arrival` ("none", "jump" or "gate") and `invulnerable`. Returns the ship, or null (with an error when the pool is spent); a
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


## Marks an actor with the HUD's waypoint (its name), or clears it (null or "").
func waypoint(target: Variant) -> void:
	if has_ended():
		return
	waypoint_name = "" if target == null else String(target).strip_edges()
	journal.append("waypoint %s" % (waypoint_name if not waypoint_name.is_empty() else "none"))


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
			"objectives": book.snapshot(), "time_s": world.time_s}
	_seq.stop()
	_live.clear()
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
	if not has_ended():
		_seq.tick()
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


## The player's ship was destroyed: the mission is lost (D51).
func player_destroyed() -> void:
	end(false, "player destroyed")


## Drops the waiting step and the links back to the game (the runner leaves the tree).
func release() -> void:
	_seq.release()
	_live.clear()
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


func _check_result() -> void:
	if has_ended():
		return
	var failed: StringName = book.failed_primary()
	if failed != &"":
		end(false, "objective failed: %s" % failed)
	elif book.all_primaries_done():
		end(true, "every primary objective done")
