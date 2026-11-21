class_name Livery
extends RefCounted
## A ship's paint (M4-T30b, Q35; architecture §17.18): its wing's colours and pattern and its own number, drawn by the hull shader
## (`hull_livery.gdshader`) over the shared maps. The table is the manifest's `mesh.livery` section, written by procgen
## (`tools/procgen/core/livery.py`); a wing it does not name gets a stable livery from its name (FNV-1a, as procgen computes it), and
## no wing (an enemy, an unnamed ship) the plain field grey with no number. A ship is handed its livery; the player's will one day
## come from a paint-scheme choice instead of its wing.

## The wing the player's own ship flies in, and its slot, until the paint-scheme choice exists.
const PLAYER_WING: String = "alpha"
const PLAYER_NUMBER: int = 1

var wing: String = ""
var number: int = 0
var primary: Color = Color(0.3, 0.3, 0.3)
var secondary: Color = Color(0.3, 0.3, 0.3)
var number_colour: Color = Color(0.8, 0.8, 0.8)
var pattern: String = "plain"
var fields: PackedStringArray = PackedStringArray()
## The pattern's index and the number fields' bits in the section's tables, as the shader reads them.
var pattern_index: int = 0
var field_bits: int = 0
## The unit marking worn over the paint (a `markers` row of the section; "" for none) and its index in the shader's table (0: none).
var marker: String = ""
var marker_index: int = 0
var marker_colour: Color = Color(0.7, 0.05, 0.04)
## The hue the hull's engine glow map is recoloured to (alpha 0: the map's own), a faction's `engine_glow` normalised to a peak of 1.
var engine_tint: Color = Color(0.0, 0.0, 0.0, 0.0)


## FNV-1a, 32 bits, over the UTF-8 bytes of `text` (procgen's `fnv1a32`).
static func fnv1a(text: String) -> int:
	var h: int = 0x811C9DC5
	for byte: int in text.to_utf8_buffer():
		h = ((h ^ byte) * 0x01000193) & 0xFFFFFFFF
	return h


## The livery of ship `p_number` (from 1; 0 for none) of wing `p_wing` under `section`; the plain one for no wing or no table.
static func for_wing(p_wing: String, p_number: int, section: Dictionary) -> Livery:
	var out := Livery.new()
	var key: String = p_wing.strip_edges().to_lower()
	out.wing = key
	var named: Dictionary = section.get("liveries", {})
	var row: Dictionary = {}
	if key.is_empty() or section.is_empty():
		row = section.get("plain", {})
	elif named.has(key):
		row = named[key]
	else:
		var fallback: Dictionary = section.get("fallback", {})
		var palettes: Array = fallback.get("palettes", [])
		var patterns: Array = fallback.get("patterns", [])
		if palettes.is_empty() or patterns.is_empty():
			row = section.get("plain", {})
		else:
			var h: int = fnv1a(key)
			row = (palettes[h % palettes.size()] as Dictionary).duplicate()
			row["pattern"] = patterns[(h >> 16) % patterns.size()]
			row["numbers"] = fallback.get("numbers", [])
	out.primary = _colour(row.get("primary", [0.3, 0.3, 0.3]))
	out.secondary = _colour(row.get("secondary", [0.3, 0.3, 0.3]))
	out.number_colour = _colour(row.get("number_colour", [0.8, 0.8, 0.8]))
	out.pattern = String(row.get("pattern", "plain"))
	out.fields = PackedStringArray(row.get("numbers", []))
	out.number = maxi(p_number, 0) if not out.fields.is_empty() else 0
	out.pattern_index = maxi((section.get("patterns", {}) as Dictionary).keys().find(out.pattern), 0)
	var field_names: Array = (section.get("number_fields", {}) as Dictionary).keys()
	for field: String in out.fields:
		var index: int = field_names.find(field)
		if index >= 0:
			out.field_bits |= 1 << index
	return out


## Adds the faction's marking (`FactionTable.marking`, M10-T02: the renegades' small unit marks) over this livery without recolouring
## the hull. An empty `marking`, or one the hull's table does not name, leaves the livery as it is. Returns `self`.
func with_marking(marking: String, section: Dictionary) -> Livery:
	var markers: Dictionary = section.get("markers", {})
	if marking.is_empty() or not markers.has(marking):
		return self
	marker = marking
	marker_index = markers.keys().find(marking) + 1
	var row: Dictionary = markers[marking]
	marker_colour = _colour(row.get("colour", [0.7, 0.05, 0.04]))
	return self


## A faction's look over this livery (`FactionTable`): its marking and its engine colour. Returns `self`.
func with_faction(table: FactionTable, faction: StringName, section: Dictionary) -> Livery:
	with_marking(table.marking(faction), section)
	return with_engine_glow(table.engine_glow(faction))


## Recolours the hull's engine glow map to `glow` (a faction's HDR engine colour; alpha 0 for none). Returns `self`.
func with_engine_glow(glow: Color) -> Livery:
	engine_tint = Color(0.0, 0.0, 0.0, 0.0)
	if glow.a > 0.0:
		var peak: float = maxf(glow.r, maxf(glow.g, glow.b))
		if peak > 0.0:
			engine_tint = Color(glow.r / peak, glow.g / peak, glow.b / peak, 1.0)
	return self


## The player's own livery until the paint-scheme choice exists: Alpha 01.
static func player(section: Dictionary) -> Livery:
	return for_wing(PLAYER_WING, PLAYER_NUMBER, section)


## Splits a ship's name in the pool's form (`ALPHA 2`) into its wing and number; ["", 0] when it has none.
static func parse_name(ship_name: String) -> Array:
	var parts: PackedStringArray = ship_name.strip_edges().split(" ", false)
	if parts.size() == 2 and parts[1].is_valid_int() and int(parts[1]) > 0:
		return [parts[0], int(parts[1])]
	return ["", 0]


## The number as painted, two digits ("01"), or "" for none.
func number_text() -> String:
	return "%02d" % (number % 100) if number > 0 else ""


## Gives `instance` this livery's per-instance shader values (the hull material's `instance uniform`s).
func apply(instance: GeometryInstance3D) -> void:
	if instance == null:
		return
	instance.set_instance_shader_parameter(&"livery_primary", primary)
	instance.set_instance_shader_parameter(&"livery_secondary", secondary)
	instance.set_instance_shader_parameter(&"livery_number_colour", number_colour)
	instance.set_instance_shader_parameter(&"livery_pattern", pattern_index)
	instance.set_instance_shader_parameter(&"livery_fields", field_bits)
	instance.set_instance_shader_parameter(&"livery_number", number)
	instance.set_instance_shader_parameter(&"livery_marker", marker_index)
	instance.set_instance_shader_parameter(&"livery_marker_colour", marker_colour)
	instance.set_instance_shader_parameter(&"livery_engine_tint", engine_tint)


## A short line for the console and the state provider.
func describe() -> String:
	return "%s %s (%s)%s" % [wing if not wing.is_empty() else "plain", number_text() if number > 0 else "-", pattern,
			" marked %s" % marker if not marker.is_empty() else ""]


static func _colour(values: Array) -> Color:
	return Color(float(values[0]), float(values[1]), float(values[2])) if values.size() >= 3 else Color(0.3, 0.3, 0.3)
