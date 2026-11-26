extends GutTest
## The native blast batch's seams (M10-T76, Q70): a hit volume packs into the 30 numbers the batch reads, a blast with no core
## lands on nothing but still counts, and a field with nothing waiting has no landing to run. The landing itself is
## `test_blast_landing_parity` (bit for bit against the GDScript landing it replaced) and the cargo tests of
## `damage_store::blasts`.


func before_each() -> void:
	BlastResolver.reset_stats()


func test_a_hit_volume_packs_into_the_numbers_the_batch_reads() -> void:
	var box := HitShape.make_box(Transform3D(Basis.from_euler(Vector3(0.3, 0.2, 0.1)), Vector3(1.0, 2.0, 3.0)), Vector3(2.0, 4.0, 6.0))
	var packed: PackedFloat64Array = box.packed()
	assert_eq(packed.size(), 30, "capsule, transform, its inverse, half extents, radius, half segment")
	assert_eq(packed[0], 0.0, "a box")
	assert_eq(Vector3(packed[25], packed[26], packed[27]), box.half_extents)
	var inverse: Transform3D = box.transform.affine_inverse()
	assert_eq(Vector3(packed[22], packed[23], packed[24]), inverse.origin, "the engine's own inverse")
	var capsule := HitShape.make_capsule(Transform3D.IDENTITY, 1.5, 8.0)
	assert_eq(capsule.packed()[0], 1.0, "a capsule")
	assert_eq(capsule.packed()[29], capsule.half_segment)


func test_a_blast_with_no_core_reaches_no_hull_and_is_still_counted() -> void:
	var batch: Object = BlastResolver.batch()
	assert_not_null(batch, "the native library has the batch")
	batch.set_off(PackedFloat64Array([60.0, 100.0, 2000.0, 50.0]), &"fighter_death", Vector3.ZERO, &"", 0)
	assert_true(bool(batch.pending()))
	var got: Array = batch.run(null, false)
	assert_true(bool(got[0]), "all landed in one run")
	assert_false(bool(batch.pending()))
	assert_eq(int((batch.stats() as PackedFloat64Array)[0]), 1, "one blast")
	assert_eq(int((batch.last() as Array)[2]), 0, "it reached nothing")


func test_a_field_with_nothing_waiting_has_no_landing() -> void:
	assert_false(bool(BlastResolver.batch().begin_field(987654, Vector3.ZERO)), "an unknown field")
