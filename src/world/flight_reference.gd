class_name FlightReference
extends Node
## The player's reference, each tick (M6-T08, D67, Q6): the shell of the pure `ReferenceFrame`. It reads the candidates from
## the World (the place the World falls with, when it is a place; the places `place_source` lists, the jumpgates; the
## dominant body from the core's sample), lets the frame pick, and hands the ship the rest its brake, assist, thrust fade and
## ceiling read the speed against. The HUD reads it too: `REF <name>`, range, closing speed, the speed against it and the
## altitude.
##
## Runs after the core's sync and the gravity sample and before the ship's own tick, so the ship flies this tick's reference.
## Rebase-safe: the reference is kept as an offset from the ship, which no rebase changes, and a velocity rebase at the end of
## a tick takes its `dv` off the rest velocity too, so the HUD's speed does not jump for the frames until the next tick.
##
## Console: provider `reference` and command `reference [auto|<id>]` (the mission's seam, by hand).

const PRIORITY: int = -5
const KM: float = 1000.0

var world: WorldFrame = null
var ship: Ship = null
## Lists the places beside the World's anchor that can be the reference: nodes with a `Targetable` child that broadcasts
## (the jumpgates). Empty when unset.
var place_source: Callable = Callable()
## The reference the mission sets (a place or body id, or a place's label), empty for Q6's own pick.
var mission_reference: StringName = &""
var frame: ReferenceFrame = ReferenceFrame.new()
## Where the reference is from the ship as of this tick's update, World axes (a rebase leaves it alone), and where it is in
## universe terms (so the HUD places it with the frame's origin of the moment it draws).
var offset: Vector3 = Vector3.ZERO
var universe_position: UniversePos = UniversePos.new()

var _console_registered: bool = false


func _init() -> void:
	name = "FlightReference"
	process_physics_priority = PRIORITY


func _ready() -> void:
	DebugConsole.registry.register_provider(&"reference", ConsoleVars.new({
		&"name": {"get": func() -> String: return frame.label, "doc": "What the speed is read against: the HUD's REF (empty: the World's anchor)"},
		&"kind": {"get": _kind_text, "doc": "none, place or body"},
		&"rest_velocity": {"get": func() -> Vector3: return frame.rest_velocity, "unit": "m/s",
				"doc": "The reference's velocity in the local frame (a body's: the circular orbit's at the ship)"},
		&"rest_accel": {"get": func() -> Vector3: return frame.rest_accel, "unit": "m/s^2",
				"doc": "What the reference falls with in the local frame (the brake's feed-forward)"},
		&"speed": {"get": speed_mps, "unit": "m/s", "doc": "The ship's speed against the reference (the HUD's speed)"},
		&"range": {"get": func() -> float: return offset.length(), "unit": "m", "doc": "Distance to the reference"},
		&"altitude": {"get": func() -> float: return frame.altitude_m, "unit": "m",
				"doc": "Height above the body the ship is near (nan when none: the altitude rule, settings.hud_altitude_radii)"},
		&"mission": {"get": func() -> StringName: return mission_reference,
				"doc": "The reference the mission (or the console) set; empty for the automatic pick"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"reference",
			"The player's reference (the HUD's REF): auto (the nearest place whose broadcast holds the ship, else the dominant body), or a place or body id (babylon5, jumpgate, epsilon_iii) as a mission sets it",
			[ConsoleArg.string_optional(&"id", null)] as Array[ConsoleArg]), _cmd_reference, self)
	_console_registered = true


func _exit_tree() -> void:
	if _console_registered:
		DebugConsole.registry.unregister_owner(self)


func _physics_process(_delta: float) -> void:
	if world != null and is_instance_valid(world) and not world.boosted.is_connected(_on_boosted):
		world.boosted.connect(_on_boosted)
	update()


# Every local velocity lost `dv` at the end of the tick: the reference's rest velocity is one of them.
func _on_boosted(dv: Vector3) -> void:
	if not frame.is_set():
		return
	frame.rest_velocity -= dv
	if ship != null and is_instance_valid(ship):
		ship.set_reference_rest(frame.rest_velocity, frame.rest_accel)


## Picks this tick's reference and hands the ship its rest. A ship with no reference reads the World's anchor.
func update() -> void:
	if ship == null or not is_instance_valid(ship) or world == null or not is_instance_valid(world):
		return
	var at: Vector3 = ship.global_position
	frame.update(at, ship.linear_velocity, world.gravity_residual(at), places(at), body_near(at), mission_reference,
			float(Settings.get_value(&"hud_altitude_radii")))
	offset = frame.position - at
	universe_position = world.to_universe(frame.position)
	if frame.is_set():
		ship.set_reference_rest(frame.rest_velocity, frame.rest_accel)
	else:
		ship.clear_reference_rest()


## The ship's speed against its reference, m/s.
func speed_mps() -> float:
	if ship == null or not is_instance_valid(ship):
		return 0.0
	return frame.speed_of(ship.linear_velocity) if frame.is_set() else ship.speed_against_rest()


## The places that can be the reference for a ship at `at`: the place the World rides when it is one (where it stands from the
## scenario's origin, M6-T09), and the broadcasting nodes of `place_source`, each moving with the anchor.
func places(at: Vector3) -> Array[ReferenceFrame.Candidate]:
	var out: Array[ReferenceFrame.Candidate] = []
	var rest_v: Vector3 = world.rest_velocity()
	var rest_a: Vector3 = world.rest_accel()
	var system: StarSystem = world.star_system
	if system != null and system.place_ids.has(world.anchor_name):
		out.append(ReferenceFrame.Candidate.place(world.anchor_name, system.display_name(world.anchor_name).to_upper(),
				world.universe_to_local(UniversePos.new(-world.anchor_offset[0], -world.anchor_offset[1], -world.anchor_offset[2],
						world.origin.system_id)), rest_v, rest_a,
				float(Settings.get_value(&"reference_place_range_km")) * KM))
	if place_source.is_valid():
		for node: Variant in place_source.call():
			var place := node as Node3D
			if place == null or not is_instance_valid(place) or not place.is_inside_tree():
				continue
			var marker := place.get_node_or_null(^"Targetable") as Targetable
			if marker == null or marker.broadcast_range_m <= 0.0:
				continue
			out.append(ReferenceFrame.Candidate.place(StringName(marker.display_name.to_lower()),
					marker.display_name.to_upper(), place.global_position, rest_v, rest_a, marker.broadcast_range_m))
	if mission_reference != &"" and system != null and system.place_ids.has(mission_reference) \
			and not out.any(func(c: ReferenceFrame.Candidate) -> bool: return c.id == mission_reference):
		var state: PackedFloat64Array = world.body_state(mission_reference)
		if state.size() == 6:
			out.append(ReferenceFrame.Candidate.place(mission_reference, system.display_name(mission_reference).to_upper(),
					Vector3(state[0], state[1], state[2]), Vector3(state[3], state[4], state[5]), rest_a, 0.0))
	return out


## The body that pulls hardest at `at`, or the mission's body when it names one; null where none does.
func body_near(at: Vector3) -> ReferenceFrame.Candidate:
	var system: StarSystem = world.star_system
	if system == null:
		return null
	var found: Dictionary = world.reference_body(at)
	if found.is_empty() or (mission_reference != &"" and system.body_ids.has(mission_reference) \
			and found["id"] != mission_reference):
		return _mission_body(at)
	var id: StringName = found["id"]
	var info: Dictionary = system.info(id)
	if info.is_empty():
		return null
	var p: PackedFloat64Array = found["position"]
	var v: PackedFloat64Array = found["velocity"]
	return ReferenceFrame.Candidate.body(id, system.display_name(id).to_upper(), Vector3(p[0], p[1], p[2]),
			Vector3(v[0], v[1], v[2]), float(info["radius_m"]), float(info["atmosphere_top_m"]), found["pull"])


# The mission's body when nothing pulls toward it here: its place and velocity, and no pull (so no orbit to read against).
func _mission_body(_at: Vector3) -> ReferenceFrame.Candidate:
	var system: StarSystem = world.star_system
	if mission_reference == &"" or not system.body_ids.has(mission_reference):
		return null
	var state: PackedFloat64Array = world.body_state(mission_reference)
	if state.size() != 6:
		return null
	var info: Dictionary = system.info(mission_reference)
	return ReferenceFrame.Candidate.body(mission_reference, system.display_name(mission_reference).to_upper(),
			Vector3(state[0], state[1], state[2]), Vector3(state[3], state[4], state[5]), float(info["radius_m"]),
			float(info["atmosphere_top_m"]), Vector3.ZERO)


func _kind_text() -> String:
	match frame.kind:
		ReferenceFrame.Kind.PLACE:
			return "place"
		ReferenceFrame.Kind.BODY:
			return "body"
	return "none"


func _cmd_reference(args: Dictionary) -> ConsoleResult:
	var wanted: Variant = args[&"id"]
	if wanted != null:
		mission_reference = &"" if String(wanted) == "auto" else StringName(String(wanted).to_lower())
		update()
	return ConsoleResult.line("reference = %s (%s); speed %.1f m/s; range %.0f m; altitude %s" % [
			frame.label if frame.is_set() else "none (the World's anchor)", _kind_text(), speed_mps(), offset.length(),
			"-" if is_nan(frame.altitude_m) else "%.0f m" % frame.altitude_m])
