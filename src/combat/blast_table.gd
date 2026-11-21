class_name BlastTable
extends RefCounted
## The blasts' sizes (M10-T09, D12.6, Q18, Q53), read from `blasts` in `data/capitals/capitals.json` through `CapitalData`:
## what each source blows with (a missile, a mine, a fighter's or a civilian's death) and, for a capital, what each explosive
## section kind blows with by its blast class (cruiser, capital, dreadnought, the ancients). A death is sized by the hull's
## class and what it carries: a capital's by the section that blew, a pooled hull's by its role and its cargo. Pure apart from
## the read; specs are cached and shared, so a caller copies one before changing it.

## A capital whose death names no section blows with this one (its reactor: what every capital carries).
const DEFAULT_KIND: String = "reactor"
## A capital class the table does not know, and a pooled hull with no row, fall back on these.
const DEFAULT_CLASS: StringName = &"capital"
const DEFAULT_SOURCE: StringName = &"fighter_death"
const SMALL_CRAFT: String = "small_craft"
const SMALL_CRAFT_SOURCE: StringName = &"small_craft_death"
const KINDS: Array[String] = ["magazine", "fuel", "reactor"]

static var _cache: Dictionary = {}  # row name -> BlastSpec


## The blast `name` names: a source (`missile`, `fighter_death`, ...) or a class's section (`capital_reactor`,
## `cruiser_magazine`, ...); null for a name the table does not hold.
static func spec(name: StringName) -> BlastSpec:
	if _cache.has(name):
		return _cache[name]
	var made: BlastSpec = _source_row(name)
	if made == null:
		var text: String = String(name)
		var cut: int = text.rfind("_")
		if cut > 0:
			made = section(StringName(text.left(cut)), text.substr(cut + 1))
	if made != null:
		_cache[name] = made
	return made


## What section `kind` (`reactor`, `magazine`, `fuel`) of a hull of blast class `blast_class` blows with; null when the
## table has no such row.
static func section(blast_class: StringName, kind: String) -> BlastSpec:
	var name := StringName("%s_%s" % [blast_class, kind])
	if _cache.has(name):
		return _cache[name]
	var row: Variant = (_blasts().get("sections", {}) as Dictionary).get(String(blast_class))
	var pair: Variant = (row as Dictionary).get(kind) if row is Dictionary else null
	if not (pair is Array) or (pair as Array).size() < 2:
		return null
	var made: BlastSpec = _finish(BlastSpec.make(name, float(pair[0]), float(pair[1]), float((row as Dictionary).get("impulse", 0.0))))
	_cache[name] = made
	return made


## Every name `spec` takes, sources first.
static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in (_blasts().get("sources", {}) as Dictionary):
		out.append(key)
	for cls: String in (_blasts().get("sections", {}) as Dictionary):
		for kind: String in KINDS:
			out.append("%s_%s" % [cls, kind])
	return out


## The blast class of a capital: its side's own row (the ancients), else the loadouts' class for its catalogue `type_id`,
## else its catalogue `capital_class` (or the row that class takes), else `DEFAULT_CLASS`.
static func capital_class(type_id: StringName, p_capital_class: StringName, faction: StringName) -> StringName:
	var sections: Dictionary = _blasts().get("sections", {})
	var by_faction: Variant = (_blasts().get("factions", {}) as Dictionary).get(String(faction))
	if by_faction != null and sections.has(str(by_faction)):
		return StringName(str(by_faction))
	var from_loadouts: String = CapitalData.hull_class(String(type_id))
	if sections.has(from_loadouts):
		return StringName(from_loadouts)
	if sections.has(String(p_capital_class)):
		return p_capital_class
	var mapped: Variant = (_blasts().get("classes", {}) as Dictionary).get(String(p_capital_class))
	return StringName(str(mapped)) if mapped != null and sections.has(str(mapped)) else DEFAULT_CLASS


## A capital's death: the blast of the section kind that blew (`DEFAULT_KIND` for none, or a kind its class has no row for).
static func capital_death(type_id: StringName, p_capital_class: StringName, faction: StringName, kind: String) -> BlastSpec:
	var cls: StringName = capital_class(type_id, p_capital_class, faction)
	var made: BlastSpec = section(cls, kind if KINDS.has(kind) else DEFAULT_KIND)
	return made if made != null else section(cls, DEFAULT_KIND)


## A pooled hull's death, by its asset id: the table's own row for the hull, else a small craft's, else its catalogue role's,
## else `DEFAULT_SOURCE`; scaled by its cargo when it carries one the table names.
static func hull_death(asset_id: String) -> BlastSpec:
	var key := StringName("death:%s" % asset_id)
	if _cache.has(key):
		return _cache[key]
	var b: Dictionary = _blasts()
	var source: Variant = (b.get("hulls", {}) as Dictionary).get(asset_id)
	if source == null and CapitalData.hull_class(asset_id) == SMALL_CRAFT:
		source = SMALL_CRAFT_SOURCE
	if source == null:
		var role: String = str(ShipCatalog.data().by_asset("role").get(asset_id, ""))
		source = (b.get("by_role", {}) as Dictionary).get(role)
	var made: BlastSpec = spec(StringName(str(source))) if source != null else null
	if made == null:
		made = spec(DEFAULT_SOURCE)
	if made == null:
		made = BlastSpec.make(DEFAULT_SOURCE, 0.0, 0.0, 0.0)
	var cargo: Variant = (b.get("cargo", {}) as Dictionary).get(asset_id)
	var scale: Variant = (b.get("cargo_scale", {}) as Dictionary).get(str(cargo)) if cargo != null else null
	if scale is Dictionary:
		var s: Dictionary = scale
		made = made.scaled(float(s.get("d0", 1.0)), float(s.get("radius_m", 1.0)), float(s.get("impulse", 1.0)))
		made.source = StringName("%s+%s" % [made.source, cargo])
	_cache[key] = made
	return made


## Reads the table again on the next call (tests).
static func reload() -> void:
	_cache.clear()
	CapitalData.reload()


static func _blasts() -> Dictionary:
	return CapitalData.table("blasts")


static func _source_row(name: StringName) -> BlastSpec:
	var row: Variant = (_blasts().get("sources", {}) as Dictionary).get(String(name))
	if not (row is Dictionary):
		return null
	var r: Dictionary = row
	return _finish(BlastSpec.make(name, float(r.get("d0", 0.0)), float(r.get("radius_m", 0.0)), float(r.get("impulse", 0.0))))


# The table's flash energy and push cap on a new spec.
static func _finish(made: BlastSpec) -> BlastSpec:
	var b: Dictionary = _blasts()
	made.flash_j_per_d0 = float(b.get("flash_j_per_d0", BlastSpec.FLASH_J_PER_D0))
	made.push_cap_mps = float(b.get("push_cap_mps", BlastSpec.PUSH_CAP_MPS))
	return made
