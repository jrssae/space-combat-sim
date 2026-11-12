class_name TargetPreviewModel
extends RefCounted
## What the target menu's preview panel says about the highlighted entry (architecture §18.20, M5-T43), pure: a title in the IFF
## colour, a line of class and faction, the rows under them and which hull to draw. Read once per highlight (the game is paused
## while the menu shows). The rows a kind of entry gets are `FIELDS`: adding or dropping a line is one entry there.

enum Kind { NONE, SHIP, BEACON, OBJECTIVE, UNKNOWN }

## The rows of each kind, top to bottom. A field with nothing to say (a hull without pod mounts) gives no row.
const FIELDS: Dictionary = {
	Kind.NONE: [],
	Kind.SHIP: [&"hull", &"range", &"closing", &"cargo"],
	Kind.BEACON: [&"range", &"closing"],
	Kind.OBJECTIVE: [&"text", &"range"],
	Kind.UNKNOWN: [&"range", &"closing"],
}
## What the pilot reads for each hull (its asset id); an unlisted one reads as its id.
const CLASS_NAMES: Dictionary = {
	"starfury_aurora": "Aurora Starfury",
	"raider_fighter": "Delta-V raider",
	"saturn_3_freighter": "Saturn 3 freighter",
	"saturn_4_transport": "Saturn 4 transport",
	"saturn_4_tanker": "Saturn 4 tanker",
	"saturn_8_transport": "Saturn 8 transport",
	"saturn_8_tanker": "Saturn 8 tanker",
	"skylark_transport": "Skylark transport",
	"narn_transport": "Narn transport",
	"centauri_brezebel": "Brezebel transport",
	"brakiri_bokmai": "Bokmai hauler",
	"nav_buoy": "Nav buoy",
}
const FLAG_ATTACKING: String = "ATTACKING YOU"
## The pilot behaviours (`PilotBrain.describe`) that are an attack on their target.
const ATTACK_BEHAVIOURS: Array[String] = ["attack", "ram"]
## Shown in the hull's place for a contact that cannot be told apart.
const NO_ID: String = "NO ID"
const OBJECTIVE_SUBTITLE: String = "Mission objective"
const UNKNOWN_SUBTITLE: String = "No transponder"

var kind: Kind = Kind.NONE
## The marker's id (`TargetInfo.id`), 0 for a bare place or nothing.
var target_id: int = 0
var title: String = ""
var title_color: Color = Factions.HUD_LINE_COLOR
var subtitle: String = ""
## The asset whose hull the panel draws; "" draws `placeholder` instead (or nothing).
var hull_id: String = ""
var placeholder: String = ""
## One line over the drawing, "" for none.
var flag: String = ""
## `{field, label, value}` each, with `bar` (0..1) and `color` on a bar row; the `text` row has no label and may wrap.
var rows: Array[Dictionary] = []


## "+120 m/s" closing, "-40 m/s" opening.
static func closing_text(closing_mps: float) -> String:
	return "%+.0f m/s" % (0.0 if absf(closing_mps) < 0.5 else closing_mps)


## Whether a pilot doing `behaviour` (in `state`) is attacking the target it has selected. A ship that merely has the pilot
## selected (an idle one, one running away) is not.
static func is_attacking(behaviour: String, state: String = "") -> bool:
	return ATTACK_BEHAVIOURS.has(behaviour) or (behaviour == "aggro" and state.begins_with("attack"))


static func class_text(asset_id: String) -> String:
	return String(CLASS_NAMES.get(asset_id, asset_id.capitalize()))


## Nothing to draw: a blank panel, or the "none" entry with what picking it does.
static func none(p_title: String = "", p_subtitle: String = "") -> TargetPreviewModel:
	var out := TargetPreviewModel.new()
	out.title = p_title
	out.title_color = Factions.UNIDENTIFIED_COLOR
	out.subtitle = p_subtitle
	return out


## A ship or a beacon from the menu's list, seen by a pilot of `own_faction` at `own_position` moving at `own_velocity`.
## `facts` is what the list does not carry: `asset_id` (the hull), `cargo_pods` and `cargo_mounts` (a hull with pod mounts),
## `attacking_you`. A contact too far to identify shows none of them.
static func contact(info: TargetInfo, own_position: Vector3, own_velocity: Vector3, own_faction: StringName,
		facts: Dictionary = {}) -> TargetPreviewModel:
	var out := TargetPreviewModel.new()
	out.target_id = info.id
	var readout: TargetReadout = TargetingSystem.compute_readout(info, own_position, own_velocity)
	var category: TargetCategories.Category = TargetCategories.category_of(info, own_position, own_faction)
	var asset_id: String = String(facts.get("asset_id", ""))
	if category == TargetCategories.Category.UNKNOWN:
		out.kind = Kind.UNKNOWN
		out.title = TargetMenu.UNKNOWN_LABEL
		out.title_color = Factions.UNIDENTIFIED_COLOR
		out.subtitle = UNKNOWN_SUBTITLE
		out.placeholder = NO_ID
	else:
		out.kind = Kind.BEACON if category == TargetCategories.Category.NAVIGATION else Kind.SHIP
		out.title = info.display_name.to_upper()
		out.title_color = Factions.hud_color(Factions.relation(own_faction, info.faction))
		out.subtitle = " · ".join(PackedStringArray([class_text(asset_id), Factions.table().display_name(info.faction)])) \
				if not asset_id.is_empty() else Factions.table().display_name(info.faction)
		out.hull_id = asset_id
		if out.kind == Kind.SHIP and bool(facts.get("attacking_you", false)):
			out.flag = FLAG_ATTACKING
	var values: Dictionary = {"hull": info.hull_fraction, "range": readout.range_m, "closing": readout.closing_mps,
			"cargo_pods": int(facts.get("cargo_pods", -1)), "cargo_mounts": int(facts.get("cargo_mounts", 0))}
	out._fill(values)
	return out


## One of the mission's objectives as the menu lists them (`{text, label, target_id, position}`); `asset_id` is its actor's
## hull when it names one in play.
static func objective(entry: Dictionary, own_position: Vector3, asset_id: String = "") -> TargetPreviewModel:
	var out := TargetPreviewModel.new()
	out.kind = Kind.OBJECTIVE
	out.target_id = int(entry.get("target_id", 0))
	out.title = str(entry.get("label", "")).to_upper()
	out.title_color = TargetCategories.COLORS[TargetCategories.Category.OBJECTIVES]
	out.subtitle = OBJECTIVE_SUBTITLE
	out.hull_id = asset_id
	var at: Vector3 = entry.get("position", own_position)
	out._fill({"text": str(entry.get("text", "")), "range": TargetingSystem.range_between(own_position, at)})
	return out


## The row of `field`, or null when there is none.
func row(field: StringName) -> Variant:
	for entry: Dictionary in rows:
		if entry["field"] == field:
			return entry
	return null


func _fill(values: Dictionary) -> void:
	for field: StringName in FIELDS[kind]:
		var entry: Dictionary = _row(field, values)
		if not entry.is_empty():
			rows.append(entry)


# One field's row from the entry's values; empty when the entry has nothing for it.
static func _row(field: StringName, values: Dictionary) -> Dictionary:
	match field:
		&"hull":
			var fraction: float = float(values.get("hull", -1.0))
			if fraction < 0.0:
				return {}
			fraction = clampf(fraction, 0.0, 1.0)
			return {"field": field, "label": "HULL", "value": "%d %%" % roundi(fraction * 100.0), "bar": fraction,
					"color": HudLayout.hull_color(fraction)}
		&"range":
			return {"field": field, "label": "RANGE", "value": TargetMenu.range_text(float(values.get("range", 0.0)))}
		&"closing":
			return {"field": field, "label": "CLOSING", "value": closing_text(float(values.get("closing", 0.0)))}
		&"cargo":
			var mounts: int = int(values.get("cargo_mounts", 0))
			if int(values.get("cargo_pods", -1)) < 0 or mounts <= 0:
				return {}
			return {"field": field, "label": "CARGO PODS", "value": "%d of %d" % [int(values["cargo_pods"]), mounts]}
		&"text":
			var text: String = str(values.get("text", ""))
			return {"field": field, "label": "", "value": text} if not text.is_empty() else {}
	return {}
