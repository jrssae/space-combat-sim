extends GutTest
## The player's candidate list built when read (M4-T34): with `perf_targeting_on_read` on, the player's targeting computer
## checks its selection every tick, as every AI ship's does, and builds its list of every targetable only when something
## reads it (the HUD and the radar once a frame, a selection command), at most once per refresh. The selection and its
## `target_changed` signals are the same tick by tick as with the list built every tick (off, the reference), and a list read
## right after a refresh is the same list.

const STARFURY_PATH: String = "res://assets/ships/starfury_aurora.tres"
const STEPS: int = 400

var world: WorldFrame
var projectiles: Node3D
var _saved: Variant


func before_each() -> void:
	_saved = Settings.get_value(&"perf_targeting_on_read")


func after_each() -> void:
	Settings.set_value(&"perf_targeting_on_read", _saved)


func _world() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	ContactScan.invalidate()


func _player() -> Combatant:
	var combatant: Combatant = ShipAssembly.build(load(STARFURY_PATH) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(combatant.ship, world.to_universe(Vector3.ZERO))
	combatant.damageable.invulnerable = true
	return combatant


func _marker(label: String, faction: StringName, at: Vector3, broadcast_m: float = 0.0) -> Targetable:
	var holder := Node3D.new()
	holder.name = label.replace(" ", "_")
	world.add_child(holder)
	holder.position = at
	var targetable := Targetable.new()
	targetable.name = "Targetable"
	targetable.display_name = label
	targetable.faction = faction
	targetable.broadcast_range_m = broadcast_m
	holder.add_child(targetable)
	return targetable


func _list(infos: Array[TargetInfo]) -> String:
	var parts := PackedStringArray()
	for info: TargetInfo in infos:
		parts.append(var_to_str([info.display_name, info.faction, info.position, info.velocity, info.hull_fraction,
				info.bounding_radius, info.broadcast_range_m]))
	return ", ".join(parts)


# A seeded run of selection commands and moves, stepped by hand: per step the selection, the signals and the list read.
func _run(on: bool) -> PackedStringArray:
	Settings.set_value(&"perf_targeting_on_read", on)
	_world()
	var player: Combatant = _player()
	var targeting: TargetingController = player.ship.targeting
	targeting.set_physics_process(false)  # stepped by hand below
	assert_true(targeting.keeps_candidates, "the player's controller keeps its list")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3402
	var markers: Array[Targetable] = []
	for i: int in 16:
		var faction: StringName = [Factions.RAIDERS, Factions.EARTH_ALLIANCE, Factions.NEUTRAL][i % 3]
		var at := Vector3(rng.randf_range(-30000.0, 30000.0), rng.randf_range(-3000.0, 3000.0), rng.randf_range(-30000.0, 30000.0))
		markers.append(_marker("T%d" % i, faction, at, 40000.0 if i % 7 == 0 else 0.0))
	var names: Dictionary = {0: "none"}
	for m: Targetable in markers:
		names[m.get_instance_id()] = m.display_name
	var signals: Array[String] = []
	targeting.target_changed.connect(func(id: int) -> void: signals.append(names.get(id, "?")))
	var log := PackedStringArray()
	for step: int in STEPS:
		var m: Targetable = markers[rng.randi_range(0, markers.size() - 1)]
		var holder := m.get_parent() as Node3D
		var roll: float = rng.randf()
		if rng.randf() < 0.5:
			# Something moves between the refresh and the command, as Jolt's step moves ships between two ticks.
			var mover := markers[rng.randi_range(0, markers.size() - 1)].get_parent() as Node3D
			mover.position += Vector3(rng.randf_range(-8000.0, 8000.0), 0.0, rng.randf_range(-8000.0, 8000.0))
		if roll < 0.35:
			holder.position += Vector3(rng.randf_range(-8000.0, 8000.0), 0.0, rng.randf_range(-8000.0, 8000.0))
		elif roll < 0.45:
			holder.visible = not holder.visible
		elif roll < 0.6:
			targeting.select_id(markers[rng.randi_range(0, markers.size() - 1)].get_instance_id())
		elif roll < 0.68:
			targeting.select_nearest_hostile()
		elif roll < 0.72 and markers.size() > 6:
			markers.erase(m)
			holder.free()
		elif roll < 0.76:
			targeting.clear_selection()
		targeting.refresh()
		var line: String = "%d sel %s name %s signals %s" % [step, names.get(targeting.selected_id(), "none"),
				targeting.selected_name(), str(signals)]
		signals.clear()
		if step % 3 == 0:
			line += " list " + _list(targeting.candidates())
		log.append(line)
	world.free()
	return log


func test_the_selection_and_the_list_read_are_the_same_either_way() -> void:
	var every_tick: PackedStringArray = _run(false)
	var on_read: PackedStringArray = _run(true)
	assert_eq(on_read.size(), every_tick.size())
	for i: int in every_tick.size():
		if on_read[i] != every_tick[i]:
			fail_test("step %d differs:\n%s\nagainst\n%s" % [i, on_read[i], every_tick[i]])
			return
	pass_test("%d steps alike" % every_tick.size())


func test_no_list_is_built_while_nothing_reads_it() -> void:
	Settings.set_value(&"perf_targeting_on_read", true)
	_world()
	var player: Combatant = _player()
	for i: int in 30:
		_marker("T%d" % i, Factions.RAIDERS, Vector3(float(i) * 100.0, 0.0, -2000.0))
	var targeting: TargetingController = player.ship.targeting
	await get_tree().physics_frame
	var before: int = TargetInfo.built_count
	for i: int in 10:
		await get_tree().physics_frame
	assert_eq(TargetInfo.built_count, before, "ten ticks with no reader build no TargetInfo")
	assert_eq(targeting.candidates().size(), 30, "a read builds the list")
	var after_read: int = TargetInfo.built_count
	targeting.candidates()
	assert_eq(TargetInfo.built_count, after_read, "a second read before the next refresh builds nothing")
	await get_tree().physics_frame
	targeting.candidates()
	assert_eq(TargetInfo.built_count, after_read + 30, "after a refresh the next read builds it again")
