class_name ReferenceFrame
extends RefCounted
## What the player's speed is read against (M6-T08, D67, Q4 to Q6). Pure: its shell (`FlightReference`) reads the candidates
## from the World each tick and hands them in; this class picks one and says where it is, how fast it moves and what it falls
## with, all in the local frame, and the ship's altitude above the nearest body.
##
## The pick (Q6): the reference the mission sets, if it names one of the candidates; else the nearest place (the station, a
## gate) whose broadcast range holds the ship, a place staying the reference a tenth beyond its range so the pick does not
## flicker at the edge; else the dominant body (the strongest pull at the ship); else none, and the ship reads its speed
## against the World's anchor.
##
## Against a place the rest velocity is the place's. Against a planet or moon it is the circular orbit's velocity at the ship's
## position (Q4, Q5): prograde in the plane of the ship's own motion about the body, at the speed the pull there holds a circle
## at, so a ship in a steady orbit reads about 0, the 9 999 m/s ceiling sits on top of the orbit, and the brake settles the ship
## into that circle instead of stopping it against the body's centre. What a circular orbit falls with at the ship is the pull
## the ship itself feels there, so the brake's feed-forward is the ship's own pull (`ship_pull`).

enum Kind { NONE, PLACE, BODY }

## A place stays the reference until the ship is this share beyond its broadcast range (the far dots' tenth).
const HYSTERESIS: float = 0.1
## Below this tangential speed against a body, m/s, the ship's motion names no orbit plane: the body's equator is taken.
const PLANE_MIN_MPS: float = 1.0


## One thing the reference may be this tick, as the shell reads it: local positions and velocities, World frame.
class Candidate:
	extends RefCounted
	var id: StringName = &""
	## What the HUD shows beside `REF`.
	var label: String = ""
	var kind: Kind = Kind.PLACE
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	## What the reference falls with in the local frame (a place); a body's is the ship's own pull.
	var accel: Vector3 = Vector3.ZERO
	## A place's broadcast range, m.
	var broadcast_m: float = 0.0
	## A body's radius and atmosphere's top above it, m, and its pull at the ship (the zone rule's), m/s^2.
	var radius_m: float = 0.0
	var atmosphere_top_m: float = 0.0
	var pull: Vector3 = Vector3.ZERO

	static func place(p_id: StringName, p_label: String, p_position: Vector3, p_velocity: Vector3, p_accel: Vector3,
			p_broadcast_m: float) -> Candidate:
		var c := Candidate.new()
		c.id = p_id
		c.label = p_label
		c.kind = Kind.PLACE
		c.position = p_position
		c.velocity = p_velocity
		c.accel = p_accel
		c.broadcast_m = p_broadcast_m
		return c

	static func body(p_id: StringName, p_label: String, p_position: Vector3, p_velocity: Vector3, p_radius_m: float,
			p_atmosphere_top_m: float, p_pull: Vector3) -> Candidate:
		var c := Candidate.new()
		c.id = p_id
		c.label = p_label
		c.kind = Kind.BODY
		c.position = p_position
		c.velocity = p_velocity
		c.radius_m = p_radius_m
		c.atmosphere_top_m = p_atmosphere_top_m
		c.pull = p_pull
		return c


## This tick's reference: what it is, where it is, the velocity a speed is read against and what it falls with.
var kind: Kind = Kind.NONE
var id: StringName = &""
var label: String = ""
var position: Vector3 = Vector3.ZERO
var rest_velocity: Vector3 = Vector3.ZERO
var rest_accel: Vector3 = Vector3.ZERO
## The ship's altitude above the body it is near, m, and that body's name; NAN and "" when no body is near (the altitude
## rule: a body is the reference, or the ship is within `altitude_radii` of its radii from its surface).
var altitude_m: float = NAN
var altitude_body: String = ""


## Picks this tick's reference for a ship at `ship_position` moving at `ship_velocity`, from `places`, the dominant `body`
## (null for none) and the `mission_id` (empty for none), and works out its rest. `ship_pull` is the pull the ship feels here,
## local frame (a body reference's feed-forward); `altitude_radii` is the altitude rule's reach.
func update(ship_position: Vector3, ship_velocity: Vector3, ship_pull: Vector3, places: Array[Candidate], body: Candidate,
		mission_id: StringName = &"", altitude_radii: float = 1.0) -> void:
	var chosen: Candidate = pick(id, mission_id, places, body, ship_position)
	altitude_m = NAN
	altitude_body = ""
	if body != null:
		var height: float = altitude_over(body, ship_position)
		if (chosen == body) or height <= body.radius_m * altitude_radii:
			altitude_m = height
			altitude_body = body.label
	if chosen == null:
		kind = Kind.NONE
		id = &""
		label = ""
		position = Vector3.ZERO
		rest_velocity = Vector3.ZERO
		rest_accel = Vector3.ZERO
		return
	kind = chosen.kind
	id = chosen.id
	label = chosen.label
	position = chosen.position
	if chosen.kind == Kind.BODY:
		rest_velocity = chosen.velocity + orbit_velocity(ship_position - chosen.position, ship_velocity - chosen.velocity,
				chosen.pull.length())
		rest_accel = ship_pull
		if chosen != body:
			altitude_m = altitude_over(chosen, ship_position)
			altitude_body = chosen.label
	else:
		rest_velocity = chosen.velocity
		rest_accel = chosen.accel


## Q6's pick: the mission's reference, else the nearest place whose range holds the ship (with the hysteresis for `current`),
## else `body`; null for none.
static func pick(current: StringName, mission_id: StringName, places: Array[Candidate], body: Candidate,
		ship_position: Vector3) -> Candidate:
	if mission_id != &"":
		if body != null and body.id == mission_id:
			return body
		for place: Candidate in places:
			if place.id == mission_id:
				return place
	var best: Candidate = null
	var best_distance: float = INF
	for place: Candidate in places:
		var distance: float = ship_position.distance_to(place.position)
		if not holds(place, distance, place.id == current):
			continue
		if distance < best_distance:
			best = place
			best_distance = distance
	return best if best != null else body


## Whether a place's broadcast holds a ship `distance_m` from it: within its range, or a tenth beyond while it is the reference.
static func holds(place: Candidate, distance_m: float, is_current: bool) -> bool:
	if place.broadcast_m <= 0.0:
		return false
	var reach: float = place.broadcast_m * (1.0 + HYSTERESIS) if is_current else place.broadcast_m
	return distance_m <= reach


## The circular orbit's velocity against a body at `offset` from its centre, for a ship moving at `relative_velocity` against
## it: prograde in the plane of that motion, at `sqrt(pull * r)`. A ship with almost no motion across the line to the centre
## names no plane, so it gets the body's equator, eastward (the game's up is north).
static func orbit_velocity(offset: Vector3, relative_velocity: Vector3, pull_mps2: float) -> Vector3:
	var r: float = offset.length()
	if r <= 0.0 or pull_mps2 <= 0.0:
		return Vector3.ZERO
	var out: Vector3 = offset / r
	var across: Vector3 = relative_velocity - out * relative_velocity.dot(out)
	var prograde: Vector3
	if across.length() >= PLANE_MIN_MPS:
		prograde = across.normalized()
	else:
		var axis: Vector3 = Vector3.UP if absf(out.y) < 0.99 else Vector3.RIGHT
		prograde = axis.cross(out).normalized()
	return prograde * sqrt(pull_mps2 * r)


## A ship's height above a body's surface, m.
static func altitude_over(body: Candidate, ship_position: Vector3) -> float:
	return ship_position.distance_to(body.position) - body.radius_m


## The ship's speed against the reference, m/s.
func speed_of(ship_velocity: Vector3) -> float:
	return (ship_velocity - rest_velocity).length()


## Whether there is a reference this tick.
func is_set() -> bool:
	return kind != Kind.NONE
