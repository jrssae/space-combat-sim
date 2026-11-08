class_name NavBuoy
extends Node3D
## A navigation buoy, the M1 target marker (architecture §6.3, §7.1, §9.3): a textured body (M4-T30d, `MeshAssets`, the beacon's lens
## glowing in its emissive map), a steady beacon on the mast with a slow fade over it (M3-T27), a 10 deg/s spin about +Y, an optional constant drift, a `Targetable` and a `Damageable`. Any bolt hurts it (it is neutral to
## everyone), and so does a ram (M3-T04): it has no physics body, so ships pass through and the `RamResolver` splits the
## momentum by `MASS_KG`. At zero hull the `DestructionDirector` calls `set_destroyed(true)`: hidden and not processing, but
## never freed (D22). `restore()` brings it back on the player's respawn.
##
## Spawn it through `World` from a scenario entry: `world.spawn(NavBuoy.create(name, velocity), position)`. It joins
## `world_shiftable` itself as well, so a rebase moves it whichever way it was added.
##
## Assets are loaded at run time, guarded like `SpaceEnvironment`, so the buoy works as a target before
## `scripts/gen_assets.sh` has run, with a warning. All buoys share one textured mesh and one hardpoints read. How it looks is (H).
##
## Motion (spin, drift) is physics state and runs in `_physics_process` from `delta`; the fade is a visual and breathes in
## `_process` from `SimClock`, never the wall clock.

const SCENE_PATH: String = "res://src/props/nav_buoy.tscn"
const ASSET_DIR: String = "res://assets/generated/nav_buoy"
const HARDPOINTS_PATH: String = ASSET_DIR + "/hardpoints.json"
const ASSET_ID: String = "nav_buoy"

const SPIN_DPS: float = 10.0
## One slow breath of the fade layer over the steady beacon, s (M3-T27).
const FADE_PERIOD_S: float = 6.0
## Where the beacon goes when `hardpoints.json` is missing (the generator's value at seed 42, to the centimetre).
const DEFAULT_BEACON_POSITION: Vector3 = Vector3(0.0, 2.46, 0.0)
const DEFAULT_BEACON_RADIUS: float = 0.1

## Every buoy broadcasts its position this far: 1 000 km (M3 Q21; M5-T10 raised it for the buoy ring, T30 put it back, Q41).
const BROADCAST_RANGE_M: float = 1.0e6
## Hull points of a buoy: six pulse-cannon hits.
const HULL_MAX: float = 60.0
## kg, for the ram maths (§16 D32; the generator's estimate is 1.94 t). A Starfury at 40 m/s changes a buoy's velocity by
## 38.4 m/s and its own by 1.6 m/s.
const MASS_KG: float = 2000.0
## m/s: a ram that changes the buoy's velocity by this much or more destroys it (the safe value is every hull's 5 m/s).
const RAM_LETHAL_DV_MPS: float = 15.0

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
static var _shared_loaded: bool = false
static var _shared_textured: Mesh = null
static var _shared_beacon_position: Vector3 = DEFAULT_BEACON_POSITION
static var _shared_beacon_radius: float = DEFAULT_BEACON_RADIUS

## Spin angle about +Y since spawn, radians in [0, TAU). Kept as an angle so the basis never drifts.
var spin_angle_rad: float = 0.0

## Where this buoy starts in the fade's cycle, s: seeded from its name when it is ready, so a buoy breathes the same every run.
var fade_phase_s: float = 0.0

var _base_basis: Basis = Basis.IDENTITY

@onready var body: MeshInstance3D = $Body
@onready var beacon: MeshInstance3D = $Beacon
@onready var beacon_fade: MeshInstance3D = $Beacon/Fade
@onready var targetable: Targetable = $Targetable


## A buoy ready for `World.spawn()`.
static func create(p_display_name: String, p_velocity: Vector3 = Vector3.ZERO) -> NavBuoy:
	var buoy := (load(SCENE_PATH) as PackedScene).instantiate() as NavBuoy
	buoy.display_name = p_display_name
	buoy.velocity = p_velocity
	buoy.name = p_display_name.to_pascal_case().validate_node_name()
	return buoy


## The fade layer's level at sim time `t`, 0..1: out at the start of the cycle and in half way through it. Pure.
static func fade_level(t: float, phase_s: float = 0.0) -> float:
	return 0.5 - 0.5 * cos(TAU * fposmod(t + phase_s, FADE_PERIOD_S) / FADE_PERIOD_S)


## A buoy's place in the fade's cycle, s, from its name. Pure.
static func fade_phase_of(p_display_name: String) -> float:
	return fposmod(float(hash(p_display_name)), FADE_PERIOD_S)


func _init() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)


func _ready() -> void:
	_load_shared_assets()
	_base_basis = basis
	body.mesh = _shared_textured
	beacon.position = _shared_beacon_position
	beacon.scale = Vector3.ONE * (_shared_beacon_radius / DEFAULT_BEACON_RADIUS)
	_sync_targetable()
	fade_phase_s = fade_phase_of(display_name)
	_update_beacon()
	_build_hull()


func _physics_process(delta: float) -> void:
	if velocity != Vector3.ZERO:
		global_position += velocity * delta
		# A script move after the core's first sync (M4-T35): the core reads this row again before the native selection
		# check and the hit sweep, so they see this tick's place as the tree reads did.
		SimCore.touch_moved(self)
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
	damageable.ram_mass_kg = MASS_KG
	damageable.ram_lethal_dv_mps = RAM_LETHAL_DV_MPS


func _update_beacon() -> void:
	beacon_fade.transparency = 1.0 - fade_level(SimClock.now(), fade_phase_s)


func _sync_targetable() -> void:
	var marker := get_node_or_null(^"Targetable") as Targetable
	if marker == null:
		return
	marker.display_name = display_name
	marker.velocity = velocity
	marker.broadcast_range_m = BROADCAST_RANGE_M


## Loads the textured mesh and the beacon hardpoint once for every buoy. Missing files only warn.
static func _load_shared_assets() -> void:
	if _shared_loaded:
		return
	_shared_loaded = true
	_shared_textured = MeshAssets.for_asset(ASSET_ID)
	if _shared_textured == null:
		push_warning("NavBuoy: %s has no textured mesh (run scripts/gen_assets.sh, then import); the buoy has no body" % ASSET_ID)
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
