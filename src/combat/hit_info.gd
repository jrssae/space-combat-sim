class_name HitInfo
extends RefCounted
## One resolved bolt hit (architecture §15.4, §15.5): plain data from `HitResolver` to `Damageable.apply_hit`, and on
## to the HUD, the impact flash, the sound and the kill counter via `hit_resolved` / `hit_taken` / `damaged`.

## Instance id of the `Damageable` (or its ship) that was hit.
var target_id: int = 0
## Instance id of the ship that fired the bolt; never equal to `target_id` for a resolved hit.
var shooter_id: int = 0
## Faction of the bolt (its shooter's faction).
var faction: StringName = &""
## Hull points the bolt carries (`WeaponSpec.damage`).
var damage: float = 0.0
## Where the bolt entered the hit volume, `World`-local.
var point: Vector3 = Vector3.ZERO
## Surface normal at `point`, best effort: the reversed relative direction of the bolt is acceptable.
var normal: Vector3 = Vector3.ZERO
## Speed of the bolt relative to the target at impact.
var relative_speed_mps: float = 0.0
## Hull points actually removed; 0 until the `Damageable` has applied the hit (and for god mode or a dead hull).
var applied: float = 0.0


func _init(p_target_id: int = 0, p_shooter_id: int = 0, p_faction: StringName = &"", p_damage: float = 0.0,
		p_point: Vector3 = Vector3.ZERO, p_normal: Vector3 = Vector3.ZERO, p_relative_speed_mps: float = 0.0) -> void:
	target_id = p_target_id
	shooter_id = p_shooter_id
	faction = p_faction
	damage = p_damage
	point = p_point
	normal = p_normal
	relative_speed_mps = p_relative_speed_mps


func _to_string() -> String:
	return "HitInfo(%d -> %d %s damage %.1f applied %.1f at %s)" % [shooter_id, target_id, faction, damage, applied,
			point]
