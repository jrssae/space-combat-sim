extends Node
## Renders every Cobra-bay launch shot for the show-likeness review (M8-T30): for each variant of the three launch pools (the
## player's launch, the exterior one, the squadron launch) a fresh scene launches with that variant forced into its phase
## (`LaunchDirector.force_variant`), so it plays at its own moment on a real launch, held to its end; four key frames are saved
## (`<id>_<n>.png`, at the start, a third, two thirds and the end of the shot, long holds capped), then a 2x2 contact sheet
## (`<id>_sheet.png`) and, at the end, `shots.md` listing each shot's pool, phase, move and files.
##
## Arguments after `--`: out=<dir> only=<id,id,...> (optional). Run by scripts/launch_shot_review.sh.

const SCENARIO: String = "res://tests/fixtures/flights/station_flight.json"
const POOLS: Array[Dictionary] = [
	{"name": "player", "path": LaunchProfile.DEFAULT_PATH, "start": "player"},
	{"name": "exterior", "path": LaunchDirector.EXTERIOR_PATH, "start": "exterior"},
	{"name": "squadron", "path": SquadronLaunch.DEFAULT_PATH, "start": "squadron"},
]
## Seconds a shot may take to come on screen before the variant is previewed instead (a hold shot needs the spine over the arm).
const WAIT_S: float = 45.0
## The longest stretch of a shot the frames are spread over, seconds (hold shots last a minute).
const SPAN_CAP_S: float = 6.0
const FRAMES: int = 4

var options: Dictionary = {"out": "", "only": ""}
var _jobs: Array[Dictionary] = []
var _rows: Array[String] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	var only: PackedStringArray = String(options["only"]).split(",", false)
	for pool: Dictionary in POOLS:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(pool["path"])))
		for phase: Dictionary in (data as Dictionary)["phases"]:
			for variant: Dictionary in phase["variants"]:
				if only.is_empty() or only.has(String(variant["id"])):
					_jobs.append({"pool": pool, "phase": phase["phase"], "step": phase["step"], "id": String(variant["id"]),
							"move": String(variant.get("move", "")) + (" **[feature, %.1f s]**" % float((variant["keys"] as Array)[-1]["t"])
									if bool(variant.get("feature", false)) else "")})
	DirAccess.make_dir_recursive_absolute(String(options["out"]))
	for job: Dictionary in _jobs:
		await _render(job)
	_write_index()
	print("[launch_shot_review] done: %d shots" % _jobs.size())
	get_tree().quit()


# One shot: a fresh scene, the launch with the variant forced, its four frames and its sheet.
func _render(job: Dictionary) -> void:
	var main: Main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = InputSource.new()  # no live pad or key may skip a shot mid-capture (the real input once did)
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	get_tree().root.add_child(main)
	for i: int in 30:
		await get_tree().physics_frame
	DebugConsole.registry.execute("set settings.show_overlay false")
	DebugConsole.registry.execute("set settings.show_fps false")
	var id: String = job["id"]
	var why: String = main.launches.force_variant(StringName(id))
	if why.is_empty():
		match String((job["pool"] as Dictionary)["start"]):
			"player":
				why = main.launches.launch_player("alpha", 3, true, false)
			"exterior":
				why = main.launches.launch_player("alpha", 3, false, true)
			"squadron":
				why = main.launches.launch_squadron("alpha")
	var files := PackedStringArray()
	if not why.is_empty():
		push_warning("launch_shot_review: %s: %s" % [id, why])
	else:
		files = await _capture(main, job)
	job["files"] = files
	_rows.append("| `%s` | %s / %s | %s | %s%s |" % [id, (job["pool"] as Dictionary)["name"], job["phase"], job["move"],
			", ".join(files) if not files.is_empty() else "not rendered",
			" (ended after frame %d)" % int(job["left"]) if job.has("left") else ""])
	main.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


# Waits for the shot (previewing it when its moment does not come), then saves the frames and the sheet.
func _capture(main: Main, job: Dictionary) -> PackedStringArray:
	var id: String = job["id"]
	var rig: CameraRig = main.camera_rig
	var waited: float = 0.0
	var previewed: bool = false
	while rig.playing_shot() == null or String(rig.playing_shot().id) != id:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		if not previewed and (waited > WAIT_S or (job["step"] == "hold" and waited > 2.0)):
			DebugConsole.registry.execute("launch preview %s" % id)
			previewed = true
		if waited > WAIT_S + 5.0:
			push_warning("launch_shot_review: %s never came on screen" % id)
			return PackedStringArray()
	var shot: CinematicShot = rig.playing_shot()
	var span: float = minf(shot.duration_s, SPAN_CAP_S) - 0.05
	var images: Array[Image] = []
	var files := PackedStringArray()
	for n: int in FRAMES:
		var at: float = span * float(n) / float(FRAMES - 1)
		while rig.playing_shot() == shot and rig.shot_time_s() < at:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		if rig.playing_shot() != shot:
			job["left"] = n  # the shot ended (its `until`, or something cut it): no frame of whatever follows
			push_warning("launch_shot_review: %s ended before frame %d" % [id, n + 1])
			break
		var image: Image = get_viewport().get_texture().get_image()
		var file: String = "%s_%d.png" % [id, n + 1]
		image.save_png("%s/%s" % [options["out"], file])  # only frames of the shot itself
		images.append(image)
		files.append(file)
	_sheet(images, id)
	files.append("%s_sheet.png" % id)
	print("[launch_shot_review] %s: %s" % [id, ", ".join(files)])
	return files


# The four frames in a 2x2 sheet at the frames' own size.
func _sheet(images: Array[Image], id: String) -> void:
	var w: int = images[0].get_width()
	var h: int = images[0].get_height()
	var sheet := Image.create(w, h, false, images[0].get_format())
	for i: int in images.size():
		var small: Image = images[i].duplicate() as Image
		small.resize(w / 2, h / 2, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(small, Rect2i(0, 0, w / 2, h / 2), Vector2i((i % 2) * (w / 2), (i / 2) * (h / 2)))
	sheet.save_png("%s/%s_sheet.png" % [options["out"], id])


func _write_index() -> void:
	var lines := PackedStringArray([
		"# M8-T30 Cobra-bay launch shots: review",
		"",
		"Each shot rendered on a real launch with the variant forced into its phase (960x540, forward_plus): four key frames",
		"(start, a third, two thirds, end; holds capped at %.0f s) and a 2x2 sheet. Pools: `player` = data/launch/cobra_launch.json" % SPAN_CAP_S,
		"(the player's launch, the tutorial's two-ship opening), `exterior` = data/launch/exterior_launch.json (the squadron's last",
		"launch, the relaunch after a repair), `squadron` = data/launch/squadron_launch.json (the squadron launch).",
		"",
		"| Shot | Pool / phase | Camera move | Files |",
		"|---|---|---|---|",
	])
	lines.append_array(_rows)
	var file: FileAccess = FileAccess.open("%s/shots.md" % options["out"], FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
