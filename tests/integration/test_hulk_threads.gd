extends GutTest
## Disabled hulks with threads (M10-T10, D12.7, architecture §17.13): the seeded battle (`SeededBattle`) beside two disabled
## Omegas, one winding down and drifting in Jolt and one a hulk row in the low-attention tier, gives the same rows tick for tick
## and the same drift with one thread and six. Reports what the wind-down costs a tick.

const TICKS: int = 240
const TYPE: StringName = &"ea_omega"

var _threads_backup: Variant = null


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # its capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)


func test_hulks_beside_a_seeded_battle_give_the_same_rows_with_one_thread_and_six() -> void:
	var one: Dictionary = await _battle(1)
	var six: Dictionary = await _battle(6)
	if one.is_empty() or six.is_empty():
		return
	assert_eq((one["rows"] as Array).size(), TICKS)
	var first: int = -1
	for i: int in TICKS:
		if one["rows"][i] != six["rows"][i]:
			first = i
			break
	assert_eq(first, -1, "the same rows tick for tick (first difference at %d)" % first)
	assert_eq(one["near"], six["near"], "the near hulk drifts the same")
	assert_eq(one["row"], six["row"], "and the tier's hulk row")
	assert_eq(one["hulks"], 1, "one hulk row in the tier")
	gut.p("capital flight with a hulk winding down: mean %.1f us a tick (wall clock, debug build)" % float(one["flight_us"]))


# The seeded battle with `threads` threads and the two hulks: each tick's rows digest, where the near hulk and the tier row
# ended, the tier's hulk count and the capital flight's mean cost.
func _battle(threads: int) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self)
	var world: WorldFrame = fight["world"]
	var sim: SimCore = fight["sim"]
	var centre: Vector3 = (fight["ships"] as Array[Combatant])[0].ship.global_position
	var near: CapitalShip = _omega(world, "EAS Agamemnon", centre + Vector3(0.0, 2500.0, 0.0))
	var far: CapitalShip = _omega(world, "EAS Achilles", centre + Vector3(0.0, -30000.0, 0.0))
	if near == null or far == null:
		await SeededBattle.finish(fight)
		return {}
	await get_tree().physics_frame
	near.set_course(Vector3.FORWARD, near.linear_velocity + Vector3(0.0, 0.0, -30.0))
	_disable(near)
	_disable(far)
	var id: int = far.get_instance_id()
	sim.core.tier_add(SimCore.KIND_CAPITAL, id, far.damageable.get_instance_id(), 0, far.global_position, far.linear_velocity,
			far.global_basis, Vector3(0.0, 0.001, 0.0))
	sim.core.tier_set_attrs(id, far.targetable.get_instance_id(), far.faction, far.targetable.display_name,
			far.damageable.bounding_radius, far.targetable.broadcast_range_m, far.damageable.hull.fraction())
	sim.core.tier_set_control(id, far.cruise_velocity + Vector3(0.0, 0.0, -50.0), PackedFloat64Array(), 0.0, false)
	sim.core.tier_set_hulk(id, true)
	far.park_for_tier()
	far.settle_as_hulk()
	var flight: CapitalFlight = CapitalFlight.of(world)
	var rows: Array = []
	var cost: float = 0.0
	for t: int in TICKS:
		await get_tree().physics_frame
		rows.append(int(sim.core.rows_digest()))
		cost += float(flight.last_us)
	var state: Dictionary = sim.core.tier_state(id)
	var pose: Array = [state.get("position"), state.get("velocity"), state.get("angular"), state.get("basis")]
	var out: Dictionary = {"rows": rows, "near": [near.global_position, near.linear_velocity, near.angular_velocity],
			"row": pose, "hulks": int(sim.core.tier_hulks()), "flight_us": cost / float(TICKS)}
	sim.core.tier_take(id)
	await SeededBattle.finish(fight)
	return out


func _omega(world: WorldFrame, display_name: String, at: Vector3) -> CapitalShip:
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, display_name, Vector3.ZERO)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap != null:
		world.spawn(cap, world.to_universe(at), Basis.IDENTITY)
	return cap


# Takes its bridge out as a hit would, leaving a hulk (M10-T65, Q72; god mode never applies to it).
func _disable(cap: CapitalShip) -> void:
	for s: CapitalSection in cap.damage.sections.values():
		if s.kind == CapitalSection.BRIDGE:
			var info := HitInfo.new(cap.get_instance_id(), 0, &"", s.hp, cap.global_transform * s.box.get_center(), Vector3.ZERO, 0.0,
					HitInfo.CAUSE_CONSOLE)
			info.set_meta(CapitalShip.SECTION_META, s.name)
			info.set_meta(CapitalShip.REST_POINT_META, s.box.get_center())
			cap.damageable.apply_hit(info)
	assert_true(cap.is_hulk())
