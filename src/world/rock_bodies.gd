class_name RockBodies
extends RefCounted
## The Jolt bodies of one owner's rocks, an asteroid field or a belt (M6-T21): a static sphere body by RID per rock, made once
## with the owner. Only the rocks a rigid hull could reach soon live: they collide, and they follow the owner's rebases and
## drift. The rest are dormant, left in Jolt with no layer and no mask, so nothing touches them and nothing moves them; their
## static rows carry them for the hit sweep, the rams and the contact scan, which never read the bodies. The owner steps the
## stream every tick (`step`, late in the tick, before Jolt's step): the native `ScsRockStream` names which rocks come and go,
## with hysteresis as the tier has. A rock that comes back is placed under its owner exactly where it would stand had it lived
## all along.
##
## A dormant body stays in Jolt rather than leaving its space so that no body is ever made again: Jolt orders a tick's
## contacts by its body ids, and those stay as they were, so a fight among the rocks keeps its bits.

## The native class that picks the live rocks.
const NATIVE_CLASS: StringName = &"ScsRockStream"
## How far ahead a hull's motion against the rocks is looked, s, and the room round it, m: a rock lives well before a hull
## could touch it.
const LOOKAHEAD_S: float = 0.25
const MARGIN_M: float = 20.0
## A live rock is demoted only this share beyond the reach that promotes it (the tier's `HYSTERESIS`), and only after this
## many ticks with no hull in that reach: a ship destroyed against a rock leaves the rows before it leaves Jolt.
const HYSTERESIS: float = 0.1
const HOLD_TICKS: int = 30
## The owner's physics priority for `step`: after every spawn and handover of the tick, before the core's `sync_out` and Jolt.
const STEP_PRIORITY: int = SimCore.OUT_PRIORITY - 1

## Live rocks over every owner, and promotions and demotions so far (work counts).
static var live_total: int = 0
static var promotions: int = 0
static var demotions: int = 0

## The last step's cost in microseconds (a profiling readout, never gameplay time).
var last_step_us: int = 0

var _bodies: Array[RID] = []
var _shapes: Array[RID] = []
var _local: Array[Transform3D] = []
var _radii := PackedFloat64Array()
var _live: Dictionary[int, bool] = {}
var _layer: int = CollisionLayers.layer_of(&"rock")
var _mask: int = CollisionLayers.mask_of(&"rock")
var _stream: Object = null
var _kept: bool = false
var _sim: SimCore = null


## Adds a dormant rock: a sphere of `radius` at `local` in its owner's frame, in `space`. Returns its body.
func add(space: RID, local: Transform3D, radius: float, owner_xform: Transform3D) -> RID:
	var shape: RID = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, radius)
	var body: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_collision_layer(body, 0)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, owner_xform * local)
	_bodies.append(body)
	_shapes.append(shape)
	_local.append(local)
	_radii.append(radius)
	_kept = false
	return body


## One step: the rocks a rigid hull of `world`'s core could reach soon come to life, the ones no hull is near any more go
## dormant. `owner` holds the rocks. Nothing without a core.
func step(owner: Node3D, world: WorldFrame) -> void:
	if _bodies.is_empty():
		return
	var started_us: int = Time.get_ticks_usec()  # profiling readout only
	# The rows as they stand: the tick's sync is behind them in play, and a step between ticks must not take the tick's sync.
	if _sim == null or not is_instance_valid(_sim) or not _sim.is_inside_tree():
		_sim = SimCore.attach(world) if world != null else SimCore.for_tree(owner.get_tree())
	var sim: SimCore = _sim
	if sim == null or sim.core == null:
		return
	var native: Object = _native()
	if not _kept:
		var centres := PackedVector3Array()
		for local: Transform3D in _local:
			centres.append(local.origin)
		native.keep(centres, _radii)
		for i: int in _live:
			_go_dormant(i)
		_live.clear()
		_kept = true
	var xform: Transform3D = owner.global_transform
	var rest: Vector3 = world.rest_velocity() if world != null else Vector3.ZERO
	var changes: PackedInt64Array = native.step(sim.core, xform.origin, xform.basis, rest, LOOKAHEAD_S, MARGIN_M, HYSTERESIS, HOLD_TICKS)
	for change: int in changes:
		if change >= 0:
			PhysicsServer3D.body_set_state(_bodies[change], PhysicsServer3D.BODY_STATE_TRANSFORM, xform * _local[change])
			PhysicsServer3D.body_set_collision_layer(_bodies[change], _layer)
			PhysicsServer3D.body_set_collision_mask(_bodies[change], _mask)
			_live[change] = true
			promotions += 1
			live_total += 1
		else:
			_go_dormant(-change - 1)
			_live.erase(-change - 1)
			demotions += 1
	last_step_us = Time.get_ticks_usec() - started_us


## Puts every live rock's body back under its owner (`owner_xform`) after a rebase or a drift moved the owner.
func place(owner_xform: Transform3D) -> void:
	for i: int in _live:
		PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, owner_xform * _local[i])


## Where rock `i`'s body stands when it lives, under an owner at `owner_xform`.
func placed(i: int, owner_xform: Transform3D) -> Transform3D:
	return owner_xform * _local[i]


## Whether rock `i` lives as a body now.
func is_live(i: int) -> bool:
	return _live.has(i)


func live_count() -> int:
	return _live.size()


func count() -> int:
	return _bodies.size()


func body_rids() -> Array[RID]:
	return _bodies


## Releases every body and shape.
func free_all() -> void:
	live_total -= _live.size()
	_live.clear()
	for body: RID in _bodies:
		PhysicsServer3D.free_rid(body)
	for shape: RID in _shapes:
		PhysicsServer3D.free_rid(shape)
	_bodies.clear()
	_shapes.clear()
	_local.clear()
	_radii.clear()
	_kept = false


func _go_dormant(i: int) -> void:
	PhysicsServer3D.body_set_collision_layer(_bodies[i], 0)
	PhysicsServer3D.body_set_collision_mask(_bodies[i], 0)
	live_total -= 1


# The native stream (the library is required, M4-T37), made on first use.
func _native() -> Object:
	if _stream == null:
		_stream = NativeLib.instantiate(NATIVE_CLASS)
	return _stream
