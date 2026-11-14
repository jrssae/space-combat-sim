class_name TourDirector
extends Node
## Plays the station's exterior tour in the game (M7-T12, the base of M8's tour): the node side of `TourBook`. It draws the tour's
## shots, plays them one after another on the cinematic camera (every shot runs to its end, never under `TourBook.min_shot_s`) and
## captions each stop in the lower letterbox bar. The shots are rebase-proof and ride the drum for the Cobra arm's stop, because
## their actors are placed from the station's pose every frame.
##
## A or Start (`Main`'s shot skip) ends the whole tour: any shot that stops before its time was cut, and the tour stops with it.
## The ship is out of the player's hands while a shot plays and flies on its own momentum. Console: command and provider `tour`.

## A shot has started: the stop's name and its caption.
signal point_started(point: String, caption: String)
## The tour is over: all its shots played (`completed`), or it was skipped or stopped.
signal tour_finished(completed: bool)

const NODE_NAME: StringName = &"TourDirector"
const PROVIDER: StringName = &"tour"
const CAPTION_LAYER: int = 42
## The letterbox bar's height as a share of the window (`Letterbox.BAR_FRACTION`) and the caption's size as a share of the window.
const CAPTION_SIZE_FRACTION: float = 0.026
## A shot that ended this close to its last key ran out by itself.
const END_EPS_S: float = 0.05

var main: Main = null
var book: TourBook = null
## The tour playing: each stop `{point, caption, variant, shot, duration_s}`, and the one on screen (-1 when none).
var stops: Array[Dictionary] = []
var index: int = -1
var playing: bool = false
## Tours started this run (seeds the draws with the scenario's seed), and a pin for the draws (-1 seeds each tour).
var tour_count: int = 0
var tour_seed: int = -1
## Every shot played so far: `{point, variant, start_s}` with the start in sim seconds (for the console and tests).
var played: Array[Dictionary] = []

var _clock_s: float = 0.0
var _turns: Dictionary = {}  # an arm stop's turn about the drum's axis, onto the arm the tour films
var _canvas: CanvasLayer = null
var _caption: Label = null


func _init() -> void:
	name = NODE_NAME
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	var made: Dictionary = TourBook.load_file()
	if bool(made["ok"]):
		book = made["book"]
	else:
		push_error("TourDirector: %s" % made["error"])
	_canvas = CanvasLayer.new()
	_canvas.layer = CAPTION_LAYER
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	_canvas.add_child(_caption)
	add_child(_canvas)
	if main != null and main.camera_rig != null:
		main.camera_rig.shot_finished.connect(_on_shot_finished)
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	_clock_s += delta


# The caption sits in the lower bar and follows the window's size.
func _process(_delta: float) -> void:
	if not playing or _caption == null:
		return
	var size_px: Vector2 = get_viewport().get_visible_rect().size
	var bar_px: float = size_px.y * Letterbox.BAR_FRACTION
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -bar_px
	_caption.add_theme_font_size_override("font_size", int(maxf(12.0, size_px.y * CAPTION_SIZE_FRACTION)))


## The station the tour is of, or null.
func station() -> Station:
	if main == null or main.far_props == null:
		return null
	var s: Station = main.far_props.station
	return s if s != null and is_instance_valid(s) and s.hardpoints != null and s.hardpoints.valid else null


## Starts the whole tour, or the one stop `only`. "" when it started, else why not.
func start(only: String = "") -> String:
	if book == null:
		return "the tour file did not load"
	var s: Station = station()
	if s == null:
		return "no station in play"
	if main == null or main.camera_rig == null or not main.player_alive:
		return "no player to film"
	if main.launches != null and main.launches.locks_controls():
		return "the launch is still running (launch skip)"
	var missing: PackedStringArray = book.missing_points(s.hardpoints)
	if not missing.is_empty():
		return "the station has no tour point %s" % ", ".join(missing)
	if not only.is_empty() and not book.points.has(only):
		return "no stop %s (%s)" % [only, ", ".join(book.order)]
	stop()
	tour_count += 1
	stops = book.plan(s.hardpoints, seed_value(), only, s.drum_angle, s.spin.rate_rad_s if s.spinning else 0.0)
	if stops.is_empty():
		return "the tour could not be planned"
	_turns.clear()
	for entry: Dictionary in stops:
		_turns[entry["point"]] = float(entry["turn_rad"])
	playing = true
	index = -1
	_play_next()
	return ""


## Ends the tour now and gives the camera back.
func stop() -> void:
	if not playing:
		return
	playing = false
	index = -1
	_caption.visible = false
	if main != null and main.camera_rig != null and main.camera_rig.playing_shot() != null:
		main.camera_rig.stop_shot()
	tour_finished.emit(false)


## The seed of the tour now starting: pinned, or from the scenario's seed and how many tours this run has had.
func seed_value() -> int:
	if tour_seed >= 0:
		return tour_seed
	return hash([main.scenario_seed if main != null else 0, tour_count])


func current() -> Dictionary:
	return stops[index] if playing and index >= 0 and index < stops.size() else {}


func describe() -> String:
	if not playing:
		return "no tour playing; stops: %s" % (", ".join(book.order) if book != null else "none")
	var c: Dictionary = current()
	return "%d of %d: %s (%s), %.1f s into a %.1f s shot" % [index + 1, stops.size(), c["point"], c["variant"],
			main.camera_rig.shot_time_s(), float(c["duration_s"])]


# Puts the next stop's shot on the camera, or ends the tour after the last.
func _play_next() -> void:
	index += 1
	if index >= stops.size():
		playing = false
		index = -1
		_caption.visible = false
		tour_finished.emit(true)
		return
	var entry: Dictionary = stops[index]
	played.append({"point": entry["point"], "variant": entry["variant"], "start_s": _clock_s})
	main.camera_rig.play_shot(entry["shot"], _actor_pose, _origin_to_local)
	_caption.text = entry["caption"]
	_caption.visible = true
	point_started.emit(entry["point"], entry["caption"])


# A shot of the tour that ran its whole length hands over to the next; one cut short (A or Start, a launch's shot) ends the tour.
func _on_shot_finished(shot_id: StringName) -> void:
	if not playing or index < 0:
		return
	var shot: CinematicShot = stops[index]["shot"]
	if shot.id != shot_id:
		return
	if main.camera_rig.shot_time_s() < shot.duration_s - END_EPS_S:
		playing = false
		index = -1
		_caption.visible = false
		tour_finished.emit(false)
		return
	_play_next()


func _actor_pose(actor: String) -> Variant:
	var s: Station = station()
	if s == null:
		return null
	var drum := Transform3D(Basis(Vector3.BACK, s.visual_angle(Engine.get_physics_interpolation_fraction())), s.drum_origin)
	return book.pose_of(actor, s.hardpoints, s.get_global_transform_interpolated(), drum, _turns)


func _origin_to_local(offset: PackedFloat64Array) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], main.world.origin.system_id))


# --- console ---------------------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"playing": {"get": func() -> bool: return playing, "type": TYPE_BOOL, "doc": "The exterior tour is playing (M7-T12)"},
		&"point": {"get": func() -> String: return String(current().get("point", "none")), "doc": "The stop on screen, or none"},
		&"variant": {"get": func() -> String: return String(current().get("variant", "none")), "doc": "The camera move of the stop on screen"},
		&"stop": {"get": func() -> int: return index + 1 if playing else 0, "type": TYPE_INT, "doc": "Which stop of the tour is on screen (1 on), 0 when none"},
		&"stops": {"get": func() -> int: return stops.size() if playing else 0, "type": TYPE_INT, "doc": "How many stops the tour playing has"},
		&"tours": {"get": func() -> int: return tour_count, "type": TYPE_INT, "doc": "Tours started this run (seeds the draws)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"The station's exterior tour (M7-T12): tour (every stop, in order), tour <stop> (one stop), tour stop, tour status, tour seed <n|off> (pin the draws); A or Start skips it",
			[ConsoleArg.string_optional(&"what"), ConsoleArg.string_optional(&"value")]), _cmd_tour, self)


func _cmd_tour(args: Dictionary) -> ConsoleResult:
	var what: String = str(args[&"what"]).to_lower() if args[&"what"] != null else ""
	match what:
		"stop":
			if not playing:
				return ConsoleResult.failure("tour stop: no tour is playing")
			stop()
			return ConsoleResult.line("tour stopped")
		"status":
			return ConsoleResult.line(describe())
		"seed":
			var value: String = str(args[&"value"]).to_lower() if args[&"value"] != null else ""
			if value == "off":
				tour_seed = -1
				return ConsoleResult.line("tour draws seeded per tour")
			if not value.is_valid_int() or int(value) < 0:
				return ConsoleResult.failure("tour seed <n|off>")
			tour_seed = int(value)
			return ConsoleResult.line("tour draws seeded with %d" % tour_seed)
	var why: String = start(what)
	if not why.is_empty():
		return ConsoleResult.failure("tour: %s" % why)
	return ConsoleResult.line("touring %s (%d stops, %.0f s)" % [what if not what.is_empty() else "the station", stops.size(), _total_s()])


func _total_s() -> float:
	var total: float = 0.0
	for entry: Dictionary in stops:
		total += float(entry["duration_s"])
	return total
