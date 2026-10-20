class_name Projectile
extends Node3D
## A pulse-cannon bolt (architecture §6.3, §7.1): a kinematic Node3D carrying an emissive capsule, no physics body
## and no hit detection in M1. It flies in a straight line at the velocity it was launched with and frees itself
## `lifetime_s` of sim time after launch (`SimClock`, never the wall clock, so time warp and pausing work).
##
## Spawn it with `PulseCannon`, or by hand: instantiate `projectile.tscn`, add it to the tree under `World`, then
## `launch(...)`. It joins `world_shiftable` itself, so `World.rebase()` moves it with everything else. `velocity` is
## a World-frame vector; a velocity rebase (roadmap) must subtract the frame velocity from it, as for rigid bodies.
##
## Hit detection (M2-T03, `HitResolver`): a bolt carries who shot it (`shooter_id`, `faction`), how hard it hits
## (`damage`, `hit_radius_m`) and the displacement of its latest tick (`last_step`, zero before its first tick), so the
## resolver can sweep the segment it just flew. It is in group `projectiles`. `spend()` retires it after a hit.
##
## The capsule is built along the node's -Z axis, and `launch` points -Z along the velocity.
##
## `configure(weapon)` (the cannon calls it before `launch`) takes the lifetime and the bolt's look from a
## `WeaponSpec`. Capsule meshes are shared between all bolts of one look.

const GROUP: StringName = &"projectiles"
const SCENE_PATH: String = "res://src/weapons/projectile.tscn"
const DEFAULT_MATERIAL: Material = preload("res://assets/materials/projectile.tres")

# Bolt meshes by look (length, radius, material), so a volley does not build a mesh per bolt.
static var _meshes: Dictionary = {}

## Seconds of sim time from launch to `queue_free`.
@export var lifetime_s: float = 4.0

## World-frame velocity, m/s. Set by `launch`.
var velocity: Vector3 = Vector3.ZERO
## Sim time at which the projectile is freed.
var expires_at_s: float = INF
## Instance id of the shooter's ship body (0 = nobody); the bolt never hits it.
var shooter_id: int = 0
## The shooter's faction: the bolt hits only ships hostile to it (`Factions`).
var faction: StringName = Factions.NEUTRAL
## Hull points a hit removes, and the bolt's radius for hit detection (m).
var damage: float = 0.0
var hit_radius_m: float = 0.25
## Impact flash tint.
var color: Color = Color(3.0, 1.0, 0.5, 1.0)
## World-frame displacement of the latest physics tick (velocity × delta); zero until the first tick. A displacement,
## not a position, so a `World.rebase()` cannot stale it.
var last_step: Vector3 = Vector3.ZERO

var _spent: bool = false

@onready var _bolt: MeshInstance3D = $Bolt


func _ready() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_to_group(GROUP)


func _physics_process(delta: float) -> void:
	if is_expired(SimClock.now()):
		queue_free()
		return
	last_step = velocity * delta
	global_position += last_step


## Takes the lifetime and the bolt's look (length, radius, material) from `weapon`. Call it after the node entered the
## tree and before `launch`.
func configure(weapon: WeaponSpec) -> void:
	lifetime_s = weapon.lifetime_s
	damage = weapon.damage
	hit_radius_m = weapon.hit_radius_m
	color = weapon.bolt_color
	_bolt.mesh = bolt_mesh(weapon.bolt_length_m, weapon.bolt_radius_m, weapon.bolt_material)


## The shared capsule mesh for a bolt of this look; a null `material` is the pulse bolt material.
static func bolt_mesh(length_m: float, radius_m: float, material: Material = null) -> CapsuleMesh:
	var mat: Material = material if material != null else DEFAULT_MATERIAL
	var key := "%s|%s|%d" % [length_m, radius_m, mat.get_instance_id()]
	var cached: CapsuleMesh = _meshes.get(key) as CapsuleMesh
	if cached != null:
		return cached
	var mesh := CapsuleMesh.new()
	mesh.radius = radius_m
	mesh.height = maxf(length_m, 2.0 * radius_m)
	mesh.radial_segments = 8
	mesh.rings = 2
	mesh.material = mat
	_meshes[key] = mesh
	return mesh


## Places the projectile at the World-frame `at`, points it along `launch_velocity` and starts the lifetime clock at
## `now_s` (`SimClock.now()`). The node must be in the tree. With a near-zero velocity the orientation is left alone.
func launch(at: Vector3, launch_velocity: Vector3, now_s: float) -> void:
	velocity = launch_velocity
	expires_at_s = now_s + lifetime_s
	global_position = at
	if launch_velocity.length_squared() > 1e-6:
		var direction: Vector3 = launch_velocity.normalized()
		# looking_at needs an up vector that is not parallel to the direction; the capsule is round, so any will do.
		var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		global_basis = Basis.looking_at(direction, up)
	# Appear here, not smeared from wherever the node was a tick ago (project-wide physics interpolation is on).
	reset_physics_interpolation()


## Retires the bolt after a hit. Idempotent.
func spend() -> void:
	if _spent:
		return
	_spent = true
	queue_free()


func is_spent() -> bool:
	return _spent


func is_expired(now_s: float) -> bool:
	return now_s >= expires_at_s
