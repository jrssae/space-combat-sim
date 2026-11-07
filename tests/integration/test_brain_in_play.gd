extends GutTest
## The native brains in play beyond the Q16 fights (M4-T17 fix round 1): a pilot whose host declines a think mid-fight (the
## rows moved under the scan: a rebase or a resolver's resync in the same frame) holds its last command for that tick instead
## of running its GDScript brain on a stale mirror, and the driver counts it (`ai.thinks_fallback`); a hit it took earlier
## never produces a spurious evade on such a tick; a ram committed from outside whose target leaves is uncommitted once, not
## pushed again every think; the core's new column reads fail on no body of a real ship. Real ships and drivers, the core
## on, in a space of their own. Skips, saying why, when the library is not built.

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const SETTINGS: Array[StringName] = [&"ai_think_rate"]

var _saved: Dictionary = {}
var space: SubViewport
var world: WorldFrame
var bolts: Node3D


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"ai_think_rate", false)  # every ship thinks every tick: the test counts thinks
	Factions.reset()
	ContactScan.invalidate()
	space = SubViewport.new()
	space.own_world_3d = true
	space.world_3d = World3D.new()
	add_child_autofree(space)
	world = WorldFrame.new()
	world.name = "World"
	space.add_child(world)
	bolts = Node3D.new()
	bolts.name = "Projectiles"
	world.add_child(bolts)


func after_each() -> void:
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	Factions.reset()
	ContactScan.invalidate()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no native brains to test")
	return true


func _ship(display_name: String, faction: StringName, at: Vector3, profile: String, seed_value: int,
		aggression: Variant = null) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(RAIDER_SPEC) as ShipSpec, world, bolts, {
		ShipAssembly.OPT_FACTION: faction, ShipAssembly.OPT_DISPLAY_NAME: display_name,
		ShipAssembly.OPT_FORCE_ASSIST: true, ShipAssembly.OPT_AI: true})
	world.spawn(c.ship, world.to_universe(at), Basis.looking_at(Vector3(0.0, 0.0, -signf(at.z) if at.z != 0.0 else -1.0), Vector3.UP))
	var spec: Dictionary = {"type": "ai", "profile": profile}
	if aggression != null:
		spec["aggression"] = aggression
	c.driver.brain = BrainFactory.from_behaviour(spec, UniversePos.new(), seed_value)["brain"] as PilotBrain
	c.damageable.invulnerable = true
	return c


func _pilot(c: Combatant) -> AiPilot:
	return c.driver.brain as AiPilot


# A bolt hit on `c` from `shooter`, as the resolver reports it (the driver notes the time and the attacker).
func _bolt_hit(c: Combatant, shooter: Combatant) -> void:
	c.damageable.apply_hit(HitInfo.new(c.ship.get_instance_id(), shooter.ship.get_instance_id(), shooter.faction, 1.0,
			c.ship.global_position, Vector3.FORWARD, 400.0, HitInfo.CAUSE_BOLT))


func test_a_declined_think_holds_the_last_command_and_is_counted_never_a_stale_gdscript_think() -> void:
	if _skipped():
		return
	var a: Combatant = _ship("RAIDER 1", Factions.RAIDERS, Vector3(0.0, 0.0, 600.0), "raider", 11)
	var b: Combatant = _ship("ALPHA 2", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -600.0), "ally_starfury", 12)
	for i: int in 20:
		await get_tree().physics_frame
	assert_gt(AiPilotDriver.thinks_native(), 0, "the pilots think natively")
	assert_eq(AiPilotDriver.thinks_fallback(), 0, "no fallback so far")
	var pilot: AiPilot = _pilot(a)
	assert_true(pilot.native_last, "RAIDER 1's last think was native")
	assert_eq(String(pilot.current.id), "attack", "it attacks")
	# A hit a while ago: the native brain reacted and is back to attacking; the GDScript objects never saw the reaction.
	_bolt_hit(a, b)
	var waited: int = 0
	while waited < 1200 and not (pilot.current != null and pilot.current.id == &"attack" and a.driver.last_bolt_hit_s < SimClock.now() - 8.0):
		await get_tree().physics_frame
		waited += 1
	assert_eq(String(pilot.current.id), "attack", "back to attacking after the reaction")
	var sim: SimCore = SimCore.for_tree(get_tree())
	assert_not_null(sim, "the core is on")
	# The scan of this frame, then the rows move under it (a rebase in the same frame): the host must decline this think.
	await get_tree().physics_frame
	var scan: ContactScan = ContactScan.shared(get_tree())
	assert_true(scan.rows_fresh(), "the frame's scan is fresh")
	world.rebase(Vector3(300.0, 0.0, -150.0))
	assert_false(scan.rows_fresh(), "after the rebase the rows moved under the scan")
	var cmd_before: Dictionary = a.ship._flight.to_dict()
	var switches_before: int = pilot.switches
	a.driver._woken = true
	a.driver.step(1.0 / 60.0)
	assert_eq(AiPilotDriver.thinks_fallback(), 1, "the declined think is counted as a fallback (the count is per tick)")
	assert_eq(String(pilot.current.id), "attack", "no spurious evade from the stale GDScript hit reaction")
	assert_eq(pilot.switches, switches_before, "nothing switched")
	assert_true(pilot.native_last, "the pilot still counts as native")
	assert_eq(a.ship._flight.to_dict(), cmd_before, "the ship holds its last command for that tick")
	# The same with a resolver's resync of a touched body in the same frame.
	await get_tree().physics_frame
	scan = ContactScan.shared(get_tree())
	sim.touch(b.ship)
	sim.core.resync_touched_now()
	assert_false(scan.rows_fresh(), "after the resync the rows changed under the scan")
	a.driver._woken = true
	a.driver.step(1.0 / 60.0)
	assert_eq(AiPilotDriver.thinks_fallback(), 1, "counted again in this tick")
	assert_eq(String(pilot.current.id), "attack", "and still no spurious evade")
	# The next frame thinks natively again.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(AiPilotDriver.thinks_native(), 0, "native thinks resume")
	assert_eq(sim.core.column_read_failures(), 0, "every hull, selection and reach read of a real ship succeeded")


func test_a_ram_committed_from_outside_is_uncommitted_once_when_its_target_leaves() -> void:
	if _skipped():
		return
	var rammer: Combatant = _ship("RAIDER 1", Factions.RAIDERS, Vector3(0.0, 0.0, 900.0), "raider", 21, "reckless")
	var target: Combatant = _ship("ALPHA 2", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -900.0), "ally_starfury", 22)
	for i: int in 10:
		await get_tree().physics_frame
	var pilot: AiPilot = _pilot(rammer)
	assert_true(pilot.native_last, "the rammer thinks natively")
	var ram := pilot.behaviour(&"ram") as BehaviourRam
	assert_true(ram.commit(pilot.context), "committed from outside, through the native slot")
	assert_eq(ram.target_id_value, target.targetable.get_instance_id(), "to the only hostile")
	var waited: int = 0
	while waited < 120 and (pilot.current == null or pilot.current.id != &"ram"):
		await get_tree().physics_frame  # the attack keeps control through its dwell, as the GDScript rule says
		waited += 1
	assert_eq(String(pilot.current.id), "ram", "the pilot flies the ram")
	# The target leaves play: the native ram lets go; the GDScript object must read that, and stay uncommitted.
	target.ship.visible = false
	target.ship.process_mode = Node.PROCESS_MODE_DISABLED
	for i: int in 6:
		await get_tree().physics_frame
	assert_false(ram.committed, "the GDScript ram reads the native uncommit")
	assert_ne(String(pilot.current.id), "ram", "and the pilot does something else")
	var rolls: int = ram.rolls
	for i: int in 6:
		await get_tree().physics_frame
	assert_false(ram.committed, "it is not committed again by the facade")
	assert_eq(ram.rolls, rolls, "and no roll was spent on a stale push")
