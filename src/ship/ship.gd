class_name Ship
extends RigidBody3D
## A flyable ship (architecture §3, §4, §5): a thin adapter between the pure `FlightModel` and Jolt. Every physics
## tick it hands the stored `FlightCommand` and the body-frame state to the model and applies the resulting
## `FlightOutput`: each pod nozzle's force at that nozzle (so pod torque is real `r × F` physics), the RCS force and
## torque at the centre of mass, and `mass * World.environment_accel(position)` (zero in M1).
##
## It never reads `Input`: Main (or later an AI pilot) calls `set_flight_command` / `set_combat_command` every tick
## before this node's `_physics_process` (a parent processes before its children). Held values persist until the
## next command; edges (`toggle_assist`, `target_next`, ...) act only in the first physics tick after they were set,
## so a command that is not refreshed never repeats them.
##
## Built from data in `_ready` (or again on a later `setup`): mass and inertia from the `ShipSpec`; centre of mass,
## collision primitives, gun muzzles and the cockpit eye point from the ship's `hardpoints.json`; the hull's textured mesh
## (`MeshAssets`, §7, §9) and the cockpit's meshes from `assets/generated/<asset_id>/`, loaded guarded so the scene loads (with
## warnings) before `scripts/gen_assets.sh` has run. Without hardpoints the ship cannot fly and only coasts.
##
## Children: `Hull` (MeshInstance3D: the asset's one shared textured mesh, so every copy instances; it writes its own depth, so
## effects behind the hull are hidden, §7.2; while the cockpit interior is shown it draws the hull's OBJ with the canopy cleared),
## `CockpitInterior` (first person only), `Thrusters` and `Guns` (attach points for M1-T13; `Guns` holds one Marker3D per muzzle),
## `Targeting` (`TargetingController`), `CockpitAnchor` (Marker3D at the hardpoints' `cockpit_camera`), `RunningLights` (M3-T27), and on the
## player's ship `CockpitScreens` (M3-T29).
##
## Reaction mass (M2-T14): every tick the flow the model reports is drawn from a `FuelTank` (sized by
## `ShipSpec.fuel_capacity_kg`, never drawn down while `settings.fuel_unlimited` is on), and when the tank is empty the
## model is told to cut all thrust.
##
## Contacts (M3-T04): Jolt reports up to `CONTACTS_REPORTED` contact points (`contact_monitor` on), and the ship keeps the
## World-frame sum of the forces it applied on its last tick (`applied_force`), so the `RamResolver` can tell the velocity
## change a collision caused from what the ship's own thrust did.
##
## The flight batch (M4-T10, architecture §17.9): every ship but the player's is `batched`, so `FlightBatch` (under `World`,
## priority -1) runs its model, governor and force application in one native call per tick for all of them; this node's
## `_physics_process` then only takes the command edges and leaves the forces to the batch. The player's ship, a ship whose
## `batched` is off, and every ship when the library or `perf_native` is off, fly the GDScript path below. On the batched
## path `get_flight_output()` fills its `FlightOutput` from the batch's row on demand (levels, RCS shares, forces, flags; the
## per-nozzle `nozzle_forces` stay empty) and `applied_force()` reads the batch's sum.
##
## Commands from the core's rows (M4-T33): a native AI pilot's command is written into the core and the flight batch flies
## it from there (`use_row_command`), so the driver does not hand the ship a command every think. Any command set from
## GDScript (`set_flight_command`) takes the ship back; a ship on its own model reads the row's command into `_flight`.
##
## AI ships are built lean (M4-T11, architecture §17.10, `lean`): no cockpit interior and no cockpit anchor, their collision shapes as
## shape owners of the body instead of a node each, and their plumes and markers as one multimesh each. Past
## `settings.far_ship_dot_m` from the camera an AI ship is a far dot (`set_far_dot`): its hull, plumes, markers and guns are hidden and
## the world's `FarDots` draws it. The player's ship is built as before.
##
## Rebase-safe: nothing here caches a World position between ticks. Console (§6.4, §15.1 D27): only the player's ship
## registers (`console_owner`, set before the ship enters the tree, `ShipAssembly` does it): provider `ship` and commands
## `assist [on|off]` and `refuel [kg]`, and it passes the flag on to its `TargetingController`. Other ships stay out of
## the console, because the registry replaces entries by name and would overwrite the player's.

## Assist was switched on or off (by `set_assist`, the console, or a `toggle_assist` edge).
signal assist_toggled(on: bool)
## The running lights went on or off (M3-T27).
signal running_lights_changed(on: bool)

const SCENE_PATH: String = "res://src/ship/ship.tscn"
const ASSET_ROOT: String = ShipSpec.ASSET_ROOT
const COCKPIT_MESH_FILE: String = "cockpit_interior.obj"
## Used when the hardpoints are missing (the chase camera still needs somewhere to sit); matches §8.
const DEFAULT_CHASE_OFFSET: Vector3 = Vector3(0.0, 2.5, 9.0)
## Contact points Jolt reports per tick: a few, enough for two or three bodies touching at once (`RamResolver`).
const CONTACTS_REPORTED: int = 8

## True for the ship the player flies: it registers the console providers and commands (set before the ship enters the
## tree). Every other ship leaves the console alone.
var console_owner: bool = false

## Ship type: mass, inertia, thrust, rates, gains and the asset id. The scene sets the Starfury; `setup` replaces it.
@export var spec: ShipSpec

## The frame the ship flies in: environment acceleration and the universe position (console). May be null (then the
## environment is empty and `universe_position` reads none).
var world: WorldFrame = null

## Flight assist (§5.5). Starts from `Settings.assist_default`; assigning it is `set_assist`.
var assist_on: bool:
	get = get_assist, set = set_assist

## AI ships: flight assist is always on, and nothing can switch it off (the toggle edge and `set_assist(false)` are
## ignored). Assigning true switches it on.
var force_assist: bool = false:
	set(value):
		force_assist = value
		if value:
			set_assist(true)

## Running lights (M3-T27, architecture §7.3): the three markers and the top lamp, on at spawn. The cabin glow stays on either way.
## Visual only: radar and AI contact lists never read it.
var running_lights: bool = true:
	set = set_running_lights

## Built lean (M4-T11): the AI ship's set of nodes, see the class notes. Set before the ship enters the tree (`ShipAssembly` does
## it for AI ships); the player's ship never is.
var lean: bool = false

var _assist_on: bool = true
## Whether this ship flies in the native flight batch when it can (M4-T10): on for every ship but the player's, whose
## `_ready` switches it off. Changing it joins or leaves the batch at once.
var batched: bool = true:
	set(value):
		batched = value
		if is_inside_tree():
			if value:
				_join_batch()
			else:
				_leave_batch()
var _hardpoints: Hardpoints = Hardpoints.new()
var _layout: ThrusterLayout = ThrusterLayout.new()
## Share of the gap to this tick's measured turn rate of the lead direction that the smoothed rate closes each tick.
const TRACK_RATE_SMOOTHING: float = 0.35

## The cabin lamp: a short-range emitter that competes for a light slot while the cockpit view is on, and lights the frame.
var _cabin_emitter: LightEmitter = null
## The paint the textured hull is drawn in (M4-T30b): the wing's livery and this ship's number. Set at spawn by whoever names the
## ship (`set_livery`); until then the player's ship is Alpha 01 and every other ship the plain field grey.
var livery: Livery = null
var _track_prev_dir: Vector3 = Vector3.ZERO
var _track_rate_w: Vector3 = Vector3.ZERO
var _model: FlightModel = null
var _output: FlightOutput = FlightOutput.new()
var _fuel: FuelTank = FuelTank.new()
var _flight: FlightCommand = FlightCommand.new()
var _flight_fresh: bool = false
var _combat: CombatCommand = CombatCommand.new()
static var _warned_no_screens: bool = false
var _combat_fresh: bool = false
var _interior_visible: bool = false
var _muzzles: Array[Node3D] = []
var _collision_nodes: Array[CollisionShape3D] = []
# A lean ship's collision shapes: one shape owner of the body per hit volume (M4-T11).
var _shape_owners: PackedInt32Array = PackedInt32Array()
# The hull's textured mesh (null before it is generated), the OBJ the cockpit view draws instead (the player's ship only), and
# whether the ship is drawn as a far dot.
var _hull_mesh: Mesh = null
var _cockpit_hull: Mesh = null
var _far_dot: bool = false
var _applied_force: Vector3 = Vector3.ZERO
# The flight batch (M4-T10): the batch this ship joined, its row and the physics frame of the last gather, whether the last
# path flown was the batch's (the assist state follows a change of path), and the frame `_output` was last filled from a row.
var _batch: FlightBatch = null
var _batch_row: int = -1
var _batch_tick: int = -1
var _native_last: bool = false
var _output_tick: int = -1
# The physics frame the batch applied this ship's forces in (so this node never applies them again that tick), and the frame
# `_prepare_command` last ran in (so a fallback after a refused step never prepares the command twice).
var _flown_tick: int = -1
var _prepared_tick: int = -1
# The ship flies its command from the core's row (M4-T33).
var _row_command: bool = false
## A disabled hulk (M4-T21, M12 groundwork): no pilot, no thrust, no assist; it coasts on its last motion.
var hulk: bool = false
# The flight batch flies this ship and owns its tick (M4-T35): this node's `_physics_process` is off until the batch gives it back.
var _batch_owned: bool = false

@onready var hull: MeshInstance3D = $Hull
@onready var cockpit_interior: MeshInstance3D = $CockpitInterior
@onready var thrusters: Node3D = $Thrusters
@onready var guns: Node3D = $Guns
@onready var targeting: TargetingController = $Targeting
@onready var cockpit_anchor: Marker3D = $CockpitAnchor
## The console's screens (M3-T29): the player's ship only, built once; null on every other ship.
var cockpit_screens: CockpitScreens = null


## A ship ready for `World.spawn()`: `world.spawn(Ship.create(spec, world), start_pos, start_basis)`.
static func create(p_spec: ShipSpec, p_world: WorldFrame) -> Ship:
	var ship := (load(SCENE_PATH) as PackedScene).instantiate() as Ship
	ship.setup(p_spec, p_world)
	return ship


## Where a ship type's generated files live.
static func asset_dir(p_spec: ShipSpec) -> String:
	return ASSET_ROOT.path_join(p_spec.asset_id)


func _init() -> void:
	# The world rebases its direct children through this group; `World.spawn` adds it too.
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	_assist_on = bool(Settings.get_value(&"assist_default"))


func _ready() -> void:
	if console_owner:
		batched = false
	_apply_newtonian_body()
	if lean:
		_strip_for_lean()
	targeting.setup(self, console_owner)
	_build()
	if not lean:
		_build_cabin_emitter()
	if get_node_or_null(^"LodSwitcher") == null:
		var switcher := LodSwitcher.new()
		switcher.name = "LodSwitcher"
		add_child(switcher)
	Settings.changed.connect(_on_hull_setting_changed)
	set_cockpit_interior_visible(_interior_visible)
	if console_owner:
		_register_console()


func _notification(what: int) -> void:
	# The cabin lamp leaves play with the ship and comes back with it, like the plumes and flashes.
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		_apply_cabin_emitter()


func _exit_tree() -> void:
	release_row_command()
	set_batch_owned(false)
	_leave_batch()
	DebugConsole.registry.unregister_owner(self)
	var rig: LightRig = LightRig.of(self)
	if rig != null and _cabin_emitter != null:
		rig.remove_emitter(_cabin_emitter)
	if Settings.changed.is_connected(_on_hull_setting_changed):
		Settings.changed.disconnect(_on_hull_setting_changed)


## Gives the ship its type and its world. Call it before `World.spawn` (the usual order, or use `create`); called
## after `_ready` it rebuilds mass, collision, muzzles and visuals for the new spec.
func setup(p_spec: ShipSpec, p_world: WorldFrame) -> void:
	spec = p_spec
	world = p_world
	if is_node_ready():
		_build()


func _physics_process(delta: float) -> void:
	var frame: int = Engine.get_physics_frames()
	var combat_fresh: bool = _take_combat_edges()
	if _flown_tick == frame:
		# The batch applied this tick's forces before this node ran; only the combat edges are left.
		if combat_fresh:
			targeting.apply(_combat)
		return
	if _native_last:
		# Back on this node's model: it carries on from the assist state the batch held.
		if _model != null and _batch != null:
			_model.assist.pod_yaw_smoothed = _batch.assist_state(self)
		_native_last = false
	_batch_tick = -1  # this node's model flies this tick, so the batch's row is no longer the latest
	if _row_command:
		pull_row_command()
	var b: Basis = global_basis
	var to_body: Basis = b.transposed()
	if _prepared_tick != frame:
		_prepare_command(delta, to_body)

	var env_accel: Vector3 = _environment_accel()
	_applied_force = mass * env_accel
	if _model != null:
		var fuel: FuelTank = get_fuel_tank()
		_output = _model.compute(_flight, to_body * linear_velocity, to_body * angular_velocity, to_body * env_accel,
				_assist_on and not hulk, delta, not fuel.is_empty())
		fuel.draw(_output.mass_flow_kg_s, delta)
		# Inertia grows with speed: the same thrust gives less acceleration the faster the ship goes (SpeedGovernor).
		var gain: float = SpeedGovernor.thrust_gain(linear_velocity.length(), spec.speed_limit_mps)
		for nozzle: Dictionary in _output.nozzle_forces:
			var force: Vector3 = b * (nozzle["force"] as Vector3) * gain
			var at: Vector3 = nozzle["position"]
			apply_force(force, b * at)  # offset from the body origin, world orientation
			_applied_force += force
		var rcs_force: Vector3 = b * _output.rcs_force_b * gain
		apply_central_force(rcs_force)
		_applied_force += rcs_force
		apply_torque(b * _output.rcs_torque_b)
		if _assist_on and not hulk:
			var net: Vector3 = b * (_output.pod_force_b + _output.rcs_force_b) * gain
			var cap: Vector3 = SpeedGovernor.assist_cap_correction(net, linear_velocity, spec.assist_speed_max_mps)
			apply_central_force(cap)
			_applied_force += cap
	apply_central_force(mass * env_accel)
	# Hard ceiling: nothing takes the ship past the speed limit.
	if spec != null and spec.speed_limit_mps > 0.0 and linear_velocity.length() > spec.speed_limit_mps:
		linear_velocity = SpeedGovernor.clamp_velocity(linear_velocity, spec.speed_limit_mps)

	if combat_fresh:
		targeting.apply(_combat)


# --- commands ----------------------------------------------------------------------------------------------------


## This tick's flight demand (pilot terms). Held until replaced; `toggle_assist` acts once. The ship overwrites its
## `face_dir_b` every tick with the line of sight to its selected target.
func set_flight_command(cmd: FlightCommand) -> void:
	if _row_command:
		release_row_command()
	_flight = cmd if cmd != null else FlightCommand.new()
	_flight_fresh = true


## From now on the ship flies the command its native pilot keeps in the core's row (M4-T33): the driver calls it once,
## right after handing the ship that pilot's first command.
func use_row_command() -> void:
	_row_command = true


## Whether the ship flies its command from the core's row.
func is_row_commanded() -> bool:
	return _row_command


## Clears the row flag and leaves the core alone: the driver calls it before handing over a command its row already holds,
## so the hand-over does not release that row (a ship whose flag outlived its row, under a core made again).
func forget_row_command() -> void:
	_row_command = false


## The flight command the ship holds (what its own model flies, and what the batch gathers).
func flight_command() -> FlightCommand:
	return _flight


## Takes the ship off its row's command (a new pilot, or a command set from GDScript): the core forgets it.
func release_row_command() -> void:
	if not _row_command:
		return
	_row_command = false
	var sim: SimCore = SimCore.current()
	if sim != null and sim.core != null:
		sim.core.release_command(get_instance_id())


## Copies the row's command into `_flight`, for a tick the flight batch does not fly from the row (this node's own model,
## or the batch's step without the core).
func pull_row_command() -> void:
	var sim: SimCore = SimCore.current()
	if sim == null or sim.core == null:
		return
	var row: PackedFloat64Array = sim.core.row_command(get_instance_id())
	if row.size() < 12:
		return
	_flight.main_left = row[1]
	_flight.main_right = row[2]
	_flight.retro_left = row[3]
	_flight.retro_right = row[4]
	_flight.strafe = Vector2(row[5], row[6])
	_flight.rot = Vector3(row[7], row[8], row[9])
	_flight.brake = row[10] != 0.0


## This tick's combat demand. `fire` is held until replaced; the edges act once (targeting here, weapons in M1-T13).
func set_combat_command(cmd: CombatCommand) -> void:
	_combat = cmd if cmd != null else CombatCommand.new()
	_combat_fresh = true


## The combat command of the current tick, edges cleared once they have been seen. Weapons (M1-T13) read it in their
## own `_physics_process`, which runs after the ship's.
func get_combat_command() -> CombatCommand:
	return _combat


func get_assist() -> bool:
	return _assist_on


## Switches flight assist; a change clears the assist's smoothed pod-yaw command and emits `assist_toggled`.
func set_assist(on: bool) -> void:
	if on == _assist_on or (force_assist and not on):
		return
	_assist_on = on
	if _model != null:
		_model.reset_assist()
	if _batch != null:
		_batch.reset_assist(self)
	assist_toggled.emit(on)


## Teleports to a World-local pose at rest (respawn): velocities zeroed, assist state cleared, tank refilled, no
## interpolation smear.
func reset_to(xform: Transform3D) -> void:
	transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_fuel.refuel()
	if _model != null:
		_model.reset_assist()
		_output = _idle_output()
	if _batch != null:
		_batch.reset_assist(self)
	_batch_tick = -1
	_output_tick = -1
	reset_physics_interpolation()


## Parks the body for the low-attention tier (M4-T21): hidden and not processing, so it leaves Jolt, the scan and every
## per-ship pass, while its name, pilot, hull and commands stay. The tier row carries its motion from here.
func park_for_tier() -> void:
	set_meta(&"_scs_tier_row", true)
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## Brings the body back from its tier row exactly where the row left it: the pose, the velocities and the assist's state;
## the row command, when it flies one, is still in the core.
func unpark_from_tier(xform: Transform3D, velocity: Vector3, spin: Vector3, pod_yaw: float) -> void:
	if has_meta(&"_scs_tier_row"):
		remove_meta(&"_scs_tier_row")
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	global_transform = xform
	linear_velocity = velocity
	angular_velocity = spin
	set_assist_state(pod_yaw)
	_batch_tick = -1
	_output_tick = -1
	reset_physics_interpolation()


## Whether the body is parked for the tier now.
func is_tier_parked() -> bool:
	return has_meta(&"_scs_tier_row")


## The assist's smoothed pod-yaw command as the path that flew the last tick holds it.
func assist_state() -> float:
	if _native_last and _batch != null and is_instance_valid(_batch):
		return _batch.assist_state(self)
	return _model.assist.pod_yaw_smoothed if _model != null else 0.0


## Sets the assist's smoothed pod-yaw command on both paths, so whichever flies next carries on from it.
func set_assist_state(value: float) -> void:
	if _model != null:
		_model.assist.pod_yaw_smoothed = value
	if _batch != null and is_instance_valid(_batch):
		_batch.set_assist_state(self, value)


## Makes the ship a drifting hulk (M4-T21): its command cleared (and its row command released), no assist from now on.
func set_hulk(on: bool) -> void:
	if on == hulk:
		return
	hulk = on
	if on:
		set_flight_command(FlightCommand.new())


## Switches the running lights.
func set_running_lights(on: bool) -> void:
	if on == running_lights:
		return
	running_lights = on
	var lights := get_node_or_null(^"RunningLights") as RunningLights
	if lights != null:
		lights.apply()
	running_lights_changed.emit(on)


# --- state -------------------------------------------------------------------------------------------------------


## Nose direction, World frame (`-basis.z`).
func forward() -> Vector3:
	return -global_basis.z


## Linear velocity in body axes (+X right, +Y up, -Z forward), m/s.
func body_velocity() -> Vector3:
	return global_basis.transposed() * linear_velocity


## Angular velocity in body axes, rad/s: +X pitches the nose up, +Y yaws it left, +Z rolls left.
func body_angular_velocity() -> Vector3:
	return global_basis.transposed() * angular_velocity


## World-frame sum of the forces the ship applied on its last physics tick (nozzles, RCS, the assist's speed cap and the
## environment), N. Jolt adds `applied_force() / mass * delta` to the velocity in the coming step; anything beyond that
## came from a contact.
func applied_force() -> Vector3:
	if _in_batch_row():
		return _batch.out_vectors[_batch_row * FlightBatch.OUT_VECTORS + FlightBatch.Out.FORCE]
	return _applied_force


## Which path flew the last physics tick: `native` (the flight batch, M4-T10) or `gdscript` (this node's own model).
func flight_path() -> StringName:
	return &"native" if _in_batch_row() else &"gdscript"


## The flight batch's gather for this tick (M4-T10): the assist edge, the brake's facing and the auto-track's lead (as
## `_physics_process` would), the command packed at `row`, and the marks that tell `_physics_process` the batch flies this tick.
func batch_gather(batch: FlightBatch, row: int, frame: int, delta: float, fuel_unlimited: bool,
		scalars: PackedFloat64Array, vectors: PackedVector3Array, flags: PackedByteArray) -> void:
	if _batch_owned and _take_combat_edges():
		targeting.apply(_combat)  # this node's tick is off (M4-T35): the edges land here, before the World's rebase at 0
	_prepare_command(delta, global_basis.transposed())
	_fuel.unlimited = fuel_unlimited
	FlightBatch.pack_command(_flight, _environment_accel(), _assist_on and not hulk, not _fuel.is_empty(), scalars, vectors, flags,
			row)
	if not _native_last:
		# Onto the batch: it carries on from the assist state this node's model held.
		if _model != null:
			batch.set_assist_state(self, _model.assist.pod_yaw_smoothed)
		_native_last = true
	_batch = batch
	_batch_row = row
	_batch_tick = frame
	_flown_tick = frame
	_output_tick = -1


## The batch's step refused this tick's arrays after the gather: this node applies the forces itself.
func batch_refused() -> void:
	_flown_tick = -1
	set_batch_owned(false)


## Whether the flight batch owns this ship's tick (M4-T35): the batch flies it and this node's `_physics_process` is off
## until the batch gives the tick back (it stops flying the ship, the ship leaves it, the setting goes off).
func set_batch_owned(owned: bool) -> void:
	if owned == _batch_owned:
		return
	_batch_owned = owned
	set_physics_process(not owned)


func is_batch_owned() -> bool:
	return _batch_owned


## Flies this node's own model for this tick at once (the batch gave the tick back inside the tick, after the engine listed
## what processes this tick).
func fly_own_tick_now(delta: float) -> void:
	if is_inside_tree() and can_process() and not _batch_owned:
		_physics_process(delta)


## The batch draws this tick's reaction mass for a batched ship (only when the tank is finite).
func batch_draw_fuel(flow_kg_s: float, delta: float) -> void:
	_fuel.draw(flow_kg_s, delta)


## The reaction-mass tank, with `unlimited` brought in line with `settings.fuel_unlimited` as of now. Never null.
func get_fuel_tank() -> FuelTank:
	_fuel.unlimited = bool(Settings.get_value(&"fuel_unlimited"))
	return _fuel


## What the flight model produced on the last physics tick (all zero before the first one). Never null. On the batched
## path it is filled from the batch's row when first asked after a tick.
func get_flight_output() -> FlightOutput:
	if _output_tick != _batch_tick and _in_batch_row():
		_fill_output_from_batch()
		_output_tick = _batch_tick
	return _output


## The pod nozzles the flight model drives (also the cosmetic RCS nozzles, for glow).
func get_layout() -> ThrusterLayout:
	return _layout


## The parsed hardpoints (nozzle radii, RCS tags and anything else visuals need). Check `valid`.
func get_hardpoints() -> Hardpoints:
	return _hardpoints


## One Marker3D per gun muzzle under `Guns`, in hardpoints order (left, right); -Z points down the barrel.
func get_muzzles() -> Array[Node3D]:
	return _muzzles.duplicate()


## The muzzles' transforms in the ship's frame, in hardpoints order, as data (M4-T35): what the cannon kernel fires from
## and the frame's flashes can be placed by (`global_transform * local`), without a marker node per muzzle.
func get_muzzle_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for entry: Dictionary in _hardpoints.muzzles:
		out.append(entry["transform"])
	return out


## Ship-local chase camera offset, for `CameraRig.setup` (the hardpoints' `chase_anchor`).
func get_chase_offset() -> Vector3:
	return _hardpoints.chase_anchor if _hardpoints.valid else DEFAULT_CHASE_OFFSET


## The camera rig's interior callback: the cockpit interior is drawn in first person only.
func set_cockpit_interior_visible(shown: bool) -> void:
	_interior_visible = shown and cockpit_interior != null
	if is_node_ready():
		if cockpit_interior != null:
			cockpit_interior.visible = _interior_visible
		_apply_hull_visuals()
		_apply_cabin_emitter()
		if cockpit_screens != null:
			cockpit_screens.set_shown(shown)


func is_cockpit_interior_visible() -> bool:
	return _interior_visible


# The hull for what the camera sees: the textured mesh, or from inside the cockpit the hull's OBJ (the view the cockpit was built
# around) with its canopy glass and window frames cleared; nothing while the ship is a far dot.
func _apply_hull_visuals() -> void:
	if not is_node_ready():
		return
	var inside: bool = _interior_visible and _cockpit_hull != null
	hull.mesh = _cockpit_hull if inside else _hull_mesh
	hull.visible = not _far_dot
	_apply_canopy_glass(inside)


## The hull's textured mesh as loaded (null before the assets are generated).
func hull_mesh() -> Mesh:
	return _hull_mesh


## Draws the ship as a far dot (M4-T11): its hull, plumes, markers and guns hidden, and a point in the world's `FarDots` instead; off
## shows them again. Its `LodSwitcher` decides from the camera's distance.
func set_far_dot(on: bool) -> void:
	if on == _far_dot:
		return
	_far_dot = on
	_apply_far_interpolation()
	_apply_hull_visuals()
	for path: NodePath in [^"ThrusterVisuals", ^"Thrusters", ^"RunningLights", ^"Guns"]:
		var node := get_node_or_null(path) as Node3D
		if node != null:
			node.visible = not on
	var dots: FarDots = FarDots.attach(world) if on else FarDots.of(world)
	if dots != null:
		if on:
			dots.add(self)
		else:
			dots.remove(self)


# A far dot's ship is not interpolated: nothing of it is drawn but a dot, so a rebase has no history to reset on its nodes
# (M4-T14). Back near, it blends again from where it is.
func _apply_far_interpolation() -> void:
	var off: bool = _far_dot and bool(Settings.get_value(&"far_ship_interpolation_off"))
	var mode: Node.PhysicsInterpolationMode = Node.PHYSICS_INTERPOLATION_MODE_OFF if off else Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	if physics_interpolation_mode == mode:
		return
	physics_interpolation_mode = mode
	reset_physics_interpolation()


## Whether the ship is drawn as a far dot now.
func is_far_dot() -> bool:
	return _far_dot


## The radius of a sphere that holds the hull, m (its hit volumes' bound, 10 m before the hull is built).
func bounding_radius() -> float:
	var damageable: Damageable = Damageable.of(self)
	return damageable.bounding_radius if damageable != null and damageable.bounding_radius > 0.0 else 10.0


## The name other ships read on this one's targeting marker.
func display_name() -> String:
	var marker := get_node_or_null(^"Targetable") as Targetable
	return marker.display_name if marker != null else String(name)


# --- build -------------------------------------------------------------------------------------------------------


# §5.4: no gravity, no damping on the body *and* REPLACE so the project defaults are not combined in, never asleep
# (a coasting ship must keep coasting), no CCD. Set here as well as in the scene so an edited scene cannot break it.
# Contacts are reported for the ram damage (M3-T04).
func _apply_newtonian_body() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	can_sleep = false
	continuous_cd = false
	# Nothing connects body_entered; the direct state's contact list (the ram resolver's) needs only the count (M4-T35).
	contact_monitor = bool(Settings.get_value(&"ship_contact_monitor"))
	max_contacts_reported = CONTACTS_REPORTED
	if collision_layer == 1 and collision_mask == 1:  # layers a caller already chose before the ship entered the tree stay
		_apply_collision_layers()


# AI ships (the lean ones) sit on the fighter layer (M4-T14); every other ship keeps the default layer and collides with everything.
func _apply_collision_layers() -> void:
	if bool(Settings.get_value(&"collision_layers")):
		var kind: StringName = &"fighter" if lean else &"player"
		collision_layer = CollisionLayers.layer_of(kind)
		collision_mask = CollisionLayers.mask_of(kind)
	else:
		collision_layer = 1
		collision_mask = 1


# A lean ship (M4-T11) needs no first-person interior and no camera anchor; the empty plume holder goes too (`ShipAssembly` puts its
# plumes on the body).
func _strip_for_lean() -> void:
	var unused: Array[Node] = [cockpit_interior, cockpit_anchor]
	if thrusters != null and thrusters.get_child_count() == 0:
		unused.append(thrusters)
		thrusters = null
	for node: Node in unused:
		if node != null:
			remove_child(node)
			node.free()
	cockpit_interior = null
	cockpit_anchor = null


func _build() -> void:
	_clear_built()
	if spec == null:
		push_warning("Ship: no ShipSpec; the ship cannot fly")
		_hardpoints = Hardpoints.new()
		_layout = ThrusterLayout.new()
		_model = null
		_output = FlightOutput.new()
		_fuel = FuelTank.new()
		return
	mass = spec.mass
	inertia = spec.inertia
	_fuel = FuelTank.new(spec.fuel_capacity_kg)
	_hardpoints = Hardpoints.load_file(spec.hardpoints_path())
	_layout = _hardpoints.thruster_layout()
	_model = null
	if not _hardpoints.valid:
		push_warning("Ship: %s; the ship cannot fly" % _hardpoints.error)
	elif not _layout.valid:
		push_warning("Ship: %s; the ship cannot fly" % _layout.error)
	else:
		_model = FlightModel.new(spec, _layout)
	if _hardpoints.valid:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = _hardpoints.center_of_mass
		if cockpit_anchor != null:
			cockpit_anchor.transform = _hardpoints.cockpit_camera
		_place_cabin_emitter()
		_build_collision()
		_build_muzzles()
	_load_visuals()
	_build_running_lights()
	_build_cockpit_screens()
	_output = _idle_output()
	_output_tick = -1
	_join_batch()


# Freed at once rather than queued: a rebuild must not leave the old shapes in the body for the rest of the frame.
func _clear_built() -> void:
	for node: Node in _collision_nodes:
		remove_child(node)
		node.free()
	_collision_nodes.clear()
	for owner_id: int in _shape_owners:
		remove_shape_owner(owner_id)
	_shape_owners.clear()
	for marker: Node3D in _muzzles:
		marker.get_parent().remove_child(marker)
		marker.free()
	_muzzles.clear()


# A node per hit volume, or on a lean ship a shape owner of the body each: the same shapes and contacts without the nodes.
func _build_collision() -> void:
	for entry: Dictionary in _hardpoints.collision:
		if lean:
			var owner_id: int = create_shape_owner(self)
			shape_owner_add_shape(owner_id, entry["shape"])
			shape_owner_set_transform(owner_id, entry["transform"])
			_shape_owners.append(owner_id)
			continue
		var node := CollisionShape3D.new()
		node.name = ("Collision_" + str(entry["name"])).to_pascal_case().validate_node_name()
		node.shape = entry["shape"]
		node.transform = entry["transform"]
		add_child(node)
		_collision_nodes.append(node)


func _build_muzzles() -> void:
	if lean:
		return  # the muzzles are data (M4-T35): the cannon fires from the transforms, the pool flashes them
	for entry: Dictionary in _hardpoints.muzzles:
		var marker := Marker3D.new()
		marker.name = ("Muzzle_" + str(entry["name"])).to_pascal_case().validate_node_name()
		marker.transform = entry["transform"]
		guns.add_child(marker)
		_muzzles.append(marker)


# On the ship the player flies, when its hardpoints have a console: a rebuild only places what exists.
func _build_cockpit_screens() -> void:
	if not console_owner or cockpit_interior == null or cockpit_interior.mesh == null:
		return
	if _hardpoints.screens.is_empty():
		if _hardpoints.valid and not _warned_no_screens:
			_warned_no_screens = true  # stale generated assets would otherwise just look like the old 2D HUD
			push_warning("Ship: %s lists no screens (run scripts/gen_assets.sh)" % spec.asset_id)
		return
	if cockpit_screens == null:
		cockpit_screens = CockpitScreens.new()
		cockpit_screens.name = "CockpitScreens"
		add_child(cockpit_screens)
	cockpit_screens.setup(_hardpoints.screens, cockpit_interior)
	cockpit_screens.set_shown(_interior_visible)


# One node with three markers per ship, built once: a rebuild only places them again.
func _build_running_lights() -> void:
	var lights := get_node_or_null(^"RunningLights") as RunningLights
	if lights == null:
		lights = RunningLights.new()
		lights.name = "RunningLights"
		lights.instanced = lean
		add_child(lights)
	lights.setup(self)


# The hull's textured mesh, and on a ship with a cockpit the interior and the hull's OBJ its view was built around.
func _load_visuals() -> void:
	var dir: String = asset_dir(spec)
	_hull_mesh = MeshAssets.for_asset(spec.asset_id)
	if _hull_mesh == null:
		push_warning("Ship: %s has no textured mesh (run scripts/gen_assets.sh, then import); the hull is not drawn" % spec.asset_id)
	var section: Dictionary = MeshAssets.livery_section(spec.asset_id)
	if livery == null and not section.is_empty():
		livery = Livery.player(section) if console_owner else Livery.for_wing("", 0, section)
	_apply_livery()
	_cockpit_hull = null
	if cockpit_interior != null:
		var with_interior: bool = spec.has_cockpit_interior
		cockpit_interior.mesh = _load_mesh(dir.path_join(COCKPIT_MESH_FILE)) if with_interior else null
		MeshMaterials.matte(cockpit_interior.mesh)
		_make_double_sided(cockpit_interior.mesh)
		MeshMaterials.cockpit(cockpit_interior.mesh)
		if with_interior:
			_cockpit_hull = _load_mesh(dir.path_join(spec.asset_id + ".obj"))
			MeshMaterials.matte(_cockpit_hull)
			_make_double_sided(_cockpit_hull)
	_apply_hull_visuals()


## Paints the hull in `p_livery` (its wing's colours and pattern and its number); null gives back the plain livery, or none for a
## hull without a livery table.
func set_livery(p_livery: Livery) -> void:
	var section: Dictionary = MeshAssets.livery_section(spec.asset_id) if spec != null else {}
	livery = p_livery if p_livery != null else (Livery.for_wing("", 0, section) if not section.is_empty() else null)
	_apply_livery()


# The hull node carries the livery as instance values.
func _apply_livery() -> void:
	if livery != null and hull != null:
		livery.apply(hull)


func _on_hull_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"collision_layers":
		_apply_collision_layers()
	elif key == &"far_ship_interpolation_off":
		_apply_far_interpolation()


# A soft red lamp just behind and above the pilot's eyes. Its range stops short of the wings, so it lights only the cockpit frame.
func _build_cabin_emitter() -> void:
	_cabin_emitter = LightEmitter.new("cabin", LightEmitter.PRIORITY_CABIN, NavLights.CABIN_LAMP_COLOR,
			float(Settings.get_value(&"cockpit_light_energy")), 4.5, 0.8)
	_cabin_emitter.anchor = self
	_place_cabin_emitter()
	_apply_cabin_emitter()


func _place_cabin_emitter() -> void:
	if _cabin_emitter != null and cockpit_anchor != null:
		_cabin_emitter.offset = cockpit_anchor.position + Vector3(0.0, 0.45, 0.5)


# The cabin lamp competes for a slot only in the cockpit camera; no other ship's interior is ever shown, so the pool adds no candidates.
# A disabled ship (the player dead, a parked ship) gives none.
func _apply_cabin_emitter() -> void:
	var rig: LightRig = LightRig.of(self)
	if rig == null or _cabin_emitter == null:
		return
	if _interior_visible and process_mode != Node.PROCESS_MODE_DISABLED:
		rig.add_emitter(_cabin_emitter)
	else:
		rig.remove_emitter(_cabin_emitter)


# From inside, the interior is the whole cabin: the hull's canopy glass would tint the view and its window frames would cross the
# side panes, so while the interior is shown those surfaces of the cockpit hull get an override that draws nothing.
func _apply_canopy_glass(inside: bool) -> void:
	var mesh: Mesh = hull.mesh
	for i: int in hull.get_surface_override_material_count():
		hull.set_surface_override_material(i, null)
	if mesh == null or not inside:
		return
	for i: int in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(i)
		if material != null and String(material.resource_name).contains("canopy"):
			hull.set_surface_override_material(i, _clear_glass())


static var _clear_material: StandardMaterial3D = null


static func _clear_glass() -> StandardMaterial3D:
	if _clear_material == null:
		_clear_material = StandardMaterial3D.new()
		_clear_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_clear_material.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
		_clear_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_clear_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _clear_material


# The cockpit bars are mirrored copies, whose faces wind the other way and vanish from inside with back-face culling on;
# the cockpit hull is seen from inside too. Both draw both sides.
static func _make_double_sided(mesh: Mesh) -> void:
	if mesh == null:
		return
	for i: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as BaseMaterial3D
		if material != null and material.cull_mode != BaseMaterial3D.CULL_DISABLED:
			material.cull_mode = BaseMaterial3D.CULL_DISABLED


static func _load_mesh(path: String) -> Mesh:
	if ResourceLoader.exists(path):
		var mesh: Mesh = load(path) as Mesh
		if mesh != null:
			return mesh
	push_warning("Ship: %s is missing or not imported (run scripts/gen_assets.sh, then import)" % path)
	return null


# Zero demand at rest with no time step: right-sized level arrays for visuals before the first tick, no state change.
func _idle_output() -> FlightOutput:
	if _model == null:
		return FlightOutput.new()
	return _model.compute(FlightCommand.new(), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, _assist_on, 0.0)


# A combat command that was not refreshed since the last tick keeps `fire` but loses its edges. Returns whether this
# tick's command is new.
func _take_combat_edges() -> bool:
	var fresh: bool = _combat_fresh
	_combat_fresh = false
	if not fresh and (_combat.weapon_next or _combat.target_next or _combat.target_ahead):
		var held := CombatCommand.new()
		held.fire = _combat.fire
		_combat = held
	return fresh


# Fills `track_dir_b` (the lead point of the selected target) and `track_rate_b` (how fast that direction is turning, from the
# change since the last tick, lightly smoothed) while auto-track is on.
func _update_tracking(delta: float, to_body: Basis) -> void:
	var offset: Vector3 = _lead_offset() if _flight.autotrack else Vector3.ZERO
	if offset.is_zero_approx() or delta <= 0.0:
		_flight.track_dir_b = Vector3.ZERO
		_flight.track_rate_b = Vector3.ZERO
		_track_prev_dir = Vector3.ZERO
		_track_rate_w = Vector3.ZERO
		return
	var dir: Vector3 = offset.normalized()
	if not _track_prev_dir.is_zero_approx():
		# Small-angle rotation vector between the two directions, per second.
		_track_rate_w = _track_rate_w.lerp(_track_prev_dir.cross(dir) / delta, TRACK_RATE_SMOOTHING)
	_track_prev_dir = dir
	_flight.track_dir_b = to_body * offset
	_flight.track_rate_b = to_body * _track_rate_w


# World-frame offset from the ship to the lead point of the selected target (the same solution as the HUD's lead reticle:
# where a bolt fired now meets it), or to the target itself when there is no intercept in range. Zero without a target.
func _lead_offset() -> Vector3:
	var readout: TargetReadout = targeting.selected_readout()
	if readout == null or spec == null:
		return Vector3.ZERO
	var weapon: WeaponSpec = spec.weapon if spec.weapon != null else WeaponSpec.new()
	var muzzle_centre: Vector3 = global_position
	if not _muzzles.is_empty():
		muzzle_centre = Vector3.ZERO
		for muzzle: Node3D in _muzzles:
			muzzle_centre += muzzle.global_position
		muzzle_centre /= float(_muzzles.size())
	elif not _hardpoints.muzzles.is_empty():
		muzzle_centre = Vector3.ZERO
		var xf: Transform3D = global_transform
		for entry: Dictionary in _hardpoints.muzzles:
			muzzle_centre += xf * (entry["transform"] as Transform3D).origin  # a marker's global position, without the marker
		muzzle_centre /= float(_hardpoints.muzzles.size())
	var lead: Dictionary = InterceptMath.solve(muzzle_centre, linear_velocity, readout.position, readout.velocity,
			weapon.muzzle_speed_mps, weapon.lifetime_s)
	return (lead["lead_point"] as Vector3) - global_position


func _environment_accel() -> Vector3:
	if world == null or not is_instance_valid(world):
		return Vector3.ZERO
	return world.environment_accel(position)


# --- the flight batch (M4-T10) ----------------------------------------------------------------------------------------


# The command as the model reads it this tick, on either path: the assist edge taken, the brake's facing and the auto-track's
# lead written in the body frame `to_body`. Once per tick, whichever path calls first.
func _prepare_command(delta: float, to_body: Basis) -> void:
	if _flight_fresh and _flight.toggle_assist:
		set_assist(not _assist_on)
	_flight_fresh = false
	if _model != null:
		_flight.face_dir_b = to_body * targeting.selected_offset()  # what the brake faces (§5.5); zero = no target
		_update_tracking(delta, to_body)
	_prepared_tick = Engine.get_physics_frames()


# Whether the batch's outputs hold a row for this ship from its latest step.
func _in_batch_row() -> bool:
	return _batch != null and _batch_tick >= 0 and _batch_tick == _batch.tick


# Joins the world's batch when this ship can fly in it, re-registering a rebuilt ship; otherwise (or on another world) leaves.
func _join_batch() -> void:
	var eligible: bool = batched and _model != null and world != null and is_instance_valid(world) and is_inside_tree()
	var batch: FlightBatch = FlightBatch.attach(world) if eligible else null
	if batch != _batch:
		_leave_batch()
	if batch == null:
		return
	_batch = batch
	batch.join(self)


func _leave_batch() -> void:
	set_batch_owned(false)
	if _batch == null:
		return
	if is_instance_valid(_batch):
		if _native_last and _model != null:
			_model.assist.pod_yaw_smoothed = _batch.assist_state(self)
		_batch.leave(self)
	_native_last = false
	_batch_tick = -1
	_batch = null


# `_output` from the batch's row: the levels per group and per pod, the RCS shares, the body-frame forces and torques, the
# flags and the flow. The per-nozzle list stays empty: nothing reads it for a batched ship.
func _fill_output_from_batch() -> void:
	var v: int = _batch_row * FlightBatch.OUT_VECTORS
	var s: int = _batch_row * FlightBatch.OUT_SCALARS
	var ov: PackedVector3Array = _batch.out_vectors
	var os: PackedFloat64Array = _batch.out_scalars
	var out: FlightOutput = _output
	out.nozzle_forces.clear()
	out.group_levels = PackedFloat64Array([os[s], os[s + 1], os[s + 2], os[s + 3]])
	var pods: int = _layout.pod_count()
	if out.main_levels.size() != pods:
		out.main_levels.resize(pods)
		out.retro_levels.resize(pods)
	for pod: int in pods:
		var right: bool = _layout.pod_is_right[pod] != 0
		out.main_levels[pod] = os[s + (ThrusterLayout.Group.R_MAIN if right else ThrusterLayout.Group.L_MAIN)]
		out.retro_levels[pod] = os[s + (ThrusterLayout.Group.R_RETRO if right else ThrusterLayout.Group.L_RETRO)]
	out.pod_force_b = ov[v + FlightBatch.Out.POD_FORCE]
	out.pod_torque_b = ov[v + FlightBatch.Out.POD_TORQUE]
	out.rcs_force_b = ov[v + FlightBatch.Out.RCS_FORCE]
	out.rcs_torque_b = ov[v + FlightBatch.Out.RCS_TORQUE]
	out.force_b = out.pod_force_b + out.rcs_force_b
	out.torque_b = out.pod_torque_b + out.rcs_torque_b
	out.rcs_force_level = ov[v + FlightBatch.Out.RCS_FORCE_LEVEL]
	out.rcs_torque_level = ov[v + FlightBatch.Out.RCS_TORQUE_LEVEL]
	out.rate_target_b = ov[v + FlightBatch.Out.RATE_TARGET]
	out.trim = os[s + FlightBatch.OutScalar.TRIM]
	out.pod_yaw_cmd = os[s + FlightBatch.OutScalar.POD_YAW_CMD]
	out.mass_flow_kg_s = os[s + FlightBatch.OutScalar.MASS_FLOW]
	out.face_error_rad = os[s + FlightBatch.OutScalar.FACE_ERROR]
	out.braking = os[s + FlightBatch.OutScalar.BRAKING] != 0.0
	out.facing = os[s + FlightBatch.OutScalar.FACING] != 0.0
	out.tracking = os[s + FlightBatch.OutScalar.TRACKING] != 0.0
	out.propellant_empty = os[s + FlightBatch.OutScalar.PROPELLANT_EMPTY] != 0.0
	out.assist_on = _assist_on


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"assist", "Toggle or set flight assist",
			[ConsoleArg.bool_optional(&"state")]), _cmd_assist, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"running_lights", "Toggle or set the running lights (the wing follows)",
			[ConsoleArg.bool_optional(&"state")]), _cmd_running_lights, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"refuel", "Refill the reaction-mass tank, or add kg",
			[ConsoleArg.float_optional(&"kg", null, 0.0)]), _cmd_refuel, self)
	DebugConsole.registry.register_provider(&"ship", ConsoleVars.new({
		&"position": {"get": func() -> Vector3: return position, "unit": "m", "doc": "World-local position"},
		&"universe_position": {"get": _universe_position, "unit": "m", "doc": "Universe position (64-bit)"},
		&"velocity": {"get": func() -> Vector3: return linear_velocity,
				"set": func(value: Variant) -> void: linear_velocity = value as Vector3,
				"type": TYPE_VECTOR3, "unit": "m/s", "doc": "World-frame velocity (settable: a debug shove, the only console write to it)"},
		&"speed": {"get": func() -> float: return linear_velocity.length(), "type": TYPE_FLOAT, "unit": "m/s",
				"doc": "Speed relative to the World frame"},
		&"body_velocity": {"get": body_velocity, "unit": "m/s",
				"doc": "Velocity in body axes (+x right, +y up, -z forward)"},
		&"angular_rate_dps": {"get": _angular_rate_dps, "unit": "deg/s",
				"doc": "Angular rate in body axes (+x pitch up, +y yaw left, +z roll left)"},
		&"assist_on": {"get": get_assist, "set": set_assist, "type": TYPE_BOOL, "doc": "Flight assist"},
		&"running_lights": {"get": func() -> bool: return running_lights, "set": set_running_lights, "type": TYPE_BOOL,
				"doc": "Port, starboard and top lights (the cabin glow stays on)"},
		&"trim": {"get": func() -> float: return _output.trim,
				"doc": "0..1: how far the flight computer cut the trimmed pod side (POD TRIM)"},
		&"pod_yaw": {"get": _pod_yaw_dps, "unit": "deg/s",
				"doc": "Assist pod-yaw command, pilot terms (+ = yaw right); 0 with assist off"},
		&"main_levels": {"get": func() -> Dictionary: return _levels_by_pod(_output.main_levels),
				"doc": "Main nozzle level per pod after trim, 0..1"},
		&"retro_levels": {"get": func() -> Dictionary: return _levels_by_pod(_output.retro_levels),
				"doc": "Retro nozzle level per pod after trim, 0..1"},
		&"mass_flow": {"get": func() -> float: return _output.mass_flow_kg_s, "unit": "kg/s",
				"doc": "Reaction mass flow (drawn from the tank unless settings.fuel_unlimited)"},
		&"fuel_kg": {"get": func() -> float: return get_fuel_tank().mass_kg(), "set": _set_fuel_kg,
				"type": TYPE_FLOAT, "unit": "kg", "min": 0.0,
				"doc": "Reaction mass in the tank (reads full while settings.fuel_unlimited)"},
		&"fuel_fraction": {"get": func() -> float: return get_fuel_tank().fraction(),
				"doc": "Tank level 0..1; 1 while settings.fuel_unlimited. The HUD's fuel gauge"},
	}), self)


func _cmd_assist(args: Dictionary) -> ConsoleResult:
	return DebugConsole.registry.toggle("ship.assist_on", args[&"state"])


func _cmd_running_lights(args: Dictionary) -> ConsoleResult:
	return DebugConsole.registry.toggle("ship.running_lights", args[&"state"])


func _cmd_refuel(args: Dictionary) -> String:
	var amount: Variant = args.get(&"kg")
	var tank: FuelTank = get_fuel_tank()
	var added: float = tank.refuel(INF if amount == null else float(amount))
	var line: String = "added %.0f kg, tank %.0f / %.0f kg" % [added, tank.mass_kg(), tank.capacity_kg]
	if tank.unlimited:
		line += " (settings.fuel_unlimited is on: never drawn down)"
	return line


# Writable `ship.fuel_kg`: "" on success, else the reason.
func _set_fuel_kg(value: float) -> String:
	var tank: FuelTank = get_fuel_tank()
	if value > tank.capacity_kg:
		return "ship.fuel_kg must be in 0..%s, got %s" % [tank.capacity_kg, value]
	tank.set_kg(value)
	return ""


func _universe_position() -> Variant:
	if world == null or not is_instance_valid(world):
		return null
	var u: UniversePos = world.to_universe(position)
	return PackedFloat64Array([u.x, u.y, u.z])


func _angular_rate_dps() -> Vector3:
	var w: Vector3 = body_angular_velocity()
	return Vector3(rad_to_deg(w.x), rad_to_deg(w.y), rad_to_deg(w.z))


func _pod_yaw_dps() -> float:
	return _output.pod_yaw_cmd * spec.rate_max.y if spec != null else 0.0


func _levels_by_pod(levels: PackedFloat64Array) -> Dictionary:
	var out: Dictionary = {}
	for pod: int in mini(levels.size(), _layout.pod_names.size()):
		out[_layout.pod_names[pod]] = levels[pod]
	return out
