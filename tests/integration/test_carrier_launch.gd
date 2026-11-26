extends GutTest
## Capital carriers launch and recover their craft (M10-T17, D12.10, Q58, Q71, Q73) in the real main scene, on their generated
## assets: the Nova brings a wing up its hidden lift and out of its forward bay; the Hyperion opens a bay's door only for that
## bay's own craft and shuts it after; a Kestrel folds its wings before it enters the shuttle bay and spreads them once it has
## left; a hostile within 15 km launches the first wing on its own, losses send the second; the fight over, the craft come
## home; a jump waits for them, then leaves the rest; a hulk launches nothing and takes nobody in.

const SPEED_UP: float = 4.0
const AHEAD_M: float = 2500.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 5
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	(main.input_source as FakeInputSource).release_all()
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	DebugConsole.flags.invulnerable = false


# A carrier of `type` for the Earth Alliance, `ahead_m` in front of the player, its bow across the player's nose, held on its
# course, its hangar stocked and its pool ready; launching by hand (auto off) unless the test turns it on.
func _carrier(type: StringName, ahead_m: float = AHEAD_M) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(type, Factions.EARTH_ALLIANCE, String(type).to_upper(), rest)
	assert_not_null(cap, "%s is generated (scripts/gen_assets.sh)" % type)
	if cap == null:
		return null
	var player: Basis = main.ship.global_basis
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - player.z * ahead_m), Basis(player.z, player.y, -player.x))
	cap.set_course(Vector3.ZERO, rest)
	CapitalGuns.of(main.world).hold(cap, true)
	CapitalBeams.of(main.world).hold(cap, true)
	assert_not_null(cap.hangar, "it has a hangar")
	cap.hangar.auto = false
	assert_gt(cap.hangar.stock_from_loadout(), 0, "its loadout's craft aboard")
	cap.hangar.prepare_pool()
	return cap


# Takes every ship of another side out of play, so the only threat is the test's own.
func _clear_hostiles() -> void:
	for c: Combatant in main.ships.alive():
		if c.faction != Factions.EARTH_ALLIANCE and c != main.combatant:
			main.ships.release(c)


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func test_a_nova_launches_a_wing_up_its_lift_and_out_of_its_bay() -> void:
	var nova: CapitalShip = _carrier(&"ea_nova")
	if nova == null:
		return
	var h: CapitalHangar = nova.hangar
	assert_eq(int(h.stock[&"starfury_ally"]), 24, "24 Starfuries (Q71)")
	var lift: BayElevator = h.lift_of("bay_fore")
	assert_not_null(lift, "the forward bay's hidden lift")
	var bay: Dictionary = (nova.hardpoints()["bays"] as Array)[0]
	var exit: Vector3 = BayBerths._vec(bay["exit"], Vector3.ZERO)
	var releases: Array[Dictionary] = []
	h.launched.connect(func(craft: Ship) -> void:
		var local: Transform3D = nova.global_transform.affine_inverse() * craft.global_transform
		releases.append({"t": SimClock.now(), "z": local.origin.z, "nose": -local.basis.z,
				"out": nova.global_basis.inverse() * (craft.linear_velocity - nova.linear_velocity)}))
	var lowest: Array[float] = [1.0]
	assert_eq(h.launch_wing(), 12, "the first wing of 12 (Q73)")
	assert_true(h.is_launching())
	await _fly(120.0, func() -> bool:
		lowest[0] = minf(lowest[0], lift.height())
		return releases.size() >= 12 and h.queued_count() == 0)
	assert_eq(releases.size(), 12, "the whole wing left")
	assert_eq(lift.trips_up, 4, "three abreast a trip up the lift")
	assert_almost_eq(lowest[0], 0.0, 1e-3, "the lift went all the way down to the hangar deck")
	for r: Dictionary in releases:
		assert_lt(float(r["z"]), exit.z, "let go past the mouth")
		assert_gt((r["nose"] as Vector3).dot(Vector3.FORWARD), 0.99, "nose out of the bay")
		assert_gt(-(r["out"] as Vector3).z, 40.0, "leaving at the push's speed (%s)" % r["out"])
	var first: float = float(releases[0]["t"])
	var last: float = float(releases[releases.size() - 1]["t"])
	assert_between(last - first, 20.0, 60.0, "a wing in under a minute: %.1f s" % (last - first))
	assert_eq(int(h.stock[&"starfury_ally"]), 12, "the second wing still aboard")
	assert_eq(h.out_count(), 12)
	for entry: Dictionary in h.craft_out():
		assert_eq((entry["combatant"] as Combatant).faction, Factions.EARTH_ALLIANCE, "its own side's")
		assert_true((entry["combatant"] as Combatant).display_name.begins_with("Delta"), "the first wing's callsign")
	assert_false(h.is_launching(), "done: its brain lets the helm go again")


func test_the_hyperion_opens_a_door_only_for_its_own_craft_and_shuts_it_after() -> void:
	var cap: CapitalShip = _carrier(&"ea_hyperion")
	if cap == null:
		return
	var h: CapitalHangar = cap.hangar
	assert_eq(int(h.stock[&"starfury_ally"]), 6, "six Starfuries (Q58)")
	assert_eq(int(h.stock.get(&"ea_shuttle", 0)), 2, "and two shuttles")
	var doors: Array[String] = []
	for bay: String in h.bay_names():
		assert_not_null(h.door_of(bay), "%s has its roll-up door" % bay)
		assert_false(h.door_of(bay).is_open(), "shut while idle")
		doors.append(bay)
	assert_eq(h.launch(&"starfury_ally", 1), 1)
	var opened: Dictionary = {}
	var released: Array[bool] = [false]
	h.launched.connect(func(_craft: Ship) -> void: released[0] = true)
	await _fly(20.0, func() -> bool:
		for bay: String in doors:
			if h.door_of(bay).amount > 0.0:
				opened[bay] = true
		return released[0])
	assert_true(released[0], "the Starfury left")
	assert_eq(opened.size(), 1, "one door opened, its own bay's: %s" % [opened.keys()])
	var used: String = opened.keys()[0] if not opened.is_empty() else ""
	assert_true(used.begins_with("bay_fury"), "a Starfury bay")
	await _fly(CapitalHangar.DOOR_IDLE_S + BayDoors.ROLL_SECONDS + 2.0)
	assert_almost_eq(h.door_of(used).amount, 0.0, 1e-3, "shut again once its craft was clear")
	# Home again: the same bay's door opens for it, it docks, the door shuts and it is aboard.
	assert_eq(h.recall_all(), 1)
	var home: Array[bool] = [false]
	var door_on_entry: Array[float] = [0.0]
	h.recovered.connect(func(_craft: Ship, _type: StringName) -> void: home[0] = true)
	await _fly(90.0, func() -> bool:
		for held: Ship in h.held_ships():
			if h._rows.phase_of(held.get_instance_id()) == CapitalHangar.PHASE_CAPTURE:
				door_on_entry[0] = maxf(door_on_entry[0], h.door_of(h.cradles.bays[h.cradle_of(held)]).amount)
		return home[0])
	assert_true(home[0], "it came home")
	assert_almost_eq(door_on_entry[0], 1.0, 1e-3, "it entered through an open door")
	assert_eq(int(h.stock[&"starfury_ally"]), 6, "aboard again")
	assert_eq(h.out_count(), 0)


func test_a_kestrel_folds_its_wings_to_enter_and_spreads_them_after_it_leaves() -> void:
	var cap: CapitalShip = _carrier(&"ea_hyperion")
	if cap == null:
		return
	var h: CapitalHangar = cap.hangar
	h.stock = {&"ea_atmo_shuttle": 1}
	h.prepare_pool()
	assert_eq(h.launch(&"ea_atmo_shuttle", 1), 1, "the shuttle bay takes the Kestrel (its pose)")
	var kestrel: Array[Ship] = [null]
	var folded_at_release: Array[float] = [-1.0]
	h.launched.connect(func(craft: Ship) -> void:
		kestrel[0] = craft
		folded_at_release[0] = WingFoldNode.of(craft).amount if WingFoldNode.of(craft) != null else -1.0)
	await _fly(30.0, func() -> bool: return kestrel[0] != null)
	assert_not_null(kestrel[0], "the Kestrel left the shuttle bay")
	if kestrel[0] == null:
		return
	var fold: WingFoldNode = WingFoldNode.of(kestrel[0])
	assert_not_null(fold, "its wings fold (their own chunks)")
	assert_almost_eq(folded_at_release[0], 1.0, 1e-3, "folded while it was in the bay")
	assert_false(kestrel[0].hull.visible, "drawn as its pieces while folded")
	await _fly(fold.fold_s + 1.0, func() -> bool: return fold.is_spread())
	assert_true(fold.is_spread(), "spread once it had left")
	assert_true(kestrel[0].hull.visible, "the one-piece hull again")
	await _fly(5.0)
	h.recall_all()
	var at_capture: Array[float] = [-1.0]
	var home: Array[bool] = [false]
	h.recovered.connect(func(_craft: Ship, _type: StringName) -> void: home[0] = true)
	await _fly(120.0, func() -> bool:
		if at_capture[0] < 0.0 and h._rows.phase_of(kestrel[0].get_instance_id()) == CapitalHangar.PHASE_CAPTURE:
			at_capture[0] = fold.amount
		return home[0])
	assert_almost_eq(at_capture[0], 1.0, 1e-3, "folded before it entered")
	assert_true(home[0], "docked in the shuttle bay")
	assert_eq(int(h.stock[&"ea_atmo_shuttle"]), 1)


func test_a_threat_launches_the_first_wing_losses_the_second_and_calm_brings_them_home() -> void:
	var nova: CapitalShip = _carrier(&"ea_nova")
	if nova == null:
		return
	var h: CapitalHangar = nova.hangar
	_clear_hostiles()
	h.auto = true
	h.options["calm_s"] = 4.0
	main.ships.prepare(ShipPool.DEFAULT_TYPE, 1)
	var at: UniversePos = main.world.to_universe(nova.global_position + nova.global_basis.x * 8000.0)
	var made: Dictionary = BrainFactory.from_behaviour({"type": "idle", "hold": true}, at, 9)
	var raider: Combatant = main.ships.acquire("RAIDER 1", at, Basis.IDENTITY, main.world.rest_velocity(), made["brain"] as PilotBrain,
			ShipPool.DEFAULT_TYPE)
	assert_not_null(raider)
	await _fly(5.0, func() -> bool: return h.wings_out > 0)
	assert_eq(h.threat_fighters, 1, "its brain saw the raider within 15 km")
	assert_eq(h.wings_out, 1, "and the first wing launched")
	var states: Dictionary = {}
	await _fly(80.0, func() -> bool:
		states[main.world.get_node(^"CapitalBrains").brain_state(nova).get("state", &"")] = true
		return h.out_count() >= 12 and not h.is_launching())
	assert_true(states.has(&"hold") or states.has(&"launch"), "launching on orders it still holds (%s)" % [states.keys()])
	assert_eq(h.wings_out, 1, "the same threat: one wing copes")
	var killed: int = 0
	for entry: Dictionary in h.craft_out():
		if killed < 3:
			(entry["combatant"] as Combatant).damageable.kill(HitInfo.CAUSE_CARRIER_LOST)
			killed += 1
	await _fly(2.0, func() -> bool: return h.wings_out > 1)
	assert_eq(h.wing_losses, 3)
	assert_eq(h.wings_out, 2, "a quarter of the first wing lost: the second goes (Q73)")
	main.ships.release(raider)
	await _fly(150.0, func() -> bool: return h.out_count() == 0 and h.held_ships().is_empty() and not h.is_launching())
	assert_true(h.recoveries > 0, "the fight over, they came home (%d recovered)" % h.recoveries)
	assert_gt(h.lift_of("bay_fore").trips_down, 0, "down the lift")


func test_a_jump_waits_for_its_craft_then_leaves_the_rest() -> void:
	var cap: CapitalShip = _carrier(&"ea_hyperion")
	if cap == null:
		return
	var h: CapitalHangar = cap.hangar
	h.launch(&"starfury_ally", 2)
	await _fly(30.0, func() -> bool: return h.out_count() == 2 and not h.is_launching())
	assert_eq(h.out_count(), 2)
	h.options["wait_s"] = 3.0
	assert_false(h.ready_to_jump(), "it waits for them")
	assert_true(h.recalling)
	await _fly(5.0)
	assert_true(h.ready_to_jump(), "time up")
	assert_eq(h.out_count(), 0, "the hangar lets go of whoever is still out")
	assert_eq(h.left_behind + h.recoveries, 2, "each came home or was left (%d left)" % h.left_behind)
	assert_eq(h.queued_count(), 0)


func test_a_hulk_launches_nothing_and_takes_nobody_in() -> void:
	var cap: CapitalShip = _carrier(&"ea_hyperion")
	if cap == null:
		return
	var h: CapitalHangar = cap.hangar
	h.launch(&"starfury_ally", 1)
	await _fly(20.0, func() -> bool: return h.out_count() == 1 and not h.is_launching())
	assert_true(cap.scuttle(), "the crew makes it a hulk")
	await _fly(1.0)
	assert_false(h.has_power())
	assert_eq(h.launch(&"starfury_ally", 2), 0, "no launch without power (Q72)")
	assert_eq(h.recall_all(), 0, "and no docking")
	for bay: String in h.bay_names():
		assert_false(cap.set_bay_door(bay, true), "its doors do not move")
