extends GutTest
## Replenishing the wing (M3-T08 phase 2, AC7, AC11, maintainer Q8, architecture §16 D36): when a wave starts,
## `WingDirector.replenish()` gives every empty slot of the player's wing an allied Starfury from the pool, named
## `Wing.callsign(slot)`, 1 500 m behind the player along its nose axis at the player's velocity, flying the wing's order in
## the slot's lane. Runs the real main scene (free flight with a pool of allies, so nothing else launches ships; one test uses
## the sandbox's real waves). `Main` connects `WaveDirector.wave_started` to the director; most tests emit the signal.

const ALLY: StringName = ShipPool.ALLY_TYPE
const FREE_FLIGHT: String = "res://data/scenarios/free_flight.json"
const BEHIND_M: float = 1500.0

var main: Main
var source: FakeInputSource
var wing: Wing = null
var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false
	ContactScan.invalidate()


## A fresh main scene with `allies` pooled starfury_allies (-1: the scenario's own) in `scenario` ("" = the sandbox).
func _launch(allies: int, scenario: String = FREE_FLIGHT) -> void:
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	main.ally_pool_size = allies
	if not scenario.is_empty():
		main.scenario_path = scenario
		main.raider_pool_size = 0
	add_child_autofree(main)
	await _ticks(2)
	wing = main.wings.player_wing()


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _start_wave(number: int = 2) -> void:
	main.waves.wave_started.emit(number, "TEST WAVE")


func _splat_nodes() -> int:
	return _count(get_tree().root)


func _count(node: Node) -> int:
	var n: int = 1 if node is GaussianSplatNode else 0
	for child: Node in node.get_children():
		n += _count(child)
	return n


## The player, turned and moving along a different line than its nose points, so "behind" is not the world's +Z or its drift.
func _pose_player() -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(10.0), deg_to_rad(40.0), deg_to_rad(15.0)))
	main.ship.reset_to(Transform3D(basis, Vector3(120.0, -30.0, 400.0)))
	main.ship.linear_velocity = Vector3(25.0, 5.0, -60.0)
	var nose: Vector3 = -main.ship.global_basis.z
	assert_gt(rad_to_deg(nose.angle_to(main.ship.linear_velocity)), 20.0, "the drift is not along the nose")


## `c` in the player's body frame (x right, y up, +z behind).
func _in_player_frame(c: Combatant) -> Vector3:
	return main.ship.global_basis.inverse() * (c.ship.global_position - main.ship.global_position)


func _assert_entered(c: Combatant, slot: int) -> void:
	var who: String = "%s (slot %d)" % [c.display_name, slot]
	var rel: Vector3 = _in_player_frame(c)
	assert_almost_eq(rel.z, BEHIND_M, 1.0, "%s: 1 500 m behind the player along its nose" % who)
	assert_almost_eq(rel.x, wing.slot_offset(slot).x, 1.0, "%s: in its slot's lane" % who)
	assert_almost_eq(rel.y, wing.slot_offset(slot).y, 1.0, "%s: at its slot's height" % who)
	assert_lt((c.ship.global_position - main.ship.global_position).length(), BEHIND_M + 3.0, "%s: no further than the lane adds" % who)
	assert_almost_eq(c.ship.linear_velocity, main.ship.linear_velocity, Vector3.ONE * 0.1, "%s: at the player's velocity" % who)
	assert_almost_eq(c.ship.global_basis.z, main.ship.global_basis.z, Vector3.ONE * 1e-3, "%s: on the player's heading" % who)


# --- the replacement -------------------------------------------------------------------------------------------------


func test_a_downed_wingman_is_replaced_by_its_callsign_when_the_next_wave_starts() -> void:
	await _launch(4)
	assert_eq(main.wings.replenish().size(), 3, "an empty wing launches its three wingmen")
	assert_true(main.wings.give_order(AiContext.Order.FORM_ON_ME)["ok"])
	var kept_a: Combatant = wing.member_at(1)
	var kept_b: Combatant = wing.member_at(3)
	var downed: Combatant = wing.member_at(2)
	_pose_player()
	assert_true(downed.damageable.kill(), "ALPHA 3 is shot down")
	assert_eq(main.ships.alive(ALLY).size(), 2, "its ship went back to the pool")
	assert_eq(wing.member_at(2), downed, "no refresh has run since: the slot still holds the dead pilot")
	_start_wave()  # in the very tick of the kill
	var fresh: Combatant = wing.member_at(2)
	assert_not_null(fresh, "slot 2 is filled again")
	assert_eq(fresh.display_name, "ALPHA 3", "named by the wing's callsign for the slot")
	assert_eq(fresh.targetable.display_name, "ALPHA 3")
	assert_eq(wing.callsign(2), fresh.display_name)
	_assert_entered(fresh, 2)
	assert_eq(wing.member_at(1), kept_a, "the others fly on")
	assert_eq(wing.member_at(3), kept_b)
	assert_true(wing.is_full())
	assert_eq(main.ships.alive(ALLY).size(), 3)
	var pilot := fresh.driver.brain as AiPilot
	assert_not_null(pilot, "an AI pilot")
	assert_eq(pilot.profile.resource_path, AiProfile.PATHS[&"ally_starfury"])
	assert_eq(pilot.context.order, AiContext.Order.FORM_ON_ME, "flying the wing's current order, not the default")
	assert_not_null(pilot.behaviour(&"formation"), "with the formation behaviour")
	assert_true(pilot.context.has_slot)
	assert_eq(pilot.context.slot_offset, wing.slot_offset(2))
	assert_eq(pilot.context.leader_id, main.combatant.targetable.get_instance_id())
	assert_true(fresh.targetable.is_active() and fresh.damageable.is_active(), "in play")
	assert_eq(fresh.faction, Factions.EARTH_ALLIANCE)


func test_two_downed_wingmen_are_both_replaced_in_their_own_slots() -> void:
	await _launch(4)
	main.wings.replenish()
	assert_true(main.wings.give_order(AiContext.Order.ENGAGE_AT_WILL)["ok"])
	var middle: Combatant = wing.member_at(2)
	var first: Combatant = wing.member_at(1)
	var third: Combatant = wing.member_at(3)
	_pose_player()
	assert_true(first.damageable.kill())
	assert_true(third.damageable.kill())
	_start_wave()
	assert_eq(wing.member_at(2), middle, "the survivor keeps its slot")
	var one: Combatant = wing.member_at(1)
	var three: Combatant = wing.member_at(3)
	assert_not_null(one)
	assert_not_null(three)
	assert_eq(one.display_name, "ALPHA 2")
	assert_eq(three.display_name, "ALPHA 4")
	_assert_entered(one, 1)
	_assert_entered(three, 3)
	assert_gt((one.ship.global_position - three.ship.global_position).length(), 40.0, "the lanes keep them apart")
	for c: Combatant in [one, three]:
		assert_eq((c.driver.brain as AiPilot).context.order, AiContext.Order.ENGAGE_AT_WILL)
	assert_true(wing.is_full())


func test_a_wing_with_no_members_gets_all_three_in_their_lanes() -> void:
	await _launch(4)
	_pose_player()
	_start_wave(1)
	assert_eq(wing.members().size(), 3)
	var names: Array[String] = []
	for slot: int in range(1, 4):
		var c: Combatant = wing.member_at(slot)
		names.append(c.display_name)
		_assert_entered(c, slot)
	assert_eq(names, ["ALPHA 2", "ALPHA 3", "ALPHA 4"] as Array[String])
	var rows: Array[Dictionary] = main.wings.roster()
	assert_eq(rows.size(), 3, "the roster lists them")
	for i: int in 3:
		for j: int in range(i + 1, 3):
			assert_gt((wing.member_at(i + 1).ship.global_position - wing.member_at(j + 1).ship.global_position).length(), 39.0,
					"no two start on top of each other")


func test_a_full_wing_is_left_alone() -> void:
	await _launch(4)
	main.wings.replenish()
	var members: Array[Combatant] = wing.members()
	var free_before: int = main.ships.free_count(ALLY)
	var positions: Array[Vector3] = []
	for m: Combatant in members:
		positions.append(m.ship.global_position)
	_start_wave()
	assert_eq(wing.members(), members, "same pilots, same slots")
	assert_eq(main.ships.free_count(ALLY), free_before, "nothing taken from the pool")
	assert_eq(main.ships.alive(ALLY).size(), 3)
	for i: int in members.size():
		assert_eq(members[i].ship.global_position, positions[i], "nobody was moved")
	assert_eq(main.wings.replenish().size(), 0)
	assert_push_warning_count(0)


func test_the_pool_runs_dry_fills_what_it_can_and_warns_once() -> void:
	await _launch(2)
	_start_wave()
	assert_eq(wing.members().size(), 2, "two ships, two slots")
	assert_eq(wing.member_at(1).display_name, "ALPHA 2")
	assert_eq(wing.member_at(2).display_name, "ALPHA 3")
	assert_eq(wing.empty_slots(), PackedInt32Array([3]), "the last slot waits for the next wave")
	assert_eq(main.ships.free_count(ALLY), 0)
	assert_push_warning_count(1)
	assert_eq(main.wings.replenish().size(), 0, "nothing left to launch")
	assert_push_warning_count(2)
	wing.member_at(1).damageable.kill()  # its ship is free again
	assert_eq(main.wings.replenish().size(), 1, "a ship that went back to the pool serves the next call")
	assert_eq(wing.member_at(1).display_name, "ALPHA 2")
	assert_eq(wing.empty_slots(), PackedInt32Array([3]))
	assert_push_warning_count(3)


func test_without_an_ally_pool_a_wave_start_does_nothing_and_says_nothing() -> void:
	await _launch(0)
	assert_eq(main.ships.pool_size(ALLY), 0)
	_start_wave()
	assert_eq(wing.members().size(), 0)
	assert_eq(main.ships.alive().size(), 0)
	assert_push_warning_count(0)


func test_nothing_launches_while_the_leader_is_dead_or_when_there_is_no_wing() -> void:
	await _launch(4)
	assert_true(main.combatant.damageable.kill(), "the player is shot down")
	assert_false(main.wings.leader_alive(wing))
	_start_wave()
	assert_eq(wing.members().size(), 0, "no one launches behind a dead leader")
	assert_eq(main.ships.alive(ALLY).size(), 0)
	main.respawn()
	_start_wave()
	assert_eq(wing.members().size(), 3, "back in play: the next wave replenishes")
	main.wings.wings.clear()
	assert_eq(main.wings.replenish().size(), 0, "no wing: no-op")
	assert_push_warning_count(0)


func test_a_callsign_already_in_play_is_not_given_twice() -> void:
	await _launch(4)
	assert_true(_exec("spawn ally idle 300").ok, "a console ally takes ALPHA 2")
	var stray: Combatant = main.ships.alive(ALLY)[0]
	assert_eq(stray.display_name, "ALPHA 2")
	_start_wave()
	assert_eq(wing.members().size(), 3, "all three slots are still filled")
	var seen: Dictionary = {}
	for c: Combatant in main.ships.alive(ALLY):
		assert_false(seen.has(c.display_name), "%s is unique" % c.display_name)
		seen[c.display_name] = true
	assert_eq(wing.member_at(2).display_name, "ALPHA 3")
	assert_eq(wing.member_at(3).display_name, "ALPHA 4")
	assert_eq(wing.member_at(1).display_name, "ALPHA 5", "slot 1's callsign was taken: the next number after the wing's")
	assert_false(wing.members().has(stray), "the stray ship stays out of the wing")
	assert_eq(stray.display_name, "ALPHA 2")


# --- AC7: no splat node enters or leaves the tree ----------------------------------------------------------------------


func test_the_splat_node_count_never_changes_across_kill_and_replenish_cycles() -> void:
	await _launch(4)
	var before: int = _splat_nodes()
	assert_gt(before, 0)
	for cycle: int in 5:
		_start_wave(cycle + 1)
		assert_eq(wing.members().size(), 3, "cycle %d: the wing is full" % cycle)
		assert_eq(_splat_nodes(), before, "cycle %d: after replenish" % cycle)
		for member: Combatant in wing.members():
			assert_true(member.damageable.kill())
		assert_eq(_splat_nodes(), before, "cycle %d: after the break-ups" % cycle)
		assert_eq(main.ships.alive(ALLY).size(), 0)
		await _ticks(3)
		assert_eq(wing.members().size(), 0, "cycle %d: the dead leave their slots on the next refresh" % cycle)
	assert_eq(_splat_nodes(), before)


# --- the real waves and the console ------------------------------------------------------------------------------------


func test_a_real_wave_start_replenishes_through_the_main_scene_wiring() -> void:
	await _launch(-1, "")
	DebugConsole.flags.invulnerable = true
	assert_eq(main.waves.scenario_id, &"combat_sandbox")
	assert_eq(wing.members().size(), 0, "the wing starts empty until T10 launches wingmen")
	var before: int = _splat_nodes()
	var seen: Array[Dictionary] = []
	main.waves.wave_started.connect(func(_number: int, _name: String) -> void:
		# Main's connection ran first: the replacements are in, and nothing has flown since.
		for slot: int in range(1, 4):
			var c: Combatant = wing.member_at(slot)
			seen.append({"name": c.display_name if c != null else "", "rel": _in_player_frame(c) if c != null else Vector3.ZERO}))
	assert_true(_exec("wave start 1").ok)
	assert_eq(wing.members().size(), 0, "not during the countdown")
	Engine.time_scale = 4.0
	var t0: float = SimClock.now()
	while main.waves.plan.state != WavePlan.State.ACTIVE and SimClock.now() - t0 < 60.0:
		await _ticks(1)
	Engine.time_scale = 1.0
	await _ticks(3)
	assert_eq(seen.size(), 3, "the wave started once")
	for i: int in 3:
		assert_eq(seen[i]["name"], wing.callsign(i + 1))
		assert_almost_eq((seen[i]["rel"] as Vector3).z, BEHIND_M, 1.0, "slot %d: 1 500 m astern as the wave begins" % (i + 1))
	assert_true(wing.is_full())
	assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 3, "the wave's raiders are not the wingmen")
	assert_eq(_splat_nodes(), before)


func test_the_console_replenishes_on_demand() -> void:
	await _launch(4)
	var result: ConsoleResult = _exec("wing replenish")
	assert_true(result.ok, result.error)
	assert_string_contains(result.text(), "ALPHA 2, ALPHA 3, ALPHA 4")
	assert_eq(wing.members().size(), 3)
	var again: ConsoleResult = _exec("wing replenish")
	assert_true(again.ok, "a full wing is no error")
	assert_string_contains(again.text(), "no empty slot")
	wing.member_at(2).damageable.kill()
	result = _exec("wing replenish")
	assert_true(result.ok, result.error)
	assert_string_contains(result.text(), "launched ALPHA 3 (1500 m astern)")
	assert_eq(wing.members().size(), 3)


func test_the_console_says_why_nothing_launched() -> void:
	await _launch(1)
	assert_true(_exec("wing replenish").ok, "one ship, one slot filled")
	var dry: ConsoleResult = _exec("wing replenish")
	assert_false(dry.ok, "empty slots and no ship to send")
	assert_string_contains(dry.error, "no free allied ship: 1 of 1 in the pool are in use")
	assert_push_warning_count(2)
	main.wings.wings.clear()
	assert_false(_exec("wing replenish").ok, "no wing in the scenario")
	assert_push_warning_count(2)
