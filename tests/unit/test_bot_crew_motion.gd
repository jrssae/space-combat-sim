extends GutTest
## `BotCrewMotion` (M7-T35): a crew bot flies its trip smoothly, rides the turning drum without moving on it, gets on at the drum
## angle it is sent to and off at its hold point, meets the moving jumpgate and turns for home when called.

const DT: float = 1.0 / 60.0
const SPIN: float = 0.148
const DOCK := Vector3(0, 339, -3534)

var frames: BotFrames
var m: BotCrewMotion


func before_each() -> void:
	frames = BotFrames.new()
	frames.pivot = Vector3(0, 0, -1000)
	frames.spin_rate = SPIN
	m = BotCrewMotion.new()
	m.setup(frames, DOCK, 4.0, 20.0)


func _tick(seconds: float, until: Callable = Callable()) -> void:
	for i: int in int(seconds / DT):
		frames.drum_angle = fposmod(frames.drum_angle + frames.spin_rate * DT, TAU)
		m.step(DT, false)
		if until.is_valid() and until.call():
			return


func _route(points: Array[Vector3]) -> BotRoute:
	return BotRoute.from_corners(PackedVector3Array(points), 20.0)


func _kind() -> int:
	return int(m.current().get("kind", -1))


# Out from under the drum at station z -1000 onto it at radius 355, to drum angle `psi` (NAN: anywhere), and a long stop there.
func _drum_trip(psi: float) -> BotTrip:
	var out: Array[Dictionary] = [
		BotTrip.fly(_route([Vector3(0, -500, -1000), Vector3(0, -355, -1000)]), BotTrip.Frame.STATION, 25.0),
		BotTrip.spin_up(355.0, -1000.0, psi)]
	return BotTrip.symmetric("drum", out, BotTrip.hold(600.0))


func test_a_docked_bot_is_hidden_at_the_bay() -> void:
	assert_true(m.is_docked())
	assert_false(m.is_visible())
	m.step(DT, false)
	assert_eq(m.position, DOCK)


func test_it_flies_out_and_back_smoothly_and_docks() -> void:
	var a := Vector3(0, 339, -3534)
	var b := Vector3(0, 339, -4250)
	var out: Array[Dictionary] = [BotTrip.fly(_route([a, b]), BotTrip.Frame.STATION, 25.0)]
	m.start(BotTrip.symmetric("line", out, BotTrip.hold(3.0)))
	assert_true(m.is_visible())
	var last: Vector3 = m.position
	var top: float = 0.0
	var reached: bool = false
	for i: int in int(200.0 / DT):
		m.step(DT, false)
		top = maxf(top, m.speed_mps)
		assert_lt(m.position.distance_to(last), 25.0 * DT + 0.05, "never faster than its cruise")
		last = m.position
		reached = reached or m.position.distance_to(b) < 0.5
		if m.is_docked():
			break
	assert_true(reached, "it got to the far end")
	assert_true(m.is_docked(), "and home again")
	assert_between(top, 20.0, 25.0, "at about its cruise on the long leg")


func test_on_the_drum_it_stays_put_on_the_hull_while_the_drum_turns() -> void:
	m.start(_drum_trip(NAN))
	_tick(120.0, func() -> bool: return _kind() == BotTrip.Kind.HOLD)
	assert_eq(_kind(), BotTrip.Kind.HOLD, "on the drum")
	var on_hull: Vector3 = frames.station_to_drum(m.position)
	var station_before: Vector3 = m.position
	for k: int in 3:
		_tick(7.0)
		assert_almost_eq(frames.station_to_drum(m.position), on_hull, Vector3.ONE * 1e-2, "the same spot on the drum")
	assert_gt(m.position.distance_to(station_before), 100.0, "carried round with the drum in the station's frame")
	assert_almost_eq(Vector2(on_hull.x, on_hull.y).length(), 355.0, 1e-2, "at its riding radius")


func test_it_lands_at_the_drum_angle_it_was_sent_to_without_a_jump() -> void:
	var psi: float = 1.0
	frames.drum_angle = 2.5
	m.start(_drum_trip(psi))
	m.step(DT, false)
	var last: Vector3 = m.position
	var jump: float = 0.0
	for i: int in int(200.0 / DT):
		frames.drum_angle = fposmod(frames.drum_angle + SPIN * DT, TAU)
		m.step(DT, false)
		jump = maxf(jump, m.position.distance_to(last))
		last = m.position
		if _kind() == BotTrip.Kind.HOLD:
			break
	var on_hull: Vector3 = frames.station_to_drum(m.position)
	assert_almost_eq(atan2(on_hull.y, on_hull.x), psi, 0.01, "on the mount's angle")
	assert_lt(jump, (SPIN * 355.0 + 2.0) * DT, "never faster than the drum's skin while getting on")


func test_getting_off_ends_at_rest_at_the_hold_point() -> void:
	m.start(_drum_trip(NAN))
	_tick(120.0, func() -> bool: return _kind() == BotTrip.Kind.HOLD)
	m.recall()
	_tick(120.0, func() -> bool: return _kind() == BotTrip.Kind.FLY)
	var hold: Vector3 = frames.on_circle(355.0, -1000.0, frames.hold_angle)
	assert_almost_eq(m.position, hold, Vector3.ONE * 0.5, "off the drum under it, where it got on")
	_tick(200.0, func() -> bool: return m.is_docked())
	assert_true(m.is_docked())


func test_spin_held_still_it_still_gets_on_and_off() -> void:
	frames.spin_rate = 0.0
	m.start(_drum_trip(0.7))
	_tick(120.0, func() -> bool: return _kind() == BotTrip.Kind.HOLD)
	var on_hull: Vector3 = frames.station_to_drum(m.position)
	assert_almost_eq(atan2(on_hull.y, on_hull.x), 0.7, 0.01)


func test_it_meets_the_jumpgate_where_it_is_now() -> void:
	frames.has_gate = true
	frames.gate = Transform3D(Basis.IDENTITY, Vector3(0, 0, -20000))
	var depart := Vector3(0, 339, -4800)
	var out: Array[Dictionary] = [BotTrip.transit(depart, BotTrip.Frame.STATION, Vector3(0, 875, -150), BotTrip.Frame.GATE, 250.0, 10.0)]
	m.start(BotTrip.symmetric("gate", out, BotTrip.hold(5.0)))
	for i: int in int(300.0 / DT):
		frames.gate.origin += Vector3(4.5, 0, 0) * DT  # the gate drifts against the station
		m.step(DT, false)
		if _kind() == BotTrip.Kind.HOLD:
			break
	assert_eq(_kind(), BotTrip.Kind.HOLD, "it arrived")
	assert_almost_eq(m.position, frames.gate * Vector3(0, 875, -150), Vector3.ONE * 0.5, "at the gate's point as the gate is now")


func test_called_home_halfway_out_it_turns_round() -> void:
	var a := Vector3(0, 339, -3534)
	var b := Vector3(0, 339, -5534)
	var out: Array[Dictionary] = [BotTrip.fly(_route([a, b]), BotTrip.Frame.STATION, 25.0)]
	m.start(BotTrip.symmetric("line", out, BotTrip.hold(3.0)))
	_tick(30.0)
	var turned_at: float = m.position.z
	m.recall()
	assert_true(m.homeward())
	var furthest: float = turned_at
	for i: int in int(300.0 / DT):
		m.step(DT, false)
		furthest = minf(furthest, m.position.z) if not m.is_docked() else furthest
		if m.is_docked():
			break
	assert_true(m.is_docked(), "back in the bay")
	assert_gt(furthest, turned_at - 15.0, "it never went on to the far end")
