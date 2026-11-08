extends GutTest
## The defensive turrets under the threading rules (M5-T21, AC19): the pick rides in the AI job, one tick behind on the frozen
## rows and memory, and lands at the join against each mount's stamp; the aim, gate and shot run on the main thread; the
## memory is written in the hit sweep's order; a shot's spread is a hash of the mount and the tick. So a seeded fight of
## two turreted transports and four AI raiders must give the same turrets, rows, commands and hits every tick, byte for
## byte, with the job on the step's thread and on the main thread (`threaded` against `delayed`), and with one thread and
## six. Skips, saying why, without the native library.

const TICKS: int = 300
const TRANSPORT: StringName = &"starfury_ally"
const RAIDER: StringName = &"raider_fighter"
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider"}


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no turrets to thread")
	return true


func test_threaded_equals_delayed_tick_for_tick() -> void:
	if _skipped():
		return
	var delayed: Dictionary = await _fight(&"delayed", 6)
	var threaded: Dictionary = await _fight(&"threaded", 6)
	assert_gt(int(delayed["shots"]), 4, "the turrets fired (%d shots)" % int(delayed["shots"]))
	assert_gt(int(delayed["picks"]), TICKS / 2, "a pick landed most ticks (%d)" % int(delayed["picks"]))
	assert_true(bool(threaded["off_main"]), "the threaded job ran off the main thread")
	assert_false(bool(delayed["off_main"]), "the delayed job ran on the main thread")
	for key: String in ["turrets", "rows", "commands", "hits"]:
		var first: int = _first_difference(delayed[key], threaded[key])
		assert_eq(first, -1, "%s: the same bits every tick (first difference at tick %d)" % [key, first])
	assert_eq(int(threaded["shots"]), int(delayed["shots"]), "the same shots")
	gut.p("threaded against delayed, %d ticks: %d turret shots, %d hits, %d picks" % [TICKS, int(threaded["shots"]),
			int(threaded["hits_total"]), int(threaded["picks"])])


func test_one_thread_and_six_give_the_same_fight() -> void:
	if _skipped():
		return
	var one: Dictionary = await _fight(&"threaded", 1)
	var six: Dictionary = await _fight(&"threaded", 6)
	assert_gt(int(one["shots"]), 4, "the turrets fired (%d shots)" % int(one["shots"]))
	for key: String in ["turrets", "rows", "commands", "hits"]:
		var first: int = _first_difference(one[key], six[key])
		assert_eq(first, -1, "%s: the same bits with one thread and six (first difference at tick %d)" % [key, first])


func test_the_own_hull_blocking_fire_is_the_same_on_every_schedule_and_thread_count() -> void:
	# Q33 (M5-T16): a Saturn 4 transport's own hull hides some of four raiders from its turrets; the blocked picks (in the
	# AI job) and the blocked shots (in the main thread's step) must land the same bits every way the step can run.
	if _skipped():
		return
	if not MeshAssets.read_manifest("saturn_4_transport").has("turret"):
		pending("the Saturn 4 is not generated (scripts/gen_assets.sh)")
		return
	var delayed: Dictionary = await _saturn_fight(&"delayed", 6)
	var threaded: Dictionary = await _saturn_fight(&"threaded", 6)
	var one: Dictionary = await _saturn_fight(&"threaded", 1)
	assert_gt(int(delayed["shots"]), 0, "the turrets fired")
	assert_gt(int(delayed["volumes"]), 10, "with the Saturn's own volumes in the core")
	for key: String in ["turrets", "rows", "commands", "hits"]:
		var first: int = _first_difference(delayed[key], threaded[key])
		assert_eq(first, -1, "%s: threaded against delayed, the same bits (first difference at tick %d)" % [key, first])
		first = _first_difference(one[key], threaded[key])
		assert_eq(first, -1, "%s: one thread against six, the same bits (first difference at tick %d)" % [key, first])
	gut.p("Saturn, %d ticks: %d turret shots, %d blocked by its own hull at the gate" % [TICKS, int(delayed["shots"]),
			int(delayed["blocked"])])


# A Saturn 4 transport on the civilian profile with its own turrets and four AI raiders around it, one astern and below:
# per tick the turrets', rows', commands' and hits' digests, as `_fight` takes them.
func _saturn_fight(mode: StringName, threads: int) -> Dictionary:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, mode, threads)
	var saturn: Combatant = scene.ship(&"saturn_4_transport", Factions.EARTH_ALLIANCE, "SATURN", Vector3.ZERO,
			{"type": "ai", "profile": "civilian"}, 3, true)
	var raiders: Array[Combatant] = []
	for at: Vector3 in [Vector3(0.0, -60.0, 420.0), Vector3(500.0, 200.0, -600.0), Vector3(-700.0, -100.0, 100.0),
			Vector3(100.0, 400.0, 300.0)]:
		raiders.append(scene.ship(RAIDER, Factions.RAIDERS, "RAIDER %d" % (raiders.size() + 1), at, RAIDER_AI,
				21 + raiders.size(), false, Basis.looking_at(-at.normalized(), Vector3.UP)))
	scene.attach()
	var turrets := PackedInt64Array()
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var hits := PackedInt64Array()
	var seen: int = 0
	for t: int in TICKS:
		if t == 2:
			for r: Combatant in raiders:
				scene.sim.note_hit(saturn.ship.get_instance_id(), r.ship.get_instance_id())
		await get_tree().physics_frame
		turrets.append(int(scene.sim.core.turret_digest()))
		rows.append(int(scene.sim.core.rows_digest()))
		commands.append(int(scene.sim.core.commands_digest()))
		hits.append(hash(_by_ship(scene, scene.hits.slice(seen))))
		seen = scene.hits.size()
	var readouts: PackedInt64Array = scene.sim.core.turret_readouts()
	var out: Dictionary = {"turrets": turrets, "rows": rows, "commands": commands, "hits": hits, "shots": readouts[0],
			"blocked": readouts[4], "volumes": int(scene.sim.core.turret_hull_count(saturn.ship.get_instance_id()))}
	await scene.free_scene(get_tree())
	return out


# The seeded fight flown `TICKS` ticks with the step `mode` and `threads` threads: per tick the turrets' digest (aims,
# targets, gates, shots, memory), the rows', the commands' and the hits'; the totals and the step's readouts.
func _fight(mode: StringName, threads: int) -> Dictionary:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, mode, threads)
	var transports: Array[Combatant] = []
	for i: int in 2:
		var t: Combatant = scene.ship(TRANSPORT, Factions.EARTH_ALLIANCE, "TRANSPORT %d" % (i + 1),
				Vector3(800.0 * i, 0.0, 0.0), {}, 1, true)
		scene.mount(t, Vector3(0.0, 3.0, -3.0), Vector3.UP, 200.0, "dorsal_fwd")
		scene.mount(t, Vector3(0.0, -2.0, 3.0), Vector3.DOWN, 200.0, "ventral_aft")
		transports.append(t)
	var raiders: Array[Combatant] = []
	for i: int in 4:
		var at := Vector3(-300.0 + 450.0 * i, 250.0 * (1 - 2 * (i % 2)), -900.0 - 120.0 * i)
		raiders.append(scene.ship(RAIDER, Factions.RAIDERS, "RAIDER %d" % (i + 1), at, RAIDER_AI, 11 + i, false,
				Basis.looking_at(-at.normalized(), Vector3.UP)))
	scene.attach()
	var host: Object = NativeBrains.host(get_tree())
	var turrets := PackedInt64Array()
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var hits := PackedInt64Array()
	var off_main: bool = false
	var seen: int = 0
	for t: int in TICKS:
		if t == 2:
			# Each raider starts as an attacker of a transport, so the turrets engage whatever the raiders do first.
			for i: int in raiders.size():
				scene.sim.note_hit(transports[i % 2].ship.get_instance_id(), raiders[i].ship.get_instance_id())
		await get_tree().physics_frame
		turrets.append(int(scene.sim.core.turret_digest()))
		rows.append(int(scene.sim.core.rows_digest()))
		commands.append(int(scene.sim.core.commands_digest()))
		hits.append(hash(_by_ship(scene, scene.hits.slice(seen))))
		seen = scene.hits.size()
		off_main = off_main or (host != null and bool(host.step_off_main()))
	var readouts: PackedInt64Array = scene.sim.core.turret_readouts()
	var out: Dictionary = {"turrets": turrets, "rows": rows, "commands": commands, "hits": hits, "shots": readouts[0],
			"picks": readouts[1], "hits_total": scene.hits.size(), "off_main": off_main}
	await scene.free_scene(get_tree())
	return out


# Hits with each ship named by its place in the scene (instance ids differ between runs).
static func _by_ship(scene: TurretScene, landed: Array) -> Array:
	var place: Dictionary = {}
	for i: int in scene.ships.size():
		place[scene.ships[i].ship.get_instance_id()] = i
	var out: Array = []
	for h: Array in landed:
		out.append([place.get(int(h[0]), -1), place.get(int(h[1]), -1), h[2]])
	return out


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())
