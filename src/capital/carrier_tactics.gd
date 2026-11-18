class_name CarrierTactics
extends RefCounted
## What a weaponless carrier decides in a raid (M12-T19, Q30): it hangs back at a stand-off, shows an attacker its stern,
## calls its fighters back and jumps out when it is hurt or the raid is over. Pure: numbers in, a decision out;
## `CarrierJumps` flies it.

## Options a raid's `carrier` data may set, with their defaults.
const DEFAULTS: Dictionary = {
	"arrival": "beside",  # how its fighters come in: "docked" on its cradles, or "beside" it out of its point (Q29)
	"standoff_m": 2500.0,  # it keeps this far from the nearest enemy
	"retreat_hull": 0.5,  # it calls its fighters back and leaves once its hull is under this share
	"wait_s": 45.0,  # how long it waits for its fighters before it leaves without them (Q27)
	"raid_s": 0.0,  # the raid is over after this long; 0: no time limit
	"fighter_return_hull": 0.35,  # a fighter under this share of its hull is called back alone
}
const ARRIVAL_DOCKED: StringName = &"docked"
const ARRIVAL_BESIDE: StringName = &"beside"
## It starts to move off this share of the stand-off before an enemy reaches it, and is at full speed at that share inside.
const EASE_SHARE: float = 0.25


## The raid's options: `given` over the defaults, numbers kept in range. Unknown keys are kept for the caller.
static func options(given: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	for key: Variant in given:
		out[key] = given[key]
	out["arrival"] = String(ARRIVAL_DOCKED) if String(out["arrival"]) == String(ARRIVAL_DOCKED) else String(ARRIVAL_BESIDE)
	out["standoff_m"] = maxf(float(out["standoff_m"]), 0.0)
	out["retreat_hull"] = clampf(float(out["retreat_hull"]), 0.0, 1.0)
	out["wait_s"] = maxf(float(out["wait_s"]), 0.0)
	out["raid_s"] = maxf(float(out["raid_s"]), 0.0)
	out["fighter_return_hull"] = clampf(float(out["fighter_return_hull"]), 0.0, 1.0)
	return out


## The velocity the carrier holds against the frame's rest: none while the nearest enemy (`threat`, the vector to it) is
## outside the stand-off, away from it at up to `speed_mps` once it is inside.
static func cruise(threat: Vector3, has_threat: bool, standoff_m: float, speed_mps: float) -> Vector3:
	if not has_threat or standoff_m <= 0.0:
		return Vector3.ZERO
	var distance: float = threat.length()
	var band: float = maxf(EASE_SHARE * standoff_m, 1.0)
	var push: float = clampf((standoff_m - distance) / band, 0.0, 1.0)
	if push <= 0.0 or distance < 1e-3:
		return Vector3.ZERO
	return -threat / distance * speed_mps * push


## The way the bow should point: away from an enemy inside the stand-off (its stern to the attacker), else zero (it keeps
## the heading it has).
static func heading(threat: Vector3, has_threat: bool, standoff_m: float) -> Vector3:
	if not has_threat or threat.length() >= standoff_m or threat.length() < 1e-3:
		return Vector3.ZERO
	return -threat.normalized()


## Whether the carrier calls its fighters back and leaves: hurt past its threshold, or the raid over.
static func should_recall(hull_fraction: float, retreat_hull: float, raid_over: bool) -> bool:
	return raid_over or hull_fraction < retreat_hull


## Whether the raid is over: ended by its script, past its time limit, or with no fighter left flying.
static func raid_over(ended: bool, elapsed_s: float, raid_s: float, fighters_brought: int, fighters_flying: int) -> bool:
	if ended or (raid_s > 0.0 and elapsed_s >= raid_s):
		return true
	return fighters_brought > 0 and fighters_flying == 0


## Whether the carrier leaves now: nobody is still on the way back, or it has waited long enough.
static func should_leave(returning: int, waited_s: float, wait_s: float) -> bool:
	return returning <= 0 or waited_s >= wait_s


## The turn rate the helm asks for, rad/s about each World axis: toward `wanted` from `forward`, eased near it, at most
## `rate_max` (0 with no wanted heading).
static func turn_rate(forward: Vector3, wanted: Vector3, rate_max: float, gain: float = 0.5) -> Vector3:
	if wanted.length() < 1e-3 or forward.length() < 1e-3:
		return Vector3.ZERO
	var f: Vector3 = forward.normalized()
	var w: Vector3 = wanted.normalized()
	var axis: Vector3 = f.cross(w)
	var angle: float = f.angle_to(w)
	if axis.length() < 1e-4:
		if angle < 1.0:
			return Vector3.ZERO
		axis = f.cross(Vector3.UP if absf(f.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)  # dead astern: any way round
	return axis.normalized() * minf(angle * gain, rate_max)
