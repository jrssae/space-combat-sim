extends GutTest
## The instructor's route (M3-T09, AC10, architecture §16 D37): `Route` (waypoints, pacing numbers, lag) and
## `BehaviourFollowPath`, which leads the route paced to the player and runs a demo at a waypoint. Scripted perceptions,
## no physics; the Jolt runs are `tests/integration/test_instructor_route.gd` and `test_manoeuvres_jolt.gd`.

const DT: float = 1.0 / 60.0
const PACE_ID: int = 77
const SELF_ID: int = 5


func _capability() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 15.0
	cap.a_rcs = Vector2(10.0, 10.0)
	cap.rate_max_rad = Vector3(1.0, 1.0, 1.5)
	cap.alpha_max_rad = Vector3(1.5, 1.5, 3.0)
	return cap


## A route along -Z: waypoints at 1, 2, ... km, each `{"demo": ..., "hold_s": ...}` or {}.
func _route(entries: Array, loop: bool = false, pace_id: int = PACE_ID) -> Route:
	var route := Route.new()
	route.name = "TEST"
	route.loop = loop
	route.pace_id = pace_id
	for i: int in entries.size():
		var e: Dictionary = entries[i]
		route.add(UniversePos.new(0.0, 0.0, -1000.0 * float(i + 1)), StringName(e.get("demo", "")), float(e.get("hold_s", 0.0)))
	return route


## The pace ship (the player) at `at`, a friendly contact.
func _pace(at: Vector3) -> Contact:
	var c := Contact.new()
	c.id = PACE_ID
	c.name = "PLAYER"
	c.relation = Factions.Relation.FRIENDLY
	c.faction = Factions.EARTH_ALLIANCE
	c.position = at
	c.is_ship = true
	c.bounding_radius = 10.0
	return c


## The instructor at `at` with `velocity`, nose -Z (or `basis`), the pace ship `lag_m` behind it (+Z), or none.
func _p(at: Vector3, lag_m: float = 300.0, velocity: Vector3 = Vector3.ZERO, basis: Basis = Basis.IDENTITY) -> Perception:
	var p := Perception.new()
	p.position = at
	p.velocity = velocity
	p.basis = basis
	p.capability = _capability()
	p.self_id = SELF_ID
	p.faction = Factions.EARTH_ALLIANCE
	var contacts: Array[Contact] = []
	if lag_m >= 0.0:
		contacts.append(_pace(at + Vector3(0.0, 0.0, lag_m)))
	p.contacts = contacts
	return p


func _context(route: Route) -> AiContext:
	var ctx := AiContext.new()
	ctx.route = route
	return ctx


func _think(b: BehaviourFollowPath, ctx: AiContext, p: Perception) -> PilotCommand:
	ctx.refresh(p)
	b.score(ctx)
	b.has_desired_velocity = false
	return b.think(ctx, DT)


# --- Route -----------------------------------------------------------------------------------------------------------


func test_the_pacing_numbers_are_the_plans() -> void:
	assert_eq(Route.DEFAULT_CRUISE_MPS, 60.0)
	assert_eq(Route.FULL_PACE_M, 600.0)
	assert_eq(Route.STOP_PACE_M, 1500.0)
	assert_eq(Route.WAIT_BEYOND_M, 1600.0)
	assert_eq(Route.RESUME_WITHIN_M, 800.0)
	assert_eq(Route.ARRIVAL_M, 150.0)


func test_full_cruise_under_600_m_then_linear_to_zero_at_1500_m() -> void:
	var route := _route([{}])
	assert_eq(route.pace_speed(0.0), 60.0)
	assert_eq(route.pace_speed(600.0), 60.0)
	assert_almost_eq(route.pace_speed(1050.0), 30.0, 1e-9)
	assert_almost_eq(route.pace_speed(1275.0), 15.0, 1e-9)
	assert_eq(route.pace_speed(1500.0), 0.0)
	assert_eq(route.pace_speed(INF), 0.0)
	route.cruise_mps = 80.0
	assert_almost_eq(route.pace_speed(1050.0), 40.0, 1e-9, "a share of the route's cruise")


func test_it_waits_beyond_1600_m_until_the_pace_ship_closes_to_800_m() -> void:
	assert_false(Route.should_wait(1600.0, false))
	assert_true(Route.should_wait(1600.5, false))
	assert_true(Route.should_wait(INF, false), "a pace ship out of sight is waited for")
	assert_true(Route.should_wait(1000.0, true), "once waiting, 1 000 m is not close enough")
	assert_true(Route.should_wait(800.0, true))
	assert_false(Route.should_wait(799.0, true))


func test_waypoints_count_label_and_wrap() -> void:
	var route := _route([{}, {"demo": "roll"}, {"hold_s": 2.0}])
	assert_eq(route.count(), 3)
	assert_eq(route.label(1), "NAV 2")
	assert_eq(route.waypoint(1).demo, &"roll")
	assert_eq(route.waypoint(2).hold_s, 2.0)
	assert_eq(route.next_index(0), 1)
	assert_eq(route.next_index(2), -1, "the end of a route that does not loop")
	route.loop = true
	assert_eq(route.next_index(2), 0)


func test_the_lag_is_the_distance_to_the_pace_ship() -> void:
	var route := _route([{}])
	var ctx := _context(route)
	ctx.refresh(_p(Vector3(10.0, 0.0, 0.0), 450.0))
	assert_almost_eq(route.lag_to(ctx.perception), 450.0, 1e-3)
	ctx.refresh(_p(Vector3.ZERO, -1.0))
	assert_eq(route.lag_to(ctx.perception), INF, "not in sight")
	route.pace_id = 0
	assert_eq(route.lag_to(ctx.perception), 0.0, "a route without a pace ship is never behind")


# --- BehaviourFollowPath: scoring and leading ----------------------------------------------------------------------


func test_it_scores_only_while_it_has_a_route_to_fly() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := AiContext.new()
	ctx.refresh(_p(Vector3.ZERO))
	assert_eq(b.score(ctx), 0.0, "no route")
	ctx.route = _route([{}])
	assert_eq(b.score(ctx), BehaviourFollowPath.SCORE)
	assert_gt(BehaviourFollowPath.SCORE, BehaviourIdle.SCORE, "it outranks idling")


func test_it_leads_toward_the_waypoint_at_cruise_with_the_player_close() -> void:
	var b := BehaviourFollowPath.new()
	var route := _route([{}, {}])
	var ctx := _context(route)
	var cmd: PilotCommand = _think(b, ctx, _p(Vector3(0.0, 0.0, 0.0), 300.0, Vector3(0.0, 0.0, -60.0), Basis(Vector3.UP, 0.3)))
	assert_eq(b.state_name(), "lead")
	assert_true(b.has_desired_velocity, "the avoidance filter sees the wish")
	assert_almost_eq(b.desired_velocity, Vector3(0.0, 0.0, -60.0), Vector3.ONE * 1e-4)
	assert_gt(cmd.flight.rot.y, 0.0, "the nose, turned left, swings back right toward the waypoint")
	assert_false(cmd.flight.brake)
	assert_eq(b.target_id(), PilotBrain.TARGET_NONE)
	assert_eq(b.index, 0)


func test_it_slows_with_the_lag_and_waits_beyond_1600_m() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{}, {}]))
	_think(b, ctx, _p(Vector3.ZERO, 1050.0))
	assert_almost_eq(b.desired_velocity.length(), 30.0, 1e-3, "half cruise at 1 050 m")
	_think(b, ctx, _p(Vector3.ZERO, 1550.0))
	assert_almost_eq(b.desired_velocity.length(), 0.0, 1e-6, "no way on beyond 1 500 m")
	assert_eq(b.state_name(), "lead")
	var cmd: PilotCommand = _think(b, ctx, _p(Vector3.ZERO, 1700.0))
	assert_eq(b.state_name(), "wait")
	assert_true(cmd.flight.brake, "it brakes ...")
	assert_eq(b.target_id(), PACE_ID, "... facing the player (the brake faces the selected target)")
	_think(b, ctx, _p(Vector3.ZERO, 1000.0))
	assert_eq(b.state_name(), "wait", "1 000 m is not close enough")
	cmd = _think(b, ctx, _p(Vector3.ZERO, 790.0))
	assert_eq(b.state_name(), "lead", "it resumes inside 800 m")
	assert_false(cmd.flight.brake)
	assert_eq(b.target_id(), PilotBrain.TARGET_NONE)


func test_a_route_without_a_pace_ship_never_waits() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{}, {}], false, 0))
	_think(b, ctx, _p(Vector3.ZERO, -1.0))
	assert_eq(b.state_name(), "lead")
	assert_almost_eq(b.desired_velocity.length(), 60.0, 1e-3)


func test_it_visits_the_waypoints_in_order_and_holds_at_the_end() -> void:
	var b := BehaviourFollowPath.new()
	var route := _route([{}, {}, {}])
	var ctx := _context(route)
	_think(b, ctx, _p(Vector3(0.0, 0.0, -800.0)))
	assert_eq(b.index, 0, "200 m out is not there yet")
	_think(b, ctx, _p(Vector3(0.0, 0.0, -900.0)))
	assert_eq(b.index, 1, "arrived within 150 m: on to the next")
	assert_eq(b.visited, PackedInt32Array([0]))
	_think(b, ctx, _p(Vector3(0.0, 0.0, -1950.0)))
	var cmd: PilotCommand = _think(b, ctx, _p(Vector3(0.0, 0.0, -2950.0)))
	assert_eq(b.visited, PackedInt32Array([0, 1, 2]))
	assert_eq(b.state_name(), "done")
	assert_true(cmd.flight.brake, "the end of the route: it stops")
	assert_eq(b.score(ctx), 0.0, "and hands over (to idle)")


func test_a_looping_route_starts_again() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{}, {}], true))
	_think(b, ctx, _p(Vector3(0.0, 0.0, -1000.0)))
	_think(b, ctx, _p(Vector3(0.0, 0.0, -2000.0)))
	assert_eq(b.index, 0)
	assert_eq(b.state_name(), "lead")


# --- demos at waypoints --------------------------------------------------------------------------------------------


func test_a_demo_runs_at_its_waypoint_when_the_player_is_close() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{"demo": "roll"}, {}]))
	var cmd: PilotCommand = _think(b, ctx, _p(Vector3(0.0, 0.0, -950.0), 300.0, Vector3(0.0, 0.0, -60.0)))
	assert_eq(b.state_name(), "demo")
	assert_eq(b.manoeuvre.id, &"roll")
	assert_eq(cmd.flight.rot, Vector3(0.0, 0.0, 1.0), "the roll's command flies the ship")
	assert_eq(b.describe()["demo"], "roll")
	assert_eq(b.describe()["step"], "rolling")


func test_a_demo_waits_for_the_player_to_close_to_800_m() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{"demo": "roll"}, {}]))
	var cmd: PilotCommand = _think(b, ctx, _p(Vector3(0.0, 0.0, -950.0), 1000.0, Vector3(0.0, 0.0, -20.0)))
	assert_eq(b.state_name(), "wait", "the player would not see it from 1 000 m")
	assert_true(cmd.flight.brake)
	assert_eq(b.target_id(), PACE_ID)
	_think(b, ctx, _p(Vector3(0.0, 0.0, -1100.0), 700.0))
	assert_eq(b.state_name(), "demo", "at 700 m it shows the move, though it braked past the waypoint")
	assert_eq(b.index, 0)


func test_a_move_that_takes_speed_away_is_shown_from_cruise() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{"demo": "all_stop"}, {}]))
	var cmd: PilotCommand = _think(b, ctx, _p(Vector3(0.0, 0.0, -1000.0), 300.0, Vector3(0.0, 0.0, -5.0)))
	assert_eq(b.state_name(), "run_up", "at 5 m/s an all stop would show nothing")
	assert_almost_eq(b.desired_velocity, Vector3(0.0, 0.0, -60.0), Vector3.ONE * 1e-3, "cruise toward the next waypoint")
	assert_false(cmd.flight.brake)
	_think(b, ctx, _p(Vector3(0.0, 0.0, -1050.0), 300.0, Vector3(0.0, 0.0, -55.0)))
	assert_eq(b.state_name(), "demo", "from 90 % of cruise the move starts")
	assert_eq(b.manoeuvre.id, &"all_stop")


func test_after_a_demo_it_holds_then_goes_on_and_keeps_the_result() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{}, {"demo": "pod_turn", "hold_s": 0.5}, {}]))
	_think(b, ctx, _p(Vector3(0.0, 0.0, -1000.0)))
	assert_eq(b.index, 1)
	_think(b, ctx, _p(Vector3(0.0, 0.0, -2000.0), 300.0, Vector3(0.0, 0.0, -60.0)))
	assert_eq(b.state_name(), "demo")
	# The nose is now 35 degrees right of where it started: the pod turn's goal.
	var turned := Basis(Vector3.UP, deg_to_rad(-35.0))
	_think(b, ctx, _p(Vector3(0.0, 0.0, -2050.0), 300.0, Vector3(0.0, 0.0, -60.0), turned))
	assert_eq(b.state_name(), "hold")
	assert_eq(b.results.size(), 1)
	assert_eq(b.results[0]["demo"], "pod_turn")
	assert_eq(b.results[0]["index"], 1)
	assert_gt(float(b.results[0]["yaw_deg"]), 30.0)
	var cmd: PilotCommand = _think(b, ctx, _p(Vector3(0.0, 0.0, -2060.0)))
	assert_true(cmd.flight.brake, "holding")
	for i: int in roundi(0.5 / DT) + 1:
		_think(b, ctx, _p(Vector3(0.0, 0.0, -2060.0)))
	assert_eq(b.state_name(), "lead")
	assert_eq(b.index, 2)


func test_a_demo_interrupted_by_another_behaviour_starts_afresh() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{"demo": "roll"}, {}]))
	_think(b, ctx, _p(Vector3(0.0, 0.0, -950.0)))
	var first: Manoeuvre = b.manoeuvre
	b.enter()
	assert_ne(b.manoeuvre, first)
	assert_eq(b.manoeuvre.id, &"roll")


# --- the HUD and the console ---------------------------------------------------------------------------------------


func test_the_status_line_names_the_waypoint_and_the_next_demo() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{}, {"demo": "roll"}, {}, {}, {}, {}]))
	_think(b, ctx, _p(Vector3(0.0, 0.0, -500.0)))
	assert_eq(b.status_line("INSTRUCTOR"), "FOLLOW INSTRUCTOR — NAV 1/6")
	_think(b, ctx, _p(Vector3(0.0, 0.0, -1000.0)))
	assert_eq(b.status_line("INSTRUCTOR"), "FOLLOW INSTRUCTOR — NAV 2/6 — NEXT: ROLL")
	_think(b, ctx, _p(Vector3(0.0, 0.0, -1000.0), 1700.0))
	assert_eq(b.status_line("INSTRUCTOR"), "CLOSE UP ON INSTRUCTOR — NAV 2/6 — NEXT: ROLL")
	_think(b, ctx, _p(Vector3(0.0, 0.0, -2000.0)))
	assert_eq(b.status_line("INSTRUCTOR"), "WATCH INSTRUCTOR — NAV 2/6 — ROLL")
	assert_eq(b.waypoint_label(), "NAV 2")


func test_describe_and_the_console_fields() -> void:
	var b := BehaviourFollowPath.new()
	var route := _route([{}, {"demo": "strafe_box"}])
	var ctx := _context(route)
	_think(b, ctx, _p(Vector3(0.0, 0.0, -1000.0), 420.0))
	var d: Dictionary = b.describe()
	assert_eq(d["state"], "lead")
	assert_eq(d["nav"], "NAV 2/2")
	assert_almost_eq(float(d["lag_m"]), 420.0, 1.0)
	assert_eq(d["demo"], "strafe_box")
	assert_eq(b.nav_number(), 2, "1-based, as the HUD")
	assert_eq(b.demo_name(), "strafe_box")


func test_reset_starts_the_route_over() -> void:
	var b := BehaviourFollowPath.new()
	var ctx := _context(_route([{}, {}]))
	_think(b, ctx, _p(Vector3(0.0, 0.0, -1000.0)))
	assert_eq(b.index, 1)
	b.reset()
	assert_eq(b.index, 0)
	assert_eq(b.state_name(), "lead")
	assert_eq(b.visited.size(), 0)


# --- on an AiPilot ---------------------------------------------------------------------------------------------------


func test_attach_gives_the_instructor_its_route_once() -> void:
	var pilot := AiPilot.new(AiProfile.load_named(&"instructor"), 3)
	var route := _route([{}, {}])
	var b: BehaviourFollowPath = BehaviourFollowPath.attach(pilot, route)
	assert_eq(pilot.context.route, route)
	assert_eq(pilot.behaviour(&"follow_path"), b)
	assert_eq(BehaviourFollowPath.attach(pilot, route), b, "a second attach reuses it")
	assert_eq(pilot.behaviours.size(), 5)
	assert_eq(AiProfile.load_named(&"instructor").weight(&"follow_path"), 1.0, "the instructor profile weighs it")
	var cmd: PilotCommand = pilot.think(_p(Vector3.ZERO), DT)
	assert_eq(pilot.current.id, &"follow_path", "it leads rather than idles")
	assert_true(pilot.has_desired_velocity)
	assert_false(cmd.combat.fire)
	assert_eq(pilot.describe()["behaviour"], "follow_path")
