class_name CompoundCollision
extends RefCounted
## A generated hull's compound collision (M7's D73, M12-T19): reads the manifest's `collision` section
## (`tools/procgen/core/collision.py`) into the shapes Jolt collides with and the volumes the hit sweeps use. Pure: a
## dictionary in, plain shapes out. A hull shape collides as itself (a `ConvexPolygonShape3D`) and is hit as its bounding
## `box`, because the hit sweeps know boxes and capsules only.

const TYPE_BOX: String = "box"
const TYPE_CAPSULE: String = "capsule"
const TYPE_HULL: String = "hull"


## Every shape of `section` for the physics body, piece by piece: `{name, piece, shape, transform}`, in the body frame.
## Malformed entries are skipped.
static func solids(section: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for piece: Dictionary in _pieces(section):
		for entry: Variant in piece.get("shapes", []):
			if not (entry is Dictionary):
				continue
			var solid: Dictionary = _solid(entry as Dictionary)
			if not solid.is_empty():
				solid["piece"] = String(piece.get("name", ""))
				out.append(solid)
	return out


## Every shape of `section` as a hit volume in `Hardpoints.collision`'s form (`{name, type, shape, transform}`, boxes and
## capsules only): a hull becomes its bounding box.
static func hit_volumes(section: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for piece: Dictionary in _pieces(section):
		for entry: Variant in piece.get("shapes", []):
			if not (entry is Dictionary):
				continue
			var source: Dictionary = entry
			if String(source.get("type", "")) == TYPE_HULL:
				if not (source.get("box") is Dictionary):
					continue
				source = (source["box"] as Dictionary).duplicate()
				source["type"] = TYPE_BOX
				source["name"] = (entry as Dictionary).get("name", "")
			var solid: Dictionary = _solid(source)
			if not solid.is_empty():
				out.append({"name": solid["name"], "type": source["type"], "shape": solid["shape"], "transform": solid["transform"]})
	return out


## The pieces' names, in order.
static func piece_names(section: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for piece: Dictionary in _pieces(section):
		out.append(String(piece.get("name", "")))
	return out


static func _pieces(section: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for piece: Variant in section.get("pieces", []):
		if piece is Dictionary:
			out.append(piece)
	return out


# One manifest shape as `{name, shape, transform}`, or {} when it is malformed.
static func _solid(entry: Dictionary) -> Dictionary:
	var position: Variant = _vec3(entry.get("position"))
	if position == null:
		return {}
	var basis: Basis = _basis(entry.get("basis"))
	var shape: Shape3D = null
	match String(entry.get("type", "")):
		TYPE_BOX:
			var size: Variant = _vec3(entry.get("size"))
			if size == null or (size as Vector3).x <= 0.0 or (size as Vector3).y <= 0.0 or (size as Vector3).z <= 0.0:
				return {}
			var box := BoxShape3D.new()
			box.size = size
			shape = box
		TYPE_CAPSULE:
			var radius: float = float(entry.get("radius", 0.0))
			var height: float = float(entry.get("height", 0.0))
			if radius <= 0.0 or height < 2.0 * radius:
				return {}
			var capsule := CapsuleShape3D.new()
			capsule.radius = radius
			capsule.height = height
			shape = capsule
			basis = basis * Hardpoints.capsule_axis_basis(String(entry.get("axis", "z")))
		TYPE_HULL:
			var points := PackedVector3Array()
			for raw: Variant in entry.get("points", []):
				var p: Variant = _vec3(raw)
				if p != null:
					points.append(p)
			if points.size() < 4:
				return {}
			var hull := ConvexPolygonShape3D.new()
			hull.points = points
			shape = hull
			return {"name": String(entry.get("name", "")), "shape": shape, "transform": Transform3D.IDENTITY}  # its points are in the body frame
		_:
			return {}
	return {"name": String(entry.get("name", "")), "shape": shape, "transform": Transform3D(basis, position)}


static func _vec3(value: Variant) -> Variant:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null


# `{x, y, z}` columns as a rotation (the generator rounds to five decimals, so it is squared up again).
static func _basis(value: Variant) -> Basis:
	if not (value is Dictionary):
		return Basis.IDENTITY
	var x: Variant = _vec3((value as Dictionary).get("x"))
	var y: Variant = _vec3((value as Dictionary).get("y"))
	var z: Variant = _vec3((value as Dictionary).get("z"))
	if x == null or y == null or z == null:
		return Basis.IDENTITY
	return Basis(x, y, z).orthonormalized()
