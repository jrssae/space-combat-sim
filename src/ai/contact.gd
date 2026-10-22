class_name Contact
extends RefCounted
## One thing an AI ship sees this tick (architecture §16 D33, D34): a ship, a drone or a prop, built by `ContactScan` from
## the active `Targetable`s and `Damageable`s around it. Plain data, World-local and current as of this tick, so nothing in
## it goes stale across a `World.rebase()`. The scan shares one object between every ship of the same faction that sees
## it: brains read contacts, they never write them.

## The `Targetable`'s instance id (the same id as `TargetInfo.id` and a `TargetingController` selection), or the body's
## instance id for a hull that has no `Targetable`. Never 0.
var id: int = 0
## What the pilot reads ("RAIDER 2", "NAV ALPHA"); empty when it has no `Targetable`.
var name: String = ""
var faction: StringName = Factions.NEUTRAL
## How the perceiving ship regards it (`Factions.relation(own faction, faction)`).
var relation: Factions.Relation = Factions.Relation.NEUTRAL
## World frame, m and m/s. Bodies without physics (a buoy) report their kinematic drift, zero for a static prop.
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Its nose (-Z of the body), unit.
var forward: Vector3 = Vector3.FORWARD
## A sphere around `position` that holds the whole body (its `Damageable`'s), m; 0 when it has no hull.
var bounding_radius: float = 0.0
## True for a rigid body that flies (a ship or a drone), false for a prop (a buoy).
var is_ship: bool = false
## Hull 0..1, or -1 when it has no hull.
var hull_fraction: float = -1.0
## The `Targetable` id it has selected, -1 when nothing is selected or it has no targeting computer.
var target_id: int = -1


## A copy seen from a ship that regards it as `p_relation`.
func with_relation(p_relation: Factions.Relation) -> Contact:
	var c := Contact.new()
	c.id = id
	c.name = name
	c.faction = faction
	c.relation = p_relation
	c.position = position
	c.velocity = velocity
	c.forward = forward
	c.bounding_radius = bounding_radius
	c.is_ship = is_ship
	c.hull_fraction = hull_fraction
	c.target_id = target_id
	return c


func _to_string() -> String:
	return "Contact(%d %s %s at %s)" % [id, name, faction, position]
