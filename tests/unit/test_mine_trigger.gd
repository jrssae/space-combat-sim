extends GutTest
## The proximity mine stand-in's trigger and blast (M4-T12, Q21), pure: a mine goes off on a hull hostile to its layer whose
## sphere comes inside the trigger radius, never on a friendly or a neutral one, and its blast reaches every hull whose sphere
## lies within the blast radius, friend or foe. The trigger query runs through the hit sweep's grid, native or GDScript, with
## the same answer.

const EA: StringName = Factions.EARTH_ALLIANCE
const RAIDERS: StringName = Factions.RAIDERS


func after_each() -> void:
	Factions.reset()


func _triggers(mines: Array[Vector3], mine_factions: Array[StringName], hulls: Array[Vector3], reach: Array[float],
		hull_factions: Array[StringName], use_native: bool = true) -> PackedInt32Array:
	var broad := HitBroadPhase.new()
	broad.use_native = use_native
	var reach_packed := PackedFloat64Array()
	for r: float in reach:
		reach_packed.append(r)
	return MineStandin.triggers(PackedVector3Array(mines), mine_factions, PackedVector3Array(hulls), reach_packed, hull_factions,
			broad)


func test_a_hostile_inside_the_trigger_sets_a_mine_off() -> void:
	var got: PackedInt32Array = _triggers([Vector3.ZERO], [EA], [Vector3(0.0, 0.0, 40.0)], [5.0], [RAIDERS])
	assert_eq(got, PackedInt32Array([0]), "hull 0 is the trigger")


func test_a_friendly_or_neutral_never_does() -> void:
	var got: PackedInt32Array = _triggers([Vector3.ZERO], [EA], [Vector3(0.0, 0.0, 10.0), Vector3(10.0, 0.0, 0.0)], [5.0, 5.0],
			[EA, Factions.NEUTRAL])
	assert_eq(got, PackedInt32Array([-1]))


func test_a_hostile_outside_the_trigger_does_not() -> void:
	var outside: float = MineStandin.TRIGGER_RADIUS_M + 5.0 + 1.0
	var got: PackedInt32Array = _triggers([Vector3.ZERO], [EA], [Vector3(outside, 0.0, 0.0)], [5.0], [RAIDERS])
	assert_eq(got, PackedInt32Array([-1]))


func test_a_capitals_hull_counts_from_its_surface() -> void:
	# A cruiser's centre 300 m off, its hull sphere reaching to 280 m: well inside the 50 m trigger.
	var got: PackedInt32Array = _triggers([Vector3.ZERO], [RAIDERS], [Vector3(300.0, 0.0, 0.0)], [280.0], [EA])
	assert_eq(got, PackedInt32Array([0]))


func test_each_mine_answers_for_itself_and_both_paths_agree() -> void:
	var mines: Array[Vector3] = []
	var mine_factions: Array[StringName] = []
	var hulls: Array[Vector3] = []
	var reach: Array[float] = []
	var hull_factions: Array[StringName] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i: int in 200:
		mines.append(Vector3(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-300.0, 300.0), rng.randf_range(-3000.0, 3000.0)))
		mine_factions.append(EA if i % 2 == 0 else RAIDERS)
	for j: int in 150:
		hulls.append(Vector3(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-300.0, 300.0), rng.randf_range(-3000.0, 3000.0)))
		reach.append(5.0 if j % 10 != 0 else 300.0)
		hull_factions.append(RAIDERS if j % 3 == 0 else EA)
	var native: PackedInt32Array = _triggers(mines, mine_factions, hulls, reach, hull_factions, true)
	var script: PackedInt32Array = _triggers(mines, mine_factions, hulls, reach, hull_factions, false)
	assert_eq(native, script, "the same triggers on both paths")
	# Against the plain definition, every mine against every hull.
	var fired: int = 0
	for i: int in mines.size():
		var expected: int = -1
		for j: int in hulls.size():
			if Factions.is_hostile(mine_factions[i], hull_factions[j]) \
					and mines[i].distance_to(hulls[j]) <= MineStandin.TRIGGER_RADIUS_M + reach[j]:
				expected = j
				break
		assert_eq(script[i], expected, "mine %d" % i)
		fired += 1 if expected >= 0 else 0
	assert_gt(fired, 0, "the crowd sets some off")


func test_the_blast_reaches_every_hull_within_its_radius_friend_or_foe() -> void:
	var hulls := PackedVector3Array([Vector3(0.0, 0.0, 60.0), Vector3(90.0, 0.0, 0.0), Vector3(0.0, 120.0, 0.0),
			Vector3(0.0, 0.0, -500.0)])
	var reach := PackedFloat64Array([5.0, 5.0, 30.0, 5.0])
	var got: PackedInt32Array = MineStandin.blast(Vector3.ZERO, hulls, reach)
	assert_eq(got, PackedInt32Array([0, 1, 2]), "inside 100 m of their spheres; the far one is not")
