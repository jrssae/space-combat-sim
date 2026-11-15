class_name BotTrip
extends RefCounted
## One maintenance bot's trip out of the cargo bay and back (M7-T35): an ordered list of steps whose second half mirrors the
## first, so a bot called home at any point turns round where it is and retraces its way to the bay. Pure data; `BotCrewMotion`
## flies it and `BotTripPlanner` builds it.
##
## Steps are dictionaries with a `kind`:
## - `FLY`: along `route` (a `BotRoute`) in `frame` at up to `speed` m/s, `up` the side away from the hull (in that frame). Drum
##   routes are drawn in the landing plane: the motion turns them by the drum angle it landed at.
## - `TRANSIT`: a straight run from `from` (in `from_frame`) to `to` (in `to_frame`) at up to `speed`, `accel` m/s^2; the ends are
##   placed again each tick, so the moving jumpgate is met where it is.
## - `SPIN_UP` / `SPIN_DOWN`: getting on and off the turning drum at `radius` and station `z`: from a hold point under the drum, the
##   bot's turn rate ramps to the drum's (and back); `psi` is the drum angle to land at (NAN: wherever the ramp ends).
## - `HOLD`: `seconds` in place. `WORK`: in place until the crew says the job is done (`area`, the repair area, or -1).

enum Kind { FLY, TRANSIT, SPIN_UP, SPIN_DOWN, HOLD, WORK }
enum Frame { STATION, DRUM, GATE }

## What the trip is for, for the console: the area's name and whether it is a repair.
var label: String = ""
var repair: bool = false
var steps: Array[Dictionary] = []
## The middle step (the work or the far hold); steps after it are the way home.
var middle: int = 0


## A trip of `out` steps, then `centre`, then `out` mirrored back.
static func symmetric(p_label: String, out: Array[Dictionary], centre: Dictionary, p_repair: bool = false) -> BotTrip:
	var trip := BotTrip.new()
	trip.label = p_label
	trip.repair = p_repair
	trip.steps.append_array(out)
	trip.middle = trip.steps.size()
	trip.steps.append(centre)
	for i: int in range(out.size() - 1, -1, -1):
		trip.steps.append(mirrored(out[i]))
	return trip


## The step flown the other way.
static func mirrored(step: Dictionary) -> Dictionary:
	var back: Dictionary = step.duplicate()
	match int(step["kind"]):
		Kind.FLY:
			back["route"] = (step["route"] as BotRoute).reversed()
		Kind.TRANSIT:
			back["from"] = step["to"]
			back["from_frame"] = step["to_frame"]
			back["to"] = step["from"]
			back["to_frame"] = step["from_frame"]
		Kind.SPIN_UP:
			back["kind"] = Kind.SPIN_DOWN
		Kind.SPIN_DOWN:
			back["kind"] = Kind.SPIN_UP
	return back


static func fly(route: BotRoute, frame: Frame, speed: float, up: Vector3 = Vector3.UP) -> Dictionary:
	return {"kind": Kind.FLY, "route": route, "frame": frame, "speed": speed, "up": up}


static func transit(from: Vector3, from_frame: Frame, to: Vector3, to_frame: Frame, speed: float, accel: float) -> Dictionary:
	return {"kind": Kind.TRANSIT, "from": from, "from_frame": from_frame, "to": to, "to_frame": to_frame, "speed": speed,
			"accel": accel}


static func spin_up(radius: float, z: float, psi: float = NAN) -> Dictionary:
	return {"kind": Kind.SPIN_UP, "radius": radius, "z": z, "psi": psi}


static func hold(seconds: float) -> Dictionary:
	return {"kind": Kind.HOLD, "seconds": seconds}


static func work(area: int) -> Dictionary:
	return {"kind": Kind.WORK, "area": area}


## The step a bot called home from step `i` goes on with: the mirror of a flight (taken up where it is), past the mirror of a
## stop; -1 when it is already on its way home.
func home_step(i: int) -> int:
	if i > middle:
		return -1
	if i == middle:
		return middle + 1
	var mirror: int = steps.size() - 1 - i
	match int(steps[i]["kind"]):
		Kind.FLY, Kind.TRANSIT, Kind.SPIN_UP:
			return mirror
	return mirror + 1
