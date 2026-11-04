class_name SpaceEnvironment
extends Node3D
## The sky and the light, outside `World` (architecture §3, §7): a black WorldEnvironment with the GDGS compositor effect, then
## the motion blur and the lens flare (`PostEffects` drives both), the `SplatLightRig` (the warm `KeyStar` and the 7 omni slots:
## the scene's only lights), and `SkySplats` (stars and nebula as Gaussian splats, never lit: they are emitters) pinned to the
## camera by `SkyFollower`. Camera-relative, so it is never rebased and holds nothing a gameplay system needs.
##
## It loads without any generated asset: the sky splats and the manifest are loaded here, guarded, so the scene (and
## the headless tests) work before `scripts/gen_assets.sh` has run, with a warning instead of a load error.
##
## `settings.ambient_level` (M4-T30a) is the environment's ambient light: what the textured meshes and every other PBR surface get
## on every side, the role `relight_ambient` plays for the splats. It applies live, to the fallback environment too.
##
## Anything visual here is (H): it cannot be seen without a GPU.

## Fallback for GPUs where neither GDGS backend starts (architecture §7.4): the panorama render of the same sky.
const ENVIRONMENT_FALLBACK_PATH: String = "res://assets/environment/environment_fallback.tres"
const SKY_DIR: String = "res://assets/generated/sky_default"
const SKY_GAUSSIAN_PATH: String = SKY_DIR + "/sky_default.ply"
const SKY_MANIFEST_PATH: String = SKY_DIR + "/manifest.json"
const SKY_PANORAMA_PATH: String = SKY_DIR + "/sky_default_panorama.png"

## GDGS compositor tunables (`GaussianCompositorEffect`), pushed into the effect in `_ready` and on every change.
## How far in front of scene depth a splat may sit before the mesh occludes it.
@export_range(0.0, 1.0, 0.001) var depth_bias: float = 0.05:
	set(value):
		depth_bias = value
		_apply_compositor_tuning()
## Splats fainter than this do not take part in the depth test.
@export_range(0.0, 1.0, 0.001) var depth_test_min_alpha: float = 0.05:
	set(value):
		depth_test_min_alpha = value
		_apply_compositor_tuning()

## The file `environment_fallback.tres` references, checked before loading it: a `.tres` whose external texture is
## missing fails to load with errors. A variable so that a test can point it at a file that does not exist.
var fallback_panorama_path: String = SKY_PANORAMA_PATH

var _default_environment: Environment
var _fallback_active: bool = false

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var light_rig: SplatLightRig = $SplatLightRig
@onready var key_star: DirectionalLight3D = $SplatLightRig/KeyStar
@onready var sky_splats: GaussianSplatNode = $SkySplats
@onready var sky_follower: SkyFollower = $SkyFollower
@onready var post_effects: PostEffects = $PostEffects


func _init() -> void:
	add_to_group(SplatStatus.SKY_GROUP)  # SplatStatus calls use_fallback_sky (no backend, console, F4)


func _ready() -> void:
	_default_environment = world_environment.environment
	_load_sky()
	_apply_compositor_tuning()
	_apply_ambient()
	Settings.changed.connect(_on_setting_changed)
	use_star_of(&"local")


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"ambient_level":
		_apply_ambient()


## The ambient light every PBR surface gets, `settings.ambient_level` of white, on whichever environment is current.
func _apply_ambient() -> void:
	var environment: Environment = world_environment.environment
	if environment == null:
		return
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = float(Settings.get_value(&"ambient_level"))


## Shows the star of `system_id`, from `data/star_systems.json`.
func use_star_of(system_id: StringName) -> void:
	set_star(StarCatalog.temperature_k(system_id))


## Gives the key star's light and the lens flare one colour: the star's, from its temperature (Q30).
func set_star(temperature_k: float) -> void:
	var color: Color = StarColor.linear_from_kelvin(temperature_k)
	key_star.light_color = color.linear_to_srgb()
	post_effects.set_star_color(color)


## Switches between the splat sky (false) and the generated panorama (true). The fallback hides `SkySplats` and swaps
## in `environment_fallback.tres`; if the panorama was not generated (it needs Pillow) it warns and keeps the black
## default environment instead of failing. The compositor effect stays: the ship and buoys are still splats.
func use_fallback_sky(enabled: bool) -> void:
	_fallback_active = enabled
	sky_splats.visible = not enabled
	if not enabled:
		world_environment.environment = _default_environment
		_apply_ambient()
		return
	var fallback: Environment = _load_fallback_environment()
	if fallback == null:
		push_warning("SpaceEnvironment: no panorama at %s (needs Pillow; run scripts/gen_assets.sh); the fallback sky is black" % fallback_panorama_path)
		return
	world_environment.environment = fallback
	_apply_ambient()


func is_fallback_sky_active() -> bool:
	return _fallback_active


## The Gaussian compositor effect on the WorldEnvironment's Compositor, or null if there is none.
func get_gaussian_effect() -> GaussianCompositorEffect:
	var compositor: Compositor = world_environment.compositor
	if compositor == null:
		return null
	for effect: CompositorEffect in compositor.compositor_effects:
		if effect is GaussianCompositorEffect:
			return effect as GaussianCompositorEffect
	return null


func _load_sky() -> void:
	var manifest: SkyManifest = SkyManifest.load_file(SKY_MANIFEST_PATH)
	if manifest.valid:
		sky_follower.centroid_offset = manifest.centroid_offset
	else:
		push_warning("SpaceEnvironment: sky manifest unusable (%s); the sky sphere will be off-centre" % manifest.error)
	if ResourceLoader.exists(SKY_GAUSSIAN_PATH):
		var gaussian: GaussianResource = load(SKY_GAUSSIAN_PATH) as GaussianResource
		if gaussian != null:
			sky_splats.gaussian = gaussian
	else:
		push_warning("SpaceEnvironment: %s is missing or not imported (run scripts/gen_assets.sh, then import); no splat sky" % SKY_GAUSSIAN_PATH)
	# Place the sky now rather than at the next frame, in case a camera is already current.
	sky_follower.follow()


func _load_fallback_environment() -> Environment:
	if not ResourceLoader.exists(fallback_panorama_path) or not ResourceLoader.exists(ENVIRONMENT_FALLBACK_PATH):
		return null
	return load(ENVIRONMENT_FALLBACK_PATH) as Environment


func _apply_compositor_tuning() -> void:
	# Exported setters run before the node tree exists when the scene is instantiated.
	if not is_node_ready():
		return
	var effect: GaussianCompositorEffect = get_gaussian_effect()
	if effect == null:
		return
	effect.depth_bias = depth_bias
	effect.depth_test_min_alpha = depth_test_min_alpha
