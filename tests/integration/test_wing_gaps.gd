extends TestSteps
## Wingmen closing the gaps losses leave (M8-T13, roadmap M7-6): when a Starfury of a formation goes down, the ones behind it
## move up (`Wing.close_gaps`, in `WingDirector.refresh`), so the wing keeps its shape with no hole, and they fly to their
## new slots with M7-T76's avoidance: no ship of the wing touches another on the way.
##
## The real main scene (free flight, the real pool, `WingDirector`, `RamResolver` and the native core, six threads), headless,
## with the physics rate and the time scale raised. The player leads on a fixed course under god mode with the wing on its
## slots under FORM ON ME, so the wingmen hold the formation while they are shot at.
## - The fights: raiders with seeded brains attack the wing from astern until it has lost `FIGHT_LOSSES` ships (or the time
##   is up), then are taken away and the wing flies on.
## - The schedules: named wingmen are shot down at set times with nobody else about.
## Every tick the slots flown must be a shape without a hole; no ram between two ships of the wing may happen; at the end
## every survivor sits on its slot.

const FREE_FLIGHT: String = "res://data/scenarios/free_flight.json"
const ALLY: StringName = ShipPool.ALLY_TYPE
const RAIDER: StringName = ShipPool.DEFAULT_TYPE
const SPEED_UP: float = 8.0
## The leader's course: down and away from the scenario's buoys and the station, m/s.
const HEADING: Vector3 = Vector3(0.0, -1.0, 0.0)
const SPEED_MPS: float = 100.0
## The wing settles on its slots before anything happens, s.
const SETTLE_S: float = 5.0
## A fight ends once the wing has lost this many, or after `FIGHT_LIMIT_S`; it must have lost `LEAST_LOSSES` by then.
const FIGHT_LOSSES: int = 4
const LEAST_LOSSES: int = 2
const FIGHT_LIMIT_S: float = 240.0
const RAIDERS: int = 6
## The raiders start this far astern of the leader, m.
const RAIDER_RANGE_M: float = 1500.0
## The wing flies on this long after its last loss, s.
const REFORM_S: float = 45.0
## Within this of its slot a wingman is formed up, m: half the V's spacing.
const FORMED_M: float = 20.0
## The least two of the wing's centres may come to each other while it closes up with nobody shooting, m: two Starfury
## radii (10 m) and a little room (M7-T76's bound).
const CLEAR_M: float = 25.0

var main: Main = null
var wing: Wing = null
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8
var _threads_backup: Variant = null
var _step_threads_backup: Variant = null
# Rams between two ships of the wing, as text.
var _rams: PackedStringArray = PackedStringArray()
# The wing's ships by `Ship` instance id: their callsigns.
var _callsigns: Dictionary = {}


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()  # minutes of flying per case


func before_each() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	_threads_backup = Settings.get_value(&"perf_threads")
	_step_threads_backup = Settings.get_value(&"perf_step_threads")
	Settings.set_value(&"perf_threads", 6)
	Settings.set_value(&"perf_step_threads", 0)
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true  # the leader flies its course whatever hits it
	ContactScan.invalidate()
	_rams = PackedStringArray()
	_callsigns = {}


func after_each() -> void:
	_slow_down()
	Settings.set_value(&"perf_threads", _threads_backup)
	Settings.set_value(&"perf_step_threads", _step_threads_backup)
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false
	ContactScan.invalidate()


# --- the fights ------------------------------------------------------------------------------------------------------


func test_a_wing_shot_at_from_astern_closes_up_behind_its_losses_seed_1() -> void:
	await _fight(1)


func test_a_wing_shot_at_from_astern_closes_up_behind_its_losses_seed_2() -> void:
	await _fight(2)


func test_a_wing_shot_at_from_astern_closes_up_behind_its_losses_seed_3() -> void:
	await _fight(3)


# --- the schedules ---------------------------------------------------------------------------------------------------


func test_the_left_arm_moves_up_behind_its_first_ship() -> void:
	# ALPHA 2 leads the left arm: the four behind it each move up one place and the centre ship takes the arm's last.
	await _shoot_down(11, [[1]])
	assert_eq(_slots_flown(), PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))


func test_three_down_at_once_and_two_more_close_up_and_even_the_arms() -> void:
	# The first two of the left arm, one in the middle of the right and the centre ship; then two more of the left arm, so
	# the right arm's last has to cross behind the leader.
	await _shoot_down(11, [[1, 4, 6, 11], [1, 4]])
	assert_eq(wing.members().size(), 5)


func test_a_finger_fours_last_ship_crosses_to_the_empty_arm() -> void:
	# ALPHA 2 was the whole left arm: ALPHA 4, behind ALPHA 3 on the right, crosses behind the leader to take its place.
	await _shoot_down(3, [[1]])
	assert_eq(wing.member_at(1).display_name, "ALPHA 4")
	assert_eq(wing.member_at(2).display_name, "ALPHA 3")


# --- the flying ------------------------------------------------------------------------------------------------------


# Raiders seeded by `seed_value` attack Alpha's eleven from astern until `FIGHT_LOSSES` are down; then they are taken away
# and the wing flies on.
func _fight(seed_value: int) -> void:
	await _launch(11, RAIDERS, seed_value)
	await _fly(SETTLE_S)
	var basis: Basis = main.ship.global_basis
	for n: int in RAIDERS:
		# A line abreast astern, 150 m apart, noses on the wing.
		var offset := Vector3((n - 0.5 * (RAIDERS - 1)) * 150.0, 60.0 * (n % 2), RAIDER_RANGE_M)
		var at: UniversePos = main.world.to_universe(main.ship.global_position + basis * offset)
		var raider_name: String = "RAIDER %d" % (n + 1)
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider"}, at, hash([raider_name, seed_value]))
		assert_true(bool(made["ok"]), str(made.get("error", "")))
		assert_not_null(main.ships.acquire(raider_name, at, basis, main.ship.linear_velocity, made["brain"] as PilotBrain, RAIDER))
	var t0: float = SimClock.now()
	var lost_at: PackedFloat32Array = PackedFloat32Array()
	var before: int = wing.members().size()
	while before - wing.members().size() < FIGHT_LOSSES and SimClock.now() - t0 < FIGHT_LIMIT_S:
		await _fly_tick()
		while lost_at.size() < before - wing.members().size():
			lost_at.append(SimClock.now() - t0)
	var lost: int = before - wing.members().size()
	for raider: Combatant in main.ships.alive(RAIDER):
		main.ships.release(raider)
	await _fly(REFORM_S)
	_slow_down()
	gut.p("seed %d: %d lost at %s s, flown slots %s, worst %.1f m off its slot %.0f s after the fight, rams in the wing %d"
			% [seed_value, lost, lost_at, _slots_flown(), _worst_m(), REFORM_S, _rams.size()])
	assert_gte(lost, LEAST_LOSSES, "the raiders shot down at least %d of the wing within %.0f s" % [LEAST_LOSSES, FIGHT_LIMIT_S])
	_assert_closed_up()


# A wing of `size` wingmen loses the ships in each list of `waves` (their slots at that moment) together, `REFORM_S` apart,
# with nobody else about, so every near miss is the closing up's own.
func _shoot_down(size: int, waves: Array) -> void:
	await _launch(size, 0, 1)
	await _fly(SETTLE_S)
	var nearest: Array = [INF, ""]
	for wave: Array in waves:
		for slot: int in wave:
			assert_true(wing.member_at(slot).damageable.kill(), "slot %d is shot down" % slot)
		await _fly(REFORM_S, nearest)
	_slow_down()
	gut.p("%d wingmen less %s: flown slots %s, worst %.1f m off its slot, nearest centres %.1f m (%s), rams in the wing %d"
			% [size, waves, _slots_flown(), _worst_m(), nearest[0], nearest[1], _rams.size()])
	assert_gt(float(nearest[0]), CLEAR_M, "no two ships of the wing closer than %.0f m (%s)" % [CLEAR_M, nearest[1]])
	_assert_closed_up()


# No ram inside the wing, no hole in the slots, and every survivor on its slot.
func _assert_closed_up() -> void:
	assert_eq(_rams.size(), 0, "no ship of the wing touched another: %s" % [_rams])
	assert_eq(wing.close_gaps(), [] as Array[Vector2i], "the wing is closed up")
	assert_eq(_hole(), "", "the slots flown have no hole")
	assert_lt(_worst_m(), FORMED_M, "every wingman is on its slot")


# The main scene in free flight with Alpha's `size` wingmen on their slots under FORM ON ME, the leader on its course.
func _launch(size: int, raiders: int, seed_value: int) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.scenario_path = FREE_FLIGHT
	main.scenario_seed = seed_value
	main.ally_pool_size = size
	main.raider_pool_size = raiders
	add_child_autofree(main)
	await _ticks(2)
	wing = main.wings.player_wing()
	assert_true(wing.resize(size))
	var basis := Basis.looking_at(HEADING, Vector3.BACK)
	main.ship.reset_to(Transform3D(basis, Vector3.ZERO))
	main.ship.linear_velocity = HEADING * SPEED_MPS
	_watch(main.combatant)
	for slot: int in range(1, size + 1):
		var callsign: String = wing.callsign(slot)
		var at: UniversePos = main.world.to_universe(basis * wing.slot_offset(slot))
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury"}, at, hash([callsign, seed_value]))
		var ally: Combatant = main.ships.acquire(callsign, at, basis, HEADING * SPEED_MPS, made["brain"] as PilotBrain, ALLY)
		assert_eq(main.wings.add_member(wing, ally, slot), slot)
		_watch(ally)
	assert_true(bool(main.wings.give_order(AiContext.Order.FORM_ON_ME)["ok"]))
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))


# Notes every ram `c` takes from another ship of the wing.
func _watch(c: Combatant) -> void:
	_callsigns[c.ship.get_instance_id()] = c.display_name
	var callsign: String = c.display_name
	c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
		if info != null and info.cause == HitInfo.CAUSE_RAM and _callsigns.has(info.shooter_id):
			_rams.append("%s against %s at %.0f m/s, %.1f s" % [callsign, _callsigns[info.shooter_id], info.relative_speed_mps,
					SimClock.now()])
			gut.p("  ram: " + _rams[_rams.size() - 1]))


# Flies `seconds` of sim time. `nearest` ([m, who and when]) takes the least distance between two of the wing's centres.
func _fly(seconds: float, nearest: Array = []) -> void:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await _fly_tick()
		if nearest.is_empty():
			continue
		var ships: Array[Combatant] = [main.combatant]
		ships.append_array(wing.members())
		for a: int in ships.size():
			for b: int in range(a + 1, ships.size()):
				var d: float = ships[a].ship.global_position.distance_to(ships[b].ship.global_position)
				if d < float(nearest[0]):
					nearest[0] = d
					nearest[1] = "%s and %s at %.1f s" % [ships[a].display_name, ships[b].display_name, SimClock.now()]


# One tick with the leader held on its course. The wing has run by then: the slots it flies must have no hole.
func _fly_tick() -> void:
	await get_tree().physics_frame
	main.ship.linear_velocity = HEADING * SPEED_MPS
	main.ship.angular_velocity = Vector3.ZERO
	main.ship.global_basis = Basis.looking_at(HEADING, Vector3.BACK)
	var hole: String = _hole()
	if not hole.is_empty():
		fail_test("%s at %.2f s" % [hole, SimClock.now()])


func _slots_flown() -> PackedInt32Array:
	var out := PackedInt32Array()
	for member: Combatant in wing.members():
		out.append(wing.slot_of(member))
	return out


# What is wrong with the slots flown, or "": an arm with an empty slot ahead of a flown one, arms more than one ship apart,
# or the centre slot flown beside an open arm slot.
func _hole() -> String:
	var counts: Array[int] = [0, 0, 0]
	var open_arm_slot: bool = false
	for arm_side: int in [-1, 1]:
		var slots: Array[int] = []
		for slot: int in range(1, wing.size + 1):
			if wing.formation.side(slot, wing.size) == arm_side:
				slots.append(slot)
		slots.sort_custom(func(a: int, b: int) -> bool:
			return wing.slot_offset(a).length_squared() < wing.slot_offset(b).length_squared())
		var seen_empty: bool = false
		for slot: int in slots:
			if wing.member_at(slot) == null:
				seen_empty = true
			elif seen_empty:
				return "slot %d is flown behind an empty slot of its arm (%s)" % [slot, _slots_flown()]
			else:
				counts[arm_side + 1] += 1
		open_arm_slot = open_arm_slot or seen_empty
	var centre: int = Formation.centre_slot(wing.size)
	if absi(counts[0] - counts[2]) > 1:
		return "the arms fly %d and %d ships (%s)" % [counts[0], counts[2], _slots_flown()]
	if centre > 0 and wing.member_at(centre) != null and open_arm_slot:
		return "the centre slot is flown beside an open arm slot (%s)" % [_slots_flown()]
	return ""


# How far the wingman furthest from its slot is from it, m.
func _worst_m() -> float:
	var worst: float = 0.0
	var lead: Ship = main.ship
	for member: Combatant in wing.members():
		var slot: Vector3 = Formation.slot_point(lead.global_position, -lead.global_basis.z, lead.global_basis.y,
				wing.slot_offset(wing.slot_of(member)))
		worst = maxf(worst, member.ship.global_position.distance_to(slot))
	return worst


func _slow_down() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
