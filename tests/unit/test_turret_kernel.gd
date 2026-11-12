extends TestSteps
## The turret kernels on the core's rows (M4-T20, architecture §17.13): a gun's target pick, aim step and fire gate, an
## interceptor's pick, and a capital's strike target for its beams and missiles run natively over the rows, bit for bit with
## the GDScript stand-ins as they were recorded before M4-T37 removed them (`tests/fixtures/parity/turret_kernel.json`). The
## aim maths (`InterceptMath.solve`, the limited turn, the angle) are compared on seeded inputs; a seeded miniature battle
## must log the recorded picks, axes, aim errors, fire ticks, bolts, kills, beams and launches every tick, also across a
## rebase between the sync and the step and a relation changed mid-run.

const NATIVE_CLASS: StringName = &"ScsWeaponRows"

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


const FIXTURE: String = "turret_kernel"


# A unit vector from the seeded generator, now and then exactly on an axis.
static func _unit(rng: RandomNumberGenerator) -> Vector3:
	if rng.randf() < 0.05:
		return [Vector3.UP, Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN][rng.randi_range(0, 3)]
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()


func test_the_aim_maths_match_the_gdscript_bit_for_bit() -> void:
	var rows: Object = ClassDB.instantiate(NATIVE_CLASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20
	var mismatches: Array[String] = []
	for i: int in 4000:
		var at := Vector3(rng.randf_range(-9e3, 9e3), rng.randf_range(-9e3, 9e3), rng.randf_range(-9e3, 9e3))
		var target := at + _unit(rng) * rng.randf_range(0.0, 6000.0)
		if i % 50 == 0:
			target = at  # on top of the shooter
		var shooter_v := _unit(rng) * rng.randf_range(0.0, 60.0)
		var target_v := _unit(rng) * rng.randf_range(0.0, 1200.0)  # some outrun the bolt
		var lead: Dictionary = InterceptMath.solve(at, shooter_v, target, target_v, TurretStandin.MUZZLE_SPEED_MPS,
				TurretStandin.BOLT_LIFETIME_S)
		var native: Vector4 = rows.solve_aim(at, shooter_v, target, target_v, TurretStandin.MUZZLE_SPEED_MPS,
				TurretStandin.BOLT_LIFETIME_S)
		var aim: Vector3 = lead["aim_dir"]
		if var_to_bytes(aim) != var_to_bytes(Vector3(native.x, native.y, native.z)) or float(lead["ok"]) != native.w:
			mismatches.append("solve %d: %s %s against %s" % [i, aim, lead["ok"], native])
		var from := _unit(rng)
		var wanted := _unit(rng)
		if i % 40 == 0:
			wanted = from  # no turn at all
		elif i % 40 == 1:
			wanted = -from  # straight behind: the fallback axis
		var max_angle: float = rng.randf_range(0.0, 0.2) if i % 9 != 0 else TurretStandin.TURN_RATE_RAD_S / 60.0
		var turned: Vector3 = TurretStandin.turned_toward(from, wanted, max_angle)
		var turned_native: Vector3 = rows.turned_toward(from, wanted, max_angle)
		if var_to_bytes(turned) != var_to_bytes(turned_native):
			mismatches.append("turn %d: %s against %s" % [i, turned, turned_native])
		if from.angle_to(wanted) != rows.angle_to(from, wanted):
			mismatches.append("angle %d" % i)
	assert_eq(mismatches.size(), 0, "the native aim maths equal the GDScript's bit for bit: %s" % [mismatches.slice(0, 5)])


func test_a_seeded_battle_gives_the_recorded_picks_aims_fire_ticks_and_kills() -> void:
	var native: WeaponRowsScene = WeaponRowsScene.build(self, 7)
	native.run(600)
	assert_eq(native.director.weapons_path(), &"native", "the run is on the native rows")
	_assert_recorded("seed_7", native.log)
	# The scene exercised every part: picks, shots, kills, beams, launches and mines.
	var reference: WeaponRowsScene = native
	var last: Dictionary = reference.log[reference.log.size() - 1]
	var counts: Array = last["counts"]
	assert_gt(int(counts[0]), 10, "interceptors shot things down: %s" % [counts])
	assert_gt(int(counts[1]), 0, "missiles among them")
	assert_gt(int(counts[2]), 0, "beams fired")
	assert_gt(int(counts[3]), 0, "missiles were launched")
	var fired: int = 0
	for entry: Dictionary in reference.log:
		for made: Array in entry["made"]:
			fired += 1 if made[0] == String(Projectile.KIND_BOLT) else 0
	assert_gt(fired, 50, "the guns fired")


func test_a_rebase_between_the_sync_and_the_step_changes_nothing() -> void:
	var native: WeaponRowsScene = WeaponRowsScene.build(self, 11)
	native.rebase_at = 90
	native.run(240)
	assert_eq(native.director.weapons_path(), &"native")
	_assert_recorded("rebase_at_90", native.log)


func test_a_relation_changed_mid_run_is_followed_the_same_tick() -> void:
	var native_log: Array = _relation_run()
	_assert_recorded("relation_changed_at_120", native_log)
	# Within a retarget (six ticks) every gun has let go: the rows read the new table.
	var after: Dictionary = native_log[130]
	var held: int = 0
	for turret: Array in after["turrets"]:
		if turret.size() == 5 and turret[1] != "":
			held += 1
	assert_eq(held, 0, "no gun holds a target once no side is hostile")


func test_turrets_of_a_capital_that_is_not_bound_are_refused() -> void:
	var rows: Object = ClassDB.instantiate(NATIVE_CLASS)
	rows.set_capitals(PackedInt64Array([0, 0]))
	var ok: bool = rows.set_turrets(PackedInt32Array([0, 2]), PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
			PackedByteArray([0, 0]))
	assert_engine_error("capital", "a turret of capital 2 of 2 is refused, saying why")
	assert_false(ok, "refused")
	ok = rows.set_turrets(PackedInt32Array([0, -1]), PackedVector3Array([Vector3.ZERO, Vector3.ZERO]), PackedByteArray([0, 0]))
	assert_engine_error("capital", "a negative capital is refused, saying why")
	assert_false(ok)
	assert_true(rows.set_turrets(PackedInt32Array([0, 1]), PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
			PackedByteArray([0, 1])), "bound capitals are taken")
	var out: Array = rows.step(1, 100.0, 1.0 / 60.0, 30, 120, 0, 2, 60)  # M4-T22 fix round 1: the ticks per second
	assert_eq((out[0] as PackedInt32Array).size(), 0, "no core: nothing fires, nothing breaks")


# Seed 17's scene for 120 ticks, then no side hostile for 120 more (the console's `relation` command changes the live table
# in place): its log.
func _relation_run() -> Array:
	var scene: WeaponRowsScene = WeaponRowsScene.build(self, 17)
	scene.run(120)
	assert_eq(Factions.table().set_relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.Relation.NEUTRAL), "")
	scene.run(120)
	assert_eq(scene.director.weapons_path(), &"native")
	var out: Array = scene.log
	scene.dispose()
	Factions.reset()
	return out


# Fails at the first tick whose entry differs from the GDScript stand-ins' recorded log.
func _assert_recorded(case: String, log: Array) -> void:
	var recorded: Variant = ParityFixture.stored(FIXTURE, case)
	assert_not_null(recorded, "%s: the GDScript stand-ins' log was recorded" % case)
	if recorded == null:
		return
	var got: Array = WeaponRowsScene.digests(log)
	assert_eq(got.size(), (recorded as Array).size(), "%s: as many ticks as the recording" % case)
	for t: int in mini(got.size(), (recorded as Array).size()):
		if got[t] != recorded[t]:
			fail_test("%s: tick %d differs from the GDScript stand-ins' recording: %s" % [case, t, var_to_str(log[t]).left(400)])
			return
	pass_test("%s: %d ticks equal the recording byte for byte" % [case, got.size()])


# --- the defensive turrets' mounts (M5-T21, D61) -------------------------------------------------------------------------
# A mount row bound to its ship's row in the core: the pick in the AI job one tick behind (on the frozen rows and memory),
# the aim, arc, gate and shot on the main thread, the shot an owned bolt row through the native hit sweep, the attacker
# memory fed by the sweep's hits. Small seeded scenes, through the core (`TurretScene`).

const TRANSPORT: StringName = &"starfury_ally"
const RAIDER: StringName = &"raider_fighter"


func _mount_scene(mode: StringName = &"threaded") -> Dictionary:
	var scene: TurretScene = TurretScene.build(self, mode)
	var transport: Combatant = scene.ship(TRANSPORT, Factions.EARTH_ALLIANCE, "TRANSPORT", Vector3.ZERO, {}, 1, true)
	var mount: TurretMount = scene.mount(transport)
	var raider_a: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "RAIDER A", Vector3(0.0, 150.0, -350.0))
	var raider_b: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "RAIDER B", Vector3(250.0, 120.0, -330.0))
	scene.attach()
	return {"scene": scene, "transport": transport, "mount": mount, "a": raider_a, "b": raider_b}


static func _id(c: Combatant) -> int:
	return c.ship.get_instance_id()


func test_a_turret_fires_only_at_the_ship_that_shot_its_own_one_tick_after_the_hit() -> void:
	var s: Dictionary = _mount_scene()
	var scene: TurretScene = s["scene"]
	var mount: TurretMount = s["mount"]
	await _ticks(30)
	assert_gte(mount.slot(), 0, "the mount bound to the core")
	assert_eq(scene.sim.turret_count(), 1)
	assert_eq(int(scene.state(mount)["target"]), 0, "two raiders in reach, neither has fired: no target")
	assert_eq(scene.shots_total(), 0, "and no shot")
	scene.sim.note_hit(_id(s["transport"]), _id(s["a"]))
	await _ticks(1)
	assert_eq(int(scene.state(mount)["target"]), 0, "the pick runs in the AI job one tick behind")
	await _ticks(1)
	assert_eq(int(scene.state(mount)["target"]), _id(s["a"]), "the one that shot is picked at the next join, not the nearer one")
	var min_el: float = float(scene.state(mount)["min_elevation"])
	var lowest: float = INF
	for i: int in 420:
		await get_tree().physics_frame
		lowest = minf(lowest, float(scene.state(mount)["elevation"]))
	assert_gt(scene.shots_total(), 2, "it fired (%d shots)" % scene.shots_total())
	assert_eq(mount.shots, scene.shots_total(), "every shot came back to its mount")
	assert_gt(scene.hits_on(s["a"], s["transport"]), 0, "its bolts hit raider A through the hit sweep")
	assert_eq(scene.hits_on(s["b"]), 0, "raider B, which never fired, was left alone")
	assert_gte(lowest, min_el - 1e-6, "the barrel never went below its arc")
	var az: float = float(scene.state(mount)["azimuth"])
	var el: float = float(scene.state(mount)["elevation"])
	assert_almost_eq(el, atan2(150.0 - 3.0, 350.0), 0.03, "it settled on raider A's elevation")
	assert_almost_eq(az, 0.0, 0.03, "straight ahead")
	await scene.free_scene(get_tree())


func test_a_target_below_the_arc_holds_the_barrel_at_the_edge_and_the_gate_shut() -> void:
	var scene: TurretScene = TurretScene.build(self)
	var transport: Combatant = scene.ship(TRANSPORT, Factions.EARTH_ALLIANCE, "TRANSPORT", Vector3.ZERO, {}, 1, true)
	var mount: TurretMount = scene.mount(transport)
	# Ahead and below: under the arc's edge, but in clear line past the own hull (Q33), which would hide it right below.
	var under: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "UNDER", Vector3(100.0, -250.0, -900.0))
	scene.attach()
	await _ticks(2)
	scene.sim.note_hit(_id(transport), _id(under))
	await _ticks(240)
	var state: Dictionary = scene.state(mount)
	assert_eq(int(state["target"]), _id(under), "the only attacker is picked, though below the arc")
	assert_almost_eq(float(state["elevation"]), float(state["min_elevation"]), 1e-6, "the barrel waits at the arc's edge")
	assert_almost_eq(float(state["min_elevation"]), deg_to_rad(-10.0), 1e-6, "200 degrees: 10 below the base")
	assert_eq(scene.shots_total(), 0, "no shot through its own hull")
	await scene.free_scene(get_tree())


func test_an_attacker_is_remembered_30_s_from_its_last_hit_and_a_destroyed_one_at_once() -> void:
	var s: Dictionary = _mount_scene(&"delayed")
	var scene: TurretScene = s["scene"]
	var core: Object = scene.sim.core
	await _ticks(2)
	scene.sim.note_hit(_id(s["transport"]), _id(s["a"]))
	scene.sim.note_hit(_id(s["transport"]), _id(s["a"]))
	scene.sim.note_hit(_id(s["transport"]), _id(s["b"]))
	assert_eq(core.attacker_pairs(), PackedInt64Array([_id(s["transport"]), _id(s["a"]), _id(s["transport"]), _id(s["b"])]),
			"one entry an attacker and victim, in the order the hits came")
	await _ticks(3)
	SimClock.reset(SimClock.now() + 29.0)
	scene.sim.note_hit(_id(s["transport"]), _id(s["b"]))
	SimClock.reset(SimClock.now() + 2.0)
	await _ticks(3)
	assert_eq(core.attacker_pairs(), PackedInt64Array([_id(s["transport"]), _id(s["b"])]),
			"raider A forgotten 30 s after its hit, raider B's refreshed")
	assert_eq(int(scene.state(s["mount"])["target"]), _id(s["b"]), "and the turret moved to raider B")
	(s["b"] as Combatant).damageable.apply_hit(HitInfo.new(_id(s["b"]), 0, Factions.EARTH_ALLIANCE, 1000.0, Vector3.ZERO,
			Vector3.UP, 0.0))
	assert_eq(int(core.attacker_count()), 0, "a destroyed ship is forgotten at once (a pooled one comes back as someone new)")
	await _ticks(3)
	assert_eq(int(scene.state(s["mount"])["target"]), 0, "nothing left to shoot at")
	await scene.free_scene(get_tree())


func test_a_turret_defends_a_civilian_or_ally_within_2_km_and_nothing_else() -> void:
	var scene: TurretScene = TurretScene.build(self)
	var transport: Combatant = scene.ship(TRANSPORT, Factions.EARTH_ALLIANCE, "TRANSPORT", Vector3.ZERO, {}, 1, true)
	var mount: TurretMount = scene.mount(transport)
	var near_ally: Combatant = scene.ship(TRANSPORT, Factions.EARTH_ALLIANCE, "NEAR", Vector3(1500.0, 0.0, 0.0))
	var far_ally: Combatant = scene.ship(TRANSPORT, Factions.EARTH_ALLIANCE, "FAR", Vector3(0.0, 0.0, 2600.0))
	var stranger: Combatant = scene.ship(TRANSPORT, Factions.NEUTRAL, "STRANGER", Vector3(-1500.0, 0.0, 0.0))
	var trader: Combatant = scene.ship(TRANSPORT, Factions.NEUTRAL, "TRADER", Vector3(-1200.0, 0.0, -600.0), {}, 1, true)
	var raider: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "RAIDER", Vector3(0.0, 400.0, -800.0))
	scene.attach()
	await _ticks(2)
	var expect: Array = [[far_ally, 0, "an ally 2.6 km away is too far"], [stranger, 0, "a neutral warship is not defended"],
			[near_ally, _id(raider), "an ally 1.5 km away is"], [trader, _id(raider), "a neutral civilian within 2 km is"]]
	for e: Array in expect:
		scene.sim.core.forget_attacker(_id(raider))
		scene.sim.note_hit(_id(e[0] as Combatant), _id(raider))
		await _ticks(3)
		assert_eq(int(scene.state(mount)["target"]), int(e[1]), e[2])
	scene.sim.core.forget_attacker(_id(raider))
	scene.sim.note_hit(_id(transport), _id(near_ally))
	await _ticks(3)
	assert_eq(int(scene.state(mount)["target"]), 0, "an ally's stray bolt makes no target of it")
	await scene.free_scene(get_tree())


func test_a_pick_for_a_mount_rebound_while_the_job_ran_is_dropped() -> void:
	var s: Dictionary = _mount_scene(&"threaded")
	var scene: TurretScene = s["scene"]
	var mount: TurretMount = s["mount"]
	await _ticks(2)
	scene.sim.note_hit(_id(s["transport"]), _id(s["a"]))
	await _ticks(1)  # this tick's job carries the hit
	var stale: int = int(scene.sim.core.turret_readouts()[2])
	scene.sim.core.set_turret_live(mount.slot(), false)
	scene.sim.core.set_turret_live(mount.slot(), true)  # a ship parked and back: a new binding
	await _ticks(1)
	assert_eq(int(scene.sim.core.turret_readouts()[2]), stale + 1, "the old binding's pick was dropped at the join")
	assert_eq(int(scene.state(mount)["target"]), 0, "so the mount has no target yet")
	await _ticks(1)
	assert_eq(int(scene.state(mount)["target"]), _id(s["a"]), "the next pick, made for the new binding, lands")
	await scene.free_scene(get_tree())


func test_the_hardpoints_turrets_become_mounts_on_the_ship() -> void:
	var hp := Hardpoints.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/hardpoints_nominal.json"))
	assert_true(hp.valid, hp.error)
	assert_eq(hp.turrets.size(), 0, "turrets are optional")
	var data: Dictionary = hp.raw.duplicate(true)
	data["turrets"] = [{"name": "dorsal_fwd", "position": [0, 13.3, 17.0], "up": [0, 2, 0], "arc_deg": 200, "barrel_m": 2.6},
			{"name": "flank_r", "position": [2.04, 8.45, 6.58], "up": [1, 0, 0]}]
	hp = Hardpoints.from_dict(data)
	assert_true(hp.valid, hp.error)
	assert_eq(hp.turrets.size(), 2)
	assert_eq(hp.turrets[0]["up"], Vector3.UP, "up comes normalised")
	assert_eq(hp.turrets[1]["arc_deg"], 200.0, "arc defaults to a hemisphere and 10 degrees")
	data["turrets"] = [{"name": "bad", "position": [0, 1, 0], "up": [0, 0, 0]}]
	assert_false(Hardpoints.from_dict(data).valid, "a zero up is refused")
	data["turrets"] = [{"name": "bad", "position": [0, 1, 0], "arc_deg": 400}]
	assert_false(Hardpoints.from_dict(data).valid, "an arc past 360 is refused")
	var flank := TurretMount.create(hp.turrets[1] if hp.turrets.size() > 1 else {}, null, Factions.NEUTRAL)
	autofree(flank)
	var b: Basis = flank.basis
	assert_almost_eq((b.y - Vector3.RIGHT).length(), 0.0, 1e-6, "the mount's +Y is its base's up")
	assert_almost_eq((-b.z - Vector3.FORWARD).length(), 0.0, 1e-6, "its rest along the ship's nose")


func test_the_saturn_4s_mounts_show_its_turret_model_turned_by_the_frame_pass() -> void:
	var asset: String = "saturn_4_transport"
	var entry: Dictionary = MeshAssets.read_manifest(asset).get("turret", {})
	if entry.is_empty():
		pending("the Saturn 4 is not generated (scripts/gen_assets.sh), so it has no turret model")
		return
	var scene: TurretScene = TurretScene.build(self)
	var transport: Combatant = scene.ship(&"saturn_4_transport", Factions.EARTH_ALLIANCE, "SATURN", Vector3.ZERO, {}, 1, true)
	var raider: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "RAIDER", Vector3(300.0, 500.0, -1000.0))
	scene.attach()
	assert_eq(transport.turrets.size(), 3, "its two flank turrets and its dorsal one (Q32), from its hardpoints")
	var model: Dictionary = TurretMount.model_for(asset)
	var base_tris: int = _triangles(model["base"])
	var barrel_tris: int = _triangles(model["barrel"])
	assert_eq(base_tris + barrel_tris, int(entry["mesh"]["triangles"]), "the split keeps every triangle of the manifest's mesh")
	assert_eq(barrel_tris, _obj_triangles(ShipSpec.ASSET_ROOT.path_join(asset).path_join(String(entry["obj"])), ["barrel", "bore"]),
			"the barrels are the model's barrel and bore triangles, no more")
	var mount: TurretMount = transport.turrets[2]  # the cargo section's dorsal mount: the raider is above it
	assert_not_null(mount.yaw.get_node_or_null(^"Base"), "the base turns round the mount's up")
	assert_not_null(mount.pitch.get_node_or_null(^"Barrels"), "the barrels lift with the elevation")
	assert_eq(mount.pitch.position, model["trunnion"], "about the trunnion")
	await _ticks(2)
	scene.sim.note_hit(_id(transport), _id(raider))
	await _ticks(90)
	FramePasses.of(mount).update_turrets()
	var state: Dictionary = scene.state(mount)
	assert_gt(float(state["elevation"]), 0.1, "the raider is above: the core lifted the barrel")
	assert_almost_eq(mount.yaw.rotation.y, float(state["azimuth"]), 1e-5, "the model turned to the core's azimuth")
	assert_almost_eq(mount.pitch.rotation.x, float(state["elevation"]), 1e-5, "and lifted to its elevation")
	transport.ship.set_far_dot(true)
	assert_false(mount.visible, "a far dot draws no turret")
	transport.ship.set_far_dot(false)
	assert_true(mount.visible)
	await scene.free_scene(get_tree())


static func _triangles(mesh: Mesh) -> int:
	var n: int = 0
	for s: int in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


# Triangles of an OBJ's faces under materials whose names hold any of `words`.
static func _obj_triangles(path: String, words: Array) -> int:
	var n: int = 0
	var counting: bool = false
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("usemtl ") or line.begins_with("g "):
			var name: String = line.get_slice(" ", 1)
			counting = words.any(func(w: String) -> bool: return name.contains(w))
		elif counting and line.begins_with("f "):
			n += line.strip_edges().split(" ", false).size() - 3
	return n
