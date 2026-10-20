class_name HullHealth
extends RefCounted
## Hull points of one ship (architecture §15.4), pure. `destroyed` turns true once; the `apply` call that crossed
## zero reports it through `destroyed_now`, so a caller that reacts to it (the `Damageable` emitting `destroyed`)
## fires exactly once per life even when several bolts land in the same tick. Later hits apply nothing.

## A capacity below this (zero, negative or NaN) is raised to it, so `fraction()` never divides by zero.
const MIN_MAX_HP: float = 1e-3

var max_hp: float = 1.0
var hp: float = 1.0
## True from the `apply` that took `hp` to zero until `restore()`.
var destroyed: bool = false
## True only directly after the `apply` call that crossed zero; every other `apply` and `restore` clear it.
var destroyed_now: bool = false


func _init(p_max_hp: float = 100.0) -> void:
	max_hp = p_max_hp if p_max_hp >= MIN_MAX_HP else MIN_MAX_HP  # the comparison is false for NaN, so NaN is caught
	hp = max_hp


## Removes up to `amount` points and returns what was actually removed: never more than the remaining `hp`, and 0
## for a negative, zero or NaN amount (no healing through this call) or once the hull is destroyed.
func apply(amount: float) -> float:
	destroyed_now = false
	if destroyed or not (amount > 0.0):
		return 0.0
	var applied: float = minf(amount, hp)
	hp -= applied
	if hp <= 0.0:
		hp = 0.0
		destroyed = true
		destroyed_now = true
	return applied


## Back to a full, intact hull (respawn, pool re-use, console `heal`).
func restore() -> void:
	hp = max_hp
	destroyed = false
	destroyed_now = false


## Remaining hull as 0.0 (dead) to 1.0 (full).
func fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)
