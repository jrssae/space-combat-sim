extends GutTest
## The native body registry (M4-T09, architecture §17.8): bodies are known to it once, and each tick one native refresh reads
## what the scan needs, so `ContactScan` builds no per-tick arrays in GDScript. Its scan must equal `ContactScan.from_tree`
## bit for bit (the same rows in the same order, the same positions, velocities, axes, factions, names, radii, ship flags
## and kinds). Light bodies made here (a rigid body with a `Targetable` and a `Damageable`, props, a hull without a marker),
## nothing stepped. Skips, saying why, when the native library is not built at all.

const ROWS_COMPARED: Array[String] = ["_body_ids", "_ids", "_names", "_factions", "_positions", "_velocities", "_forwards",
		"_ups", "_radii", "_is_ship", "_kinds"]

var root: Node3D
var _native_backup: bool


## A marker that says what kind of body it marks, as `Targetable.kind` will (M4-T07).
class KindedMarker extends Targetable:
	var kind: Variant = &"ship"


func before_each() -> void:
	_native_backup = bool(Settings.get_value(&"perf_native"))
	Settings.set_value(&"perf_native", true)
	Factions.reset()
	ContactScan.invalidate()
	ContactScan.clear_statics()
	root = Node3D.new()
	add_child_autofree(root)


func after_each() -> void:
	ContactScan.clear_statics()
	ContactScan.invalidate()
	Settings.set_value(&"perf_native", _native_backup)
	Factions.reset()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no registry to compare")
	return true


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
			var marker := KindedMarker.new()
			marker.kind = [&"capital", &"static", 4, "Prop", 9, null][rng.randi_range(0, 5)]
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
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026_11_09
	for n: int in [1, 7, 60, 300]:
		for child: Node in root.get_children():
			child.free()
		_crowd(rng, n)
		_assert_same_rows(_registry_scan(), ContactScan.from_tree(get_tree()), "%d bodies" % n)


func test_node_less_static_rows_come_after_the_bodies_on_both_paths() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_crowd(rng, 40)
	for s: int in 1000:
		ContactScan.register_static(900000 + s, Vector3(rng.randf_range(-10000.0, 10000.0), 0.0, rng.randf_range(-10000.0,
				10000.0)), rng.randf_range(20.0, 200.0), BodyKind.MINE if s % 10 == 0 else BodyKind.STATIC)
	var script := ContactScan.from_tree(get_tree())
	_assert_same_rows(_registry_scan(), script, "40 bodies and 1 000 statics")
	assert_eq(script._body_ids.slice(script._body_ids.size() - 1000), PackedInt64Array(range(900000, 901000)),
			"the statics follow the bodies in the order they were registered")
	ContactScan.shift_statics(Vector3(100.0, 0.0, -50.0))
	ContactScan.unregister_static(900003)
	script = ContactScan.from_tree(get_tree())
	_assert_same_rows(_registry_scan(), script, "after a shift and one removal")
	assert_false(script._body_ids.has(900003), "the removed static is gone")


func test_a_parked_body_is_gone_from_the_next_scan_and_back_renamed_after_a_quick_reuse() -> void:
	if _skipped():
		return
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
	if _skipped():
		return
	var a := _body(Vector3(100, 0, 0), Factions.RAIDERS, "RAIDER 1")
	_registry_scan()
	a.global_position = Vector3(-4000, 25, 12.5)
	a.linear_velocity = Vector3(7, 8, 9)
	var scan := _registry_scan()
	var at: int = scan._body_ids.find(a.get_instance_id())
	assert_eq(scan._positions[at], Vector3(-4000, 25, 12.5), "the new position")
	assert_eq(scan._velocities[at], Vector3(7, 8, 9), "the new velocity")


func test_a_freed_body_is_noticed_by_the_scan_and_dropped_by_the_next() -> void:
	if _skipped():
		return
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
	if _skipped():
		return
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
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	_crowd(rng, 50)
	var before: int = ContactScan.gathers
	var scan := ContactScan.shared(get_tree())
	assert_eq(ContactScan.gathers, before, "no gather from the tree with the library and perf_native on")
	_assert_same_rows(scan, ContactScan.from_tree(get_tree()), "the shared scan")
	Settings.set_value(&"perf_native", false)
	ContactScan.invalidate()
	before = ContactScan.gathers
	ContactScan.shared(get_tree())
	assert_eq(ContactScan.gathers, before + 1, "perf_native off: the GDScript gather")
