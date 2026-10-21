extends GutTest
## SpaceEnvironment against the real scene, headless (architecture §3, §7.2, §9.2). There is no GPU here: GDGS finds
## no RenderingDevice and skips backend selection quietly, so these tests cover wiring and values, not pixels. What
## the sky and the compositor look like is (H).

const SCENE_PATH: String = "res://src/environment/space_environment.tscn"
const ENVIRONMENT_DEFAULT_PATH: String = "res://assets/environment/environment_default.tres"
const GDGS_EFFECT_SCRIPT_PATH: String = "res://addons/gdgs/runtime/compositor/gaussian_compositor_effect.gd"
const MANIFEST_PATH: String = "res://assets/generated/sky_default/manifest.json"
const PANORAMA_PATH: String = "res://assets/generated/sky_default/sky_default_panorama.png"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"

var env: SpaceEnvironment
var camera: Camera3D


func before_each() -> void:
	camera = Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	env = _instantiate()
	add_child_autofree(env)


func _instantiate() -> SpaceEnvironment:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed, "scene loads")
	return packed.instantiate() as SpaceEnvironment


## The real manifest, parsed independently of SkyManifest so a parser bug cannot hide in both.
func _read_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _manifest_offset() -> Vector3:
	var manifest: Dictionary = _read_manifest()
	assert_true(manifest.has("centroid_offset"), "manifest has centroid_offset (%s)" % GEN_ASSETS_HINT)
	var parts: Array = manifest.get("centroid_offset", [0.0, 0.0, 0.0])
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


## One frame has run its `_process` once the second `process_frame` has fired (the signal fires before the nodes').
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


# --- structure ---------------------------------------------------------------------------------------------------


func test_scene_instantiates_with_every_part() -> void:
	assert_not_null(env, "root script is SpaceEnvironment")
	assert_true(env.world_environment is WorldEnvironment)
	assert_true(env.key_star is DirectionalLight3D)
	assert_true(env.sky_splats is GaussianSplatNode)
	assert_true(env.sky_follower is SkyFollower)
	assert_eq(env.sky_follower.sky, env.sky_splats, "the follower is wired to SkySplats (node_paths in the .tscn)")
	assert_true(env.sky_splats.top_level, "the sky ignores its parent's transform")
	assert_null(env.get_parent() as WorldFrame, "the environment is not under World: it is camera-relative")


func test_sky_splats_load_when_the_asset_is_generated() -> void:
	var gaussian: GaussianResource = env.sky_splats.gaussian
	assert_not_null(gaussian, "sky_default.ply imported as a GaussianResource (%s)" % GEN_ASSETS_HINT)
	if gaussian == null:
		return
	var lods: Array = _read_manifest().get("lods", [])
	assert_false(lods.is_empty(), "manifest lists lods")
	if not lods.is_empty():
		assert_eq(gaussian.point_count, int((lods[0] as Dictionary)["splats"]), "splat count matches manifest.lods[0]")


# --- environment resource ----------------------------------------------------------------------------------------


func test_default_environment_is_black_dim_filmic_with_modest_glow() -> void:
	var e: Environment = env.world_environment.environment
	assert_not_null(e)
	assert_eq(e.resource_path, ENVIRONMENT_DEFAULT_PATH)
	assert_eq(e.background_mode, Environment.BG_COLOR)
	assert_eq(e.background_color, Color.BLACK)
	assert_eq(e.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_almost_eq(e.ambient_light_color.r, 0.02, 0.0001)
	assert_almost_eq(e.ambient_light_color.g, 0.02, 0.0001)
	assert_almost_eq(e.ambient_light_color.b, 0.02, 0.0001)
	assert_eq(e.tonemap_mode, Environment.TONE_MAPPER_FILMIC)
	assert_true(e.glow_enabled)
	assert_almost_eq(e.glow_intensity, 0.4, 0.0001)
	assert_almost_eq(e.glow_hdr_threshold, 1.0, 0.0001)
	assert_false(e.fog_enabled)
	assert_false(e.ssao_enabled)
	assert_false(e.ssr_enabled)
	assert_null(e.sky, "the default sky is the splats, not a Sky resource")


# --- GDGS compositor ---------------------------------------------------------------------------------------------


func test_compositor_holds_exactly_the_gdgs_effect() -> void:
	var compositor: Compositor = env.world_environment.compositor
	assert_not_null(compositor)
	assert_eq(compositor.compositor_effects.size(), 1, "one effect")
	var effect: GaussianCompositorEffect = env.get_gaussian_effect()
	assert_not_null(effect, "the effect is a GaussianCompositorEffect")
	assert_eq((effect.get_script() as Script).resource_path, GDGS_EFFECT_SCRIPT_PATH)
	assert_eq(effect.effect_callback_type, CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT, "splats go before transparent meshes (§7.2)")
	assert_true(effect.access_resolved_depth, "the depth test needs resolved scene depth")
	assert_true(effect.enabled)


func test_defaults_match_the_gdgs_defaults() -> void:
	var effect: GaussianCompositorEffect = env.get_gaussian_effect()
	assert_almost_eq(env.depth_bias, 0.05, 0.0001)
	assert_almost_eq(env.depth_test_min_alpha, 0.05, 0.0001)
	assert_almost_eq(effect.depth_bias, env.depth_bias, 0.0001)
	assert_almost_eq(effect.depth_test_min_alpha, env.depth_test_min_alpha, 0.0001)


func test_root_exports_drive_the_effect() -> void:
	var effect: GaussianCompositorEffect = env.get_gaussian_effect()
	env.depth_bias = 0.2
	assert_almost_eq(effect.depth_bias, 0.2, 0.0001)
	env.depth_test_min_alpha = 0.125
	assert_almost_eq(effect.depth_test_min_alpha, 0.125, 0.0001)
	assert_almost_eq(effect.depth_bias, 0.2, 0.0001, "the other tunable is untouched")


func test_exports_set_before_entering_the_tree_are_applied_at_ready() -> void:
	var tuned: SpaceEnvironment = _instantiate()
	tuned.depth_bias = 0.3
	tuned.depth_test_min_alpha = 0.4
	add_child_autofree(tuned)
	var effect: GaussianCompositorEffect = tuned.get_gaussian_effect()
	assert_almost_eq(effect.depth_bias, 0.3, 0.0001)
	assert_almost_eq(effect.depth_test_min_alpha, 0.4, 0.0001)


func test_a_new_instance_reapplies_its_own_values_to_the_shared_effect() -> void:
	# The Compositor sub-resource lives in the cached PackedScene, so instances share it; each instance's _ready
	# must therefore push its own exports rather than trust what it finds on the effect.
	env.depth_bias = 0.9
	var fresh: SpaceEnvironment = _instantiate()
	add_child_autofree(fresh)
	assert_almost_eq(fresh.get_gaussian_effect().depth_bias, 0.05, 0.0001)


# --- key light ---------------------------------------------------------------------------------------------------


func test_key_star_is_a_warm_light_from_front_left_above() -> void:
	var light: DirectionalLight3D = env.key_star
	assert_almost_eq(light.light_energy, 1.5, 0.0001)
	assert_gt(light.light_color.r, light.light_color.b + 0.05, "warm: more red than blue")
	assert_true(light.visible)
	# A directional light shines along its local -Z, so +Z points at the light. The ship faces -Z, its left is -X.
	var to_light: Vector3 = light.global_transform.basis.z.normalized()
	assert_lt(to_light.z, -0.3, "from the front (-Z)")
	assert_lt(to_light.x, -0.2, "from the left (-X)")
	assert_gt(to_light.y, 0.3, "from above (+Y)")


# --- sky follower ------------------------------------------------------------------------------------------------


func test_sky_origin_adds_the_offset() -> void:
	assert_eq(SkyFollower.sky_origin(Vector3(1, 2, 3), Vector3(10, 20, 30)), Vector3(11, 22, 33))
	assert_eq(SkyFollower.sky_origin(Vector3(1, 2, 3), Vector3.ZERO), Vector3(1, 2, 3))


func test_follower_runs_late_in_both_loops() -> void:
	assert_gt(env.sky_follower.process_priority, 0, "after the camera rig's _process")
	assert_gt(env.sky_follower.process_physics_priority, 0, "after a rebase made in the physics tick")
	assert_true(env.sky_follower.is_processing())
	assert_true(env.sky_follower.is_physics_processing())


func test_follower_gets_the_manifest_offset() -> void:
	var offset: Vector3 = _manifest_offset()
	assert_almost_eq(env.sky_follower.centroid_offset, offset, Vector3.ONE * 0.001)
	assert_gt(offset.length(), 100.0, "the generated sky really is one-sided; otherwise this test proves nothing")


func test_sky_origin_tracks_the_camera_plus_the_centroid_offset() -> void:
	var offset: Vector3 = _manifest_offset()
	for camera_position: Vector3 in [Vector3.ZERO, Vector3(1000.0, -250.0, 4000.0), Vector3(-18000.0, 9000.0, -500.0)]:
		camera.global_position = camera_position
		await _settle()
		var expected: Vector3 = camera_position + offset
		assert_almost_eq(env.sky_splats.global_position, expected, Vector3.ONE * 0.01, "camera at %s" % camera_position)
		assert_almost_eq(env.sky_splats.global_position - camera.global_position, offset, Vector3.ONE * 0.01, "the node sits at camera + offset, not on the camera")


func test_physics_tick_alone_repositions_the_sky() -> void:
	var offset: Vector3 = _manifest_offset()
	camera.global_position = Vector3(5000.0, 0.0, -7000.0)
	# No process frame in between: this is the path a teleport or rebase made in a physics tick relies on.
	env.sky_follower._physics_process(1.0 / 60.0)
	assert_almost_eq(env.sky_splats.global_position, camera.global_position + offset, Vector3.ONE * 0.01)


func test_process_alone_repositions_the_sky() -> void:
	var offset: Vector3 = _manifest_offset()
	camera.global_position = Vector3(-300.0, 40.0, 25.0)
	env.sky_follower._process(0.016)
	assert_almost_eq(env.sky_splats.global_position, camera.global_position + offset, Vector3.ONE * 0.01)


func test_a_large_jump_is_followed_at_once() -> void:
	# What a World rebase does to the camera: a sudden shift of kilometres.
	var offset: Vector3 = _manifest_offset()
	camera.global_position = Vector3(100.0, 0.0, 0.0)
	await _settle()
	camera.global_position -= Vector3(15000.0, 0.0, 0.0)
	env.sky_follower._physics_process(1.0 / 60.0)
	assert_almost_eq(env.sky_splats.global_position, Vector3(-14900.0, 0.0, 0.0) + offset, Vector3.ONE * 0.01)


func test_sky_ignores_camera_rotation() -> void:
	await _settle()
	var basis_before: Basis = env.sky_splats.global_transform.basis
	camera.global_position = Vector3(10.0, 20.0, 30.0)
	camera.rotate_y(deg_to_rad(90.0))
	camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(35.0))
	await _settle()
	assert_true(env.sky_splats.global_transform.basis.is_equal_approx(basis_before), "the sky is fixed in the world; the camera turns inside it")


func test_without_a_camera_the_sky_stays_put() -> void:
	camera.global_position = Vector3(10.0, 0.0, 0.0)
	await _settle()
	var placed: Vector3 = env.sky_splats.global_position
	camera.clear_current()
	assert_null(get_viewport().get_camera_3d(), "no current camera")
	camera.global_position = Vector3(99.0, 0.0, 0.0)
	assert_false(env.sky_follower.follow())
	await _settle()
	assert_eq(env.sky_splats.global_position, placed)


func test_star_sphere_is_centred_on_the_camera() -> void:
	# The whole import chain in one assertion: PLY (re-centred by the generator, flipped to the 3DGS frame), GDGS
	# (subtracts the mean again, node turned by 180 degrees about Z), SkyFollower (adds the manifest offset). Every
	# star must then lie 20 km from the camera. Leaving the offset out puts the nearest stars 4.6 km closer and the
	# farthest 4.6 km further away.
	var manifest: Dictionary = _read_manifest()
	var gaussian: GaussianResource = env.sky_splats.gaussian
	assert_not_null(gaussian, GEN_ASSETS_HINT)
	if gaussian == null or manifest.is_empty():
		return
	var star_count: int = int(manifest["counts"]["stars"])
	var radius: float = float(manifest["sky_radius_m"])
	camera.global_position = Vector3(-3000.0, 800.0, 1500.0)
	await _settle()
	var sky_transform: Transform3D = env.sky_splats.global_transform
	var offset: Vector3 = _manifest_offset()
	var uncorrected_transform := Transform3D(sky_transform.basis, camera.global_position)
	var worst_with_offset: float = 0.0
	var worst_without_offset: float = 0.0
	for i: int in star_count:
		var local: Vector3 = gaussian.xyz[i]
		worst_with_offset = maxf(worst_with_offset, absf((sky_transform * local - camera.global_position).length() - radius))
		worst_without_offset = maxf(worst_without_offset, absf((uncorrected_transform * local - camera.global_position).length() - radius))
	assert_lt(worst_with_offset, 1.0, "every star within 1 m of the sky radius")
	assert_gt(worst_without_offset, 0.9 * offset.length(), "without the offset the sphere is visibly off-centre")


# --- fallback sky ------------------------------------------------------------------------------------------------


func test_fallback_sky_swaps_the_environment_and_hides_the_splats() -> void:
	if not ResourceLoader.exists(PANORAMA_PATH):
		pending("sky_default_panorama.png not generated (needs Pillow); the missing-panorama path is tested below")
		return
	var default_env: Environment = env.world_environment.environment
	assert_false(env.is_fallback_sky_active())
	env.use_fallback_sky(true)
	assert_true(env.is_fallback_sky_active())
	assert_false(env.sky_splats.visible, "SkySplats hidden")
	var fallback: Environment = env.world_environment.environment
	assert_ne(fallback, default_env, "environment swapped")
	assert_eq(fallback.background_mode, Environment.BG_SKY)
	assert_not_null(fallback.sky)
	assert_true(fallback.sky.sky_material is PanoramaSkyMaterial, "PanoramaSkyMaterial")
	var panorama: Texture2D = (fallback.sky.sky_material as PanoramaSkyMaterial).panorama
	assert_not_null(panorama, "panorama texture loaded")
	assert_eq(panorama.resource_path, PANORAMA_PATH)
	assert_not_null(env.get_gaussian_effect(), "the compositor stays: hull and buoys are still splats")
	# The panorama environment keeps the tone mapping, glow and ambient source of the default one (and adds ambient fill, below).
	assert_eq(fallback.tonemap_mode, default_env.tonemap_mode)
	assert_eq(fallback.ambient_light_source, default_env.ambient_light_source)
	# Only the ambient level differs: the mesh hull has no baked light, so it needs a fill the splat hull does not.
	assert_gte(fallback.ambient_light_color.r, default_env.ambient_light_color.r, "the fallback is not darker")
	assert_eq(fallback.glow_enabled, default_env.glow_enabled)
	assert_almost_eq(fallback.glow_intensity, default_env.glow_intensity, 0.0001)
	assert_almost_eq(fallback.glow_hdr_threshold, default_env.glow_hdr_threshold, 0.0001)
	assert_false(fallback.fog_enabled)
	assert_false(fallback.ssao_enabled)
	assert_false(fallback.ssr_enabled)


func test_fallback_sky_can_be_switched_off_and_on_repeatedly() -> void:
	var default_env: Environment = env.world_environment.environment
	env.use_fallback_sky(true)
	env.use_fallback_sky(true)
	env.use_fallback_sky(false)
	assert_false(env.is_fallback_sky_active())
	assert_true(env.sky_splats.visible, "SkySplats shown again")
	assert_eq(env.world_environment.environment, default_env, "the default environment is back")
	env.use_fallback_sky(false)
	assert_eq(env.world_environment.environment, default_env)
	env.use_fallback_sky(true)
	env.use_fallback_sky(false)
	assert_eq(env.world_environment.environment, default_env)


func test_fallback_sky_without_a_panorama_degrades_without_errors() -> void:
	var default_env: Environment = env.world_environment.environment
	env.fallback_panorama_path = "res://assets/generated/sky_default/no_such_panorama.png"
	env.use_fallback_sky(true)
	assert_true(env.is_fallback_sky_active())
	assert_false(env.sky_splats.visible, "the splat sky is still hidden")
	assert_eq(env.world_environment.environment, default_env, "no panorama to show, so the black environment stays")
	assert_push_warning("no panorama")
	env.use_fallback_sky(false)
	assert_true(env.sky_splats.visible)
	assert_eq(env.world_environment.environment, default_env)
