extends GutTest
## The station's big hulls under the threading rules (M7-T06, CLAUDE.md, architecture §17.13): avoidance, the fire lane and
## the brains read the frame's and drum's surfaces from the AI job's frozen rows; the hit sweep and the drum's skin rams run on
## the main thread. Four raiders attack two Starfuries parked on the far side of the turning drum, so they fly round its
## skin: the rows and commands must be the same bits every tick with the job threaded and delayed, and with one thread and
## six.

const TICKS: int = 240
const RAIDER: StringName = &"raider_fighter"
const ALLY: StringName = &"starfury_ally"
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider"}


func test_threaded_equals_delayed_and_one_thread_equals_six() -> void:
	var delayed: Dictionary = await _run(&"delayed", 6)
	if delayed.is_empty():
		pending("the babylon5_station asset is not generated")
		return
	var threaded: Dictionary = await _run(&"threaded", 6)
	var one: Dictionary = await _run(&"threaded", 1)
	assert_gt(int(delayed["avoiding"]), 0, "the raiders went round the station's skin (%d ship-ticks)" % int(delayed["avoiding"]))
	for key: String in ["rows", "commands"]:
		var first: int = _first_difference(delayed[key], threaded[key])
		assert_eq(first, -1, "%s: threaded against delayed, the same bits (first difference at tick %d)" % [key, first])
		first = _first_difference(one[key], threaded[key])
		assert_eq(first, -1, "%s: one thread against six, the same bits (first difference at tick %d)" % [key, first])
	assert_eq(threaded["avoiding"], delayed["avoiding"])


# The raid flown `TICKS` ticks with the step `mode` and `threads` threads: per tick the rows' and commands' digests, and how
# many ship-ticks the raiders spent dodging. Empty without the asset.
func _run(mode: StringName, threads: int) -> Dictionary:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, mode, threads)
	var station := Station.new()
	station.name = "Station"
	if not station.build():
		station.free()
		await scene.free_scene(get_tree())
		return {}
	scene.world.spawn(station, scene.world.to_universe(Vector3.ZERO))
	# The forward drum's side, 417 m out on +x; the allies 900 m beyond it on -x, the raiders 700 m out on +x.
	var drum_z: float = station.drum_origin.z - 900.0
	for i: int in 2:
		scene.ship(ALLY, Factions.EARTH_ALLIANCE, "ALLY %d" % (i + 1), Vector3(-1300.0, 60.0 * i, drum_z + 80.0 * i))
	var raiders: Array[Combatant] = []
	for i: int in 4:
		var at := Vector3(1100.0, -90.0 + 60.0 * i, drum_z - 120.0 + 80.0 * i)
		raiders.append(scene.ship(RAIDER, Factions.RAIDERS, "RAIDER %d" % (i + 1), at, RAIDER_AI, 31 + i, false,
				Basis.looking_at(Vector3.LEFT, Vector3.UP)))
	var rams := RamResolver.new()
	rams.name = "RamResolver"
	rams.world = scene.world
	scene.space.add_child(rams)
	scene.attach()
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var avoiding: int = 0
	for t: int in TICKS:
		await get_tree().physics_frame
		rows.append(int(scene.sim.core.rows_digest()))
		commands.append(int(scene.sim.core.commands_digest()))
		for r: Combatant in raiders:
			var driver := r.driver as AiPilotDriver
			avoiding += 1 if driver != null and driver.avoiding else 0
	var out: Dictionary = {"rows": rows, "commands": commands, "avoiding": avoiding}
	await scene.free_scene(get_tree())
	return out


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())
