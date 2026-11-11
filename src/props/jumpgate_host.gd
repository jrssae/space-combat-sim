class_name JumpgateHost
extends Node
## The flight scene's jumpgates and the player's jump (M6-T14, D69): places the scenario's `jumpgate` props from the star-system
## data, offers the jump when the gate is targeted within `GateJumpPrompt.RANGE_M`, and carries out `GateJump`'s events: the
## controls held, `GateAutopilot` flying, the departure and arrival shots (`CinematicShot`), the flash and the fade, the ship
## hidden while away and placed back by the gate's blue arrival. A thin adapter: the rules are in `GateJump`, `GateJumpPrompt`,
## `GateAutopilot` and `VortexTiming`.
##
## Console: command `gate`, provider `gate` (both exist in every flight scene; with no gate the command says so).

const NODE_NAME: StringName = &"JumpgateHost"
## Q3: the gate is about 50 km from the station on its orbit; used only when the star-system data cannot say.
const FALLBACK_DISTANCE_M: float = 50000.0
## Where the hidden ship waits while away: behind the gate on its axis, out of every path.
const PARK_BEHIND_M: float = 3000.0
## `gate approach` puts the player this far in front of the gate, facing it (inside the prompt's 10 km).
const APPROACH_M: float = 6000.0
## Lit layer of the flash and the fade: over the HUD and the letterbox (39), under the console.
const FADE_LAYER: int = 60
const ACTIONS: Array[StringName] = [&"status", &"open", &"close", &"jump", &"cancel", &"target", &"approach"]
const DIRECTIONS: Array[StringName] = [&"arrival", &"departure"]

var main: Main = null
var gates: Array[Jumpgate] = []
## The player's jump.
var jump: GateJump = GateJump.new()
## The gate the jump goes through (null while none runs).
var jump_gate: Jumpgate = null

var _went_through: bool = false
var _placed: bool = false
var _assist_before: bool = true
var _capability: ShipCapability = null
var _fade: ColorRect = null
var _flash_colour: Color = JumpVortex.DEFAULT_FLASH


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "JumpFade"
	layer.layer = FADE_LAYER
	add_child(layer)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.visible = false
	layer.add_child(_fade)
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _process(_delta: float) -> void:
	var flash: float = jump.flash_level
	var black: float = jump.black_level
	_fade.visible = flash > 0.0 or black > 0.0
	_fade.color = Color(_flash_colour.r * flash, _flash_colour.g * flash, _flash_colour.b * flash, maxf(flash, black))


## Spawns a scenario's `jumpgate` prop (`ScenarioLoader._jumpgate`): at its position, else `bearing` from its station at the
## distance `system` gives between the two places, its front along `facing`. Returns the gate.
func place(entry: Dictionary, system: StarSystem) -> Jumpgate:
	var at: UniversePos = entry["position"] as UniversePos
	if at == null:
		var distance: float = FALLBACK_DISTANCE_M
		if system != null and system.is_valid() and system.has_id(entry["place"]) and system.has_id(entry["from"]):
			distance = system.distance_m(entry["place"], entry["from"], 0.0)
		else:
			push_warning("JumpgateHost: the star system cannot place %s from %s; %.0f km from the station" % [entry["place"],
					entry["from"], FALLBACK_DISTANCE_M / 1000.0])
		at = (entry["station"] as UniversePos).plus_local((entry["bearing"] as Vector3) * distance)
	var facing: Vector3 = entry["facing"]
	var up: Vector3 = Vector3.UP if absf(facing.normalized().dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var gate: Jumpgate = Jumpgate.create(String(entry["name"]))
	main.world.spawn(gate, at, Basis.looking_at(facing, up), main.targets)
	gates.append(gate)
	return gate


## The first gate of the scene, or null.
func gate() -> Jumpgate:
	return gates[0] if not gates.is_empty() else null


## The gate the player has targeted, or null.
func targeted_gate() -> Jumpgate:
	if main == null or main.ship == null:
		return null
	var selected: int = main.ship.targeting.selected_id()
	for g: Jumpgate in gates:
		if selected != 0 and g.targetable.get_instance_id() == selected:
			return g
	return null


## Whether X asks for a jump now (`GateJumpPrompt`).
func jump_offered() -> bool:
	var g: Jumpgate = targeted_gate()
	if g == null:
		return false
	return GateJumpPrompt.offered(main.ship.global_position.distance_to(g.global_position), true, main.player_alive,
			not _others_hold_controls(), not jump.is_active())


## The HUD's prompt line ("" when no jump is offered).
func prompt_line() -> String:
	return GateJumpPrompt.TEXT if jump_offered() else ""


## The jump holds the player's controls.
func locks_controls() -> bool:
	return jump.is_active()


## Starts the player's jump through `through` (the targeted gate by default). Returns "" or why it cannot start.
func start_jump(through: Jumpgate = null) -> String:
	var g: Jumpgate = through if through != null else targeted_gate()
	if g == null:
		return "no gate targeted"
	if not main.player_alive:
		return "the player's ship is lost"
	if jump.is_active():
		return "a jump is under way (%s)" % jump.state_name()
	jump_gate = g
	jump.arrival_z = g.arrival_point.z
	_went_through = false
	_placed = false
	_flash_colour = g.vortex.flash_colour
	_handle(jump.start())
	return ""


## Ends a jump under way (the console, a respawn); the ship is put back in sight at the arrival if it was away.
func cancel_jump(why: String = "cancelled") -> void:
	_handle(jump.cancel(why))


## One tick of the player's jump (`Main` calls it after the control lock): the autopilot's command while it flies, a coasting
## command while the jump otherwise holds the ship, null while no jump runs.
func step_player(delta: float) -> FlightCommand:
	if not jump.is_active() or jump_gate == null:
		return null
	if not is_instance_valid(jump_gate):
		cancel_jump("the gate is gone")
		return null
	var ship: Ship = main.ship
	var local: Vector3 = jump_gate.local_of(ship.global_position)
	var events: PackedStringArray = jump.step(delta, local, jump_gate.departure_point, main.player_alive, _went_through, _placed)
	_went_through = false
	_placed = false
	_handle(events)
	if not jump.is_active():
		return null
	if not jump.autopilot_on():
		return FlightCommand.new()
	if _capability == null:
		_capability = ShipCapability.from_spec(ship.spec, ship.get_layout())
	if jump.state == GateJump.State.LINE_UP:
		var target: Vector3 = jump_gate.global_transform * GateAutopilot.line_up_target(local, jump_gate.departure_point)
		return GateAutopilot.line_up(ship.global_position, ship.linear_velocity, ship.global_basis, target, _capability)
	var axis: Vector3 = (jump_gate.global_basis * jump_gate.departure_forward).normalized()
	return GateAutopilot.run_in(ship.global_position, ship.linear_velocity, ship.global_basis, jump_gate.global_position, axis,
			jump_gate.global_basis.y, jump_gate.vortex.open_in_s(JumpVortex.Direction.DEPARTURE), _capability)


func _handle(events: PackedStringArray) -> void:
	for ev: String in events:
		match StringName(ev):
			GateJump.EV_START:
				_assist_before = main.ship.assist_on
				main.ship.assist_on = true
			GateJump.EV_RUN_IN:
				jump_gate.send_departure(main.ship, _on_player_through)
				_play(_departure_shot())
			GateJump.EV_THROUGH:
				_park_away()
			GateJump.EV_ASK_ARRIVAL:
				jump_gate.request_arrival(_place_player)
				_play(_arrival_shot())
			GateJump.EV_ARRIVED:
				pass  # the arrival shot is already framing the way out
			GateJump.EV_DONE, GateJump.EV_ABORT:
				_finish()


func _on_player_through(_ship: Node3D) -> void:
	_went_through = true


# Out of sight while away: hidden and parked at rest behind the gate, where nothing flies.
func _park_away() -> void:
	var ship: Ship = main.ship
	ship.reset_to(Transform3D(ship.global_basis, jump_gate.global_transform * Vector3(0.0, 0.0, PARK_BEHIND_M)))
	ship.visible = false


# The gate's arrival is open: the ship comes out of it, in sight again.
func _place_player() -> void:
	if not jump.is_active() or not main.player_alive:
		return
	var ship: Ship = main.ship
	ship.reset_to(jump_gate.arrival_transform())
	ship.linear_velocity = jump_gate.arrival_velocity()
	ship.visible = true
	ship.reset_physics_interpolation()
	_placed = true


func _finish() -> void:
	var ship: Ship = main.ship
	if jump_gate != null and is_instance_valid(jump_gate):
		jump_gate.cancel_departure(ship)
		if main.player_alive and not ship.visible:
			_placed = true
			ship.reset_to(jump_gate.arrival_transform())
			ship.visible = true
	if main.player_alive:
		ship.assist_on = _assist_before
	if main.camera_rig.is_playing_shot():
		main.camera_rig.stop_shot()
	main.camera_rig.snap_chase()
	main.adapter.resync_edges(main.input_source)
	_placed = false
	jump_gate = null


func _play(shot: CinematicShot) -> void:
	if shot != null:
		main.camera_rig.play_shot(shot, _actor_pose, _origin_to_local)


# Follows the ship in from behind and beside, then watches it from in front of the gate as it goes into the funnel.
func _departure_shot() -> CinematicShot:
	var g: String = _gate_key()
	return _shot(&"gate_departure", [
		{"t": 0.0, "position": {"actor": "player", "offset": [45, 18, 95]}, "look_at": {"actor": "player", "offset": [0, 0, -300]}, "fov": 62},
		{"t": 3.0, "position": {"actor": "player", "offset": [140, 45, 70]}, "look_at": {"actor": g, "offset": [0, 0, 0]}, "fov": 60},
		{"t": 7.0, "position": {"actor": g, "offset": [420, 170, -950]}, "look_at": {"actor": "player"}, "fov": 55},
		{"t": 30.0, "position": {"actor": g, "offset": [380, 150, -800]}, "look_at": {"actor": g, "offset": [0, 0, 600]}, "fov": 55},
	])


# From in front of the gate, on the vortex opening, then easing onto the way the ship comes out.
func _arrival_shot() -> CinematicShot:
	var g: String = _gate_key()
	return _shot(&"gate_arrival", [
		{"t": 0.0, "position": {"actor": g, "offset": [520, 210, -2700]}, "look_at": {"actor": g, "offset": [0, 0, 0]}, "fov": 55},
		{"t": 4.0, "position": {"actor": g, "offset": [470, 190, -2550]}, "look_at": {"actor": g, "offset": [0, 0, -150]}, "fov": 52},
		{"t": 30.0, "position": {"actor": g, "offset": [300, 130, -2300]}, "look_at": {"actor": g, "offset": [0, 0, -2000]}, "fov": 55},
	])


func _shot(id: StringName, keys: Array) -> CinematicShot:
	var made: Dictionary = CinematicShot.from_dict(id, {"keys": keys})
	if not bool(made["ok"]):
		push_warning("JumpgateHost: %s" % made["error"])
		return null
	return made["shot"]


func _gate_key() -> String:
	return "gate:" + jump_gate.display_name


func _actor_pose(actor: String) -> Variant:
	if actor == "player":
		return main.ship.get_global_transform_interpolated() if main.ship != null else null
	if jump_gate != null and is_instance_valid(jump_gate) and actor == _gate_key():
		return jump_gate.global_transform
	return null


func _origin_to_local(offset: PackedFloat64Array) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], main.world.origin.system_id))


# A mission's lock or a cinematic of its own holds the controls: no jump is offered then.
func _others_hold_controls() -> bool:
	var held: bool = main.mission != null and main.mission.api != null and main.mission.api.controls_locked
	return held or main.camera_rig.is_playing_shot()


# --- console ----------------------------------------------------------------------------------------------------------


func _register_console() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	registry.register_command(ConsoleCommand.new(&"gate",
			"The jumpgate: status, open <arrival|departure> (the vortex), close, jump (start the player's jump through it, from anywhere), cancel (end the jump), target (select it), approach (put the player 6 km in front of it, facing it)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"),
			ConsoleArg.enum_optional(&"direction", DIRECTIONS, null)] as Array[ConsoleArg]), _cmd_gate, self)
	registry.register_provider(&"gate", ConsoleVars.new({
		&"count": {"get": func() -> int: return gates.size(), "doc": "Jumpgates in the scene"},
		&"name": {"get": func() -> String: return gate().display_name if gate() != null else "none", "doc": "The gate's name"},
		&"distance_km": {"get": _distance_km, "unit": "km", "doc": "From the player to the gate's centre (-1 with no gate)"},
		&"targeted": {"get": func() -> bool: return targeted_gate() != null, "doc": "The player has the gate targeted"},
		&"prompt": {"get": jump_offered, "doc": "The jump is offered: the HUD shows X: REQUEST JUMP and X asks for it"},
		&"vortex": {"get": func() -> String: return gate().vortex.phase_name() if gate() != null else "none",
				"doc": "The vortex: closed, glow, flash, grow, open or closing"},
		&"vortex_direction": {"get": func() -> String: return String(gate().vortex.direction_name()) if gate() != null else "none",
				"doc": "arrival (blue), departure (orange) or none"},
		&"vortex_age_s": {"get": func() -> float: return gate().vortex.age_s if gate() != null and gate().vortex.is_active() else 0.0,
				"unit": "s", "doc": "Sim time since the vortex began to open"},
		&"openings": {"get": func() -> int: return gate().vortex.openings if gate() != null else 0, "doc": "Openings so far"},
		&"arrived": {"get": func() -> int: return gate().arrived if gate() != null else 0, "doc": "Ships placed by an arrival"},
		&"departed": {"get": func() -> int: return gate().departed if gate() != null else 0, "doc": "Ships gone through a departure"},
		&"pending_arrivals": {"get": func() -> int: return gate().pending_arrivals() if gate() != null else 0,
				"doc": "Ships waiting for the arrival vortex to open"},
		&"departing": {"get": func() -> int: return gate().departing() if gate() != null else 0,
				"doc": "Ships the gate watches flying in to depart"},
		&"jump": {"get": jump.state_name, "doc": "The player's jump: idle, line_up, run_in, flash, away, arriving or clearing"},
		&"jump_state_s": {"get": func() -> float: return jump.state_s, "unit": "s", "doc": "Time in the jump's current state"},
		&"jumps_completed": {"get": func() -> int: return jump.completed, "doc": "Jumps the player finished"},
		&"jumps_aborted": {"get": func() -> int: return jump.aborted, "doc": "Jumps that ended early"},
		&"last_abort": {"get": func() -> String: return jump.ended_why if not jump.ended_why.is_empty() else "none",
				"doc": "Why the last jump ended early"},
	}), self)


func _distance_km() -> float:
	if gate() == null or main == null or main.ship == null:
		return -1.0
	return main.ship.global_position.distance_to(gate().global_position) / 1000.0


func _cmd_gate(args: Dictionary) -> ConsoleResult:
	var action: StringName = StringName(args[&"action"])
	var g: Jumpgate = gate()
	if g == null and action != &"status":
		return ConsoleResult.failure("no jumpgate in this scenario")
	match action:
		&"open":
			if args.get(&"direction") == null:
				return ConsoleResult.failure("gate open <arrival|departure>")
			var dir: JumpVortex.Direction = JumpVortex.Direction.ARRIVAL if StringName(args[&"direction"]) == &"arrival" \
					else JumpVortex.Direction.DEPARTURE
			if not g.vortex.open(dir):
				return ConsoleResult.failure("the vortex is %s for %s; one direction per opening" % [g.vortex.phase_name(),
						g.vortex.direction_name()])
			return ConsoleResult.line("%s vortex opening" % args[&"direction"])
		&"close":
			g.vortex.close()
			return ConsoleResult.line("vortex closing (%s)" % g.vortex.phase_name())
		&"jump":
			main.ship.targeting.select_id(g.targetable.get_instance_id())
			var why: String = start_jump(g)
			return ConsoleResult.failure(why) if not why.is_empty() else ConsoleResult.line("jump started (%s)" % jump.state_name())
		&"cancel":
			if not jump.is_active():
				return ConsoleResult.failure("no jump under way")
			cancel_jump()
			return ConsoleResult.line("jump cancelled")
		&"target":
			if not main.ship.targeting.select_id(g.targetable.get_instance_id()):
				return ConsoleResult.failure("the gate is not in the target list yet")
			return ConsoleResult.line("%s targeted" % g.display_name)
		&"approach":
			var at: Vector3 = g.global_transform * Vector3(0.0, 0.0, -APPROACH_M)
			main.ship.reset_to(Transform3D(Basis.looking_at(g.global_position - at, g.global_basis.y), at))
			main.camera_rig.snap_chase()
			return ConsoleResult.line("player %.0f km in front of %s" % [APPROACH_M / 1000.0, g.display_name])
	if g == null:
		return ConsoleResult.line("no jumpgate in this scenario")
	return ConsoleResult.line("%s %.1f km; vortex %s (%s); jump %s; %d arrived, %d departed" % [g.display_name, _distance_km(),
			g.vortex.phase_name(), g.vortex.direction_name(), jump.state_name(), g.arrived, g.departed])
