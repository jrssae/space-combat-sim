extends GutTest
## The focus pull's amount over time (architecture §18.21, M5-T44).


func test_rest_is_sharp_and_at_rest() -> void:
	var pull := FocusPull.new()
	pull.advance(1.0)
	assert_eq(pull.amount(), 0.0)
	assert_true(pull.at_rest())


func test_open_reaches_full_in_the_duration() -> void:
	var pull := FocusPull.new()
	pull.set_open(true)
	pull.advance(FocusPull.DURATION_S * 0.5)
	assert_almost_eq(pull.amount(), 0.5, 0.001, "smoothstep is half way at half time")
	assert_false(pull.at_rest())
	pull.advance(FocusPull.DURATION_S * 0.5)
	assert_eq(pull.amount(), 1.0)
	pull.advance(5.0)
	assert_eq(pull.amount(), 1.0, "it stays at full")


func test_close_returns_in_the_duration() -> void:
	var pull := FocusPull.new()
	pull.set_open(true)
	pull.advance(1.0)
	pull.set_open(false)
	pull.advance(FocusPull.DURATION_S * 0.999)
	assert_false(pull.at_rest())
	pull.advance(FocusPull.DURATION_S)
	assert_eq(pull.amount(), 0.0)
	assert_true(pull.at_rest())


func test_reversal_starts_from_where_it_is() -> void:
	var pull := FocusPull.new()
	pull.set_open(true)
	pull.advance(FocusPull.DURATION_S * 0.25)
	var before: float = pull.amount()
	pull.set_open(false)
	assert_eq(pull.amount(), before, "no jump on the reversal")
	pull.advance(FocusPull.DURATION_S * 0.25)
	assert_almost_eq(pull.amount(), 0.0, 0.001, "it takes the same time back as it went")


func test_a_negative_step_changes_nothing() -> void:
	var pull := FocusPull.new()
	pull.set_open(true)
	pull.advance(-1.0)
	assert_eq(pull.amount(), 0.0)
