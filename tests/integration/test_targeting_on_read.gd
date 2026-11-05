extends GutTest
## The player's candidate list built when read (M4-T34): with `perf_targeting_on_read` on, the player's targeting computer
## checks its selection every tick, as every AI ship's does, and builds its list of every targetable only when something
## reads it (the HUD and the radar once a frame, a selection command), at most once per refresh. The selection and its
## `target_changed` signals are the same tick by tick as with the list built every tick (off, the reference), and a list read
## right after a refresh is the same list.

const STARFURY_PATH: String = "res://assets/ships/starfury_aurora.tres"
const STEPS: int = 600

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


# A seeded run stepped by hand, as ticks go: a refresh, then things move, hide or go before anything reads the list (Jolt's
# step, a hit), then sometimes a selection command, and only sometimes a read, so a read or a command often meets a list
# several refreshes old or targets that left since. Per step: the selection, its signals, the selection's name when read, and
# the list when read with nothing changed since the refresh. Returns [log, commands that selected a target already out of
# reach when they ran, late list reads].
func _run(on: bool) -> Array:
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
		var at := Vector3(rng.randf_range(-24000.0, 24000.0), rng.randf_range(-3000.0, 3000.0), rng.randf_range(-24000.0, 24000.0))
		markers.append(_marker("T%d" % i, faction, at, 40000.0 if i % 7 == 0 else 0.0))
	var names: Dictionary = {0: "none"}
	for m: Targetable in markers:
		names[m.get_instance_id()] = m.display_name
	var signals: Array[String] = []
	targeting.target_changed.connect(func(id: int) -> void: signals.append(names.get(id, "?")))
	var log := PackedStringArray()
	var stale_selects: int = 0
	var late_reads: int = 0
	for step: int in STEPS:
		targeting.refresh()
		var line: String = "%d refresh sel %s signals %s" % [step, names.get(targeting.selected_id(), "none"), str(signals)]
		signals.clear()
		# After the refresh, before anything reads: moves (some across the 25 km reach), hides, a target gone.
		var changed: bool = false
		for e: int in rng.randi_range(0, 3):
			var m: Targetable = markers[rng.randi_range(0, markers.size() - 1)]
			var holder := m.get_parent() as Node3D
			var roll: float = rng.randf()
			if roll < 0.6:
				holder.position += Vector3(rng.randf_range(-9000.0, 9000.0), 0.0, rng.randf_range(-9000.0, 9000.0))
			elif roll < 0.85:
				holder.visible = not holder.visible
			elif markers.size() > 6:
				markers.erase(m)
				holder.free()
			changed = true
		# Sometimes a command.
		var command: float = rng.randf()
		if command < 0.35:
			var wanted: Targetable = markers[rng.randi_range(0, markers.size() - 1)]
			var reach: float = maxf(TargetingSystem.SENSOR_RANGE_M, wanted.broadcast_range_m)
			var out_now: bool = not wanted.is_active() or TargetingSystem.range_between(player.ship.global_position,
					wanted.global_position) > reach
			var took: bool = targeting.select_id(wanted.get_instance_id())
			stale_selects += 1 if took and out_now else 0
			line += " | select %s %s" % [wanted.display_name, took]
		elif command < 0.45:
			line += " | nearest %s" % targeting.select_nearest_hostile()
		elif command < 0.5:
			targeting.clear_selection()
			line += " | clear"
		line += " sel %s signals %s" % [names.get(targeting.selected_id(), "none"), str(signals)]
		signals.clear()
		# Only sometimes a read.
		if rng.randf() < 0.3:
			line += " | name %s" % targeting.selected_name()
		if rng.randf() < 0.2:
			var listed: Array[TargetInfo] = targeting.candidates()
			if changed or command < 0.5:
				late_reads += 1  # read after things changed since the refresh: built now on read, so not compared
			else:
				line += " | list " + _list(listed)
			line += " sel %s signals %s" % [names.get(targeting.selected_id(), "none"), str(signals)]
			signals.clear()
		log.append(line)
	world.free()
	return [log, stale_selects, late_reads]


func test_the_selection_and_the_list_read_are_the_same_either_way() -> void:
	var every_tick: Array = _run(false)
	var on_read: Array = _run(true)
	var a: PackedStringArray = every_tick[0]
	var b: PackedStringArray = on_read[0]
	assert_eq(b.size(), a.size())
	for i: int in a.size():
		if b[i] != a[i]:
			fail_test("step %d differs:\n%s\nagainst\n%s" % [i, b[i], a[i]])
			return
	gut.p("%d steps alike; %d commands took a target already out of reach (the refresh's list decides, both ways); %d late reads" % [
			a.size(), every_tick[1], every_tick[2]])
	assert_eq(on_read[1], every_tick[1])
	assert_gt(every_tick[1], 0, "some commands met a list older than the target's move, so that case was compared")
	assert_gt(every_tick[2], 10, "some reads came late")


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
