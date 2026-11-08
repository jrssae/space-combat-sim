class_name FireLane
extends RefCounted
## The AI's "don't shoot through friends" check (architecture §16 D31). Pure. The lane is the straight bolt path from the
## shooter along `aim_dir`, short of the target (`0 < along < range_m`); a contact closes it when its centre is within its
## bounding radius plus `CLEARANCE_M` of that line and it is a friendly, or, with friendly fire on (a bolt then hurts any
## hull but the shooter's), any ship that is not hostile. A friendly prop (a buoy or station of the shooter's faction)
## closes it like a friendly ship. The target itself never closes the lane, nor do hostiles (hitting one is fine) or
## other props (buoys: every bolt hits them whatever the setting, so the setting changes nothing about them).
## `AttackBrain` asks before it holds the trigger; the check runs in both settings.
## The check runs in the native pilot kernels (M4-T16, architecture §17.13; `kernels::pilot::fire_lane`): over the core's
## rows when the perception is on them (`Perception.on_rows`), else over the contacts loaded as rows (`PilotRows`). The
## GDScript loop it matched went in M4-T42; its verdicts are recorded in `tests/fixtures/parity/pilot_kernels.json`.

## Clearance around a contact's bounding sphere, m: the muzzles sit a few metres off the ship's centre line.
const CLEARANCE_M: float = 5.0


## True when nothing that must not be hit sits in the lane. `target_id` is the target's `Contact.id` (`TargetInfo.id`).
static func clear(own_pos: Vector3, aim_dir: Vector3, range_m: float, contacts: Array[Contact], target_id: int = 0,
		friendly_fire: bool = false) -> bool:
	var kernels: Object = PilotRows.kernels_of(contacts)
	if kernels == null:
		return true
	return kernels.fire_lane(PilotRows.span(0, contacts.size()), PilotRows.relations(contacts), own_pos, aim_dir, range_m,
			target_id, friendly_fire)


## `clear` for a perception: from its position, against its contacts, with its friendly-fire setting, over the core's rows
## when it is on them.
static func clear_seen(p: Perception, aim_dir: Vector3, range_m: float, target_id: int = 0) -> bool:
	if p.on_rows():
		return p.kernels.fire_lane(p.contact_rows, p.relation_row, p.position, aim_dir, range_m, target_id, p.friendly_fire)
	return clear(p.position, aim_dir, range_m, p.contacts, target_id, p.friendly_fire)
