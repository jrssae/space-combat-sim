class_name MineFieldPlan
extends RefCounted
## Where a minefield's mines lie (M10-T15, Q20), from the data a scenario or a mission gives (one dictionary, the same shape in
## `scenario.minefields[]` and in `MissionApi.lay_minefield`). Pure and seeded: the same entry gives the same field, in any
## order of play.
##
## An entry (offsets are metres from the field's anchor; `faction` is the side that laid it, the one its mines never hurt):
## ```
## {"id": "gate_screen", "faction": "narn", "kind": "mine_prox", "pattern": "box",
##  "centre": [0, 0, -4000], "size": [2000, 600, 2000], "count": 120, "seed": 7, "min_gap_m": 80}
## ```
## `pattern` is one of:
## - `box` (`size` full extents) or `sphere` (`radius_m`): mines at random in the volume.
## - `shell` (`radius_m`, `thickness_m`): on a sphere's skin, as a screen round a station or a capital.
## - `ring` (`radius_m`, `width_m`, `thickness_m`, `axis`): in a flat ring, as round a jump point or a planet.
## - `line` (`from`, `to`): evenly spaced along it, a chain across a lane (`count` of them).
## - `points`: `points` lists every mine's offset; `count` is ignored.
## `kind` defaults to `mine_prox`. `min_gap_m` keeps random mines apart (a mine that finds no room in 40 draws is dropped and
## counted in `shortfall`).

const PATTERNS: Array[String] = ["box", "sphere", "shell", "ring", "line", "points"]
const DEFAULT_KIND: StringName = &"mine_prox"
const MAX_MINES: int = 5000
const DRAWS: int = 40
## The cell of the grid that keeps mines apart, m.
const GAP_CELL_M: float = 250.0

## The mines, each `{"offset": Vector3, "faction": StringName, "kind": StringName}`.
var rows: Array[Dictionary] = []
## Mines asked for that found no room.
var shortfall: int = 0


## The empty string when `entry` is a field this class can lay, else what is wrong with it.
static func problem(entry: Dictionary) -> String:
	var pattern: String = str(entry.get("pattern", "box"))
	if not PATTERNS.has(pattern):
		return "pattern must be one of %s" % [PATTERNS]
	if not MineKinds.is_kind(StringName(str(entry.get("kind", DEFAULT_KIND)))):
		return "kind must be one of %s" % [MineKinds.NAMES]
	if str(entry.get("faction", "")).is_empty():
		return "faction is needed (the side whose mines these are)"
	if _vec(entry.get("centre", [0, 0, 0])) == null:
		return "centre must be [x, y, z]"
	if pattern == "points":
		var list: Variant = entry.get("points")
		if not (list is Array) or (list as Array).is_empty():
			return "points must list at least one [x, y, z]"
		for p: Variant in list:
			if _vec(p) == null:
				return "every point must be [x, y, z]"
		return "" if (list as Array).size() <= MAX_MINES else "at most %d mines" % MAX_MINES
	var count: Variant = entry.get("count")
	if not (count is float or count is int) or int(count) < 1 or int(count) > MAX_MINES:
		return "count must be a whole number from 1 to %d" % MAX_MINES
	match pattern:
		"box":
			var size: Variant = _vec(entry.get("size"))
			if size == null or (size as Vector3).x <= 0.0 or (size as Vector3).y <= 0.0 or (size as Vector3).z <= 0.0:
				return "box needs size [x, y, z], each above 0"
		"sphere", "shell", "ring":
			if not (float(entry.get("radius_m", 0.0)) > 0.0):
				return "%s needs radius_m above 0" % pattern
		"line":
			if _vec(entry.get("from")) == null or _vec(entry.get("to")) == null:
				return "line needs from and to, each [x, y, z]"
	return ""


## The mines of `entry`; an entry with a `problem` lays none (and says so with a warning).
static func place(entry: Dictionary) -> MineFieldPlan:
	var plan := MineFieldPlan.new()
	var wrong: String = problem(entry)
	if not wrong.is_empty():
		push_warning("MineFieldPlan: %s: %s" % [entry.get("id", "?"), wrong])
		return plan
	var faction := StringName(str(entry["faction"]))
	var kind := StringName(str(entry.get("kind", DEFAULT_KIND)))
	var centre: Vector3 = _vec(entry.get("centre", [0, 0, 0]))
	var pattern: String = str(entry.get("pattern", "box"))
	if pattern == "points":
		for p: Variant in entry["points"]:
			plan._add(centre + (_vec(p) as Vector3), faction, kind)
		return plan
	var count: int = int(entry["count"])
	if pattern == "line":
		var a: Vector3 = _vec(entry["from"])
		var b: Vector3 = _vec(entry["to"])
		for k: int in count:
			plan._add(centre + a.lerp(b, 0.5 if count == 1 else float(k) / float(count - 1)), faction, kind)
		return plan
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([str(entry.get("id", "")), int(entry.get("seed", 1)), pattern])
	var gap: float = maxf(float(entry.get("min_gap_m", 0.0)), 0.0)
	var grid: Dictionary = {}
	for k: int in count:
		var placed: bool = false
		for draw: int in DRAWS:
			var at: Vector3 = centre + _draw(rng, pattern, entry)
			if gap > 0.0 and _crowded(grid, at, gap):
				continue
			plan._add(at, faction, kind)
			if gap > 0.0:
				_remember(grid, at)
			placed = true
			break
		if not placed:
			plan.shortfall += 1
	return plan


func _add(at: Vector3, faction: StringName, kind: StringName) -> void:
	rows.append({"offset": at, "faction": faction, "kind": kind})


# One random offset from the centre for `pattern`.
static func _draw(rng: RandomNumberGenerator, pattern: String, entry: Dictionary) -> Vector3:
	match pattern:
		"box":
			var size: Vector3 = _vec(entry["size"])
			return Vector3((rng.randf() - 0.5) * size.x, (rng.randf() - 0.5) * size.y, (rng.randf() - 0.5) * size.z)
		"sphere":
			return _unit(rng) * float(entry["radius_m"]) * pow(rng.randf(), 1.0 / 3.0)
		"shell":
			var thick: float = float(entry.get("thickness_m", 0.0))
			return _unit(rng) * (float(entry["radius_m"]) + (rng.randf() - 0.5) * thick)
		_:  # ring
			var raw_axis: Variant = _vec(entry.get("axis", [0, 1, 0]))
			var axis: Vector3 = (raw_axis as Vector3).normalized() if raw_axis != null and (raw_axis as Vector3).length_squared() > 1e-9 else Vector3.UP
			var side: Vector3 = axis.cross(Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
			var round_: Vector3 = axis.cross(side)
			var angle: float = rng.randf() * TAU
			var width: float = float(entry.get("width_m", 0.0))
			var radius: float = float(entry["radius_m"]) + (rng.randf() - 0.5) * width
			var up: float = (rng.randf() - 0.5) * float(entry.get("thickness_m", 0.0))
			return (side * cos(angle) + round_ * sin(angle)) * radius + axis * up


static func _unit(rng: RandomNumberGenerator) -> Vector3:
	var v := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
	return v.normalized() if v.length_squared() > 1e-9 else Vector3.UP


static func _cell(at: Vector3) -> Vector3i:
	return Vector3i(floori(at.x / GAP_CELL_M), floori(at.y / GAP_CELL_M), floori(at.z / GAP_CELL_M))


# Whether a mine already placed lies closer than `gap` to `at` (its own cell and the next ones are looked in).
static func _crowded(grid: Dictionary, at: Vector3, gap: float) -> bool:
	var home: Vector3i = _cell(at)
	var reach: int = ceili(gap / GAP_CELL_M)
	for x: int in range(home.x - reach, home.x + reach + 1):
		for y: int in range(home.y - reach, home.y + reach + 1):
			for z: int in range(home.z - reach, home.z + reach + 1):
				for other: Vector3 in grid.get(Vector3i(x, y, z), []):
					if other.distance_squared_to(at) < gap * gap:
						return true
	return false


static func _remember(grid: Dictionary, at: Vector3) -> void:
	var key: Vector3i = _cell(at)
	if not grid.has(key):
		grid[key] = [] as Array[Vector3]
	(grid[key] as Array).append(at)


static func _vec(raw: Variant) -> Variant:
	if raw is Array and (raw as Array).size() == 3:
		for c: Variant in raw:
			if not (c is float or c is int):
				return null
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return null
