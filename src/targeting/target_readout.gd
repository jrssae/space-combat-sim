class_name TargetReadout
extends RefCounted
## What the pilot is told about the selected target (architecture §6.3): computed by `TargetingSystem.compute_readout`
## from one ship state and one target state, never cached across ticks. The debug overlay prints
## `TGT NAV BRAVO  1243 m  +12.4 m/s` from it and draws the bracket at `position` (T15).

var id: int = 0
var display_name: String = ""
var faction: StringName = &"neutral"
## Target position, `World`-local (where the bracket goes).
var position: Vector3 = Vector3.ZERO
## Straight-line distance ship to target, metres.
var range_m: float = 0.0
## Rate at which the range shrinks, m/s: `-(v_t - v_s) . (p_t - p_s) / range`. Positive = closing, negative = opening.
var closing_mps: float = 0.0
## Angle between the ship's forward axis and the line of sight, degrees (0 = dead ahead, 180 = dead astern).
var angle_off_deg: float = 0.0
## Target velocity, World frame (the HUD's lead reticle).
var velocity: Vector3 = Vector3.ZERO
## Target hull 0..1, or -1 without a hull; and the radius of a sphere holding it (metres, 0 = unknown).
var hull_fraction: float = -1.0
var bounding_radius: float = 0.0
## Damage by main component, as in `TargetInfo`.
var damage_layout: DamageZones.Layout = DamageZones.Layout.NONE
var damage_zones: PackedFloat32Array = PackedFloat32Array()


func _to_string() -> String:
	return "TargetReadout(%s %.1f m %+.2f m/s %.1f deg)" % [display_name, range_m, closing_mps, angle_off_deg]
