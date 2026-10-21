class_name Silhouette
extends RefCounted
## Outline drawings of the main components for the HUD's damage indicators (pure data). Each polygon belongs to one damage
## zone (`DamageZones`) and is in the unit square -0.5..0.5 (x right, y down, as on the screen), to be scaled into a rect.
## The X fighter (Starfury) is drawn from the front: the cabin and the four arms with their pods. The delta (raider) is drawn
## from above: the central hump and the two wings, nose up.

const _CABIN: PackedVector2Array = [Vector2(0.0, -0.32), Vector2(0.12, -0.14), Vector2(0.12, 0.2), Vector2(0.0, 0.34),
		Vector2(-0.12, 0.2), Vector2(-0.12, -0.14)]


## `[{zone: int, points: PackedVector2Array}, ...]` for a layout; empty for `Layout.NONE`.
static func polygons(layout: DamageZones.Layout) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match layout:
		DamageZones.Layout.X_FIGHTER:
			out.append({"zone": DamageZones.CABIN, "points": _CABIN})
			_arm(out, DamageZones.UPPER_LEFT, -1.0, -1.0)
			_arm(out, DamageZones.UPPER_RIGHT, 1.0, -1.0)
			_arm(out, DamageZones.LOWER_LEFT, -1.0, 1.0)
			_arm(out, DamageZones.LOWER_RIGHT, 1.0, 1.0)
		DamageZones.Layout.DELTA:
			out.append({"zone": DamageZones.DELTA_CENTRE, "points": PackedVector2Array([Vector2(0.0, -0.4), Vector2(0.1, -0.05),
					Vector2(0.1, 0.34), Vector2(-0.1, 0.34), Vector2(-0.1, -0.05)])})
			out.append({"zone": DamageZones.DELTA_LEFT, "points": PackedVector2Array([Vector2(-0.1, -0.05), Vector2(-0.5, 0.3),
					Vector2(-0.5, 0.4), Vector2(-0.1, 0.34)])})
			out.append({"zone": DamageZones.DELTA_RIGHT, "points": PackedVector2Array([Vector2(0.1, -0.05), Vector2(0.5, 0.3),
					Vector2(0.5, 0.4), Vector2(0.1, 0.34)])})
	return out


# One arm of the X: a slanted strut from the cabin and the pod at its end. `sx` / `sy` are -1 / +1 for left / right and
# up / down (y grows downward on the screen).
static func _arm(out: Array[Dictionary], zone: int, sx: float, sy: float) -> void:
	var strut := PackedVector2Array([Vector2(sx * 0.1, sy * 0.06), Vector2(sx * 0.4, sy * 0.24), Vector2(sx * 0.4, sy * 0.32),
			Vector2(sx * 0.1, sy * 0.14)])
	var pod := PackedVector2Array([Vector2(sx * 0.36, sy * 0.16), Vector2(sx * 0.48, sy * 0.16), Vector2(sx * 0.48, sy * 0.44),
			Vector2(sx * 0.36, sy * 0.44)])
	out.append({"zone": zone, "points": strut})
	out.append({"zone": zone, "points": pod})
