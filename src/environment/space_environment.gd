class_name SpaceEnvironment
extends Node3D
## The sky and the light, outside `World` (architecture §3, §7, §17.19): the WorldEnvironment with the motion blur and the lens flare
## (`PostEffects` drives both), the `LightRig` (the warm `KeyStar` and the 7 omni slots: the scene's only lights), and the sky
## (M4-T30c): `StarField`, the stars as points pinned to the camera by `SkyFollower`, and the nebula as a panorama on the
## environment's sky. Camera-relative, so it is never rebased and holds nothing a gameplay system needs.
##
## It loads without any generated asset: the manifest, the star file and the panorama are loaded here, guarded, so the scene (and
## the headless tests) work before `scripts/gen_assets.sh` has run, with a warning and a black sky instead of a load error.
##
## `settings.ambient_level` (M4-T30a) is the environment's ambient light: what the textured meshes and every other PBR surface get
## on every side, so the dark side of a hull stays legible. It applies live.
##
## The far bodies (M6-T10, D68): `ScaledSpace` draws the star and the planets where they truly are, and the `KeyStar` follows it:
## the light comes from the true sun direction and dims by the part of the star's disc a planet hides at the camera. The lens
## flare reads the `KeyStar`, so it follows too. With no star system in view the light stays as the scene made it. A look sheet
## takes the light for itself with `hold_key_star`.
##
## Anything visual here is (H): it cannot be seen without a GPU.

const SKY_DIR: String = "res://assets/generated/sky_default"
## The parts of the sky the `sky` command shows and hides.
const SKY_PARTS: Array[StringName] = [&"stars", &"nebula"]

## Where the generated sky is read from. A variable so that a test can point it at a directory that does not exist.
var sky_dir: String = SKY_DIR

## The far bodies' layer; made in `_ready`.
var scaled_space: ScaledSpace

var _panorama: Texture2D
var _nebula_shown: bool = true
## The key star's energy in full sunlight, as the scene set it.
var _key_energy: float = 1.0
var _key_held: bool = false

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var light_rig: LightRig = $LightRig
@onready var key_star: DirectionalLight3D = $LightRig/KeyStar
@onready var star_field: StarField = $StarField
@onready var sky_follower: SkyFollower = $SkyFollower
@onready var post_effects: PostEffects = $PostEffects
@onready var anti_aliasing: AntiAliasing = $AntiAliasing
@onready var upscaler: Upscaler = $Upscaler


func _init() -> void:
	# After the layer has placed the bodies for this frame's camera.
	process_priority = ScaledSpace.LATE_PRIORITY + 1


func _ready() -> void:
	_key_energy = key_star.light_energy
	scaled_space = ScaledSpace.new()
	scaled_space.name = "ScaledSpace"
	add_child(scaled_space)
	_load_sky()
	_apply_ambient()
	Settings.changed.connect(_on_setting_changed)
	use_star_of(&"local")
	DebugConsole.registry.register_provider(&"sky", ConsoleVars.new({
		&"stars": {"get": func() -> int: return star_field.star_count(), "doc": "Stars in the point field (M4-T30c)"},
		&"stars_shown": {"get": func() -> bool: return star_field.visible, "doc": "The star field is drawn"},
		&"panorama": {"get": func() -> bool: return has_panorama(), "doc": "The nebula panorama was loaded"},
		&"nebula_shown": {"get": func() -> bool: return _nebula_shown and has_panorama(), "doc": "The nebula panorama is drawn"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"sky",
			"Show or hide a part of the sky (the star points or the nebula panorama); with no state, toggle",
			[ConsoleArg.enum_required(&"part", SKY_PARTS), ConsoleArg.bool_optional(&"state")]), _cmd_sky, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


func _process(_delta: float) -> void:
	follow_sun()


## Turns the key star to shine from the true sun and dims it in a planet's shadow. `_process` calls it; public for the tests.
func follow_sun() -> void:
	if _key_held or not scaled_space.has_sun():
		return
	key_star.global_transform = Transform3D(key_basis(scaled_space.sun_direction()), key_star.global_position)
	key_star.light_energy = _key_energy * scaled_space.key_light()


## The key star's orientation for a star in direction `to_sun`: the light travels along its -Z, so its +Z points at the star
## (what the lens flare reads).
static func key_basis(to_sun: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(-to_sun, up)


## Leaves the key star to a caller that lights its own subject (a look sheet), in full light; false gives it back to the sun.
func hold_key_star(held: bool) -> void:
	_key_held = held
	if held:
		key_star.light_energy = _key_energy


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"ambient_level":
		_apply_ambient()
	elif key == &"hull_sheen":
		_apply_background()


## The ambient light every PBR surface gets, `settings.ambient_level` of white.
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


func has_panorama() -> bool:
	return _panorama != null


## Shows or hides one part of the sky: `stars` (the point field) or `nebula` (the panorama), for comparisons and measures.
func show_sky_part(part: StringName, shown: bool) -> void:
	if part == &"stars":
		star_field.visible = shown
	elif part == &"nebula":
		_nebula_shown = shown
		_apply_background()


## Reads the generated sky: the star points and the nebula panorama. What is missing stays dark, with a warning.
func _load_sky() -> void:
	_panorama = null
	var manifest: SkyManifest = SkyManifest.load_file(sky_dir + "/manifest.json")
	if not manifest.valid:
		push_warning("SpaceEnvironment: sky manifest unusable (%s); no stars or nebula" % manifest.error)
		star_field.clear()
	else:
		star_field.load_file(sky_dir + "/" + manifest.star_file, manifest.star_count, manifest.star_radius_mrad,
				manifest.star_floor_px)
		var panorama_path: String = sky_dir + "/" + manifest.panorama_file
		if manifest.panorama_file != "" and ResourceLoader.exists(panorama_path):
			_panorama = load(panorama_path) as Texture2D
		else:
			push_warning("SpaceEnvironment: no nebula panorama in %s (run scripts/gen_assets.sh, then import)" % sky_dir)
	_apply_background()
	# Place the sky now rather than at the next frame, in case a camera is already current.
	sky_follower.follow()


## The environment's background: the nebula panorama when it is loaded and shown, else black. With `settings.hull_sheen` above 0
## the hulls' clear coat reflects it faintly; at 0 nothing reflects it, the flat paint they were first approved with.
func _apply_background() -> void:
	var environment: Environment = world_environment.environment
	if environment == null:
		return
	var reflect: bool = float(Settings.get_value(&"hull_sheen")) > 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if reflect else Environment.REFLECTION_SOURCE_DISABLED
	star_field.set_nebula(_panorama if _nebula_shown else null)
	if _panorama == null or not _nebula_shown:
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color.BLACK
		return
	if environment.sky == null or not (environment.sky.sky_material is PanoramaSkyMaterial):
		var sky := Sky.new()
		sky.sky_material = PanoramaSkyMaterial.new()
		# Only the hulls' sheen samples its radiance, through a fairly rough clear coat: a small cubemap is enough.
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		environment.sky = sky
	(environment.sky.sky_material as PanoramaSkyMaterial).panorama = _panorama
	environment.background_mode = Environment.BG_SKY


func _cmd_sky(args: Dictionary) -> ConsoleResult:
	var part: StringName = StringName(args[&"part"])
	var current: bool = star_field.visible if part == &"stars" else _nebula_shown
	var shown: bool = not current if args[&"state"] == null else bool(args[&"state"])
	show_sky_part(part, shown)
	if part == &"nebula" and not has_panorama():
		return ConsoleResult.line("sky nebula missing (no panorama loaded; run scripts/gen_assets.sh)")
	return ConsoleResult.line("sky %s %s" % [part, "on" if shown else "off"])
