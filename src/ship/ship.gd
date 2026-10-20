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
## collision primitives, gun muzzles and the cockpit eye point from the ship's `hardpoints.json`; the hull splats and
## meshes from `assets/generated/<asset_id>/`, loaded guarded so the scene loads (with warnings) before
## `scripts/gen_assets.sh` has run. Without hardpoints the ship cannot fly and only coasts.
##
## Children: `HullSplats` (GaussianSplatNode, identity in the scene: GDGS applies its own Rz(180°) on entering the
## tree, §9.1), `HullMeshFallback` (shown when `SplatStatus` finds no splat backend, or forced), `CockpitInterior`
## (first person only), `Thrusters` and `Guns` (attach points for M1-T13; `Guns` holds one Marker3D per muzzle),
## `Targeting` (`TargetingController`), `CockpitAnchor` (Marker3D at the hardpoints' `cockpit_camera`).
##
## Rebase-safe: nothing here caches a World position between ticks. Console: provider `ship` and command
## `assist [on|off]` (§6.4).

## Assist was switched on or off (by `set_assist`, the console, or a `toggle_assist` edge).
signal assist_toggled(on: bool)

const SCENE_PATH: String = "res://src/ship/ship.tscn"
const ASSET_ROOT: String = "res://assets/generated"
const COCKPIT_MESH_FILE: String = "cockpit_interior.obj"
## Used when the hardpoints are missing (the chase camera still needs somewhere to sit); matches §8.
const DEFAULT_CHASE_OFFSET: Vector3 = Vector3(0.0, 2.5, 9.0)

## Ship type: mass, inertia, thrust, rates, gains and the asset id. The scene sets the Starfury; `setup` replaces it.
@export var spec: ShipSpec

## The frame the ship flies in: environment acceleration and the universe position (console). May be null (then the
## environment is empty and `universe_position` reads none).
var world: WorldFrame = null

## Flight assist (§5.5). Starts from `Settings.assist_default`; assigning it is `set_assist`.
var assist_on: bool:
	get = get_assist, set = set_assist

var _assist_on: bool = true
var _hardpoints: Hardpoints = Hardpoints.new()
var _layout: ThrusterLayout = ThrusterLayout.new()
var _model: FlightModel = null
var _output: FlightOutput = FlightOutput.new()
var _flight: FlightCommand = FlightCommand.new()
var _flight_fresh: bool = false
var _combat: CombatCommand = CombatCommand.new()
var _combat_fresh: bool = false
var _fallback_active: bool = false
var _interior_visible: bool = false
var _muzzles: Array[Node3D] = []
var _collision_nodes: Array[CollisionShape3D] = []

@onready var hull_splats: GaussianSplatNode = $HullSplats
@onready var hull_mesh_fallback: MeshInstance3D = $HullMeshFallback
@onready var cockpit_interior: MeshInstance3D = $CockpitInterior
@onready var thrusters: Node3D = $Thrusters
@onready var guns: Node3D = $Guns
@onready var targeting: TargetingController = $Targeting
@onready var cockpit_anchor: Marker3D = $CockpitAnchor


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
	add_to_group(SplatStatus.MESH_GROUP)
	_assist_on = bool(Settings.get_value(&"assist_default"))


func _ready() -> void:
	_apply_newtonian_body()
	targeting.setup(self)
	_build()
	use_fallback_mesh(_fallback_active or SplatStatus.needs_fallback(SplatStatus.active_backend()))
	set_cockpit_interior_visible(_interior_visible)
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Gives the ship its type and its world. Call it before `World.spawn` (the usual order, or use `create`); called
## after `_ready` it rebuilds mass, collision, muzzles and visuals for the new spec.
func setup(p_spec: ShipSpec, p_world: WorldFrame) -> void:
	spec = p_spec
	world = p_world
	if is_node_ready():
		_build()


func _physics_process(delta: float) -> void:
	if _flight_fresh and _flight.toggle_assist:
		set_assist(not _assist_on)
	_flight_fresh = false
	var combat_fresh: bool = _take_combat_edges()

	var env_accel: Vector3 = _environment_accel()
	if _model != null:
		var b: Basis = global_basis
		var to_body: Basis = b.transposed()
		_output = _model.compute(_flight, to_body * linear_velocity, to_body * angular_velocity, to_body * env_accel,
				_assist_on, delta)
		for nozzle: Dictionary in _output.nozzle_forces:
			var force: Vector3 = nozzle["force"]
			var at: Vector3 = nozzle["position"]
			apply_force(b * force, b * at)  # offset from the body origin, world orientation
		apply_central_force(b * _output.rcs_force_b)
		apply_torque(b * _output.rcs_torque_b)
	apply_central_force(mass * env_accel)

	if combat_fresh:
		targeting.apply(_combat)


# --- commands ----------------------------------------------------------------------------------------------------


## This tick's flight demand (pilot terms). Held until replaced; `toggle_assist` acts once.
func set_flight_command(cmd: FlightCommand) -> void:
	_flight = cmd if cmd != null else FlightCommand.new()
	_flight_fresh = true


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
	if on == _assist_on:
		return
	_assist_on = on
	if _model != null:
		_model.reset_assist()
	assist_toggled.emit(on)


## Teleports to a World-local pose at rest (respawn): velocities zeroed, assist state cleared, no interpolation smear.
func reset_to(xform: Transform3D) -> void:
	transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if _model != null:
		_model.reset_assist()
		_output = _idle_output()
	reset_physics_interpolation()


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


## What the flight model produced on the last physics tick (all zero before the first one). Never null.
func get_flight_output() -> FlightOutput:
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


## Ship-local chase camera offset, for `CameraRig.setup` (the hardpoints' `chase_anchor`).
func get_chase_offset() -> Vector3:
	return _hardpoints.chase_anchor if _hardpoints.valid else DEFAULT_CHASE_OFFSET


## The camera rig's interior callback: the cockpit interior is drawn in first person only.
func set_cockpit_interior_visible(shown: bool) -> void:
	_interior_visible = shown
	if is_node_ready():
		cockpit_interior.visible = shown


func is_cockpit_interior_visible() -> bool:
	return _interior_visible


## Draws the hull with the fallback mesh instead of the splats (`SplatStatus` group `splat_fallback_mesh`).
func use_fallback_mesh(enabled: bool) -> void:
	_fallback_active = enabled
	if not is_node_ready():
		return
	hull_mesh_fallback.visible = enabled
	hull_splats.visible = not enabled


func is_fallback_mesh_active() -> bool:
	return _fallback_active


# --- build -------------------------------------------------------------------------------------------------------


# §5.4: no gravity, no damping on the body *and* REPLACE so the project defaults are not combined in, never asleep
# (a coasting ship must keep coasting), no CCD. Set here as well as in the scene so an edited scene cannot break it.
func _apply_newtonian_body() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	can_sleep = false
	continuous_cd = false


func _build() -> void:
	_clear_built()
	if spec == null:
		push_warning("Ship: no ShipSpec; the ship cannot fly")
		_hardpoints = Hardpoints.new()
		_layout = ThrusterLayout.new()
		_model = null
		_output = FlightOutput.new()
		return
	mass = spec.mass
	inertia = spec.inertia
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
		cockpit_anchor.transform = _hardpoints.cockpit_camera
		_build_collision()
		_build_muzzles()
	_load_visuals()
	_output = _idle_output()


# Freed at once rather than queued: a rebuild must not leave the old shapes in the body for the rest of the frame.
func _clear_built() -> void:
	for node: Node in _collision_nodes:
		remove_child(node)
		node.free()
	_collision_nodes.clear()
	for marker: Node3D in _muzzles:
		marker.get_parent().remove_child(marker)
		marker.free()
	_muzzles.clear()


func _build_collision() -> void:
	for entry: Dictionary in _hardpoints.collision:
		var node := CollisionShape3D.new()
		node.name = ("Collision_" + str(entry["name"])).to_pascal_case().validate_node_name()
		node.shape = entry["shape"]
		node.transform = entry["transform"]
		add_child(node)
		_collision_nodes.append(node)


func _build_muzzles() -> void:
	for entry: Dictionary in _hardpoints.muzzles:
		var marker := Marker3D.new()
		marker.name = ("Muzzle_" + str(entry["name"])).to_pascal_case().validate_node_name()
		marker.transform = entry["transform"]
		guns.add_child(marker)
		_muzzles.append(marker)


func _load_visuals() -> void:
	var dir: String = asset_dir(spec)
	var splat_path: String = dir.path_join(spec.asset_id + ".ply")
	var gaussian: GaussianResource = null
	if ResourceLoader.exists(splat_path):
		gaussian = load(splat_path) as GaussianResource
	if gaussian == null:
		push_warning("Ship: %s is missing or not imported (run scripts/gen_assets.sh, then import); no hull splats" % splat_path)
	hull_splats.gaussian = gaussian
	hull_mesh_fallback.mesh = _load_mesh(dir.path_join(spec.asset_id + ".obj"))
	cockpit_interior.mesh = _load_mesh(dir.path_join(COCKPIT_MESH_FILE))


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


func _environment_accel() -> Vector3:
	if world == null or not is_instance_valid(world):
		return Vector3.ZERO
	return world.environment_accel(position)


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"assist", "Toggle or set flight assist",
			[ConsoleArg.bool_optional(&"state")]), _cmd_assist, self)
	DebugConsole.registry.register_provider(&"ship", ConsoleVars.new({
		&"position": {"get": func() -> Vector3: return position, "unit": "m", "doc": "World-local position"},
		&"universe_position": {"get": _universe_position, "unit": "m", "doc": "Universe position (64-bit)"},
		&"velocity": {"get": func() -> Vector3: return linear_velocity, "unit": "m/s", "doc": "World-frame velocity"},
		&"speed": {"get": func() -> float: return linear_velocity.length(), "type": TYPE_FLOAT, "unit": "m/s",
				"doc": "Speed relative to the World frame"},
		&"body_velocity": {"get": body_velocity, "unit": "m/s",
				"doc": "Velocity in body axes (+x right, +y up, -z forward)"},
		&"angular_rate_dps": {"get": _angular_rate_dps, "unit": "deg/s",
				"doc": "Angular rate in body axes (+x pitch up, +y yaw left, +z roll left)"},
		&"assist_on": {"get": get_assist, "set": set_assist, "type": TYPE_BOOL, "doc": "Flight assist"},
		&"trim": {"get": func() -> float: return _output.trim,
				"doc": "0..1: how far the flight computer cut the trimmed pod side (POD TRIM)"},
		&"pod_yaw": {"get": _pod_yaw_dps, "unit": "deg/s",
				"doc": "Assist pod-yaw command, pilot terms (+ = yaw right); 0 with assist off"},
		&"main_levels": {"get": func() -> Dictionary: return _levels_by_pod(_output.main_levels),
				"doc": "Main nozzle level per pod after trim, 0..1"},
		&"retro_levels": {"get": func() -> Dictionary: return _levels_by_pod(_output.retro_levels),
				"doc": "Retro nozzle level per pod after trim, 0..1"},
		&"mass_flow": {"get": func() -> float: return _output.mass_flow_kg_s, "unit": "kg/s",
				"doc": "Reaction mass flow (not consumed in M1)"},
	}), self)


func _cmd_assist(args: Dictionary) -> ConsoleResult:
	return DebugConsole.registry.toggle("ship.assist_on", args[&"state"])


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
