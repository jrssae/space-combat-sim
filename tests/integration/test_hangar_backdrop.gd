extends GutTest
## The front end's hangar backdrop (M7-T09, M7-T20; D77, AC8): the generated Cobra-bay interior behind the menu with Alpha wing's
## twelve real Starfuries (six racked over the doors, six staged in the second row) in their numbered livery, its work lamps in the
## light rig's slots and the key light turned into the hall's faint fill, the camera on the hangar's move; without the interior the
## front end keeps M5's sky drift.

const FrontEndScene: PackedScene = preload("res://src/frontend/front_end.tscn")


func before_each() -> void:
	get_tree().paused = false


func _front_end(asset_root: String = "") -> FrontEnd:
	var front: FrontEnd = FrontEndScene.instantiate() as FrontEnd
	front.game = RecordingGame.new()
	autofree(front.game)
	front.quit_game = func() -> void: pass
	if not asset_root.is_empty():
		(front.get_node(^"%Backdrop") as HangarBackdrop).asset_root = asset_root
	add_child_autofree(front)
	await wait_process_frames(2)
	return front


func test_the_hangar_is_behind_the_menu() -> void:
	var front: FrontEnd = await _front_end()
	var backdrop: HangarBackdrop = front.backdrop()
	assert_true(backdrop.is_loaded(), "run scripts/gen_assets.sh, then import")
	var pieces: int = 0
	for child: Node in backdrop.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("bay_"):
			pieces += 1
	assert_eq(pieces, 6, "one launch position drawn at each of the six doors")
	assert_not_null(backdrop.get_node_or_null(^"ends"))
	assert_not_null(backdrop.get_node_or_null(^"signs"))


func test_twelve_starfuries_six_racked_and_six_staged_in_alpha_wings_numbered_livery() -> void:
	var front: FrontEnd = await _front_end()
	var fighters: Array[MeshInstance3D] = front.backdrop().fighters()
	assert_eq(fighters.size(), 12)
	var expected: Mesh = MeshAssets.for_asset("starfury_aurora")
	var manifest: Dictionary = MeshAssets.read_manifest(HangarBackdrop.ASSET_ID)
	var entries: Array = manifest["fighters"]
	for k: int in fighters.size():
		var ship: MeshInstance3D = fighters[k]
		var entry: Dictionary = entries[k]
		assert_eq(ship.mesh, expected, "the real Starfury, not a copy baked into the hall")
		assert_eq(String(ship.name), "alpha_%d_%d" % [int(entry["door"]), int(entry["wave"])], "named by its id")
		assert_eq(int(ship.get_instance_shader_parameter(&"livery_number")), int(entry["number"]), "Alpha 1 to 12")
		assert_true(ship.basis.is_equal_approx(Basis.IDENTITY), "nose toward the arm's head")
	var racked: Array = entries.filter(func(e: Dictionary) -> bool: return int(e["wave"]) == 1)
	var staged: Array = entries.filter(func(e: Dictionary) -> bool: return int(e["wave"]) == 2)
	assert_eq(racked.size(), 6, "one over each door")
	assert_eq(staged.size(), 6, "the second row")
	assert_gt(float(staged[0]["position"][1]), float(racked[0]["position"][1]), "staged in the lower hall, toward the axis")


func test_its_lamps_fit_the_light_rigs_budget() -> void:
	var front: FrontEnd = await _front_end()
	var backdrop: HangarBackdrop = front.backdrop()
	assert_eq(backdrop.emitters().size(), 6, "one work lamp a bay")
	assert_lte(backdrop.emitters().size(), LightPicker.SLOT_COUNT, "never more than the omni slots")
	var rig: LightRig = LightRig.of(backdrop)
	assert_not_null(rig)
	await wait_process_frames(2)
	assert_lte(rig.active_count(), 8, "the key light and the 7 omni slots")
	var manifest: Dictionary = MeshAssets.read_manifest(HangarBackdrop.ASSET_ID)
	assert_almost_eq(rig.key_star.light_energy, float(manifest["fill"]["energy"]), 1e-4, "the key light is the hall's dim fill")
	assert_gt(rig.key_star.global_basis.z.y, 0.5, "shining down from the ceiling (the light travels along its -Z)")


func test_the_camera_follows_the_hangars_move() -> void:
	var front: FrontEnd = await _front_end()
	var camera: Camera3D = front.get_node(^"%Camera") as Camera3D
	var start: Vector3 = camera.global_position
	await wait_seconds(0.5)
	assert_true(camera.transform.is_equal_approx(front.backdrop().camera_pose()), "the camera is where the move puts it")
	assert_ne(camera.global_position, start, "and it moves")
	assert_lt(absf(camera.global_position.x), 20.0, "inside the upper hall")


func test_the_console_picks_the_view() -> void:
	var front: FrontEnd = await _front_end()
	var results: Array[ConsoleResult] = DebugConsole.registry.execute("backdrop wide")
	assert_true(results[0].ok, results[0].text())
	assert_eq(DebugConsole.registry.read("backdrop.view").get("value"), "wide")
	assert_eq(int(DebugConsole.registry.read("backdrop.fighters").get("value")), 12)
	DebugConsole.registry.execute("backdrop second")
	assert_eq(DebugConsole.registry.read("backdrop.view").get("value"), "second")
	DebugConsole.registry.execute("backdrop move 30")
	assert_almost_eq(float(DebugConsole.registry.read("backdrop.time_s").get("value")), 30.0, 0.1)
	assert_not_null(front)


func test_without_the_interior_the_sky_drifts_as_before() -> void:
	var front: FrontEnd = await _front_end("res://tests/fixtures/no_such_assets")
	assert_false(front.backdrop().is_loaded())
	assert_eq(front.backdrop().fighters().size(), 0)
	await wait_seconds(0.5)
	var camera: Camera3D = front.get_node(^"%Camera") as Camera3D
	assert_eq(camera.position, Vector3.ZERO, "the sky's camera stays put")
	assert_false(camera.basis.is_equal_approx(Basis.IDENTITY), "and turns with the drift")
