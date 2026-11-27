class_name FarMeshRange
extends RefCounted
## Where a capital piece's far mesh takes over from its full mesh (M10-T89, architecture §22.15). Godot's visibility ranges make
## the swap, per camera and with no script per frame: the far mesh fades in over `margin_m` either side of `from_m`, drawn over
## the full hull while that is still opaque; the full hull and what rides on it (its marks, doors and bay halls) are the far
## mesh's visibility dependents, so they stop drawing only once the far mesh is opaque and come back as soon as it starts to fade.
## There is never a frame with neither, and the fade, a function of distance alone, cannot flap at the boundary. Pure.

## How every capital's far mesh is used: by distance, never (the full hull at every range) or always (for comparisons).
enum Mode { AUTO, FULL, FAR }

## The mode the pieces built from now on take, and `RenderPiece.set_far_mode` gives the live ones.
static var mode: Mode = Mode.AUTO

## What a piece's camera sees at a distance: the full mesh alone, both (the far one fading in) or the far mesh alone.
enum Shown { FULL, BOTH, FAR }

## Below this a range is off in Godot; the far mesh drawn from here on counts as always.
const ALWAYS_M: float = 0.001


## The piece's far level of detail (its manifest `mesh.lods` entry), or empty when it has none.
static func lod_of(mesh_entry: Dictionary) -> Dictionary:
	var lods: Variant = mesh_entry.get("lods", [])
	if not lods is Array or (lods as Array).is_empty() or not (lods as Array)[0] is Dictionary:
		return {}
	var lod: Dictionary = (lods as Array)[0]
	return lod if not String(lod.get("file", "")).is_empty() and float(lod.get("from_m", 0.0)) > 0.0 else {}


## Where the far mesh's fade is centred, m.
static func begin_m(lod: Dictionary, p_mode: Mode) -> float:
	return ALWAYS_M if p_mode == Mode.FAR else float(lod.get("from_m", 0.0))


## The fade either side of `begin_m`, m (kept inside it, so the far mesh never reaches the camera).
static func margin_m(lod: Dictionary, p_mode: Mode) -> float:
	if p_mode == Mode.FAR:
		return 0.0
	var from: float = float(lod.get("from_m", 0.0))
	return clampf(float(lod.get("margin_m", 0.0)), 0.0, 0.5 * from)


## Sets the far mesh node's range for `p_mode`; in FULL it is hidden, which takes it out of the dependency tree (the full hull
## then draws at every range).
static func apply(node: GeometryInstance3D, lod: Dictionary, p_mode: Mode) -> void:
	node.visible = p_mode != Mode.FULL
	node.visibility_range_begin = begin_m(lod, p_mode)
	node.visibility_range_begin_margin = margin_m(lod, p_mode)
	node.visibility_range_end = 0.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED if p_mode == Mode.FAR \
			else GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## What a camera `distance_m` from the piece sees, as Godot's range check decides it for the far mesh and its dependents.
static func shown(distance_m: float, lod: Dictionary, p_mode: Mode) -> Shown:
	if lod.is_empty() or p_mode == Mode.FULL:
		return Shown.FULL
	var begin: float = begin_m(lod, p_mode)
	var margin: float = margin_m(lod, p_mode)
	if distance_m < begin - margin:
		return Shown.FULL
	return Shown.BOTH if distance_m < begin + margin else Shown.FAR


## The far mesh's opacity at `distance_m` (Godot's smoothstep across the fade), 0 to 1.
static func far_alpha(distance_m: float, lod: Dictionary, p_mode: Mode) -> float:
	match shown(distance_m, lod, p_mode):
		Shown.FULL:
			return 0.0
		Shown.FAR:
			return 1.0
	var begin: float = begin_m(lod, p_mode)
	var margin: float = margin_m(lod, p_mode)
	return smoothstep(0.0, 1.0, (distance_m - (begin - margin)) / (2.0 * margin))


## The mode named `text` (`auto`, `full`, `far`), or -1.
static func mode_named(text: String) -> int:
	return ["auto", "full", "far"].find(text.to_lower())


static func mode_name(p_mode: Mode) -> String:
	return ["auto", "full", "far"][p_mode]
