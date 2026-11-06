extends GutTest
## The native simulation core (M4-T15, architecture §17.13): one store of rows in the crate, filled once per tick from the
## engine (`sync_in`) and read by every native class, so the contact field, the hit sweep, the flight step and the ram broad
## phase stop loading their own copies. Rows survive a pool release and acquire with a new handle; a rebase shifts every row
## once; the four classes answer from the core exactly as they do from their own loads (bit for bit, on seeded worlds); a
## row of each kind round-trips its state; and the sync points are the only places the core touches the engine. Light
## bodies made here (a rigid body with a `Targetable` and a `Damageable`, props, a hull without a marker, bolts), real ships
## only for the flight step. Skips, saying why, when the native library is not built at all.

const ROWS_COMPARED: Array[String] = ["_body_ids", "_ids", "_names", "_factions", "_positions", "_velocities", "_forwards",
		"_ups", "_radii", "_is_ship", "_kinds"]
const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const PROJECTILE_SCENE: PackedScene = preload("res://src/weapons/projectile.tscn")
const SIDES: Array[StringName] = [Factions.RAIDERS, Factions.EARTH_ALLIANCE, Factions.NEUTRAL, &"drifters"]
const KINDS_ROUND_TRIPPED: Array[int] = [SimCore.KIND_SHIP, SimCore.KIND_CAPITAL, SimCore.KIND_TURRET, SimCore.KIND_MISSILE,
		SimCore.KIND_BEAM, SimCore.KIND_BOLT, SimCore.KIND_MINE, SimCore.KIND_STATIC]
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_flight", &"fuel_unlimited"]

var world: WorldFrame
var projectiles: Node3D
var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"perf_native_core", true)
	Settings.set_value(&"perf_native_flight", true)
	Settings.set_value(&"fuel_unlimited", true)
	Factions.reset()
	ContactScan.invalidate()
	ContactScan.clear_statics()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func after_each() -> void:
	ContactScan.clear_statics()
	ContactScan.invalidate()
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	Factions.reset()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no core to test")
	return true


# --- the world ---------------------------------------------------------------------------------------------------------


# A rigid body with a marker and a hull, as `ShipAssembly` builds them (without the rest of a ship).
func _body(at: Vector3, faction: StringName, label: String, radius: float = 12.0, marker: Targetable = null) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	world.add_child(body)
	body.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	body.global_transform = Transform3D(Basis.from_euler(Vector3(at.x * 0.001, at.y * 0.002, at.z * 0.003)), at)
	body.linear_velocity = Vector3(at.z * 0.01, -at.x * 0.01, 3.0)
	body.angular_velocity = Vector3(at.y * 0.0001, 0.01, -at.x * 0.0001)
	var hull := Damageable.new()
	hull.faction = faction
	hull.bounding_radius = radius
	body.add_child(hull)
	var t: Targetable = marker if marker != null else Targetable.new()
	t.name = "Targetable"
	t.display_name = label
	t.faction = faction
	body.add_child(t)
	return body


# A prop: a plain node with a marker that drifts (its velocity on the marker) and a hull.
func _prop(at: Vector3, label: String) -> Node3D:
	var prop := Node3D.new()
	world.add_child(prop)
	prop.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	prop.global_position = at
	var hull := Damageable.new()
	hull.bounding_radius = 3.0
	prop.add_child(hull)
	var t := Targetable.new()
	t.display_name = label
	t.velocity = Vector3(0.5, 0.0, -0.25)
	prop.add_child(t)
	return prop


# A rigid body with a hull and no marker (a drone).
func _drone(at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	world.add_child(body)
	body.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	body.global_position = at
	body.linear_velocity = Vector3(1.0, 2.0, 3.0)
	var hull := Damageable.new()
	hull.faction = Factions.RAIDERS
	hull.bounding_radius = 4.0
	body.add_child(hull)
	return body


# A bolt as the game launches it: at `at` along `velocity`, with no step behind it yet (`last_step` is zero until its first
# `_physics_process`, §15.3); `flown` gives it one tick of flight, as `_physics_process` would.
func _bolt(at: Vector3, velocity: Vector3, faction: StringName, shooter_id: int, kind: StringName = Projectile.KIND_BOLT,
		flown: bool = false) -> Projectile:
	var bolt := PROJECTILE_SCENE.instantiate() as Projectile
	bolt.faction = faction
	bolt.shooter_id = shooter_id
	bolt.damage = 5.0
	projectiles.add_child(bolt)
	bolt.set_kind(kind)
	bolt.launch(at, velocity, 0.0)
	if flown:
		_fly(bolt)
	return bolt


# One tick of a bolt's flight by hand, as `Projectile._physics_process` does it.
func _fly(bolt: Projectile) -> void:
	bolt.last_step = bolt.velocity * (1.0 / 60.0)
	bolt.global_position += bolt.last_step


# A hull killed where it stands (the `destroyed` signal fires; nothing hides the body here).
func _kill(body: Node3D) -> void:
	var hull: Damageable = Damageable.of(body)
	hull.apply_hit(HitInfo.new(body.get_instance_id(), 0, &"", hull.hull.max_hp, body.global_position, Vector3.ZERO, 0.0))


func _park(body: Node3D) -> void:
	body.visible = false
	body.process_mode = Node.PROCESS_MODE_DISABLED


func _unpark(body: Node3D) -> void:
	body.process_mode = Node.PROCESS_MODE_INHERIT
	body.visible = true


# A seeded crowd of every sort of body, some of them parked, some rocks and mines as static rows, and bolts among them.
func _crowd(rng: RandomNumberGenerator, n: int, bolts: int = 0, statics: int = 0) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for i: int in n:
		var at := Vector3(rng.randf_range(-6000.0, 6000.0), rng.randf_range(-2000.0, 2000.0), rng.randf_range(-6000.0, 6000.0))
		var roll: float = rng.randf()
		var body: Node3D
		if roll < 0.08:
			body = _prop(at, "BUOY %d" % i)
		elif roll < 0.14:
			body = _drone(at)
		elif roll < 0.22:
			var marker := Targetable.new()
			marker.kind = [Targetable.Kind.CAPITAL, Targetable.Kind.PROP, Targetable.Kind.TURRET,
					Targetable.Kind.SHIP][rng.randi_range(0, 3)]
			body = _body(at, SIDES[rng.randi_range(0, 3)], "KIND %d" % i, rng.randf_range(5.0, 600.0), marker)
		else:
			body = _body(at, SIDES[rng.randi_range(0, 3)], "SHIP %d" % i, rng.randf_range(5.0, 30.0))
		if rng.randf() < 0.15:
			_park(body)
		out.append(body)
	for s: int in statics:
		var at := Vector3(rng.randf_range(-6000.0, 6000.0), rng.randf_range(-2000.0, 2000.0), rng.randf_range(-6000.0, 6000.0))
		var mine: bool = rng.randf() < 0.3
		ContactScan.register_static(900000 + s, at, 50.0 if mine else rng.randf_range(20.0, 200.0),
				BodyKind.MINE if mine else BodyKind.STATIC, SIDES[rng.randi_range(0, 3)] if mine else Factions.NEUTRAL, world)
	for b: int in bolts:
		# Some bolts about to reach a body (a pair for the sweep), the rest well off it.
		var near: Node3D = out[rng.randi_range(0, out.size() - 1)]
		var spread: float = 20.0 if b % 2 == 0 else 200.0
		var at: Vector3 = near.global_position + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread),
				rng.randf_range(-spread, spread))
		var velocity: Vector3 = (near.global_position - at).normalized() * rng.randf_range(300.0, 900.0)
		var kind: StringName = Projectile.KIND_MISSILE if rng.randf() < 0.1 else Projectile.KIND_BOLT
		# Half the bolts have flown a tick, the rest are on their launch tick (no step behind them yet).
		_bolt(at, velocity, SIDES[rng.randi_range(0, 3)], out[rng.randi_range(0, out.size() - 1)].get_instance_id(), kind,
				b % 4 < 2)
	return out


func _core() -> SimCore:
	var core: SimCore = SimCore.attach(world)
	assert_not_null(core, "a core attaches to the world (%s)" % NativeLib.version(SimCore.NATIVE_CLASS))
	return core


# Fails, naming the first difference, unless both scans hold the same rows bit for bit.
func _assert_same_rows(a_scan: ContactScan, b_scan: ContactScan, label: String) -> void:
	for field: String in ROWS_COMPARED:
		var a: Variant = a_scan.get(field)
		var b: Variant = b_scan.get(field)
		if a == b:
			continue
		var first: int = -1
		for i: int in mini(a.size(), b.size()):
			if a[i] != b[i]:
				first = i
				break
		fail_test("%s: %s differs (sizes %d and %d, first at row %d: %s against %s)" % [label, field, a.size(), b.size(),
				first, str(a[first]) if first >= 0 else "", str(b[first]) if first >= 0 else ""])
		return
	pass_test("%s: the same rows" % label)


static func _ids(contacts: Array[Contact]) -> PackedInt64Array:
	var out := PackedInt64Array()
	for c: Contact in contacts:
		out.append(c.id)
	return out


# --- lifecycle ---------------------------------------------------------------------------------------------------------


func test_rows_survive_a_pool_release_and_acquire_with_a_new_handle() -> void:
	if _skipped():
		return
	var ship: RigidBody3D = _body(Vector3(100.0, 0.0, -50.0), Factions.EARTH_ALLIANCE, "KILO 1")
	_body(Vector3(-300.0, 20.0, 400.0), Factions.RAIDERS, "R 1")
	var core: SimCore = _core()
	core.sync_now()
	var first: int = core.handle_of(ship.get_instance_id())
	assert_gt(first, 0, "an active body has a row handle")
	assert_eq(core.row_name(first), "KILO 1", "the row carries the ship's name")
	assert_eq(core.rows(), 2, "two bodies, two rows")
	# Released to the pool: hidden, not processing, its name taken away (ShipPool.release).
	_park(ship)
	(ship.get_node("Targetable") as Targetable).display_name = ""
	core.sync_now()
	assert_eq(core.rows(), 1, "a parked ship has no row")
	assert_eq(core.row_of(first), -1, "its old handle points at no row")
	# Acquired again, under a new name, at a new place.
	_unpark(ship)
	(ship.get_node("Targetable") as Targetable).display_name = "KILO 2"
	ship.global_position = Vector3(5.0, 6.0, 7.0)
	core.sync_now()
	var second: int = core.handle_of(ship.get_instance_id())
	assert_eq(core.rows(), 2, "the ship is a row again")
	assert_ne(second, first, "a ship back from the pool gets a new handle")
	assert_eq(core.row_of(first), -1, "the old handle stays dead")
	assert_eq(core.row_name(second), "KILO 2", "the row carries the new name")
	assert_eq(core.row_position(second), Vector3(5.0, 6.0, 7.0), "and the new place")
	_assert_same_rows(ContactScan.shared(get_tree()), ContactScan.from_tree(get_tree()), "the scan after the reuse")


func test_the_slot_map_stays_bounded_over_spawn_and_release_cycles_and_refuses_an_old_handle() -> void:
	if _skipped():
		return
	_body(Vector3(-300.0, 20.0, 400.0), Factions.RAIDERS, "ANCHOR")
	var core: SimCore = _core()
	core.sync_now()
	var first: int = 0
	var most: int = 0
	for cycle: int in 300:
		var body: RigidBody3D = _body(Vector3(100.0 + float(cycle), 0.0, -50.0), Factions.EARTH_ALLIANCE, "R %d" % cycle)
		core.sync_now()
		var handle: int = core.handle_of(body.get_instance_id())
		assert_gt(handle, 0, "cycle %d: the new body has a row" % cycle)
		if cycle == 0:
			first = handle
		most = maxi(most, int(core.core.slot_count()))
		body.get_parent().remove_child(body)
		body.free()
		core.sync_now()
	assert_lte(most, 4, "the slot map never holds more than the live members (a marker and a hull each for the anchor and one body): %d" % most)
	assert_eq(int(core.core.slot_count()), 2, "only the anchor's two are left after 300 bodies came and went")
	var reused: RigidBody3D = _body(Vector3(7.0, 8.0, 9.0), Factions.EARTH_ALLIANCE, "REUSED")
	core.sync_now()
	var again: int = core.handle_of(reused.get_instance_id())
	assert_eq(again >> 32, first >> 32, "the new body took the first body's slot")
	assert_ne(again, first, "with a later generation, so the old handle is not the new row's")
	assert_eq(core.row_of(first), -1, "the old handle to the reused slot is refused")
	assert_eq(core.row_name(again), "REUSED", "and the new handle reads the new row")


func test_a_rebase_shifts_every_row_once() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	var bodies: Array[Node3D] = _crowd(rng, 40, 30, 20)
	var core: SimCore = _core()
	core.sync_now()
	var before: PackedVector3Array = core.body_positions()
	var bolts_before: PackedVector3Array = core.bolt_positions()
	var offset := Vector3(4321.5, -17.25, 2000.125)
	world.rebase(offset)
	var after: PackedVector3Array = core.body_positions()
	assert_eq(after.size(), before.size(), "the same rows")
	var ids: PackedInt64Array = core.body_ids()
	var wrong: int = 0
	for i: int in after.size():
		var node := instance_from_id(ids[i]) as Node3D
		if after[i] != before[i] - offset or (node != null and after[i] != node.global_position):
			wrong += 1
	assert_eq(wrong, 0, "every body row moved by the shift, once, to where its node is")
	var bolts_after: PackedVector3Array = core.bolt_positions()
	wrong = 0
	for i: int in bolts_after.size():
		if bolts_after[i] != bolts_before[i] - offset:
			wrong += 1
	assert_eq(wrong, 0, "every bolt row moved by the shift, once")
	core.sync_now()
	var next: PackedVector3Array = core.body_positions()
	assert_eq(next, after, "the next sync reads the nodes where the shift left them: no second move")
	assert_eq(core.static_positions(), StaticRows.positions, "the static rows follow StaticRows' own shift")
	_assert_same_rows(ContactScan.shared(get_tree()), ContactScan.from_tree(get_tree()), "the scan after the rebase")
	assert_true(bodies.size() > 0, "a crowd was made")


func test_a_row_of_each_kind_round_trips_its_state() -> void:
	if _skipped():
		return
	var core: SimCore = _core()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var handles: PackedInt64Array = PackedInt64Array()
	var given: Array[Dictionary] = []
	for kind: int in KINDS_ROUND_TRIPPED:
		var row: Dictionary = {
			"kind": kind,
			"id": 70000 + kind,
			"faction": SIDES[kind % SIDES.size()],
			"radius": rng.randf_range(0.25, 1200.0),
			"flags": rng.randi_range(0, 255),
			"position": Vector3(rng.randf_range(-1e5, 1e5), rng.randf_range(-1e5, 1e5), rng.randf_range(-1e5, 1e5)),
			"velocity": Vector3(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0)),
			"basis": Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))),
			"angular": Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)),
			"command": PackedFloat64Array([rng.randf(), rng.randf(), rng.randf(), rng.randf(), rng.randf_range(-1.0, 1.0),
					rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), 1.0, 0.0, 1.0]),
			"state": PackedFloat64Array([rng.randf_range(0.0, 100.0), rng.randf_range(0.0, 100.0), rng.randf_range(0.0, 100.0)]),
		}
		var handle: int = core.add_row(row)
		assert_gt(handle, 0, "kind %d gets a handle" % kind)
		handles.append(handle)
		given.append(row)
	for i: int in handles.size():
		var back: Dictionary = core.row(handles[i])
		for key: String in given[i]:
			assert_eq(back.get(key), given[i][key], "kind %d: %s round-trips" % [given[i]["kind"], key])
	# A changed command and state come back changed; a removed row answers nothing.
	var moved: PackedFloat64Array = PackedFloat64Array([0.5, 0.25, 0.0, 0.0, 0.1, -0.2, 0.3, 0.0, 1.0, 0.0])
	core.set_row_command(handles[0], moved)
	assert_eq((core.row(handles[0]) as Dictionary)["command"], moved, "the command changes in place")
	core.remove_row(handles[1])
	assert_true((core.row(handles[1]) as Dictionary).is_empty(), "a removed row is gone")
	assert_eq((core.row(handles[2]) as Dictionary)["id"], 70000 + KINDS_ROUND_TRIPPED[2], "its neighbours stay")


# --- the four classes, from the core and from their own loads -------------------------------------------------------


func test_the_contact_scan_answers_from_the_core_as_from_its_own_load() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 150
	for round: int in 6:
		for node: Node in world.get_children():
			if node != projectiles:
				node.free()
		for node: Node in projectiles.get_children():
			node.free()
		ContactScan.clear_statics()
		ContactScan.invalidate()
		var n: int = [1, 3, 12, 40, 120, 200][round]
		var bodies: Array[Node3D] = _crowd(rng, n, 25 if n > 2 else 0, 30 if n > 10 else 0)
		var core: SimCore = _core()
		core.sync_now()
		var shared: ContactScan = ContactScan.shared(get_tree())
		assert_eq(shared.source(), &"core", "round %d: the shared scan comes from the core" % round)
		var script: ContactScan = ContactScan.from_tree(get_tree())
		script.use_native = false
		_assert_same_rows(shared, script, "round %d" % round)
		var differences: PackedStringArray = PackedStringArray()
		for q: int in mini(bodies.size(), 60):
			var own: Node3D = bodies[rng.randi_range(0, bodies.size() - 1)]
			var faction: StringName = SIDES[rng.randi_range(0, 3)]
			var at: Vector3 = own.global_position + Vector3(rng.randf_range(-500.0, 500.0), 0.0, rng.randf_range(-500.0, 500.0))
			var own_id: int = own.get_instance_id()
			var k: int = [0, 3, 12][q % 3]
			var range_m: float = [ContactScan.SENSOR_RANGE_M, 900.0, 20000.0][q % 3]
			var a: Array = [_ids(shared.contacts_for(own_id, at, faction, range_m)),
					_ids(shared.nearest_for(own_id, at, faction, k, Callable(), range_m)),
					_ids(shared.statics_for(own_id, at, faction, 4, range_m)),
					shared.incoming_fire(own_id, at, Vector3(1.0, 0.0, 0.0), faction)]
			var b: Array = [_ids(script.contacts_for(own_id, at, faction, range_m)),
					_ids(script.nearest_for(own_id, at, faction, k, Callable(), range_m)),
					_ids(script.statics_for(own_id, at, faction, 4, range_m)),
					script.incoming_fire(own_id, at, Vector3(1.0, 0.0, 0.0), faction)]
			if a != b:
				differences.append("round %d query %d: %s against %s" % [round, q, a, b])
		assert_eq(differences.size(), 0, "round %d: the same answers from the core as from the scan's own load: %s" % [round,
				differences.slice(0, 3)])
		assert_eq(shared.path(), &"native", "round %d: the queries ran natively" % round)


func test_the_hit_sweep_pairs_from_the_core_as_from_its_own_load() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var resolver := HitResolver.new()
	resolver.name = "HitResolver"
	add_child_autofree(resolver)
	var bolts_moved_pairs: bool = false
	for round: int in 4:
		for node: Node in world.get_children():
			if node != projectiles:
				node.free()
		for node: Node in projectiles.get_children():
			node.free()
		ContactScan.invalidate()
		var n: int = [2, 10, 60, 150][round]
		_crowd(rng, n, 40 * (round + 1), 0)
		var core: SimCore = _core()
		core.sync_now()
		var delta: float = 1.0 / 60.0
		# The resolver's own load: hulls and bolts gathered from the tree, paired by the broad phase.
		resolver.use_core = false
		var own: Array = resolver.broad_phase_pairs(delta)
		# From the core: the same pairs, named by body and bolt instance id, and the same work.
		resolver.use_core = true
		var from_core: Array = resolver.broad_phase_pairs(delta)
		assert_eq(from_core[0], own[0], "round %d: the same bolt and hull pairs" % round)
		assert_eq(from_core[1], own[1], "round %d: the same pairs visited" % round)
		assert_true((own[0] as Array).size() > 0 or round == 0, "round %d: there were pairs to compare" % round)
		assert_eq(resolver.source(), &"core", "round %d: the resolver read the core" % round)
		# The bolts fly on after the tick's first sync (they move at priority 0, the resolver runs at 200): the resolver's
		# sync point must read them where they are now, not where the first sync saw them.
		core.sync_now()
		for node: Node in projectiles.get_children():
			_fly(node as Projectile)
		resolver.use_core = false
		var own_moved: Array = resolver.broad_phase_pairs(delta)
		resolver.use_core = true
		var core_moved: Array = resolver.broad_phase_pairs(delta)
		assert_eq(core_moved[0], own_moved[0], "round %d: the same pairs after the bolts moved" % round)
		if own_moved[0] != own[0]:
			bolts_moved_pairs = true
	assert_true(bolts_moved_pairs, "the moved bolts paired differently in some round, so the second sync was tested")


func test_a_bolt_on_its_launch_tick_sweeps_only_its_muzzle_on_both_paths() -> void:
	if _skipped():
		return
	var resolver := HitResolver.new()
	resolver.name = "HitResolver"
	add_child_autofree(resolver)
	# A ship whose hull ends 2 m short of the muzzle, the bolt flying away from it: a launch-tick bolt has no step behind it,
	# so its sweep is the muzzle alone and misses the ship; a step of `velocity * delta` laid behind the muzzle would reach it.
	var ship: RigidBody3D = _body(Vector3.ZERO, Factions.RAIDERS, "BEHIND", 12.0)
	ship.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	_bolt(Vector3(0.0, 0.0, -14.0), Vector3(0.0, 0.0, -400.0), Factions.EARTH_ALLIANCE, 1)
	var core: SimCore = _core()
	core.sync_now()
	var delta: float = 1.0 / 60.0
	resolver.use_core = false
	var own: Array = resolver.broad_phase_pairs(delta)
	resolver.use_core = true
	var from_core: Array = resolver.broad_phase_pairs(delta)
	assert_eq((own[0] as PackedInt64Array).size(), 0, "the reference sweeps the muzzle alone and misses the ship")
	assert_eq(from_core[0], own[0], "launch tick: the same pairs from the core")
	# The next tick the bolt has flown one step (its own `_physics_process`): both paths see the same segment.
	await get_tree().physics_frame
	await get_tree().physics_frame
	resolver.use_core = false
	var own_next: Array = resolver.broad_phase_pairs(delta)
	resolver.use_core = true
	var core_next: Array = resolver.broad_phase_pairs(delta)
	assert_eq(core_next[0], own_next[0], "the tick after: the same pairs from the core")
	assert_eq(core_next[1], own_next[1], "the tick after: the same pairs visited")


func test_a_hull_destroyed_between_the_resolvers_leaves_the_ram_rows_on_both_paths() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2102
	var hits := HitResolver.new()
	hits.name = "HitResolver"
	add_child_autofree(hits)
	var rams := RamResolver.new()
	rams.name = "RamResolver"
	rams.world = world
	add_child_autofree(rams)
	var bodies: Array[Node3D] = _crowd(rng, 30, 20, 0)
	# Crowd a few so there are pairs.
	for i: int in 8:
		var body := bodies[i] as RigidBody3D
		if body != null:
			body.global_position = Vector3(rng.randf_range(-40.0, 40.0), rng.randf_range(-10.0, 10.0), rng.randf_range(-40.0, 40.0))
			body.linear_velocity = Vector3(rng.randf_range(-600.0, 600.0), 0.0, rng.randf_range(-600.0, 600.0))
	var core: SimCore = _core()
	core.sync_now()
	var delta: float = 1.0 / 60.0
	# The hit resolver (200) reads the tick's bolts, then one of its hits kills a hull; the ram resolver (210) must not see it.
	hits.use_core = true
	hits.broad_phase_pairs(delta)
	var victim: Node3D = bodies[0] if bodies[0] is RigidBody3D else bodies[1]
	_kill(victim)
	assert_false(Damageable.of(victim).is_active(), "the hull is destroyed")
	rams.use_core = true
	var from_core: PackedInt64Array = rams.broad_phase_pairs(delta, PackedInt64Array())
	var core_count: int = rams.hulls_last_tick
	rams.use_core = false
	var own: PackedInt64Array = rams.broad_phase_pairs(delta, PackedInt64Array())
	assert_eq(core_count, rams.hulls_last_tick, "the destroyed hull is out of the core's hull rows, as it is out of the tree walk")
	assert_eq(from_core, own, "the same pairs from the core after a kill between the resolvers")


func test_a_ship_parked_after_the_resync_and_back_the_next_tick_gets_a_new_handle() -> void:
	if _skipped():
		return
	var ship: RigidBody3D = _body(Vector3(100.0, 0.0, -50.0), Factions.EARTH_ALLIANCE, "KILO 1")
	_body(Vector3(-300.0, 20.0, 400.0), Factions.RAIDERS, "R 1")
	var core: SimCore = _core()
	core.sync_now()  # tick N's first sync
	core.sync_bolts_now()  # tick N's resync (the hit resolver's)
	var first: int = core.handle_of(ship.get_instance_id())
	_park(ship)  # released later in tick N (after the resync)
	core.sync_now()  # tick N+1's first sync: the ship sits it out
	assert_eq(core.row_of(first), -1, "a parked ship has no row")
	_unpark(ship)  # acquired again at -5 of tick N+1
	core.sync_bolts_now()  # tick N+1's resync gives it its row
	var second: int = core.handle_of(ship.get_instance_id())
	assert_gt(second, 0, "the ship is a row again")
	assert_ne(second, first, "a ship that sat out one first sync comes back as a new row")
	assert_eq(core.row_of(first), -1, "the old handle stays dead")


func test_the_ram_broad_phase_pairs_from_the_core_as_from_its_own_load() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2101
	var rams := RamResolver.new()
	rams.name = "RamResolver"
	rams.world = world
	add_child_autofree(rams)
	for round: int in 4:
		for node: Node in world.get_children():
			if node != projectiles:
				node.free()
		ContactScan.invalidate()
		var n: int = [2, 10, 60, 150][round]
		var bodies: Array[Node3D] = _crowd(rng, n, 0, 0)
		# Crowd a few of them so the tick's swept boxes overlap.
		for i: int in mini(bodies.size(), 12):
			var body := bodies[i] as RigidBody3D
			if body != null:
				body.global_position = Vector3(rng.randf_range(-40.0, 40.0), rng.randf_range(-10.0, 10.0), rng.randf_range(-40.0, 40.0))
				body.linear_velocity = Vector3(rng.randf_range(-600.0, 600.0), 0.0, rng.randf_range(-600.0, 600.0))
		var core: SimCore = _core()
		core.sync_now()
		var delta: float = 1.0 / 60.0
		var always := PackedInt64Array([0, 1])
		rams.use_core = false
		var own: Array = rams.broad_phase_pairs(delta, always)
		rams.use_core = true
		var from_core: Array = rams.broad_phase_pairs(delta, always)
		assert_eq(from_core, own, "round %d: the same hull pairs from the core as from the resolver's own gather" % round)
		assert_true(own.size() > 1 or round == 0, "round %d: there were pairs to compare" % round)
		assert_eq(rams.source(), &"core", "round %d: the resolver read the core" % round)


## Reuses a ship inside a tick as a carrier launch does (priority -5, after the core's first sync): parked, then taken
## again at a new place with a new velocity.
class Launcher extends Node:
	var ship: Ship = null
	var at_frame: int = -1

	func _init() -> void:
		process_physics_priority = -5

	func _physics_process(_delta: float) -> void:
		if Engine.get_physics_frames() != at_frame or ship == null:
			return
		ship.visible = false
		ship.process_mode = Node.PROCESS_MODE_DISABLED
		ship.process_mode = Node.PROCESS_MODE_INHERIT
		ship.visible = true
		ship.reset_to(Transform3D(Basis.from_euler(Vector3(0.3, 1.1, -0.7)), Vector3(500.0, -20.0, 300.0)))
		ship.linear_velocity = Vector3(0.0, 0.0, -80.0)


func test_the_flight_step_flies_the_same_from_the_core_as_from_the_physics_server() -> void:
	if _skipped():
		return
	var spec: ShipSpec = load(SPEC_PATH) as ShipSpec
	var digests: Array[Array] = []
	for use_core: bool in [true, false]:
		Settings.set_value(&"perf_native_core", use_core)
		var ships: Array[Ship] = []
		for i: int in 3:
			var ship: Ship = Ship.create(spec, world)
			world.spawn(ship, world.to_universe(Vector3(300.0 * i, 0.0, -200.0 * i)))
			assert_true(ship.get_layout().valid, "ship has a valid thruster layout (run scripts/gen_assets.sh)")
			ships.append(ship)
		var launcher := Launcher.new()
		launcher.ship = ships[1]
		add_child(launcher)
		await get_tree().physics_frame
		await get_tree().physics_frame
		launcher.at_frame = Engine.get_physics_frames() + 30  # the same recorded tick in both runs
		var rng := RandomNumberGenerator.new()
		rng.seed = 44
		var lines: Array = []
		for tick: int in 90:
			for ship: Ship in ships:
				var cmd := FlightCommand.new()
				cmd.main_left = rng.randf()
				cmd.main_right = rng.randf()
				cmd.retro_left = 1.0 if rng.randf() < 0.2 else 0.0
				cmd.retro_right = 1.0 if rng.randf() < 0.2 else 0.0
				cmd.rot = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
				cmd.strafe = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
				cmd.brake = rng.randf() < 0.1
				ship.set_flight_command(cmd)
			await get_tree().physics_frame
			var batch: FlightBatch = FlightBatch.attach(world)
			if tick == 10:
				assert_eq(batch.source(), &"core" if use_core else &"server", "the batch reads the %s" % ("core" if use_core else "server"))
			for ship: Ship in ships:
				var o: FlightOutput = ship.get_flight_output()
				# Exact values, compared as such: a formatted float would hide a difference in the last bits.
				lines.append([tick, ship.global_position, ship.linear_velocity, ship.angular_velocity, ship.applied_force(),
						o.rcs_torque_b, o.group_levels[0], o.mass_flow_kg_s, o.face_error_rad])
		digests.append(lines)
		launcher.free()
		for ship: Ship in ships:
			ship.free()
		var batch: FlightBatch = world.get_node_or_null(NodePath(FlightBatch.NODE_NAME))
		if batch != null:
			batch.free()
		var core: Node = world.get_node_or_null(NodePath(SimCore.NODE_NAME))
		if core != null:
			core.free()
		await get_tree().physics_frame
	assert_eq(digests[0].size(), digests[1].size(), "both runs logged every tick")
	var first_difference: int = -1
	for i: int in mini(digests[0].size(), digests[1].size()):
		if digests[0][i] != digests[1][i]:
			first_difference = i
			break
	assert_eq(first_difference, -1, "the batch flies the same from the core as from the physics server (first difference: %s | %s)" % [
			str(digests[0][first_difference]) if first_difference >= 0 else "", str(digests[1][first_difference]) if first_difference >= 0 else ""])


# --- the engine seam ---------------------------------------------------------------------------------------------------


## The kernels (`native/src/kernels.rs`) and the row tables they read (`native/src/rows.rs`) must hold no way to the
## engine: no engine object handle, class, Variant, property read, singleton, instance id, no path into another module of
## the crate and no `godot::` path but the maths and string value types named below. Checked line by line on the source;
## comments are skipped, block comments are refused outright so nothing hides in one.
const KERNEL_FILE: String = "res://native/src/kernels.rs"
const ROWS_FILE: String = "res://native/src/rows.rs"
const KERNEL_USERS: Array[String] = ["res://native/src/contact_field.rs", "res://native/src/hit_sweep.rs",
		"res://native/src/ram_phase.rs", "res://native/src/flight_step.rs", "res://native/src/pilot_kernels.rs",
		"res://native/src/brain_step.rs"]
## The bolt kernels (M4-T35): the bolt step, the cannon gate and spawn and the multimesh transforms, held to the kernels'
## rules; they import the row tables and the shared vector maths, nothing else.
const BOLT_KERNEL_FILE: String = "res://native/src/bolt_kernels.rs"
const BOLT_KERNEL_USERS: Array[String] = ["res://native/src/bolt_rows.rs", "res://native/src/cannons.rs"]
const BOLT_KERNEL_USE_ALLOWED: Array[String] = ["use std::", "use godot::builtin::{Basis, Vector3};", "use crate::rows::",
		"use crate::v3::"]
## The brains' engine-free files (M4-T17): the shared vector maths, the brain maths and the behaviours, held to the kernels'
## rules; they may import each other and the kernels, nothing else.
const BRAIN_FILES: Array[String] = ["res://native/src/v3.rs", "res://native/src/brain_maths.rs",
		"res://native/src/brain_behaviours.rs"]
const BRAIN_USE_ALLOWED: Array[String] = ["use std::", "use godot::builtin::Vector3;", "use godot::builtin::{Basis, Vector3};",
		"use crate::rows::", "use crate::v3::", "use crate::brain_maths::", "use crate::kernels::"]
const KERNEL_FORBIDDEN: Array[String] = ["Gd<", "Variant", "InstanceId", "instance_id", "singleton", "PhysicsServer",
		"godot_error", "godot_print", "godot_warn", "#[func]", "#[godot_api]", "GodotClass", ".get(&", ".call(", "Node",
		"RigidBody", "StringName", "GString", "Scs", "pub use", "/*", "unsafe"]
const ROWS_FORBIDDEN: Array[String] = ["Gd<", "Variant", "InstanceId", "instance_id", "singleton", "PhysicsServer",
		"godot_error", "godot_print", "godot_warn", "#[func]", "#[godot_api]", "GodotClass", ".get(&", ".call(", "Node",
		"RigidBody", "Scs", "pub use", "/*", "unsafe", "Object", "Array", "Packed", "GString"]
## The only `use` lines the kernels may hold: the standard library, two maths builtins, and the row tables' plain data.
const KERNEL_USE_ALLOWED: Array[String] = ["use std::", "use godot::builtin::Vector3;", "use godot::builtin::{Basis, Vector3};",
		"use crate::rows::{Bolts, FLAG_RIGID, Rows};", "use crate::rows::{FLAG_RIGID, Rows};", "use crate::rows::Rows;",
		"use crate::v3::"]
## The only `use` lines the row tables may hold: the standard library and the value types the columns are made of. No engine
## string: the worker threads share the rows (M4-T18), and an engine string cannot be shared between threads.
const ROWS_USE_ALLOWED: Array[String] = ["use std::", "use godot::builtin::{Basis, Vector3};"]
## The core's worker threads (M4-T18): engine-free, the standard library and rayon only.
const THREADS_FILE: String = "res://native/src/threads.rs"
const THREADS_USE_ALLOWED: Array[String] = ["use std::", "use rayon::"]


# Every non-comment line of `path` that names a forbidden token, a path into the crate, or a `godot::` path outside an
# allowed `use` line.
static func _engine_free_violations(path: String, forbidden: Array[String], use_allowed: Array[String]) -> PackedStringArray:
	var found := PackedStringArray()
	var source: String = FileAccess.get_file_as_string(path)
	if source.length() < 200:
		found.append("%s: missing or empty" % path)
		return found
	var lines: PackedStringArray = source.split("\n")
	for i: int in lines.size():
		var line: String = lines[i]
		var code: String = line.strip_edges()
		if code.begins_with("//"):
			continue  # comments may name what the code must not
		for token: String in forbidden:
			if line.contains(token):
				found.append("%s:%d: %s (%s)" % [path.get_file(), i + 1, code, token])
		if code.begins_with("use "):
			var allowed: bool = false
			for prefix: String in use_allowed:
				if code.begins_with(prefix):
					allowed = true
			if not allowed:
				found.append("%s:%d: %s (an import outside the allow-list)" % [path.get_file(), i + 1, code])
			continue
		# Outside a `use` line, no path leaves the module: not into the crate, not up a level, not into godot.
		for path_token: String in ["crate::", "super::", "godot::"]:
			if line.contains(path_token):
				found.append("%s:%d: %s (%s)" % [path.get_file(), i + 1, code, path_token])
	return found


func test_the_kernels_hold_no_engine_type() -> void:
	var violations: PackedStringArray = _engine_free_violations(KERNEL_FILE, KERNEL_FORBIDDEN, KERNEL_USE_ALLOWED)
	violations.append_array(_engine_free_violations(ROWS_FILE, ROWS_FORBIDDEN, ROWS_USE_ALLOWED))
	violations.append_array(_engine_free_violations(BOLT_KERNEL_FILE, KERNEL_FORBIDDEN, BOLT_KERNEL_USE_ALLOWED))
	for user: String in BOLT_KERNEL_USERS:
		assert_true(FileAccess.get_file_as_string(user).contains("use crate::bolt_kernels"), "%s reads the bolt kernels" % user)
	for brain_file: String in BRAIN_FILES:
		violations.append_array(_engine_free_violations(brain_file, KERNEL_FORBIDDEN, BRAIN_USE_ALLOWED))
	violations.append_array(_engine_free_violations(THREADS_FILE, KERNEL_FORBIDDEN, THREADS_USE_ALLOWED))
	assert_eq(violations.size(), 0, "no engine type, call, crate path or stray import in the kernels, the row tables or the brains: %s" % violations)
	var source: String = FileAccess.get_file_as_string(KERNEL_FILE)
	assert_true(source.contains("pub mod contact") and source.contains("pub mod sweep") and source.contains("pub mod ram")
			and source.contains("pub mod flight"), "the four kernels are there")
	# The four classes take their maths from the kernels, so a query or step cannot grow an engine call outside the module.
	for user: String in KERNEL_USERS:
		assert_true(FileAccess.get_file_as_string(user).contains("use crate::kernels::"), "%s reads the kernels" % user)


func test_sync_in_and_sync_out_are_the_only_places_the_core_touches_the_engine() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var resolver := HitResolver.new()
	resolver.name = "HitResolver"
	add_child_autofree(resolver)
	var rams := RamResolver.new()
	rams.name = "RamResolver"
	rams.world = world
	add_child_autofree(rams)
	var sync_reads := PackedInt64Array()
	var fallback_reads := PackedInt64Array()
	for size: int in [10, 100]:
		for node: Node in world.get_children():
			if node != projectiles:
				node.free()
		for node: Node in projectiles.get_children():
			node.free()
		ContactScan.invalidate()
		var bodies: Array[Node3D] = _crowd(rng, size, size * 3, size)
		# Two assembled ships (a marker and a hull, as the game's ships have), far from the crowd, for the flight step.
		for i: int in 2:
			var c: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, projectiles, {
				ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE, ShipAssembly.OPT_DISPLAY_NAME: "FLIGHT %d" % i,
				ShipAssembly.OPT_LEAN: true})
			world.spawn(c.ship, world.to_universe(Vector3(20000.0 + 300.0 * i, 0.0, 0.0)))
			c.ship.set_flight_command(FlightCommand.new())
		var batch: FlightBatch = FlightBatch.attach(world)
		var core: SimCore = _core()
		# Two ticks with no kernel at all: the first reads every body's attributes once, the second is what the sync points
		# cost by themselves from then on.
		for i: int in 2:
			core.sync_now()
			core.sync_bolts_now()
			core.sync_out_now()
		var quiet: int = core.engine_calls()[0]
		core.sync_now()
		# A tick's worth of kernels over the rows: the scan's queries, the hit sweep, the ram broad phase and the flight step.
		var scan: ContactScan = ContactScan.shared(get_tree())
		for body: Node3D in bodies:
			var id: int = body.get_instance_id()
			scan.nearest_for(id, body.global_position, Factions.RAIDERS, 12)
			scan.statics_for(id, body.global_position, Factions.RAIDERS, 4)
			scan.incoming_fire(id, body.global_position, Vector3.ZERO, Factions.RAIDERS)
		resolver.use_core = true
		resolver.broad_phase_pairs(1.0 / 60.0)
		rams.use_core = true
		rams.broad_phase_pairs(1.0 / 60.0, PackedInt64Array())
		# The flight step over the real ships: it reads its rows from the core and applies the forces (the one write).
		batch._physics_process(1.0 / 60.0)
		assert_eq(batch.source(), &"core", "the batch stepped the ships from the core")
		assert_eq(batch.fallback_reads, 0, "no ship had to be read from the physics server")
		core.sync_out_now()
		var calls: PackedInt64Array = core.engine_calls()
		sync_reads.append(calls[0])
		fallback_reads.append(calls[1])
		assert_gte(calls[0], 3 * bodies.size(), "the sync made at least three calls a body at %d bodies" % size)
		assert_eq(calls[0], quiet, "the sync points read nothing again for the queries and steps: the same calls as a quiet tick at %d bodies" % size)
	assert_eq(fallback_reads[0], 0, "no ship read from the physics server at 10 bodies")
	assert_eq(fallback_reads[1], 0, "none at 100 bodies either")
	assert_gt(sync_reads[1], sync_reads[0], "the sync reads once per body and bolt, so it grows with them")
	assert_lt(sync_reads[1], sync_reads[0] * 20, "and only with them")


# --- the weapon kernels (M4-T20) ----------------------------------------------------------------------------------------


## The weapon kernels (`native/src/weapon_kernels.rs`: turrets, interceptors, strike targets, missiles, mines) hold no way to
## the engine either, under the same tokens as the core's kernels; their shell reads them through the crate path.
const WEAPON_KERNEL_FILE: String = "res://native/src/weapon_kernels.rs"
const WEAPON_KERNEL_USERS: Array[String] = ["res://native/src/weapon_rows.rs"]
const WEAPON_KERNEL_USE_ALLOWED: Array[String] = ["use std::", "use godot::builtin::{Basis, Vector3};",
		"use crate::rows::{Bolts, FLAG_HULL_ACTIVE, FLAG_RIGID, Rows};"]


func test_the_weapon_kernels_hold_no_engine_type() -> void:
	var violations: PackedStringArray = _engine_free_violations(WEAPON_KERNEL_FILE, KERNEL_FORBIDDEN, WEAPON_KERNEL_USE_ALLOWED)
	assert_eq(violations.size(), 0, "no engine type, call, crate path or stray import in the weapon kernels: %s" % violations)
	var source: String = FileAccess.get_file_as_string(WEAPON_KERNEL_FILE)
	for kernel: String in ["pub fn retarget", "pub fn aim_gun", "pub fn gate", "pub fn intercept_candidates", "pub fn strike_target",
			"pub fn steer", "pub fn mine_hits", "pub fn blast"]:
		assert_true(source.contains(kernel), "the weapon kernels hold %s" % kernel)
	assert_false(source.contains("static mut") or source.contains("thread_local") or source.contains("Cell<"),
			"no shared mutable state in the weapon kernels (T18's threads)")
	for user: String in WEAPON_KERNEL_USERS:
		assert_true(FileAccess.get_file_as_string(user).contains("use crate::weapon_kernels::"), "%s reads the weapon kernels" % user)


# --- the AI step as a job (M4-T24) --------------------------------------------------------------------------------------


## The step's job (`native/src/brain_step.rs`: the batch over a snapshot of the rows, the hosted drivers' step, the
## commands written) runs on the step's worker thread, so it holds no way to the engine: the kernels' tokens are refused
## and it may import only the engine-free files (the rows, the vector maths, the brains, the kernels, the plain command
## row and the threads). The thread itself lives in `threads.rs`, under the same rule.
const BRAIN_STEP_FILE: String = "res://native/src/brain_step.rs"
const BRAIN_STEP_USE_ALLOWED: Array[String] = ["use std::", "use godot::builtin::Vector3;", "use godot::builtin::{Basis, Vector3};",
		"use crate::rows::", "use crate::v3::", "use crate::brain_maths::", "use crate::brain_behaviours::", "use crate::kernels::",
		"use crate::row_commands::RowCommand;", "use crate::row_commands::{CMD_LEN, EVENT_ENTER, EVENT_FIRE, EVENT_SELECT, EVENT_SETTLE};",
		"use crate::threads::"]


## The low-attention tier's table and integrator (M4-T21): held to the kernels' rules; they import the row tables, the shared
## vector maths, the flight kernel and the command row, nothing else. The core's shell (`tier_rows.rs`) is what reaches them.
const TIER_FILE: String = "res://native/src/tier.rs"
const TIER_SHELL_FILE: String = "res://native/src/tier_rows.rs"
const TIER_USE_ALLOWED: Array[String] = ["use std::", "use godot::builtin::{Basis, Vector3};", "use crate::rows::",
		"use crate::v3::", "use crate::kernels::", "use crate::row_commands::RowCommand;"]


func test_the_tier_kernel_holds_no_engine_type() -> void:
	var violations: PackedStringArray = _engine_free_violations(TIER_FILE, KERNEL_FORBIDDEN, TIER_USE_ALLOWED)
	assert_eq(violations.size(), 0, "no engine type, call, crate path or stray import in the tier: %s" % violations)
	var source: String = FileAccess.get_file_as_string(TIER_FILE)
	for part: String in ["pub fn step(", "fn beat(", "pub fn rotate_basis(", "pub fn far_bodies(", "pub fn near_rows(",
			"pub fn append_to("]:
		assert_true(source.contains(part), "the tier holds %s" % part)
	assert_false(source.contains("static mut") or source.contains("thread_local") or source.contains("Cell<"),
			"no shared mutable state in the tier")
	assert_true(FileAccess.get_file_as_string(TIER_SHELL_FILE).contains("use crate::tier::"), "the shell reads the tier")


func test_the_step_job_holds_no_engine_type() -> void:
	var violations: PackedStringArray = _engine_free_violations(BRAIN_STEP_FILE, KERNEL_FORBIDDEN, BRAIN_STEP_USE_ALLOWED)
	violations.append_array(_engine_free_violations(THREADS_FILE, KERNEL_FORBIDDEN, THREADS_USE_ALLOWED))
	assert_eq(violations.size(), 0, "no engine type, call, crate path or stray import in the step's job or its thread: %s" % violations)
	var source: String = FileAccess.get_file_as_string(BRAIN_STEP_FILE)
	for part: String in ["pub fn run(job: Job) -> Done", "fn run_batch", "fn queue_hosted", "fn write_commands", "fn settle_hosted"]:
		assert_true(source.contains(part), "the job holds %s" % part)
	assert_false(source.contains("static mut") or source.contains("thread_local") or source.contains("Cell<"),
			"no shared mutable state in the job")
	var threads: String = FileAccess.get_file_as_string(THREADS_FILE)
	assert_true(threads.contains("pub struct StepThread"), "the step's thread lives in threads.rs")
	# The compiler keeps engine handles out of a job: a Gd<T> is not Send without gdext's experimental-threads, and the
	# thread takes only Send jobs.
	assert_true(threads.contains("pub struct StepThread<J: Send + 'static, D: Send + 'static>"), "the thread takes Send jobs only")
	# The host hands the job nothing but plain data: it launches through the job's `run`, with no engine handle inside.
	var host: String = FileAccess.get_file_as_string("res://native/src/brain.rs")
	assert_true(host.contains("StepThread::start(STEP_THREAD, brain_step::run)"), "the host's thread runs the job's run")
