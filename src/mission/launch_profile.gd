class_name LaunchProfile
extends RefCounted
## How a Cobra-bay launch runs (M7-T08, D76), read from `data/launch/cobra_launch.json`: the steps' timings and the launch camera's
## shots, each played when the player's fighter has been in a step for a while. Data, so M8's squadron launch can bring its own.
##
## Steps of one fighter (`LaunchSequence`): `door` (stored on its rack while its door opens), `rotate` (the clamp turns it nose-out,
## then it waits for its drop), `hold` (waiting under the spine), `drop` (nose first down the rail), `release` (the hand-off).
##
## Starfuries launch front first (maintainer): stored at 90 degrees to the launch, the clamp turns them nose-out before the drop. Both
## poses are given in the door's frame (`LaunchSequence.door_frame`: x across the arm, y out of the drum, z aft).
##
## The camera comes in phases (rack, rotate, hold, drop, exit, chase), each a pool of shot variants that `LaunchCut` draws from; a
## phase plays at `at_s` into its step, and an optional one is left out with its `optional` chance.

const DEFAULT_PATH: String = "res://data/launch/cobra_launch.json"
const STEPS: Array[StringName] = [&"door", &"rotate", &"hold", &"drop", &"release"]
const MIN_SHOT_FLOOR_S: float = 1.0

## Seconds for a door's leaves to swing open, and how far they swing (degrees, outward).
var door_open_s: float = 2.0
var door_open_deg: float = 95.0
## Seconds to close, and how long after its last fighter left a door starts closing.
var door_close_s: float = 3.0
var door_close_after_s: float = 2.0
## Seconds from the rack to the release point: the ejection, from rest at a steady acceleration (maintainer: quick and punchy).
var drop_s: float = 0.75
## Seconds between one door firing and the next along the arm, a range each gap is drawn from per launch (seeded): a rippling
## launch, as the show's (maintainer). The smallest is also the least gap when held fighters go together after a hold.
var stagger_min_s: float = 0.25
var stagger_max_s: float = 0.5
## Seconds from the first wave's last release to the second wave's first drop (maintainer, Q3).
var wave_gap_s: float = 10.0
## Seconds for the second row to move from staging onto the racks.
var row_move_s: float = 6.0
## Seconds after its door starts opening that the clamp turns a fighter (so it turns while the leaves swing), and the turn's length.
var rotate_after_s: float = 0.8
var rotate_s: float = 1.4
## Seconds from a door fully open to its fighter's ejection (maintainer: the launch follows the doors briskly).
var eject_after_open_s: float = 0.3
## How much further out than the station's release point a nose-first fighter is let go, so its tail is clear of the arm, m.
var release_extra_m: float = 6.0
## The player's engines after the hand-off: seconds of main thrust and its throttle (0 to 1), as it clears the arm.
var burn_s: float = 3.0
var burn_throttle: float = 1.0
## The fighter's attitude stored on the rack and turned for the launch, in the door's frame: nose (`forward`) and top (`up`).
var stored_forward: Vector3 = Vector3(0.0, 0.0, -1.0)
var stored_up: Vector3 = Vector3(0.0, -1.0, 0.0)
var launch_forward: Vector3 = Vector3(0.0, 1.0, 0.0)
var launch_up: Vector3 = Vector3(0.0, 0.0, -1.0)
## No shot is cut before this long on screen, seconds (maintainer: at least 1 s; values under `MIN_SHOT_FLOOR_S` are refused).
var min_shot_s: float = 1.0
## A row shot (a variant with `row`) is held until this many fighters were let go during it, the wave has none left, or `row_max_s`.
var row_ejections: int = 3
var row_max_s: float = 4.0
## A launch with at least this many fighters in its first wave films the drop with a row shot and leaves the exit out.
var row_wave_min: int = 3
## The camera's phases, in order: each `{phase: String, step: StringName, at_s, optional (0 to 1: the chance it is left out),
## variants}`; each variant `{id: StringName, shot: CinematicShot, weight, fill, row: bool, subject: "fighter" or "row"}`: a row
## variant films the door row (subject `row`: the wave's doors in frame) and is held for several ejections. `fill` (empty for none) is a light lit for the
## shot's length: `actor`, `offset` (Vector3 in its frame), `energy`, `range_m`, `color`.
var phases: Array[Dictionary] = []


## The profile in `path`: `{ok: true, profile}` or `{ok: false, error}`.
static func load_file(path: String = DEFAULT_PATH) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "error": "%s: cannot read (%s)" % [path, error_string(FileAccess.get_open_error())]}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()]}
	return from_dict(json.data, path)


## A profile from its dictionary; every timing is optional (the defaults above).
static func from_dict(data: Variant, source: String = "launch profile") -> Dictionary:
	if not data is Dictionary:
		return {"ok": false, "error": "%s: the root must be an object" % source}
	var raw: Dictionary = data
	var made := LaunchProfile.new()
	for key: String in ["door_open_s", "door_open_deg", "door_close_s", "door_close_after_s", "drop_s", "stagger_min_s",
			"stagger_max_s", "wave_gap_s",
			"row_move_s", "rotate_after_s", "rotate_s", "eject_after_open_s", "release_extra_m", "burn_s", "burn_throttle"]:
		var v: Variant = raw.get(key, made.get(key))
		if not (v is float or v is int) or float(v) < 0.0:
			return {"ok": false, "error": "%s: %s must be a number, 0 or more" % [source, key]}
		made.set(key, float(v))
	if made.drop_s <= 0.0 or made.row_move_s <= 0.0:
		return {"ok": false, "error": "%s: drop_s and row_move_s must be more than 0" % source}
	for key: String in ["min_shot_s", "row_max_s"]:
		var v: Variant = raw.get(key, made.get(key))
		if not (v is float or v is int) or float(v) < MIN_SHOT_FLOOR_S:
			return {"ok": false, "error": "%s: %s must be %.1f s or more" % [source, key, MIN_SHOT_FLOOR_S]}
		made.set(key, float(v))
	for key: String in ["row_ejections", "row_wave_min"]:
		var n: Variant = raw.get(key, made.get(key))
		if not (n is int or n is float) or int(n) < 1:
			return {"ok": false, "error": "%s: %s must be 1 or more" % [source, key]}
		made.set(key, int(n))
	if made.stagger_max_s < made.stagger_min_s:
		return {"ok": false, "error": "%s: stagger_max_s must not be below stagger_min_s" % source}
	for pose: String in ["stored", "launch"]:
		var raw_pose: Variant = raw.get("%s_pose" % pose, {})
		if not raw_pose is Dictionary:
			return {"ok": false, "error": "%s: %s_pose must be {forward, up}" % [source, pose]}
		var f: Variant = _vec3((raw_pose as Dictionary).get("forward", made.get("%s_forward" % pose)))
		var u: Variant = _vec3((raw_pose as Dictionary).get("up", made.get("%s_up" % pose)))
		if f == null or u == null or (f as Vector3).is_zero_approx() or (u as Vector3).is_zero_approx() \
				or absf((f as Vector3).normalized().dot((u as Vector3).normalized())) > 1e-3:
			return {"ok": false, "error": "%s: %s_pose needs forward and up at right angles" % [source, pose]}
		made.set("%s_forward" % pose, (f as Vector3).normalized())
		made.set("%s_up" % pose, (u as Vector3).normalized())
	var list: Variant = raw.get("phases", [])
	if not list is Array:
		return {"ok": false, "error": "%s: phases must be an array" % source}
	for i: int in (list as Array).size():
		var phase: Variant = _phase((list as Array)[i], "%s: phases[%d]" % [source, i])
		if phase is String:
			return {"ok": false, "error": phase}
		# Every shot lasts its least hold (a row shot its longest), so the camera never drops back to the cockpit before the cut.
		for variant: Dictionary in (phase as Dictionary)["variants"]:
			_extend(variant["shot"], made.row_max_s if bool(variant["row"]) else made.min_shot_s)
		made.phases.append(phase)
	return {"ok": true, "profile": made}


## The rack's stored attitude in the door's frame (-z the nose, +y the top).
func stored_basis() -> Basis:
	return _basis(stored_forward, stored_up)


## The attitude the clamp turns the fighter to, nose out through the door.
func launch_basis() -> Basis:
	return _basis(launch_forward, launch_up)


## Seconds from a first-wave fighter's slot to its ejection: its door open plus `eject_after_open_s`, and the clamp's turn done.
func lead_s() -> float:
	return maxf(door_open_s + eject_after_open_s, rotate_after_s + rotate_s)


static func _basis(forward: Vector3, up: Vector3) -> Basis:
	var back: Vector3 = -forward.normalized()
	return Basis(up.cross(back).normalized(), up.normalized(), back).orthonormalized()


static func _vec3(v: Variant) -> Variant:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return null


# A shot's fill light, or why it is not one.
static func _fill(raw: Variant, where: String) -> Variant:
	if raw == null:
		return {}
	if not raw is Dictionary:
		return "%s must be an object" % where
	var d: Dictionary = raw
	var offset: Variant = d.get("offset", [0.0, 0.0, 0.0])
	if not (d.get("actor") is String) or not offset is Array or (offset as Array).size() != 3:
		return "%s needs an actor and an offset [x, y, z]" % where
	for key: String in ["energy", "range_m"]:
		if not (d.get(key) is float or d.get(key) is int) or float(d[key]) <= 0.0:
			return "%s.%s must be a number above 0" % [where, key]
	var o: Array = offset
	return {"actor": d["actor"], "offset": Vector3(float(o[0]), float(o[1]), float(o[2])), "energy": float(d["energy"]),
			"range_m": float(d["range_m"]), "color": Color.html(str(d.get("color", "#FFF2E0")))}


# Holds a shot's last key until `until_s` when it would end sooner.
static func _extend(shot: CinematicShot, until_s: float) -> void:
	if shot.duration_s >= until_s:
		return
	var last: CinematicShot.Frame = shot.keys[-1]
	var held := CinematicShot.Frame.new()
	held.t = until_s
	held.position = last.position
	held.look_at = last.look_at
	held.fov = last.fov
	held.roll = last.roll
	held.up_actor = last.up_actor
	held.up_direction = last.up_direction
	shot.keys.append(held)
	shot.duration_s = until_s


## The phase called `name`, or empty.
func phase(name: String) -> Dictionary:
	for entry: Dictionary in phases:
		if entry["phase"] == name:
			return entry
	return {}


# One phase and its pool, or why it is not one.
static func _phase(raw: Variant, where: String) -> Variant:
	if not raw is Dictionary:
		return "%s must be an object" % where
	var e: Dictionary = raw
	var step := StringName(str(e.get("step", "")))
	if not STEPS.has(step):
		return "%s.step must be one of %s" % [where, STEPS]
	var at: Variant = e.get("at_s", 0.0)
	var optional: Variant = e.get("optional", 0.0)
	if not (at is float or at is int) or float(at) < 0.0:
		return "%s.at_s must be seconds, 0 or more" % where
	if not (optional is float or optional is int) or float(optional) < 0.0 or float(optional) >= 1.0:
		return "%s.optional must be a chance from 0 to below 1" % where
	var raw_variants: Variant = e.get("variants")
	if not raw_variants is Array or (raw_variants as Array).is_empty():
		return "%s.variants must be a non-empty array" % where
	var variants: Array[Dictionary] = []
	for i: int in (raw_variants as Array).size():
		var v: Variant = (raw_variants as Array)[i]
		var vw: String = "%s.variants[%d]" % [where, i]
		if not v is Dictionary or not ((v as Dictionary).get("id") is String):
			return "%s needs an id" % vw
		var weight: Variant = (v as Dictionary).get("weight", 1.0)
		if not (weight is float or weight is int) or float(weight) <= 0.0:
			return "%s.weight must be above 0" % vw
		var shot: Dictionary = CinematicShot.from_dict(StringName((v as Dictionary)["id"]), v)
		if not bool(shot["ok"]):
			return "%s: %s" % [vw, shot["error"]]
		var fill: Variant = _fill((v as Dictionary).get("fill"), "%s.fill" % vw)
		if fill is String:
			return fill
		var row: bool = bool((v as Dictionary).get("row", false))
		var subject: String = str((v as Dictionary).get("subject", "row" if row else "fighter"))
		if subject != "fighter" and subject != "row":
			return "%s.subject must be fighter or row" % vw
		variants.append({"id": StringName((v as Dictionary)["id"]), "shot": shot["shot"], "weight": float(weight), "fill": fill,
				"row": row, "subject": subject})
	return {"phase": str(e.get("phase", step)), "step": step, "at_s": float(at), "optional": float(optional), "variants": variants}
