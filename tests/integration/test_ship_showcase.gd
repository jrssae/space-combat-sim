extends TestSteps
## The ship line-up beside Babylon 5 (M10-T64): `ship_showcase` parks every finalized hull, one row per faction, held still
## (an idle brain on the brakes for ships, a holding helm for capitals), at peace with the player. Skips, saying why, when a
## hull's asset is not generated.

const SHOWCASE: String = "res://data/scenarios/ship_showcase.json"
## Seconds the line-up is watched, as sim time at a raised step rate.
const WATCH_S: float = 60.0
const SPEED_UP: float = 4.0
## Most a held hull may stray, m. A capital's rotor turns about its own pivot, so the hull origin must not move at all.
const HELD_M: float = 0.5

var _rate_backup: int = 60
var _scale_backup: float = 1.0


func before_each() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	get_tree().paused = false


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


func _skipped() -> bool:
	for type: StringName in ShipCatalog.data().finalized_ids():
		var dir: String = "res://assets/generated/%s/manifest.json" % ShipCatalog.entry_text(type, "asset")
		if not FileAccess.file_exists(dir):
			pending("%s is not generated (scripts/gen_assets.sh)" % type)
			return true
	return false


func _line_up() -> Main:
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SHOWCASE
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	return main


# Where every held body stands in universe terms (a rebase moves the scene, not the line-up), by node.
func _stands(main: Main) -> Dictionary:
	var out: Dictionary = {}
	for c: Combatant in main.scenario_ships:
		out[c.ship] = main.world.to_universe(c.ship.global_position)
	for cap: CapitalBody in main.scenario_capitals:
		out[cap] = main.world.to_universe(cap.global_position)
	return out


func test_the_catalogue_flags_what_the_line_up_must_hold() -> void:
	var finalized: Array[StringName] = ShipCatalog.data().finalized_ids()
	for type: StringName in [&"ea_omega", &"ea_nova", &"ea_hyperion", &"raider_strike_carrier", &"saturn_3_freighter", &"ea_panama"]:
		assert_has(finalized, type, "%s is finalized" % type)
	assert_does_not_have(finalized, &"capital_test_cruiser", "the test cruiser is not a finished hull")


func test_every_finalized_hull_is_in_the_line_up() -> void:
	if _skipped():
		return
	var main: Main = await _line_up()
	var present: Dictionary = {}
	for c: Combatant in main.scenario_ships:
		present[main.ships.type_of(c)] = true
	for cap: CapitalBody in main.scenario_capitals:
		present[cap.get_meta(&"line_up_type")] = true
	for type: StringName in ShipCatalog.data().finalized_ids():
		assert_true(present.has(type), "%s is parked in the line-up (add it to data/scenarios/ship_showcase.json)" % type)


func test_the_big_hulls_never_overlap_and_each_ship_has_a_name() -> void:
	if _skipped():
		return
	var main: Main = await _line_up()
	var caps: Array[CapitalBody] = main.scenario_capitals
	assert_gte(caps.size(), 4, "the carrier, Omega, Nova and Hyperion")
	for i: int in caps.size():
		assert_false(caps[i].targetable.display_name.is_empty(), "%s has a contact name" % caps[i].get_meta(&"line_up_type"))
		for j: int in range(i + 1, caps.size()):
			# Their boxes must not meet: the gap along the row is more than the two halves' lengths.
			var gap: float = caps[i].global_position.distance_to(caps[j].global_position)
			var reach: float = caps[i].half_extents().z + caps[j].half_extents().z
			assert_gt(gap, reach, "%s and %s do not overlap" % [caps[i].get_meta(&"line_up_type"), caps[j].get_meta(&"line_up_type")])
	for c: Combatant in main.scenario_ships:
		assert_false(c.display_name.is_empty(), "%s has a contact name" % main.ships.type_of(c))
		assert_false(c.targetable == null, "%s can be targeted by name" % c.display_name)


func test_the_line_up_holds_still_and_nothing_fires_for_a_minute() -> void:
	if _skipped():
		return
	var main: Main = await _line_up()
	var hits: Array[String] = []
	for node: Node in get_tree().get_nodes_in_group("damageable"):
		var damageable := node as Damageable
		if damageable != null:
			damageable.hit_taken.connect(func(_info: HitInfo) -> void: hits.append(str(node.get_path())))
	var before: Dictionary = _stands(main)
	assert_gt(before.size(), 20, "the whole line-up is in play")
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < WATCH_S:
		await get_tree().physics_frame
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	var after: Dictionary = _stands(main)
	var worst: float = 0.0
	for node: Node in before:
		var a: UniversePos = before[node]
		var b: UniversePos = after[node]
		var moved: float = Vector3(b.x - a.x, b.y - a.y, b.z - a.z).length()
		worst = maxf(worst, moved)
		assert_lt(moved, HELD_M, "%s stays where it was parked (%.2f m)" % [node.name, moved])
	gut.p("line-up of %d hulls: the worst drift in %.0f s is %.3f m, %d hits" % [before.size(), WATCH_S, worst, hits.size()])
	assert_true(hits.is_empty(), "nothing fires in the line-up: %s" % [hits])
