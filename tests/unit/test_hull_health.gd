extends GutTest
## HullHealth (architecture §15.4, AC1): points removed, clamped at zero, and `destroyed` reported exactly once.

const EPS: float = 1e-9

var hull: HullHealth


func before_each() -> void:
	hull = HullHealth.new(60.0)


func test_starts_full_and_intact() -> void:
	assert_eq(hull.max_hp, 60.0)
	assert_eq(hull.hp, 60.0)
	assert_false(hull.destroyed)
	assert_false(hull.destroyed_now)
	assert_eq(hull.fraction(), 1.0)


func test_apply_returns_what_it_removed() -> void:
	assert_eq(hull.apply(6.0), 6.0)
	assert_almost_eq(hull.hp, 54.0, EPS)
	assert_almost_eq(hull.fraction(), 0.9, EPS)
	assert_false(hull.destroyed)
	assert_false(hull.destroyed_now)


func test_six_hits_of_ten_destroy_a_sixty_point_hull_exactly_once() -> void:
	var destroyed_reports: int = 0
	var removed: float = 0.0
	for hit: int in 20:
		removed += hull.apply(10.0)
		if hull.destroyed_now:
			destroyed_reports += 1
			assert_eq(hit, 5, "the sixth hit crosses zero")
	assert_eq(destroyed_reports, 1)
	assert_almost_eq(removed, 60.0, EPS, "later hits apply nothing")
	assert_true(hull.destroyed)
	assert_eq(hull.hp, 0.0)
	assert_eq(hull.fraction(), 0.0)


func test_the_crossing_hit_applies_only_what_is_left() -> void:
	hull.apply(55.0)
	assert_almost_eq(hull.apply(10.0), 5.0, EPS)
	assert_eq(hull.hp, 0.0, "clamped at zero, never negative")
	assert_true(hull.destroyed)
	assert_true(hull.destroyed_now)


func test_a_hit_for_exactly_the_remaining_points_destroys() -> void:
	assert_eq(hull.apply(60.0), 60.0)
	assert_true(hull.destroyed)
	assert_true(hull.destroyed_now)


func test_destroyed_now_lasts_for_one_apply_call() -> void:
	hull.apply(100.0)
	assert_true(hull.destroyed_now)
	assert_eq(hull.apply(10.0), 0.0, "a dead hull takes nothing")
	assert_false(hull.destroyed_now)
	assert_true(hull.destroyed, "destroyed stays")
	assert_eq(hull.apply(10.0), 0.0)
	assert_false(hull.destroyed_now)


func test_overkill_and_infinite_damage_destroy_once() -> void:
	assert_eq(hull.apply(INF), 60.0)
	assert_true(hull.destroyed_now)
	assert_eq(hull.apply(INF), 0.0)
	assert_false(hull.destroyed_now)


func test_negative_zero_and_nan_amounts_apply_nothing() -> void:
	for amount: float in [-5.0, -INF, 0.0, NAN]:
		assert_eq(hull.apply(amount), 0.0, "amount %s" % amount)
		assert_eq(hull.hp, 60.0, "amount %s leaves the hull alone" % amount)
		assert_false(hull.destroyed)
		assert_false(hull.destroyed_now)


func test_a_harmless_apply_clears_destroyed_now() -> void:
	# destroyed_now describes the latest apply only: a zero-damage call after the fatal one does not repeat it.
	hull.apply(60.0)
	assert_true(hull.destroyed_now)
	hull.apply(0.0)
	assert_false(hull.destroyed_now)


func test_restore_refills_and_allows_one_more_death() -> void:
	hull.apply(60.0)
	hull.restore()
	assert_eq(hull.hp, 60.0)
	assert_false(hull.destroyed)
	assert_false(hull.destroyed_now)
	assert_eq(hull.fraction(), 1.0)
	var reports: int = 0
	for hit: int in 8:
		hull.apply(10.0)
		if hull.destroyed_now:
			reports += 1
	assert_eq(reports, 1, "a restored hull dies exactly once again")


func test_restore_on_a_damaged_living_hull_tops_it_up() -> void:
	hull.apply(25.0)
	hull.restore()
	assert_eq(hull.hp, 60.0)


func test_restore_clears_destroyed_now_too() -> void:
	hull.apply(60.0)
	assert_true(hull.destroyed_now)
	hull.restore()
	assert_false(hull.destroyed_now)


func test_fraction_tracks_hp() -> void:
	hull.apply(15.0)
	assert_almost_eq(hull.fraction(), 0.75, EPS)
	hull.apply(30.0)
	assert_almost_eq(hull.fraction(), 0.25, EPS)


func test_fraction_is_clamped_if_hp_is_set_out_of_range() -> void:
	hull.hp = 90.0
	assert_eq(hull.fraction(), 1.0)
	hull.hp = -5.0
	assert_eq(hull.fraction(), 0.0)


func test_default_capacity() -> void:
	var default_hull := HullHealth.new()
	assert_eq(default_hull.max_hp, 100.0)
	assert_eq(default_hull.hp, 100.0)


func test_a_non_positive_or_nan_capacity_is_raised_to_the_minimum() -> void:
	for capacity: float in [0.0, -10.0, NAN]:
		var odd := HullHealth.new(capacity)
		assert_eq(odd.max_hp, HullHealth.MIN_MAX_HP, "capacity %s" % capacity)
		assert_eq(odd.hp, odd.max_hp)
		assert_eq(odd.fraction(), 1.0)
		assert_true(is_finite(odd.fraction()))
		odd.apply(1.0)
		assert_true(odd.destroyed_now)
