extends GutTest
## The player's wing following the player close past Babylon 5 (M7-T38): the maintainer lost all three wingmen to the
## station flying the showcase, then two of three threading the Cobra arms and the fins. A leader flown on a fixed track
## close past the hull (down the drum, over the bow and the spine, round and between the Cobra arms as they come round,
## along and through the fins) at a pilot's speeds and turns, with ALPHA 2 to 4 on their finger-four slots, some of them
## inside the hull as the leader passes, and then on past the hull while the wing rejoins: no wingman may strike the
## station or another ship. Flown headless through the native core with the physics rate and the time scale raised.

const ALLY: StringName = &"starfury_ally"
const SPEED_UP: float = 8.0
## The finger-four's slots (`Formation`, 40 m spacing), ALPHA 2 to 4.
const SLOTS: Array[Vector3] = [Vector3(-40.0, 0.0, 40.0), Vector3(40.0, 0.0, 40.0), Vector3(80.0, 0.0, 80.0)]
## The least a wingman's centre may come to the collision hulls, m: a Starfury's radius (10 m) and a little room.
const CLEAR_M: float = 15.0
## How long the leader flies on straight past its track's end while the wing comes back to its slots, s: a wing left behind
## rejoins at its far closing speed, and its way back may cross the station.
const REJOIN_S: float = 40.0
## How long the threads test flies the dive: into the arms and out (100 m/s from 900 m out).
const DIGEST_TICKS: int = 780

## The wing's slots this test flies: the finger-four, or Alpha's eleven (`_alpha`).
var _slots: Array[Vector3] = SLOTS
## Whether the leader stops at its track's end instead of flying on (M7-T76: a leader that runs into the hull), and then
## bounces back off it, tumbling.
var _hold: bool = false
var _bounce: bool = false
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()  # two minutes of flying


func before_each() -> void:
	_slots = SLOTS
	_hold = false
	_bounce = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func test_the_wing_follows_the_leader_down_the_drum_without_touching_the_station() -> void:
	# Down the drum's port side 75 m off its widest band (425 m out): the right-hand slots lie inside the hull.
	await _fly([Vector3(-520.0, 0.0, -4200.0), Vector3(-500.0, 0.0, -2600.0), Vector3(-500.0, 0.0, -1000.0),
			Vector3(-800.0, 0.0, -100.0), Vector3(-1200.0, 0.0, 800.0)], 120.0)


func test_the_wing_follows_the_leader_over_the_bow_and_the_spine_without_touching_the_station() -> void:
	# Over the bow's prongs and along the spine, rolled so the right-hand slots hang below toward the hull.
	await _fly([Vector3(0.0, 480.0, -5000.0), Vector3(0.0, 470.0, -4100.0), Vector3(0.0, 560.0, -3200.0),
			Vector3(0.0, 660.0, -1800.0), Vector3(0.0, 640.0, -400.0), Vector3(-300.0, 1000.0, -200.0),
			Vector3(-500.0, 1800.0, -100.0)], 120.0, Vector3.LEFT)


func test_the_wing_follows_the_leader_round_the_cobra_arms_without_touching_the_station() -> void:
	# Round under the drum's waist 58 m outside the Cobra arms' tips (242 m out, coming round at 36 m/s), the leader's top
	# toward the bow so its right-hand slots lie inward, ALPHA 4's among the arms.
	var path: Array[Vector3] = [Vector3(-300.0, 700.0, -2790.0), Vector3(-300.0, 300.0, -2790.0)]
	for k: int in 13:
		var a: float = PI + PI * float(k) / 12.0
		path.append(Vector3(cos(a) * 300.0, sin(a) * 300.0, -2790.0))
	path.append_array([Vector3(300.0, 300.0, -2790.0), Vector3(300.0, 700.0, -2790.0)])
	await _fly(path, 100.0, Vector3.FORWARD)


func test_the_wing_follows_the_leader_along_the_fins_without_touching_the_station() -> void:
	# Along the port fins 85 m out (thin vanes 4 m through), rolled so the right-hand slots reach in to the vanes.
	await _fly([Vector3(-620.0, 600.0, -1200.0), Vector3(-620.0, 600.0, 0.0), Vector3(-620.0, 600.0, 1600.0),
			Vector3(-900.0, 600.0, 2600.0)], 120.0, Vector3.DOWN)


func test_the_wing_keeps_out_of_the_cobra_arms_when_the_leader_dives_between_them() -> void:
	# The leader (a ghost: nothing strikes it) dives at the drum's waist between two Cobra arms, down to 180 m from the axis
	# (the arms' decks are 196 to 242 m out), and runs round under the drum among them: the slots trail it through the
	# ring the arms sweep at 36 m/s, and the wing must leave them to keep clear.
	await _fly(_dive(), 100.0, Vector3.UP, true)


func test_the_dive_is_the_same_threaded_and_delayed_and_with_one_thread_and_six() -> void:
	# The dive among the arms, where the wing pushes out of the swept rings and pulls out short of them: the rows and the
	# commands must be the same bits every tick with the AI job threaded and delayed, and with one thread and six.
	var delayed: Dictionary = await _digests(&"delayed", 6)
	if delayed.is_empty():
		pending("the babylon5_station asset is not generated")
		return
	var threaded: Dictionary = await _digests(&"threaded", 6)
	var one: Dictionary = await _digests(&"threaded", 1)
	assert_gt(int(delayed["avoiding"]), 0, "the wing kept off the arms (%d ship-ticks)" % int(delayed["avoiding"]))
	for key: String in ["rows", "commands"]:
		var first: int = _first_difference(delayed[key], threaded[key])
		assert_eq(first, -1, "%s: threaded against delayed, the same bits (first difference at tick %d)" % [key, first])
		first = _first_difference(one[key], threaded[key])
		assert_eq(first, -1, "%s: one thread against six, the same bits (first difference at tick %d)" % [key, first])
	assert_eq(threaded["avoiding"], delayed["avoiding"])


func test_the_wing_threads_the_cobra_arms_three_times_behind_the_leader() -> void:
	# Three laps of a racetrack under the drum, each pass a chord 205 m from the axis through the gap between two Cobra arms
	# as it comes round (the arms 196 to 246 m out, their tips at 36 m/s), timed so the leader threads the gap's middle;
	# the leader (a ghost) flies with its top away from the drum at 120 m/s, turning at 24 m/s^2 as a Starfury can.
	await _fly(_threading, 120.0, Vector3.ZERO, true)


func test_the_wing_threads_the_cobra_arms_three_times_against_their_turn() -> void:
	# The same three laps flown the other way round, against the arms' turn, so a gap closes on the wing twice as fast;
	# the chords run 225 m from the axis, where the leader's track still fits the gap.
	await _fly(func(station: Station, speed: float) -> Array[Vector3]: return _threading(station, speed, true), 120.0,
			Vector3.ZERO, true)


func test_the_wing_follows_the_leader_through_both_fin_sets_twice() -> void:
	# Across the station 700 m up through the gaps between the fins (vanes 4 m thick, 190 m apart), port to starboard
	# between the first and second vanes, back round over the bow side, and across again between the second and third: the
	# outer slots lie by a vane. Turns a Starfury can fly at 100 m/s (22 and 15 m/s^2).
	var y: float = 700.0
	var path: Array[Vector3] = [Vector3(-1500.0, y, 585.0)]
	_racetrack_leg(path, Vector3(-1500.0, y, 585.0), Vector3(1100.0, y, 585.0))
	_turn(path, Vector3(1100.0, y, 135.0), Vector3(1100.0, y, 585.0), Vector3(1.0, 0.0, 0.0), PI)
	_racetrack_leg(path, Vector3(1100.0, y, -315.0), Vector3(-1100.0, y, -315.0))
	_turn(path, Vector3(-1100.0, y, 355.5), Vector3(-1100.0, y, -315.0), Vector3(-1.0, 0.0, 0.0), PI)
	_racetrack_leg(path, Vector3(-1100.0, y, 1026.0), Vector3(1500.0, y, 1026.0))
	await _fly(path, 100.0, Vector3.UP, true)


func test_the_wing_holds_off_when_the_leader_runs_into_the_drum() -> void:
	# M7-T76: the leader (a ghost) flies at the drum's side at 120 m/s and stops 20 m inside its skin; the wing, trailing
	# it, must hold off or break away rather than follow it in.
	_hold = true
	await _fly(func(station: Station, _speed: float) -> Array[Vector3]:
		return _into(station, Vector3(-2000.0, 0.0, -2000.0), Vector3.RIGHT), 120.0, Vector3.UP, true)


func test_alpha_holds_off_when_the_leader_glances_into_the_drum() -> void:
	# Alpha's eleven on the V (M7-T74) behind a leader (a ghost) at 200 m/s closing on the drum at 11 degrees, into its
	# flank and on inside the hull to a stop, then backing out tumbling. On HEAD before M7-T76 ALPHA 6 and 9 rammed each
	# other at 48 m/s pulling out of the hull's way, and both were lost.
	_slots = _alpha()
	_hold = true
	_bounce = true
	await _fly(_glance(), 200.0, Vector3.UP, true)


# The glancing track: from 1.1 km off the drum's port flank ahead of the bow end, 5 km on at 11 degrees to the axis, in
# through the drum's flank to a stop deep inside the station.
static func _glance() -> Array[Vector3]:
	var from := Vector3(-1000.0, 0.0, -5200.0)
	var to: Vector3 = from + Vector3(600.0, 0.0, 3200.0).normalized() * 4998.0
	return [from, from.lerp(to, 0.5), to]


# Alpha's eleven slots (the balanced V, M7-T74).
static func _alpha() -> Array[Vector3]:
	var formation := Formation.new()
	var out: Array[Vector3] = []
	for k: int in range(1, 12):
		out.append(formation.offset(k, 11))
	return out


# A straight track from `from` along `direction` to 20 m inside the station's collision hulls.
static func _into(station: Station, from: Vector3, direction: Vector3) -> Array[Vector3]:
	var at: Vector3 = from
	while not _touches(station, at, 1.0) and at.distance_to(from) < 5000.0:
		at += direction * 5.0
	return [from, from.lerp(at, 0.5), at + direction * 20.0]


## The middle of the groove between the Cobra arms along the axis, station frame (the drum's waist, 280 m long).
const ARMS_Z: float = -2840.0
## How far from the axis the leader threads the arms, and its racetrack's turn radius, m.
const THREAD_R: float = 205.0
const TURN_R: float = 600.0


# The leader's racetrack under the drum at `speed` (see the test), turned so each pass meets a gap's middle: a lap is four
# of the arms' passing times long, and the first pass is timed from the drum's angle now. `against` flies it against the
# arms' turn.
static func _threading(station: Station, speed: float, against: bool = false) -> Array[Vector3]:
	var w: float = station.spin.rate_rad_s
	var period: float = 0.5 * PI / w
	var half: float = (4.0 * period * speed - TAU * TURN_R) / 4.0
	var t_mid: float = (2.0 * half + PI * TURN_R) / speed
	# A gap's middle lies 45 degrees on from an arm; the first pass is under the drum.
	var gap: float = station.drum_angle + w * t_mid + 0.25 * PI
	var phi: float = gap + 0.5 * PI * roundf((-0.5 * PI - gap) / (0.5 * PI))
	var u := Vector3(cos(phi), sin(phi), 0.0)
	var v := Vector3(-sin(phi), cos(phi), 0.0) * (-1.0 if against else 1.0)
	var z := Vector3(0.0, 0.0, ARMS_Z)
	var thread_r: float = THREAD_R + (20.0 if against else 0.0)
	var out: float = thread_r + 2.0 * TURN_R
	var path: Array[Vector3] = [z + u * out]
	for lap: int in 3:
		_racetrack_leg(path, z + u * out, z + u * out - v * half)
		_turn(path, z + u * (thread_r + TURN_R) - v * half, z + u * out - v * half, -v, PI)
		_racetrack_leg(path, z + u * thread_r - v * half, z + u * thread_r + v * half)
		_turn(path, z + u * (thread_r + TURN_R) + v * half, z + u * thread_r + v * half, v, PI)
	_racetrack_leg(path, z + u * out + v * half, z + u * out)
	return path


# Appends points every 25 m along the straight from `a` to `b` (not `a` itself).
static func _racetrack_leg(path: Array[Vector3], a: Vector3, b: Vector3) -> void:
	var n: int = maxi(1, ceili(a.distance_to(b) / 25.0))
	for k: int in n:
		path.append(a.lerp(b, float(k + 1) / float(n)))


# Appends points every 25 m round the arc about `centre` from `from`, setting off along `heading`, through `angle` rad.
static func _turn(path: Array[Vector3], centre: Vector3, from: Vector3, heading: Vector3, angle: float) -> void:
	var arm: Vector3 = from - centre
	var axis: Vector3 = arm.cross(heading).normalized()
	var n: int = maxi(2, ceili(arm.length() * angle / 25.0))
	for k: int in n:
		path.append(centre + arm.rotated(axis, angle * float(k + 1) / float(n)))


# The leader's way in the dive among the Cobra arms (station frame).
static func _dive() -> Array[Vector3]:
	var path: Array[Vector3] = [Vector3(-900.0, 0.0, -2830.0), Vector3(-450.0, 0.0, -2810.0)]
	for k: int in 7:
		var a: float = PI + 0.5 * PI * float(k) / 6.0
		path.append(Vector3(cos(a) * 180.0, sin(a) * 180.0, -2790.0))
	path.append_array([Vector3(0.0, -450.0, -2790.0), Vector3(0.0, -900.0, -2790.0)])
	return path


# Flies the leader along the spline through `path` (station frame; or a Callable making it from the station and the speed)
# at `speed`, its top toward `up` (away from the station's axis when zero), with the wing on its slots, and asserts no
# wingman touched the station. A `ghost` leader strikes nothing and may fly through the hull.
func _fly(path: Variant, speed: float, up: Vector3 = Vector3.UP, ghost: bool = false) -> void:
	var f: Dictionary = await _launch(path, speed, up, ghost, &"threaded", 6)
	if f.is_empty():
		pending("the babylon5_station asset is not generated")
		return
	var scene: TurretScene = f["scene"]
	var station: Station = f["station"]
	var leader: Combatant = f["leader"]
	var wing: Array[Combatant] = f["wing"]
	var rams: Array[int] = f["rams"]
	var total_s: float = f["total_s"]
	var nearest: Array[float] = []
	var nearest_at: Array[String] = []
	nearest.resize(wing.size())
	nearest.fill(INF)
	nearest_at.resize(wing.size())
	var leader_nearest: float = INF
	_speed_up()
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < total_s + REJOIN_S:
		await get_tree().physics_frame
		var t: float = SimClock.now() - t0
		var at: Vector3 = _lead(f, t)
		leader_nearest = minf(leader_nearest, _hull_skin(scene, station, at))
		for i: int in wing.size():
			if wing[i].damageable.hull.destroyed:
				continue
			var p: Vector3 = wing[i].ship.global_position
			var d: float = _hull_skin(scene, station, p)
			if d < nearest[i]:
				nearest[i] = d
				var slot: Vector3 = Formation.slot_point(at, -leader.ship.global_basis.z, leader.ship.global_basis.y, _slots[i])
				nearest_at[i] = "%.1f s at (%.0f, %.0f, %.0f), %.0f m/s, %.0f m from its slot" % [t, p.x, p.y, p.z,
						wing[i].ship.linear_velocity.length(), p.distance_to(slot)]
	after_each()
	var lost: int = 0
	var off_slot := PackedStringArray()
	for i: int in wing.size():
		lost += 1 if wing[i].damageable.hull.destroyed else 0
		off_slot.append("%.0f" % wing[i].ship.global_position.distance_to(Formation.slot_point(leader.ship.global_position,
				-leader.ship.global_basis.z, leader.ship.global_basis.y, _slots[i])))
	gut.p("  at the end the wing is %s m from its slots" % " / ".join(off_slot))
	gut.p("wing past the station at %.0f m/s: rams %d, lost %d, leader at least %.0f m off, %.0f s" % [speed, rams[0], lost,
			leader_nearest, total_s])
	for i: int in wing.size():
		gut.p("  ALPHA %d at least %.0f m off: %s" % [i + 2, nearest[i], nearest_at[i]])
	if not ghost:
		assert_gt(leader_nearest, 30.0, "the leader's track stays off the hull")
	assert_eq(rams[0], 0, "no wingman rammed the station or a ship")
	assert_eq(lost, 0, "the whole wing came through")
	for i: int in wing.size():
		assert_gt(nearest[i], CLEAR_M, "ALPHA %d kept off the hull" % (i + 2))
	await scene.free_scene(get_tree())


# The dive flown `DIGEST_TICKS` ticks with the step `mode` and `threads` threads: per tick the rows' and commands' digests,
# and how many ship-ticks the wing spent avoiding. Empty without the asset.
func _digests(mode: StringName, threads: int) -> Dictionary:
	var f: Dictionary = await _launch(_dive(), 100.0, Vector3.UP, true, mode, threads)
	if f.is_empty():
		return {}
	var scene: TurretScene = f["scene"]
	var wing: Array[Combatant] = f["wing"]
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var avoiding: int = 0
	_speed_up()
	var t0: float = SimClock.now()
	for k: int in DIGEST_TICKS:
		await get_tree().physics_frame
		_lead(f, SimClock.now() - t0)
		rows.append(int(scene.sim.core.rows_digest()))
		commands.append(int(scene.sim.core.commands_digest()))
		for c: Combatant in wing:
			var driver := c.driver as AiPilotDriver
			avoiding += 1 if driver != null and driver.avoiding else 0
	after_each()
	var out: Dictionary = {"rows": rows, "commands": commands, "avoiding": avoiding}
	await scene.free_scene(get_tree())
	return out


# A scene with the station, the leader at the start of the spline through `path` (flown at `speed`, its top toward `up`, a
# `ghost` striking nothing) and the wing on its slots, stepped with `mode` and `threads` threads: a Dictionary of the scene,
# station, leader, wing, rams counter, track and its length in seconds. Empty without the asset.
func _launch(path_of: Variant, speed: float, up: Vector3, ghost: bool, mode: StringName, threads: int) -> Dictionary:
	var scene: TurretScene = await _scene(mode, threads)
	if scene == null:
		return {}
	var path: Array[Vector3] = []
	path.assign((path_of as Callable).call(scene.get_meta(&"station"), speed) if path_of is Callable else path_of)
	var track := PackedVector3Array()
	var lengths := PackedFloat64Array()
	_sample(path, track, lengths)
	var start: Vector3 = track[0]
	var heading: Vector3 = (track[1] - track[0]).normalized()
	var basis := Basis.looking_at(heading, _up_at(up, start, heading))
	var leader: Combatant = scene.ship(ALLY, Factions.EARTH_ALLIANCE, "ALPHA 1", start, {}, 1, false, basis)
	if ghost:
		leader.ship.collision_layer = 0
		leader.ship.collision_mask = 0
	var wing: Array[Combatant] = []
	var rams: Array[int] = [0]
	for i: int in _slots.size():
		var c: Combatant = scene.ship(ALLY, Factions.EARTH_ALLIANCE, "ALPHA %d" % (i + 2),
				Formation.slot_point(start, heading, basis.y, _slots[i]), {"type": "ai", "profile": "ally_starfury"}, 80 + i,
				false, basis)
		var pilot: AiPilot = c.driver.brain as AiPilot
		pilot.add_behaviour(BehaviourFormation.new(pilot.profile))  # as `WingDirector.add_member` briefs a wingman
		pilot.add_behaviour(BehaviourRally.new(pilot.profile))
		var callsign: String = c.display_name
		c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
			if info != null and info.cause == HitInfo.CAUSE_RAM:
				var other: Object = instance_from_id(info.shooter_id) if info.shooter_id != 0 else null
				var against: String = String(other.name) if other is Node else str(info.shooter_id)
				rams[0] += 1
				gut.p("  ram: %s against %s at %s, %.0f m/s" % [callsign, against, str(info.point.round()),
						info.relative_speed_mps]))
		c.ship.linear_velocity = heading * speed
		wing.append(c)
	leader.ship.linear_velocity = heading * speed
	_add_rams(scene)
	scene.attach()
	_brief(wing, leader, _slots)
	return {"scene": scene, "station": scene.get_meta(&"station"), "leader": leader, "wing": wing, "rams": rams,
			"track": track, "lengths": lengths, "speed": speed, "up": up, "total_s": lengths[lengths.size() - 1] / speed,
			"hold": _hold, "bounce": _bounce}


# Puts flight `f`'s leader where its track is `t` seconds in, moving along it, and tells the wing where it is, as
# `WingDirector.refresh` does each tick. Returns the leader's position.
static func _lead(f: Dictionary, t: float) -> Vector3:
	var leader: Combatant = f["leader"]
	var track: PackedVector3Array = f["track"]
	var lengths: PackedFloat64Array = f["lengths"]
	var speed: float = f["speed"]
	var up: Vector3 = f["up"]
	var scene: TurretScene = f["scene"]
	var at: Vector3 = leader.ship.global_position
	var end: float = lengths[lengths.size() - 1] if f["hold"] else INF
	var since_end: float = t - end / speed
	if f["bounce"] and since_end > 0.0:
		_bounce_off(f, since_end, at)
		return at
	var want: Vector3 = _along(track, lengths, minf(t * speed, end))
	var velocity: Vector3 = (_along(track, lengths, minf((t + 0.1) * speed, end)) - want) / 0.1
	leader.ship.linear_velocity = velocity + (want - at) * 2.0
	leader.ship.angular_velocity = Vector3.ZERO
	if velocity.length_squared() > 1.0:
		var forward: Vector3 = velocity.normalized()
		leader.ship.global_basis = Basis.looking_at(forward, _up_at(up, at, forward))
	for c: Combatant in f["wing"]:
		var ctx: AiContext = (c.driver.brain as AiPilot).context
		ctx.leader_link_position = scene.world.to_universe(at)
		ctx.leader_link_velocity = velocity
	return at


# Flight `f`'s leader `since_end` seconds after its track's end, inside the hull: backing off at 0.3 of its speed for
# 3 s, tumbling for 4 s, then at rest; and tells the wing.
static func _bounce_off(f: Dictionary, since_end: float, at: Vector3) -> void:
	var leader: Combatant = f["leader"]
	var track: PackedVector3Array = f["track"]
	var scene: TurretScene = f["scene"]
	if not f.has("struck_basis"):
		f["struck_basis"] = leader.ship.global_basis
	var last: Vector3 = (track[track.size() - 1] - track[track.size() - 2]).normalized()
	var velocity: Vector3 = -last * 0.3 * float(f["speed"]) if since_end < 3.0 else Vector3.ZERO
	leader.ship.linear_velocity = velocity
	leader.ship.angular_velocity = Vector3.ZERO
	var struck: Basis = f["struck_basis"]
	leader.ship.global_basis = struck.rotated(Vector3(1.0, 1.0, 0.3).normalized(), 1.5 * minf(since_end, 4.0)).orthonormalized()
	for c: Combatant in f["wing"]:
		var ctx: AiContext = (c.driver.brain as AiPilot).context
		ctx.leader_link_position = scene.world.to_universe(at)
		ctx.leader_link_velocity = velocity


# The leader's top at `at` flying along `forward`: `up`, or away from the station's axis when `up` is zero; never along
# `forward`.
static func _up_at(up: Vector3, at: Vector3, forward: Vector3) -> Vector3:
	var top: Vector3 = up if up != Vector3.ZERO else Vector3(at.x, at.y, 0.0).normalized()
	return top if absf(forward.normalized().dot(top)) < 0.95 else Vector3.FORWARD


# Puts the wing on the leader's slots under COVER ME, as `WingDirector.refresh` briefs a player's wing.
static func _brief(wing: Array[Combatant], leader: Combatant, slots: Array[Vector3]) -> void:
	var ids := PackedInt64Array([leader.targetable.get_instance_id()])
	for c: Combatant in wing:
		ids.append(c.targetable.get_instance_id())
	for i: int in wing.size():
		var own: int = wing[i].targetable.get_instance_id()
		var mates := PackedInt64Array()
		for id: int in ids:
			if id != own:
				mates.append(id)
		var ctx: AiContext = (wing[i].driver.brain as AiPilot).context
		ctx.wing_ids = mates
		ctx.order = AiContext.Order.COVER_ME
		ctx.leader_id = leader.targetable.get_instance_id()
		ctx.has_slot = true
		ctx.slot_offset = slots[i]


# The Catmull-Rom spline through `path`, densely sampled into `track` with the length flown to each sample in `lengths`.
static func _sample(path: Array[Vector3], track: PackedVector3Array, lengths: PackedFloat64Array) -> void:
	var run: float = 0.0
	for k: int in path.size() - 1:
		var p0: Vector3 = path[maxi(k - 1, 0)]
		var p3: Vector3 = path[mini(k + 2, path.size() - 1)]
		for n: int in 40:
			var q: Vector3 = path[k].cubic_interpolate(path[k + 1], p0, p3, float(n) / 40.0)
			if not track.is_empty():
				run += track[track.size() - 1].distance_to(q)
			track.append(q)
			lengths.append(run)
	run += track[track.size() - 1].distance_to(path[path.size() - 1])
	track.append(path[path.size() - 1])
	lengths.append(run)


# The point `s` metres along the sampled track (beyond its end, on along its last straight).
static func _along(track: PackedVector3Array, lengths: PackedFloat64Array, s: float) -> Vector3:
	var k: int = lengths.bsearch(s)
	if k <= 0:
		return track[0]
	var last: int = track.size() - 1
	if k >= lengths.size():
		return track[last] + (track[last] - track[last - 1]).normalized() * (s - lengths[last])
	var span: float = lengths[k] - lengths[k - 1]
	return track[k - 1].lerp(track[k], (s - lengths[k - 1]) / span if span > 1e-6 else 1.0)


# How far `at` is from the station's collision hulls (what a ship strikes), to 0.5 m, or the core's box distance where
# that is beyond `cap` (its boxes hold the hulls, so a hull is never nearer than its box).
static func _hull_skin(scene: TurretScene, station: Station, at: Vector3, cap: float = 60.0) -> float:
	var boxes: float = minf(scene.sim.core.surface_distance(station.get_instance_id(), at),
			scene.sim.core.surface_distance(station.drum_body.get_instance_id(), at))
	if boxes >= cap or not _touches(station, at, cap):
		return maxf(boxes, cap)
	var lo: float = boxes
	var hi: float = cap
	while hi - lo > 0.5:
		var mid: float = 0.5 * (lo + hi)
		if _touches(station, at, mid):
			hi = mid
		else:
			lo = mid
	return lo


# Whether a ball of `radius` at `at` overlaps the station's frame or drum.
static func _touches(station: Station, at: Vector3, radius: float) -> bool:
	var ball := SphereShape3D.new()
	ball.radius = maxf(radius, 0.01)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, at)
	for hit: Dictionary in station.get_world_3d().direct_space_state.intersect_shape(q, 16):
		if hit["collider"] == station.frame_body or hit["collider"] == station.drum_body:
			return true
	return false


# A scene stepped with `mode` and `threads` threads with the station at the origin (kept in the scene's meta), or null
# without the asset.
func _scene(mode: StringName, threads: int) -> TurretScene:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, mode, threads)
	var station := Station.new()
	station.name = "Station"
	if not station.build():
		station.free()
		await scene.free_scene(get_tree())
		return null
	scene.world.spawn(station, scene.world.to_universe(Vector3.ZERO))
	scene.set_meta(&"station", station)
	return scene


static func _add_rams(scene: TurretScene) -> void:
	var rams := RamResolver.new()
	rams.name = "RamResolver"
	rams.world = scene.world
	scene.space.add_child(rams)


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


func _speed_up() -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
