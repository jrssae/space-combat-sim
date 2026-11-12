class_name Projectile
extends Node3D
## A pulse-cannon bolt (architecture §6.3, §7.1): a kinematic Node3D carrying an emissive capsule, no physics body
## and no hit detection in M1. It flies on at the velocity it was launched with, bent only by gravity (M6-T07, `HeldPull`),
## and frees itself `lifetime_s` of sim time after launch (`SimClock`, never the wall clock, so time warp and pausing work).
##
## Spawn it with `PulseCannon`, or by hand: instantiate `projectile.tscn`, add it to the tree under `World`, then
## `launch(...)`. It joins `world_shiftable` itself, so `World.rebase()` moves it with everything else. `velocity` is
## a World-frame vector; a velocity rebase takes its `dv` off it (`frame_boost`), as off a rigid body's.
##
## Hit detection (M2-T03, `HitResolver`): a bolt carries who shot it (`shooter_id`, `faction`), how hard it hits
## (`damage`, `hit_radius_m`) and the displacement of its latest tick (`last_step`, zero before its first tick), so the
## resolver can sweep the segment it just flew. It is in group `projectiles`. `spend()` retires it after a hit.
##
## The capsule is built along the node's -Z axis, and `launch` points -Z along the velocity.
##
## Guided and one-tick kinds (M4-T12): a projectile with `steering` asks it for its velocity every tick (a missile), and
## `fire_beam` makes a beam whose segment is its one tick of flight; the hit resolver retires a beam after sweeping it.
##
## `configure(weapon)` (the cannon calls it before `launch`) takes the lifetime and the bolt's look from a
## `WeaponSpec`. Capsule meshes are shared between all bolts of one look.

const GROUP: StringName = &"projectiles"
const SCENE_PATH: String = "res://src/weapons/projectile.tscn"
const DEFAULT_MATERIAL: Material = preload("res://assets/materials/projectile.tres")
## What a projectile is (M4-T08, architecture §17.7). The hit resolver treats every kind alike, a sphere of `hit_radius_m` swept
## along the tick's flight: a bolt, a beam (its whole length flown in the tick it fires), a guided missile, a proximity mine.
const KIND_BOLT: StringName = &"bolt"
const KIND_BEAM: StringName = &"beam"
const KIND_MISSILE: StringName = &"missile"
const KIND_MINE: StringName = &"mine"
const KINDS: Array[StringName] = [KIND_BOLT, KIND_BEAM, KIND_MISSILE, KIND_MINE]
## Each kind's hit radius (m): stand-in values until the real weapons (roadmap M12) bring their own. A mine's is its fuse.
const HIT_RADIUS_BY_KIND: Dictionary = {KIND_BOLT: 0.25, KIND_BEAM: 0.5, KIND_MISSILE: 2.0, KIND_MINE: 25.0}

# Bolt meshes by look (length, radius, material), so a volley does not build a mesh per bolt.
static var _meshes: Dictionary = {}

## How much larger the bolt is drawn than it is (the chase camera sees it from further away than the cockpit does). The
## camera rig sets it on a mode change; it never touches hit detection.
static var visual_scale: float = 1.0

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
## What this projectile is, one of `KINDS`.
var kind: StringName = KIND_BOLT
## Steers a guided projectile (M4-T12): `func(projectile: Projectile, delta: float) -> Vector3`, the velocity for this tick,
## called before it moves. Empty for a bolt, which flies straight.
var steering: Callable = Callable()
## The object behind `steering`, held here because a Callable does not keep a RefCounted alive.
var guidance: RefCounted = null
## Impact flash tint.
var color: Color = Color(0.9, 1.5, 3.0, 1.0)
## World-frame displacement of the latest physics tick (velocity × delta); zero until the first tick. A displacement,
## not a position, so a `World.rebase()` cannot stale it.
var last_step: Vector3 = Vector3.ZERO

var _spent: bool = false
var _laid_beam: bool = false
var _pull := HeldPull.new()  # gravity (M6-T07), read once a second

@onready var _bolt: MeshInstance3D = $Bolt


func _ready() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_to_group(GROUP)
	set_visual_scale(visual_scale)


func _physics_process(delta: float) -> void:
	if is_expired(SimClock.now()):
		queue_free()
		return
	if _laid_beam:
		return  # its segment was laid when it fired; the hit resolver retires it
	if steering.is_valid():
		velocity = steering.call(self, delta)
		_face(velocity)
	velocity = _pull.kick(self, velocity, delta)
	last_step = velocity * delta
	global_position += last_step


## A velocity rebase (`WorldFrame.boost`): the bolt keeps its universe velocity. It keeps its heading too: nothing turns.
func frame_boost(dv: Vector3) -> void:
	if not _laid_beam:
		velocity -= dv
		_pull.reset()


## Draws the bolt `factor` times its size (all axes); the hit radius stays as it is.
func set_visual_scale(factor: float) -> void:
	if _bolt != null:
		_bolt.scale = Vector3.ONE * maxf(factor, 0.01)


## Takes the lifetime and the bolt's look (length, radius, material) from `weapon`. Call it after the node entered the
## tree and before `launch`.
func configure(weapon: WeaponSpec) -> void:
	lifetime_s = weapon.lifetime_s
	damage = weapon.damage
	hit_radius_m = weapon.hit_radius_m
	color = weapon.bolt_color
	_bolt.mesh = bolt_mesh(weapon.bolt_length_m, weapon.bolt_radius_m, weapon.bolt_material)


## Every bolt material in use: the default and those of the meshes built so far (M4-T38 switches them for TAA).
static func bolt_materials() -> Array[Material]:
	var out: Array[Material] = [DEFAULT_MATERIAL]
	for mesh: CapsuleMesh in _meshes.values():
		if mesh.material != null and not out.has(mesh.material):
			out.append(mesh.material)
	return out


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
	if BoltMesh.motion_vectors():
		BoltMesh.set_motion_vectors(true)  # a new material joins the opaque ones under TAA
	return mesh


## Places the projectile at the World-frame `at`, points it along `launch_velocity` and starts the lifetime clock at
## `now_s` (`SimClock.now()`). The node must be in the tree. With a near-zero velocity the orientation is left alone.
func launch(at: Vector3, launch_velocity: Vector3, now_s: float) -> void:
	velocity = launch_velocity
	expires_at_s = now_s + lifetime_s
	global_position = at
	_face(launch_velocity)
	# Appear here, not smeared from wherever the node was a tick ago (project-wide physics interpolation is on).
	reset_physics_interpolation()


## Fires a beam (M4-T12): the whole segment from `from` to `to` is this tick's flight, swept by the hit resolver in this tick,
## which then retires it. The node must be in the tree; call it before the resolver's tick.
func fire_beam(from: Vector3, to: Vector3, now_s: float) -> void:
	set_kind(KIND_BEAM)
	_laid_beam = true
	velocity = Vector3.ZERO
	expires_at_s = now_s + lifetime_s
	global_position = to
	last_step = to - from
	_face(last_step)
	if _bolt != null:
		_bolt.visible = false  # one tick long; the stand-in draws nothing
	reset_physics_interpolation()


# Points the capsule along `direction`; left alone for a near-zero one.
func _face(direction: Vector3) -> void:
	if direction.length_squared() <= 1e-6:
		return
	var unit: Vector3 = direction.normalized()
	# looking_at needs an up vector that is not parallel to the direction; the capsule is round, so any will do.
	var up: Vector3 = Vector3.UP if absf(unit.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	global_basis = Basis.looking_at(unit, up)


## Makes this projectile a `p_kind`, with that kind's hit radius.
func set_kind(p_kind: StringName) -> void:
	kind = p_kind
	hit_radius_m = hit_radius_for(p_kind)


## The hit radius of a projectile of `p_kind`; a bolt's for a kind it does not know.
static func hit_radius_for(p_kind: StringName) -> float:
	return float(HIT_RADIUS_BY_KIND.get(p_kind, HIT_RADIUS_BY_KIND[KIND_BOLT]))


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
