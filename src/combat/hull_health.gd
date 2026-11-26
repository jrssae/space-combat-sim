class_name HullHealth
extends RefCounted
## Hull points of one ship (architecture §15.4). `destroyed` turns true once; the `apply` call that crossed zero reports it
## through `destroyed_now`, so a caller that reacts to it (the `Damageable` emitting `destroyed`) fires exactly once per life
## even when several bolts land in the same tick. Later hits apply nothing.
##
## The points live in the native damage store (M10-T75, Q94, `DamageStore`), which applies the rules; this is the ship's
## read-only copy, refreshed by each call. Writing `hp` or `max_hp` writes the store too.

## A capacity below this (zero, negative or NaN) is raised to it, so `fraction()` never divides by zero.
const MIN_MAX_HP: float = 1e-3

var max_hp: float = 1.0:
	set(value):
		max_hp = value
		_push()
var hp: float = 1.0:
	set(value):
		hp = value
		_push()
## True from the `apply` that took `hp` to zero until `restore()`.
var destroyed: bool = false
## True only directly after the `apply` call that crossed zero; every other `apply` and `restore` clear it.
var destroyed_now: bool = false
## Its handle in the store.
var id: int = -1


func _init(p_max_hp: float = 100.0) -> void:
	var capacity: float = p_max_hp if p_max_hp >= MIN_MAX_HP else MIN_MAX_HP  # the comparison is false for NaN, so NaN is caught
	id = int(DamageStore.store.hull_add(capacity))
	DamageStore.adopt(DamageStore.ON_HULL, id, self)
	var was: bool = DamageStore.quiet
	DamageStore.quiet = true
	max_hp = capacity
	hp = capacity
	DamageStore.quiet = was


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and id >= 0 and DamageStore.store != null:
		DamageStore.store.hull_free(id)
		DamageStore.forget(DamageStore.ON_HULL, id)


## Removes up to `amount` points and returns what was actually removed: never more than the remaining `hp`, and 0
## for a negative, zero or NaN amount (no healing through this call) or once the hull is destroyed.
func apply(amount: float) -> float:
	var out: PackedFloat64Array = DamageStore.store.hull_apply(id, amount)
	take(out[1], out[2] != 0.0, out[3] != 0.0)
	return out[0]


## The store's word on this hull after a hit it landed itself (a beam batch): its points and flags.
func take(p_hp: float, p_destroyed: bool, p_destroyed_now: bool) -> void:
	var was: bool = DamageStore.quiet
	DamageStore.quiet = true
	hp = p_hp
	DamageStore.quiet = was
	destroyed = p_destroyed
	destroyed_now = p_destroyed_now


## Back to a full, intact hull (respawn, pool re-use, console `heal`).
func restore() -> void:
	DamageStore.store.hull_restore(id)
	take(max_hp, false, false)


## Remaining hull as 0.0 (dead) to 1.0 (full).
func fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func _push() -> void:
	if id >= 0 and not DamageStore.quiet:
		DamageStore.store.hull_set(id, max_hp, hp)
