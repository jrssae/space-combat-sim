class_name MissionWorld
extends RefCounted
## What a mission's triggers see of the world in one physics tick (architecture §18 D52): actors by name (universe position,
## alive, route end and whether it is reached), sim time, the dialog lines finished, and this tick's player actions. Pure data:
## the runner's `MissionStage` fills it each tick for the names the live triggers watch, and tests fill it by hand.
##
## Names are matched without case ("player" is the player's ship, whose name is PLAYER). Every lookup a trigger makes adds one to
## `work`, so the cost of the live triggers is counted, never timed (D52). A name counts as destroyed only once it has been seen
## alive: a ship the script has not spawned yet is not "destroyed" (an objective declared before its ships arrive waits for them).
##
## A forced trigger (D51's skip) changes the world through `place`, `release`, `finish_line` and `finish_route`: the snapshot
## changes at once and the `stage`, when there is one, makes the same change in the game.

## Seconds of sim time since the mission began (summed physics deltas).
var time_s: float = 0.0
## The scenario's star system: trigger points are in it.
var system_id: StringName = &"local"
## Lookups since the runner last reset it (per tick).
var work: int = 0
## The game side, or null (tests): it refreshes actors and carries out forced changes.
var stage: MissionStage = null
## Names released by forced `destroyed` triggers, in order (lower case).
var released: PackedStringArray = PackedStringArray()

var _positions: Dictionary = {}  # key -> UniversePos
var _alive: Dictionary = {}  # key -> bool
var _route_end: Dictionary = {}  # key -> UniversePos
var _route_done: Dictionary = {}  # key -> bool
var _lines: Dictionary = {}  # StringName -> true
var _seen: Dictionary = {}  # key -> true once it was in play
var _actions: Dictionary = {}  # StringName -> true, this tick only


## How a name is matched: trimmed, lower case.
static func key(actor: String) -> String:
	return actor.strip_edges().to_lower()


# --- filled by the stage (or a test) ---------------------------------------------------------------------------------------


## An actor in play at `position`.
func set_actor(actor: String, position: UniversePos, alive: bool = true) -> void:
	var k: String = key(actor)
	_positions[k] = position
	_alive[k] = alive
	if alive:
		_seen[k] = true


func set_alive(actor: String, alive: bool) -> void:
	var k: String = key(actor)
	_alive[k] = alive
	if alive:
		_seen[k] = true


## `actor` was in play and is gone (the stage knew it, but it died or left before any trigger looked).
func set_gone(actor: String) -> void:
	var k: String = key(actor)
	_alive[k] = false
	_seen[k] = true


## The end of the route `actor` leads, and whether it has got there.
func set_route(actor: String, end: UniversePos, done: bool) -> void:
	var k: String = key(actor)
	_route_end[k] = end
	_route_done[k] = done


## This tick's player actions (`PlayerActions.from_command`).
func set_actions(actions: Dictionary) -> void:
	_actions = actions


# --- read by triggers (each a counted lookup) -------------------------------------------------------------------------------


## Where `actor` is, or null when it is unknown or not alive.
func position_of(actor: String) -> UniversePos:
	work += 1
	var k: String = key(actor)
	if not bool(_alive.get(k, false)):
		return null
	return _positions.get(k) as UniversePos


func is_alive(actor: String) -> bool:
	work += 1
	return bool(_alive.get(key(actor), false))


## Whether `actor` was in play and is no longer (never seen: not destroyed, it has not arrived yet).
func is_destroyed(actor: String) -> bool:
	work += 1
	var k: String = key(actor)
	return _seen.has(k) and not bool(_alive.get(k, false))


func route_done(actor: String) -> bool:
	work += 1
	return bool(_route_done.get(key(actor), false))


## The end of the route `actor` leads, or null.
func route_end(actor: String) -> UniversePos:
	work += 1
	return _route_end.get(key(actor)) as UniversePos


func line_finished(line_id: StringName) -> bool:
	work += 1
	return _lines.has(line_id)


func performed(action: StringName) -> bool:
	work += 1
	return _actions.has(action)


# --- changed by forced triggers ---------------------------------------------------------------------------------------------


## Puts `actor` at `at` (its velocity kept), in the snapshot and in the game.
func place(actor: String, at: UniversePos) -> void:
	var k: String = key(actor)
	if not bool(_alive.get(k, false)):
		return
	_positions[k] = at
	if stage != null:
		stage.place(actor, at)


## Takes `actor` out of play with no explosion and no kill credit (a skipped `destroyed`).
func release(actor: String) -> void:
	var k: String = key(actor)
	if not bool(_alive.get(k, false)):
		return
	_alive[k] = false
	released.append(k)
	if stage != null:
		stage.release(actor)


func finish_line(line_id: StringName) -> void:
	_lines[line_id] = true


## Marks the route `actor` leads as flown to its end.
func finish_route(actor: String) -> void:
	_route_done[key(actor)] = true
	if stage != null:
		stage.finish_route(actor)
