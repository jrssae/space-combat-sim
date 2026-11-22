class_name CapitalData
extends RefCounted
## The capital ships' tuning (M8-T08, D83), read once from `data/capitals/capitals.json`: how long each class's jump drive
## needs after a jump before it can open another point, each faction's carrier doctrine (when its fighters go home and
## when the carrier flees; `CarrierTactics.DEFAULTS` lists the keys), how far each class is heard (M10-T07, Q51), and how its
## sections and mounts take damage (M10-T08, D12.5), the blasts' table (M10-T09, D12.6, `BlastTable`) and how a disabled hull
## winds down and which ships never leave one (M10-T10, D12.7). Pure apart from the reads.

const PATH: String = "res://data/capitals/capitals.json"
## The weapons' kinds (M10-T03), for a mount's hit points.
const LOADOUTS_PATH: String = "res://data/capitals/loadouts.json"
## The section rules a file without `section_damage` falls back on (D12.5's numbers).
const SECTION_DEFAULTS: Dictionary = {"reactor_overload": 0.5, "pass_on": 0.5, "headless_fire_rate": 0.5,
		"power_stage_at": 0.5, "power_stage_level": 0.5, "mount_reach_m": 10.0}
## The hulk rules a file without `hulks` falls back on (D12.7, Q19): when control goes and when the drive is cold after the ship
## is disabled, and how long its lights take to die, s.
const HULK_DEFAULTS: Dictionary = {"control_loss_s": 2.0, "cold_s": 6.0, "lights_fade_s": 3.0}
## A mount neither table names has this many hit points (a medium mount's).
const DEFAULT_MOUNT_HP: float = 800.0
## A class the file does not name recharges this long, s.
const DEFAULT_RECHARGE_S: float = 60.0

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _weapons: Dictionary = {}
static var _hulls: Dictionary = {}
static var _weapons_loaded: bool = false


## How long `cls`'s drive needs after a jump, s.
static func jump_recharge_s(cls: StringName) -> float:
	var table: Variant = _read().get("jump_recharge_s")
	var value: Variant = (table as Dictionary).get(String(cls)) if table is Dictionary else null
	return maxf(float(value), 0.0) if value is float or value is int else DEFAULT_RECHARGE_S


## How far a capital of `cls` is heard, by every side, m (M10-T07, Q51): the file's `broadcast_range_m` for the class, or its
## `capital` value for a class it does not name (destroyers, carriers).
static func broadcast_range_m(cls: StringName) -> float:
	var table: Variant = _read().get("broadcast_range_m")
	if not (table is Dictionary):
		return 0.0
	var value: Variant = (table as Dictionary).get(String(cls), (table as Dictionary).get("capital"))
	return maxf(float(value), 0.0) if value is float or value is int else 0.0


## The carrier doctrine of `faction`: the options its raids start from (empty: `CarrierTactics.DEFAULTS` alone).
static func doctrine(faction: StringName) -> Dictionary:
	var table: Variant = _read().get("carrier_doctrine")
	var found: Variant = (table as Dictionary).get(String(faction)) if table is Dictionary else null
	return (found as Dictionary).duplicate() if found is Dictionary else {}


## Hulk rule `key` (`HULK_DEFAULTS` lists them): the file's `hulks` value, else the default.
static func hulk_rule(key: String) -> float:
	var table: Variant = _read().get("hulks")
	var value: Variant = (table as Dictionary).get(key) if table is Dictionary else null
	return float(value) if value is float or value is int else float(HULK_DEFAULTS.get(key, 0.0))


## Whether a ship of `faction` and hull `type_id` never becomes a hulk: disabled, it explodes instead (the ancients' ships; the
## file's `hulks.never_hulk` lists factions and hulls).
static func never_hulk(faction: StringName, type_id: StringName) -> bool:
	var table: Variant = _read().get("hulks")
	var rule: Variant = (table as Dictionary).get("never_hulk") if table is Dictionary else null
	if not (rule is Dictionary):
		return false
	var factions: Variant = (rule as Dictionary).get("factions")
	var hulls: Variant = (rule as Dictionary).get("hulls")
	return (factions is Array and (factions as Array).has(String(faction))) or (hulls is Array and (hulls as Array).has(String(type_id)))


## Section rule `key` (`SECTION_DEFAULTS` lists them): the file's `section_damage` value, else the default.
static func section_rule(key: String) -> float:
	var table: Variant = _read().get("section_damage")
	var value: Variant = (table as Dictionary).get(key) if table is Dictionary else null
	return float(value) if value is float or value is int else float(SECTION_DEFAULTS.get(key, 0.0))


## A mount's own hit points: by its weapon's kind when `weapon` names one in the loadouts, else by the hardpoint's `mount_kind`.
static func mount_hit_points(weapon: String, mount_kind: String) -> float:
	var table: Variant = _read().get("mount_hit_points")
	if not (table is Dictionary):
		return DEFAULT_MOUNT_HP
	var by_weapon: Variant = (table as Dictionary).get("by_weapon_kind")
	var kind: String = weapon_kind(weapon)
	if by_weapon is Dictionary and (by_weapon as Dictionary).has(kind):
		return float((by_weapon as Dictionary)[kind])
	var by_mount: Variant = (table as Dictionary).get("by_mount_kind")
	if by_mount is Dictionary and (by_mount as Dictionary).has(mount_kind):
		return float((by_mount as Dictionary)[mount_kind])
	return DEFAULT_MOUNT_HP


## The kind of weapon `id` in the loadouts (`bolt_heavy`, `beam_sustained`, ...), "" when it names none.
static func weapon_kind(id: String) -> String:
	_read_loadouts()
	var entry: Variant = _weapons.get(id)
	return str((entry as Dictionary).get("kind", "")) if entry is Dictionary else ""


## Weapon `id`'s row in the loadouts (`kind`, `damage`, `arc_deg`, ...), empty when they do not list it (M10-T12). Shared and
## read-only to the caller.
static func weapon_entry(id: String) -> Dictionary:
	_read_loadouts()
	var entry: Variant = _weapons.get(id)
	return entry if entry is Dictionary else {}


## The class the loadouts give hull `id` (`fighter`, `small_craft`, `cruiser`, `capital`, `dreadnought`), "" when they do not
## list it (M10-T09: what a death's blast is sized by).
static func hull_class(id: String) -> String:
	_read_loadouts()
	var entry: Variant = _hulls.get(id)
	return str((entry as Dictionary).get("class", "")) if entry is Dictionary else ""


## A hull's loadout row (`hull`, `damage_scale`, ...), empty when the loadouts do not list `id` (M10-T09: what a death's blast
## scales by). Shared and read-only to the caller.
static func hull_entry(id: String) -> Dictionary:
	_read_loadouts()
	var entry: Variant = _hulls.get(id)
	return entry if entry is Dictionary else {}


## The file's table under `key` (M10-T09: `blasts`), empty when it has none. Shared and read-only to the caller.
static func table(key: String) -> Dictionary:
	var found: Variant = _read().get(key)
	return found if found is Dictionary else {}


## Reads the files again on the next call (tests).
static func reload() -> void:
	_loaded = false
	_weapons_loaded = false


static func _read_loadouts() -> void:
	if _weapons_loaded:
		return
	_weapons_loaded = true
	_weapons = {}
	_hulls = {}
	var file := FileAccess.open(LOADOUTS_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary and (parsed as Dictionary).get("weapons") is Dictionary:
		_weapons = (parsed as Dictionary)["weapons"]
	if parsed is Dictionary and (parsed as Dictionary).get("hulls") is Dictionary:
		_hulls = (parsed as Dictionary)["hulls"]


static func _read() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		var file := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		if parsed is Dictionary:
			_data = parsed
		else:
			push_warning("CapitalData: cannot read %s; defaults are used" % PATH)
	return _data
