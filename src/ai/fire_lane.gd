class_name FireLane
extends RefCounted
## The AI's "don't shoot through friends" check (architecture §16 D31). Pure. The lane is the straight bolt path from the
## shooter along `aim_dir`, short of the target (`0 < along < range_m`); a contact closes it when its centre is within its
## bounding radius plus `CLEARANCE_M` of that line and it is a friendly, or, with friendly fire on (a bolt then hurts any
## hull but the shooter's), any ship that is not hostile. The target itself never closes the lane, nor do hostiles (hitting
## one is fine) or props (buoys: every bolt hits them whatever the setting, so the setting changes nothing about them).
## `AttackBrain` asks before it holds the trigger; the check runs in both settings.

## Clearance around a contact's bounding sphere, m: the muzzles sit a few metres off the ship's centre line.
const CLEARANCE_M: float = 5.0


## True when nothing that must not be hit sits in the lane. `target_id` is the target's `Contact.id` (`TargetInfo.id`).
static func clear(own_pos: Vector3, aim_dir: Vector3, range_m: float, contacts: Array[Contact], target_id: int = 0,
		friendly_fire: bool = false) -> bool:
	if aim_dir.length_squared() < 1e-12 or range_m <= 0.0:
		return true
	var dir: Vector3 = aim_dir.normalized()
	for c: Contact in contacts:
		if c.id == target_id or not _protected(c, friendly_fire):
			continue
		var rel: Vector3 = c.position - own_pos
		var along: float = rel.dot(dir)
		if along <= 0.0 or along >= range_m:
			continue
		var width: float = c.bounding_radius + CLEARANCE_M
		if (rel - dir * along).length_squared() < width * width:
			return false
	return true


static func _protected(c: Contact, friendly_fire: bool) -> bool:
	if c.relation == Factions.Relation.FRIENDLY:
		return true
	return friendly_fire and c.is_ship and c.relation != Factions.Relation.HOSTILE
