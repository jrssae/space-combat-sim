class_name CapitalMarkerRules
extends RefCounted
## When the HUD marks a far capital ship (M8-T08), read once from `data/hud/capital_markers.json`: a small hull kilometres out
## is a dark speck, so the HUD shows where it is until it is big enough to read. By relation and size on screen, never by
## class, so every capital gets it.

const PATH: String = "res://data/hud/capital_markers.json"

## Relations whose capitals are marked.
var relations: Array[Factions.Relation] = [Factions.Relation.HOSTILE]
## Farther than this, no marker, m.
var max_range_m: float = 30000.0
## The marker hides once the hull's bounding radius is this big on screen, px at 1080p.
var hide_above_px: float = 14.0
## At most this many markers, the nearest first.
var max_markers: int = 4
## Off-screen capitals get an edge arrow.
var edge_arrows: bool = true

static var _shared: CapitalMarkerRules = null


## The file's rules, read on the first call.
static func shared() -> CapitalMarkerRules:
	if _shared == null:
		_shared = from_file(PATH)
	return _shared


## Reads the file again on the next call (tests).
static func reload() -> void:
	_shared = null


## Rules from `path`; the defaults above for anything it does not give.
static func from_file(path: String) -> CapitalMarkerRules:
	var rules := CapitalMarkerRules.new()
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		push_warning("CapitalMarkerRules: cannot read %s; defaults are used" % path)
		return rules
	var data: Dictionary = parsed
	if data.get("relations") is Array:
		rules.relations = []
		for name: Variant in data["relations"]:
			var key: String = str(name).to_upper()
			if Factions.Relation.has(key):
				rules.relations.append(Factions.Relation[key])
	rules.max_range_m = float(data.get("max_range_m", rules.max_range_m))
	rules.hide_above_px = float(data.get("hide_above_px", rules.hide_above_px))
	rules.max_markers = int(data.get("max_markers", rules.max_markers))
	rules.edge_arrows = bool(data.get("edge_arrows", rules.edge_arrows))
	return rules
