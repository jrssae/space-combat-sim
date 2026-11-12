extends Node
## Photographs Epsilon III on the scaled-space layer for the maintainer's look sheet (M6-T11): the day side, the terminator and
## the night side from the station's rail, the limb, the ground and the terminator from a 400 km orbit, the planet from
## 1 000 km up, and close-ups of the limb. The scene is the game's own sky and light (`SpaceEnvironment`) with a bare camera
## and no ships, so nothing stands in front of the planet. Each view sets the frame's anchor, the sim time and where the
## camera looks, then saves one PNG. Bench-only: nothing in the game uses it.
##
## Each line printed gives the GPU's time for the frame, the mean over the last `measure` frames: `layer=off` hides the
## scaled-space layer for the same views, the cost's baseline.
##
## Arguments after `--`: shots=<dir> views=<a,b,...> settle=<frames> measure=<frames> layer=<on|off> flare=<on|off>

const ENV_SCENE: String = "res://src/environment/space_environment.tscn"
const PLANET: StringName = &"epsilon_iii"
const STAR: StringName = &"epsilon"
const RAIL: StringName = &"babylon5"
## Each view: the anchor (`rail`, or an orbit `altitude_km` at `phase_deg` from the point under the sun, 90 the
## terminator, 180 midnight), the sim time as a share of the station's orbit (`orbit`), what the camera aims at (`planet`,
## `lit_limb`, `dark_limb`, `down`), how far past that it turns (`lift_deg`), the field of view and a roll (deg).
const VIEWS: Dictionary = {
	"rail_day": {"anchor": "rail", "orbit": 0.333, "aim": "planet", "fov": 32.0, "roll": 0.0},
	"rail_terminator": {"anchor": "rail", "orbit": 0.25, "aim": "planet", "fov": 32.0, "roll": 0.0},
	"rail_full": {"anchor": "rail", "orbit": 0.5, "aim": "planet", "fov": 32.0, "roll": 0.0},
	"rail_crescent": {"anchor": "rail", "orbit": 0.07, "aim": "planet", "fov": 32.0, "roll": 0.0},
	"rail_eclipse": {"anchor": "rail", "orbit": 0.0, "aim": "planet", "fov": 32.0, "roll": 0.0},
	"rail_like_still": {"anchor": "rail", "orbit": 0.305, "aim": "planet", "fov": 26.0, "roll": 56.0},
	"rail_lit_limb_zoom": {"anchor": "rail", "orbit": 0.333, "aim": "lit_limb", "lift_deg": 0.0, "fov": 3.0, "roll": 0.0},
	"rail_dark_limb_zoom": {"anchor": "rail", "orbit": 0.333, "aim": "dark_limb", "lift_deg": 0.0, "fov": 3.0, "roll": 0.0},
	"sun_open": {"anchor": "rail", "orbit": 0.333, "aim": "sun", "fov": 24.0, "roll": 0.0},
	"sun_wide": {"anchor": "rail", "orbit": 0.333, "aim": "sun", "fov": 70.0, "roll": 0.0},
	"sun_off_axis": {"anchor": "rail", "orbit": 0.333, "aim": "sun", "lift_deg": 14.0, "fov": 60.0, "roll": 0.0},
	"sun_planet": {"anchor": "rail", "orbit": 0.07, "aim": "sun_planet", "fov": 70.0, "roll": 0.0},
	"sun_planet_tight": {"anchor": "rail", "orbit": 0.045, "aim": "sun_planet", "fov": 40.0, "roll": 0.0},
	"sun_limb_a": {"anchor": "rail", "orbit": 0.0268, "aim": "sun", "fov": 12.0, "roll": 0.0},
	"sun_limb_b": {"anchor": "rail", "orbit": 0.0278, "aim": "sun", "fov": 12.0, "roll": 0.0},
	"sun_limb_c": {"anchor": "rail", "orbit": 0.0287, "aim": "sun", "fov": 12.0, "roll": 0.0},
	"sun_limb_d": {"anchor": "rail", "orbit": 0.0310, "aim": "sun", "fov": 12.0, "roll": 0.0},
	"sun_eclipse": {"anchor": "rail", "orbit": 0.0, "aim": "sun", "fov": 12.0, "roll": 0.0},
	"sun_orbit400": {"anchor": "orbit", "altitude_km": 400.0, "phase_deg": 100.0, "aim": "sun_planet", "fov": 80.0, "roll": 0.0},
	"orbit400_lit_limb": {"anchor": "orbit", "altitude_km": 400.0, "phase_deg": 90.0, "aim": "lit_limb", "lift_deg": 12.0,
			"fov": 60.0, "roll": 0.0},
	"orbit400_day_limb": {"anchor": "orbit", "altitude_km": 400.0, "phase_deg": 45.0, "aim": "side_limb", "lift_deg": 12.0,
			"fov": 60.0, "roll": 0.0},
	"orbit400_down": {"anchor": "orbit", "altitude_km": 400.0, "phase_deg": 35.0, "aim": "down", "fov": 60.0, "roll": 0.0},
	"orbit400_terminator": {"anchor": "orbit", "altitude_km": 400.0, "phase_deg": 90.0, "aim": "down", "fov": 60.0, "roll": 0.0},
	"orbit400_night": {"anchor": "orbit", "altitude_km": 400.0, "phase_deg": 150.0, "aim": "dark_limb", "lift_deg": 12.0,
			"fov": 60.0, "roll": 0.0},
	"alt1000_lit_limb": {"anchor": "orbit", "altitude_km": 1000.0, "phase_deg": 100.0, "aim": "lit_limb", "lift_deg": 20.0,
			"fov": 70.0, "roll": 0.0},
	"alt1000_down": {"anchor": "orbit", "altitude_km": 1000.0, "phase_deg": 70.0, "aim": "down", "fov": 70.0, "roll": 0.0},
	"alt10000": {"anchor": "orbit", "altitude_km": 10_000.0, "phase_deg": 60.0, "aim": "planet", "fov": 50.0, "roll": 0.0},
}

var options: Dictionary = {"shots": "references/screenshots/M6-T11 planet", "views": ",".join(PackedStringArray(VIEWS.keys())),
		"settle": "12", "measure": "60", "layer": "on", "flare": "on"}
var world: WorldFrame
var camera: Camera3D
var env: SpaceEnvironment
var system: StarSystem


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	world = WorldFrame.new()
	world.name = "World"
	add_child(world)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 50_000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(camera)
	camera.current = true
	env = (load(ENV_SCENE) as PackedScene).instantiate() as SpaceEnvironment
	add_child(env)
	env.scaled_space.epoch_offset_s = 0.0
	env.scaled_space.visible = options["layer"] != "off"
	system = StarSystem.load_system(&"local")
	Settings.set_value(&"lens_flare", options["flare"] != "off")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(String(options["shots"]))
	for view_name: String in String(options["views"]).split(",", false):
		if not VIEWS.has(view_name):
			print("[planet_sheet] unknown view %s" % view_name)
			continue
		_pose(VIEWS[view_name])
		for i: int in int(options["settle"]):
			await RenderingServer.frame_post_draw
			_aim(VIEWS[view_name])
		var gpu_ms: float = 0.0
		for i: int in int(options["measure"]):
			await RenderingServer.frame_post_draw
			gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		gpu_ms /= maxf(float(options["measure"]), 1.0)
		var path: String = String(options["shots"]).path_join(view_name + ".png")
		get_viewport().get_texture().get_image().save_png(path)
		var planet: ScaledPlacement = env.scaled_space.placement_of(PLANET)
		print("[planet_sheet] %s: planet %.2f deg across, sun %.1f deg from it, key light %.2f, flare %.2f, GPU %.3f ms, draw calls %d, VRAM %.1f MB -> %s" % [
				view_name, planet.angular_size_deg(), rad_to_deg(planet.direction.angle_to(env.scaled_space.sun_direction())),
				env.scaled_space.key_light(), env.post_effects.flare_strength(), gpu_ms,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, path])
	get_tree().quit()


# Puts the frame's anchor and the sim clock where the view wants them.
func _pose(view: Dictionary) -> void:
	var period: float = system.period_s(RAIL)
	var time_s: float = float(view.get("orbit", 0.0)) * period
	SimClock.reset(time_s)
	if view["anchor"] == "rail":
		world.anchor_on_rail(system, RAIL)
		return
	var to_sun_k: PackedFloat64Array = system.relative_state(STAR, PLANET, time_s)
	var to_sun: Vector3 = _game(to_sun_k).normalized()
	var across: Vector3 = to_sun.cross(Vector3.UP).normalized()
	var phase: float = deg_to_rad(float(view["phase_deg"]))
	var radius: float = float(system.info(PLANET)["radius_m"]) + float(view["altitude_km"]) * 1000.0
	var at: Vector3 = (to_sun * cos(phase) + across * sin(phase)) * radius
	var velocity: Vector3 = Vector3.UP.cross(at).normalized() * sqrt(float(system.info(PLANET)["gm"]) / radius)
	world.anchor_in_orbit(system, PLANET, PackedFloat64Array([at.x, at.y, at.z, velocity.x, velocity.y, velocity.z]))


# Turns the camera to what the view looks at, from where the layer places the planet now.
func _aim(view: Dictionary) -> void:
	camera.fov = float(view["fov"])
	env.scaled_space.refresh(camera)
	var planet: ScaledPlacement = env.scaled_space.placement_of(PLANET)
	if planet == null:
		return
	var down: Vector3 = planet.direction
	var sun: Vector3 = env.scaled_space.sun_direction()
	var sunward: Vector3 = (sun - down * sun.dot(down))
	sunward = sunward.normalized() if sunward.length() > 1.0e-4 else Vector3.UP.cross(down).normalized()
	var side: Vector3 = down.cross(sunward).normalized()
	var limb: float = planet.angular_radius_rad + deg_to_rad(float(view.get("lift_deg", 0.0)))
	var look: Vector3 = down
	match String(view["aim"]):
		"sun":
			var over: Vector3 = sun.cross(Vector3.UP).normalized()
			look = (sun * cos(deg_to_rad(float(view.get("lift_deg", 0.0)))) + over * sin(deg_to_rad(float(view.get("lift_deg", 0.0))))).normalized()
		"sun_planet":
			look = (down + sun).normalized()
		"lit_limb":
			look = down * cos(limb) + sunward * sin(limb)
		"dark_limb":
			look = down * cos(limb) - sunward * sin(limb)
		"side_limb":
			look = down * cos(limb) + side * sin(limb)
	# Limb views keep the sky up (away from the planet's centre across the picture); face-on views keep the sun up.
	var up: Vector3 = sunward
	if not ["planet", "down", "sun", "sun_planet"].has(String(view["aim"])):
		up = (-down - look * look.dot(-down)).normalized()
	if absf(up.dot(look)) > 0.999:
		up = side
	var basis := Basis.looking_at(look, up)
	camera.global_basis = basis * Basis(Vector3.BACK, deg_to_rad(float(view["roll"])))
	env.scaled_space.refresh(camera)


static func _game(kernel: PackedFloat64Array) -> Vector3:
	var g: PackedFloat64Array = ScaledPlacement.to_game(kernel)
	return Vector3(g[0], g[1], g[2])
