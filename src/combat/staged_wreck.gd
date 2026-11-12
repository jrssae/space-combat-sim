class_name StagedWreck
extends RefCounted
## The chunks of a dying Starfury, still together as one rigid body on the ship's velocity and spin (M3-T28, architecture
## §15.7), until each is released on its `BreakupPlan` time. Pure: the pool draws the pieces at `chunk_transform` and starts
## each at `release_velocity` when `advance` names it. Spin is constant in the world frame and nothing damps it, so the wreck
## and a released chunk both keep their motion for good.

var plan: BreakupPlan = null
## Pose (World-local), velocity and spin (world frame, rad/s) of the wreck's centre.
var origin: Vector3 = Vector3.ZERO
var basis: Basis = Basis.IDENTITY
var velocity: Vector3 = Vector3.ZERO
var spin: Vector3 = Vector3.ZERO
var age_s: float = 0.0

var _offsets: Array[Vector3] = []
var _joints: Array[Vector3] = []
var _released: PackedByteArray = PackedByteArray()
var _released_count: int = 0
var _pull := HeldPull.new()  # gravity (M6-T07), read once a second


## `offsets` and `joints` are the chunks' centroids and detachment points in the body frame, `xform` the body's pose.
func _init(p_plan: BreakupPlan, offsets: Array[Vector3], joints: Array[Vector3], xform: Transform3D, p_velocity: Vector3,
		p_spin: Vector3) -> void:
	plan = p_plan
	_offsets = offsets
	_joints = joints
	origin = xform.origin
	basis = xform.basis.orthonormalized()
	velocity = p_velocity
	spin = p_spin
	_released.resize(offsets.size())


## Moves the wreck `delta` seconds on in `world` (its pull, M6-T07; null for none) and returns the chunks whose time has come,
## in release order.
func advance(delta: float, world: WorldFrame = null) -> PackedInt32Array:
	age_s += delta
	if world != null:
		velocity = _pull.kick_at(world, origin, velocity, delta)
	origin += velocity * delta
	var angle: float = spin.length() * delta
	if angle > 0.0:
		basis = (Basis(spin.normalized(), angle) * basis).orthonormalized()
	var out := PackedInt32Array()
	for chunk: int in plan.order:
		if _released[chunk] == 0 and age_s >= plan.release_s[chunk]:
			_released[chunk] = 1
			_released_count += 1
			out.append(chunk)
	return out


func is_released(chunk: int) -> bool:
	return _released[chunk] != 0


func finished() -> bool:
	return _released_count >= _released.size()


## Chunk `chunk`'s centroid in the body frame.
func offset_of(chunk: int) -> Vector3:
	return _offsets[chunk]


## Where chunk `chunk`'s centroid sits now, World-local.
func chunk_transform(chunk: int) -> Transform3D:
	return Transform3D(basis, origin + basis * _offsets[chunk])


## Where chunk `chunk`'s detachment point sits now, World-local.
func joint_position(chunk: int) -> Vector3:
	return origin + basis * _joints[chunk]


## The wreck's velocity at the body-frame point `local`.
func point_velocity(local: Vector3) -> Vector3:
	return velocity + spin.cross(basis * local)


## The wreck's velocity at chunk `chunk`'s detachment point.
func joint_velocity(chunk: int) -> Vector3:
	return velocity + spin.cross(basis * _joints[chunk])


## Direction a chunk's kick takes: away from the wreck's centre, or the plan's hint for a chunk sitting on it.
func kick_direction(chunk: int) -> Vector3:
	var r: Vector3 = basis * _offsets[chunk]
	return r.normalized() if r.length_squared() > 1e-6 else plan.direction_hint[chunk]


## Velocity a chunk keeps from its release on: the wreck's motion at its centroid plus its kick.
func release_velocity(chunk: int) -> Vector3:
	return point_velocity(_offsets[chunk]) + kick_direction(chunk) * plan.kick_mps[chunk]


## A chunk's spin once released: the wreck's, plus its own tumble.
func release_spin(chunk: int) -> Vector3:
	return spin + plan.spin[chunk]


## A rebase by `offset`: the wreck moves with the world.
func shift(offset: Vector3) -> void:
	origin -= offset


## A velocity rebase by `dv`: the wreck keeps its universe velocity.
func boost(dv: Vector3) -> void:
	velocity -= dv
	_pull.reset()
