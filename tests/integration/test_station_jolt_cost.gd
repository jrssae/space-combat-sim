extends GutTest
## What the station's collision costs Jolt (M7-T06; T05's budget of 192 shapes a piece, approved by the maintainer): the
## physics stage of `PerfProbe` (Jolt's step and the body sync) over a fighter's run down the main docking bay's tunnel, along
## the frame's dorsal spine and along the turning drum's skin, with the station in the scene and with it taken away, at one
## core thread and six. Prints the medians; holds the station's extra under a millisecond a tick. A slow file (GUT_SLOW=1).

const DT: float = 1.0 / 60.0
const TICKS: int = 300
const WARMUP: int = 30
const STARFURY_HARDPOINTS: String = "res://assets/generated/starfury_aurora/hardpoints.json"
## The most the station may add to the physics stage's median, microseconds.
const BUDGET_US: float = 1000.0

var main: Main
var _saved_threads: Variant = null


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


func before_all() -> void:
	_saved_threads = Settings.get_value(&"perf_threads")


func after_all() -> void:
	Settings.set_value(&"perf_threads", _saved_threads)


func test_the_station_costs_jolt_little_in_its_tunnel_and_along_its_hull() -> void:
	var lines := PackedStringArray()
	var worst: float = 0.0
	for threads: int in [1, 6]:
		Settings.set_value(&"perf_threads", threads)
		for run: StringName in [&"tunnel", &"spine", &"drum"]:
			var with: Array = await _measure(run, true)
			var without: Array = await _measure(run, false)
			var extra: float = float(with[0]) - float(without[0])
			worst = maxf(worst, extra)
			lines.append("threads %d %-6s physics median %5.0f us with the station (p90 %5.0f, %d contacts), %5.0f us without: %+5.0f us" % [
					threads, run, with[0], with[1], with[2], without[0], extra])
	for line: String in lines:
		gut.p(line)
	assert_lt(worst, BUDGET_US, "the station adds under %.0f us to Jolt's tick (worst %+.0f us)" % [BUDGET_US, worst])


# One run: the physics stage's median and 90th percentile over `TICKS` ticks and the contacts the fighter reported (they must
# be none: it flies the open tunnel and 15 m off the hull).
func _measure(run: StringName, with_station: bool) -> Array:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 0
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child(main)
	await _ticks(3)
	var station: Station = main.far_props.station
	var path: Array[Vector3] = _path(station, run)
	if not with_station:
		main.far_props.toggle_station()  # takes it away
		await _ticks(2)
	var fighter: RigidBody3D = _fighter(path[0], path[1])
	main.ship.reset_to(Transform3D(Basis.IDENTITY, path[0] + Vector3(0.0, 0.0, 2000.0)))  # the focus near, so no rebase
	main.perf_probe.enabled = true
	await _ticks(WARMUP)
	main.perf_probe.clear_series()
	main.perf_probe.recording = true
	var contacts: int = 0
	for i: int in TICKS:
		await _ticks(1)
		contacts += fighter.get_contact_count()
		main.ship.reset_to(Transform3D(Basis.IDENTITY, fighter.global_position + Vector3(0.0, 0.0, 2000.0)))
	main.perf_probe.recording = false
	var physics: PackedInt64Array = main.perf_probe.series[PerfProbe.Field.PHYSICS].duplicate()
	main.perf_probe.enabled = false
	remove_child(main)
	main.free()
	await _ticks(2)
	physics.sort()
	return [physics[physics.size() / 2], physics[physics.size() * 9 / 10], contacts]


# Where the run starts (World) and its velocity, from the hardpoints and rays against the built bodies.
func _path(station: Station, run: StringName) -> Array[Vector3]:
	match run:
		&"tunnel":
			var bay: Dictionary = station.hardpoints.main_docking_bay
			var mouth: Vector3 = station.to_world(bay["main_docking_bay_mouth"], StationHardpoints.DRUM)
			var airlock: Vector3 = station.to_world(bay["main_docking_bay_airlock"], StationHardpoints.DRUM)
			var axis: Vector3 = (airlock - mouth).normalized()
			var speed: float = (mouth.distance_to(airlock) + 120.0) / (TICKS * DT + WARMUP * DT)
			return [mouth - axis * 120.0, axis * speed]
		&"spine":
			var spine: AABB = station.sections.sections[station.sections.index_of("spine")]["aabb"]
			var top: Vector3 = station.global_transform * Vector3(0.0, spine.end.y + 300.0, spine.position.z + 50.0)
			var skin: Vector3 = _hit(top, station.global_transform * Vector3(0.0, spine.position.y, spine.position.z + 50.0))
			return [skin + station.global_basis.y * 15.0, station.global_basis.z * 100.0]
	var drum: AABB = station.sections.sections[station.sections.index_of("forward_drum")]["aabb"]
	var mid: Vector3 = station.to_world(Vector3(0.0, 0.0, drum.position.z + 40.0), StationHardpoints.DRUM)
	var out_dir: Vector3 = station.global_basis.x
	var skin: Vector3 = _hit(mid + out_dir * 900.0, mid)
	# Along the axis, 15 m off the skin, the drum turning under it.
	return [skin + out_dir * 15.0, station.global_basis.z * 80.0]


func _hit(from: Vector3, to: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, to, CollisionLayers.layer_of(Station.COLLISION_KIND))
	var hit: Dictionary = main.world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position", to)


func _fighter(at: Vector3, velocity: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.can_sleep = false
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.mass = 9000.0
	body.collision_layer = CollisionLayers.layer_of(&"fighter")
	body.collision_mask = CollisionLayers.mask_of(&"fighter")
	for entry: Dictionary in Hardpoints.load_collision_only(STARFURY_HARDPOINTS):
		var shape := CollisionShape3D.new()
		shape.shape = entry["shape"]
		shape.transform = entry["transform"]
		body.add_child(shape)
	main.world.add_child(body)
	body.global_transform = Transform3D(Basis.looking_at(velocity.normalized(), Vector3.UP if absf(velocity.normalized().y) < 0.9 else Vector3.BACK), at)
	body.linear_velocity = velocity
	return body


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
