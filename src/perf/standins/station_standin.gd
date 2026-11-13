class_name StationStandin
extends Node3D
## The Babylon 5 station stand-in for the render comparison (M4-T27, Q24): bench-only, the generated `b5_station` asset's shape (no
## franchise asset), about 8 km long. The habitat drum turns about the station's long axis; the frame around it (reactor, spine,
## vanes, top bar, command section, bow) stands still. Each is a `RenderPiece` drawn as its textured mesh (M4-T30d).
##
## The drum's turn is a visual: it has no body, so it turns each frame by the frame's own time.

const ASSET_ID: String = "b5_station"
## The drum's spin, rad/s: one standard gravity at its 445 m radius, about 1.4 turns a minute.
const DRUM_RAD_S: float = 0.148

var frame_piece: RenderPiece = null
var drum_piece: RenderPiece = null
var drum_pivot: Node3D = null
var length_m: float = 0.0


func _init() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_to_group(WorldFrame.ANCHORED_GROUP)


## Builds both pieces from the generated asset; false (and nothing built) when it was not generated.
func build() -> bool:
	var manifest: Dictionary = MeshAssets.read_manifest(ASSET_ID)
	var pieces: Dictionary = manifest.get("pieces", {})
	if not pieces.has("drum") or not pieces.has("frame"):
		push_warning("StationStandin: %s is not generated (run scripts/gen_assets.sh, then import)" % ASSET_ID)
		return false
	length_m = float(manifest.get("length_m", 8000.0))
	var dir: String = ShipSpec.ASSET_ROOT.path_join(ASSET_ID)
	frame_piece = RenderPiece.new()
	frame_piece.name = "Frame"
	frame_piece.build(dir, pieces["frame"])
	add_child(frame_piece)
	drum_pivot = Node3D.new()
	drum_pivot.name = "DrumPivot"
	drum_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # turned each frame, not each tick
	var pivot: Array = (pieces["drum"] as Dictionary).get("pivot", [0.0, 0.0, 0.0])
	drum_pivot.position = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))
	add_child(drum_pivot)
	drum_piece = RenderPiece.new()
	drum_piece.name = "Drum"
	drum_piece.build(dir, pieces["drum"])
	drum_pivot.add_child(drum_piece)
	return true


func _process(delta: float) -> void:
	if drum_pivot != null:
		drum_pivot.rotate_object_local(Vector3.BACK, DRUM_RAD_S * delta)
