class_name DebriefRecorder
extends Node
## Keeps the player's counters for a mission's debrief (architecture §18, D56): feeds a `MissionTally` from the player's
## cannon (`projectile_fired`), the hit resolver (`hit_resolved`) and the destruction director (`ship_destroyed`), and adds
## them, with the kills and assists `WaveDirector`'s `KillCredit` holds, to the mission's result. A thin adapter; the counting
## rules are `MissionTally`'s. `MissionRunner` creates it under itself.

var main: Main = null
var tally: MissionTally = MissionTally.new()


func _ready() -> void:
	tally.player_id = main.ship.get_instance_id()
	main.cannon.projectile_fired.connect(_on_fired)
	(main.get_node(^"Combat/HitResolver") as HitResolver).hit_resolved.connect(tally.note_hit)
	main.director.ship_destroyed.connect(_on_ship_destroyed)


## `result` (`MissionApi.result`) with the counters the debrief shows added: a new dictionary, the original is left alone.
func report(result: Dictionary) -> Dictionary:
	var out: Dictionary = result.duplicate()
	out.merge(tally.stats(), true)
	out["kills"] = main.waves.credit.player_kills
	out["assists"] = main.waves.credit.player_assists
	return out


func _on_fired(_muzzle_index: int, _projectile: Projectile) -> void:
	tally.note_fired()


# The ship is still in its wing's slot here: the wings drop it at their next tick.
func _on_ship_destroyed(combatant: Combatant, _info: HitInfo) -> void:
	var wing: Wing = main.wings.player_wing()
	if wing != null and (wing.slot_of(combatant) > 0 or wing.leader == combatant):
		tally.note_wing_loss()
