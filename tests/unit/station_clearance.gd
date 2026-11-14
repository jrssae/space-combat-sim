class_name StationClearance
extends RefCounted
## How far a point is from the station's drawn hull (M7-T12), for tests that keep a camera out of the walls: the frame's mesh and the
## drum's, each in its own frame, the drum turned about its pivot. Everything is in the station's frame; the drum's angle is a
## parameter, so a camera path sampled while the drum turns is read against the drum as it stood at that moment.

const ASSET_DIR: String = "res://assets/generated/babylon5_station/"

var pivot: Vector3 = Vector3.ZERO
var _frame: BotMeshField = null
var _drum: BotMeshField = null


## The clearance field of the generated station, or null when the asset is not built here.
static func load_station() -> StationClearance:
	var manifest: Dictionary = MeshAssets.read_manifest(Station.ASSET_ID)
	var drum: Variant = (manifest.get("pieces", {}) as Dictionary).get("drum")
	if not drum is Dictionary or not FileAccess.file_exists(ASSET_DIR + "babylon5_station_drum.glb"):
		return null
	var made := StationClearance.new()
	var p: Array = (drum as Dictionary).get("pivot", [0.0, 0.0, 0.0])
	made.pivot = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var pieces: Dictionary = manifest["pieces"]
	var frame_faces: PackedVector3Array = BotMeshField.faces_of_glb(ASSET_DIR + "babylon5_station_frame.glb")
	frame_faces.append_array(_prop_faces(pieces["frame"]))
	var drum_faces: PackedVector3Array = BotMeshField.faces_of_glb(ASSET_DIR + "babylon5_station_drum.glb")
	drum_faces.append_array(_prop_faces(pieces["drum"]))
	made._frame = BotMeshField.of_faces(frame_faces)
	made._drum = BotMeshField.of_faces(drum_faces)
	return made


# The faces of a piece's props (clamps, gantries, panels) where the manifest places them, in the piece's frame. The door leaves are
# left out: they swing, and the tests that care place them for the moment they test.
static func _prop_faces(piece: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var props: Dictionary = piece.get("props", {})
	var origins: Dictionary = {}
	for section: Dictionary in (piece.get("mesh", {}) as Dictionary).get("sections", []) as Array:
		var o: Array = section.get("origin", [0.0, 0.0, 0.0])
		origins[String(section["name"])] = Vector3(float(o[0]), float(o[1]), float(o[2]))
	var cache: Dictionary = {}
	for group: Dictionary in props.get("groups", []) as Array:
		var kind: String = String(group["kind"])
		if kind.begins_with("door_leaf"):
			continue
		if not cache.has(kind):
			cache[kind] = BotMeshField.faces_of_glb(ASSET_DIR + String((props["kinds"] as Dictionary)[kind]["file"]))
		var origin: Vector3 = origins.get(String(group["section"]), Vector3.ZERO)
		for flat: Array in group["transforms"] as Array:
			var xf: Transform3D = PieceSections.transform_of(flat)
			xf.origin += origin
			for p: Vector3 in cache[kind] as PackedVector3Array:
				out.append(xf * p)
	return out


## The distance from `point` (the station's frame) to the nearest drawn surface, with the drum turned by `drum_angle` radians; `reach`
## is how far the search looks (a larger distance answers `reach`).
func distance(point: Vector3, drum_angle: float, reach: float = 40.0) -> float:
	var in_drum: Vector3 = Basis(Vector3.BACK, -drum_angle) * (point - pivot)
	return minf(_frame.distance(point, reach), _drum.distance(in_drum, reach))
