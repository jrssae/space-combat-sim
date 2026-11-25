extends GutTest
## `StationDamage` (M10-T65, Q72), pure: the capitals' rules on a station's own ledgers. A grid mount hit takes it in full and the
## hull half, the command (bridge) and reactor sections are subsystems too, any other hit is hull damage off its section and the
## total, a lost section's hits go to the total; the reactor or the hull at 0 destroys it (a hulk or not), the command at 0, the
## reactor at a tenth (Q78) or the hull below a tenth leaves a hulk. Three sections of 1 000 points side by side on the frame, one light gun on the cargo section.

var _disabled: int = 0
var _destroyed: Array[String] = []


func _model() -> StationDamage:
	var sections := StationSections.new()
	var names: Array[String] = ["command", "cargo", "reactor"]
	for i: int in names.size():
		sections.sections.append({"name": names[i], "body": "frame",
				"aabb": AABB(Vector3(100.0 * i, -20.0, -20.0), Vector3(100.0, 40.0, 40.0))})
		sections.max_health.append(1000.0)
	sections.health = sections.max_health.duplicate()
	var mounts: GridMountHealth = GridMountHealth.from_mounts([
		{"name": "L1", "kind": "light_pulse", "body": "frame", "position": Vector3(150.0, 20.0, 0.0)},
	] as Array[Dictionary], func(k: String) -> int: return StationGrid.KIND_OF.get(k, 1))
	var d: StationDamage = StationDamage.make(sections, mounts, {"command": "bridge", "reactor": "reactor"})
	_disabled = 0
	_destroyed.clear()
	d.disabled.connect(func() -> void: _disabled += 1)
	d.destroyed.connect(func(s: String) -> void: _destroyed.append(s))
	return d


func test_the_hull_is_the_sections_together() -> void:
	var d: StationDamage = _model()
	assert_eq(d.hull_max, 3000.0)
	assert_eq(d.kinds, PackedStringArray(["bridge", "structure", "reactor"]))
	assert_true(d.has_power())


func test_a_grid_mount_hit_takes_it_in_full_and_the_hull_half() -> void:
	var d: StationDamage = _model()
	assert_almost_eq(d.hit("frame", Vector3(150.0, 15.0, 0.0), 100.0), 50.0, 1e-6)
	assert_eq(d.mounts.health[0], 200.0, "the mount all of it")
	assert_eq(d.sections.health[1], 1000.0, "its section none")
	assert_almost_eq(d.hull_hp, 2950.0, 1e-6)


func test_a_hull_hit_lowers_its_section_and_the_total_and_a_lost_sections_hits_the_total() -> void:
	var d: StationDamage = _model()
	assert_eq(d.hit("frame", Vector3(110.0, 0.0, 0.0), 1000.0), 1000.0)
	assert_true(d.sections.is_lost(1))
	assert_eq(d.hit("frame", Vector3(110.0, 0.0, 0.0), 200.0), 200.0, "on the lost section: the total")
	assert_eq(d.hull_hp, 1800.0)
	assert_eq(d.sections.health[0], 1000.0, "no neighbour takes any")
	assert_true(d.has_power(), "a lost hull section leaves it fighting")


func test_the_command_section_is_its_bridge_and_at_zero_a_hulk() -> void:
	var d: StationDamage = _model()
	assert_almost_eq(d.hit("frame", Vector3(50.0, 0.0, 0.0), 400.0), 200.0, 1e-6, "the bridge in full, the hull half")
	assert_eq(d.sections.health[0], 600.0)
	d.hit_section(0, 600.0)
	assert_true(d.is_disabled, "a hulk")
	assert_false(d.has_power())
	assert_eq(_disabled, 1)
	assert_false(d.is_destroyed)


func test_the_reactor_at_zero_destroys_it() -> void:
	var d: StationDamage = _model()
	d.hit("frame", Vector3(250.0, 0.0, 0.0), 1000.0)
	assert_true(d.is_destroyed, "from whole to 0 in one hit: destroyed, no hulk first")
	assert_eq(_disabled, 0)
	assert_eq(d.blown, "reactor")
	assert_eq(_destroyed, ["reactor"] as Array[String])
	assert_eq(d.hull_hp, 0.0)
	assert_eq(d.hit("frame", Vector3(110.0, 0.0, 0.0), 10.0), 0.0, "a wreck takes nothing more")


func test_the_reactor_at_a_tenth_leaves_a_hulk_and_at_zero_still_destroys_it() -> void:
	var d: StationDamage = _model()
	d.hit_section(2, 890.0)
	assert_false(d.is_disabled, "110 of 1 000 points: still above a tenth")
	d.hit_section(2, 15.0)
	assert_true(d.is_disabled, "95 of 1 000: the reactor shuts down (Q78)")
	assert_false(d.has_power())
	assert_eq(_disabled, 1)
	assert_false(d.is_destroyed)
	d.hit_section(2, 50.0)
	assert_eq(_disabled, 1, "once")
	d.hit_section(2, 45.0)
	assert_true(d.is_destroyed, "the hulk's reactor at 0 still destroys it")
	assert_eq(_destroyed, ["reactor"] as Array[String])


func test_the_hull_below_a_tenth_is_a_hulk_and_at_zero_destroyed() -> void:
	var d: StationDamage = _model()
	d.hit_section(1, 2600.0)  # the cargo section and the rest off the total
	assert_almost_eq(d.hull_fraction(), 400.0 / 3000.0, 1e-6)
	assert_false(d.is_disabled)
	d.hit_section(1, 150.0)
	assert_true(d.is_disabled, "below 10 %")
	d.hit_section(1, 250.0)
	assert_true(d.is_destroyed, "the hull ran out")
	assert_eq(_destroyed, [""] as Array[String])
	assert_eq(d.describe(), "destroyed (hull gone), hull 0/3000")


func test_restore_makes_it_whole_with_power() -> void:
	var d: StationDamage = _model()
	d.hit_section(0, 1000.0)
	d.restore()
	assert_true(d.has_power())
	assert_eq(d.hull_hp, d.hull_max)
	assert_eq(d.sections.health[0], 1000.0)
