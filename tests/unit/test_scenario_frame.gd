extends GutTest
## Where and when a scenario is (M6-T09, AC6, Q7, Q9): the `anchor` block's three forms (a place's rail with the station
## beside the start, a circle at an altitude over a body, any orbit), the `epoch` (a number, or seeded from the run's seed
## among starts that are lit with the planet ahead), their refusals, and every shipped scenario starting lit with the planet
## in view.

const PLANET: StringName = &"epsilon_iii"
const STATION: StringName = &"babylon5"
const GATE: StringName = &"jumpgate"
const PLANET_RADIUS_M: float = 4.78e6
const PLANET_GM: float = 1.68e14
const STATION_ORBIT_M: float = 2.75e7
const AT: Array = [5500, -1200, -6000]
const SCENARIOS: Array[String] = ["free_flight", "combat_sandbox", "instructor_route", "dogfight", "civilian_showcase",
		"belt_showcase", "civilian_escort"]

var system: StarSystem


func before_all() -> void:
	system = StarSystem.load_system(&"local")


func _spec(anchor: Variant, epoch: Variant = null) -> Dictionary:
	var made: Variant = ScenarioFrame.parse(anchor, epoch, "t")
	assert_true(made is Dictionary, str(made))
	return made if made is Dictionary else ScenarioFrame.default_spec()


func _resolve(spec: Dictionary, seed_value: int = 0) -> Dictionary:
	var out: Dictionary = ScenarioFrame.resolve(spec, system, seed_value, PackedFloat64Array([0.0, 0.0, 0.0]), Vector3.FORWARD)
	assert_true(out["ok"], out["error"])
	return out


static func _v(a: PackedFloat64Array, from: int = 0) -> Vector3:
	return Vector3(a[from], a[from + 1], a[from + 2])


# Lengths and angles in 64 bits: a Vector3 holds 32.
static func _len(a: PackedFloat64Array, from: int = 0) -> float:
	return sqrt(a[from] * a[from] + a[from + 1] * a[from + 1] + a[from + 2] * a[from + 2])


static func _dot(a: PackedFloat64Array, b: PackedFloat64Array, from_a: int = 0, from_b: int = 0) -> float:
	return a[from_a] * b[from_b] + a[from_a + 1] * b[from_b + 1] + a[from_a + 2] * b[from_b + 2]


static func _minus(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


func test_no_anchor_rides_the_station_rail_with_the_origin_on_it() -> void:
	assert_true(system.is_valid(), "; ".join(system.errors))
	var spec: Dictionary = _spec(null)
	assert_eq(spec["kind"], ScenarioFrame.KIND_PLACE)
	assert_eq(spec["id"], STATION)
	assert_false(spec["standin"], "the tests' own scenarios get no stand-in")
	assert_eq(spec["epoch_s"], 0.0)
	var out: Dictionary = _resolve(spec)
	assert_eq(_v(out["offset"]), Vector3.ZERO)
	assert_eq(_v(ScenarioFrame.place_in_scene(out, system, STATION, 0.0)), Vector3.ZERO, "the station at the origin, as before T09")


func test_a_place_anchor_puts_the_station_where_the_scenario_says() -> void:
	var spec: Dictionary = _spec({"place": "babylon5", "at": AT}, 1234.5)
	assert_true(spec["standin"], "a scenario that names the place gets its stand-in")
	var out: Dictionary = _resolve(spec)
	assert_eq(out["epoch_s"], 1234.5)
	assert_eq(_v(out["offset"]), -Vector3(5500, -1200, -6000), "the scenario's origin from the station")
	var station: Vector3 = _v(ScenarioFrame.place_in_scene(out, system, STATION, out["epoch_s"]))
	assert_almost_eq(station, Vector3(5500, -1200, -6000), Vector3.ONE * 1.0e-6)
	assert_false(_spec({"place": "babylon5", "standin": false})["standin"])


func test_the_gate_stands_on_the_rail_50_km_ahead_of_the_station() -> void:
	for epoch: float in [0.0, 20000.0, 540148.0]:
		var out: Dictionary = _resolve(_spec({"place": "babylon5", "at": AT}, epoch))
		var station64: PackedFloat64Array = ScenarioFrame.place_in_scene(out, system, STATION, epoch)
		var gate64: PackedFloat64Array = ScenarioFrame.place_in_scene(out, system, GATE, epoch)
		var planet64: PackedFloat64Array = ScenarioFrame.place_in_scene(out, system, PLANET, epoch)
		var station: Vector3 = _v(station64)
		var gate: Vector3 = _v(gate64)
		var planet: Vector3 = _v(planet64)
		assert_almost_eq(_len(_minus(gate64, station64)), 50000.0, 10.0, "Q3: 50 km on the same orbit")
		assert_almost_eq(_len(_minus(gate64, planet64)), STATION_ORBIT_M, 1.0e-3, "on the station's orbit")
		var radial: Vector3 = (station - planet).normalized()
		var ahead: Vector3 = (gate - station).normalized()
		assert_almost_eq(radial.dot(ahead), 0.0, 0.002, "along the orbit, not toward the planet")
		var orbit_velocity: Vector3 = _v(ScaledPlacement.to_game(system.relative_state(STATION, PLANET, epoch).slice(3, 6)))
		assert_gt(ahead.dot(orbit_velocity.normalized()), 0.999, "ahead: where the station goes next")


func test_a_body_anchor_is_a_circle_at_the_altitude() -> void:
	var out: Dictionary = _resolve(_spec({"body": "epsilon_iii", "altitude_m": 400000}, 5000.0))
	assert_eq(out["kind"], ScenarioFrame.KIND_BODY)
	assert_eq(out["id"], PLANET)
	var state: PackedFloat64Array = out["state"]
	var r: Vector3 = _v(state)
	var radius: float = PLANET_RADIUS_M + 400000.0
	assert_almost_eq(_len(state), radius, 1.0e-6)
	assert_almost_eq(_len(state, 3), sqrt(PLANET_GM / radius), 1.0e-9, "the circular speed")
	assert_almost_eq(_dot(state, state, 0, 3), 0.0, 1.0e-3)
	assert_almost_eq(state[1], 0.0, 1.0e-6, "in the planet's plane with no inclination (the game's Y is north)")
	var turned: PackedFloat64Array = _resolve(_spec({"body": "epsilon_iii", "altitude_m": 400000, "phase_deg": 90}, 5000.0))["state"]
	assert_almost_eq(rad_to_deg(acos(_dot(state, turned) / (radius * radius))), 90.0, 1.0e-6, "the phase at the epoch")
	var tilted: PackedFloat64Array = _resolve(_spec({"body": "epsilon_iii", "altitude_m": 400000, "phase_deg": 90,
			"inclination_deg": 30}, 5000.0))["state"]
	assert_almost_eq(rad_to_deg(asin(tilted[1] / radius)), 30.0, 1.0e-6, "tilted out of the plane")
	assert_eq(_v(ScenarioFrame.place_in_scene(out, system, PLANET, 5000.0)), -r, "the planet seen from the anchor")


func test_an_orbit_anchor_follows_its_elements() -> void:
	var a: float = 1.2e7
	var out: Dictionary = _resolve(_spec({"orbit": {"body": "epsilon_iii", "a_m": a, "e": 0.25}}, 777.0))
	assert_eq(out["kind"], ScenarioFrame.KIND_ORBIT)
	var r: float = _len(out["state"])
	var v: float = _len(out["state"], 3)
	assert_almost_eq(r, a * 0.75, 1.0e-3, "at periapsis at the epoch (m0 0)")
	assert_almost_eq(v, sqrt(PLANET_GM * (2.0 / r - 1.0 / a)), 1.0e-6, "the vis-viva speed")
	var later: Dictionary = _resolve(_spec({"orbit": {"body": "epsilon_iii", "a_m": a, "e": 0.25, "epoch_s": 0.0}}, 777.0))
	assert_ne(_v(later["state"]), _v(out["state"]), "its own epoch_s is kept: 777 s along the orbit")


func test_the_epoch_and_the_forms_refuse_what_they_cannot_use() -> void:
	var refusals: Dictionary = {
		"exactly one of place, body or orbit": [{"place": "babylon5", "body": "epsilon_iii"}, null],
		"epoch must be a number": [null, "tomorrow"],
		"anchor.at must be": [{"place": "babylon5", "at": [1, 2]}, null],
		"anchor.altitude_m must be": [{"body": "epsilon_iii", "altitude_m": 0}, null],
		"anchor.orbit.a_m is missing": [{"orbit": {"body": "epsilon_iii", "e": 0.1}}, null],
		"anchor.orbit.peri is not an orbit key": [{"orbit": {"body": "epsilon_iii", "a_m": 1.0e7, "peri": 3}}, null],
		"anchor.standin must be": [{"place": "babylon5", "standin": "yes"}, null],
	}
	for reason: String in refusals:
		var made: Variant = ScenarioFrame.parse(refusals[reason][0], refusals[reason][1], "t")
		assert_true(made is String and (made as String).contains(reason), "%s: got %s" % [reason, made])
	var unknown: Dictionary = ScenarioFrame.resolve(_spec({"place": "nowhere"}), system, 0, PackedFloat64Array([0, 0, 0]), Vector3.FORWARD)
	assert_false(unknown["ok"])
	assert_string_contains(unknown["error"], "not a place")
	var star: Dictionary = ScenarioFrame.resolve(_spec({"body": "epsilon", "altitude_m": 1.0e6}), system, 0, PackedFloat64Array([0, 0, 0]),
			Vector3.FORWARD)
	assert_false(star["ok"], "the star is no body to circle in a scenario")
	var inside: Dictionary = ScenarioFrame.resolve(_spec({"orbit": {"body": "epsilon_iii", "a_m": 4.0e6}}), system, 0,
			PackedFloat64Array([0, 0, 0]), Vector3.FORWARD)
	assert_false(inside["ok"])
	assert_string_contains(inside["error"], "inside its parent's surface")
	var loaded: Dictionary = ScenarioLoader.from_data({"scenario_id": "t", "player": {"position": [0, 0, 0]}, "epoch": [1]})
	assert_false(loaded["ok"])
	assert_string_contains(loaded["error"], "epoch must be")


func test_a_seeded_epoch_starts_lit_with_the_planet_ahead_and_repeats_with_its_seed() -> void:
	var spec: Dictionary = _spec({"place": "babylon5", "at": AT}, "seeded")
	var seen: Dictionary = {}
	for seed_value: int in [0, 1, 2, 3, 4, 99, -7]:
		var epoch: float = _resolve(spec, seed_value)["epoch_s"]
		assert_eq(_resolve(spec, seed_value)["epoch_s"], epoch, "the same seed, the same start")
		seen[epoch] = true
		var eye: PackedFloat64Array = ScenarioFrame.eye_from_body(spec, system, PackedFloat64Array([0, 0, 0]), epoch)
		var view: Dictionary = ScenarioFrame.view_from(system, PLANET, eye, epoch, Vector3.FORWARD)
		assert_lte(float(view["angle_deg"]), ScenarioFrame.VIEW_DEG, "seed %d: the planet ahead" % seed_value)
		assert_gte(float(view["key_light"]), ScenarioFrame.KEY_LIGHT_MIN, "seed %d: out of the planet's shadow" % seed_value)
		assert_gte(float(view["planet_lit"]), ScenarioFrame.PLANET_LIT_MIN, "seed %d: the planet's day side" % seed_value)
	assert_eq(seen.size(), 7, "each seed its own start")
	var orbit: Dictionary = _spec({"body": "epsilon_iii", "altitude_m": 400000}, "seeded")
	var lit_epoch: float = _resolve(orbit, 5)["epoch_s"]
	assert_true(ScenarioFrame.good_start(orbit, system, PackedFloat64Array([0, 0, 0]), Vector3.FORWARD, lit_epoch),
			"an orbit's seeded start is out of the shadow")


func test_epoch_zero_is_in_the_shadow_which_is_why_scenarios_set_one() -> void:
	var spec: Dictionary = _spec({"place": "babylon5"}, 0.0)
	var eye: PackedFloat64Array = ScenarioFrame.eye_from_body(spec, system, PackedFloat64Array([0, 0, 0]), 0.0)
	assert_lt(float(ScenarioFrame.view_from(system, PLANET, eye, 0.0, Vector3.FORWARD)["key_light"]), 0.01,
			"the data's epoch has the station behind Epsilon III (T10's finding)")


func test_every_shipped_scenario_starts_beside_the_station_lit_with_the_planet_in_view() -> void:
	for id: String in SCENARIOS:
		var s: Dictionary = ScenarioLoader.load("res://data/scenarios/%s.json" % id)
		assert_true(s["ok"], s["error"])
		var spec: Dictionary = s["frame"]
		assert_true(spec["declared"] and spec["standin"], "%s names its anchor and has the station's stand-in" % id)
		assert_eq(spec["id"], STATION, id)
		assert_true(spec["seeded"] == (id == "free_flight"), "%s: free flight seeds its epoch, the rest set one" % id)
		var player: UniversePos = s["player"]["position"]
		var start := PackedFloat64Array([player.x, player.y, player.z])
		var forward: Vector3 = s["player"]["forward"]
		var out: Dictionary = ScenarioFrame.resolve(spec, system, 1, start, forward)
		assert_true(out["ok"], out["error"])
		assert_true(ScenarioFrame.good_start(spec, system, start, forward, out["epoch_s"]),
				"%s: lit, the planet within %.0f degrees of the start's forward" % [id, ScenarioFrame.VIEW_DEG])
		var station: Vector3 = _v(ScenarioFrame.place_in_scene(out, system, STATION, out["epoch_s"]))
		var apart: float = station.distance_to(_v(start))
		assert_between(apart, 6000.0, 12000.0, "%s: the station beside the start, %.1f km off" % [id, apart / 1000.0])
