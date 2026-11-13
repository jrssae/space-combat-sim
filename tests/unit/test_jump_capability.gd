extends GutTest
## Who may open a jump point (M6-T23, `JumpCapability`): no designed hull can, every capital stand-in can; a point holds within
## twice its opener's length by default (or its type's own range), and collapses when its opener is gone, destroyed, disabled or
## out of range, or a short hold after the opener went through its own ring. A collapse goes straight to the closing flash.

const SHIPS_DIR: String = "res://assets/ships/"


func test_no_designed_hull_can_open_a_jump_point() -> void:
	var specs: int = 0
	for file: String in DirAccess.get_files_at(SHIPS_DIR):
		if not file.ends_with(".tres"):
			continue
		var spec := load(SHIPS_DIR + file) as ShipSpec
		if spec == null:
			continue
		specs += 1
		assert_false(spec.can_open_jump_point, "%s cannot open a jump point" % file)
		assert_eq(spec.jump_hold_range_m, 0.0, "%s gives no hold range of its own" % file)
	assert_gte(specs, 12, "the Starfuries, the raider and the nine civilian hulls")


func test_every_capital_stand_in_can_and_holds_within_twice_its_length() -> void:
	for cls: StringName in CapitalStandin.CLASSES:
		var cap: CapitalStandin = CapitalStandin.create(cls, Factions.RAIDERS, "TEST", Vector3.ZERO)
		assert_true(JumpCapability.can_open(cap), "a %s stand-in opens points" % cls)
		assert_almost_eq(JumpCapability.hold_range_of(cap), 2.0 * cap.length_m(), 1e-3, "%s: 2 x its length" % cls)
		assert_almost_eq(JumpCapability.length_of(cap), cap.length_m(), 1e-3)
		cap.free()
	assert_false(JumpCapability.can_open(null))
	assert_false(JumpCapability.can_open(autofree(Node3D.new()) as Node3D), "a plain node cannot")


func test_the_hold_range_is_twice_the_length_unless_the_type_gives_one() -> void:
	assert_eq(JumpCapability.hold_range_m(300.0), 600.0)
	assert_eq(JumpCapability.hold_range_m(1200.0), 2400.0)
	assert_eq(JumpCapability.hold_range_m(300.0, 450.0), 450.0, "the type's own value wins")
	assert_eq(JumpCapability.hold_range_m(-5.0), 0.0)


func test_a_point_holds_until_its_opener_is_lost() -> void:
	var holds: StringName = JumpCapability.HOLDS
	assert_eq(JumpCapability.verdict(true, false, false, 599.0, 600.0), holds, "within range")
	assert_eq(JumpCapability.verdict(true, false, false, 600.0, 600.0), holds, "at the range")
	assert_eq(JumpCapability.verdict(true, false, false, 601.0, 600.0), JumpCapability.OUT_OF_RANGE)
	assert_eq(JumpCapability.verdict(true, true, false, 10.0, 600.0), JumpCapability.DESTROYED)
	assert_eq(JumpCapability.verdict(true, false, true, 10.0, 600.0), JumpCapability.DISABLED)
	assert_eq(JumpCapability.verdict(false, false, false, 0.0, 600.0), JumpCapability.GONE)


func test_an_opener_gone_through_its_own_point_holds_it_a_moment_more() -> void:
	var hold: float = JumpCapability.OWN_DEPARTURE_HOLD_S
	assert_between(hold, 2.0, 5.0, "a few seconds")
	assert_eq(JumpCapability.verdict(false, false, false, 0.0, 600.0, 0.0), JumpCapability.HOLDS, "just through: gone, yet held")
	assert_eq(JumpCapability.verdict(false, false, false, 0.0, 600.0, hold - 0.01), JumpCapability.HOLDS)
	assert_eq(JumpCapability.verdict(false, false, false, 0.0, 600.0, hold), JumpCapability.OPENER_THROUGH)
	assert_eq(JumpCapability.verdict(true, false, false, 5000.0, 600.0, 1.0), JumpCapability.HOLDS,
			"its range no longer counts once it is through")


func test_a_collapse_goes_straight_to_the_closing_flash() -> void:
	var timing := VortexTiming.new()
	var at: float = timing.open_at_s + 1.0
	assert_eq(timing.phase(at), VortexTiming.Phase.OPEN)
	timing.collapse_now(at)
	assert_true(timing.collapsed)
	assert_eq(timing.phase(at), VortexTiming.Phase.END_FLASH, "no fold: the flash at once")
	assert_almost_eq(timing.flash(at), 1.0, 1e-4, "at its peak")
	assert_eq(timing.growth(at), 0.0, "the funnel gone")
	assert_false(timing.is_open(at))
	timing.extend(at, 10.0)
	assert_almost_eq(timing.done_at_s(), at + VortexTiming.END_FLASH_S, 1e-4, "nothing keeps it open")
	assert_eq(timing.phase(at + VortexTiming.END_FLASH_S), VortexTiming.Phase.CLOSED)
	var early := VortexTiming.new()
	early.collapse_now(0.4)
	assert_eq(early.phase(0.4), VortexTiming.Phase.END_FLASH, "even in its opening flash")
	early.reset()
	assert_false(early.collapsed, "a new opening starts whole")
	assert_eq(early.phase(0.4), VortexTiming.Phase.FLASH)
