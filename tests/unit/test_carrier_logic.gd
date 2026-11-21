extends GutTest
## The strike carrier's pure logic (M12-T19): the compound collision read from a manifest (`CompoundCollision`), the cradles'
## bookkeeping (`CarrierCradles`), the carrier's decisions (`CarrierTactics`) and the native docking rows (`ScsDockRows`).

const IDENTITY_BASIS: Dictionary = {"x": [1.0, 0.0, 0.0], "y": [0.0, 1.0, 0.0], "z": [0.0, 0.0, 1.0]}
const SLAB: Dictionary = {"name": "slab", "type": "box", "position": [0.0, 1.0, 2.0], "size": [4.0, 2.0, 6.0], "basis": IDENTITY_BASIS}
const ARM: Dictionary = {"name": "arm", "type": "capsule", "position": [5.0, 0.0, 0.0], "radius": 0.5, "height": 4.0, "axis": "z",
		"basis": {"x": [0.0, 1.0, 0.0], "y": [0.0, 0.0, 1.0], "z": [1.0, 0.0, 0.0]}}
## The manifest's `collision` section as `core/collision.py` writes it (M7's format, M8-T07): per piece its bounds, its shapes
## and a hit volume for each shape.
const SECTION: Dictionary = {
	"max_shapes": 64, "max_hull_points": 32,
	"pieces": [
		{"name": "core", "aabb_min": [-2.0, -0.5, -1.0], "aabb_max": [7.0, 2.0, 5.0], "bound": {"center": [2.5, 0.75, 2.0], "radius": 6.0},
				"shapes": [SLAB, ARM], "hit_volumes": [SLAB, ARM]},
		{"name": "ring", "aabb_min": [-1.0, 9.0, -1.0], "aabb_max": [1.0, 11.0, 1.0], "bound": {"center": [0.0, 10.0, 0.0], "radius": 1.8},
				"shapes": [{"name": "sector", "type": "hull",
						"points": [[-1.0, 9.0, -1.0], [1.0, 9.0, -1.0], [1.0, 11.0, -1.0], [-1.0, 11.0, -1.0], [0.0, 10.0, 1.0]]}],
				"hit_volumes": [{"name": "sector", "type": "box", "position": [0.0, 10.0, 0.0], "size": [2.0, 2.0, 2.0], "basis": IDENTITY_BASIS}]},
	],
}

const CRADLES: Array = [
	{"name": "top", "position": [0.0, 40.0, 10.0], "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0], "approach_from": [0.0, 100.0, 10.0]},
	{"name": "side_r", "position": [40.0, 0.0, 10.0], "forward": [0.0, 0.0, -1.0], "up": [1.0, 0.0, 0.0], "approach_from": [100.0, 0.0, 10.0]},
	{"name": "no_position"},
]


# --- the compound collision -------------------------------------------------------------------------------------------


func test_solids_are_jolts_shapes_piece_by_piece() -> void:
	var solids: Array[Dictionary] = CompoundCollision.solids(SECTION)
	assert_eq(solids.size(), 3)
	assert_eq(CompoundCollision.piece_names(SECTION), PackedStringArray(["core", "ring"]))
	assert_true(solids[0]["shape"] is BoxShape3D)
	assert_eq((solids[0]["shape"] as BoxShape3D).size, Vector3(4.0, 2.0, 6.0))
	assert_eq((solids[0]["transform"] as Transform3D).origin, Vector3(0.0, 1.0, 2.0))
	assert_eq(solids[0]["piece"], "core")
	var capsule: CapsuleShape3D = solids[1]["shape"]
	assert_almost_eq(capsule.height, 4.0, 1e-6)
	# Its length (Godot's +Y) lies along the entry's local z, which the basis turns onto World +X.
	assert_almost_eq(((solids[1]["transform"] as Transform3D).basis.y - Vector3.RIGHT).length(), 0.0, 1e-5)
	assert_true(solids[2]["shape"] is ConvexPolygonShape3D, "a hull collides as itself")
	assert_eq((solids[2]["shape"] as ConvexPolygonShape3D).points.size(), 5)
	assert_eq(solids[2]["piece"], "ring")


func test_hit_volumes_are_boxes_and_capsules_only() -> void:
	var volumes: Array[Dictionary] = CompoundCollision.hit_volumes(SECTION)
	assert_eq(volumes.size(), 3)
	for volume: Dictionary in volumes:
		assert_not_null(HitShape.from_collision(volume), "%s is a hit shape" % volume["name"])
	assert_true(volumes[2]["shape"] is BoxShape3D, "a hull is hit as its bounding box")
	assert_eq(volumes[2]["name"], "sector")
	assert_eq((volumes[2]["transform"] as Transform3D).origin, Vector3(0.0, 10.0, 0.0))
	assert_eq(CompoundCollision.solids({}).size(), 0, "no section, no shapes")


func test_a_broken_section_gives_no_shapes() -> void:
	var broken: Dictionary = SECTION.duplicate(true)
	(broken["pieces"][1]["shapes"] as Array).append({"name": "broken", "type": "hull", "points": [[0.0, 0.0, 0.0]]})
	assert_eq(CompoundCollision.solids(broken).size(), 0, "the caller falls back to its plain box")
	assert_eq(CompoundCollision.hit_volumes(broken).size(), 0)
	assert_eq(CompoundCollision.piece_names(broken).size(), 0)


# --- the cradles ------------------------------------------------------------------------------------------------------


func test_cradles_are_read_from_the_hardpoints() -> void:
	var cradles: CarrierCradles = CarrierCradles.from_hardpoints(CRADLES)
	assert_eq(cradles.count(), 2, "an entry without a position is skipped")
	assert_eq(cradles.names[1], "side_r")
	assert_almost_eq(cradles.approach_m[0], 60.0, 1e-4)
	assert_almost_eq((cradles.bases[1].y - Vector3.RIGHT).length(), 0.0, 1e-5, "the fighter's back points out")
	assert_almost_eq((cradles.bases[1].z - Vector3.BACK).length(), 0.0, 1e-5, "its nose to the carrier's bow")
	assert_almost_eq((cradles.approach_point(1) - Vector3(100.0, 0.0, 10.0)).length(), 0.0, 1e-4)
	var rest: Vector3 = CarrierCradles.rest_point(AABB(Vector3(-8.5, -0.8, -4.3), Vector3(17.0, 2.0, 7.2)), 0.05)
	assert_almost_eq((rest - Vector3(0.0, -0.85, -0.7)).length(), 0.0, 1e-5)
	var docked: Transform3D = cradles.docked_transform(0, rest)
	assert_almost_eq((docked * rest - Vector3(0.0, 40.0, 10.0)).length(), 0.0, 1e-5, "its resting point is on the pad")


func test_cradles_track_who_is_where() -> void:
	var cradles: CarrierCradles = CarrierCradles.from_hardpoints(CRADLES)
	assert_eq(cradles.count_in(CarrierCradles.State.FREE), 2)
	assert_eq(cradles.nearest_free(Vector3(500.0, 0.0, 0.0)), 1, "the cradle on its side")
	cradles.set_state(1, CarrierCradles.State.BUSY)
	assert_eq(cradles.nearest_free(Vector3(500.0, 0.0, 0.0)), 0, "the next free one")
	cradles.set_state(0, CarrierCradles.State.DOCKED)
	assert_eq(cradles.nearest_free(Vector3.ZERO), -1)
	assert_eq(cradles.first_in(CarrierCradles.State.DOCKED), 0)
	assert_eq(cradles.count_in(CarrierCradles.State.BUSY), 1)
	cradles.set_state(7, CarrierCradles.State.FREE)  # out of range: ignored
	assert_eq(cradles.count_in(CarrierCradles.State.FREE), 0)


# --- the carrier's decisions ------------------------------------------------------------------------------------------


func test_options_fill_in_and_stay_in_range() -> void:
	var o: Dictionary = CarrierTactics.options({"arrival": "docked", "retreat_hull": 7.0, "wait_s": -3.0, "class": "cruiser"})
	assert_eq(o["arrival"], "docked")
	assert_eq(o["retreat_hull"], 1.0)
	assert_eq(o["wait_s"], 0.0)
	assert_eq(o["standoff_m"], 2500.0, "the default")
	assert_eq(o["class"], "cruiser", "other keys are kept")
	assert_eq(CarrierTactics.options({"arrival": "sideways"})["arrival"], "beside", "anything else is beside")


func test_a_raids_options_lie_over_its_factions_doctrine_over_the_defaults() -> void:
	var doctrine: Dictionary = {"recall_left": 5, "wait_s": 20.0}
	var o: Dictionary = CarrierTactics.options({"wait_s": 8.0}, doctrine)
	assert_eq(o["recall_left"], 5, "the doctrine's")
	assert_eq(o["wait_s"], 8.0, "the raid's own wins")
	assert_eq(o["retreat_hull"], 0.5, "the default where neither says")
	assert_eq(CarrierTactics.options({"recall_left": -2})["recall_left"], 0, "kept in range")


func test_the_raiders_doctrine_and_the_jump_drives_are_data() -> void:
	# D83 (maintainer, 2026-11-18): home at 3 left or under 20 % hull, the carrier flees at 50 % damage.
	var raiders: Dictionary = CarrierTactics.options({}, CapitalData.doctrine(Factions.RAIDERS))
	assert_eq(raiders["recall_left"], 3)
	assert_almost_eq(float(raiders["fighter_return_hull"]), 0.2, 1e-6)
	assert_almost_eq(float(raiders["retreat_hull"]), 0.5, 1e-6)
	assert_gt(float(raiders["wait_s"]), 0.0, "a time limit for the ones called home (Q30)")
	assert_gt(float(raiders["flee_mps"]), CarrierJumps.CARRIER_SPEED_MPS, "it runs faster than it cruises")
	assert_eq(CapitalData.doctrine(&"nobody"), {}, "a faction with no doctrine takes the defaults")
	var longest: float = 0.0
	for cls: StringName in CapitalStandin.CLASSES:
		var recharge_s: float = CapitalData.jump_recharge_s(cls)
		assert_gt(recharge_s, 0.0, "%s: its drive needs time after a jump" % cls)
		longest = maxf(longest, recharge_s)
	assert_eq(CapitalData.jump_recharge_s(CapitalStandin.STRIKE_CARRIER), longest, "the raiders' carrier has the longest")
	assert_eq(CapitalData.jump_recharge_s(&"no_such_class"), CapitalData.DEFAULT_RECHARGE_S)


func test_it_hangs_back_from_an_enemy_inside_its_stand_off() -> void:
	assert_eq(CarrierTactics.cruise(Vector3(0.0, 0.0, -4000.0), true, 2500.0, 30.0), Vector3.ZERO, "outside: it holds")
	assert_eq(CarrierTactics.cruise(Vector3.ZERO, false, 2500.0, 30.0), Vector3.ZERO, "no enemy: it holds")
	var away: Vector3 = CarrierTactics.cruise(Vector3(0.0, 0.0, -1500.0), true, 2500.0, 30.0)
	assert_almost_eq((away - Vector3(0.0, 0.0, 30.0)).length(), 0.0, 1e-4, "well inside: away at full speed")
	var easing: Vector3 = CarrierTactics.cruise(Vector3(0.0, 0.0, -2400.0), true, 2500.0, 30.0)
	assert_between(easing.z, 1.0, 29.0, "just inside: it eases off")


func test_it_shows_an_attacker_its_stern() -> void:
	assert_eq(CarrierTactics.heading(Vector3(0.0, 0.0, -4000.0), true, 2500.0), Vector3.ZERO, "outside its stand-off it keeps its heading")
	assert_almost_eq((CarrierTactics.heading(Vector3(1000.0, 0.0, 0.0), true, 2500.0) - Vector3.LEFT).length(), 0.0, 1e-5)
	var rate: Vector3 = CarrierTactics.turn_rate(Vector3.FORWARD, Vector3.LEFT, 0.07)
	assert_almost_eq((rate - Vector3(0.0, 0.07, 0.0)).length(), 0.0, 1e-5, "a turn to port about +Y, at its limit")
	assert_eq(CarrierTactics.turn_rate(Vector3.FORWARD, Vector3.ZERO, 0.07), Vector3.ZERO, "no heading to hold")
	assert_gt(CarrierTactics.turn_rate(Vector3.FORWARD, Vector3.BACK, 0.07).length(), 0.06, "dead astern: it still turns")
	assert_lt(CarrierTactics.turn_rate(Vector3.FORWARD, Vector3(0.01, 0.0, -1.0), 0.07).length(), 0.01, "nearly there: it eases")


func test_its_fighters_go_home_when_three_are_left_or_one_is_badly_hurt() -> void:
	assert_false(CarrierTactics.recall_all(6, 4, 3), "four of six still fight")
	assert_true(CarrierTactics.recall_all(6, 3, 3), "only three of the raid are left (D83)")
	assert_true(CarrierTactics.recall_all(6, 1, 3))
	assert_false(CarrierTactics.recall_all(6, 0, 3), "nobody left to call")
	assert_false(CarrierTactics.recall_all(3, 3, 3), "a raid of three is not called back as it arrives")
	assert_true(CarrierTactics.recall_all(3, 2, 3), "it goes home at its first loss")
	assert_false(CarrierTactics.recall_all(6, 3, 0), "a raid told never to")
	assert_true(CarrierTactics.fighter_goes_home(0.19, 0.2), "under 20 % hull it goes home alone (D83)")
	assert_false(CarrierTactics.fighter_goes_home(0.2, 0.2))
	assert_false(CarrierTactics.fighter_goes_home(0.6, 0.2))


func test_it_flees_at_half_damage_or_when_every_survivor_has_docked() -> void:
	assert_eq(CarrierTactics.flee_reason(0.8, 0.5, false, 6, 4, 1), CarrierTactics.STAYS)
	assert_eq(CarrierTactics.flee_reason(0.51, 0.5, false, 6, 4, 0), CarrierTactics.STAYS)
	assert_eq(CarrierTactics.flee_reason(0.5, 0.5, false, 6, 4, 0), CarrierTactics.FLEE_HURT, "at least 50 % damage (D83)")
	assert_eq(CarrierTactics.flee_reason(1.0, 0.5, false, 6, 0, 2), CarrierTactics.STAYS, "two are still on their way home")
	assert_eq(CarrierTactics.flee_reason(1.0, 0.5, false, 6, 0, 0), CarrierTactics.FLEE_ALL_DOCKED, "every survivor has docked")
	assert_eq(CarrierTactics.flee_reason(1.0, 0.5, false, 0, 0, 0), CarrierTactics.STAYS, "it brought none: nobody to wait for")
	assert_eq(CarrierTactics.flee_reason(1.0, 0.5, true, 6, 4, 0), CarrierTactics.FLEE_RAID_OVER)
	assert_false(CarrierTactics.raid_over(false, 100.0, 0.0), "no time limit")
	assert_true(CarrierTactics.raid_over(false, 100.0, 90.0), "past its time limit")
	assert_true(CarrierTactics.raid_over(true, 1.0, 0.0), "ended by its script")


func test_fleeing_is_a_jump_once_recharged_and_a_run_for_the_gate_until_then() -> void:
	assert_eq(CarrierTactics.flee_move(true, true, 0, 5.0, 45.0), CarrierTactics.MOVE_JUMP, "recharged, all aboard: its own point")
	assert_eq(CarrierTactics.flee_move(true, false, 2, 5.0, 45.0), CarrierTactics.MOVE_WAIT, "recharged: it waits for its fighters")
	assert_eq(CarrierTactics.flee_move(true, false, 2, 45.0, 45.0), CarrierTactics.MOVE_JUMP, "their time is up (Q30)")
	assert_eq(CarrierTactics.flee_move(false, true, 0, 5.0, 45.0), CarrierTactics.MOVE_GATE, "still recharging: the gate needs no drive")
	assert_eq(CarrierTactics.flee_move(false, true, 2, 5.0, 45.0), CarrierTactics.MOVE_GATE, "it runs early, its fighters catching up")
	assert_eq(CarrierTactics.flee_move(false, false, 0, 5.0, 45.0), CarrierTactics.MOVE_RUN, "no gate: it runs until the drive is ready")
	assert_false(CarrierTactics.should_leave(2, 10.0, 45.0), "it waits for its fighters")
	assert_true(CarrierTactics.should_leave(0, 10.0, 45.0), "all home")
	assert_true(CarrierTactics.should_leave(2, 45.0, 45.0), "it has waited long enough")


func test_a_run_for_a_gate_goes_round_its_side_onto_the_axis_and_through() -> void:
	var r: float = 750.0
	var dep_z: float = -1500.0
	assert_eq(CarrierTactics.gate_run_target(Vector3(100.0, 0.0, -5000.0), dep_z, r), Vector3(0.0, 0.0, r),
			"on the run-in: through the mouth's centre")
	assert_eq(CarrierTactics.gate_run_target(Vector3(4000.0, 0.0, -5000.0), dep_z, r), Vector3(0.0, 0.0, dep_z),
			"in front, off the axis: to the departure point")
	var behind: Vector3 = CarrierTactics.gate_run_target(Vector3(100.0, 0.0, 3000.0), dep_z, r)
	assert_almost_eq(behind.x, CarrierTactics.GATE_CLEAR_RADII * r, 1e-3, "behind the mouth: out sideways first")
	assert_eq(behind.z, 3000.0, "not through the gate's back")
	var beside: Vector3 = CarrierTactics.gate_run_target(Vector3(0.0, 2000.0, 500.0), dep_z, r)
	assert_almost_eq(beside.y, CarrierTactics.GATE_CLEAR_RADII * r, 1e-3, "clear of the arms")
	assert_eq(beside.z, dep_z, "then forward to the front")
	# Flown from dead astern it ends through the mouth from the front, never crossing the mouth's plane inside the arms.
	var at := Vector3(0.0, 0.0, 4000.0)
	var through: bool = false
	for i: int in 4000:
		var step: Vector3 = (CarrierTactics.gate_run_target(at, dep_z, r) - at).normalized() * 10.0
		var next: Vector3 = at + step
		if at.z < 0.0 and next.z >= 0.0:
			through = Vector2(next.x, next.y).length() < r
			break
		if at.z > 0.0 and next.z <= 0.0:
			assert_gt(Vector2(next.x, next.y).length(), 1240.0, "it passes the mouth's plane outside the gate's arms")
		at = next
	assert_true(through, "and goes through the mouth")


# --- the play-test rules of 2026-11-20 (M8-T08) ------------------------------------------------------------------------


func test_cornered_is_under_attack_with_the_drive_empty() -> void:
	assert_true(CarrierTactics.cornered(true, false), "hit, and it cannot jump: every docked fighter goes out")
	assert_false(CarrierTactics.cornered(true, true), "hit, but it can jump away")
	assert_false(CarrierTactics.cornered(false, false), "nobody is shooting at it")


func test_its_weave_never_stops_and_is_its_own() -> void:
	var first: Vector3 = CarrierTactics.weave(7, 0.0, 12.0, 90.0)
	var turned: float = 0.0
	var last: Vector3 = first
	for i: int in 900:
		var w: Vector3 = CarrierTactics.weave(7, float(i), 12.0, 90.0)
		assert_almost_eq(w.length(), 12.0, 1e-3, "always under way, at its weave's speed")
		turned = maxf(turned, rad_to_deg(first.angle_to(w)))
		assert_lt(rad_to_deg(last.angle_to(w)), 8.0, "slow: no more than a few degrees a second")
		last = w
	assert_gt(turned, 150.0, "it comes right round")
	assert_eq(CarrierTactics.weave(7, 33.0, 12.0, 90.0), CarrierTactics.weave(7, 33.0, 12.0, 90.0), "the same every time for one seed")
	assert_gt(CarrierTactics.weave(7, 33.0, 12.0, 90.0).distance_to(CarrierTactics.weave(8, 33.0, 12.0, 90.0)), 0.5,
			"another carrier weaves its own way")


func test_it_is_pushed_out_of_what_it_keeps_clear_of() -> void:
	var centres := PackedVector3Array([Vector3.ZERO])
	var radii := PackedFloat32Array([12000.0])
	assert_eq(CarrierTactics.keep_out(Vector3(13000.0, 0.0, 0.0), centres, radii), Vector3.ZERO, "outside: nothing to do")
	var edge: Vector3 = CarrierTactics.keep_out(Vector3(11900.0, 0.0, 0.0), centres, radii)
	assert_gt(edge.x, 0.45, "just inside: out again at half speed or more, faster than its weave could take it in")
	var deep: Vector3 = CarrierTactics.keep_out(Vector3(0.0, 6000.0, 0.0), centres, radii)
	assert_almost_eq((deep - Vector3.UP).length(), 0.0, 1e-4, "deep inside: straight out at full speed")
	var two: Vector3 = CarrierTactics.keep_out(Vector3(500.0, 0.0, 0.0), PackedVector3Array([Vector3.ZERO, Vector3(1000.0, 0.0, 0.0)]),
			PackedFloat32Array([4000.0, 4000.0]))
	assert_lte(two.length(), 1.0, "between two it is still one push")


func test_a_run_goes_round_the_guns_when_a_safer_way_exists() -> void:
	# The grid sits on the straight line from the carrier to the gate's approach.
	var from := Vector3(0.0, 0.0, 30000.0)
	var goal := Vector3(0.0, 0.0, -30000.0)
	var centres := PackedVector3Array([Vector3(1000.0, 0.0, 0.0)])
	var radii := PackedFloat32Array([12000.0])
	assert_gt(CarrierTactics.time_inside(from, goal, centres, radii, 60.0), 300.0, "the straight way is minutes under the guns")
	var via: Vector3 = CarrierTactics.route_via(from, goal, centres, radii, 60.0, 4.0)
	assert_ne(via, goal, "so it does not fly it")
	assert_gt(via.distance_to(centres[0]), radii[0], "its way round passes outside the guns' reach")
	assert_almost_eq(CarrierTactics.time_inside(from, via, centres, radii, 60.0), 0.0, 1e-3, "the first leg is clear")
	assert_lt(CarrierTactics.time_inside(via, goal, centres, radii, 60.0), 30.0, "and the second all but clear")
	# Flown, deciding again as it goes, it reaches the goal without entering the guns' reach.
	var at: Vector3 = from
	var nearest: float = INF
	for i: int in 4000:
		if at.distance_to(goal) < 100.0:
			break
		at += (CarrierTactics.route_via(at, goal, centres, radii, 60.0, 4.0) - at).normalized() * 30.0
		nearest = minf(nearest, at.distance_to(centres[0]))
	assert_lt(at.distance_to(goal), 100.0, "it gets there")
	assert_gt(nearest, radii[0] - 600.0, "having no more than skimmed the margin round the guns' reach (%.0f m)" % nearest)
	# Nothing in the way: straight there.
	assert_eq(CarrierTactics.route_via(from, goal, PackedVector3Array([Vector3(40000.0, 0.0, 0.0)]), radii, 60.0, 4.0), goal)
	assert_eq(CarrierTactics.route_via(from, goal, PackedVector3Array(), PackedFloat32Array(), 60.0, 4.0), goal)


func test_with_every_way_dangerous_a_run_still_goes() -> void:
	# The gate itself lies inside the guns' reach, and so does the carrier: there is no safe way, and it goes all the same.
	var from := Vector3(0.0, 0.0, 5000.0)
	var goal := Vector3(0.0, 0.0, -5000.0)
	var centres := PackedVector3Array([Vector3.ZERO])
	var radii := PackedFloat32Array([12000.0])
	var via: Vector3 = CarrierTactics.route_via(from, goal, centres, radii, 60.0, 4.0)
	assert_true(via.is_finite())
	var at: Vector3 = from
	for i: int in 2000:
		if at.distance_to(goal) < 100.0:
			break
		at += (CarrierTactics.route_via(at, goal, centres, radii, 60.0, 4.0) - at).normalized() * 30.0
	assert_lt(at.distance_to(goal), 100.0, "it reaches the gate")


func test_the_play_test_distances_are_data() -> void:
	var raiders: Dictionary = CarrierTactics.options({}, CapitalData.doctrine(Factions.RAIDERS))
	for key: String in ["grid_margin_m", "wing_keepout_m", "wing_span_m", "watch_m", "weave_mps", "weave_period_s", "attack_memory_s",
			"danger_weight"]:
		assert_true(CapitalData.doctrine(Factions.RAIDERS).has(key), "%s is in capitals.json" % key)
		assert_gt(float(raiders[key]), 0.0, key)
	assert_gte(int(raiders["wing_size"]), 2, "a group is more than one fighter")
	assert_lt(float(raiders["weave_mps"]), CarrierJumps.CARRIER_SPEED_MPS * CarrierTactics.KEEP_OUT_MIN + 0.01,
			"its weave cannot carry it into what it is pushed out of")


# --- the native docking rows ------------------------------------------------------------------------------------------


func _step(rows: ScsDockRows, at: Vector3, velocity: Vector3, carrier_velocity: Vector3 = Vector3.ZERO) -> Array:
	return rows.step(1.0 / 60.0, Vector3.ZERO, Basis.IDENTITY, carrier_velocity, Vector3.ZERO, 150.0, PackedVector3Array([at]),
			PackedVector3Array([velocity]), PackedFloat32Array([20.0]))


func test_a_launch_runs_from_the_pad_to_its_release() -> void:
	var rows := ScsDockRows.new()
	var numbers: PackedFloat64Array = rows.constants()
	rows.add(7, CarrierDock.PHASE_LAUNCH, Vector3(0.0, 40.0, 10.0), Basis.IDENTITY, 60.0, Vector3(0.0, -0.8, 0.0))
	assert_eq(rows.count(), 1)
	assert_eq(rows.keys(), PackedInt64Array([7]))
	assert_eq(rows.phase_of(7), 0)
	var out: Array = _step(rows, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -30.0))
	assert_almost_eq((out[1][0] as Vector3).y, 40.8, 0.01, "it starts on its pad")
	var ticks: int = 1
	while (out[0] as PackedInt32Array)[0] == 0 and ticks < 600:
		out = _step(rows, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -30.0))
		ticks += 1
	assert_eq((out[0] as PackedInt32Array)[0], CarrierDock.EVENT_RELEASED)
	assert_almost_eq(float(ticks) / 60.0, numbers[0], 0.05, "after the launch time")
	assert_almost_eq((out[1][0] as Vector3).y, 40.8 + numbers[2], 0.01, "at the release height")
	assert_almost_eq((out[2][0] as Vector3).z, -30.0, 1e-3, "with the carrier's velocity")
	assert_gt((out[2][0] as Vector3).y, 20.0, "and the push outward")
	assert_eq(rows.count(), 0, "a released row is gone")


func test_a_return_ends_at_the_approach_point_and_a_capture_on_the_pad() -> void:
	var rows := ScsDockRows.new()
	rows.add(3, CarrierDock.PHASE_RETURN, Vector3(0.0, 40.0, 10.0), Basis.IDENTITY, 60.0, Vector3(0.0, -0.8, 0.0))
	var far: Array = _step(rows, Vector3(0.0, 1500.0, 10.0), Vector3.ZERO)
	assert_eq((far[0] as PackedInt32Array)[0], 0)
	assert_lt((far[2][0] as Vector3).y, -100.0, "it is sent in fast from far out")
	assert_almost_eq(((far[1][0] as Vector3) - Vector3(0.0, 100.8, 10.0)).length(), 0.0, 1e-3, "to its approach point")
	var behind: Array = _step(rows, Vector3(0.0, -600.0, 10.0), Vector3.ZERO)
	assert_gt((behind[1][0] as Vector3).length(), 149.0, "from behind the carrier it is sent round, outside the hull")
	var there: Array = _step(rows, Vector3(0.5, 102.0, 10.0), Vector3(0.0, -5.0, 0.0))
	assert_eq((there[0] as PackedInt32Array)[0], CarrierDock.EVENT_AT_APPROACH)
	rows.begin_capture(3, Vector3(0.5, 102.0, 10.0), Basis.IDENTITY)
	assert_eq(rows.phase_of(3), 2)
	var out: Array = there
	var ticks: int = 0
	while rows.count() > 0 and ticks < 900:
		out = _step(rows, Vector3.ZERO, Vector3.ZERO)
		ticks += 1
	assert_eq((out[0] as PackedInt32Array)[0], CarrierDock.EVENT_DOCKED)
	assert_almost_eq(((out[1][0] as Vector3) - Vector3(0.0, 40.8, 10.0)).length(), 0.0, 1e-3, "on its pad")
	assert_almost_eq(float(ticks) / 60.0, rows.constants()[1], 0.05, "after the capture time")


func test_rows_are_kept_by_key_in_the_order_they_were_added() -> void:
	var rows := ScsDockRows.new()
	rows.add(1, CarrierDock.PHASE_RETURN, Vector3(0.0, 40.0, 0.0), Basis.IDENTITY, 60.0, Vector3.ZERO)
	rows.add(2, CarrierDock.PHASE_RETURN, Vector3(0.0, -40.0, 0.0), Basis(Vector3.RIGHT, PI), 60.0, Vector3.ZERO)
	rows.add(1, CarrierDock.PHASE_LAUNCH, Vector3(0.0, 40.0, 0.0), Basis.IDENTITY, 60.0, Vector3.ZERO)
	assert_eq(rows.keys(), PackedInt64Array([2, 1]), "a key added again is replaced, at the end")
	assert_true(rows.remove(2))
	assert_false(rows.remove(2))
	assert_eq(rows.phase_of(2), -1)
	rows.clear()
	assert_eq(rows.count(), 0)
