class_name VramReading
extends RefCounted
## One sample of GPU memory for the debug overlay (M8-T20, D86): what the whole card holds and its size, as the driver reports
## them, and the game's own share beside it.
##
## Pure: the driver's files are read under a root the tests replace with a fake tree. Linux only for now (the DRM sysfs files,
## which the AMD driver fills in); anywhere else the total is unknown and the line says so. A GB here is 1024^3 bytes, the unit
## cards are sold in.

const DRM_ROOT := "/sys/class/drm"
const USED_FILE := "device/mem_info_vram_used"
const TOTAL_FILE := "device/mem_info_vram_total"
const VENDOR_FILE := "device/vendor"
const UNKNOWN: int = -1
const BYTES_PER_GB: float = 1073741824.0

## Words an adapter name carries, by the card's PCI vendor id: how a card is matched to the adapter Godot draws with.
const VENDOR_WORDS: Dictionary = {
	"0x1002": ["amd", "radeon"],
	"0x10de": ["nvidia", "geforce"],
	"0x8086": ["intel"],
}

## The driver's card (`card1`), empty when no card gave a reading.
var card: String = ""
## Memory in use on the whole card, every program's; `UNKNOWN` without a driver reading.
var used_bytes: int = UNKNOWN
## The card's memory; `UNKNOWN` without a driver reading.
var total_bytes: int = UNKNOWN
## What the game's renderer holds.
var game_bytes: int = 0


## Samples the card the adapter names, or the first card that reports its memory. Reads a few small files: callers keep it
## off the per-frame path.
static func read(game: int, adapter_name: String, drm_root: String = DRM_ROOT) -> VramReading:
	var best := VramReading.new()
	for card_name: String in _card_names(drm_root):
		var found: VramReading = _read_card(drm_root.path_join(card_name), card_name)
		if found == null:
			continue
		if _names_vendor(adapter_name, _first_line(drm_root.path_join(card_name).path_join(VENDOR_FILE))):
			best = found
			break
		if not best.has_total():
			best = found
	best.game_bytes = game
	return best


func has_total() -> bool:
	return total_bytes > 0 and used_bytes >= 0


## Card-wide use in GB, -1 when unknown.
func used_gb() -> float:
	return used_bytes / BYTES_PER_GB if has_total() else float(UNKNOWN)


## The card's size in GB, -1 when unknown.
func total_gb() -> float:
	return total_bytes / BYTES_PER_GB if has_total() else float(UNKNOWN)


## Card-wide use as a percentage of the card, -1 when unknown.
func pct() -> float:
	return 100.0 * float(used_bytes) / float(total_bytes) if has_total() else float(UNKNOWN)


func game_gb() -> float:
	return game_bytes / BYTES_PER_GB


## The overlay's line: `VRAM  2.41 / 16.00 GB (15 %)   GAME 0.48 GB`, or the game's share and `total unknown`.
func line() -> String:
	if not has_total():
		return "VRAM  GAME %.2f GB   total unknown" % game_gb()
	return "VRAM  %.2f / %.2f GB (%d %%)   GAME %.2f GB" % [used_gb(), total_gb(), roundi(pct()), game_gb()]


# The cards themselves, lowest number first: connectors (`card1-DP-1`) and render nodes share the directory.
static func _card_names(drm_root: String) -> Array[String]:
	var names: Array[String] = []
	if not DirAccess.dir_exists_absolute(drm_root):
		return names
	for entry: String in DirAccess.get_directories_at(drm_root):
		var number: String = entry.trim_prefix("card")
		if entry.begins_with("card") and number.is_valid_int() and int(number) >= 0:
			names.append(entry)
	names.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(4)) < int(b.substr(4)))
	return names


# A card's reading, or null when it does not report both numbers.
static func _read_card(card_dir: String, card_name: String) -> VramReading:
	var used: int = _parse_bytes(_first_line(card_dir.path_join(USED_FILE)))
	var total: int = _parse_bytes(_first_line(card_dir.path_join(TOTAL_FILE)))
	if used < 0 or total <= 0:
		return null
	var reading := VramReading.new()
	reading.card = card_name
	reading.used_bytes = used
	reading.total_bytes = total
	return reading


static func _parse_bytes(text: String) -> int:
	return int(text) if text.is_valid_int() and int(text) >= 0 else UNKNOWN


static func _first_line(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return file.get_line().strip_edges() if file != null else ""


static func _names_vendor(adapter_name: String, vendor_id: String) -> bool:
	var adapter: String = adapter_name.to_lower()
	for word: String in VENDOR_WORDS.get(vendor_id.to_lower(), []):
		if adapter.contains(word):
			return true
	return false
