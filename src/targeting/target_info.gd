class_name TargetInfo
extends RefCounted
## One targeting candidate as `TargetingSystem` sees it (architecture §6.3): plain data, rebuilt every physics tick
## from the live `Targetable`s, so nothing holds a stale world position across a `World.rebase()`.
##
## `position` and `velocity` are `World`-local (metres, m/s): candidates are within sensor range (25 km) of the ship,
## where float32 is still millimetre-accurate. `faction` is the IFF seam (§14.9): `&"neutral"` for every M1 buoy;
## allies and enemies arrive with M2.

## Identity of the target for as long as it exists (the `Targetable` node's instance id). Never 0: 0 means "none".
var id: int = 0
## What the pilot reads ("NAV ALPHA"); the console selects targets by it.
var display_name: String = ""
var faction: StringName = &"neutral"
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Hull 0..1 of the target, or -1 when it has no hull (a buoy): the HUD's hull bar (M2-T08).
var hull_fraction: float = -1.0
## Radius of a sphere around the target that holds it (its `Damageable`'s), metres; 0 when unknown. Sizes the HUD's target box.
var bounding_radius: float = 0.0


func _init(p_id: int = 0, p_display_name: String = "", p_faction: StringName = &"neutral",
		p_position: Vector3 = Vector3.ZERO, p_velocity: Vector3 = Vector3.ZERO, p_hull_fraction: float = -1.0,
		p_bounding_radius: float = 0.0) -> void:
	id = p_id
	display_name = p_display_name
	faction = p_faction
	position = p_position
	velocity = p_velocity
	hull_fraction = p_hull_fraction
	bounding_radius = p_bounding_radius


func _to_string() -> String:
	return "TargetInfo(%d %s %s at %s)" % [id, display_name, faction, position]
