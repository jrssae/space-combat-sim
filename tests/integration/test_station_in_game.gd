extends GutTest
## The station in the game (M7-T06, AC5, D74) on the real main scene: free flight places Babylon 5 at the system data's point and
## it stays there across rebases and off the anchor; the drum turns from the system's clock; a bolt lands on the station's real
## shape and lowers the damage section it hit and no other; the target box shows the sections; the AI hears the station's
## beacon out to 1 000 km; a fighter flies into the main docking bay, the cargo bay and a Cobra bay's hall with no false contact,
## a rebase on the way included; a ship that rams the frame takes a contact ram and one that scrapes the turning drum takes a ram
## at the skin's speed (Q9). Every place comes from the manifest's hardpoints and rays against the built bodies, never from
## numbers here.

const DT: float = 1.0 / 60.0
## The scenario coordinates free flight puts the station at (M6-T09).
const FREE_FLIGHT_STATION := Vector3(5500.0, -1200.0, -6000.0)
const STARFURY_HARDPOINTS: String = "res://assets/generated/starfury_aurora/hardpoints.json"

var main: Main
var station: Station


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	DebugConsole.flags.invulnerable = false


func after_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func _start(raiders: int = 0) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = raiders
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	station = main.far_props.station


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _universe(node: Node3D) -> Vector3:
	var u: UniversePos = main.world.to_universe(node.global_position)
	return Vector3(u.x, u.y, u.z)


# A Starfury's collision shapes on a bare rigid body that reports its contacts: what Jolt sees of a fighter, flown by nothing.
func _fighter(at: Transform3D, velocity: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "TestFighter"
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
	body.global_transform = at
	body.linear_velocity = velocity
	return body


# Flies `body` for `ticks` ticks; the most contacts it reported in any one of them.
func _fly(body: RigidBody3D, ticks: int, rebase_at: int = -1) -> int:
	var most: int = 0
	for i: int in ticks:
		if i == rebase_at:
			main.world.rebase(Vector3(4000.0, 0.0, 0.0))
		await _ticks(1)
		most = maxi(most, body.get_contact_count())
	return most


# Where a ray from `from` toward `to` first meets the station's bodies (World), or null.
func _hit_point(from: Vector3, to: Vector3) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(from, to, CollisionLayers.layer_of(Station.COLLISION_KIND))
	var hit: Dictionary = main.world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position") if not hit.is_empty() else null


func test_free_flight_places_the_station_and_it_stays_there_across_rebases() -> void:
	await _start()
	assert_not_null(station, "free flight places the station (M6-T09's anchor, now M7-T06's Station)")
	assert_true(station is Station)
	assert_almost_eq(_universe(station), FREE_FLIGHT_STATION, Vector3.ONE * 0.01, "at the system data's point")
	assert_not_null(FarProp.of(station), "dressed for the far field")
	for offset: Vector3 in [Vector3(4000.0, 0.0, 0.0), Vector3(0.0, -6000.0, 2500.0), Vector3(-12000.0, 300.0, 0.0)]:
		var local_before: Vector3 = station.global_position
		main.world.rebase(offset)
		assert_almost_eq(station.global_position, local_before - offset, Vector3.ONE * 0.01, "moved on screen with everything else")
		await _ticks(1)
		assert_almost_eq(_universe(station), FREE_FLIGHT_STATION, Vector3.ONE * 0.01, "still there after a rebase of %s" % offset)
	# Off the anchor (a velocity rebase): the frame falls freely and the station rides its anchor with the buoys and the gate.
	main.world.boost(Vector3(2500.0, 0.0, 0.0))
	await _ticks(60)
	assert_almost_eq(_universe(station), FREE_FLIGHT_STATION, Vector3.ONE * 0.05, "with its anchor off the frame's")


func test_the_drum_turns_from_the_system_clock() -> void:
	await _start()
	assert_almost_eq(station.spin.rate_rad_s, 0.148, 1e-6, "the manifest's spin")
	for i: int in 3:
		await _ticks(7)
		# The tick turned the drum before the clock moved on: the angle of the tick's own time.
		var expected: float = station.spin.angle_at(main.world.system_time() - DT)
		assert_almost_eq(station.drum_angle, expected, 1e-9, "the angle the clock gives")
		assert_almost_eq(station.drum_body.transform.basis.get_euler().z, wrapf(expected, -PI, PI), 1e-4, "the body turned to it")
	# The core's row of the drum holds that pose, so the hit sweep sees the drum where Jolt has it.
	var sim: SimCore = SimCore.for_tree(get_tree())
	assert_eq(int(sim.core.surface_count()), 2, "the frame and the drum are big hulls in the core")
	assert_gt(int(sim.core.surface_volume_count(station.drum_body.get_instance_id())), 50)
	var held: float = station.drum_angle
	station.set_spinning(false)
	await _ticks(10)
	assert_eq(station.drum_angle, held, "held still")
	station.set_spinning(true)
	await _ticks(1)
	var resumed: float = station.drum_angle
	assert_almost_eq(resumed, held, station.spin.rate_rad_s * DT * 1.01, "on from where it was, no jump")
	await _ticks(1)
	assert_almost_eq(station.drum_angle - resumed, station.spin.rate_rad_s * DT, 1e-6, "at the drum's own rate")


func test_a_bolt_lands_on_the_real_shape_and_lowers_only_its_section() -> void:
	await _start()
	var hits: Array[HitInfo] = []
	(main.get_node("Combat/HitResolver") as HitResolver).hit_resolved.connect(func(info: HitInfo) -> void: hits.append(info))
	# Down the drum's axis from far ahead of the bow: through the docking bay's tunnel, so it hits the airlock's doors or the
	# tunnel's end, never the empty space the 4 km bounding sphere covers.
	var bay: Dictionary = station.hardpoints.main_docking_bay
	var mouth: Vector3 = station.to_world(bay["main_docking_bay_mouth"], StationHardpoints.DRUM)
	var airlock: Vector3 = station.to_world(bay["main_docking_bay_airlock"], StationHardpoints.DRUM)
	var axis: Vector3 = (airlock - mouth).normalized()
	# A raider's bolt beside the station, flying past it 600 m clear of the drum's side: inside the bounding sphere, no hit.
	var side: Vector3 = station.global_transform * Vector3(1100.0, 0.0, 0.0)
	_bolt(side - axis * 300.0, axis * 900.0)
	await _ticks(60)
	assert_eq(hits.size(), 0, "no hit on the station's empty bounding sphere")
	# Now one at the frame's command section, from straight above it.
	var command: int = station.sections.index_of("command")
	var box: AABB = station.sections.sections[command]["aabb"]
	var top: Vector3 = station.global_transform * Vector3(box.get_center().x, box.end.y + 400.0, box.get_center().z)
	var target_point: Variant = _hit_point(top, station.global_transform * box.get_center())
	assert_not_null(target_point, "the command section is under the ray")
	_bolt(top, ((target_point as Vector3) - top).normalized() * 900.0)
	await _ticks(60)
	assert_eq(hits.size(), 1, "one hit")
	var hit: HitInfo = hits[0]
	assert_eq(hit.target_id, station.get_instance_id(), "on the frame's row")
	assert_almost_eq(hit.point.distance_to(target_point as Vector3), 0.0, 2.0, "where the hull is")
	for i: int in station.sections.count():
		if i == command:
			assert_almost_eq(station.sections.health[i], StationSections.SECTION_HEALTH - 6.0, 1e-6, "the command section took it")
		else:
			assert_eq(station.sections.health[i], StationSections.SECTION_HEALTH, "%s untouched" % station.sections.sections[i]["name"])
	assert_eq(station.frame_hull.hull.hp, Station.HULL_MAX, "the hull itself never falls")
	# The target box shows the sections: the player targets the station.
	assert_true(main.ship.targeting.select_id(station.targetable.get_instance_id()))
	var info: TargetInfo = station.targetable.to_target_info()
	assert_eq(info.damage_layout, DamageZones.Layout.STATION)
	assert_eq(info.damage_zones.size(), station.sections.count())
	assert_gt(info.damage_zones[command], 0.0, "the command section shows its damage")
	assert_eq(Silhouette.polygons(DamageZones.Layout.STATION).size(), station.sections.count(), "drawn one box a section")


func test_a_lost_section_says_so_once_and_the_station_goes_on() -> void:
	await _start()
	var lost: Array[String] = []
	station.section_lost.connect(func(_i: int, section_name: String) -> void: lost.append(section_name))
	var cargo: int = station.sections.index_of("cargo")
	assert_true(DebugConsole.registry.execute("station section cargo damage %d" % int(StationSections.SECTION_HEALTH - 1.0))[0].ok)
	assert_eq(lost.size(), 0)
	assert_true(station.damage_section(cargo, 5.0), "this hit loses it")
	assert_false(station.damage_section(cargo, 5.0), "lost already")
	assert_eq(lost, ["cargo"] as Array[String], "once")
	assert_true(station.is_inside_tree() and station.targetable.is_active(), "never destroyed or disabled (Q5)")
	station.heal()
	assert_eq(station.sections.health[cargo], StationSections.SECTION_HEALTH)


func test_the_ai_hears_the_station_out_to_about_1000_km() -> void:
	await _start(2)
	for row: Array in [[900000.0, true], [1100000.0, false]]:
		var at: Vector3 = station.global_position + Vector3(0.0, 0.0, -float(row[0]))
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider"}, main.world.to_universe(at), 5)
		var raider: Combatant = main.ships.acquire(main.ships.next_name(ShipPool.NAME_PREFIX, 1), main.world.to_universe(at),
				Basis.IDENTITY, Vector3.ZERO, made["brain"] as PilotBrain, ShipPool.DEFAULT_TYPE)
		await _ticks(2)
		ContactScan.invalidate()
		var heard := PackedStringArray()
		for contact: Contact in raider.driver.perceive().broadcasts:
			heard.append(contact.name)
		if bool(row[1]):
			assert_has(heard, Station.DISPLAY_NAME, "a raider %.0f km out hears the station" % (float(row[0]) / 1000.0))
		else:
			assert_does_not_have(heard, Station.DISPLAY_NAME, "not %.0f km out" % (float(row[0]) / 1000.0))
		main.ships.release(raider)


func test_a_fighter_flies_into_the_bays_with_no_false_contact() -> void:
	await _start()
	var bay: Dictionary = station.hardpoints.main_docking_bay
	var path: Array = bay["main_docking_bay_path"]
	# The main docking bay, down the turning drum's axis from its approach to short of the airlock, with a rebase on the way.
	var start: Vector3 = station.to_world(path[1], StationHardpoints.DRUM)
	var airlock: Vector3 = station.to_world(bay["main_docking_bay_airlock"], StationHardpoints.DRUM)
	var axis: Vector3 = (airlock - start).normalized()
	var run: float = start.distance_to(airlock) - 40.0
	var fighter: RigidBody3D = _fighter(Transform3D(Basis.looking_at(axis, Vector3.UP), start), axis * 120.0)
	var ticks: int = int(run / 120.0 / DT)
	assert_eq(await _fly(fighter, ticks, ticks / 2), 0, "no contact all the way into the tunnel, a rebase included")
	var mouth: Vector3 = station.to_world(bay["main_docking_bay_mouth"], StationHardpoints.DRUM)
	assert_gt((fighter.global_position - mouth).dot(axis), 100.0, "well past the mouth")
	assert_almost_eq(fighter.linear_velocity, axis * 120.0, Vector3.ONE * 0.01, "nothing touched it")
	fighter.free()
	# The cargo bay (zero-gravity, on the frame), along its path from the release point to its entry.
	var cargo: Dictionary = station.hardpoints.cargo_bay
	var release: Vector3 = station.to_world(cargo["cargo_bay_release"], StationHardpoints.FRAME)
	var entry: Vector3 = station.to_world(cargo["cargo_bay_entry"], StationHardpoints.FRAME)
	var along: Vector3 = (entry - release).normalized()
	fighter = _fighter(Transform3D(Basis.looking_at(along, Vector3.UP), release), along * 150.0)
	assert_eq(await _fly(fighter, int(release.distance_to(entry) / 150.0 / DT)), 0, "no contact into the cargo bay")
	assert_lt(fighter.global_position.distance_to(entry), 5.0, "at its entry point")
	fighter.free()
	# A Cobra bay door's hall, the drum held (a launch is M7-T08's): from the release point down through the door to the rack.
	station.set_spinning(false)
	await _ticks(1)
	var door: Dictionary = station.hardpoints.cobra_bays[0]
	var drop_from: Vector3 = station.to_world(door["release"], StationHardpoints.DRUM)
	var rack: Vector3 = station.to_world(door["rail_start"], StationHardpoints.DRUM)
	var down: Vector3 = (rack - drop_from).normalized()
	var turn: Basis = station.global_basis * Basis(Vector3.BACK, station.drum_angle)
	var facing := Basis.looking_at(turn * (door["forward"] as Vector3), turn * (door["up"] as Vector3))
	fighter = _fighter(Transform3D(facing, drop_from), down * 4.0)
	assert_eq(await _fly(fighter, int(drop_from.distance_to(rack) / 4.0 / DT)), 0, "no contact through %s's door" % door["name"])
	assert_lt(fighter.global_position.distance_to(rack), 1.0, "on the rack in the hall")
	fighter.free()


func test_ramming_the_frame_is_a_contact_ram_and_scraping_the_drum_rams_at_the_skins_speed() -> void:
	await _start()
	var rams: Array[HitInfo] = []
	var ship_at: Array[Vector3] = []  # where the ship was at each ram (a rebase may come between)
	main.rams.ram_resolved.connect(func(info: HitInfo) -> void:
		rams.append(info)
		ship_at.append(main.ship.global_position))
	var player_id: int = main.ship.get_instance_id()
	# The frame: the player at 30 m/s straight into the command section's top.
	var command: AABB = station.sections.sections[station.sections.index_of("command")]["aabb"]
	var above: Vector3 = station.global_transform * Vector3(command.get_center().x, command.end.y + 300.0, command.get_center().z)
	var skin: Variant = _hit_point(above, station.global_transform * command.get_center())
	assert_not_null(skin)
	var down: Vector3 = ((skin as Vector3) - above).normalized()
	main.ship.reset_to(Transform3D(Basis.looking_at(down, Vector3.BACK), (skin as Vector3) - down * 40.0))
	main.ship.linear_velocity = down * 30.0
	await _ticks(120)
	var on_player: Array[HitInfo] = rams.filter(func(r: HitInfo) -> bool: return r.target_id == player_id)
	assert_eq(on_player.size(), 1, "one ram from the frame")
	if not on_player.is_empty():
		assert_eq(on_player[0].cause, HitInfo.CAUSE_RAM)
		assert_lt(on_player[0].point.distance_to(ship_at[rams.find(on_player[0])]), 12.0, "where it touched, on the ship's skin")
		assert_almost_eq(on_player[0].relative_speed_mps, 30.0, 0.5, "at the speed it flew in")
	assert_eq(station.sections.health[station.sections.index_of("command")], StationSections.SECTION_HEALTH, "rams never hurt the station")
	# The drum: a fresh player beside the forward drum's skin, at rest against the station, drifting onto it at 1 m/s.
	main.respawn()
	await _ticks(2)
	DebugConsole.flags.invulnerable = true  # it survives to be measured
	rams.clear()
	ship_at.clear()
	var drum_box: AABB = station.sections.sections[station.sections.index_of("forward_drum")]["aabb"]
	var mid: Vector3 = station.to_world(Vector3(0.0, 0.0, drum_box.get_center().z), StationHardpoints.DRUM)
	var out_dir: Vector3 = station.global_basis * Vector3(1.0, 0.0, 0.0)
	var drum_skin: Variant = _hit_point(mid + out_dir * 900.0, mid)
	assert_not_null(drum_skin, "the forward drum is under the ray")
	main.ship.reset_to(Transform3D(Basis.looking_at(-out_dir, station.global_basis.z), (drum_skin as Vector3) + out_dir * 14.0))
	main.ship.linear_velocity = -out_dir * 1.0
	main.ship.angular_velocity = Vector3.ZERO
	var radius: float = ((drum_skin as Vector3) - mid).length()
	for i: int in 900:
		await _ticks(1)
		if not rams.filter(func(r: HitInfo) -> bool: return r.target_id == player_id).is_empty():
			break
	on_player = rams.filter(func(r: HitInfo) -> bool: return r.target_id == player_id)
	assert_eq(on_player.size(), 1, "one ram from the drum")
	if not on_player.is_empty():
		assert_almost_eq(on_player[0].relative_speed_mps, station.spin.surface_speed(radius), 3.0,
				"at the skin's speed, %.1f m/s at %.0f m (Q9), not the 1 m/s it drifted in" % [station.spin.surface_speed(radius), radius])
		assert_eq(on_player[0].shooter_id, station.drum_body.get_instance_id(), "the drum rammed it")


func test_the_station_takes_no_light_slot() -> void:
	await _start()
	var lights: Array[Node] = station.find_children("*", "Light3D", true, false)
	assert_eq(lights.size(), 0, "no lights until M7-T18")


func _bolt(at: Vector3, velocity: Vector3) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	main.projectiles.add_child(bolt)
	var weapon := WeaponSpec.new()
	weapon.damage = 6.0
	weapon.lifetime_s = 8.0
	bolt.configure(weapon)
	bolt.shooter_id = 1
	bolt.faction = Factions.RAIDERS
	bolt.launch(at, velocity, SimClock.now())
	return bolt
