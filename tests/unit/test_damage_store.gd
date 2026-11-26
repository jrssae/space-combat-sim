extends GutTest
## The damage store's GDScript side (M10-T75, Q94, `DamageStore`): the log codes agree with the native store's, a copy's direct
## writes reach the store, freed copies free their ledgers, a hull's landing is registered for the beams' batch, and the store's
## World-to-body maths gives the engine's bits (so the batch names the same sections and zones as GDScript did).

const CASES: int = 500


func test_the_log_codes_agree_with_the_native_store() -> void:
	var native: Dictionary = ClassDB.class_call_static(DamageStore.NATIVE_CLASS, &"codes")
	assert_false(native.is_empty(), "the store names its codes")
	var mine: Dictionary = (DamageStore as Script).get_script_constant_map()
	for name: String in native:
		assert_eq(mine.get(name), int(native[name]), "%s agrees" % name)


func test_a_direct_write_reaches_the_store_and_a_freed_copy_frees_its_ledger() -> void:
	var before: int = int(DamageStore.live()[0])
	var hull := HullHealth.new(300.0)
	assert_eq(int(DamageStore.live()[0]), before + 1)
	hull.hp = 120.0
	var held: PackedFloat64Array = DamageStore.store.hull_state(hull.id)
	assert_eq(held[1], 120.0, "the store has the written points")
	assert_eq(hull.apply(150.0), 120.0, "and the rules take them from there")
	assert_true(hull.destroyed)
	hull = null
	assert_eq(int(DamageStore.live()[0]), before, "the ledger went with its copy")


func test_a_hulls_landing_is_registered_with_its_flags() -> void:
	var d := Damageable.new()
	var id: int = d.get_instance_id()
	d.setup([], 50.0, Factions.RAIDERS, true, false, &"x_fighter")
	d.invulnerable = true
	var held: PackedInt64Array = DamageStore.store.target_state(d.get_instance_id())
	assert_eq(held.size(), 8, "registered")
	assert_eq(held[0], d.hull.id, "its hull")
	assert_eq(held[2], Damageable.LANDING_PLAIN)
	assert_eq(held[6], DamageZones.Layout.X_FIGHTER, "its silhouette's zones")
	assert_eq(held[7], 1 | 2, "invulnerable, and god mode applies")
	d.free()
	assert_eq(DamageStore.store.target_state(id).size(), 0, "a freed hull's landing goes with it")


func test_the_stores_world_to_body_maths_gives_the_engines_bits() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 75
	var worst: int = 0
	for i: int in CASES:
		var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if axis.length_squared() < 1e-6:
			axis = Vector3.UP
		var basis := Basis(axis.normalized(), rng.randf_range(-PI, PI))
		if i % 4 == 0:
			basis = basis.scaled(Vector3(rng.randf_range(0.3, 3.0), rng.randf_range(0.3, 3.0), rng.randf_range(0.3, 3.0)))
		var xform := Transform3D(basis, Vector3(rng.randf_range(-9e3, 9e3), rng.randf_range(-9e3, 9e3), rng.randf_range(-9e3, 9e3)))
		var point := Vector3(rng.randf_range(-9e3, 9e3), rng.randf_range(-9e3, 9e3), rng.randf_range(-9e3, 9e3))
		var engine: Vector3 = xform.affine_inverse() * point
		var store: Vector3 = ClassDB.class_call_static(DamageStore.NATIVE_CLASS, &"probe_to_local", xform, point)
		if engine != store:
			worst += 1
	assert_eq(worst, 0, "every point bit for bit (%d of %d off)" % [worst, CASES])
