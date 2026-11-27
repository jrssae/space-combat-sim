class_name DockingPlan
extends RefCounted
## The lanes civilian traffic flies at the station (M7-T10, Q8 as refined), from the station's bay hardpoints: pure, in the
## station's frame. Each lane is a list of waypoints `{at, hold_s, face, spin}` for a `Route.lane`:
##
## - **Main docking bay** (in the turning drum): in along the approach, with the drum's turn matched (`spin`, about the nose)
##   from the last approach point on, through the mouth and the inner doors into the black void behind them, where the ship
##   leaves the world once they shut (M7-T25, `StationAirlock`); out is the same lane backwards.
## - **Cargo bay** (on the frame): a freighter flies nose first to a turning point short of the hold point; the leg from
##   there to the hold point asks for its nose away from the station, so it turns where it is and then backs in; it waits,
##   and leaves nose first the way it came. The station's maintenance bots carry its cargo meanwhile (M7-T30); the traffic sends
##   it on when they are done.

const FREIGHTER_TYPE: StringName = &"saturn_3_freighter"
## How far short of the hold point a freighter turns its stern to the bay, metres.
const TURN_SHORT_M: float = 700.0
## How far short of the void's back wall (the manifest's `main_docking_bay_airlock`) a docking lane ends, and an undocking one
## starts, metres: the longest tunnel hull lies wholly behind the inner doors there, with room before the wall for a hull that
## brakes late.
const AIRLOCK_SHORT_M: float = 145.0
## A docking ship stops at its lane's end, in the void behind the inner doors, and waits there until they have shut (M7-T25).
const DOCKED_HOLD_S: float = 120.0
## Seconds a freighter rests at its turning point (so it slows into it), and the longest it waits at the hold point (the traffic
## sends it on as soon as the bots have carried its cargo).
const TURN_STOP_S: float = 1.0
const WAIT_S: float = 1800.0
## Lane speeds, m/s: the docking lane (through a 34 m tunnel) and the freighter's (a Saturn brakes at a few hundredths of a g).
const DOCK_CRUISE_MPS: float = 45.0
## From the approach's far point in, a docking ship flies slower (M7-T25): it stops in the void behind the inner doors, and a
## hull's brakes are weaker than the lane's braking plan assumes.
const DOCK_INNER_MPS: float = 20.0
## The docking lane's index of the approach's far point, where the slower inner leg starts.
const DOCK_INNER_FROM: int = 0
const FREIGHTER_CRUISE_MPS: float = 20.0

var valid: bool = false
var error: String = ""
## The drum's turn as a vector in the station's frame, rad/s.
var spin: Vector3 = Vector3.ZERO
## The tunnel's mouth and where a ship is at the inner airlock (`AIRLOCK_SHORT_M` from its wall), in the station's frame.
var mouth: Vector3 = Vector3.ZERO
var airlock: Vector3 = Vector3.ZERO
var dock_in: Array[Dictionary] = []
var dock_out: Array[Dictionary] = []
## The freighter's lane, and which of its waypoints is the hold at the bay.
var freighter: Array[Dictionary] = []
var freighter_hold_index: int = -1
## The unit vector a held freighter's nose points along (away from the bay).
var away: Vector3 = Vector3.FORWARD


## Hulls that fit the docking bay's mouth (M7-T25: a band 73 x 17 m across a core 45 x 30 m) with room to spare, lying square in it;
## every other civilian holds outside (the Saturns never enter). The catalogue's `docking: tunnel` entries, in its order; a
## `traffic_only` one (the Centauri shuttle, the Minbari Flyer, M10 Q99) only for a scenario whose encounter `pooled` list it.
static func tunnel_types(pooled: Dictionary = {}) -> Array[StringName]:
	return ShipCatalog.docking_types("tunnel", pooled)


## Whether a hull of `type` may fly the docking lane when it is named, whatever the scenario pools.
static func fits_tunnel(type: StringName) -> bool:
	return ShipCatalog.entry_text(type, "docking") == "tunnel"


## Every Saturn that comes to the cargo bay (M7-T30: each by its own pods or tanks): the catalogue's `docking: cargo_bay` entries.
static func freighter_types() -> Array[StringName]:
	return ShipCatalog.types_where("docking", "cargo_bay")


## The plan from the station's hardpoints. The main docking bay's points are given in the drum's frame (they lie on its
## axis, so its turn does not move them): `drum_origin` is the drum's pivot in the station's frame.
static func build(hardpoints: StationHardpoints, drum_origin: Vector3) -> DockingPlan:
	var plan := DockingPlan.new()
	var dock: Dictionary = hardpoints.main_docking_bay
	var cargo: Dictionary = hardpoints.cargo_bay
	for key: String in ["main_docking_bay_approach", "main_docking_bay_mouth", "main_docking_bay_airlock"]:
		if not dock.has(key):
			plan.error = "the main docking bay has no %s" % key
			return plan
	for key: String in ["cargo_bay_approach", "cargo_bay_hold", "cargo_bay_hold_forward"]:
		if not cargo.has(key):
			plan.error = "the cargo bay has no %s" % key
			return plan
	var approach: Array = dock["main_docking_bay_approach"]
	var cargo_approach: Array = cargo["cargo_bay_approach"]
	if approach.size() < 2 or cargo_approach.is_empty():
		plan.error = "a bay's approach is too short"
		return plan
	var axis: Vector3 = dock.get("spin_axis", Vector3.BACK)
	plan.spin = axis.normalized() * float(dock.get("spin_rad_s", hardpoints.spin_rad_s))
	var far: Vector3 = (approach[0] as Vector3) + drum_origin
	var near: Vector3 = (approach[approach.size() - 1] as Vector3) + drum_origin
	var mouth: Vector3 = (dock["main_docking_bay_mouth"] as Vector3) + drum_origin
	# The lane ends a hull's half length short of the airlock's wall.
	var airlock: Vector3 = (dock["main_docking_bay_airlock"] as Vector3) + drum_origin
	airlock += (mouth - airlock).normalized() * AIRLOCK_SHORT_M
	plan.mouth = mouth
	plan.airlock = airlock
	plan.dock_in = [_point(far), _point(near, 0.0, Vector3.ZERO, plan.spin), _point(mouth, 0.0, Vector3.ZERO, plan.spin),
			_point(airlock, DOCKED_HOLD_S, Vector3.ZERO, plan.spin)]
	plan.dock_out = [_point(mouth, 0.0, Vector3.ZERO, plan.spin), _point(near, 0.0, Vector3.ZERO, plan.spin), _point(far)]
	var hold: Vector3 = cargo["cargo_bay_hold"]
	var toward: Vector3 = (cargo["cargo_bay_hold_forward"] as Vector3).normalized()
	plan.away = -toward
	var out: Vector3 = cargo_approach[0]
	var turn: Vector3 = hold - toward * TURN_SHORT_M
	plan.freighter = [_point(out), _point(turn, TURN_STOP_S), _point(hold, WAIT_S, plan.away), _point(out)]
	plan.freighter_hold_index = 2
	plan.valid = true
	return plan


## A lane's waypoints as a `Route.lane` in the World, the station at `station_xform`.
static func route_of(lane: Array[Dictionary], station_xform: Transform3D, world: WorldFrame, cruise_mps: float, name: String) -> Route:
	var route := Route.new()
	route.name = name
	route.pace = Route.PACE_NONE
	route.lane = true
	route.cruise_mps = cruise_mps
	for w: Dictionary in lane:
		route.add_lane(world.to_universe(station_xform * (w["at"] as Vector3)), float(w["hold_s"]),
				station_xform.basis * (w["face"] as Vector3), station_xform.basis * (w["spin"] as Vector3))
	return route


static func _point(at: Vector3, hold_s: float = 0.0, face: Vector3 = Vector3.ZERO, spin_rad_s: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"at": at, "hold_s": hold_s, "face": face, "spin": spin_rad_s}
