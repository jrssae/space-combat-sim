extends GutTest
## The native body registry (M4-T09, architecture §17.8): bodies are known to it once, and each tick one native refresh reads
## what the scan needs, so `ContactScan` builds no per-tick arrays in GDScript. Its scan must equal `ContactScan.from_tree`
## bit for bit (the same rows in the same order, the same positions, velocities, axes, factions, names, radii, ship flags
## and kinds). Light bodies made here (a rigid body with a `Targetable` and a `Damageable`, props, a hull without a marker),
## nothing stepped.

const FIXTURE: String = "body_registry"
const ROWS_COMPARED: Array[String] = ["_body_ids", "_ids", "_names", "_factions", "_positions", "_velocities", "_forwards",
		"_ups", "_radii", "_is_ship", "_kinds"]

var root: Node3D


func before_each() -> void:
	Factions.reset()
	ContactScan.invalidate()
	ContactScan.clear_statics()
	root = Node3D.new()
	add_child_autofree(root)


func after_each() -> void:
	ContactScan.clear_statics()
	ContactScan.invalidate()
	Factions.reset()


# A rigid body with a marker and a hull, as `ShipAssembly` builds them (without the rest of a ship).
func _body(at: Vector3, faction: StringName, label: String, radius: float = 12.0, marker: Targetable = null) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	root.add_child(body)
	body.global_transform = Transform3D(Basis.from_euler(Vector3(at.x * 0.001, at.y * 0.002, at.z * 0.003)), at)
	body.linear_velocity = Vector3(at.z * 0.01, -at.x * 0.01, 3.0)
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
	root.add_child(prop)
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
	root.add_child(body)
	body.global_position = at
	var hull := Damageable.new()
	hull.faction = Factions.RAIDERS
	hull.bounding_radius = 4.0
	body.add_child(hull)
	return body


func _park(body: Node3D) -> void:
	body.visible = false
	body.process_mode = Node.PROCESS_MODE_DISABLED


func _unpark(body: Node3D) -> void:
	body.process_mode = Node.PROCESS_MODE_INHERIT
	body.visible = true


# A seeded crowd of every sort of body, some of them parked.
func _crowd(rng: RandomNumberGenerator, n: int) -> Array[Node3D]:
	var sides: Array[StringName] = [Factions.RAIDERS, Factions.EARTH_ALLIANCE, Factions.NEUTRAL]
	var out: Array[Node3D] = []
	for i: int in n:
		var at := Vector3(rng.randf_range(-9000.0, 9000.0), rng.randf_range(-3000.0, 3000.0), rng.randf_range(-9000.0, 9000.0))
		var roll: float = rng.randf()
		var body: Node3D
		if roll < 0.08:
			body = _prop(at, "BUOY %d" % i)
		elif roll < 0.14:
			body = _drone(at)
		elif roll < 0.22:
			var marker := Targetable.new()
			marker.kind = [Targetable.Kind.CAPITAL, Targetable.Kind.STATIC, Targetable.Kind.MINE, Targetable.Kind.PROP, Targetable.Kind.TURRET,
					Targetable.Kind.SHIP][rng.randi_range(0, 5)]
			body = _body(at, sides[rng.randi_range(0, 2)], "KIND %d" % i, rng.randf_range(5.0, 600.0), marker)
		else:
			body = _body(at, sides[rng.randi_range(0, 2)], "SHIP %d" % i, rng.randf_range(5.0, 30.0))
		if rng.randf() < 0.15:
			_park(body)
		out.append(body)
	return out


# The registry's scan of the tree as it is now (a fresh one, never the cached `shared`).
func _registry_scan() -> ContactScan:
	var scan: ContactScan = ContactScan.from_registry(get_tree())
	assert_not_null(scan, "the registry is available (%s)" % NativeLib.version(ContactScan.REGISTRY_CLASS))
	return scan


# Fails, naming the first difference, unless both scans hold the same rows bit for bit.
func _assert_same_rows(native: ContactScan, script: ContactScan, label: String) -> void:
	for field: String in ROWS_COMPARED:
		var a: Variant = native.get(field)
		var b: Variant = script.get(field)
		if a == b:
			continue
		var first: int = -1
		for i: int in mini(a.size(), b.size()):
			if a[i] != b[i]:
				first = i
				break
		fail_test("%s: %s differs (sizes %d and %d, first at row %d: %s against %s)" % [label, field, a.size(), b.size(),
				first, a[first] if first >= 0 else "-", b[first] if first >= 0 else "-"])
		return
	pass_test("%s: %d rows the same" % [label, script._body_ids.size()])


func test_body_kinds_read_names_values_and_nothing() -> void:
	assert_eq(BodyKind.from_variant(null), BodyKind.SHIP, "nothing is a ship")
	assert_eq(BodyKind.from_variant(&"static"), BodyKind.STATIC)
	assert_eq(BodyKind.from_variant("Mine"), BodyKind.MINE, "any case")
	assert_eq(BodyKind.from_variant(BodyKind.CAPITAL), BodyKind.CAPITAL)
	assert_eq(BodyKind.from_variant(42), BodyKind.SHIP, "an unknown value is a ship")
	assert_eq(BodyKind.from_variant(&"asteroid"), BodyKind.SHIP, "an unknown name is a ship")
	assert_true(BodyKind.is_static(BodyKind.STATIC) and BodyKind.is_static(BodyKind.MINE), "rocks and mines are obstacles")
	assert_false(BodyKind.is_static(BodyKind.PROP) or BodyKind.is_static(BodyKind.CAPITAL), "props and capitals are contacts")


func test_the_registry_scan_equals_the_tree_gather_bit_for_bit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026_11_09
	for n: int in [1, 7, 60, 300]:
		for child: Node in root.get_children():
			child.free()
		_crowd(rng, n)
		_assert_same_rows(_registry_scan(), ContactScan.from_tree(get_tree()), "%d bodies" % n)


func test_the_core_scan_equals_the_recorded_tree_gather_bit_for_bit() -> void:
	# M4-T37: the tree gather is gone; its rows for these seeded crowds are recorded in
	# `tests/fixtures/parity/body_registry.json` (without the instance ids, which differ between runs).
	var world := WorldFrame.new()
	add_child_autofree(world)
	var sim: SimCore = SimCore.attach(world)
	assert_not_null(sim, "a core under the world")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026_11_09
	for n: int in [1, 7, 60, 300]:
		for child: Node in root.get_children():
			child.free()
		_crowd(rng, n)
		await get_tree().physics_frame
		var recorded: Variant = await ParityFixture.expected(FIXTURE, "crowd_%d" % n, func() -> Dictionary:
			return _rows(ContactScan.from_tree(get_tree())))
		sim.forget_attributes()
		sim.sync_now()
		var scan: ContactScan = ContactScan.from_core(get_tree())
		assert_not_null(scan, "%d bodies: the core gives a scan" % n)
		assert_eq(ParityFixture.encode(_rows(scan)), recorded, "%d bodies: the core's rows are the tree gather's (recorded)" % n)


# A scan's rows without the instance ids: each compared field's digest and the row count.
static func _rows(scan: ContactScan) -> Dictionary:
	var out: Dictionary = {"rows": scan._names.size()}
	for field: String in ROWS_COMPARED:
		if field != "_body_ids" and field != "_ids":
			out[field] = ParityFixture.digest(scan.get(field))
	return out


func test_node_less_static_rows_come_after_the_bodies_on_both_paths() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_crowd(rng, 40)
	var world := WorldFrame.new()
	add_child_autofree(world)
	for s: int in 1000:
		ContactScan.register_static(900000 + s, Vector3(rng.randf_range(-10000.0, 10000.0), 0.0, rng.randf_range(-10000.0,
				10000.0)), rng.randf_range(20.0, 200.0), BodyKind.MINE if s % 10 == 0 else BodyKind.STATIC, Factions.NEUTRAL,
				world)
	var script := ContactScan.from_tree(get_tree())
	_assert_same_rows(_registry_scan(), script, "40 bodies and 1 000 statics")
	assert_eq(script._body_ids.slice(script._body_ids.size() - 1000), PackedInt64Array(range(900000, 901000)),
			"the statics follow the bodies in the order they were registered")
	ContactScan.shift_statics(Vector3(100.0, 0.0, -50.0), world)
	ContactScan.unregister_static(900003)
	script = ContactScan.from_tree(get_tree())
	_assert_same_rows(_registry_scan(), script, "after a shift and one removal")
	assert_false(script._body_ids.has(900003), "the removed static is gone")


func test_a_parked_body_is_gone_from_the_next_scan_and_back_renamed_after_a_quick_reuse() -> void:
	var a := _body(Vector3(100, 0, 0), Factions.RAIDERS, "RAIDER 1")
	var b := _body(Vector3(200, 0, 0), Factions.RAIDERS, "RAIDER 2")
	var marker_b := b.get_node(^"Targetable") as Targetable
	assert_true(_registry_scan()._body_ids.has(b.get_instance_id()), "both bodies are in the scan")
	_park(b)
	var scan := _registry_scan()
	assert_false(scan._body_ids.has(b.get_instance_id()), "a parked body is gone from the next scan")
	assert_true(scan._body_ids.has(a.get_instance_id()), "the other stays")
	# The pool's release and acquire in one tick: the registry never sees it parked, yet reads its new name.
	_unpark(b)
	_registry_scan()
	_park(b)
	marker_b.display_name = "RAIDER 9"
	_unpark(b)
	scan = _registry_scan()
	var at: int = scan._body_ids.find(b.get_instance_id())
	assert_gt(at, -1, "back in the scan")
	assert_eq(scan._names[at], "RAIDER 9", "with the name it was given while parked")
	_assert_same_rows(scan, ContactScan.from_tree(get_tree()), "after the reuse")


func test_a_moved_body_is_seen_at_its_new_place_without_registering_again() -> void:
	var a := _body(Vector3(100, 0, 0), Factions.RAIDERS, "RAIDER 1")
	_registry_scan()
	a.global_position = Vector3(-4000, 25, 12.5)
	a.linear_velocity = Vector3(7, 8, 9)
	var scan := _registry_scan()
	var at: int = scan._body_ids.find(a.get_instance_id())
	assert_eq(scan._positions[at], Vector3(-4000, 25, 12.5), "the new position")
	assert_eq(scan._velocities[at], Vector3(7, 8, 9), "the new velocity")


func test_a_freed_body_is_noticed_by_the_scan_and_dropped_by_the_next() -> void:
	var a := _body(Vector3(100, 0, 0), Factions.RAIDERS, "RAIDER 1")
	var b := _body(Vector3(200, 0, 0), Factions.RAIDERS, "RAIDER 2")
	var b_id: int = b.get_instance_id()
	var scan := _registry_scan()
	assert_true(scan._bodies_alive(), "both exist")
	b.free()
	assert_false(scan._bodies_alive(), "the scan knows a body it holds was freed")
	scan = _registry_scan()
	assert_false(scan._body_ids.has(b_id), "the next scan has no row for it")
	assert_true(scan._bodies_alive())
	assert_true(scan._body_ids.has(a.get_instance_id()))


func test_attributes_are_read_once_not_every_tick() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	_crowd(rng, 100)
	_registry_scan()
	var registry: Object = ContactScan.registry()
	var reads: int = registry.attribute_reads()
	assert_gt(reads, 0, "the first scan read every active body's faction, name, kind and radius")
	for tick: int in 10:
		_registry_scan()
	assert_eq(registry.attribute_reads(), reads, "ten more scans read no attribute again")


func test_the_shared_scan_gathers_nothing_in_gdscript_on_the_native_path() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	_crowd(rng, 50)
	var before: int = ContactScan.gathers
	var scan := ContactScan.shared(get_tree())
	assert_eq(ContactScan.gathers, before, "no gather from the tree with the library")
	_assert_same_rows(scan, ContactScan.from_tree(get_tree()), "the shared scan")


func test_a_rebase_moves_its_own_worlds_static_rows_once_on_both_paths() -> void:
	var a := WorldFrame.new()
	add_child_autofree(a)
	var b := WorldFrame.new()
	add_child_autofree(b)
	var at_a := Vector3(1234.5, -20.25, 987.125)
	var at_b := Vector3(-40.0, 5.5, 3000.0)
	var at_none := Vector3(7.0, 8.0, 9.0)
	ContactScan.register_static(910001, at_a, 50.0, BodyKind.STATIC, Factions.NEUTRAL, a)
	ContactScan.register_static(910002, at_b, 60.0, BodyKind.MINE, Factions.NEUTRAL, b)
	ContactScan.register_static(910003, at_none, 70.0)
	var offset := Vector3(5000.0, -250.0, 12000.5)
	var expected_a: Vector3 = at_a
	for rebase: int in 2:
		a.rebase(offset)
		expected_a = expected_a - offset
		for native: bool in [true]:
			ContactScan.invalidate()
			var scan: ContactScan = ContactScan.shared(get_tree())
			var label: String = "after rebase %d, %s" % [rebase + 1, scan.path()]
			assert_eq(scan._positions[scan._body_ids.find(910001)], expected_a, "%s: world A's row moved by -offset once" % label)
			assert_eq(scan._positions[scan._body_ids.find(910002)], at_b, "%s: world B's row did not move" % label)
			assert_eq(scan._positions[scan._body_ids.find(910003)], at_none, "%s: a row with no world did not move" % label)
		_assert_same_rows(_registry_scan(), ContactScan.from_tree(get_tree()), "after rebase %d" % (rebase + 1))


func test_the_broadcast_scan_equals_from_broadcasters_row_for_row() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	_crowd(rng, 30)
	# Buoys, allies with a 100 km reach, a parked broadcaster, and a body whose second marker broadcasts.
	for i: int in 3:
		var buoy := _prop(Vector3(float(i) * 9000.0, 0.0, -20000.0), "NAV %d" % i)
		(buoy.get_child(1) as Targetable).broadcast_range_m = 1.0e6
	for i: int in 6:
		var ally := _body(Vector3(float(i) * 300.0, 0.0, 15000.0), Factions.EARTH_ALLIANCE, "ALPHA %d" % i)
		(ally.get_node(^"Targetable") as Targetable).broadcast_range_m = 1.0e5
		if i == 4:
			_park(ally)
	var twin := _body(Vector3(-6000.0, 100.0, 4000.0), Factions.EARTH_ALLIANCE, "TWIN")
	var second := Targetable.new()
	second.display_name = "TWIN BEACON"
	second.faction = Factions.EARTH_ALLIANCE
	twin.add_child(second)
	second.broadcast_range_m = 5.0e4
	ContactScan.invalidate()
	ContactScan.shared(get_tree())
	var native: ContactScan = ContactScan.shared_broadcasts()
	assert_true(native._from_registry, "the broadcast scan comes from the registry")
	var script := ContactScan.from_broadcasters(Targetable.broadcasters())
	_assert_same_rows(native, script, "broadcasters")
	assert_eq(native._reach, script._reach, "the same reach, row by row")
	assert_eq(script._body_ids.size(), 9, "three buoys, five shown allies and the twin's beacon")
	assert_true(native._ids.has(second.get_instance_id()), "a body's second marker broadcasts too")
	for who: Array in [[Vector3(0.0, 0.0, -60000.0), Factions.RAIDERS], [Vector3(0.0, 0.0, 70000.0), Factions.EARTH_ALLIANCE]]:
		var heard_native: Array[Contact] = native.broadcasts_for(-1, who[0], who[1])
		var heard_script: Array[Contact] = script.broadcasts_for(-1, who[0], who[1])
		assert_eq(heard_native.size(), heard_script.size(), "heard at %s" % who[0])
		for i: int in mini(heard_native.size(), heard_script.size()):
			assert_eq(heard_native[i].id, heard_script[i].id)
			assert_eq(heard_native[i].hull_fraction, heard_script[i].hull_fraction)
