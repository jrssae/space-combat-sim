extends GutTest
## The mine kernel on the core's rows (M4-T20, architecture §17.13): each tick a third of the mines ask natively for a
## hostile hull inside their trigger and a mine that goes off asks for the hulls in its blast, over the core's rows, bit for
## bit with `MineStandin`'s GDScript, which stays the reference behind `perf_native_weapons`. Hulls are put within a
## millimetre of a trigger's edge, and a seeded belt crossed by fighters is run once on each path: the same mines check, go off on
## the same ticks, hurt the same hulls and are laid again on the same ticks. Skips, saying why, without the native library.

const NATIVE_CLASS: StringName = &"ScsWeaponRows"
const DT: float = 1.0 / 60.0

var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in WeaponRowsScene.SETTINGS:
		_saved[key] = Settings.get_value(key)


func after_each() -> void:
	for key: StringName in _saved:
		Settings.set_value(key, _saved[key])
	MissileStandin.native_rows = null
	StaticRows.clear()
	ContactScan.invalidate()
	Factions.reset()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no weapon kernels to test")
	return true


# Hulls on the edge of the triggers: each hostile drone sits at the trigger's reach from its mine, within a millimetre
# inside or outside, along a seeded direction; a friend sits well inside another.
func _edge_scene(native: bool) -> Dictionary:
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"perf_native_core", true)
	Settings.set_value(&"perf_native_weapons", native)
	StaticRows.clear()
	ContactScan.invalidate()
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var director := StandinDirector.new()
	director.name = "Standins"
	director.world = world
	director.projectiles = projectiles
	world.add_child(director)
	director.set_physics_process(false)
	director.active = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var rows: Array[Dictionary] = []
	var drones: Array[TargetDrone] = []
	var anchor := Vector3(1234.567, -89.25, 4321.125)
	for i: int in 60:
		var offset := Vector3(rng.randf_range(-2000, 2000), rng.randf_range(-300, 300), rng.randf_range(-2000, 2000))
		rows.append({"offset": offset, "faction": Factions.EARTH_ALLIANCE if i % 2 == 0 else Factions.RAIDERS})
	var mines: MineStandin = director.add_mines(rows, world.to_universe(anchor))
	for i: int in 60:
		var drone := (load("res://tests/fixtures/target_drone.tscn") as PackedScene).instantiate() as TargetDrone
		drone.faction = Factions.RAIDERS if i % 2 == 0 else Factions.EARTH_ALLIANCE
		if i % 10 == 9:
			drone.faction = Factions.EARTH_ALLIANCE if i % 2 == 0 else Factions.RAIDERS  # a friend of the mine
		drone.set_physics_process(false)
		drone.freeze = true
		world.spawn(drone, world.to_universe(Vector3(0.0, 9000.0 + 50.0 * i, 0.0)))
		drones.append(drone)
	# Now each drone where its mine's trigger ends: the mine's centre as the step computes it, the reach along a direction.
	for i: int in 60:
		var centre: Vector3 = mines.global_position + (rows[i]["offset"] as Vector3)
		var direction := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var reach: float = MineStandin.TRIGGER_RADIUS_M + drones[i].damageable.bounding_radius
		var at: Vector3 = centre + direction * reach
		# Nudge along one axis, half a millimetre at a time, until the squared distance falls on the wanted side.
		var inside: bool = i % 3 != 0
		for step: int in 64:
			var d_sq: float = at.distance_squared_to(centre)
			if (d_sq <= reach * reach) == inside:
				break
			at.x = at.x - signf(direction.x) * 0.0005 if inside else at.x + signf(direction.x) * 0.0005
		drones[i].global_position = at
	var hits: Array = []
	for i: int in drones.size():
		drones[i].damageable.hit_taken.connect(func(info: HitInfo) -> void: hits.append([i, info.damage, info.point, info.normal]))
	var core: SimCore = SimCore.attach(world)
	return {"director": director, "mines": mines, "core": core, "hits": hits}


func test_hulls_on_the_edge_of_a_trigger_set_off_the_same_mines_on_both_paths() -> void:
	if _skipped():
		return
	var logs: Array = []
	for native: bool in [false, true]:
		var scene: Dictionary = _edge_scene(native)
		var director: StandinDirector = scene["director"]
		var mines: MineStandin = scene["mines"]
		var entries: Array = []
		var now_s: float = SimClock.now() + 100.0
		for tick: int in 6:
			(scene["core"] as SimCore).sync_now()
			director.step(DT, now_s, ContactScan.from_tree(get_tree()))
			now_s += DT
			var alive := PackedByteArray()
			for i: int in mines.count():
				alive.append(1 if mines.is_alive(i) else 0)
			var hits: Array = (scene["hits"] as Array).duplicate()
			hits.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
			entries.append([alive, mines.checked_last_tick, var_to_bytes(hits)])
		assert_eq(director.weapons_path(), &"native" if native else &"gdscript")
		logs.append(entries)
		var world: Node = director.get_parent()
		remove_child(world)
		world.free()  # the next scene's core and scan see only their own bodies
	for tick: int in 6:
		assert_eq(var_to_bytes(logs[1][tick]), var_to_bytes(logs[0][tick]), "tick %d: the same mines alive, checked and hurting the same hulls" % tick)
	var gone: int = 0
	for b: int in (logs[0][5] as Array)[0]:
		gone += 1 - b
	assert_between(gone, 10, 50, "some mines on the edge went off and some did not")


func test_a_seeded_belt_goes_off_and_is_laid_again_on_the_same_ticks_on_both_paths() -> void:
	if _skipped():
		return
	var reference: WeaponRowsScene = WeaponRowsScene.build(self, 23, false)
	reference.run(840)
	reference.dispose()
	var native: WeaponRowsScene = WeaponRowsScene.build(self, 23, true)
	native.run(840)
	assert_eq(native.director.weapons_path(), &"native")
	var detonated: int = 0
	var laid_again: int = 0
	for t: int in reference.log.size():
		var a: Dictionary = reference.log[t]
		var b: Dictionary = native.log[t]
		for key: String in ["mines", "checked", "hits"]:
			if var_to_bytes(a[key]) != var_to_bytes(b[key]):
				fail_test("tick %d differs in %s: %s against %s" % [a["tick"], key, str(a[key]).left(200), str(b[key]).left(200)])
				return
		if t > 0:
			var before: PackedByteArray = reference.log[t - 1]["mines"]
			var now: PackedByteArray = a["mines"]
			for i: int in now.size():
				detonated += 1 if before[i] == 1 and now[i] == 0 else 0
				laid_again += 1 if before[i] == 0 and now[i] == 1 else 0
	assert_gt(detonated, 3, "mines went off")
	assert_gt(laid_again, 0, "and were laid again after their wait")
