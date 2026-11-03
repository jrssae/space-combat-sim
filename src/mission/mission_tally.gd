class_name MissionTally
extends RefCounted
## The counters a mission keeps for its debrief that no other class already keeps (architecture §18, D56): the player's bolts
## fired and the ones that hit, and the wingmen lost. Kills and assists are `KillCredit`'s; the time and the objectives are the
## mission's own. Pure: `DebriefRecorder` feeds it from the game's signals.
##
## Only the player's own bolts count: `player_id` is the player ship's body instance id, which is what a bolt's `shooter_id`
## holds. A ram, a console hit and another ship's bolt are not shots the player landed.

var player_id: int = 0
var shots_fired: int = 0
var shots_hit: int = 0
var wing_losses: int = 0


func _init(p_player_id: int = 0) -> void:
	player_id = p_player_id


## The player's cannon fired one bolt.
func note_fired() -> void:
	shots_fired += 1


## A hit was resolved anywhere; it counts when it is a bolt of the player's.
func note_hit(info: HitInfo) -> void:
	if player_id != 0 and info != null and info.cause == HitInfo.CAUSE_BOLT and info.shooter_id == player_id:
		shots_hit += 1


## A ship of the player's wing was destroyed.
func note_wing_loss() -> void:
	wing_losses += 1


## Hits over shots, 0 to 1; 0 with no shots.
func accuracy() -> float:
	return clampf(float(shots_hit) / float(shots_fired), 0.0, 1.0) if shots_fired > 0 else 0.0


## The keys a mission result carries for the debrief.
func stats() -> Dictionary:
	return {"shots_fired": shots_fired, "shots_hit": shots_hit, "wing_losses": wing_losses}
