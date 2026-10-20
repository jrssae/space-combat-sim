class_name WeaponCapacitor
extends RefCounted
## The energy store behind the pulse cannons (architecture §6.3, M2-T14). Pure: time comes in as a number
## (`SimClock.now()` in the game, a fake clock in tests), like `PulseCannonGate`.
##
## Every projectile costs `cost_per_shot`; the store refills at `recharge_per_s` up to `capacity`, all the time
## (firing does not pause the recharge). The gate asks `spend` before it commits a shot, so an empty capacitor
## blocks the trigger without disturbing the gate's cooldown or muzzle turn.
##
## Defaults, in arbitrary energy units: 100 capacity, 14 per shot, 25 per second.
## - Empty to full in `capacity / recharge_per_s` = 4 s.
## - Both modes fire 4 projectiles a second, so holding the trigger drains 56 - 25 = 31 per second. A full charge
##   lasts 12 alternating shots (3 s) or 5 linked volleys (10 projectiles, 2.5 s), all at the full M1 rates; after
##   that the cannon is held to `recharge / cost` = 1.8 projectiles per second until the trigger is released and the
##   store refills.
## - A LINKED volley is two projectiles, so it costs 2 × `cost_per_shot` and waits until it can pay all of it.
##
## Charge is kept as a value and the time it was last true; `charge_at` extrapolates without changing anything (the
## console and HUD read it between ticks), `advance` and `spend` fold the elapsed time in. A clock that jumps back
## (`SimClock.reset`, a respawn) adds nothing and loses nothing.

const DEFAULT_CAPACITY: float = 100.0
const DEFAULT_COST_PER_SHOT: float = 14.0
const DEFAULT_RECHARGE_PER_S: float = 25.0
## Slack for the affordability test, so a charge that sums to the cost a few ulps short still pays.
const CHARGE_EPSILON: float = 1e-9

## Energy units held when full.
var capacity: float = DEFAULT_CAPACITY
## Energy units taken by one projectile.
var cost_per_shot: float = DEFAULT_COST_PER_SHOT
## Energy units regained per second.
var recharge_per_s: float = DEFAULT_RECHARGE_PER_S

var _charge: float = DEFAULT_CAPACITY
# Sim time at which `_charge` was exact; NAN until the first `advance` or `spend`.
var _stamp_s: float = NAN


func _init(p_capacity: float = DEFAULT_CAPACITY, p_cost_per_shot: float = DEFAULT_COST_PER_SHOT,
		p_recharge_per_s: float = DEFAULT_RECHARGE_PER_S) -> void:
	capacity = maxf(0.0, p_capacity)
	cost_per_shot = maxf(0.0, p_cost_per_shot)
	recharge_per_s = maxf(0.0, p_recharge_per_s)
	_charge = capacity


## Energy units in the store at `now_s`.
func charge_at(now_s: float) -> float:
	var elapsed: float = 0.0 if is_nan(_stamp_s) else maxf(0.0, now_s - _stamp_s)
	return minf(capacity, _charge + recharge_per_s * elapsed)


## 0..1 at `now_s`; 0 for a capacitor without capacity.
func fraction_at(now_s: float) -> float:
	return clampf(charge_at(now_s) / capacity, 0.0, 1.0) if capacity > 0.0 else 0.0


## Whether `shots` projectiles could be paid for at `now_s` (changes nothing).
func can_afford(shots: int, now_s: float) -> bool:
	return charge_at(now_s) + CHARGE_EPSILON >= float(shots) * cost_per_shot


## Folds the time up to `now_s` into the charge. The gate calls it every tick, so a clock that was reset to an
## earlier time starts recharging again from there instead of waiting to catch up.
func advance(now_s: float) -> void:
	_charge = charge_at(now_s)
	_stamp_s = now_s


## Pays for `shots` projectiles at `now_s`. Returns false and takes nothing when the store cannot cover all of them.
func spend(shots: int, now_s: float) -> bool:
	advance(now_s)
	var need: float = float(shots) * cost_per_shot
	if _charge + CHARGE_EPSILON < need:
		return false
	_charge = maxf(0.0, _charge - need)
	return true


## Full again (respawn, the console).
func refill() -> void:
	_charge = capacity


## Sets the charge to `fraction` (0..1) of capacity as of `now_s` (console and tests).
func set_fraction(fraction: float, now_s: float) -> void:
	if is_nan(fraction):
		return
	advance(now_s)
	_charge = clampf(fraction, 0.0, 1.0) * capacity
