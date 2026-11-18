class_name CarrierTactics
extends RefCounted
## What a weaponless carrier decides in a raid (M12-T19, Q30; the retreat rules of M8-T08, D83): it hangs back at a
## stand-off and shows an attacker its stern; its fighters go home when few of the raid are left, or one by one when badly
## hurt; it flees when it has taken its share of damage, when its raid is over or when every surviving fighter has docked.
## Fleeing is a jump through its own point once its drive has recharged, else a run for the jumpgate. Pure: numbers in, a
## decision out; `CarrierJumps` flies it.

## Options a raid's `carrier` data may set, with their defaults. A faction's doctrine (`CapitalData.doctrine`) comes
## between the two.
const DEFAULTS: Dictionary = {
	"arrival": "beside",  # how its fighters come in: "docked" on its cradles, or "beside" it out of its point (Q29)
	"standoff_m": 2500.0,  # it keeps this far from the nearest enemy
	"recall_left": 3,  # its fighters all go home once this few of the raid are left in the fight (D83)
	"fighter_return_hull": 0.2,  # a fighter under this share of its hull goes home alone (D83)
	"retreat_hull": 0.5,  # it flees once its hull is down to this share (D83)
	"wait_s": 90.0,  # called home, fighters not docked within this long are left behind (Q27, Q30)
	"raid_s": 0.0,  # the raid is over after this long; 0: no time limit
	"flee_mps": 60.0,  # its speed while it runs with its drive still recharging
}
const ARRIVAL_DOCKED: StringName = &"docked"
const ARRIVAL_BESIDE: StringName = &"beside"
## It starts to move off this share of the stand-off before an enemy reaches it, and is at full speed at that share inside.
const EASE_SHARE: float = 0.25

## Why a carrier flees (`flee_reason`); empty while it stays.
const STAYS: StringName = &""
const FLEE_HURT: StringName = &"hurt"
const FLEE_RAID_OVER: StringName = &"raid_over"
const FLEE_ALL_DOCKED: StringName = &"all_docked"
## What a fleeing carrier does now (`flee_move`).
const MOVE_WAIT: StringName = &"wait"
const MOVE_JUMP: StringName = &"jump"
const MOVE_GATE: StringName = &"gate"
const MOVE_RUN: StringName = &"run"
## A carrier running for a gate from beside or behind it keeps this many mouth radii off its axis until it is in front,
## and counts as on the run-in within `GATE_AXIS_RADII` of the axis.
const GATE_CLEAR_RADII: float = 2.5
const GATE_AXIS_RADII: float = 0.4


## The raid's options: `given` over the faction's `doctrine` over the defaults, numbers kept in range. Unknown keys are
## kept for the caller.
static func options(given: Dictionary, doctrine: Dictionary = {}) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	for layer: Dictionary in [doctrine, given]:
		for key: Variant in layer:
			out[key] = layer[key]
	out["arrival"] = String(ARRIVAL_DOCKED) if String(out["arrival"]) == String(ARRIVAL_DOCKED) else String(ARRIVAL_BESIDE)
	out["standoff_m"] = maxf(float(out["standoff_m"]), 0.0)
	out["recall_left"] = maxi(int(out["recall_left"]), 0)
	out["retreat_hull"] = clampf(float(out["retreat_hull"]), 0.0, 1.0)
	out["wait_s"] = maxf(float(out["wait_s"]), 0.0)
	out["raid_s"] = maxf(float(out["raid_s"]), 0.0)
	out["fighter_return_hull"] = clampf(float(out["fighter_return_hull"]), 0.0, 1.0)
	out["flee_mps"] = maxf(float(out["flee_mps"]), 0.0)
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


## Whether a raid's fighters all go home (D83): only `recall_left` of them are left in the fight. A raid that came with no
## more than that is not called back on arrival: it goes home at its first loss.
static func recall_all(brought: int, fighting: int, recall_left: int) -> bool:
	return fighting > 0 and fighting <= recall_left and fighting < brought


## Whether one fighter goes home alone (D83): its hull is under its share.
static func fighter_goes_home(hull_fraction: float, fighter_return_hull: float) -> bool:
	return hull_fraction < fighter_return_hull


## Whether the raid is over: ended by its script, or past its time limit.
static func raid_over(ended: bool, elapsed_s: float, raid_s: float) -> bool:
	return ended or (raid_s > 0.0 and elapsed_s >= raid_s)


## Why the carrier flees now (D83), or `STAYS`: it has taken its share of damage, its raid is over, or every surviving
## fighter of the `brought` has docked (none `fighting`, none `returning`).
static func flee_reason(hull_fraction: float, retreat_hull: float, over: bool, brought: int, fighting: int,
		returning: int) -> StringName:
	if hull_fraction <= retreat_hull:
		return FLEE_HURT
	if over:
		return FLEE_RAID_OVER
	if brought > 0 and fighting + returning <= 0:
		return FLEE_ALL_DOCKED
	return STAYS


## Whether the carrier stops waiting for its fighters: nobody is still on the way back, or their time is up.
static func should_leave(returning: int, waited_s: float, wait_s: float) -> bool:
	return returning <= 0 or waited_s >= wait_s


## What a fleeing carrier does now (D83): with its drive recharged it waits for its fighters, up to their limit, and jumps
## through its own point; with the drive still recharging it runs for the jumpgate, which needs no drive, or with no gate
## away from the enemy until the drive is ready.
static func flee_move(drive_ready: bool, has_gate: bool, returning: int, waited_s: float, wait_s: float) -> StringName:
	if drive_ready:
		return MOVE_JUMP if should_leave(returning, waited_s, wait_s) else MOVE_WAIT
	return MOVE_GATE if has_gate else MOVE_RUN


## Where a carrier running for a gate steers now, in the gate's frame (the mouth at the origin, ships leave along +Z from
## `departure_z` in front of it): out round the gate's side when it is beside or behind the mouth, onto the axis in front,
## then through the mouth's centre.
static func gate_run_target(local: Vector3, departure_z: float, radius_m: float) -> Vector3:
	var lateral := Vector2(local.x, local.y)
	var off_axis_m: float = lateral.length()
	if local.z < 0.0 and off_axis_m <= GATE_AXIS_RADII * radius_m:
		return Vector3(0.0, 0.0, radius_m)
	if local.z <= 0.5 * departure_z:
		return Vector3(0.0, 0.0, departure_z)
	var side: Vector2 = lateral / off_axis_m if off_axis_m > 1.0 else Vector2.RIGHT
	var clear_m: float = GATE_CLEAR_RADII * radius_m
	if off_axis_m < 0.9 * clear_m:
		return Vector3(side.x * clear_m, side.y * clear_m, local.z)
	return Vector3(side.x * clear_m, side.y * clear_m, departure_z)


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
