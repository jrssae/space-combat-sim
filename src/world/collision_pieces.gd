class_name CollisionPieces
extends RefCounted
## A manifest's `collision` section (M7-T03, D73; `tools/procgen/core/collision.py`): per piece of an asset, the convex shapes
## its physics body is made of and the hit volumes fitted to them, so Jolt, the hit sweep and the turrets see one shape.
## Pure: no scene tree. `CollisionBodies` turns a piece into a body.
##
## A piece is a Dictionary: `name`, `aabb`, `bound_center`, `bound_radius`, `shapes` (each `name`, `type`, `shape`,
## `transform`, as a `Hardpoints.collision` entry) and `hit_volumes` (`HitShape`s, boxes and capsules only).

const TYPE_HULL: String = "hull"

## False when the section is missing or broken; `error` says why and `pieces` is empty.
var valid: bool = false
var error: String = ""
var pieces: Array[Dictionary] = []


## The collision pieces of a generated asset, read from its manifest.
static func for_asset(asset_id: String, asset_root: String = ShipSpec.ASSET_ROOT) -> CollisionPieces:
	return from_manifest(MeshAssets.read_manifest(asset_id, asset_root))


static func from_manifest(manifest: Dictionary) -> CollisionPieces:
	var out := CollisionPieces.new()
	out.error = out._parse(manifest.get("collision"))
	out.valid = out.error.is_empty()
	if not out.valid:
		out.pieces.clear()
	return out


## The piece called `piece_name`, or {} when there is none.
func piece(piece_name: String) -> Dictionary:
	for entry: Dictionary in pieces:
		if entry["name"] == piece_name:
			return entry
	return {}


func _parse(value: Variant) -> String:
	if not (value is Dictionary):
		return "the manifest has no collision section"
	var section: Dictionary = value
	var max_shapes: int = int(_number(section.get("max_shapes")))
	var max_points: int = int(_number(section.get("max_hull_points")))
	if max_shapes < 1 or max_points < 4:
		return "collision needs max_shapes and max_hull_points"
	var list: Variant = section.get("pieces")
	if not (list is Array) or (list as Array).is_empty():
		return "collision has no pieces[]"
	for raw: Variant in list as Array:
		var problem: String = _parse_piece(raw, max_shapes, max_points)
		if not problem.is_empty():
			return problem
	return ""


func _parse_piece(value: Variant, max_shapes: int, max_points: int) -> String:
	if not (value is Dictionary) or str((value as Dictionary).get("name", "")).is_empty():
		return "collision piece %d needs a name" % pieces.size()
	var entry: Dictionary = value
	var label: String = str(entry["name"])
	if not piece(label).is_empty():
		return "collision piece %s is named twice" % label
	var bound: Variant = entry.get("bound")
	if not _is_vec3(entry.get("aabb_min")) or not _is_vec3(entry.get("aabb_max")) \
			or not (bound is Dictionary) or not _is_vec3((bound as Dictionary).get("center")):
		return "collision piece %s needs aabb_min, aabb_max and bound.center" % label
	var radius: float = _number((bound as Dictionary).get("radius"))
	if radius <= 0.0:
		return "collision piece %s needs a positive bound.radius" % label
	var raw_shapes: Variant = entry.get("shapes")
	var raw_volumes: Variant = entry.get("hit_volumes")
	if not (raw_shapes is Array) or (raw_shapes as Array).is_empty() or not (raw_volumes is Array):
		return "collision piece %s needs shapes[] and hit_volumes[]" % label
	if (raw_shapes as Array).size() > max_shapes:
		return "collision piece %s has %d shapes, over its budget of %d" % [label, (raw_shapes as Array).size(), max_shapes]
	var shapes: Array[Dictionary] = []
	for raw: Variant in raw_shapes as Array:
		var shape: Dictionary = _shape(raw, max_points)
		if shape.is_empty():
			return "collision piece %s has a shape that is no box, capsule or hull of 4 to %d points" % [label, max_points]
		shapes.append(shape)
	var volumes: Array[HitShape] = []
	for raw: Variant in raw_volumes as Array:
		var volume: HitShape = HitShape.from_collision(Hardpoints.collision_entry(raw))
		if volume == null:
			return "collision piece %s has a hit volume that is no box or capsule" % label
		volumes.append(volume)
	var lo: Vector3 = _to_vec3(entry["aabb_min"])
	pieces.append({
		"name": label,
		"aabb": AABB(lo, _to_vec3(entry["aabb_max"]) - lo),
		"bound_center": _to_vec3((bound as Dictionary)["center"]),
		"bound_radius": radius,
		"shapes": shapes,
		"hit_volumes": volumes,
	})
	return ""


# One shape as `Hardpoints` gives a box or a capsule; a hull's points are already in the piece's frame.
static func _shape(value: Variant, max_points: int) -> Dictionary:
	if not (value is Dictionary) or str((value as Dictionary).get("type", "")) != TYPE_HULL:
		return Hardpoints.collision_entry(value)
	var entry: Dictionary = value
	var raw_points: Variant = entry.get("points")
	if not (raw_points is Array) or (raw_points as Array).size() < 4 or (raw_points as Array).size() > max_points:
		return {}
	var points := PackedVector3Array()
	for raw: Variant in raw_points as Array:
		if not _is_vec3(raw):
			return {}
		points.append(_to_vec3(raw))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	return {"name": str(entry.get("name", "")), "type": TYPE_HULL, "shape": hull, "transform": Transform3D.IDENTITY}


static func _number(value: Variant) -> float:
	return float(value) if value is float or value is int else 0.0


static func _is_vec3(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 3:
		return false
	for part: Variant in value as Array:
		if not (part is float or part is int):
			return false
	return true


static func _to_vec3(value: Variant) -> Vector3:
	var parts: Array = value
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
