class_name Transponder
extends RefCounted
## The identity a ship broadcasts (M10-T02): a renegade carries the Earth Alliance's transponder, so everyone but its own side
## takes it for Earth Alliance until it fires on someone it should not (`Targetable.reveal`). Pure rules; the per-ship state
## lives on `Targetable` and in the native core's rows.


## The faction `observer` takes a ship to be: the broadcast one while it is disguised, except to the ship's own side.
static func seen_faction(true_faction: StringName, broadcast: StringName, observer: StringName) -> StringName:
	if broadcast.is_empty() or observer == true_faction:
		return true_faction
	return broadcast


## Whether a shot at (or a hit on) `victim_faction` gives a disguised ship away: the victim is the player, or of the faction the
## ship broadcasts or one friendly to it.
static func is_hostile_act(broadcast: StringName, victim_faction: StringName, victim_is_player: bool) -> bool:
	return victim_is_player or Factions.relation(broadcast, victim_faction) == Factions.Relation.FRIENDLY


## A disguised ship fired: it gives itself away when the target it holds is the player or of a side its transponder calls friend.
static func note_shot(shooter: Targetable) -> void:
	if shooter == null or not shooter.is_disguised():
		return
	var id: int = ContactScan.selection_of(shooter.get_parent())
	if id <= 0 or not is_instance_id_valid(id):
		return
	var victim := instance_from_id(id) as Targetable
	if victim != null and is_hostile_act(shooter.transponder, victim.faction, _is_player(victim.get_parent())):
		shooter.reveal()


## A bolt of body `shooter_id` hit `victim`: the same test, on what it actually hit.
static func note_hit(shooter_id: int, victim: Damageable) -> void:
	if not SimCore.is_disguised(shooter_id) or not is_instance_id_valid(shooter_id) or victim == null:
		return
	var shooter: Targetable = Targetable.of(instance_from_id(shooter_id) as Node)
	if shooter != null and is_hostile_act(shooter.transponder, victim.faction, _is_player(victim.body())):
		shooter.reveal()


static func _is_player(body: Node) -> bool:
	var ship := body as Ship
	return ship != null and ship.console_owner
