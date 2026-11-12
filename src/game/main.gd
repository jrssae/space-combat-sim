class_name Main
extends Node3D
## Main scene (architecture §3, M1-T15): loads the free-flight scenario, spawns the player and the nav buoys through
## World, wires camera, weapons, thruster glow and overlay, and turns one PilotCommand per physics tick into ship
## commands and UI actions. Main runs while paused (so Start can unpause); World and everything in it pause.
##
## Ships the scenario places at load (`spawns`, M3-T09) come from the pool. One that leads a `route` (the instructor) is paced
## to the player, and the HUD, status line and console `route` provider follow it. A respawn places the route leaders again, so
## the lesson restarts; wing ships and fighting ships stay in play (maintainer Q8: a downed wingman is replaced at the next wave).

const SCENARIO_DIR := "res://data/scenarios/"
## The debug overlay's text is rebuilt this often while it shows (M4-T36): a readout, not an animation.
const OVERLAY_INTERVAL_S: float = 0.1
const SCENARIO_CHOICES: Array[StringName] = [&"combat_sandbox", &"free_flight", &"instructor_route", &"dogfight",
		&"civilian_showcase", &"belt_showcase"]

## The player's hull reached zero (the ship is hidden and disabled; input is ignored until the respawn).
signal player_died
## The player is back at the scenario start with a full hull (after `DestructionDirector.RESPAWN_DELAY_S`, or `respawn`).
signal player_respawned

## Raiders built (parked) at load for the waves and the console's `spawn`. -1 = the scenario's `pools`; 0 or more overrides
## it. Set before the node enters the tree.
var raider_pool_size: int = -1
## Allied Starfuries built (parked) at load (M3-T08), same rule as `raider_pool_size`.
var ally_pool_size: int = -1
## Overrides `settings.scenario` with a scenario file (tests). Empty = the setting.
var scenario_path: String = ""
## The sandbox starts wave 1's countdown at load. Tests that drive the waves themselves turn this off.
var waves_auto_start: bool = true
## Mixed into the brain seed of every ship the scenario places (M3-T10): the same seed flies the same fight (the dogfight's
## AC12 runs). Set before the node enters the tree.
var scenario_seed: int = 0
## Free-flight encounters from the start (M5-T17, D58): the menu's request sets it; every other run starts them off.
var encounters: bool = false
## Overrides the scenario's encounter pools file (tests). Empty = `data/encounters/<scenario_id>.json`, if there is one.
var encounter_pools_path: String = ""

## Set before the node enters the tree to drive Main from a script (tests use FakeInputSource).
var input_source: InputSource = null
var adapter: InputAdapter = InputAdapter.new()

## One line for the HUD's top centre (wave, raiders left, kills); the wave director sets it (M2-T09).
var status_line: String = ""
## Debug: both main pods are held at this level (0..1) on top of the pilot's input (console `throttle`), for captures and tests.
var debug_throttle: float = 0.0
## False from the player's death until the respawn; input is ignored meanwhile.
var player_alive: bool = true
## The running mission (M5-T05), or null: free flight and the sandbox have none.
var mission: MissionRunner = null
## The bars of a cinematic, and the filter that takes the ship out of the player's hands during one (M5-T08, D55).
var letterbox: Letterbox = null
var control_lock: ControlLock = ControlLock.new()
var combatant: Combatant = null
var ship: Ship = null
var thrusters: ThrusterVisuals = null
var cannon: PulseCannon = null
var buoys: Array[NavBuoy] = []
## The scenario's asteroid belts (M5-T29).
var asteroid_belts: Array[AsteroidBelt] = []
## The ships the scenario places at load (`spawns`, M3-T09), from the pool; the route leaders are placed again on a respawn.
var scenario_ships: Array[Combatant] = []
## The ship leading a route (the instructor) and its follow-path behaviour; null when the scenario has none.
var instructor: Combatant = null
var instructor_path: BehaviourFollowPath = null
## The pause menu (M5-T02): Start opens it and the world pauses behind it.
var pause_menu: PauseMenu = null
## The tick's stage timers (`perf`) and the many-ships benchmark (`bench`), M4-T01.
var perf_probe: PerfProbe = null
var bench: BenchRunner = null
## The render comparison's station scene (M4-T27), closed until `station near|far`.
var station_scene: StationScene = null
## Times the overlay's text was rebuilt (tests).
var overlay_refreshes: int = 0
## The comms menu on D-pad Right (M5-T46): a radial menu, the game pauses while it is open.
var comms: CommsMenuDirector = null
## The target menu on a hold of the target button (M5-T25): the game pauses while it is open.
var target_menu: TargetMenuDirector = null
## Free-flight encounters (M5-T17): null in a scenario without an encounter pools file.
var encounter_director: EncounterDirector = null

var _spawn_position: UniversePos = UniversePos.new()
var _overlay_in_s: float = 0.0
var _spawn_basis: Basis = Basis.IDENTITY
# The player's velocity at the first spawn (a mission that opens in flight); a respawn starts at rest.
var _start_velocity: Vector3 = Vector3.ZERO
var _system_id: StringName = &"local"
var _scenario_spawns: Array[Dictionary] = []
var _scenario_routes: Array[Route] = []
var _scenario_wings: Array[Dictionary] = []
# By `scenario_ships` index: the brain each was given, to tell when the pool has reused the ship, and the spawn it came from.
var _scenario_brains: Array[PilotBrain] = []
var _scenario_entries: Array[Dictionary] = []
var _refused: bool = false  # the native library is missing: the scene never starts (M4-T37)

@onready var world: WorldFrame = $World
@onready var space_environment: SpaceEnvironment = $SpaceEnvironment
@onready var camera_rig: CameraRig = $World/CameraRig
@onready var targets: Node3D = $World/Targets
@onready var projectiles: Node3D = $World/Projectiles
@onready var ships: ShipPool = $World/Ships
@onready var effects: Node3D = $World/Effects
@onready var debris: DebrisPool = $World/Debris
@onready var fx: FxPool = $World/Fx
@onready var audio: AudioDirector = $World/Audio
@onready var rams: RamResolver = $Combat/RamResolver
@onready var director: DestructionDirector = $Combat/DestructionDirector
@onready var waves: WaveDirector = $Combat/WaveDirector
@onready var wings: WingDirector = $Combat/WingDirector
@onready var hud: Hud = $Hud
@onready var render_status: RenderStatus = $RenderStatus
@onready var overlay: DebugOverlay = $DebugOverlay


# Refuses to start without the native library (M4-T37): says why, stops the scene and exits with 1.
func _enter_tree() -> void:
	var why: String = NativeLib.refusal()
	if why.is_empty():
		# Each battle starts at sim time 0, also a scene loaded again in the same process (the `scenario` command), so its
		# timers round as a first run's do (M4-T37). Before the children enter, so none reads the old time.
		SimClock.reset()
		return
	_refused = true
	process_mode = Node.PROCESS_MODE_DISABLED
	push_error(why)
	if DisplayServer.get_name() != "headless":
		OS.alert(why, "Space Combat Sim")
	get_tree().quit(1)


func _ready() -> void:
	if _refused:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_input()
	var scenario: Dictionary = ScenarioLoader.load(resolved_scenario_path())
	ScenarioLoader.resolve_random_civilian(scenario, scenario_seed)
	if not bool(scenario.get("ok", false)):
		push_warning("Main: %s; spawning at the origin with no props" % scenario.get("error", "no scenario"))
	else:
		var player: Dictionary = scenario["player"]
		_spawn_position = player["position"]
		_spawn_basis = player["basis"]
		_start_velocity = player["velocity"]
		_system_id = scenario["system_id"]
		_scenario_spawns = scenario["spawns"]
		_scenario_routes = scenario["routes"]
		_scenario_wings = scenario["wings"]
	_spawn_ship()
	# The player leads wing ALPHA (architecture §16 D36). Members join later (M3-T08, M3-T10).
	wings.setup(world, ships)
	if not _ai_leads_player_wing():
		wings.create_wing(Wing.DEFAULT_NAME, combatant)
	wings.declare(_scenario_wings)
	ships.world = world
	ships.projectiles = projectiles
	ships.player = ship
	var pool_count: int = _pool_count(scenario, ShipPool.DEFAULT_TYPE, raider_pool_size)
	if pool_count > 0:
		ships.prepare(ShipPool.DEFAULT_TYPE, pool_count)
		debris.prepare(ShipPool.DEFAULT_TYPE)
	var ally_count: int = _pool_count(scenario, ShipPool.ALLY_TYPE, ally_pool_size)
	if ally_count > 0:
		ships.prepare(ShipPool.ALLY_TYPE, ally_count)
	# The Starfury's break-up chunks serve the allies and the player (the player can die in any scenario).
	debris.prepare(ShipCatalog.PLAYER_TYPE)
	_prepare_other_pools(scenario)
	hud.input_provider = _build_hud_input
	hud.screens = ship.cockpit_screens
	director.setup(world, ships, debris, effects, combatant)
	# Hits, rams, explosions and debris throw their sparks from one fixed pool (M3-T23).
	($Combat/HitResolver as HitResolver).fx = fx
	rams.fx = fx
	director.fx = fx
	debris.fx = fx
	director.player_destroyed.connect(_on_player_destroyed)
	director.respawn_due.connect(respawn)
	_wire_audio()
	waves.status_sink = func(line: String) -> void: status_line = line
	waves.wings = wings
	waves.setup(world, ships, combatant, scenario if pool_count > 0 else {}, director, waves_auto_start)
	player_respawned.connect(waves.on_player_respawned)
	# Downed wingmen are replaced when the next wave starts (maintainer Q8, AC11).
	waves.wave_started.connect(wings.on_wave_started)
	if bool(scenario.get("ok", false)):
		_spawn_props(scenario["props"])
		_spawn_belts(scenario["belts"])
	_spawn_scenario_ships()
	if not (scenario.get("mission", {}) as Dictionary).is_empty():
		mission = MissionRunner.create(self, scenario)
	camera_rig.setup(ship, ship.cockpit_anchor, ship.get_chase_offset(), ship.set_cockpit_interior_visible)
	# The World keeps its origin within `auto_rebase_distance_m` (5 km, main.tscn) of the player (M3-T14, §14.1).
	world.focus = ship
	# The cockpit camera follows a RemoteTransform3D, so reset its interpolation on a rebase or the jump smears.
	world.rebased.connect(func(_offset: Vector3) -> void: camera_rig.cockpit_pivot.reset_physics_interpolation())
	letterbox = Letterbox.new()
	add_child(letterbox)
	camera_rig.mode_changed.connect(_on_camera_mode_changed)
	# Ram contact points outlive a tick; they move with the rebase.
	rams.world = world
	# The motion blur skips the frames around a rebase (M3-T25).
	space_environment.post_effects.watch_world(world)
	space_environment.use_star_of(_system_id)
	pause_menu = (preload("res://src/hud/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	pause_menu.audio = audio
	pause_menu.objectives_source = objectives
	# The button that closed the menu may still be down: it must not also tap a target or toggle something.
	pause_menu.resumed.connect(func() -> void: adapter.resync_edges(input_source))
	pause_menu.opened.connect(_start_pause_backdrop)
	pause_menu.resumed.connect(_stop_pause_backdrop)
	add_child(pause_menu)
	_setup_perf()
	_setup_encounters(scenario)
	comms = CommsMenuDirector.new()
	comms.main = self
	add_child(comms)
	target_menu = TargetMenuDirector.new()
	target_menu.main = self
	add_child(target_menu)
	hud.final_input = target_menu.fill_hud_input
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	if pause_menu != null and pause_menu.is_open():
		# Behind the pause menu the pad belongs to the menu: only Start (and Esc) is read.
		_handle_ui(adapter.sample_menu(input_source, delta))
		return
	if target_menu.is_open():
		# The target menu has the pad and the game is paused: only its stick, select, back and Start are read.
		target_menu.step(adapter.sample_radial(input_source, delta))
		return
	if comms.is_open():
		comms.step(adapter.sample_radial(input_source, delta))
		return
	var pc: PilotCommand = adapter.sample(input_source, delta)
	if control_lock.apply(pc, controls_locked(), camera_rig.is_playing_shot()):
		camera_rig.stop_shot()
	if debug_throttle > 0.0:
		pc.flight.main_left = maxf(pc.flight.main_left, debug_throttle)
		pc.flight.main_right = maxf(pc.flight.main_right, debug_throttle)
	if pc.flight.autotrack and not _target_for_autotrack():
		adapter.autotrack_on = false
		pc.flight.autotrack = false
	if not get_tree().paused and player_alive:
		combatant.apply_commands(pc.flight, pc.combat)
	if not get_tree().paused:
		camera_rig.set_look(delta, pc.ui.look_active, pc.ui.look_stick, pc.ui.look_mouse_px)
	_handle_ui(pc.ui)
	if pc.ui.comms_open:
		comms.open()  # says nothing when it cannot (the player is down, a cinematic): the press is simply lost
	if pc.ui.target_menu_open:
		target_menu.open()  # it says nothing when it cannot (the player is down, a cinematic): the hold is simply lost


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


func _process(delta: float) -> void:
	_update_mouse_capture()
	update_overlay(delta)
	_update_bracket()


## Rebuilds the overlay's text when it is due, `OVERLAY_INTERVAL_S` apart while it shows (at once when it appears). Public for the
## tests.
func update_overlay(delta: float) -> void:
	_overlay_in_s -= delta
	if not overlay.visible or _overlay_in_s > 0.0:
		return
	_overlay_in_s = OVERLAY_INTERVAL_S
	overlay_refreshes += 1
	overlay.show_snapshot(snapshot())


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
	s["renderer"] = String(RenderStatus.renderer())
	s["fps"] = Engine.get_frames_per_second()
	s["gpu"] = RenderingServer.get_video_adapter_name()
	s["pads"] = input_source.pad_info()
	return s


# How many ships of `type` to build: the override when it is 0 or more, else the scenario's `pools` entry (0 when it has none).
func _pool_count(scenario: Dictionary, type: StringName, override_count: int) -> int:
	if override_count >= 0:
		return override_count
	return int((scenario.get("pools", {}) as Dictionary).get(type, 0))


# The scenario's pools of every other type (the civilians, M5-T16) and their break-up chunks.
func _prepare_other_pools(scenario: Dictionary) -> void:
	var pools: Dictionary = scenario.get("pools", {})
	for type: StringName in pools:
		if type == ShipPool.DEFAULT_TYPE or type == ShipPool.ALLY_TYPE or int(pools[type]) <= 0:
			continue
		ships.prepare(type, int(pools[type]))
		debris.prepare(type)


## Grows the pool of `type` to at least `count` ships, heard like the scenario's own (the benchmark's load, M4-T01). Returns
## how many were built.
func ensure_pool(type: StringName, count: int) -> int:
	var missing: int = count - ships.pool_size(type)
	if missing <= 0:
		return 0
	var known: int = ships.pool_size()
	var built: int = ships.prepare(type, missing)
	for pooled: Combatant in ships.all_ships().slice(known):
		audio.watch_ship(pooled)
	return built


# The tick's stage timers and the benchmark (M4-T01); both pause with the world. The battle benchmark's stand-ins live in
# `World/Standins` (M4-T07), empty outside a battle run.
func _setup_perf() -> void:
	var standins := StandinDirector.new()
	standins.name = "Standins"
	standins.world = world
	standins.projectiles = projectiles
	standins.ships = ships
	standins.player = ship
	world.add_child(standins)
	TierDirector.attach(world, ships, standins)  # the low-attention tier (M4-T21): far ships as core rows
	perf_probe = PerfProbe.new()
	perf_probe.name = "PerfProbe"
	perf_probe.process_mode = Node.PROCESS_MODE_PAUSABLE
	perf_probe.world = world
	perf_probe.hits = $Combat/HitResolver as HitResolver
	perf_probe.rams = rams
	perf_probe.ships_in_play = func() -> int: return ships.in_use_count() + (1 if player_alive else 0)
	perf_probe.standins = standins
	add_child(perf_probe)
	bench = BenchRunner.new()
	bench.name = "BenchRunner"
	bench.process_mode = Node.PROCESS_MODE_PAUSABLE
	bench.main = self
	bench.probe = perf_probe
	bench.standins = standins
	add_child(bench)
	# M4-T30a: the look sheets' scene.
	var look_scene := LookScene.new()
	look_scene.name = "LookScene"
	add_child(look_scene)
	station_scene = StationScene.new()
	station_scene.name = "StationScene"
	station_scene.process_mode = Node.PROCESS_MODE_PAUSABLE
	station_scene.main = self
	add_child(station_scene)


# The encounter director in a scenario with an encounter pools file, on at once when the request asked for encounters.
func _setup_encounters(scenario: Dictionary) -> void:
	var path: String = encounter_pools_path
	if path.is_empty():
		path = EncounterDirector.pools_file(StringName(scenario.get("scenario_id", &"")))
	if path.is_empty():
		return
	encounter_director = EncounterDirector.create(self, path)
	if encounter_director != null and encounters:
		print("[encounters] ", encounter_director.enable())


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
	ship.running_lights = true  # lit at spawn; the wing follows
	for buoy: NavBuoy in buoys:
		buoy.restore()
	director.cancel_respawn()  # Back while dead: the death's own respawn must not follow
	_restart_lessons()
	combatant.cannon.reset_gate()
	combatant.cannon.reset_flashes()
	thrusters.reset()  # the dead ship's last burn does not fade out at the start
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


## The HUD's reference point (its `REF` range and closing speed): the launch point, for now. Universe coordinates.
func reference_point() -> UniversePos:
	return _spawn_position


## Every objective of the running mission (`ObjectiveBook.snapshot`), empty outside one: the pause menu's objectives source.
func objectives() -> Array[Dictionary]:
	return mission.objectives() if mission != null else ([] as Array[Dictionary])


## The running mission holds the player's controls (`MissionApi.lock_controls`): the ship flies on without them.
func controls_locked() -> bool:
	return mission != null and mission.api != null and mission.api.controls_locked


# A cinematic hides the HUD and brings the letterbox in; the comms panel keeps its subtitles (D55).
func _on_camera_mode_changed(new_mode: CameraRig.Mode) -> void:
	var cinematic: bool = new_mode == CameraRig.Mode.CINEMATIC
	hud.cinematic = cinematic
	letterbox.shown = cinematic


# The slow camera move behind the pause menu (M5-T42); the flight HUD steps aside while it runs.
func _start_pause_backdrop() -> void:
	if not bool(Settings.get_value(&"pause_backdrop")) or ship == null:
		return
	if camera_rig.start_backdrop(float(Settings.get_value(&"pause_backdrop_loop_s")), ship.bounding_radius()):
		hud.cinematic = true


func _stop_pause_backdrop() -> void:
	if camera_rig.is_backdrop_running():
		camera_rig.stop_backdrop()
		hud.cinematic = camera_rig.is_playing_shot()


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
	input.show_velocity_marker = bool(Settings.get_value(&"hud_velocity_marker"))
	input.has_reference = true
	input.reference_position = world.universe_to_local(reference_point())  # with this frame's origin: it follows every rebase
	input.tracking = ship.get_flight_output().tracking
	input.running_lights = ship.running_lights
	input.assist = ship.assist_on
	input.guns_ready = cannon.gate.capacitor == null or cannon.gate.capacitor.can_afford(1, SimClock.now())
	input.screen_sizes = hud.screens.sizes() if hud.screens != null else {}
	input.overlay_bottom_px = overlay.text_bottom_px() if overlay.visible else 0.0
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
	input.target_unknown = input.target != null and not ship.targeting.selection_identified
	# The radar's contacts straight from the targetables (M4-T36): the candidate list is built only when something cycles it.
	input.radar_contacts = RadarContacts.gather(get_tree(), ship, ship.targeting.system.sensor_range_m)
	input.selected_id = ship.targeting.selected_id()
	input.status_line = status_line
	input.roster = wings.hud_roster()
	input.roster_color = Factions.FRIENDLY_COLOR
	input.ack_line = wings.ack_text()
	if route_active():
		input.status_line = instructor_path.status_line(instructor.display_name)
		var waypoint: UniversePos = instructor_path.waypoint_position()
		if waypoint != null:
			input.has_waypoint = true
			input.waypoint_position = world.universe_to_local(waypoint)  # this frame's World frame (rebase-proof)
			input.waypoint_label = instructor_path.waypoint_label()
			input.waypoint_key = "route:" + input.waypoint_label
	return input


## Whether a ship is leading a route right now (a pooled ship reused for something else is not).
func route_active() -> bool:
	if instructor_path == null or instructor == null or not instructor.damageable.is_active() or instructor.driver == null:
		return false
	var pilot := instructor.driver.brain as AiPilot
	return pilot != null and pilot.behaviour(&"follow_path") == instructor_path


# --- ships at load (M3-T09) ------------------------------------------------------------------------------------------


# Places the scenario's `spawns` from the pool, at load.
func _spawn_scenario_ships() -> void:
	for entry: Dictionary in _scenario_spawns:
		_place_spawn(entry)


# A respawn restarts the lessons: the ships leading a route are placed again. Wing ships and fighting ships stay in play.
func _restart_lessons() -> void:
	var restarted: Array[Dictionary] = []
	for i: int in range(scenario_ships.size() - 1, -1, -1):
		if String(_scenario_entries[i]["route"]).is_empty():
			continue
		var placed: Combatant = scenario_ships[i]
		if placed.driver != null and placed.driver.brain == _scenario_brains[i]:  # not reused by the pool
			ships.release(placed)
		restarted.push_front(_scenario_entries[i])
		scenario_ships.remove_at(i)
		_scenario_brains.remove_at(i)
		_scenario_entries.remove_at(i)
	if restarted.is_empty():
		return
	instructor = null
	instructor_path = null
	for entry: Dictionary in restarted:
		_place_spawn(entry)


# Takes one spawn's ship from the pool and gives it its brain, route and wing.
func _place_spawn(entry: Dictionary) -> void:
	var type: StringName = entry["type"]
	var anchor: UniversePos = _spawn_position if StringName(entry["anchor"]) == &"player" \
			else UniversePos.new(0.0, 0.0, 0.0, _system_id)
	var ship_name: String = String(entry["name"])
	if ship_name.is_empty():
		ship_name = ships.next_name(ShipPool.ALLY_NAME_PREFIX, ShipPool.ALLY_FIRST_NUMBER) if type == ShipPool.ALLY_TYPE \
				else ships.next_name()
	var made: Dictionary = BrainFactory.from_behaviour(entry["behaviour"], anchor, hash([ship_name, scenario_seed]))
	if not bool(made["ok"]):
		push_warning("Main: spawn %s: %s" % [ship_name, made["error"]])
		return
	var brain: PilotBrain = made["brain"]
	var path: BehaviourFollowPath = null
	var route: Route = _route_named(String(entry["route"]))
	if route != null and brain is AiPilot:
		route.pace_id = combatant.targetable.get_instance_id() if route.pace == Route.PACE_PLAYER else 0
		path = BehaviourFollowPath.attach(brain as AiPilot, route)
	var forward: Vector3 = entry.get("forward", Vector3.ZERO)
	var basis: Basis = _spawn_basis if forward.is_zero_approx() else ScenarioLoader.basis_facing(forward)
	var placed: Combatant = ships.acquire(ship_name, anchor.plus_local(entry["offset"]), basis, entry["velocity"], brain, type)
	if placed == null:
		return
	if placed.cargo_pods != null:
		placed.cargo_pods.set_count(int(entry.get("cargo_pods", -1)))  # M5-T16: the spawn's pods, all by default
	placed.damageable.invulnerable = bool(entry["invulnerable"])
	scenario_ships.append(placed)
	_scenario_brains.append(brain)
	_scenario_entries.append(entry)
	if not String(entry.get("wing", "")).is_empty():
		wings.join(String(entry["wing"]), placed)  # says so itself when the wing cannot take it
	if path != null and instructor == null and not ShipCatalog.is_civilian(type):  # a civilian's route is not a lesson
		instructor = placed
		instructor_path = path


# Whether an AI ship leads the player's wing (the dogfight's ALPHA), so the player leads none of its own.
func _ai_leads_player_wing() -> bool:
	for d: Dictionary in _scenario_wings:
		if String(d["name"]).to_lower() == Wing.DEFAULT_NAME.to_lower() and String(d["leader"]) != "player":
			return true
	return false


func _route_named(route_name: String) -> Route:
	for route: Route in _scenario_routes:
		if route.name == route_name:
			return route
	return null


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
	adapter.target_hold_s = float(Settings.get_value(&"target_hold_s"))
	adapter.mouse_full_rate_px_s = float(Settings.get_value(&"mouse_full_rate_px_s"))
	Engine.physics_jitter_fix = float(Settings.get_value(&"physics_jitter_fix"))
	Engine.max_physics_steps_per_frame = int(Settings.get_value(&"physics_max_steps_per_frame"))  # M4-T24
	var godot_source := input_source as GodotInputSource
	if godot_source != null:
		godot_source.trigger_deadzone = float(Settings.get_value(&"trigger_deadzone"))


func _spawn_ship() -> void:
	var spec: ShipSpec = ShipCatalog.spec_for(ShipCatalog.PLAYER_TYPE)
	combatant = ShipAssembly.build(spec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(combatant.ship, _spawn_position, _spawn_basis)
	combatant.ship.linear_velocity = _start_velocity
	# The player is part of the wing the allies broadcast for (M3-T10): heard like an allied Starfury, to 100 km.
	combatant.targetable.broadcast_range_m = ShipPool.ALLY_BROADCAST_RANGE_M
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


# The scenario's asteroid belts (M5-T29, D63), each laid out from its seed and built as static rows.
func _spawn_belts(belts: Array) -> void:
	var shape_count: int = maxi(AsteroidBelt.shapes().size(), 1)
	for i: int in belts.size():
		var entry: Dictionary = belts[i]
		var belt := AsteroidBelt.new()
		belt.name = "Belt%d" % i
		world.spawn(belt, entry["centre"])
		var layout: BeltLayout = BeltLayout.place(entry, shape_count)
		if layout.shortfall > 0:
			push_warning("Belt%d: %d of %d rocks did not fit the box with the gap asked for" % [i, layout.shortfall, entry["count"]])
		belt.build(layout, world.get_world_3d().space, world)
		world.rebased.connect(belt.on_rebased)
		asteroid_belts.append(belt)


func _handle_ui(ui: UiCommand) -> void:
	if ui.pause:
		pause_menu.on_pause_action()
	if ui.toggle_camera:
		camera_rig.toggle()
	if ui.reset and mission == null:  # no respawn in a mission (D51)
		respawn()
	if ui.toggle_overlay:
		Settings.set_value(&"show_overlay", not bool(Settings.get_value(&"show_overlay")))
	if ui.toggle_running_lights and player_alive:
		ship.running_lights = not ship.running_lights
	if ui.screenshot:
		var result: ConsoleResult = DebugConsole.registry.execute_tokens(PackedStringArray(["screenshot"]))
		print("[screenshot] ", result.lines[0] if result.ok and not result.lines.is_empty() else result.error)
	_give_wing_orders(ui)


# Keys 1-4 (UiCommand edges, never `Input`): orders for the player's wing (architecture §16.3).
func _give_wing_orders(ui: UiCommand) -> void:
	if ui.wing_attack:
		wings.give_order(AiContext.Order.ATTACK_MY_TARGET)
	if ui.wing_form:
		wings.give_order(AiContext.Order.FORM_ON_ME)
	if ui.wing_engage:
		wings.give_order(AiContext.Order.ENGAGE_AT_WILL)
	if ui.wing_cover:
		wings.give_order(AiContext.Order.COVER_ME)


# Captures the mouse while flying. Alt (window managers use Alt+drag to move a window), the console, the pause and a window without focus give it back, and the source
# then reads it as idle.
func _update_mouse_capture() -> void:
	var godot_source := input_source as GodotInputSource
	if godot_source == null or DisplayServer.get_name() == "headless":
		return
	# A radial menu keeps the mouse too: its direction points at a slice.
	var in_play: bool = not get_tree().paused or (target_menu != null and target_menu.is_open()) or (comms != null and comms.is_open())
	var flying: bool = in_play and not DebugConsole.is_open() and get_window().has_focus() \
			and not Input.is_physical_key_pressed(KEY_ALT)
	var wanted: Input.MouseMode = Input.MOUSE_MODE_CAPTURED if flying else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted
	godot_source.mouse_free = not flying


func _update_bracket() -> void:
	if hud.visible or ship == null:  # the HUD has its own box
		overlay.hide_bracket()
		return
	var readout: TargetReadout = ship.targeting.selected_readout()
	var cam: Camera3D = camera_rig.active_camera()
	if readout == null or cam == null or cam.is_position_behind(readout.position):
		overlay.hide_bracket()
		return
	overlay.show_bracket(cam.unproject_position(readout.position))


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"belts", ConsoleVars.new({
		&"count": {"get": func() -> int: return asteroid_belts.size(), "doc": "Asteroid belts in the scenario (M5-T29)"},
		&"rocks": {"get": func() -> int: return asteroid_belts.reduce(func(n: int, b: AsteroidBelt) -> int: return n + b.rock_count, 0),
				"doc": "Rocks in every belt"},
		&"spheres": {"get": func() -> int: return asteroid_belts.reduce(func(n: int, b: AsteroidBelt) -> int: return n + b.sphere_count, 0),
				"doc": "Collision spheres (static rows) the rocks stand on"},
		&"draw_groups": {"get": func() -> int: return asteroid_belts.reduce(func(n: int, b: AsteroidBelt) -> int: return n + b.draw_groups, 0),
				"doc": "Multimeshes drawing the rocks (one per shape)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"respawn", "Reset the ship to the scenario start",
			[] as Array[ConsoleArg]), _cmd_respawn, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"window", "Resize the game window (width and height in pixels), or `window max` / `window normal` to maximize or restore it",
			[ConsoleArg.string_required(&"width_or_mode"), ConsoleArg.int_optional(&"height", null, 200, 4320)]), _cmd_window, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"throttle", "Hold both main pods at this level, 0..1 (debug; on top of the pilot's input)",
			[ConsoleArg.float_required(&"level", 0.0, 1.0)]), _cmd_throttle, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"pause", "Pause or resume the game (toggles with no argument)",
			[ConsoleArg.bool_optional(&"state")] as Array[ConsoleArg]), _cmd_pause, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"pausemenu", "Open or close the pause menu (toggles with no argument)",
			[ConsoleArg.bool_optional(&"state")] as Array[ConsoleArg]), _cmd_pausemenu, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"scenario",
			"Load a scenario (%s): sets settings.scenario for this session and reloads the scene" % ", ".join(PackedStringArray(SCENARIO_CHOICES)),
			[ConsoleArg.enum_optional(&"name", SCENARIO_CHOICES, null)] as Array[ConsoleArg]), _cmd_scenario, self)
	if instructor_path != null:
		_register_route_provider()


# Provider `route` (§16.4), on a scenario with a ship leading a route: the instructor's progress, read live.
func _register_route_provider() -> void:
	DebugConsole.registry.register_provider(&"route", ConsoleVars.new({
		&"index": {"get": func() -> int: return instructor_path.nav_number() if instructor_path != null else 0,
				"doc": "The waypoint the instructor leads to (1-based, the HUD's NAV n)"},
		&"count": {"get": func() -> int: return instructor_path.waypoint_count() if instructor_path != null else 0,
				"doc": "Waypoints on the route"},
		&"lag_m": {"get": func() -> float: return instructor_path.lag_m if instructor_path != null and instructor_path.lag_m < INF else -1.0,
				"unit": "m", "doc": "Distance from the instructor to the player (-1 when out of sight)"},
		&"state": {"get": func() -> String: return instructor_path.state_name() if route_active() else "none",
				"doc": "lead, wait (for the player), run_up, demo, hold, done; none when the instructor is not in play"},
		&"demo": {"get": func() -> String: return _route_demo(),
				"doc": "The demo at the waypoint flown to (none, roll, flip_and_burn, strafe_box, pod_turn, all_stop)"},
	}), self)


func _route_demo() -> String:
	var demo: String = instructor_path.demo_name() if instructor_path != null else ""
	return demo if not demo.is_empty() else "none"


func _cmd_throttle(args: Dictionary) -> String:
	debug_throttle = float(args[&"level"])
	return "main pods held at %.2f" % debug_throttle


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


func _cmd_respawn(_args: Dictionary) -> ConsoleResult:
	if mission != null:
		return ConsoleResult.failure("no respawn in a mission (D51)")
	respawn()
	return ConsoleResult.line("ship reset to the scenario start")


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


func _cmd_pause(args: Dictionary) -> ConsoleResult:
	# The pause menu owns the pause while it is open; resuming behind it would leave the ship uncommanded.
	if pause_menu != null and pause_menu.is_open():
		return ConsoleResult.failure("the pause menu is open: resume from it")
	if target_menu != null and target_menu.is_open():
		return ConsoleResult.failure("the target menu is open: close it first (targetmenu close)")
	if comms != null and comms.is_open():
		return ConsoleResult.failure("the comms menu is open: close it first (commsmenu close)")
	var requested: Variant = args.get(&"state")
	set_paused(not get_tree().paused if requested == null else bool(requested))
	return ConsoleResult.line("paused" if get_tree().paused else "running")


func _cmd_pausemenu(args: Dictionary) -> ConsoleResult:
	var requested: Variant = args.get(&"state")
	var want_open: bool = not pause_menu.is_open() if requested == null else bool(requested)
	if want_open:
		pause_menu.open()
	else:
		pause_menu.close()
	return ConsoleResult.line("pause menu open" if pause_menu.is_open() else "pause menu closed")


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key in [&"stick_deadzone", &"invert_y", &"target_hold_s", &"trigger_deadzone", &"mouse_full_rate_px_s", &"physics_jitter_fix",
			&"physics_max_steps_per_frame"]:
		_apply_input_settings()
