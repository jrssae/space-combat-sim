class_name MissileRacks
extends Node3D
## A capital's missile racks (M8-T09, the Battle Wagon): a child of the ship, built from its hull's `missile_racks[]`. The
## pick of a target and the launch decision are the native rows' that the bench's capitals use (`NativeWeapons` over
## `ScsWeaponRows`: the nearest hostile fighter in a missile's reach), asked only when a rack is ready (`RackSchedule`), so a
## ship with racks costs a time check a tick. The missile is M4's (`MissileStandin`), steered by the same rows.

## Asks the rows for one launch whenever a target is there: the schedule, not a count in flight, paces the racks.
const NO_LIMIT: int = 1 << 30

var schedule: RackSchedule = RackSchedule.create(0)
## Where each rack's missiles leave from and along which way, the ship's frame.
var positions: PackedVector3Array = PackedVector3Array()
var forwards: PackedVector3Array = PackedVector3Array()
## Missiles launched so far (a readout).
var launches: int = 0

var _native: NativeWeapons = null


## Takes the hull's racks (`missile_racks[]`: `position`, `forward`) and the class's numbers. Call before it enters the tree.
func setup(entries: Array, tuning: Dictionary) -> void:
	for raw: Variant in entries:
		var entry: Dictionary = raw if raw is Dictionary else {}
		var at: Variant = _vec3(entry.get("position"))
		var way: Variant = _vec3(entry.get("forward"))
		if at == null or way == null or (way as Vector3).is_zero_approx():
			continue
		positions.append(at)
		forwards.append((way as Vector3).normalized())
	schedule = RackSchedule.create(positions.size(), tuning)


func count() -> int:
	return positions.size()


func _exit_tree() -> void:
	_unbind()


func _physics_process(delta: float) -> void:
	var now: float = SimClock.now()
	if not schedule.due(now):
		return
	var cap := get_parent() as CapitalStandin
	if cap == null or cap.damageable == null or cap.damageable.hull.destroyed:
		return
	var target: Node3D = _pick(cap, now, delta)
	var ready: PackedInt32Array = schedule.ready(now)
	if target == null or cap.global_position.distance_to(target.global_position) > schedule.range_m or ready.is_empty():
		schedule.missed(now)
		return
	var to_target: Vector3 = cap.global_basis.inverse() * (target.global_position - cap.global_position)
	var rack: int = RackSchedule.best_facing(ready, forwards, to_target)
	var projectiles: Node3D = cap.world.get_node_or_null(^"Projectiles") as Node3D if cap.world != null else null
	if rack < 0 or projectiles == null:
		schedule.missed(now)
		return
	MissileStandin.launch(projectiles, cap.global_transform * positions[rack], target, cap.get_instance_id(), cap.faction, now)
	schedule.fired(rack, now)
	launches += 1


# The fighter the native rows would launch at now, or null: the nearest hostile one in a missile's reach of the ship.
func _pick(cap: CapitalStandin, now_s: float, delta: float) -> Node3D:
	var native: NativeWeapons = _bound(cap)
	if native == null:
		return null
	native.refresh_relations()
	var ticks: int = Engine.physics_ticks_per_second
	var out: Array = native.rows.step(Engine.get_physics_frames(), now_s, delta, ticks, ticks, NO_LIMIT, 1, ticks)
	var targets: PackedInt64Array = out[8] if out.size() > 8 else PackedInt64Array()
	return instance_from_id(targets[0]) as Node3D if not targets.is_empty() and is_instance_id_valid(targets[0]) else null


# The rows over this tick's core, bound to the ship; null without a core. The missiles in flight steer by them.
func _bound(cap: CapitalStandin) -> NativeWeapons:
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim == null or not sim.ensure_synced():
		_unbind()
		return null
	if _native == null or _native.sim != sim:
		_unbind()
		_native = NativeWeapons.bind(sim, [cap], null)
	if MissileStandin.native_rows == null:
		MissileStandin.native_rows = _native.rows
	return _native


func _unbind() -> void:
	if _native != null and MissileStandin.native_rows == _native.rows:
		MissileStandin.native_rows = null
	_native = null


static func _vec3(value: Variant) -> Variant:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null
