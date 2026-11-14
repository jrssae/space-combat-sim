class_name TourBook
extends RefCounted
## The station's exterior tour as data (M7-T12, the base of M8's tour): `data/tour/station_tour.json` names the stops in order and
## gives a small pool of camera moves (templates). Each stop is one of the station's tour hardpoints (`StationHardpoints.tour_points`:
## where the camera stands, what it looks at), or a view of the stop's own; a template's keys are offsets from those two places, in fractions of the distance
## between them, so one move frames a close stop and a far one alike. Per stop the book draws one move from a seeded shuffle bag, so
## a tour differs from run to run and no move comes back before its pool has played.
##
## Pure. The shots name their actors `<stop>.stop` (the camera's stand: x right, y up, looking at the subject) and `<stop>.subject`
## (the look-at point, same axes); `pose_of` places both from the station's pose, so a shot rides the drum for a drum stop and
## survives a rebase like every `CinematicShot`.

const DEFAULT_PATH: String = "res://data/tour/station_tour.json"
## No shot may be shorter (maintainer: at least 1 s per camera angle).
const MIN_SHOT_FLOOR_S: float = 1.0
## How far (degrees) an arm filmed on the drum keeps from the blocked sectors, and how often its sweep is checked.
const ARM_VIEW_MARGIN_DEG: float = 20.0
const ARM_CHECK_STEP_S: float = 0.5

var valid: bool = false
var error: String = ""
var min_shot_s: float = MIN_SHOT_FLOOR_S
## The stops in tour order.
var order: PackedStringArray = PackedStringArray()
## Per stop: `{caption (with `{wing}` for an arm's wing), scale: float, stand: Vector3 (metres the camera's base moves from where it
## stands, in the stop's frame: -z toward the subject), aim: Vector3 (metres, in the subject's frame), templates: PackedStringArray,
## hardpoint: String ("" for none), body, camera, subject (Vector3 in the body's frame, or null), shows: PackedStringArray (grid
## mounts the shot points out), arm: bool (a stop on a Cobra arm, filmed on the best placed arm)}`.
var points: Dictionary = {}
## Per template id: its keys as written (`t`, `at`, `aim`, `fov`).
var templates: Dictionary = {}

# Per stop: the template ids still in the bag, and the one played last.
var _bags: Dictionary = {}
var _last: Dictionary = {}


## The tour in `path`: `{ok: true, book}` or `{ok: false, error}`.
static func load_file(path: String = DEFAULT_PATH) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "error": "%s: cannot read (%s)" % [path, error_string(FileAccess.get_open_error())]}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()]}
	return from_dict(json.data, path)


static func from_dict(data: Variant, source: String = "tour") -> Dictionary:
	if not data is Dictionary:
		return {"ok": false, "error": "%s: the root must be an object" % source}
	var book := TourBook.new()
	var why: String = book._parse(data as Dictionary)
	if not why.is_empty():
		return {"ok": false, "error": "%s: %s" % [source, why]}
	book.valid = true
	return {"ok": true, "book": book}


## The stops the station cannot place (empty when the tour is whole): a stop whose tour hardpoint is missing, or "stop:mount" for a
## grid mount it shows that is missing.
func missing_points(hardpoints: StationHardpoints) -> PackedStringArray:
	var out := PackedStringArray()
	for point_name: String in order:
		if resolve(point_name, hardpoints).is_empty():
			out.append(point_name)
			continue
		for mount_name: String in points[point_name]["shows"]:
			if hardpoints.mount(mount_name).is_empty():
				out.append("%s:%s" % [point_name, mount_name])
	return out


## Where a stop's camera stands and what it looks at, as a tour hardpoint reads (`name`, `body`, `position`, `look_at`, `direction`),
## or {} when it cannot be placed. The stop's own `camera` and `subject` take the place of its hardpoint's `position` and `look_at`
## (the tour frames what it points out, while the hardpoint stays the station's default view); a stop with no hardpoint (the
## defence grid along the spine) brings both and its `body`.
func resolve(point_name: String, hardpoints: StationHardpoints) -> Dictionary:
	if not points.has(point_name):
		return {}
	var entry: Dictionary = points[point_name]
	var base: Dictionary = {}
	if not String(entry["hardpoint"]).is_empty():
		base = hardpoints.tour(entry["hardpoint"])
		if base.is_empty():
			return {}
	var body: String = String(base.get("body", entry["body"]))
	var camera: Variant = entry["camera"] if entry["camera"] != null else base.get("position")
	var subject: Variant = entry["subject"] if entry["subject"] != null else base.get("look_at")
	if body.is_empty() or camera == null or subject == null:
		return {}
	var direction: Vector3 = ((subject as Vector3) - (camera as Vector3)).normalized()
	return {"name": point_name, "body": body, "position": camera, "look_at": subject, "direction": direction}


## The tour for `seed_value`: per stop (all, in order, or only `only`) `{point, caption, variant, shot, duration_s, turn_rad, wing}`.
## A stop on a Cobra arm (`arm`) is put on the arm best placed to be filmed: `drum_angle_rad` is the drum's angle now and
## `spin_rad_s` its turn, so each arm's sweep over its stop's shot (which starts when the stops before it have played) is known;
## `turn_rad` turns the stop about the drum's axis onto that arm and `wing` names it ("" for other stops). Empty when a stop cannot be
## placed or `only` is not a stop.
func plan(hardpoints: StationHardpoints, seed_value: int, only: String = "", drum_angle_rad: float = 0.0,
		spin_rad_s: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not missing_points(hardpoints).is_empty() or (not only.is_empty() and not points.has(only)):
		return out
	var start_s: float = 0.0
	for point_name: String in order:
		if not only.is_empty() and point_name != only:
			continue
		var variant: String = _draw(seed_value, point_name)
		var tour_point: Dictionary = resolve(point_name, hardpoints)
		var made: Dictionary = shot_for(point_name, variant, tour_point)
		if not bool(made["ok"]):
			push_error("TourBook: %s" % made["error"])
			return [] as Array[Dictionary]
		var shot: CinematicShot = made["shot"]
		var arm: Dictionary = {"turn_rad": 0.0, "wing": ""}
		if bool(points[point_name]["arm"]):
			arm = arm_turn(hardpoints, tour_point, drum_angle_rad, spin_rad_s, start_s, shot.duration_s, seed_value)
		out.append({"point": point_name, "caption": String(points[point_name]["caption"]).replace("{wing}", String(arm["wing"]).to_upper()),
				"variant": variant, "shot": shot, "duration_s": shot.duration_s, "turn_rad": arm["turn_rad"], "wing": arm["wing"]})
		start_s += shot.duration_s
	return out


## The arm to film for a drum stop (`tour_point`, as `resolve` gives it): the arms are on the drum 90 degrees apart, and a stop on
## one arm shows the same view on any other once turned about the drum's axis. Arms whose whole sweep over the shot, from
## `start_s` after now, keeps `ARM_VIEW_MARGIN_DEG` clear of the launch-blocked sectors (the frame's spine and forks over the
## drum) are fit; one of them is drawn from the seed, so a tour shows different wings. `{turn_rad, wing}`.
func arm_turn(hardpoints: StationHardpoints, tour_point: Dictionary, drum_angle_rad: float, spin_rad_s: float, start_s: float,
		duration_s: float, seed_value: int) -> Dictionary:
	var arms: Array = hardpoints.cobra_arm.get("arms", [])
	if arms.is_empty():
		return {"turn_rad": 0.0, "wing": ""}
	var at: Vector3 = tour_point["position"]
	var stop_deg: float = rad_to_deg(atan2(at.y, at.x))
	var home: Dictionary = arms[0]
	for arm: Dictionary in arms:
		if absf(angle_difference(deg_to_rad(float(arm["angle_deg"])), deg_to_rad(stop_deg))) \
				< absf(angle_difference(deg_to_rad(float(home["angle_deg"])), deg_to_rad(stop_deg))):
			home = arm
	var fit: Array[Dictionary] = []
	for arm: Dictionary in arms:
		if _arm_clear(hardpoints, float(arm["angle_deg"]), drum_angle_rad, spin_rad_s, start_s, duration_s):
			fit.append(arm)
	var pick: Dictionary = home
	if not fit.is_empty():
		pick = fit[int(LaunchCut.unit(seed_value, str(tour_point["name"]) + " arm", 0) * float(fit.size())) % fit.size()]
	return {"turn_rad": deg_to_rad(float(pick["angle_deg"]) - float(home["angle_deg"])), "wing": String(pick["wing"])}


# Whether an arm at `angle_deg` (before the drum turns) stays out of the blocked sectors, with a margin, for the whole shot.
func _arm_clear(hardpoints: StationHardpoints, angle_deg: float, drum_angle_rad: float, spin_rad_s: float, start_s: float,
		duration_s: float) -> bool:
	var t: float = 0.0
	while t <= duration_s + 0.001:
		var a: float = angle_deg + rad_to_deg(drum_angle_rad + spin_rad_s * (start_s + t))
		for margin: float in [-ARM_VIEW_MARGIN_DEG, 0.0, ARM_VIEW_MARGIN_DEG]:
			if hardpoints.launch_blocked(a + margin):
				return false
		t += ARM_CHECK_STEP_S
	return true


## One stop's shot with template `variant`: `{ok: true, shot}` or `{ok: false, error}`. `tour_point` is the resolved stop (`position`,
## `look_at`); the offsets scale with the distance between the two.
func shot_for(point_name: String, variant: String, tour_point: Dictionary) -> Dictionary:
	if not points.has(point_name) or not templates.has(variant) or tour_point.is_empty():
		return {"ok": false, "error": "tour %s / %s: unknown stop or move" % [point_name, variant]}
	var stand: Vector3 = points[point_name]["stand"]
	var aim: Vector3 = points[point_name]["aim"]
	var reach: float = ((tour_point["look_at"] as Vector3) - (tour_point["position"] as Vector3)).length() \
			* float(points[point_name]["scale"])
	var keys: Array = []
	for raw: Dictionary in templates[variant]["keys"] as Array:
		var at: Array = raw["at"]
		var look: Array = raw["aim"]
		keys.append({
			"t": float(raw["t"]),
			"position": {"actor": stop_actor(point_name), "offset": [stand.x + float(at[0]) * reach, stand.y + float(at[1]) * reach, stand.z + float(at[2]) * reach]},
			"look_at": {"actor": subject_actor(point_name),
					"offset": [aim.x + float(look[0]) * reach, aim.y + float(look[1]) * reach, aim.z + float(look[2]) * reach]},
			"up": {"actor": stop_actor(point_name), "direction": [0.0, 1.0, 0.0]},
			"fov": float(raw["fov"])})
	return CinematicShot.from_dict(StringName("tour_%s_%s" % [point_name, variant]), {"keys": keys})


static func stop_actor(point_name: String) -> String:
	return point_name + ".stop"


static func subject_actor(point_name: String) -> String:
	return point_name + ".subject"


## An actor's World-local pose: `<stop>.stop` or `<stop>.subject`, else null. `station_xf` is the station node's pose and `drum_xf` the
## drum's pose in it (the turn about its axis, at the pivot), both as drawn this frame; `turns` is each arm stop's turn about the
## drum's axis (`plan`'s `turn_rad`, by stop name).
func pose_of(actor: String, hardpoints: StationHardpoints, station_xf: Transform3D, drum_xf: Transform3D, turns: Dictionary = {}) -> Variant:
	var dot: int = actor.rfind(".")
	if dot < 0:
		return null
	var point_name: String = actor.substr(0, dot)
	var tour_point: Dictionary = resolve(point_name, hardpoints)
	var role: String = actor.substr(dot + 1)
	if tour_point.is_empty() or (role != "stop" and role != "subject"):
		return null
	var body_xf: Transform3D = station_xf
	if String(tour_point["body"]) == StationHardpoints.DRUM:
		body_xf = station_xf * drum_xf * Transform3D(Basis(Vector3.BACK, float(turns.get(point_name, 0.0))), Vector3.ZERO)
	var basis: Basis = Basis.looking_at(tour_point["direction"] as Vector3, Vector3.UP)
	return body_xf * Transform3D(basis, tour_point["position"] if role == "stop" else tour_point["look_at"])


## Where grid mount `mount_name` stands in the World when the stop is filmed (a drum mount follows the drum and the arm turn the stop
## was given), for checking that a shot shows what it points out. Null when the station has no such mount.
func mount_point(point_name: String, mount_name: String, hardpoints: StationHardpoints, station_xf: Transform3D, drum_xf: Transform3D,
		turns: Dictionary = {}) -> Variant:
	var mount: Dictionary = hardpoints.mount(mount_name)
	if mount.is_empty():
		return null
	if String(mount["body"]) == StationHardpoints.DRUM:
		var turn := Transform3D(Basis(Vector3.BACK, float(turns.get(point_name, 0.0))), Vector3.ZERO)
		return station_xf * drum_xf * turn * (mount["position"] as Vector3)
	return station_xf * (mount["position"] as Vector3)


# Takes the stop's next move out of its bag (refilled when empty, never the one played last), weighted equally.
func _draw(seed_value: int, point_name: String) -> String:
	var pool: PackedStringArray = points[point_name]["templates"]
	var bag: Array = _bags.get(point_name, [])
	var last: String = String(_last.get(point_name, ""))
	if bag.is_empty():
		bag = Array(pool)
	var choices: Array = bag.filter(func(id: String) -> bool: return id != last)
	if choices.is_empty():
		choices = bag
	var drawn: int = bag.size()
	var chosen: String = choices[int(LaunchCut.unit(seed_value, point_name, drawn) * float(choices.size())) % choices.size()]
	bag.erase(chosen)
	_bags[point_name] = bag
	_last[point_name] = chosen
	return chosen


func _parse(data: Dictionary) -> String:
	min_shot_s = float(data.get("min_shot_s", MIN_SHOT_FLOOR_S))
	if min_shot_s < MIN_SHOT_FLOOR_S:
		return "min_shot_s must be %.0f s or more" % MIN_SHOT_FLOOR_S
	var raw_templates: Variant = data.get("templates")
	if not raw_templates is Dictionary or (raw_templates as Dictionary).is_empty():
		return "templates must be an object of moves"
	for id: String in (raw_templates as Dictionary).keys():
		var why: String = _parse_template(id, (raw_templates as Dictionary)[id])
		if not why.is_empty():
			return why
	var raw_order: Variant = data.get("order")
	if not raw_order is Array or (raw_order as Array).is_empty():
		return "order must list the stops"
	for stop: Variant in raw_order as Array:
		if not stop is String or order.has(stop as String):
			return "order: %s is not a stop name or is listed twice" % JSON.stringify(stop)
		order.append(stop as String)
	var raw_points: Variant = data.get("points")
	if not raw_points is Dictionary:
		return "points must be an object"
	for stop_name: String in order:
		var entry: Variant = (raw_points as Dictionary).get(stop_name)
		if not entry is Dictionary:
			return "points.%s is missing" % stop_name
		var why: String = _parse_point(stop_name, entry as Dictionary)
		if not why.is_empty():
			return why
	return ""


func _parse_template(id: String, raw: Variant) -> String:
	var keys: Variant = (raw as Dictionary).get("keys") if raw is Dictionary else null
	if not keys is Array or (keys as Array).is_empty():
		return "templates.%s.keys must be a list" % id
	var last_t: float = -INF
	var out: Array = []
	for key: Variant in keys as Array:
		if not key is Dictionary:
			return "templates.%s: a key is not an object" % id
		var entry: Dictionary = key
		for field: String in ["t", "fov"]:
			if not _is_number(entry.get(field)):
				return "templates.%s: key %s must be a number" % [id, field]
		for field: String in ["at", "aim"]:
			var triple: Variant = entry.get(field)
			if not triple is Array or (triple as Array).size() != 3 or not (triple as Array).all(_is_number):
				return "templates.%s: key %s must be [x, y, z]" % [id, field]
		if float(entry["t"]) <= last_t:
			return "templates.%s: key times must increase" % id
		last_t = float(entry["t"])
		out.append(entry)
	if float((out[-1] as Dictionary)["t"]) < min_shot_s:
		return "templates.%s lasts %.1f s, under the %.1f s least hold" % [id, float((out[-1] as Dictionary)["t"]), min_shot_s]
	templates[id] = {"keys": out}
	return ""


func _parse_point(stop_name: String, entry: Dictionary) -> String:
	var vectors: Dictionary = {"aim": Vector3.ZERO, "stand": Vector3.ZERO, "camera": null, "subject": null}
	for field: String in vectors.keys():
		if entry.has(field):
			var raw: Variant = entry[field]
			if not raw is Array or (raw as Array).size() != 3 or not (raw as Array).all(_is_number):
				return "points.%s.%s must be [x, y, z] metres" % [stop_name, field]
			vectors[field] = Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	var scale: float = float(entry.get("scale", 1.0))
	if scale <= 0.0:
		return "points.%s.scale must be above 0" % stop_name
	var pool := PackedStringArray()
	for id: Variant in entry.get("templates", templates.keys()) as Array:
		if not templates.has(str(id)):
			return "points.%s uses the unknown move %s" % [stop_name, str(id)]
		pool.append(str(id))
	if pool.is_empty():
		return "points.%s has no moves" % stop_name
	var hardpoint: String = str(entry.get("hardpoint", stop_name))
	var body: String = str(entry.get("body", ""))
	if hardpoint.is_empty() and (vectors["camera"] == null or vectors["subject"] == null or body.is_empty()):
		return "points.%s has no hardpoint, so it needs camera, subject and body" % stop_name
	if not body.is_empty() and body != StationHardpoints.DRUM and body != StationHardpoints.FRAME:
		return "points.%s.body must be drum or frame" % stop_name
	var shows := PackedStringArray()
	for mount_name: Variant in entry.get("shows", []) as Array:
		shows.append(str(mount_name))
	points[stop_name] = {"caption": str(entry.get("caption", stop_name)), "scale": scale, "stand": vectors["stand"],
			"aim": vectors["aim"], "templates": pool, "hardpoint": hardpoint, "body": body, "camera": vectors["camera"],
			"subject": vectors["subject"], "shows": shows, "arm": bool(entry.get("arm", false))}
	return ""


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
