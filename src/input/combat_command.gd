class_name CombatCommand
extends RefCounted
## Weapons and targeting requests for one physics tick; written by the player or an AI (architecture §6.2).

var fire: bool = false  ## held
var weapon_next: bool = false  ## edge
var target_next: bool = false  ## edge
var target_ahead: bool = false  ## edge


func to_dict() -> Dictionary:
	return {"fire": fire, "weapon_next": weapon_next, "target_next": target_next, "target_ahead": target_ahead}
