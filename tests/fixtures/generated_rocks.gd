class_name GeneratedRocks
extends RefCounted
## The game's generated rocks for the tests (M7-T48): rock entries for `AsteroidBelt.build_rocks` and
## `StandinDirector.add_asteroids`, so no test flies among sphere stand-ins. A round rock is a generated shape that collides as
## one sphere, placed and sized so that sphere stands where asked with the radius asked: a test aiming at a rock's face keeps
## its numbers, and rock `i` is sphere `i`. A mixed rock takes any shape and turn, as the bench's do.


## The generated shape that collides as one sphere and fills its bounds most; -1 when the asteroids are not generated.
static func round_shape() -> int:
	var best: int = -1
	var best_fill: float = 0.0
	var list: Array = AsteroidBelt.shapes()
	for i: int in list.size():
		var spheres: Array = list[i]["spheres"]
		if spheres.size() != 1:
			continue
		var fill: float = float(spheres[0]["radius_m"]) / float(list[i]["bounding_radius_m"])
		if fill > best_fill:
			best = i
			best_fill = fill
	return best


## A round rock whose collision sphere stands at `at` (from the field) with `radius` m.
static func round_rock(at: Vector3, radius: float) -> Dictionary:
	var index: int = round_shape()
	var shape: Dictionary = AsteroidBelt.shapes()[index]
	var sphere: Dictionary = (shape["spheres"] as Array)[0]
	var scale: float = radius / float(sphere["radius_m"])
	var c: Array = sphere["centre"]
	return {"offset": at - Vector3(float(c[0]), float(c[1]), float(c[2])) * scale,
			"radius": float(shape["bounding_radius_m"]) * scale, "shape": index, "basis": Basis.IDENTITY}


## A rock of any shape and turn (from `seed_value`) at `at`, `radius` m its bounding radius.
static func mixed_rock(at: Vector3, radius: float, seed_value: int) -> Dictionary:
	var rock: Dictionary = {"offset": at, "radius": radius}
	rock.merge(AsteroidBelt.seeded_look(seed_value))
	return rock


## Leaves `test` pending and says so when the asteroids are not generated (`scripts/gen_assets.sh`).
static func missing(test: GutTest) -> bool:
	if round_shape() >= 0:
		return false
	test.pending("the asteroids are not generated (scripts/gen_assets.sh)")
	return true


## The collision spheres a field built: each one's row position and radius, in build order.
static func spheres(field: AsteroidBelt) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in field.sphere_count:
		var at: int = StaticRows.ids.find(field.row_id(i))
		out.append({"at": StaticRows.positions[at], "radius": StaticRows.radii[at]})
	return out
