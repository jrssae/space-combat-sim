extends GutTest
## The station's defence grid under the threading rules (M7-T07, AC6, CLAUDE.md, architecture §17.13): the guns' pick runs in
## the AI job one tick behind on the frozen rows and latch; the aim, gate, shots, interceptions and the latch's writes run on the
## main thread. Six raiders attack the station's bow; they fire first, the grid opens on them and the interceptors work. The
## rows, the commands and the turrets' digest must be the same bits every tick with the job threaded and delayed, and with one
## thread and six.

const TICKS: int = 600
const RAIDER: StringName = &"raider_fighter"
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider", "orders": "attack", "objective": Station.DISPLAY_NAME}


func test_threaded_equals_delayed_and_one_thread_equals_six() -> void:
	var delayed: Dictionary = await _run(&"delayed", 6)
	if delayed.is_empty():
		pending("the babylon5_station asset is not generated")
		return
	var threaded: Dictionary = await _run(&"threaded", 6)
	var one: Dictionary = await _run(&"threaded", 1)
	assert_true(bool(delayed["free"]), "the raiders fired first and the grid opened on them")
	assert_gt(int(delayed["gun_shots"]), 0, "the guns fired (%d)" % int(delayed["gun_shots"]))
	assert_gt(int(delayed["intercepts"]), 0, "the interceptors shot something down (%d)" % int(delayed["intercepts"]))
	for key: String in ["rows", "commands", "turrets"]:
		var first: int = _first_difference(delayed[key], threaded[key])
		assert_eq(first, -1, "%s: threaded against delayed, the same bits (first difference at tick %d)" % [key, first])
		first = _first_difference(one[key], threaded[key])
		assert_eq(first, -1, "%s: one thread against six, the same bits (first difference at tick %d)" % [key, first])


# The raid flown `TICKS` ticks with the step `mode` and `threads` threads: per tick the digests, and what the grid did. Empty
# without the asset.
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
	# 1.6 km off the bow, above the spike: in the light guns', the heavy cannons' and the interceptors' reach.
	var bow: Vector3 = station.to_world(station.hardpoints.mount("H1")["position"], StationHardpoints.FRAME)
	for i: int in 6:
		var at: Vector3 = bow + Vector3(-250.0 + 100.0 * i, 300.0 + 40.0 * i, -900.0)
		scene.ship(RAIDER, Factions.RAIDERS, "RAIDER %d" % (i + 1), at, RAIDER_AI, 71 + i, false,
				Basis.looking_at(Vector3.BACK, Vector3.UP))
	for c: Combatant in scene.ships:
		scene.park_on_death(c)
	scene.attach()
	TurretMount.rebind_all()
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var turrets := PackedInt64Array()
	for t: int in TICKS:
		await get_tree().physics_frame
		rows.append(int(scene.sim.core.rows_digest()))
		commands.append(int(scene.sim.core.commands_digest()))
		turrets.append(int(scene.sim.core.turret_digest()))
	var r: PackedInt64Array = station.grid.readouts()
	var out: Dictionary = {"rows": rows, "commands": commands, "turrets": turrets, "gun_shots": r[0] + r[1],
			"intercepts": r[2], "free": station.grid.free_sides().has(String(Factions.RAIDERS))}
	await scene.free_scene(get_tree())
	return out


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())
