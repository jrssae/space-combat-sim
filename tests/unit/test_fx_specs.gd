extends GutTest
## FxSpecs (M3-T23, AC32): the pure numbers behind the particle effects, and the maths that aims and sizes a burst.


func test_every_effect_has_a_complete_spec() -> void:
	for effect: int in FxSpecs.COUNT:
		var spec: Dictionary = FxSpecs.spec(effect)
		for key: String in ["name", "emitters", "amount", "lifetime_s", "speed_mps", "spread_deg", "continuous", "material"]:
			assert_true(spec.has(key), "%s has %s" % [effect, key])
		assert_gt(int(spec["emitters"]), 0)
		assert_gt(int(spec["amount"]), 0)
		assert_gt(float(spec["lifetime_s"]), 0.0)
		assert_lte((spec["speed_mps"] as Vector2).x, (spec["speed_mps"] as Vector2).y, "speed range is ordered")


# One buoy's shards must not take vents from each other or from a ship breaking up beside it.
func test_the_debris_pool_covers_a_whole_break_up() -> void:
	assert_gte(int(FxSpecs.spec(FxSpecs.DEBRIS)["emitters"]), DebrisPool.SHARD_COUNT)


func test_names_are_unique() -> void:
	var seen: Dictionary = {}
	for effect: int in FxSpecs.COUNT:
		var effect_name: String = FxSpecs.spec(effect)["name"]
		assert_false(seen.has(effect_name), "%s is used twice" % effect_name)
		seen[effect_name] = true


func test_density_scales_the_amount_and_zero_emits_nothing() -> void:
	var full: int = int(FxSpecs.spec(FxSpecs.HIT)["amount"])
	assert_eq(FxSpecs.amount_for(FxSpecs.HIT, 1.0), full)
	assert_eq(FxSpecs.amount_for(FxSpecs.HIT, 0.0), 0, "density 0 emits nothing")
	assert_eq(FxSpecs.amount_for(FxSpecs.HIT, 0.5), roundi(full * 0.5))
	assert_eq(FxSpecs.amount_for(FxSpecs.HIT, 7.0), full, "above 1 is capped")
	assert_eq(FxSpecs.amount_for(FxSpecs.HIT, -1.0), 0, "below 0 is capped")


func test_the_amount_ratio_is_the_share_of_the_pool_amount() -> void:
	assert_almost_eq(FxSpecs.ratio_for(FxSpecs.EXPLOSION_SPARKS, 1.0), 1.0, 1e-6)
	assert_eq(FxSpecs.ratio_for(FxSpecs.EXPLOSION_SPARKS, 0.0), 0.0)
	var half: float = FxSpecs.ratio_for(FxSpecs.EXPLOSION_SPARKS, 0.5)
	assert_almost_eq(half, 0.5, 0.02)


func test_a_hit_throws_sparks_back_off_the_surface() -> void:
	# A bolt flying down -Z into a hull whose surface faces +Z comes back out along +Z.
	var out: Vector3 = FxSpecs.hit_direction(Vector3(0, 0, -1), Vector3(0, 0, 1))
	assert_almost_eq(out, Vector3(0, 0, 1), Vector3.ONE * 1e-5)
	# A glancing bolt keeps its tangential motion and loses the normal one.
	var glance: Vector3 = FxSpecs.hit_direction(Vector3(1, 0, -1).normalized(), Vector3(0, 0, 1))
	assert_almost_eq(glance, Vector3(1, 0, 1).normalized(), Vector3.ONE * 1e-5)


func test_a_reflection_never_points_into_the_hull() -> void:
	# A surface normal that faces the wrong way (a bolt that started inside the shell) is flipped, not followed.
	var out: Vector3 = FxSpecs.hit_direction(Vector3(0, 0, -1), Vector3(0, 0, -1))
	assert_gt(out.dot(Vector3(0, 0, 1)), 0.0, "the sparks leave the surface")
	assert_almost_eq(out.length(), 1.0, 1e-5)


func test_hit_direction_survives_degenerate_input() -> void:
	assert_eq(FxSpecs.hit_direction(Vector3.ZERO, Vector3.ZERO), Vector3.UP, "no information: a safe default")
	assert_almost_eq(FxSpecs.hit_direction(Vector3(0, 0, -1), Vector3.ZERO).length(), 1.0, 1e-5)


func test_basis_facing_points_y_along_the_direction() -> void:
	for direction: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3(1, 2, 3).normalized(), Vector3(0, 0, -1)]:
		var basis: Basis = FxSpecs.basis_facing(direction)
		assert_almost_eq(basis.y, direction, Vector3.ONE * 1e-5)
		assert_almost_eq(basis.determinant(), 1.0, 1e-4, "a proper rotation")
		assert_almost_eq(basis.x.length(), 1.0, 1e-5)
		assert_almost_eq(basis.x.dot(basis.y), 0.0, 1e-5)
		assert_almost_eq(basis.z.dot(basis.y), 0.0, 1e-5)
	assert_eq(FxSpecs.basis_facing(Vector3.ZERO), Basis.IDENTITY, "no direction: identity")


func test_the_debris_vents_for_two_to_four_seconds() -> void:
	assert_almost_eq(FxSpecs.debris_duration_s(0.0), FxSpecs.DEBRIS_MIN_S, 1e-6)
	assert_almost_eq(FxSpecs.debris_duration_s(1.0), FxSpecs.DEBRIS_MAX_S, 1e-6)
	assert_eq(FxSpecs.DEBRIS_MIN_S, 2.0)
	assert_eq(FxSpecs.DEBRIS_MAX_S, 4.0)
	assert_almost_eq(FxSpecs.debris_duration_s(7.0), FxSpecs.DEBRIS_MAX_S, 1e-6, "out of range is capped")


func test_debris_venting_ends_well_before_its_chunk_does() -> void:
	var worst: float = FxSpecs.busy_s(FxSpecs.DEBRIS, FxSpecs.DEBRIS_MAX_S)
	assert_lt(worst, DebrisChunk.LIFETIME_S, "the emitter is free again before the chunk is")


func test_busy_time_of_one_shot_and_continuous_effects() -> void:
	var hit_life: float = float(FxSpecs.spec(FxSpecs.HIT)["lifetime_s"])
	assert_almost_eq(FxSpecs.busy_s(FxSpecs.HIT, 0.0), hit_life, 1e-6, "a one-shot is busy for its particle lifetime")
	var vent_life: float = float(FxSpecs.spec(FxSpecs.DEBRIS)["lifetime_s"])
	assert_almost_eq(FxSpecs.busy_s(FxSpecs.DEBRIS, 3.0), 3.0 + vent_life, 1e-6, "a vent is busy for its duration plus the tail")


func test_every_process_material_is_newtonian() -> void:
	# AC32 / architecture 5.4: no gravity and no damping, so a spark flies straight at the speed it was thrown.
	for effect: int in FxSpecs.COUNT:
		var spec: Dictionary = FxSpecs.spec(effect)
		var material := load(String(spec["material"])) as ParticleProcessMaterial
		assert_not_null(material, "%s loads" % spec["name"])
		if material == null:
			continue
		assert_eq(material.gravity, Vector3.ZERO, "%s: no gravity" % spec["name"])
		assert_eq(material.damping_min, 0.0, "%s: no damping" % spec["name"])
		assert_eq(material.damping_max, 0.0, "%s: no damping" % spec["name"])
		assert_eq(material.linear_accel_min, 0.0)
		assert_eq(material.linear_accel_max, 0.0)
		assert_eq(material.radial_accel_max, 0.0)
		assert_eq(material.tangential_accel_max, 0.0)
		assert_eq(material.initial_velocity_min, (spec["speed_mps"] as Vector2).x, "%s: spec speed" % spec["name"])
		assert_eq(material.initial_velocity_max, (spec["speed_mps"] as Vector2).y, "%s: spec speed" % spec["name"])
		assert_eq(material.spread, float(spec["spread_deg"]), "%s: spec spread" % spec["name"])
