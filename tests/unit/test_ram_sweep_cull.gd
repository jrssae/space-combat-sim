extends GutTest
## The ram resolver's swept test with its early rejects (M4-T34): before placing a hull's volumes in the other's frame, the
## hull's bounding sphere, and then each volume's, swept over the tick and padded, must reach the other hull's box, or no volume
## can. The rejects only skip work whose answer is "no ram", so the answer is the same bit for bit: seeded pairs of a many-volume
## fighter and a one-box capital (and the other way round, and two fighters), near misses, grazes and hits, swept both ways,
## give the hits at the points the test gave without the rejects (recorded in `tests/fixtures/parity/ram_sweep_cull.json`
## before M4-T37 removed `perf_ram_sweep_cull`).

const FIXTURE: String = "ram_sweep_cull"
const PAIRS: int = 1500

# A fighter-like hull of many boxes and capsules round its origin.
func _fighter(rng: RandomNumberGenerator) -> Damageable:
	var collision: Array[Dictionary] = []
	for i: int in 13:
		var at := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-1.5, 1.5), rng.randf_range(-7.0, 7.0))
		var turn := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-3.0, 3.0), rng.randf_range(-0.4, 0.4)))
		var shape: Shape3D
		if i % 3 == 0:
			var capsule := CapsuleShape3D.new()
			capsule.radius = rng.randf_range(0.3, 1.0)
			capsule.height = capsule.radius * 2.0 + rng.randf_range(0.5, 4.0)
			shape = capsule
		else:
			var box := BoxShape3D.new()
			box.size = Vector3(rng.randf_range(0.4, 4.0), rng.randf_range(0.3, 1.5), rng.randf_range(0.5, 6.0))
			shape = box
		collision.append({"name": "part %d" % i, "shape": shape, "transform": Transform3D(turn, at)})
	var hull := Damageable.new()
	hull.setup(collision, 300.0, &"raiders")
	autofree(hull)
	return hull


# A capital-like hull: one long box.
func _capital(rng: RandomNumberGenerator) -> Damageable:
	var box := BoxShape3D.new()
	box.size = Vector3(rng.randf_range(60.0, 200.0), rng.randf_range(30.0, 80.0), rng.randf_range(300.0, 900.0))
	var collision: Array[Dictionary] = [{"name": "hull", "shape": box, "transform": Transform3D.IDENTITY}]
	var hull := Damageable.new()
	hull.setup(collision, 30000.0, &"earth_alliance")
	autofree(hull)
	return hull


# A hull as `RamResolver._hull` gives it, at `at` with `basis`, moving by `move` over the tick.
func _entry(hull: Damageable, at: Vector3, basis: Basis, move: Vector3) -> Dictionary:
	return {"damageable": hull, "body": null, "id": hull.get_instance_id(), "rigid": true, "basis": basis,
			"to_body": basis.transposed(), "mass": 1.0, "velocity": move * 60.0, "start": at, "end": at + move}


func test_the_rejects_change_no_answer() -> void:
	var recorded: Variant = ParityFixture.stored(FIXTURE, "pairs_seed_3401")
	assert_not_null(recorded, "the answers without the rejects were recorded")
	if recorded == null:
		return
	var culled: Dictionary = _sweeps()
	gut.p("%d hits among %d sweeps; volumes placed %d without the rejects (recorded), %d with them" % [int(culled["hits"]),
			PAIRS * 4, int(recorded["placed"]), int(culled["placed"])])
	assert_lt(float(culled["placed"]), float(recorded["placed"]) / 2.0, "the rejects spare most of the placing")
	assert_eq(int(culled["count"]), int(recorded["count"]), "as many sweeps as the recording")
	assert_eq(culled["answers"], recorded["answers"], "the same answer to every sweep as without the rejects (recorded, M4-T37)")
	assert_gt(int(culled["hits"]), PAIRS / 10, "enough of the pairs met to compare their points")
	assert_lt(int(culled["hits"]), PAIRS * 3, "and enough missed for the rejects to work")


# The seeded pairs swept both ways, deep and shallow: a digest of every answer, the volumes placed and the hits.
func _sweeps() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3401
	var resolver := RamResolver.new()
	var hits: int = 0
	var placed: int = 0
	var answers: Array = []
	for p: int in PAIRS:
		var big: Damageable = _capital(rng) if p % 3 != 2 else _fighter(rng)
		var small: Damageable = _fighter(rng)
		var reach: float = big.bounding_radius + small.bounding_radius
		# Somewhere inside the two bounding spheres, so the first sphere test passes and the rejects decide.
		var offset := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() \
				* rng.randf_range(0.0, reach)
		var origin := Vector3(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-500.0, 500.0), rng.randf_range(-3000.0, 3000.0))
		var move := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) \
				* rng.randf_range(0.0, 15.0)
		var a: Dictionary = _entry(small, origin + offset, Basis.from_euler(Vector3(rng.randf() * 3.0, rng.randf() * 6.0, rng.randf())),
				move)
		var b: Dictionary = _entry(big, origin, Basis.from_euler(Vector3(rng.randf(), rng.randf() * 6.0, rng.randf())),
				Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)))
		for order: Array in [[a, b], [b, a]]:
			for deep: bool in [true, false]:
				var before: int = resolver.volumes_placed
				var answer: Dictionary = resolver._sweep_pair(order[0], order[1], deep)
				placed += resolver.volumes_placed - before
				answers.append(var_to_str(answer))
				hits += 0 if answer.is_empty() else 1
	resolver.free()
	return {"answers": ParityFixture.digest(answers), "count": answers.size(), "placed": placed, "hits": hits}
