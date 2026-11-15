extends GutTest
## The interceptor battery's own model (M7-T42): its three parts load from the asset's part files, hang from the mount as
## `TurretMount` turns them (the pedestal fixed, the yoke on `yaw`, the barrels on `pitch` at the trunnion), its four muzzles come
## from the manifest, and every one of the station's nine batteries wears it while the light and heavy guns keep the Saturns'.

const ASSET: String = "grid_interceptor_battery"
const HINT: String = "run scripts/gen_assets.sh and import first"


func _model() -> Dictionary:
	var model: Dictionary = TurretMount.model_for(ASSET)
	if model.is_empty():
		pending("the %s asset is not generated (%s)" % [ASSET, HINT])
	return model


func test_the_model_loads_in_three_parts_about_its_trunnion() -> void:
	var model: Dictionary = _model()
	if model.is_empty():
		return
	for part: String in ["pedestal", "yaw", "pitch"]:
		assert_true(model.get(part) is Mesh, "the %s part loads from its own file" % part)
		assert_gt((model[part] as Mesh).get_surface_count(), 0, part)
	assert_eq(model["trunnion"], Vector3(0.0, 12.5, 0.0), "the barrels lift about the head's axle, 12.5 m over the base")
	assert_false(model.has("base"), "not split at the barrels like a one-mesh turret")


func test_four_muzzles_come_from_the_manifest_in_the_pitch_frame() -> void:
	if _model().is_empty():
		return
	var muzzles: Array[Vector3] = TurretMount.pitch_muzzles(ASSET)
	assert_eq(muzzles.size(), 4, "a muzzle for each barrel")
	var corners: Dictionary = {}
	for m: Vector3 in muzzles:
		assert_almost_eq(m.z, -8.4, 1e-4, "at the barrels' ends, down -Z")
		assert_almost_eq(absf(m.x), 3.9, 1e-4, "outside the bracket")
		assert_almost_eq(absf(m.y), 1.4, 1e-4, "above or below the axle")
		corners[Vector2(signf(m.x), signf(m.y))] = true
	assert_eq(corners.size(), 4, "one in each corner of the rectangle")
	assert_almost_eq(TurretMount.barrel_reach(ASSET, 0.0), 8.4, 1e-4, "the reach the manifest gives")
	assert_eq(TurretMount.pitch_muzzles("no_such_asset").size(), 0, "none for an asset without them")
	assert_eq(TurretMount.barrel_reach("no_such_asset", 4.5), 4.5, "the fallback without a manifest")


func test_the_parts_hang_from_the_mount_and_turn_as_the_core_aims() -> void:
	var model: Dictionary = _model()
	if model.is_empty():
		return
	var mount: TurretMount = TurretMount.create({"name": "I0", "position": Vector3.ZERO, "up": Vector3.UP}, null, Factions.NEUTRAL)
	add_child_autofree(mount)
	mount.use_model(model)
	assert_eq(mount.pedestal.get_parent(), mount, "the pedestal stays on the mount")
	assert_not_null(mount.yaw.get_node_or_null(^"Yoke"), "the bracket turns round the mount's up")
	assert_not_null(mount.pitch.get_node_or_null(^"Barrels"), "the barrels lift with the elevation")
	assert_eq(mount.pitch.position, model["trunnion"], "about the trunnion")
	var muzzle: Vector3 = TurretMount.pitch_muzzles(ASSET)[0]
	var pedestal_at: Transform3D = mount.pedestal.global_transform
	var rest: Vector3 = mount.pitch.to_global(muzzle)
	mount.turn_to(0.7, 0.5)
	var turned: Vector3 = mount.pitch.to_global(muzzle)
	assert_gt(turned.distance_to(rest), 1.0, "the muzzle swings with the aim")
	assert_gt(turned.y, rest.y + 2.0, "and rises with the elevation")
	assert_true(mount.pedestal.global_transform.is_equal_approx(pedestal_at), "the pedestal does not turn")
	mount.knocked_out = true
	assert_not_null(mount.pedestal.material_override, "a knocked-out battery goes dark, pedestal too")
	assert_not_null((mount.pitch.get_node(^"Barrels") as MeshInstance3D).material_override, "and its barrels")
	mount.knocked_out = false
	assert_null(mount.pedestal.material_override, "its own look back when repaired")


func test_every_battery_on_the_station_wears_it_and_the_guns_keep_theirs() -> void:
	if _model().is_empty():
		return
	var station := Station.new()
	if not station.build():
		station.free()
		pending("the babylon5_station asset is not generated (%s)" % HINT)
		return
	var batteries: int = 0
	for mount: TurretMount in station.grid.mounts:
		if mount.grid_kind == StationGrid.Kind.INTERCEPTOR:
			batteries += 1
			assert_not_null(mount.pedestal, "%s has the battery's pedestal" % mount.mount_name)
			assert_not_null(mount.yaw.get_node_or_null(^"Yoke"), "%s has its bracket" % mount.mount_name)
			assert_not_null(mount.pitch.get_node_or_null(^"Barrels"), "%s has its barrels" % mount.mount_name)
			assert_almost_eq(mount.basis.get_scale().x, 1.0, 1e-4, "%s at the model's own size" % mount.mount_name)
			assert_almost_eq(mount.barrel_m, 8.4, 1e-4, "%s reaches as far as its barrels" % mount.mount_name)
		elif mount.grid_kind == StationGrid.Kind.LIGHT:
			assert_null(mount.pedestal, "%s is a light gun: no pedestal" % mount.mount_name)
			assert_not_null(mount.yaw.get_node_or_null(^"Base"), "%s keeps the Saturns' turret" % mount.mount_name)
	assert_eq(batteries, 9, "D75's nine interceptor batteries")
	station.free()
