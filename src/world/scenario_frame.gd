class_name ScenarioFrame
extends RefCounted
## Where a scenario is in its star system and when (M6-T09, AC6, Q7, Q9): the `anchor` and `epoch` of a scenario file.
## Pure: `parse` checks the file's blocks, `resolve` turns them into what the World anchors on, with the star system's
## ephemeris for every position (GDScript computes no orbit).
##
## A scenario's coordinates are measured from its World's anchor (D64), in axes that do not turn. The anchor is one of:
## - `{"place": "babylon5", "at": [x, y, z]}`: on a place's rail. `at` is where the place stands in the scenario's
##   coordinates (default [0, 0, 0]), so a layout keeps its numbers and the station stands beside it. `standin` (default
##   true) puts the station's stand-in there.
## - `{"body": "epsilon_iii", "altitude_m": h, "phase_deg": 0, "inclination_deg": 0}`: a circular orbit that high above the
##   body, at that phase at the epoch.
## - `{"orbit": {"body": "epsilon_iii", "a_m": ..., "e", "i_deg", "node_deg", "peri_deg", "m0_deg", "epoch_s"}}`: any orbit,
##   the star system's own orbit keys; `epoch_s` defaults to the scenario's epoch.
## With no `anchor` the World rides the station's rail with the scenario's origin on it and no stand-in (the old scenes and
## the tests' own scenarios).
##
## `epoch` is the system time at the scenario's start, in seconds from the data's epoch (the planet's phase, day or night
## under the station), or "seeded": drawn from the run's seed among the times that start lit, with the planet ahead of the
## player's start for a place's rail. Absent, it is 0. The sim clock still starts at 0; the World adds the epoch.

const KIND_PLACE: StringName = &"place"
const KIND_BODY: StringName = &"body"
const KIND_ORBIT: StringName = &"orbit"
## The place the World rides when a scenario names none, and the only place with a stand-in so far.
const DEFAULT_PLACE: StringName = &"babylon5"
const SEEDED: String = "seeded"
## A seeded start has the planet's centre within this angle of the player's forward, so it is in view.
const VIEW_DEG: float = 25.0
## ...the key light at least this unshadowed...
const KEY_LIGHT_MIN: float = 0.999
## ...and at least this part of the planet's disc lit as seen from the start.
const PLANET_LIT_MIN: float = 0.5
## A seeded epoch tries this many days of the planet's year, each scanned over one turn of the place round its planet.
const SEED_TRIES: int = 24
const SCAN_STEPS: int = 360


## The `anchor` and `epoch` blocks as a frame spec, or an error string naming `source`.
static func parse(anchor_raw: Variant, epoch_raw: Variant, source: String) -> Variant:
	var spec: Dictionary = default_spec()
	if epoch_raw is String:
		if epoch_raw != SEEDED:
			return "%s: epoch must be a number of seconds or \"seeded\", got %s" % [source, JSON.stringify(epoch_raw)]
		spec["seeded"] = true
	elif _is_number(epoch_raw):
		spec["epoch_s"] = float(epoch_raw)
	elif epoch_raw != null:
		return "%s: epoch must be a number of seconds or \"seeded\", got %s" % [source, JSON.stringify(epoch_raw)]
	if anchor_raw == null:
		return spec
	if not (anchor_raw is Dictionary):
		return "%s: anchor must be an object with a place, a body or an orbit" % source
	var block: Dictionary = anchor_raw
	var forms: int = int(block.has("place")) + int(block.has("body")) + int(block.has("orbit"))
	if forms != 1:
		return "%s: anchor needs exactly one of place, body or orbit" % source
	spec["declared"] = true
	if block.has("place"):
		return _parse_place(block, spec, source)
	if block.has("body"):
		return _parse_body(block, spec, source)
	return _parse_orbit(block, spec, source)


## What a scenario with no `anchor` or `epoch` gets: the station's rail, the scenario's origin on it, epoch 0, no stand-in.
static func default_spec() -> Dictionary:
	return {"kind": KIND_PLACE, "id": DEFAULT_PLACE, "at": PackedFloat64Array([0.0, 0.0, 0.0]), "standin": false,
			"declared": false, "epoch_s": 0.0, "seeded": false, "orbit": {}}


## The spec against `system`: `{ok, error, kind, id (the place, or the body circled), offset (the scenario's origin from the
## place, game axes, m; zero for an orbit), state (an orbit's position and velocity against its body at the epoch, game
## axes, six numbers), epoch_s, standin}`. `start` (the player's start, three numbers) and `forward` serve a seeded epoch.
static func resolve(spec: Dictionary, system: StarSystem, seed_value: int, start: PackedFloat64Array,
		forward: Vector3) -> Dictionary:
	var out: Dictionary = {"ok": false, "error": "", "kind": spec["kind"], "id": spec["id"],
			"offset": PackedFloat64Array([0.0, 0.0, 0.0]), "state": PackedFloat64Array(), "epoch_s": float(spec["epoch_s"]),
			"standin": bool(spec["standin"])}
	if system == null or not system.is_valid():
		out["error"] = "no usable star system"
		return out
	var id: StringName = spec["id"]
	if spec["kind"] == KIND_PLACE:
		if not system.place_ids.has(id):
			out["error"] = "anchor.place %s is not a place of %s (%s)" % [id, system.id, ", ".join(PackedStringArray(system.place_ids))]
			return out
		var at: PackedFloat64Array = spec["at"]
		out["offset"] = PackedFloat64Array([-at[0], -at[1], -at[2]])
	elif not system.body_ids.has(id) or id == system.star_id():
		out["error"] = "anchor body %s is not a planet or moon of %s" % [id, system.id]
		return out
	if bool(spec["seeded"]):
		out["epoch_s"] = seeded_epoch(spec, system, seed_value, start, forward)
	if spec["kind"] != KIND_PLACE:
		var orbit: Dictionary = orbit_of(spec, system, out["epoch_s"])
		var made: Dictionary = system.orbit_state(id, orbit, out["epoch_s"])
		if not String(made["error"]).is_empty():
			out["error"] = "anchor: %s" % made["error"]
			return out
		out["state"] = _game6(made["state"])
	out["ok"] = true
	return out


## The orbit keys of a body or orbit spec at `epoch_s`: a circle at the altitude has its phase at the epoch.
static func orbit_of(spec: Dictionary, system: StarSystem, epoch_s: float) -> Dictionary:
	var orbit: Dictionary = (spec["orbit"] as Dictionary).duplicate()
	if spec["kind"] == KIND_BODY:
		var radius: float = float(system.info(spec["id"])["radius_m"])
		orbit = {"a_m": radius + float(orbit["altitude_m"]), "e": 0.0, "i_deg": float(orbit["inclination_deg"]),
				"node_deg": 0.0, "peri_deg": 0.0, "m0_deg": float(orbit["phase_deg"])}
	if not orbit.has("epoch_s"):
		orbit["epoch_s"] = epoch_s
	return orbit


## Where `place` is in the scenario's coordinates at `time_s` (three numbers, game axes, m), from a resolved frame; empty
## when the system cannot say. On an orbit the frame's start is used, which is all a scenario's placing needs.
static func place_in_scene(resolved: Dictionary, system: StarSystem, place: StringName, time_s: float) -> PackedFloat64Array:
	if system == null or not system.is_valid() or not system.has_id(place) or not bool(resolved.get("ok", false)):
		return PackedFloat64Array()
	var id: StringName = resolved["id"]
	var seen: PackedFloat64Array = system.relative_state(place, id, time_s)
	if seen.size() < 3:
		return PackedFloat64Array()
	var game: PackedFloat64Array = ScaledPlacement.to_game(seen)
	var from: PackedFloat64Array = resolved["offset"] if resolved["kind"] == KIND_PLACE else resolved["state"]
	return PackedFloat64Array([game[0] - from[0], game[1] - from[1], game[2] - from[2]])


## How the planet looks from a point (`eye`, three numbers, game axes, against `body`'s centre) at `time_s`: `{angle_deg`
## (between `forward` and the planet's centre), `key_light` (the star's disc left showing), `planet_lit` (the part of the
## planet's disc lit, as seen)}.
static func view_from(system: StarSystem, body: StringName, eye: PackedFloat64Array, time_s: float, forward: Vector3) -> Dictionary:
	var star: StringName = system.star_id()
	var sun: PackedFloat64Array = ScaledPlacement.to_game(system.relative_state(star, body, time_s))
	var to_planet := PackedFloat64Array([-eye[0], -eye[1], -eye[2]])
	var to_star := PackedFloat64Array([sun[0] - eye[0], sun[1] - eye[1], sun[2] - eye[2]])
	var key: float = EclipseMath.lit_fraction(to_star, float(system.info(star)["radius_m"]), to_planet,
			float(system.info(body)["radius_m"]))
	# The phase is the angle at the planet between the star and the eye.
	var phase: float = _angle(sun, eye)
	return {"angle_deg": rad_to_deg(_angle(to_planet, PackedFloat64Array([forward.x, forward.y, forward.z]))),
			"key_light": key, "planet_lit": (1.0 + cos(phase)) * 0.5}


## The player's start against the body of a resolved frame at `time_s` (three numbers, game axes); on an orbit, at the epoch.
static func eye_from_body(spec: Dictionary, system: StarSystem, start: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
	var from: PackedFloat64Array
	if spec["kind"] == KIND_PLACE:
		var body: StringName = system.body_of_place(spec["id"])
		var place: PackedFloat64Array = ScaledPlacement.to_game(system.relative_state(spec["id"], body, time_s))
		var at: PackedFloat64Array = spec["at"]
		from = PackedFloat64Array([place[0] - at[0], place[1] - at[1], place[2] - at[2]])
	else:
		var made: Dictionary = system.orbit_state(spec["id"], orbit_of(spec, system, time_s), time_s)
		if (made["state"] as PackedFloat64Array).size() < 3:
			return PackedFloat64Array()
		from = ScaledPlacement.to_game(made["state"])
	return PackedFloat64Array([from[0] + start[0], from[1] + start[1], from[2] + start[2]])


## The body whose planet a scenario looks at: the place's planet, or the body its orbit circles.
static func planet_of(spec: Dictionary, system: StarSystem) -> StringName:
	return system.body_of_place(spec["id"]) if spec["kind"] == KIND_PLACE else StringName(spec["id"])


## Whether the start looks good at `time_s`: lit, and on a place's rail the planet ahead and at least half lit.
static func good_start(spec: Dictionary, system: StarSystem, start: PackedFloat64Array, forward: Vector3, time_s: float) -> bool:
	var eye: PackedFloat64Array = eye_from_body(spec, system, start, time_s)
	if eye.size() < 3:
		return false
	var view: Dictionary = view_from(system, planet_of(spec, system), eye, time_s, forward)
	if float(view["key_light"]) < KEY_LIGHT_MIN:
		return false
	if spec["kind"] != KIND_PLACE:
		return true  # the planet fills the view below an orbit; only the light matters
	return float(view["angle_deg"]) <= VIEW_DEG and float(view["planet_lit"]) >= PLANET_LIT_MIN


## A start time drawn from `seed_value` among the good starts: a day of the planet's year from the seed, then, on a place's
## rail, the times of one turn of the place that look good, one of them from the seed. The same seed gives the same epoch.
static func seeded_epoch(spec: Dictionary, system: StarSystem, seed_value: int, start: PackedFloat64Array,
		forward: Vector3) -> float:
	var planet: StringName = planet_of(spec, system)
	var year: float = system.period_s(planet)
	var turn: float = system.period_s(spec["id"]) if spec["kind"] == KIND_PLACE else 0.0
	var first: float = -1.0
	for attempt: int in SEED_TRIES:
		var day: float = year * float(posmod(hash([seed_value, attempt, "epoch"]), 1_000_000)) / 1.0e6
		if first < 0.0:
			first = day
		if turn <= 0.0:
			if good_start(spec, system, start, forward, day):
				return day
			continue
		var good := PackedFloat64Array()
		for step: int in SCAN_STEPS:
			var t: float = day + turn * float(step) / float(SCAN_STEPS)
			if good_start(spec, system, start, forward, t):
				good.append(t)
		if not good.is_empty():
			return good[posmod(hash([seed_value, attempt, "pick"]), good.size())]
	push_warning("ScenarioFrame: no start in %d tries is lit with the planet in view; taking the seed's first day" % SEED_TRIES)
	return maxf(first, 0.0)


static func _parse_place(block: Dictionary, spec: Dictionary, source: String) -> Variant:
	var place: Variant = block["place"]
	if not (place is String) or (place as String).strip_edges().is_empty():
		return "%s: anchor.place must be a star-system place id" % source
	var at: Variant = _numbers3(block.get("at", [0.0, 0.0, 0.0]))
	if at == null:
		return "%s: anchor.at must be [x, y, z] (numbers): where the place stands in the scenario's coordinates" % source
	var standin: Variant = block.get("standin", true)
	if typeof(standin) != TYPE_BOOL:
		return "%s: anchor.standin must be true or false" % source
	spec["kind"] = KIND_PLACE
	spec["id"] = StringName((place as String).strip_edges())
	spec["at"] = at
	spec["standin"] = standin
	return spec


static func _parse_body(block: Dictionary, spec: Dictionary, source: String) -> Variant:
	var body: Variant = block["body"]
	if not (body is String) or (body as String).strip_edges().is_empty():
		return "%s: anchor.body must be a star-system body id" % source
	var altitude: Variant = block.get("altitude_m")
	if not _is_number(altitude) or float(altitude) <= 0.0:
		return "%s: anchor.altitude_m must be a number above 0 (metres above the surface)" % source
	var circle: Dictionary = {"altitude_m": float(altitude)}
	for key: String in ["phase_deg", "inclination_deg"]:
		var value: Variant = block.get(key, 0.0)
		if not _is_number(value):
			return "%s: anchor.%s must be a number (degrees)" % [source, key]
		circle[key] = float(value)
	spec["kind"] = KIND_BODY
	spec["id"] = StringName((body as String).strip_edges())
	spec["orbit"] = circle
	return spec


static func _parse_orbit(block: Dictionary, spec: Dictionary, source: String) -> Variant:
	var raw: Variant = block["orbit"]
	if not (raw is Dictionary):
		return "%s: anchor.orbit must be an object with a body and the orbit's keys" % source
	var orbit: Dictionary = (raw as Dictionary).duplicate()
	var body: Variant = orbit.get("body")
	if not (body is String) or (body as String).strip_edges().is_empty():
		return "%s: anchor.orbit.body must be a star-system body id" % source
	orbit.erase("body")
	for key: Variant in orbit:
		if not ["a_m", "e", "i_deg", "node_deg", "peri_deg", "m0_deg", "epoch_s"].has(str(key)):
			return "%s: anchor.orbit.%s is not an orbit key" % [source, key]
		if not _is_number(orbit[key]):
			return "%s: anchor.orbit.%s must be a number" % [source, key]
	if not orbit.has("a_m"):
		return "%s: anchor.orbit.a_m is missing (the orbit's size, m)" % source
	spec["kind"] = KIND_ORBIT
	spec["id"] = StringName((body as String).strip_edges())
	spec["orbit"] = orbit
	return spec


# Kernel axes to the game's for a position and a velocity.
static func _game6(kernel: PackedFloat64Array) -> PackedFloat64Array:
	if kernel.size() < 6:
		return PackedFloat64Array()
	var p: PackedFloat64Array = ScaledPlacement.to_game(kernel.slice(0, 3))
	var v: PackedFloat64Array = ScaledPlacement.to_game(kernel.slice(3, 6))
	return PackedFloat64Array([p[0], p[1], p[2], v[0], v[1], v[2]])


static func _angle(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var la: float = sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
	var lb: float = sqrt(b[0] * b[0] + b[1] * b[1] + b[2] * b[2])
	if la <= 0.0 or lb <= 0.0:
		return 0.0
	return acos(clampf((a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) / (la * lb), -1.0, 1.0))


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func _numbers3(value: Variant) -> Variant:
	if not (value is Array) or (value as Array).size() != 3:
		return null
	var out := PackedFloat64Array()
	for v: Variant in value as Array:
		if not _is_number(v) or is_nan(float(v)) or is_inf(float(v)):
			return null
		out.append(float(v))
	return out
