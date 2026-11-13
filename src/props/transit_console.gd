class_name TransitConsole
extends RefCounted
## The console's `transit` command (M6-T22): brings a ship out of a jump vortex's funnel, or sends one down it, to look at and to
## capture: a fighter (a pooled raider, no pilot, so it coasts) or a capital (a bench cruiser stand-in) through the scene's gate or
## out of a ship-made point ahead of the player, optionally followed by a cinematic camera (`follow`) for captures and play-tests.
## Registered by `JumpgateHost`, which owns the scene's gates and console points.
##
## A debug tool (M6-T23): a capital opens its own point (it may), but a fighter's `arrive point` opens one held by nothing, which
## no fighter could in play. `carrier` shows the real way: a cruiser stand-in opens a point ahead of the player and two fighters
## come out with it (`CarrierJumps`), then it jumps back.

const ACTIONS: Array[StringName] = [&"arrive", &"depart", &"carrier", &"status"]
const WHERES: Array[StringName] = [&"gate", &"point"]
const KINDS: Array[StringName] = [&"fighter", &"capital"]
const CAMERAS: Array[StringName] = [&"none", &"follow"]
## A departing ship starts this far in front of the gate's mouth on its axis, flying in at the gate's arrival speed.
const DEPART_FROM_M: float = 1700.0
## A point opened ahead of the player sits this far ahead.
const POINT_AHEAD_M: float = 2500.0
const CAPITAL_CLASS: StringName = &"cruiser"

var host: JumpgateHost = null
var _made: int = 0
var _followed: Node3D = null  # the ship the `follow` camera watches
var _last_pose: Variant = null


func _init(p_host: JumpgateHost) -> void:
	host = p_host


func register(registry: ConsoleRegistry) -> void:
	registry.register_command(ConsoleCommand.new(&"transit",
			"Ships through a jump vortex's funnel (M6-T22), a debug tool: arrive <gate|point> [fighter|capital] [none|follow] (out of the gate's black ring once it opens, or out of a point opened 2.5 km ahead of the player: a capital opens and holds its own, a fighter's is held by nothing, which no fighter could do in play, M6-T23), depart gate [fighter|capital] [none|follow] (one flies in from 1.7 km in front of the gate and down its funnel), carrier [-] [-] [none|follow] (a cruiser stand-in opens a point 2.5 km ahead, two fighters come out with it, then it jumps back; follow watches the second fighter), status; follow holds a cinematic camera on it",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"),
			ConsoleArg.enum_optional(&"where", WHERES, &"gate"),
			ConsoleArg.enum_optional(&"kind", KINDS, &"fighter"),
			ConsoleArg.enum_optional(&"camera", CAMERAS, &"none")] as Array[ConsoleArg]), _cmd, host)


func _cmd(args: Dictionary) -> ConsoleResult:
	var main: Main = host.main
	var transits: VortexTransits = VortexTransits.attach(main.world)
	var action: StringName = StringName(args[&"action"])
	if action == &"status":
		return ConsoleResult.line("%d ships in a funnel, %d arrived, %d departed" % [transits.count(), transits.arrivals_done,
				transits.departures_done])
	var where: StringName = StringName(args[&"where"])
	var capital: bool = StringName(args[&"kind"]) == &"capital"
	var follow: bool = StringName(args.get(&"camera", &"none")) == &"follow"
	var gate: Jumpgate = host.gate()
	if where == &"gate" and gate == null:
		return ConsoleResult.failure("no jumpgate in this scenario")
	if action == &"carrier":
		return _carrier(follow)
	if action == &"depart" and where != &"gate":
		return ConsoleResult.failure("transit depart gate [fighter|capital]: only the gate takes departures from the console")
	if action == &"arrive" and where == &"gate":
		gate.request_arrival(func() -> void:
			var xform: Transform3D = gate.arrival_transform()
			var body: RigidBody3D = _make(capital, xform, gate.arrival_velocity() + main.world.rest_velocity())
			if body != null:
				gate.bring_through(body, true)
				_followed = body
				if follow:
					_play(_arrival_shot(capital)))
		return ConsoleResult.line("a %s comes out of the gate once its vortex is open" % ("capital" if capital else "fighter"))
	if action == &"arrive":
		var nose: Vector3 = -main.ship.global_basis.z
		var at: Vector3 = main.ship.global_position + nose * POINT_AHEAD_M
		var out_dir: Vector3 = (main.ship.global_basis.x - nose).normalized()  # across the player's view, a little toward it
		var body: RigidBody3D = _make(capital, Transform3D(Basis.looking_at(out_dir, main.ship.global_basis.y), at),
				out_dir * 40.0 + main.world.rest_velocity())
		if body == null:
			return ConsoleResult.failure("no free ship to bring in")
		var radius: float = _cross_radius(body)
		# A capital opens and holds its own point; a fighter's is a debug point nothing holds (M6-T23).
		var opener: Node3D = body if JumpCapability.can_open(body) else null
		var point: JumpVortex = host.console_points.open_for(main.world.to_universe(at), out_dir, radius,
				JumpVortex.Direction.ARRIVAL, true, opener)
		if point == null or not transits.begin_arrival(body, point, at, body.linear_velocity, true):
			return ConsoleResult.failure("no point to bring it through")
		_followed = body
		if follow:
			_play(_arrival_shot(capital))
		return ConsoleResult.line("a %s comes out of a %.0f m point 2.5 km ahead" % ["capital" if capital else "fighter",
				point.fit.mouth_radius_m])
	var into: Vector3 = (gate.global_basis * gate.departure_forward).normalized()
	var start: Vector3 = gate.global_transform * Vector3(0.0, 0.0, -DEPART_FROM_M)
	var body: RigidBody3D = _make(capital, Transform3D(Basis.looking_at(into, gate.global_basis.y), start),
			into * Jumpgate.ARRIVAL_SPEED_MPS + main.world.rest_velocity())
	if body == null:
		return ConsoleResult.failure("no free ship to send")
	gate.send_departure(body, _leave)
	_followed = body
	if follow:
		_play(_departure_shot(capital))
	return ConsoleResult.line("a %s flies in to depart through the gate" % ("capital" if capital else "fighter"))


# A cruiser stand-in opens a point 2.5 km ahead of the player, across its view, and two pilotless raiders come out with it.
func _carrier(follow: bool) -> ConsoleResult:
	var main: Main = host.main
	if main.ships.free_count(ShipPool.DEFAULT_TYPE) < 2:
		return ConsoleResult.failure("no two free raiders to bring in")
	var nose: Vector3 = -main.ship.global_basis.z
	var at: Vector3 = main.ship.global_position + nose * POINT_AHEAD_M
	var out_dir: Vector3 = (main.ship.global_basis.x - nose).normalized()
	var carriers: CarrierJumps = CarrierJumps.attach(main.world)
	if carriers.free_count() == 0:
		carriers.prepare(carriers.size() + 1)  # a console hitch, not play
	var run: CarrierRun = carriers.run_for(host.console_points, main.world.to_universe(at), out_dir, Factions.RAIDERS)
	if run == null:
		return ConsoleResult.failure("no carrier could open a point")
	for k: int in 2:
		var body: RigidBody3D = _make(false, Transform3D(Basis.looking_at(out_dir, main.ship.global_basis.y), at),
				run.exit_velocity)
		if body != null:
			carriers.bring_through(run, body, run.exit_velocity)
			_followed = body
	if follow:
		_play(_arrival_shot(false))
	return ConsoleResult.line("%s opens a %.0f m point 2.5 km ahead; two fighters come out with it" % [
			run.carrier.targetable.display_name, run.arrival.fit.mouth_radius_m])


# A fighter from the raider pool with no pilot (it coasts), or a cruiser stand-in holding its velocity, at `xform`.
func _make(capital: bool, xform: Transform3D, velocity: Vector3) -> RigidBody3D:
	var main: Main = host.main
	_made += 1
	var at: UniversePos = main.world.to_universe(xform.origin)
	if capital:
		if main.bench == null or main.bench.standins == null:
			return null
		return main.bench.standins.add_capital(CAPITAL_CLASS, Factions.EARTH_ALLIANCE, "TRANSIT %d" % _made, at, xform.basis,
				velocity)
	if main.ships.free_count(ShipPool.DEFAULT_TYPE) == 0:
		return null
	var placed: Combatant = main.ships.acquire(main.ships.next_name(), at, xform.basis, velocity, null)
	return placed.ship if placed != null else null


# The `follow` camera: `shot` on the rig, its actor the followed ship (`ship`), no letterbox.
func _play(shot: CinematicShot) -> void:
	if shot == null:
		return
	var main: Main = host.main
	main.camera_rig.play_shot(shot, _pose, _to_local)
	main.letterbox.shown = false


func _to_local(offset: PackedFloat64Array) -> Vector3:
	var world: WorldFrame = host.main.world
	return world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], world.origin.system_id))


func _pose(actor: String) -> Variant:
	if actor != "ship":
		return null
	if _followed != null and is_instance_valid(_followed) and _followed.is_visible_in_tree():
		_last_pose = _followed.get_global_transform_interpolated()
	return _last_pose  # gone through the ring, the camera holds where it last saw the ship


# Behind and above the ship all the way in, at a fixed distance, so it is seen shrinking as the funnel narrows round it, down to
# the ring's flash.
func _departure_shot(capital: bool) -> CinematicShot:
	var k: float = 6.0 if capital else 1.0
	return _shot(&"transit_departure", [
		{"t": 0.0, "position": {"actor": "ship", "offset": [16.0 * k, 7.0 * k, 50.0 * k]}, "look_at": {"actor": "ship", "offset": [0.0, 0.0, -30.0 * k]}, "fov": 50},
		{"t": 60.0, "position": {"actor": "ship", "offset": [16.0 * k, 7.0 * k, 50.0 * k]}, "look_at": {"actor": "ship", "offset": [0.0, 0.0, -30.0 * k]}, "fov": 50},
	])


# Ahead of the ship, looking back at it as it comes out of the ring's flash and grows on its way out, then drawing back.
func _arrival_shot(capital: bool) -> CinematicShot:
	var k: float = 6.0 if capital else 1.0
	return _shot(&"transit_arrival", [
		{"t": 0.0, "position": {"actor": "ship", "offset": [12.0 * k, 5.0 * k, -55.0 * k]}, "look_at": {"actor": "ship"}, "fov": 50},
		{"t": 4.5, "position": {"actor": "ship", "offset": [13.0 * k, 5.5 * k, -60.0 * k]}, "look_at": {"actor": "ship"}, "fov": 50},
		{"t": 8.0, "position": {"actor": "ship", "offset": [25.0 * k, 10.0 * k, -110.0 * k]}, "look_at": {"actor": "ship"}, "fov": 50},
		{"t": 60.0, "position": {"actor": "ship", "offset": [25.0 * k, 10.0 * k, -110.0 * k]}, "look_at": {"actor": "ship"}, "fov": 50},
	])


func _shot(id: StringName, keys: Array) -> CinematicShot:
	var made: Dictionary = CinematicShot.from_dict(id, {"keys": keys})
	if not bool(made["ok"]):
		push_warning("TransitConsole: %s" % made["error"])
		return null
	return made["shot"]


# Out of play once through: a pooled fighter back to its pool, a capital stand-in parked.
func _leave(body: Node3D) -> void:
	var main: Main = host.main
	var cap := body as CapitalStandin
	if cap != null:
		cap.leave_play()
		return
	for c: Combatant in main.ships.alive():
		if c.ship == body:
			main.ships.release(c)
			return


static func _cross_radius(body: RigidBody3D) -> float:
	var damageable: Damageable = Damageable.of(body)
	return VortexTransit.lateral_radius(damageable.ram_bounds) if damageable != null else 10.0
