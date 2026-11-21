class_name JumpDrive
extends RefCounted
## A jump-capable ship's drive (M8-T08, D83): opening a point empties it, and it needs its class's recharge before it can
## open another. A jumpgate needs no drive. Pure: sim seconds in.

## How long it needs after a jump, s.
var recharge_s: float = 0.0
## When it last opened a point (sim seconds); never: charged.
var fired_at_s: float = -INF


func _init(p_recharge_s: float = 0.0) -> void:
	recharge_s = maxf(p_recharge_s, 0.0)


## It opened a point at `now_s`.
func fire(now_s: float) -> void:
	fired_at_s = now_s


## Full now (a ship fresh from its pool, the console).
func charge() -> void:
	fired_at_s = -INF


## Seconds until it can open a point again (0: now).
func left_s(now_s: float) -> float:
	return maxf(fired_at_s + recharge_s - now_s, 0.0)


func is_ready(now_s: float) -> bool:
	return left_s(now_s) <= 0.0


## Its charge, 0 (just fired) to 1 (ready).
func level(now_s: float) -> float:
	return 1.0 if recharge_s <= 0.0 else clampf(1.0 - left_s(now_s) / recharge_s, 0.0, 1.0)
