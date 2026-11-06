extends GutTest
## The ram resolver's swept test with its early rejects (M4-T34): before placing a hull's volumes in the other's frame, the
## hull's bounding sphere, and then each volume's, swept over the tick and padded, must reach the other hull's box, or no volume
## can. The rejects only skip work whose answer is "no ram", so the answer is the same bit for bit: seeded pairs of a many-volume
## fighter and a one-box capital (and the other way round, and two fighters), near misses, grazes and hits, swept both ways
## with `perf_ram_sweep_cull` on and off, give the same hits at the same points.

const PAIRS: int = 1500

var _saved: Variant


func before_each() -> void:
	_saved = Settings.get_value(&"perf_ram_sweep_cull")


func after_each() -> void:
	Settings.set_value(&"perf_ram_sweep_cull", _saved)


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
			"to_body": basis.transposed(), "mass": 1.0, "velocity": move * 60.0, "start": at, "end": at + move, "accel": Vector3.ZERO}


func test_the_rejects_change_no_answer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3401
	var resolver := RamResolver.new()
	autofree(resolver)
	assert_true(Settings.get_value(&"perf_ram_sweep_cull") is bool, "the setting exists")
	var hits: int = 0
	var placed := PackedInt64Array([0, 0])
	var differences := PackedStringArray()
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
				Settings.set_value(&"perf_ram_sweep_cull", false)
				var before: int = resolver.volumes_placed
				var plain: Dictionary = resolver._sweep_pair(order[0], order[1], deep)
				placed[0] += resolver.volumes_placed - before
				Settings.set_value(&"perf_ram_sweep_cull", true)
				before = resolver.volumes_placed
				var culled: Dictionary = resolver._sweep_pair(order[0], order[1], deep)
				placed[1] += resolver.volumes_placed - before
				if var_to_str(plain) != var_to_str(culled):
					differences.append("pair %d: %s against %s" % [p, var_to_str(plain), var_to_str(culled)])
				hits += 0 if plain.is_empty() else 1
	gut.p("%d hits among %d sweeps; volumes placed %d without the rejects, %d with them" % [hits, PAIRS * 4, placed[0], placed[1]])
	assert_lt(placed[1], placed[0] / 2, "the rejects spare most of the placing")
	assert_eq(differences.size(), 0, "the same answer with and without the rejects: %s" % ", ".join(differences.slice(0, 5)))
	assert_gt(hits, PAIRS / 10, "enough of the pairs met to compare their points")
	assert_lt(hits, PAIRS * 3, "and enough missed for the rejects to work")
