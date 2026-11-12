class_name BeltLayout
extends RefCounted
## A belt's rocks scattered through its box (M5-T29, D63): seeded and deterministic, every rock inside the box, no two closer
## than the gap, small rocks far more common than large ones. Pure: the belt node and the tests read `rocks`.

## Placement tries per rock asked for before the layout settles for what fitted.
const TRIES_PER_ROCK: int = 40
## How strongly sizes lean small: a radius is min * (max / min) ^ (u ^ SIZE_SKEW) for a uniform u.
const SIZE_SKEW: float = 3.0

## Each rock: {"offset": Vector3 from the belt's centre, "radius": float (its bounding radius), "shape": int, "basis": Basis}.
var rocks: Array[Dictionary] = []
## Rocks asked for that did not fit.
var shortfall: int = 0


## Lays out `belt` ({size: Vector3, count, radius_m: Vector2 (min, max), seed, min_gap_m}) over `shape_count` rock shapes.
static func place(belt: Dictionary, shape_count: int) -> BeltLayout:
	var layout := BeltLayout.new()
	var size: Vector3 = belt["size"]
	var count: int = int(belt["count"])
	var radii: Vector2 = belt["radius_m"]
	var gap: float = float(belt["min_gap_m"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(belt["seed"])
	var wanted: Array[float] = []
	for i: int in count:
		wanted.append(radii.x * pow(radii.y / radii.x, pow(rng.randf(), SIZE_SKEW)))
	wanted.sort()
	wanted.reverse()  # the big ones first, while there is room
	var cell: float = 2.0 * radii.y + gap
	var grid: Dictionary[Vector3i, Array] = {}
	var half: Vector3 = 0.5 * size
	var tries_left: int = TRIES_PER_ROCK * count
	for r: float in wanted:
		var room: Vector3 = half - Vector3.ONE * r
		if room.x < 0.0 or room.y < 0.0 or room.z < 0.0:
			continue
		var placed: bool = false
		while tries_left > 0 and not placed:
			tries_left -= 1
			var at := Vector3(rng.randf_range(-room.x, room.x), rng.randf_range(-room.y, room.y), rng.randf_range(-room.z, room.z))
			if _clear(grid, cell, at, r, gap, layout.rocks):
				var key := Vector3i((at / cell).floor())
				if not grid.has(key):
					grid[key] = []
				grid[key].append(layout.rocks.size())
				var turn := Quaternion(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
						.normalized(), rng.randf_range(-PI, PI))
				layout.rocks.append({"offset": at, "radius": r, "shape": rng.randi_range(0, shape_count - 1), "basis": Basis(turn)})
				placed = true
	layout.shortfall = count - layout.rocks.size()
	return layout


# Whether a rock of radius `r` at `at` keeps the gap to every rock already placed near it.
static func _clear(grid: Dictionary[Vector3i, Array], cell: float, at: Vector3, r: float, gap: float, rocks: Array[Dictionary]) -> bool:
	var key := Vector3i((at / cell).floor())
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			for dz: int in [-1, 0, 1]:
				for index: int in grid.get(key + Vector3i(dx, dy, dz), []):
					var other: Dictionary = rocks[index]
					if at.distance_to(other["offset"]) < r + float(other["radius"]) + gap:
						return false
	return true
