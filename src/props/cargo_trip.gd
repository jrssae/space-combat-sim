class_name CargoTrip
extends RefCounted
## One cargo pod's way between a Saturn at the cargo bay's hold point and the bay's back wall (M7-T30), in the station's frame:
## the path the pod's centre takes, where each of its bots holds it, and the routes the bots fly empty. Built by
## `CargoFerryPlan.for_freighter`; pure.
##
## The pod lifts straight off the hull (outboard), slides aft past the stern, eases onto the bay's centre line and goes in through
## the back wall. A tank turns onto its side on the way, before the bay's mouth, so it fits the opening. A long pod has two bots
## (front and back), a short one one; a bot whose end of the pod is boxed in on the hull takes hold after the lift instead.

## Pod centre path, metres along it: 0 on the hull, `carry.length_m` behind the bay's back wall.
var carry: BotRoute = null
var pod_name: String = ""
## The pod's box size in its own frame (before any turn), and its orientation on the hull.
var size: Vector3 = Vector3.ONE
var hull_basis: Basis = Basis.IDENTITY
## Whether it turns onto its side, and the stretch (station z of its centre) over which it turns.
var roll: bool = false
var roll_from_z: float = 0.0
var roll_to_z: float = 0.0
## Where the lift off the hull ends, and the last point at which its bots may let it go (past it they carry on into the bay).
var unberth_s: float = 0.0
var commit_s: float = 0.0
## The corners of its way off the hull, where it stops before going on.
var stops := PackedFloat64Array()
## Each bot's place relative to the pod's centre (0 at the end toward the bay, 1 at the far end), where along the path it takes
## hold, and its route from the bay's back wall to that place.
var offsets: Array[Vector3] = []
var grab_s := PackedFloat64Array()
var out_routes: Array[BotRoute] = []
## The bay's back wall (station z) and how far a bot sinks into it to be hidden.
var wall_z: float = 0.0
var sink_m: float = 5.0


func bot_count() -> int:
	return offsets.size()


func centre_at(s: float) -> Vector3:
	return carry.point_at(s)


## The pod's pose at `s`: its centre on the path, turned onto its side by the roll's progress there.
func pose_at(s: float) -> Transform3D:
	var at: Vector3 = carry.point_at(s)
	return Transform3D(hull_basis * Basis(Vector3.BACK, roll_angle(at.z)), at)


## How far the pod has turned onto its side with its centre at station z `z`, radians.
func roll_angle(z: float) -> float:
	if not roll or roll_to_z <= roll_from_z:
		return 0.0
	var t: float = clampf((z - roll_from_z) / (roll_to_z - roll_from_z), 0.0, 1.0)
	return PI * 0.5 * t * t * (3.0 - 2.0 * t)


## Where bot `k` holds the pod with the pod at `s`.
func bot_position(k: int, s: float) -> Vector3:
	return carry.point_at(s) + offsets[k]


## The pod's half height (station up) at `s`, as it turns.
func half_height_at(s: float) -> float:
	var a: float = roll_angle(carry.point_at(s).z)
	return absf(cos(a)) * size.y * 0.5 + absf(sin(a)) * size.x * 0.5


## The way home for bot `k` letting go of the pod at `s` (fighting started): a bot at the bay's end follows the pod's own path on
## into the wall; one at the far end first rises over the pod. Points from where it is to inside the wall.
func escape_points(k: int, s: float) -> PackedVector3Array:
	var bay_points := PackedVector3Array()
	var start: Vector3 = bot_position(0, s)
	bay_points.append(start)
	var step: float = 25.0
	var at: float = s + step
	while at < carry.length_m:
		var p: Vector3 = carry.point_at(at) + offsets[0]
		bay_points.append(p)
		if p.z >= wall_z + sink_m:
			break
		at += step
	if bay_points[bay_points.size() - 1].z < wall_z + sink_m:
		var last: Vector3 = bay_points[bay_points.size() - 1]
		bay_points.append(Vector3(last.x, last.y, wall_z + sink_m))
	if k == 0:
		return bay_points
	# The far end: up over the pod, along it, and down onto the bay end's way in.
	var rise: Vector3 = Vector3.UP * (half_height_at(s) + CargoFerryPlan.STANDOFF_M + 2.0)
	var mine: Vector3 = bot_position(k, s)
	var out := PackedVector3Array([mine, mine + rise, start + rise])
	for i: int in range(1, bay_points.size()):
		out.append(bay_points[i])
	return out
