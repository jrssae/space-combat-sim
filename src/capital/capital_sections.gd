class_name CapitalSections
extends RefCounted
## A capital hull's damage sections as its collision knows them (M10-T07, D12.5's groundwork): each entry of the manifest's
## `collision.pieces` is one section, on the body its `piece` names (the hull, or a rotating piece). So a hit or a ram on a
## body can be named by the section it landed on; T08 takes the damage from there. Pure: a manifest in, names out.

## The body every section belongs to when the manifest names none.
const HULL: String = "hull"

## The collision pieces as `CollisionPieces` read them, each with `piece` (its body) added; empty when the section is broken.
var pieces: Array[Dictionary] = []
var valid: bool = false
var error: String = ""
## The manifest's `sections[]` by name (kind, hull share, hardpoints held, blast energy).
var by_name: Dictionary = {}


static func from_manifest(manifest: Dictionary) -> CapitalSections:
	var out := CapitalSections.new()
	var read: CollisionPieces = CollisionPieces.from_manifest(manifest)
	out.valid = read.valid
	out.error = read.error
	if not read.valid:
		return out
	var raw: Array = (manifest["collision"] as Dictionary)["pieces"]
	for i: int in read.pieces.size():
		var entry: Dictionary = read.pieces[i].duplicate()
		entry["piece"] = str((raw[i] as Dictionary).get("piece", HULL))
		out.pieces.append(entry)
	for raw_section: Variant in manifest.get("sections", []):
		if raw_section is Dictionary:
			out.by_name[str((raw_section as Dictionary).get("name", ""))] = raw_section
	return out


## The bodies the sections sit on (`hull` first, then each rotating piece), in manifest order.
func bodies() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in pieces:
		if not out.has(entry["piece"]):
			out.append(entry["piece"])
	if out.has(HULL):
		out.remove_at(out.find(HULL))
		out.insert(0, HULL)
	return out


## The sections on body `piece`, in order.
func on(piece: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in pieces:
		if entry["piece"] == piece:
			out.append(entry)
	return out


## Every hit volume of body `piece`, section by section.
func volumes_of(piece: String) -> Array[HitShape]:
	var out: Array[HitShape] = []
	for entry: Dictionary in on(piece):
		out.append_array(entry["hit_volumes"])
	return out


## Every collision shape of body `piece`, section by section, as `CollisionPieces` gives them.
func shapes_of(piece: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in on(piece):
		out.append_array(entry["shapes"])
	return out


## The section of each of body `piece`'s hit volumes, in `volumes_of`'s order.
func volume_sections(piece: String) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in on(piece):
		for _v: HitShape in entry["hit_volumes"]:
			out.append(entry["name"])
	return out


## The section of body `piece` that `local` (a point in that body's frame) lies in or nearest, or "" with none.
func section_at(piece: String, local: Vector3) -> String:
	var best: String = ""
	var best_d: float = INF
	for entry: Dictionary in on(piece):
		for v: HitShape in entry["hit_volumes"]:
			var d: float = distance(v, local)
			if d < best_d:
				best_d = d
				best = entry["name"]
	return best


## How far `p` (body frame) is from volume `v`'s surface, 0 inside.
static func distance(v: HitShape, p: Vector3) -> float:
	var q: Vector3 = v.transform.affine_inverse() * p
	if v.kind == HitShape.Kind.BOX:
		return (q.abs() - v.half_extents).max(Vector3.ZERO).length()
	var on_axis := Vector3(0.0, clampf(q.y, -v.half_segment, v.half_segment), 0.0)
	return maxf((q - on_axis).length() - v.radius, 0.0)
