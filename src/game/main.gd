class_name Main
extends Node3D
## Main scene (architecture §3, M1-T15): loads the free-flight scenario, spawns the player and the nav buoys through
## World, wires camera, weapons, thruster glow and overlay, and turns one PilotCommand per physics tick into ship
## commands and UI actions. Main runs while paused (so Start can unpause); World and everything in it pause.

const SCENARIO_DIR := "res://data/scenarios/"
const SHIP_SPEC_PATH := "res://assets/ships/starfury_aurora.tres"
const SCENARIO_CHOICES: Array[StringName] = [&"combat_sandbox", &"free_flight"]

## The player's hull reached zero (the ship is hidden and disabled; input is ignored until the respawn).
signal player_died
## The player is back at the scenario start with a full hull (after `DestructionDirector.RESPAWN_DELAY_S`, or `respawn`).
signal player_respawned

## Raiders built (parked) at load for the waves and the console's `spawn`. -1 = what the scenario's `pools` says (the
## sandbox 6, free flight none); 0 or more overrides it. Set before the node enters the tree.
var raider_pool_size: int = -1
## Overrides `settings.scenario` with a scenario file (tests). Empty = the setting.
var scenario_path: String = ""
## The sandbox starts wave 1's countdown at load. Tests that drive the waves themselves turn this off.
var waves_auto_start: bool = true

## Set before the node enters the tree to drive Main from a script (tests use FakeInputSource).
var input_source: InputSource = null
var adapter: InputAdapter = InputAdapter.new()

## One line for the HUD's top centre (wave, raiders left, kills); the wave director sets it (M2-T09).
var status_line: String = ""
## False from the player's death until the respawn; input is ignored meanwhile.
var player_alive: bool = true
var combatant: Combatant = null
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
@onready var ships: ShipPool = $World/Ships
@onready var effects: Node3D = $World/Effects
@onready var debris: DebrisPool = $World/Debris
@onready var audio: AudioDirector = $World/Audio
@onready var director: DestructionDirector = $Combat/DestructionDirector
@onready var waves: WaveDirector = $Combat/WaveDirector
@onready var hud: Hud = $Hud
@onready var splat_status: SplatStatus = $SplatStatus
@onready var overlay: DebugOverlay = $DebugOverlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_input()
	get_tree().root.size_changed.connect(_update_render_scale)
	_update_render_scale()
	var scenario: Dictionary = ScenarioLoader.load(resolved_scenario_path())
	if not bool(scenario.get("ok", false)):
		push_warning("Main: %s; spawning at the origin with no props" % scenario.get("error", "no scenario"))
	else:
		var player: Dictionary = scenario["player"]
		_spawn_position = player["position"]
		_spawn_basis = player["basis"]
	_spawn_ship()
	ships.world = world
	ships.projectiles = projectiles
	ships.player = ship
	var pool_count: int = raider_pool_size
	if pool_count < 0:
		pool_count = int((scenario.get("pools", {}) as Dictionary).get(ShipPool.DEFAULT_TYPE, 0))
	if pool_count > 0:
		ships.prepare(ShipPool.DEFAULT_TYPE, pool_count)
		debris.prepare(ShipPool.DEFAULT_TYPE)
	hud.input_provider = _build_hud_input
	director.setup(world, ships, debris, effects, combatant)
	director.player_destroyed.connect(_on_player_destroyed)
	director.respawn_due.connect(respawn)
	_wire_audio()
	waves.status_sink = func(line: String) -> void: status_line = line
	waves.setup(world, ships, combatant, scenario if pool_count > 0 else {}, director, waves_auto_start)
	player_respawned.connect(waves.on_player_respawned)
	if bool(scenario.get("ok", false)):
		_spawn_props(scenario["props"])
	camera_rig.setup(ship, ship.cockpit_anchor, ship.get_chase_offset(), ship.set_cockpit_interior_visible)
	world.focus = ship
	# The chase camera is world_shiftable; the cockpit camera follows a RemoteTransform3D, so drop its interpolation
	# history on a rebase too, or it would smear the jump across one frame.
	world.rebased.connect(func(_offset: Vector3) -> void: camera_rig.cockpit_pivot.reset_physics_interpolation())
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if get_tree() != null and get_tree().root.size_changed.is_connected(_update_render_scale):
		get_tree().root.size_changed.disconnect(_update_render_scale)


# The splat renderer cannot draw more than 65 535 tiles of 16 x 16 px; a very large window is rendered at a lower 3D scale (RenderScale).
func _update_render_scale() -> void:
	var root: Window = get_tree().root
	var scale: float = RenderScale.scale_for(root.size.x, root.size.y)
	if not is_equal_approx(root.scaling_3d_scale, scale):
		root.scaling_3d_scale = scale


func _physics_process(delta: float) -> void:
	var pc: PilotCommand = adapter.sample(input_source, delta)
	if pc.flight.autotrack and not _target_for_autotrack():
		adapter.autotrack_on = false
		pc.flight.autotrack = false
	if not get_tree().paused and player_alive:
		combatant.apply_commands(pc.flight, pc.combat)
	if not get_tree().paused:
		camera_rig.set_look(delta, pc.ui.look_active, pc.ui.look_stick, pc.ui.look_mouse_px)
	_handle_ui(pc.ui)


# Auto-track needs a target: with none selected the nearest hostile is taken; with none in range it switches itself off.
func _target_for_autotrack() -> bool:
	if ship == null or not player_alive:
		return false
	return ship.targeting.system.has_selection() or ship.targeting.select_nearest_hostile()


# The mouse flies the ship and works the targets (architecture §6.1): its motion and wheel go to the input source, which
# hands them to the adapter once per physics tick.
func _input(event: InputEvent) -> void:
	var source := input_source as GodotInputSource
	if source == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		source.add_mouse_motion((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_DOWN:
			source.add_wheel(1)
		elif button == MOUSE_BUTTON_WHEEL_UP:
			source.add_wheel(-1)


func _process(_delta: float) -> void:
	_update_mouse_capture()
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


## The scenario file in use: `scenario_path`, else the one `settings.scenario` names.
func resolved_scenario_path() -> String:
	if not scenario_path.is_empty():
		return scenario_path
	return SCENARIO_DIR + String(Settings.get_value(&"scenario")) + ".json"


## Back to the scenario start, at rest, with a full hull (Back / Backspace / `respawn`, and the respawn after a death).
func respawn() -> void:
	ship.process_mode = Node.PROCESS_MODE_INHERIT
	ship.visible = true
	ship.reset_to(Transform3D(_spawn_basis, world.universe_to_local(_spawn_position)))
	combatant.damageable.restore()
	for buoy: NavBuoy in buoys:
		buoy.restore()
	combatant.cannon.gate.reset()
	ship.set_flight_command(FlightCommand.new())
	ship.set_combat_command(CombatCommand.new())
	adapter.reset()
	camera_rig.snap_chase()
	var was_dead: bool = not player_alive
	player_alive = true
	if was_dead:
		player_respawned.emit()


# Gun sounds and engine hums for every ship, and the combat events (hits, explosions, warnings).
func _wire_audio() -> void:
	audio.connect_combat($Combat/HitResolver as HitResolver, director, combatant)
	audio.watch_ship(combatant)
	for pooled: Combatant in ships.all_ships():
		audio.watch_ship(pooled)


## This frame's `HudInput`, read from the live nodes (the HUD never caches anything).
func _build_hud_input() -> HudInput:
	var camera: Camera3D = camera_rig.active_camera()
	var input := HudInput.new()
	if camera == null or ship == null:
		return input
	input.camera_transform = camera.global_transform
	input.projection = camera.get_camera_projection()
	input.viewport_size = get_viewport().get_visible_rect().size
	input.cockpit = camera_rig.mode == CameraRig.Mode.COCKPIT
	input.show_grid = bool(Settings.get_value(&"hud_targeting_grid"))
	input.own_position = ship.global_position
	input.own_basis = ship.global_basis
	input.own_velocity = ship.linear_velocity
	input.has_reference = true
	input.reference_position = world.universe_to_local(_spawn_position)  # the launch point, for now
	input.tracking = ship.get_flight_output().tracking
	var muzzles: Array[Node3D] = ship.get_muzzles()
	var mean := Vector3.ZERO
	for muzzle: Node3D in muzzles:
		mean += muzzle.global_position
	input.muzzle_position = mean / float(muzzles.size()) if not muzzles.is_empty() else ship.global_position
	input.weapon_speed_mps = cannon.weapon.muzzle_speed_mps
	input.weapon_lifetime_s = cannon.weapon.lifetime_s
	input.faction = combatant.faction
	input.hull_fraction = combatant.damageable.hull.fraction()
	input.damage_layout = combatant.damageable.zones.layout
	input.damage_zones = combatant.damageable.zone_severities()
	input.god = DebugConsole.flags.invulnerable
	var tank: FuelTank = ship.get_fuel_tank()
	input.fuel_fraction = tank.fraction()
	input.fuel_unlimited = tank.unlimited
	input.charge_fraction = cannon.charge_fraction()
	input.fire_mode = String(PulseCannonGate.mode_name(cannon.gate.mode))
	input.target = ship.targeting.selected_readout()
	input.contacts = ship.targeting.candidates()
	input.selected_id = ship.targeting.selected_id()
	input.status_line = status_line
	return input


func _on_player_destroyed(_info: HitInfo) -> void:
	player_alive = false
	player_died.emit()


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
	adapter.mouse_full_rate_px_s = float(Settings.get_value(&"mouse_full_rate_px_s"))
	var godot_source := input_source as GodotInputSource
	if godot_source != null:
		godot_source.trigger_deadzone = float(Settings.get_value(&"trigger_deadzone"))


func _spawn_ship() -> void:
	var spec := load(SHIP_SPEC_PATH) as ShipSpec
	combatant = ShipAssembly.build(spec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(combatant.ship, _spawn_position, _spawn_basis)
	ship = combatant.ship
	thrusters = combatant.thrusters
	cannon = combatant.cannon


func _spawn_props(props: Array) -> void:
	for entry: Dictionary in props:
		if StringName(entry["type"]) != &"nav_buoy":
			push_warning("Main: unknown prop type '%s'" % entry["type"])
			continue
		var buoy: NavBuoy = NavBuoy.create(String(entry["name"]), entry["velocity"])
		world.spawn(buoy, entry["position"], Basis.IDENTITY, targets)
		buoys.append(buoy)
		director.watch_buoy(buoy)


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
	if ui.screenshot:
		var result: ConsoleResult = DebugConsole.registry.execute_tokens(PackedStringArray(["screenshot"]))
		print("[screenshot] ", result.lines[0] if result.ok and not result.lines.is_empty() else result.error)


# The mouse is captured (hidden, unbounded) while flying with a mouse-capable source; holding Alt, the console, the pause and a
# window that lost focus give it back to the desktop (Alt + drag then moves the window in most window managers). While it is
# the desktop's, the source reads it as idle.
func _update_mouse_capture() -> void:
	var godot_source := input_source as GodotInputSource
	if godot_source == null or DisplayServer.get_name() == "headless":
		return
	var flying: bool = not get_tree().paused and not DebugConsole.is_open() and get_window().has_focus() \
			and not Input.is_physical_key_pressed(KEY_ALT)
	var wanted: Input.MouseMode = Input.MOUSE_MODE_CAPTURED if flying else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted
	godot_source.mouse_free = not flying


func _update_bracket() -> void:
	var readout: TargetReadout = ship.targeting.selected_readout() if ship != null else null
	var cam: Camera3D = camera_rig.active_camera()
	if hud.visible or readout == null or cam == null or cam.is_position_behind(readout.position):  # the HUD has its own box
		overlay.hide_bracket()
		return
	overlay.show_bracket(cam.unproject_position(readout.position))


func _register_console() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"respawn", "Reset the ship to the scenario start",
			[] as Array[ConsoleArg]), _cmd_respawn, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"window", "Resize the game window (width and height in pixels), or `window max` / `window normal` to maximize or restore it",
			[ConsoleArg.string_required(&"width_or_mode"), ConsoleArg.int_optional(&"height", null, 200, 4320)]), _cmd_window, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"pause", "Pause or resume the game (toggles with no argument)",
			[ConsoleArg.bool_optional(&"state")] as Array[ConsoleArg]), _cmd_pause, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"scenario",
			"Load a scenario (combat_sandbox or free_flight): sets settings.scenario for this session and reloads the scene",
			[ConsoleArg.enum_optional(&"name", SCENARIO_CHOICES, null)] as Array[ConsoleArg]), _cmd_scenario, self)


func _cmd_window(args: Dictionary) -> ConsoleResult:
	if DisplayServer.get_name() == "headless":
		return ConsoleResult.failure("window needs a display (this run is --headless)")
	var first: String = String(args[&"width_or_mode"])
	if first == "max":
		get_window().mode = Window.MODE_MAXIMIZED
		return ConsoleResult.line("window maximized")
	if first == "normal":
		get_window().mode = Window.MODE_WINDOWED
		return ConsoleResult.line("window restored")
	if not first.is_valid_int() or args[&"height"] == null:
		return ConsoleResult.failure("window expects <width> <height>, max or normal")
	var size := Vector2i(int(first), int(args[&"height"]))
	get_window().size = size
	return ConsoleResult.line("window %dx%d" % [size.x, size.y])


func _cmd_respawn(_args: Dictionary) -> String:
	respawn()
	return "ship reset to the scenario start"


func _cmd_scenario(args: Dictionary) -> ConsoleResult:
	var wanted: Variant = args.get(&"name")
	if wanted == null:
		return ConsoleResult.line("scenario = %s" % Settings.get_value(&"scenario"))
	Settings.set_value(&"scenario", StringName(wanted))
	if get_tree().current_scene == null:
		return ConsoleResult.line("settings.scenario = %s (no current scene to reload)" % wanted)
	# The console autoload keeps its statement queue across the reload, so a startup script carries on in the new scene.
	get_tree().reload_current_scene.call_deferred()
	return ConsoleResult.line("loading %s" % wanted)


func _cmd_pause(args: Dictionary) -> String:
	var requested: Variant = args.get(&"state")
	set_paused(not get_tree().paused if requested == null else bool(requested))
	return "paused" if get_tree().paused else "running"


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key in [&"stick_deadzone", &"invert_y", &"yaw_ramp_s", &"target_hold_s", &"trigger_deadzone", &"mouse_full_rate_px_s"]:
		_apply_input_settings()
