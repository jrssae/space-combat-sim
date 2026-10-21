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
## tree, §9.1; `HullSplatSync` draws it at the interpolated pose), `HullMeshFallback` (shown when `SplatStatus` finds
## no splat backend, or forced), `HullDepthProxy` (the fallback mesh inset by a few centimetres, opaque black, shown
## exactly when the splats are: it writes the depth splats do not, so effects behind the hull are hidden, §7.2), `CockpitInterior`
## (first person only), `Thrusters` and `Guns` (attach points for M1-T13; `Guns` holds one Marker3D per muzzle),
## `Targeting` (`TargetingController`), `CockpitAnchor` (Marker3D at the hardpoints' `cockpit_camera`).
##
## Reaction mass (M2-T14): every tick the flow the model reports is drawn from a `FuelTank` (sized by
## `ShipSpec.fuel_capacity_kg`, never drawn down while `settings.fuel_unlimited` is on), and when the tank is empty the
## model is told to cut all thrust.
##
## Rebase-safe: nothing here caches a World position between ticks. Console (§6.4, §15.1 D27): only the player's ship
## registers (`console_owner`, set before the ship enters the tree, `ShipAssembly` does it): provider `ship` and commands
## `assist [on|off]` and `refuel [kg]`, and it passes the flag on to its `TargetingController`. Other ships stay out of
## the console, because the registry replaces entries by name and would overwrite the player's.

## Assist was switched on or off (by `set_assist`, the console, or a `toggle_assist` edge).
signal assist_toggled(on: bool)

const SCENE_PATH: String = "res://src/ship/ship.tscn"
const ASSET_ROOT: String = "res://assets/generated"
const COCKPIT_MESH_FILE: String = "cockpit_interior.obj"
## Used when the hardpoints are missing (the chase camera still needs somewhere to sit); matches §8.
const DEFAULT_CHASE_OFFSET: Vector3 = Vector3(0.0, 2.5, 9.0)

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

var _assist_on: bool = true
var _hardpoints: Hardpoints = Hardpoints.new()
var _layout: ThrusterLayout = ThrusterLayout.new()
## Share of the gap to this tick's measured turn rate of the lead direction that the smoothed rate closes each tick.
const TRACK_RATE_SMOOTHING: float = 0.35

## The cabin lamp: a short-range light that comes on with the cockpit view and lights the frame (the hull's splats take no light).
var _cabin_light: OmniLight3D = null
var _track_prev_dir: Vector3 = Vector3.ZERO
var _track_rate_w: Vector3 = Vector3.ZERO
var _model: FlightModel = null
var _output: FlightOutput = FlightOutput.new()
var _fuel: FuelTank = FuelTank.new()
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
@onready var hull_depth_proxy: HullDepthProxy = $HullDepthProxy
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
	targeting.setup(self, console_owner)
	_build()
	_build_cabin_light()
	Settings.changed.connect(_on_hull_setting_changed)
	_apply_hull_sync_setting()
	use_fallback_mesh(_fallback_active or SplatStatus.needs_fallback(SplatStatus.active_backend()))
	set_cockpit_interior_visible(_interior_visible)
	if console_owner:
		_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
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
	if _flight_fresh and _flight.toggle_assist:
		set_assist(not _assist_on)
	_flight_fresh = false
	var combat_fresh: bool = _take_combat_edges()

	var env_accel: Vector3 = _environment_accel()
	if _model != null:
		var b: Basis = global_basis
		var to_body: Basis = b.transposed()
		_flight.face_dir_b = to_body * targeting.selected_offset()  # what the brake faces (§5.5); zero = no target
		_update_tracking(delta, to_body)
		var fuel: FuelTank = get_fuel_tank()
		_output = _model.compute(_flight, to_body * linear_velocity, to_body * angular_velocity, to_body * env_accel,
				_assist_on, delta, not fuel.is_empty())
		fuel.draw(_output.mass_flow_kg_s, delta)
		# Inertia grows with speed: the same thrust gives less acceleration the faster the ship goes (SpeedGovernor).
		var gain: float = SpeedGovernor.thrust_gain(linear_velocity.length(), spec.speed_limit_mps)
		for nozzle: Dictionary in _output.nozzle_forces:
			var force: Vector3 = nozzle["force"]
			var at: Vector3 = nozzle["position"]
			apply_force(b * force * gain, b * at)  # offset from the body origin, world orientation
		apply_central_force(b * _output.rcs_force_b * gain)
		apply_torque(b * _output.rcs_torque_b)
		if _assist_on:
			var net: Vector3 = b * (_output.pod_force_b + _output.rcs_force_b) * gain
			apply_central_force(SpeedGovernor.assist_cap_correction(net, linear_velocity, spec.assist_speed_max_mps))
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
	if on == _assist_on or (force_assist and not on):
		return
	_assist_on = on
	if _model != null:
		_model.reset_assist()
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


## The reaction-mass tank, with `unlimited` brought in line with `settings.fuel_unlimited` as of now. Never null.
func get_fuel_tank() -> FuelTank:
	_fuel.unlimited = bool(Settings.get_value(&"fuel_unlimited"))
	return _fuel


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
		_apply_hull_visuals()
		if _cabin_light != null:
			_cabin_light.visible = shown


func is_cockpit_interior_visible() -> bool:
	return _interior_visible


## Draws the hull with the fallback mesh instead of the splats (`SplatStatus` group `splat_fallback_mesh`). The depth
## proxy is only wanted while the splats are drawn: the fallback mesh writes depth itself.
func use_fallback_mesh(enabled: bool) -> void:
	_fallback_active = enabled
	_apply_hull_visuals()


# Splats or mesh for the hull. The mesh is drawn when the fallback is on, and also while the cockpit interior is shown: from
# inside, the hull's splats are seen from a few tens of centimetres, where each one is a huge flat disc that turns into a
# serrated, flickering sliver at a grazing angle (the 2026-10-21 play test). The mesh has none of that. The depth proxy stays on
# in the cockpit, so effects behind the hull stay hidden.
func _apply_hull_visuals() -> void:
	if not is_node_ready():
		return
	var mesh_mode: bool = _fallback_active or _interior_visible
	hull_mesh_fallback.visible = mesh_mode
	_apply_canopy_glass()
	hull_depth_proxy.visible = (_interior_visible or not _fallback_active) and bool(Settings.get_value(&"hull_depth_proxy"))
	hull_splats.visible = not mesh_mode


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
		cockpit_anchor.transform = _hardpoints.cockpit_camera
		_place_cabin_light()
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
	hull_depth_proxy.mesh = hull_mesh_fallback.mesh  # whatever is loaded, so a regenerated hull needs no changes here
	cockpit_interior.mesh = _load_mesh(dir.path_join(COCKPIT_MESH_FILE)) if spec.has_cockpit_interior else null
	MeshMaterials.matte(hull_mesh_fallback.mesh)
	MeshMaterials.matte(cockpit_interior.mesh)
	_make_double_sided(hull_mesh_fallback.mesh)
	_make_double_sided(cockpit_interior.mesh)
	_lift_shadows(cockpit_interior.mesh)


func _on_hull_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"hull_depth_proxy":
		_apply_hull_visuals()
	elif key == &"hull_splat_sync":
		_apply_hull_sync_setting()


# Debug switch: with the sync off the splat node is a plain interpolated child of the body again.
func _apply_hull_sync_setting() -> void:
	var sync := get_node_or_null(^"HullSplatSync") as Node
	var on: bool = bool(Settings.get_value(&"hull_splat_sync"))
	if sync != null:
		sync.set_process(on)
	hull_splats.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF if on else Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	if not on and sync is SplatPoseSync:
		hull_splats.transform = (sync as SplatPoseSync).local_pose()  # back to the body-relative pose
		hull_splats.reset_physics_interpolation()


# A soft lamp just behind and above the pilot's eyes. Its range stops short of the wings, so it lights only the cockpit frame.
func _build_cabin_light() -> void:
	_cabin_light = OmniLight3D.new()
	_cabin_light.name = "CabinLight"
	_cabin_light.omni_range = 4.5
	_cabin_light.omni_attenuation = 0.8
	_cabin_light.light_energy = float(Settings.get_value(&"cockpit_light_energy"))
	_cabin_light.light_color = Color(0.85, 0.92, 1.0)
	_cabin_light.shadow_enabled = false
	_cabin_light.visible = _interior_visible
	add_child(_cabin_light)
	_place_cabin_light()


func _place_cabin_light() -> void:
	if _cabin_light != null:
		_cabin_light.position = cockpit_anchor.position + Vector3(0.0, 0.45, 0.5)


# The canopy glass is a green translucent surface of the hull mesh. Seen from inside it tints the whole view green, so the pilot's
# window is clear: from the cockpit the glass surface gets an override that draws nothing (from outside it is the real glass).
func _apply_canopy_glass() -> void:
	var mesh: Mesh = hull_mesh_fallback.mesh
	if mesh == null:
		return
	for i: int in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(i)
		if material == null or not String(material.resource_name).contains("glass"):
			continue
		hull_mesh_fallback.set_surface_override_material(i, _clear_glass() if _interior_visible else null)


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
# the hull mesh is seen from inside the cockpit too. Both draw both sides.
static func _make_double_sided(mesh: Mesh) -> void:
	if mesh == null:
		return
	for i: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as BaseMaterial3D
		if material != null and material.cull_mode != BaseMaterial3D.CULL_DISABLED:
			material.cull_mode = BaseMaterial3D.CULL_DISABLED


# The cockpit frame on the side away from the sun would be pure black against the black sky (and read as a hole): a faint
# emission keeps both struts visible.
static func _lift_shadows(mesh: Mesh) -> void:
	if mesh == null:
		return
	for i: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as BaseMaterial3D
		if material != null:
			material.emission_enabled = true
			material.emission = Color(0.045, 0.047, 0.055)


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
	var lead: Dictionary = InterceptMath.solve(muzzle_centre, linear_velocity, readout.position, readout.velocity,
			weapon.muzzle_speed_mps, weapon.lifetime_s)
	return (lead["lead_point"] as Vector3) - global_position


func _environment_accel() -> Vector3:
	if world == null or not is_instance_valid(world):
		return Vector3.ZERO
	return world.environment_accel(position)


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"assist", "Toggle or set flight assist",
			[ConsoleArg.bool_optional(&"state")]), _cmd_assist, self)
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
