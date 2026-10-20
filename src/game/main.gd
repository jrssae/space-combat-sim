class_name Main
extends Node3D
## Main scene (architecture §3, M1-T15): loads the free-flight scenario, spawns the player and the nav buoys through
## World, wires camera, weapons, thruster glow and overlay, and turns one PilotCommand per physics tick into ship
## commands and UI actions. Main runs while paused (so Start can unpause); World and everything in it pause.

const SCENARIO_PATH := "res://data/scenarios/free_flight.json"
const SHIP_SPEC_PATH := "res://assets/ships/starfury_aurora.tres"

## Set before the node enters the tree to drive Main from a script (tests use FakeInputSource).
var input_source: InputSource = null
var adapter: InputAdapter = InputAdapter.new()

var ship: Ship = null
var thrusters: ThrusterVisuals = null
var cannon: PulseCannon = null
var buoys: Array[NavBuoy] = []

var _spawn_position: UniversePos = UniversePos.new()
var _spawn_basis: Basis = Basis.IDENTITY

@onready var world: WorldFrame = $World
@onready var space_environment: SpaceEnvironment = $SpaceEnvironment
@onready var camera_rig: CameraRig = $World/CameraRig
@onready var targets: Node3D = $World/Targets
@onready var projectiles: Node3D = $World/Projectiles
@onready var splat_status: SplatStatus = $SplatStatus
@onready var overlay: DebugOverlay = $DebugOverlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_input()
	var scenario: Dictionary = ScenarioLoader.load(SCENARIO_PATH)
	if not bool(scenario.get("ok", false)):
		push_warning("Main: %s; spawning at the origin with no props" % scenario.get("error", "no scenario"))
	else:
		var player: Dictionary = scenario["player"]
		_spawn_position = player["position"]
		_spawn_basis = player["basis"]
	_spawn_ship()
	if bool(scenario.get("ok", false)):
		_spawn_props(scenario["props"])
	camera_rig.setup(ship, ship.cockpit_anchor, ship.get_chase_offset(), ship.set_cockpit_interior_visible)
	world.focus = ship
	# The chase camera is world_shiftable; the cockpit camera follows a RemoteTransform3D, so drop its interpolation
	# history on a rebase too, or it would smear the jump across one frame.
	world.rebased.connect(func(_offset: Vector3) -> void: camera_rig.cockpit_camera.reset_physics_interpolation())
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	var pc: PilotCommand = adapter.sample(input_source, delta)
	if not get_tree().paused:
		ship.set_flight_command(pc.flight)
		ship.set_combat_command(pc.combat)
		cannon.set_combat_command(pc.combat)
	_handle_ui(pc.ui)


func _process(_delta: float) -> void:
	if overlay.visible:
		overlay.show_snapshot(snapshot())
	_update_bracket()


## Everything the overlay shows, gathered from the subsystems' typed getters.
func snapshot() -> Dictionary:
	var s: Dictionary = {}
	if ship != null:
		s["speed_mps"] = ship.linear_velocity.length()
		s["body_velocity"] = ship.body_velocity()
		s["angular_rate_dps"] = ship.body_angular_velocity() * FlightModel.AXIS_SIGN * (180.0 / PI)
		s["assist_on"] = ship.assist_on
		var out: FlightOutput = ship.get_flight_output()
		if out != null:
			s["pod_yaw_dps"] = out.pod_yaw_cmd * ship.spec.rate_max.y
			s["pod_trim"] = out.trim
		var u: UniversePos = world.to_universe(ship.position)
		s["universe_position"] = PackedFloat64Array([u.x, u.y, u.z])
		s["system_id"] = String(u.system_id)
		var readout: TargetReadout = ship.targeting.selected_readout()
		if readout != null:
			s["target_name"] = readout.display_name
			s["target_range_m"] = readout.range_m
			s["target_closing_mps"] = readout.closing_mps
			var cam: Camera3D = camera_rig.active_camera()
			s["target_behind"] = cam != null and cam.is_position_behind(readout.position)
		else:
			s["target_name"] = ""
	s["camera_mode"] = String(CameraRig.mode_name(camera_rig.mode))
	if cannon != null:
		s["weapon_mode"] = String(PulseCannonGate.mode_name(cannon.gate.mode))
	s["timescale"] = Engine.time_scale
	s["splat_backend"] = String(SplatStatus.active_backend())
	s["fps"] = Engine.get_frames_per_second()
	s["gpu"] = RenderingServer.get_video_adapter_name()
	s["pads"] = input_source.pad_info()
	return s


## Back to the scenario start, at rest (Back / Backspace / `respawn`).
func respawn() -> void:
	ship.reset_to(Transform3D(_spawn_basis, world.universe_to_local(_spawn_position)))
	adapter.reset()
	camera_rig.snap_chase()


func set_paused(paused: bool) -> void:
	get_tree().paused = paused


func _setup_input() -> void:
	if input_source == null:
		var source := GodotInputSource.new()
		source.load_calibration(Settings.get_pad_calibration())
		source.trigger_rest_changed.connect(Settings.set_trigger_rest)
		input_source = source
	_apply_input_settings()
	Settings.changed.connect(_on_setting_changed)
	DebugConsole.set_input_source(input_source, adapter)


func _apply_input_settings() -> void:
	adapter.stick_deadzone = float(Settings.get_value(&"stick_deadzone"))
	adapter.invert_y = bool(Settings.get_value(&"invert_y"))
	adapter.yaw_ramp_s = float(Settings.get_value(&"yaw_ramp_s"))
	adapter.target_hold_s = float(Settings.get_value(&"target_hold_s"))
	var godot_source := input_source as GodotInputSource
	if godot_source != null:
		godot_source.trigger_deadzone = float(Settings.get_value(&"trigger_deadzone"))


func _spawn_ship() -> void:
	var spec := load(SHIP_SPEC_PATH) as ShipSpec
	ship = Ship.create(spec, world)
	world.spawn(ship, _spawn_position, _spawn_basis)
	thrusters = ThrusterVisuals.new()
	thrusters.name = "ThrusterVisuals"
	ship.thrusters.add_child(thrusters)
	thrusters.setup(ship.get_layout(), ship.get_flight_output)
	cannon = PulseCannon.new()
	cannon.name = "PulseCannon"
	ship.guns.add_child(cannon)
	cannon.setup(ship, ship.get_muzzles(), projectiles)


func _spawn_props(props: Array) -> void:
	for entry: Dictionary in props:
		if StringName(entry["type"]) != &"nav_buoy":
			push_warning("Main: unknown prop type '%s'" % entry["type"])
			continue
		var buoy: NavBuoy = NavBuoy.create(String(entry["name"]), entry["velocity"])
		world.spawn(buoy, entry["position"], Basis.IDENTITY, targets)
		buoys.append(buoy)


func _handle_ui(ui: UiCommand) -> void:
	if ui.pause:
		set_paused(not get_tree().paused)
	if ui.toggle_camera:
		camera_rig.toggle()
	if ui.reset:
		respawn()
	if ui.toggle_overlay:
		Settings.set_value(&"show_overlay", not bool(Settings.get_value(&"show_overlay")))
	if ui.toggle_fallback_mesh:
		splat_status.toggle_fallback()


func _update_bracket() -> void:
	var readout: TargetReadout = ship.targeting.selected_readout() if ship != null else null
	var cam: Camera3D = camera_rig.active_camera()
	if readout == null or cam == null or cam.is_position_behind(readout.position):
		overlay.hide_bracket()
		return
	overlay.show_bracket(cam.unproject_position(readout.position))


func _register_console() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"respawn", "Reset the ship to the scenario start",
			[] as Array[ConsoleArg]), _cmd_respawn, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"pause", "Pause or resume the game (toggles with no argument)",
			[ConsoleArg.bool_optional(&"state")] as Array[ConsoleArg]), _cmd_pause, self)


func _cmd_respawn(_args: Dictionary) -> String:
	respawn()
	return "ship reset to the scenario start"


func _cmd_pause(args: Dictionary) -> String:
	var requested: Variant = args.get(&"state")
	set_paused(not get_tree().paused if requested == null else bool(requested))
	return "paused" if get_tree().paused else "running"


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key in [&"stick_deadzone", &"invert_y", &"yaw_ramp_s", &"target_hold_s", &"trigger_deadzone"]:
		_apply_input_settings()
