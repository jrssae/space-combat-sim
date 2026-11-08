extends GutTest
## A ship's own hull blocks its turrets' fire (M5-T16, Q33): the Saturn 4 transport's three turrets (two flanks on the
## command disc, one dorsal on the cargo section, Q32) never fire at a raider astern of it and a little below, where the
## cargo section and the engine stand between, though both flanks have it inside their arcs; with the hull's volumes taken
## from the core the same raider is fired at, and so is a raider beside the ship. The ship and the raiders hold still, so
## the geometry alone decides. Skips, saying why, without the native library or the Saturn 4's generated asset.

const TRANSPORT: StringName = &"saturn_4_transport"
const RAIDER: StringName = &"raider_fighter"
## Body frame (the Saturn at the origin, unturned): 320 m behind its stern, 60 m below its axis.
const ASTERN_BELOW := Vector3(0.0, -60.0, 400.0)
## Off its starboard side, level with the astern raider.
const BESIDE := Vector3(450.0, -60.0, 0.0)
const TICKS: int = 360


func _skipped() -> bool:
	if not NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		pending("the native library is not built (scripts/build_native.sh), so there are no turrets")
		return true
	if not MeshAssets.read_manifest(String(TRANSPORT)).has("turret"):
		pending("the Saturn 4 is not generated (scripts/gen_assets.sh), so it has no turrets")
		return true
	return false


func test_a_raider_astern_and_below_is_never_fired_at_its_hull_is_in_the_way() -> void:
	if _skipped():
		return
	var run: Dictionary = await _hold(ASTERN_BELOW, true)
	assert_eq(int(run["mounts"]), 3, "two flanks and the dorsal (Q32)")
	assert_gt(int(run["hull_volumes"]), 10, "the core holds the Saturn's own volumes")
	assert_eq(int(run["in_arc"]), 2, "both flanks have it inside their arcs: only the hull hides it")
	assert_eq(int(run["targeted"]), 0, "no turret picks it")
	assert_eq(int(run["shots"]), 0, "and none fires")


func test_without_its_hull_the_same_raider_is_fired_at() -> void:
	if _skipped():
		return
	var run: Dictionary = await _hold(ASTERN_BELOW, false)
	assert_gt(int(run["targeted"]), 0, "a flank picks it once nothing is in the way")
	assert_gt(int(run["shots"]), 0, "and fires")


func test_a_raider_beside_the_ship_is_fired_at() -> void:
	if _skipped():
		return
	var run: Dictionary = await _hold(BESIDE, true)
	assert_gt(int(run["targeted"]), 0, "the starboard flank picks it")
	assert_gt(int(run["shots"]), 0, "and fires past nothing")


# The Saturn and one raider at `at` (its frame), both still, the raider made an attacker of the Saturn; `TICKS` ticks with
# the hull's volumes in the core or taken out. Counts the mounts, how many have the raider inside their arc, how many
# picked it, and the shots.
func _hold(at: Vector3, with_hull: bool) -> Dictionary:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, &"threaded", 1)
	var saturn: Combatant = scene.ship(TRANSPORT, Factions.EARTH_ALLIANCE, "SATURN", Vector3.ZERO, {}, 1, true)
	var raider: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "RAIDER", at)
	scene.attach()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var body: int = saturn.ship.get_instance_id()
	var volumes: int = int(scene.sim.core.turret_hull_count(body))
	if not with_hull:
		scene.sim.core.set_turret_hull(body, PackedFloat64Array())
	var in_arc: int = 0
	for m: TurretMount in saturn.turrets:
		var base: Vector3 = saturn.ship.global_transform * m.position
		var up: Vector3 = (saturn.ship.global_basis * m.up).normalized()
		var to: Vector3 = (raider.ship.global_position - base).normalized()
		if rad_to_deg(asin(clampf(to.dot(up), -1.0, 1.0))) >= 90.0 - m.arc_deg * 0.5:
			in_arc += 1
	var targeted: Dictionary = {}
	for t: int in TICKS:
		scene.sim.note_hit(body, raider.ship.get_instance_id())
		await get_tree().physics_frame
		for m: TurretMount in saturn.turrets:
			if int(scene.state(m)["target"]) == raider.ship.get_instance_id():
				targeted[m] = true
	var out: Dictionary = {"mounts": saturn.turrets.size(), "hull_volumes": volumes, "in_arc": in_arc,
			"targeted": targeted.size(), "shots": scene.shots_total()}
	gut.p("raider at %s, hull %s: %s" % [at, "on" if with_hull else "off", out])
	await scene.free_scene(get_tree())
	return out
