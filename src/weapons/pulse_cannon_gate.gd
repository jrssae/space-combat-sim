class_name PulseCannonGate
extends RefCounted
## The pulse cannon's trigger logic (architecture §6.3): which muzzles fire on a given tick. Pure: time comes in as
## a number (`SimClock.now()` in the game, a fake clock in tests), nothing is spawned here.
##
## - `ALTERNATING`: one shot every 0.25 s (4 Hz), the muzzles taking turns 0, 1, 0, 1, ...
## - `LINKED`: both muzzles together every 0.5 s (2 Hz), `[0, 1]`.
##
## Both modes put out the same 4 projectiles per second. The gate keeps one number, the time the next shot is
## allowed (`_ready_at_s`), and each shot pushes it out by 0.25 s per projectile fired. Switching mode therefore
## carries the remaining cooldown over and can never raise the rate of fire, however often the player cycles.
## The first shot after a quiet spell comes out on the very tick the trigger is pressed.
##
## With a `capacitor` (M2-T14) every projectile also has to be paid for: a shot that cannot be paid is simply not
## fired, and the cooldown and the muzzle turn stay as they were, so the shot comes out on the first tick the
## capacitor can cover it. Without one (`null`, the default here) fire is unlimited, as in M1.

enum Mode { ALTERNATING, LINKED }

const MUZZLE_COUNT: int = 2
const ALTERNATING_INTERVAL_S: float = 0.25
const LINKED_INTERVAL_S: float = 0.5
const MODE_NAMES: Array[StringName] = [&"alternating", &"linked"]
## Slack for the comparison with the ready time: a clock summed from 1/60 s ticks reaches 0.25 s a few ulps short.
const TIME_EPSILON_S: float = 1e-6

var mode: Mode = Mode.ALTERNATING
## Energy store the shots are paid from; null = unlimited. `PulseCannon` gives its gate one.
var capacitor: WeaponCapacitor = null

# Sim time at which the next shot is allowed; -INF means never fired.
var _ready_at_s: float = -INF
# Which muzzle the next ALTERNATING shot uses. LINKED volleys leave it alone.
var _next_alternating: int = 0


## Next mode in the list, wrapping (ALTERNATING -> LINKED -> ALTERNATING). Does not touch the cooldown.
func cycle_mode() -> void:
	mode = ((int(mode) + 1) % MODE_NAMES.size()) as Mode


## Muzzle indices to fire on this tick (empty when the trigger is up or the cannon is still cooling down). Call it
## once per physics tick with the current sim time and whether the fire button is held.
func update(now_s: float, trigger_held: bool) -> Array[int]:
	var fired: Array[int] = []
	_ready_at_s = _clamped_ready_at(now_s)
	if capacitor != null:
		capacitor.advance(now_s)  # recharges while the trigger is up, and after a clock reset
	if not trigger_held or now_s + TIME_EPSILON_S < _ready_at_s:
		return fired
	var projectiles: int = MUZZLE_COUNT if mode == Mode.LINKED else 1
	if capacitor != null and not capacitor.spend(projectiles, now_s):
		return fired
	if mode == Mode.LINKED:
		for muzzle: int in MUZZLE_COUNT:
			fired.append(muzzle)
		_ready_at_s = now_s + LINKED_INTERVAL_S
	else:
		fired.append(_next_alternating)
		_next_alternating = (_next_alternating + 1) % MUZZLE_COUNT
		_ready_at_s = now_s + ALTERNATING_INTERVAL_S
	return fired


## Seconds until the next shot is allowed, 0 when the cannon is ready.
func cooldown_remaining(now_s: float) -> float:
	return maxf(0.0, _clamped_ready_at(now_s) - now_s)


## Forget the cooldown and the muzzle turn, and refill the capacitor (respawn).
func reset() -> void:
	_ready_at_s = -INF
	_next_alternating = 0
	if capacitor != null:
		capacitor.refill()


static func mode_name(m: Mode) -> StringName:
	return MODE_NAMES[m]


## The mode called `mode_text`; anything unknown is `ALTERNATING`.
static func mode_from_name(mode_text: StringName) -> Mode:
	var index: int = MODE_NAMES.find(mode_text)
	return (index if index >= 0 else Mode.ALTERNATING) as Mode


# The cooldown never exceeds the longest interval. That is a no-op while the clock only runs forward, and it stops
# the cannon sticking if the clock is ever reset to an earlier time (`SimClock.reset`, a respawn). `update` stores
# the clamped value, so the wait ends one interval after the reset instead of sliding away with the clock.
func _clamped_ready_at(now_s: float) -> float:
	return minf(_ready_at_s, now_s + LINKED_INTERVAL_S)
