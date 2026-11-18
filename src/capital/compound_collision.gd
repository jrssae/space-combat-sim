class_name CompoundCollision
extends RefCounted
## A generated capital hull's compound collision as one body (M7's D73, M12-T19): every piece of the manifest's `collision`
## section (`tools/procgen/core/collision.py`, the station's format too since M8-T07) as the shapes Jolt collides with and the
## volumes the hit sweeps use. `CollisionPieces` reads and checks the section; a broken section gives no shapes at all, so the
## caller falls back to its plain box. Pure: a dictionary in, plain shapes out.


## Every shape of `section` for the physics body, piece by piece: `{name, piece, shape, transform}`, in the body frame.
static func solids(section: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for piece: Dictionary in _read(section).pieces:
		for shape: Dictionary in piece["shapes"]:
			out.append({"name": shape["name"], "piece": piece["name"], "shape": shape["shape"], "transform": shape["transform"]})
	return out


## Every hit volume of `section` in `Hardpoints.collision`'s form (`{name, type, shape, transform}`, boxes and capsules only),
## one per shape: a hull is hit as the box fitted round it.
static func hit_volumes(section: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _read(section).valid:
		return out
	for piece: Dictionary in section["pieces"]:
		for raw: Variant in piece["hit_volumes"]:
			out.append(Hardpoints.collision_entry(raw))
	return out


## The pieces' names, in order.
static func piece_names(section: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for piece: Dictionary in _read(section).pieces:
		out.append(String(piece["name"]))
	return out


static func _read(section: Dictionary) -> CollisionPieces:
	return CollisionPieces.from_manifest({"collision": section})
