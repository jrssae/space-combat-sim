extends GutTest
## AI flights of three in a seeded fight (M8-T19, D85, AC15): two flights of Starfuries under the real `WingDirector`
## against raiders, through the native core, headless with the physics rate and the time scale raised.
## - Cohesion: every wingman stays within the flights' cohesion distance of its lead (`data/wings/flights.json`), give or
##   take the room a fighter needs to turn back.
## - Cover: while a raider has a member of a flight selected, that member's flight-mates in an attack go for a raider that
##   is after one of the flight.
## - The same fight without the flights' rules (the wings as they flew before) is the control: its wingmen stray farther.
## - A short leash: with a cohesion distance the fight's runs do overrun, a wingman past it breaks off its attack, flies
##   back to its lead and fights again.
## - Threads: the rows and the commands are the same bits every tick with the AI job threaded and delayed, and with one
##   thread and six.

const ALLY: StringName = &"starfury_ally"
const RAIDER: StringName = &"raider_fighter"
const SPEED_UP: float = 8.0
const FLIGHTS: int = 2
const RAIDERS: int = 6
## The raiders start this far ahead of the flights, m.
const RANGE_M: float = 4000.0
const FIGHT_S: float = 120.0
## How long the threads test flies the fight: into the merge and the first passes.
const DIGEST_TICKS: int = 2400
## The short leash's distances, m: shorter than a gun run's extension.
const SHORT_COHESION_M: float = 700.0
const SHORT_REJOINED_M: float = 300.0
## A wingman past the cohesion distance is already turning back; this is the room that takes, m.
const TURN_ROOM_M: float = 600.0

var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()  # minutes of fighting


func before_each() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func test_flights_of_three_stay_within_their_cohesion_distance_and_cover_each_other() -> void:
	var rules: FlightRules = FlightRules.shared()
	var with_rules: Dictionary = await _fight_stats(true, rules)
	gut.p("  flights: %s" % str(with_rules))
	assert_gt(int(with_rules["hits"]), 0, "it was a fight (%d hits)" % int(with_rules["hits"]))
	assert_gt(int(with_rules["wingman_ticks"]), 1000, "the wingmen flew with their leads")
	assert_lt(float(with_rules["farthest_m"]), rules.cohesion_m + TURN_ROOM_M,
			"no wingman strayed farther than the cohesion distance and its turn back (%.0f m)" % float(with_rules["farthest_m"]))
	assert_gt(float(with_rules["within"]), 0.98, "the wingmen were inside the distance %.1f %% of the time" %
			(100.0 * float(with_rules["within"])))
	assert_gt(int(with_rules["cover_asked"]), 200, "flight-mates were under attack (%d mate-ticks)" % int(with_rules["cover_asked"]))
	assert_gt(float(with_rules["covered"]), 0.9, "a mate in an attack went for the flight's attacker %.1f %% of the time" %
			(100.0 * float(with_rules["covered"])))
	# The control: the same ships and seeds as wings without the flights' rules.
	var without: Dictionary = await _fight_stats(false, rules)
	gut.p("  control: %s" % str(without))
	assert_gt(float(without["farthest_m"]), float(with_rules["farthest_m"]), "without the rules the wingmen stray farther")
	assert_gt(float(with_rules["covered"]), float(without["covered"]), "and cover each other less")


func test_a_wingman_past_a_short_cohesion_distance_breaks_off_rejoins_and_fights_again() -> void:
	var short: FlightRules = FlightRules.from_dict({"cohesion_m": SHORT_COHESION_M, "rejoined_m": SHORT_REJOINED_M})
	var stats: Dictionary = await _fight_stats(true, short)
	gut.p("  short leash: %s" % str(stats))
	assert_gt(int(stats["rejoins"]), 2, "wingmen overran the distance (%d times)" % int(stats["rejoins"]))
	assert_gt(int(stats["strayed_ticks"]), 0)
	assert_lt(float(stats["strayed_attacking"]), 0.1, "a strayed wingman is not in an attack (%.1f %% of its ticks, the think's lag)" %
			(100.0 * float(stats["strayed_attacking"])))
	assert_lt(float(stats["farthest_m"]), SHORT_COHESION_M + TURN_ROOM_M, "it turned back within the room a turn takes (%.0f m)" %
			float(stats["farthest_m"]))
	assert_gt(int(stats["rejoined"]), 0, "and came back inside the rejoin distance to fight again")
	assert_gt(int(stats["hits"]), 0, "the flights still fought (%d hits)" % int(stats["hits"]))


func test_the_fight_is_the_same_threaded_and_delayed_and_with_one_thread_and_six() -> void:
	var delayed: Dictionary = await _digests(&"delayed", 6)
	var threaded: Dictionary = await _digests(&"threaded", 6)
	var one: Dictionary = await _digests(&"threaded", 1)
	assert_gt(int(delayed["shots"]), 0, "the fight was joined (%d hits)" % int(delayed["shots"]))
	for key: String in ["rows", "commands"]:
		var first: int = _first_difference(delayed[key], threaded[key])
		assert_eq(first, -1, "%s: threaded against delayed, the same bits (first difference at tick %d)" % [key, first])
		first = _first_difference(one[key], threaded[key])
		assert_eq(first, -1, "%s: one thread against six, the same bits (first difference at tick %d)" % [key, first])
	assert_eq(threaded["shots"], delayed["shots"])


# The fight flown `FIGHT_S` with the flights' rules (`rules`) on or off: the hits landed, the wingmen's distances from their
# leads (`farthest_m`, the share of ticks `within` the cohesion distance, over `wingman_ticks`), how often a wingman
# overran the distance (`rejoins`) and came back inside the rejoin distance (`rejoined`), the ticks it was strayed and the
# share of them it was still in an attack, and of the ticks a pilot in an attack had a flight-mate under attack
# (`cover_asked`) the share it spent on a raider that was after one of the flight (`covered`).
func _fight_stats(flights_on: bool, rules: FlightRules) -> Dictionary:
	var f: Dictionary = await _fight(&"threaded", 6, flights_on, rules)
	var scene: TurretScene = f["scene"]
	var director: WingDirector = f["director"]
	var raiders: Array[Combatant] = f["raiders"]
	var farthest_m: float = 0.0
	var wingman_ticks: int = 0
	var within: int = 0
	var rejoins: int = 0
	var rejoined: int = 0
	var strayed_ticks: int = 0
	var strayed_attacking: int = 0
	var cover_asked: int = 0
	var covered: int = 0
	var strayed: Dictionary = {}
	_speed_up()
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < FIGHT_S:
		await get_tree().physics_frame
		# Who each living raider is after.
		var after: Dictionary = {}
		for r: Combatant in raiders:
			if r.damageable.is_active():
				after[r.targetable.get_instance_id()] = r.ship.targeting.selected_id()
		for wing: Wing in f["wings"]:
			if not director.leader_alive(wing):
				continue
			var flight: Array[Combatant] = [wing.leader]
			flight.append_array(wing.members())
			var lead_at: Vector3 = wing.leader.ship.global_position
			for c: Combatant in wing.members():
				var d: float = c.ship.global_position.distance_to(lead_at)
				farthest_m = maxf(farthest_m, d)
				wingman_ticks += 1
				within += 1 if d <= rules.cohesion_m else 0
				# The brain's own rule, kept here from the distances: past the cohesion distance until back within the rejoin's.
				var pilot := c.driver.brain as AiPilot
				var was: bool = strayed.get(c, false)
				var now: bool = pilot.context.cohesion_m > 0.0 and d > (rules.rejoined_m if was else rules.cohesion_m)
				rejoins += 1 if now and not was else 0
				rejoined += 1 if was and not now else 0
				strayed[c] = now
				if now:
					strayed_ticks += 1
					strayed_attacking += 1 if pilot.current != null and pilot.current.id == &"attack" else 0
			for c: Combatant in flight:
				var pilot := c.driver.brain as AiPilot
				if pilot == null or pilot.current == null or pilot.current.id != &"attack":
					continue
				# The raiders after one of its flight-mates.
				var threats: Array[int] = []
				for raider_id: int in after:
					for mate: Combatant in flight:
						if mate != c and after[raider_id] == mate.targetable.get_instance_id():
							threats.append(raider_id)
				if threats.is_empty():
					continue
				cover_asked += 1
				covered += 1 if threats.has(pilot.wanted_target_id) else 0
	var hits: int = scene.hits.size()
	after_each()
	await scene.free_scene(get_tree())
	return {"hits": hits, "farthest_m": farthest_m, "wingman_ticks": wingman_ticks,
			"within": float(within) / float(maxi(wingman_ticks, 1)), "rejoins": rejoins, "rejoined": rejoined,
			"strayed_ticks": strayed_ticks, "strayed_attacking": float(strayed_attacking) / float(maxi(strayed_ticks, 1)),
			"cover_asked": cover_asked, "covered": float(covered) / float(maxi(cover_asked, 1))}


# The fight's first `DIGEST_TICKS` ticks with the step `mode` and `threads` threads: per tick the rows' and commands' digests.
func _digests(mode: StringName, threads: int) -> Dictionary:
	var f: Dictionary = await _fight(mode, threads, true, FlightRules.shared())
	var scene: TurretScene = f["scene"]
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	_speed_up()
	for k: int in DIGEST_TICKS:
		await get_tree().physics_frame
		rows.append(int(scene.sim.core.rows_digest()))
		commands.append(int(scene.sim.core.commands_digest()))
	var out: Dictionary = {"rows": rows, "commands": commands, "shots": scene.hits.size()}
	after_each()
	await scene.free_scene(get_tree())
	return out


# `FLIGHTS` flights of three Starfuries (BETA, joined through the wing director as a scenario's wing of flights, or with
# `flights_on` off as plain wings of three) flying -z, and `RAIDERS` raiders `RANGE_M` ahead coming at them, every brain
# seeded, stepped with `mode` and `threads` threads; the flights fly by `rules`.
func _fight(mode: StringName, threads: int, flights_on: bool, rules: FlightRules) -> Dictionary:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, mode, threads)
	var director := WingDirector.new()
	director.name = "WingDirector"
	scene.space.add_child(director)
	director.setup(scene.world)
	director.flight_rules = rules
	director.declare([{"name": "BETA", "leader": "", "order": AiContext.Order.ENGAGE_AT_WILL,
			"formation": Formation.Shape.FINGER_FOUR, "home": &"", "flight": flights_on}] as Array[Dictionary])
	var places: Array[Vector3] = [Vector3.ZERO, Vector3(-40.0, 0.0, 40.0), Vector3(40.0, 0.0, 40.0)]
	var wings: Array[Wing] = []
	for i: int in FLIGHTS * places.size():
		@warning_ignore("integer_division")
		var flight: int = i / places.size()
		var at: Vector3 = Vector3(700.0 * flight, 0.0, 0.0) + places[i % places.size()]
		var c: Combatant = scene.ship(ALLY, Factions.EARTH_ALLIANCE, "BETA %d" % (i + 1), at,
				{"type": "ai", "profile": "ally_starfury"}, 100 + i)
		scene.park_on_death(c)
		c.ship.linear_velocity = Vector3(0.0, 0.0, -100.0)
		# The control flies the same ships as wings of three without the flights' rules: one wing a flight, named apart.
		var wing: Wing = director.join("BETA", c) if flights_on else director.join("BETA %d" % flight, c)
		if not wings.has(wing):
			wings.append(wing)
	var raiders: Array[Combatant] = []
	for i: int in RAIDERS:
		var at := Vector3(350.0 + 220.0 * (float(i) - 0.5 * float(RAIDERS - 1)), 60.0 * float(i % 3 - 1), -RANGE_M)
		var c: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "RAIDER %d" % (i + 1), at, {"type": "ai", "profile": "raider"},
				200 + i, false, Basis.looking_at(Vector3.BACK))
		scene.park_on_death(c)
		c.ship.linear_velocity = Vector3(0.0, 0.0, 100.0)
		raiders.append(c)
	scene.attach()
	return {"scene": scene, "director": director, "wings": wings, "raiders": raiders}


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


func _speed_up() -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
