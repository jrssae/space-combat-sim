class_name RaiderTactics
extends Resource
## The attack brain's numbers (architecture §15.8, M2-T07): ranges, speeds, the firing cone and timings of a raider's gun
## run. One resource, `assets/ai/raider_tactics.tres`; the defaults below are those values. Tune in (H).

## APPROACH: the closing speed to fly at beyond `near_range_m`, and inside it (m/s).
@export var closing_far_mps: float = 120.0
@export var closing_near_mps: float = 60.0
@export var near_range_m: float = 1500.0
## APPROACH: face the intercept lead once the velocity error is below this (m/s); before that, face the error.
@export var face_lead_delta_v_mps: float = 40.0
## FIRE while approaching: inside this range (m) and this angle off the lead (degrees).
@export var fire_range_m: float = 1200.0
@export var fire_cone_deg: float = 2.5
## FIRE: also only when the aim error would miss by less than this (m) at the target's range: `atan(fire_miss_m / range)`
## caps the cone, so the trigger tightens as the range grows. A hull a few metres across is hit within about this.
@export var fire_miss_m: float = 3.0
## BREAK: when closer than this (m), or after this long (s) inside the fire range.
@export var break_range_m: float = 300.0
@export var max_time_on_target_s: float = 8.0
## BREAK: speed (m/s) across the line of sight, and how long (s) before the extension starts.
@export var break_speed_mps: float = 120.0
@export var break_duration_s: float = 2.5
## EXTEND: at least this long (s) and until beyond this range (m), then APPROACH again.
@export var extend_min_s: float = 4.0
@export var extend_range_m: float = 1400.0
