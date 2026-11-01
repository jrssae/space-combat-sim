class_name KillCredit
extends RefCounted
## Who gets what for one enemy death (M3-T16, maintainer Q18, AC24): pure bookkeeping on ids the code already has.
##
## - **Kill**: the killing `HitInfo.shooter_id` is the player's ship (a bolt, or a ram: `RamResolver` puts the other body
##   there, so the player's own ram counts).
## - **Assist**: the kill is not the player's, and the player fired at least one shot while that ship was their selected
##   target (fired, not hit). The mark is kept per target id until the ship dies or its pool ship is reused (`forget`).
##
## A death is either a kill or an assist, never both. Ids: `player_id` is the player ship's body instance id (what
## `shooter_id` holds); targets are their `Targetable`'s instance id (what `TargetingSystem.selected_id()` returns).
## The counts last the session, across the player's respawns. `WaveDirector` owns one and feeds it.

const NONE: StringName = &"none"
const KILL: StringName = &"kill"
const ASSIST: StringName = &"assist"

var player_id: int = 0
var player_kills: int = 0
var player_assists: int = 0

var _fired_at: Dictionary = {}  # target id -> true


func _init(p_player_id: int = 0) -> void:
	player_id = p_player_id


## The player fired one shot with `selected_target_id` selected (0 or less: nothing selected, ignored).
func note_shot(selected_target_id: int) -> void:
	if selected_target_id > 0:
		_fired_at[selected_target_id] = true


func fired_at(target_id: int) -> bool:
	return _fired_at.has(target_id)


## Drops the mark on `target_id` (its pool ship is back in play as somebody new, or it left play).
func forget(target_id: int) -> void:
	_fired_at.erase(target_id)


## One enemy ship died: `target_id` its `Targetable`, `killer_id` the killing `HitInfo.shooter_id` (0 for the console).
## Updates the counts, forgets the mark and returns `KILL`, `ASSIST` or `NONE`.
func credit(target_id: int, killer_id: int) -> StringName:
	var marked: bool = _fired_at.has(target_id)
	_fired_at.erase(target_id)
	if player_id != 0 and killer_id == player_id:
		player_kills += 1
		return KILL
	if marked:
		player_assists += 1
		return ASSIST
	return NONE
