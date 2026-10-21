class_name NavBuoy
extends Node3D
## A navigation buoy, the M1 target marker (architecture §6.3, §7.1, §9.3): a splat body, a blinking beacon
## mesh on the mast, a 10 deg/s spin about its long axis (+Y), an optional constant drift, a `Targetable` and (post-M2) a
## `Damageable`: any bolt hurts it (`hit_by_anyone`, it is neutral to everyone), and at zero hull the `DestructionDirector`
## blows it up and calls `set_destroyed(true)`: hidden and not processing, so nothing targets or hits it, but never freed (no
## splat node leaves the tree during play, D22). `restore()` brings it back with a full hull (the player's respawn does that).
##
## Spawn it through `World` from a scenario entry: `world.spawn(NavBuoy.create(name, velocity), position)`. It joins
## `world_shiftable` itself as well, so a rebase moves it whichever way it was added.
##
## Assets are loaded here at run time, guarded (like `SpaceEnvironment`): the scene loads and the buoy works as a
## target before `scripts/gen_assets.sh` has run, with a warning instead of a load error. Every buoy shares one
## loaded `GaussianResource` (GDGS draws the instances from the same data), one fallback mesh and one hardpoints
## read. Without a GPU GDGS is a silent no-op, so how it looks is (H).
##
## Motion (spin, drift) is physics state and runs in `_physics_process` from `delta`; the beacon is a visual and
## blinks in `_process` from `SimClock`, never the wall clock.

const SCENE_PATH: String = "res://src/props/nav_buoy.tscn"
const ASSET_DIR: String = "res://assets/generated/nav_buoy"
const GAUSSIAN_PATH: String = ASSET_DIR + "/nav_buoy.ply"
const MESH_PATH: String = ASSET_DIR + "/nav_buoy.obj"
const HARDPOINTS_PATH: String = ASSET_DIR + "/hardpoints.json"

const SPIN_DPS: float = 10.0
const BLINK_HZ: float = 1.0
## Fraction of each blink period the beacon is lit: a short flash, like an anti-collision light.
const BLINK_DUTY: float = 0.25
## Where the beacon goes when `hardpoints.json` is missing (the generator's value at seed 42, to the centimetre).
const DEFAULT_BEACON_POSITION: Vector3 = Vector3(0.0, 2.46, 0.0)
const DEFAULT_BEACON_RADIUS: float = 0.1

## Hull points of a buoy: six pulse-cannon hits.
const HULL_MAX: float = 60.0

## The buoy's hull (nodes are added in `_ready`).
var damageable: Damageable = null

## Shown in the target readout and used by the console (`set targeting.selected "NAV ALPHA"`).
@export var display_name: String = "NAV BUOY":
	set(value):
		display_name = value
		_sync_targetable()
## Spin about the buoy's own +Y axis, degrees per second.
@export var spin_dps: float = SPIN_DPS
## Constant drift, World frame, m/s (kinematic: the buoy has no body).
@export var velocity: Vector3 = Vector3.ZERO:
	set(value):
		velocity = value
		_sync_targetable()
## Offset of this buoy's blink within the 1 s period, seconds.
@export var blink_phase_s: float = 0.0

static var _shared_loaded: bool = false
static var _shared_gaussian: GaussianResource = null
static var _shared_mesh: Mesh = null
static var _shared_beacon_position: Vector3 = DEFAULT_BEACON_POSITION
static var _shared_beacon_radius: float = DEFAULT_BEACON_RADIUS

## Spin angle about +Y since spawn, radians in [0, TAU). Kept as an angle so the basis never drifts.
var spin_angle_rad: float = 0.0

var _base_basis: Basis = Basis.IDENTITY
var _fallback_active: bool = false

@onready var splats: GaussianSplatNode = $BuoySplats
@onready var mesh_fallback: MeshInstance3D = $BuoyMeshFallback
@onready var depth_proxy: HullDepthProxy = $BuoyDepthProxy
@onready var beacon: MeshInstance3D = $Beacon
@onready var targetable: Targetable = $Targetable


## A buoy ready for `World.spawn()`.
static func create(p_display_name: String, p_velocity: Vector3 = Vector3.ZERO) -> NavBuoy:
	var buoy := (load(SCENE_PATH) as PackedScene).instantiate() as NavBuoy
	buoy.display_name = p_display_name
	buoy.velocity = p_velocity
	buoy.name = p_display_name.to_pascal_case().validate_node_name()
	return buoy


## Whether the beacon is lit at sim time `t` (1 Hz, `BLINK_DUTY` on). Pure.
static func beacon_lit(t: float, phase_s: float = 0.0) -> bool:
	var period: float = 1.0 / BLINK_HZ
	return fposmod(t + phase_s, period) < BLINK_DUTY * period


func _init() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_to_group(SplatStatus.MESH_GROUP)  # SplatStatus calls use_fallback_mesh (no backend, console, F4)


func _ready() -> void:
	_base_basis = basis
	_load_shared_assets()
	splats.gaussian = _shared_gaussian
	MeshMaterials.matte(_shared_mesh)
	mesh_fallback.mesh = _shared_mesh
	depth_proxy.mesh = _shared_mesh  # hides the beacon behind the body (§7.2); splats write no depth
	beacon.position = _shared_beacon_position
	beacon.scale = Vector3.ONE * (_shared_beacon_radius / DEFAULT_BEACON_RADIUS)
	use_fallback_mesh(_fallback_active)
	_sync_targetable()
	_update_beacon()
	_build_hull()


func _physics_process(delta: float) -> void:
	if velocity != Vector3.ZERO:
		global_position += velocity * delta
	if spin_dps != 0.0:
		spin_angle_rad = fposmod(spin_angle_rad + deg_to_rad(spin_dps) * delta, TAU)
		basis = _base_basis * Basis(Vector3.UP, spin_angle_rad)


func _process(_delta: float) -> void:
	_update_beacon()


## True from the destroying hit until `restore`.
func is_destroyed() -> bool:
	return damageable != null and damageable.hull.destroyed


## Takes the buoy out of play (or back in): hidden and not processing, never freed. The `DestructionDirector` calls it.
func set_destroyed(gone: bool) -> void:
	visible = not gone
	process_mode = Node.PROCESS_MODE_DISABLED if gone else Node.PROCESS_MODE_INHERIT


## A full hull again, back in play (the player's respawn).
func restore() -> void:
	if damageable != null:
		damageable.restore()
	set_destroyed(false)


func _build_hull() -> void:
	damageable = Damageable.new()
	damageable.name = "Damageable"
	add_child(damageable)
	damageable.setup(Hardpoints.load_collision_only(HARDPOINTS_PATH), HULL_MAX, Factions.NEUTRAL)
	damageable.hit_by_anyone = true


## Shows the fallback mesh instead of the splats (splats unavailable, or the F4 comparison toggle).
func use_fallback_mesh(enabled: bool) -> void:
	_fallback_active = enabled
	if not is_node_ready():
		return
	mesh_fallback.visible = enabled
	depth_proxy.visible = not enabled
	splats.visible = not enabled


func is_fallback_mesh_active() -> bool:
	return _fallback_active


func _update_beacon() -> void:
	beacon.visible = beacon_lit(SimClock.now(), blink_phase_s)


func _sync_targetable() -> void:
	var marker := get_node_or_null(^"Targetable") as Targetable
	if marker == null:
		return
	marker.display_name = display_name
	marker.velocity = velocity


## Loads the splats, the fallback mesh and the beacon hardpoint once for every buoy. Missing files only warn.
static func _load_shared_assets() -> void:
	if _shared_loaded:
		return
	_shared_loaded = true
	if ResourceLoader.exists(GAUSSIAN_PATH):
		_shared_gaussian = load(GAUSSIAN_PATH) as GaussianResource
	if _shared_gaussian == null:
		push_warning("NavBuoy: %s is missing or not imported (run scripts/gen_assets.sh, then import); no buoy splats" % GAUSSIAN_PATH)
	if ResourceLoader.exists(MESH_PATH):
		_shared_mesh = load(MESH_PATH) as Mesh
	var file := FileAccess.open(HARDPOINTS_PATH, FileAccess.READ)
	if file == null:
		push_warning("NavBuoy: no %s; the beacon goes at the default position" % HARDPOINTS_PATH)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	var beacon_data: Variant = (data as Dictionary).get("beacon") if data is Dictionary else null
	if not (beacon_data is Dictionary):
		push_warning("NavBuoy: %s has no beacon; the beacon goes at the default position" % HARDPOINTS_PATH)
		return
	var position_data: Variant = (beacon_data as Dictionary).get("position")
	var radius_data: Variant = (beacon_data as Dictionary).get("radius")
	if position_data is Array and (position_data as Array).size() == 3:
		var p: Array = position_data
		_shared_beacon_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if radius_data is float or radius_data is int:
		_shared_beacon_radius = float(radius_data)
