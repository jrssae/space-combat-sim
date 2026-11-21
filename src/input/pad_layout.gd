class_name PadLayout
extends RefCounted
## The face layout of a gamepad (M10-T63): which printed labels its buttons wear, and whether Godot reports its face buttons
## by label instead of by position. Profile bindings are positional (the Xbox 360 layout the game was built on: `a` is the
## bottom face button, `b` right, `x` left, `y` top), so only the words change per layout, plus one swap for Nintendo pads.
##
## Why Nintendo pads need the swap: Godot 4.5+ reads pads through SDL3, which by default lets a Nintendo pad's labels win
## (SDL_GAMECONTROLLER_USE_BUTTON_LABELS), so the right button, printed A, arrives as `JOY_BUTTON_A` and the bottom one,
## printed B, as `JOY_BUTTON_B`. Swapping A/B and X/Y at the input-source layer keeps bindings positional. Pure: the
## active layout is set by `Joypads`, never read from `Input` here.

const AUTO: StringName = &"auto"
const XBOX_360: StringName = &"xbox360"
const XBOX_ONE: StringName = &"xbox_one"
const SWITCH: StringName = &"switch"
const PLAYSTATION: StringName = &"playstation"
const GENERIC: StringName = &"generic"

## What the settings accept: `AUTO`, then the layouts in the order the menu cycles them.
const LAYOUTS: Array[StringName] = [XBOX_360, XBOX_ONE, SWITCH, PLAYSTATION, GENERIC]
const CHOICES: Array[StringName] = [AUTO, XBOX_360, XBOX_ONE, SWITCH, PLAYSTATION, GENERIC]

const VENDOR_MICROSOFT: int = 0x045e
const VENDOR_SONY: int = 0x054c
const VENDOR_NINTENDO: int = 0x057e
# Xbox 360 family product ids (wired and wireless receiver); any other Microsoft pad is taken as an Xbox One/Series.
const _XBOX_360_PRODUCTS: Array[int] = [0x028e, 0x028f, 0x0291, 0x0719]

const _NAMES: Dictionary = {
	AUTO: "Auto", XBOX_360: "Xbox 360", XBOX_ONE: "Xbox One/Series", SWITCH: "Nintendo Switch",
	PLAYSTATION: "PlayStation", GENERIC: "Generic",
}
# Printed labels that differ from the Xbox 360's, by layout then by the Xbox 360 part they sit on. Generic keeps the Xbox
# words: the game's own layout is what an unknown pad is assumed to follow.
const _TAGS: Dictionary = {
	XBOX_ONE: {&"back": "View", &"start": "Menu"},
	SWITCH: {&"a": "B", &"b": "A", &"x": "Y", &"y": "X", &"lb": "L", &"rb": "R", &"lt": "ZL", &"rt": "ZR",
			&"back": "-", &"start": "+"},
	PLAYSTATION: {&"a": "Cross", &"b": "Circle", &"x": "Square", &"y": "Triangle", &"lb": "L1", &"rb": "R1", &"lt": "L2",
			&"rt": "R2", &"back": "Share", &"start": "Options"},
}
const _FACE_SWAP: Dictionary = {0: 1, 1: 0, 2: 3, 3: 2}

## The layout in use now, kept up to date by `Joypads` from the setting and the pad that is connected.
static var active: StringName = XBOX_360


## The layout a pad most likely has, from its name and SDL GUID; `GENERIC` for one nothing recognises.
static func detect(pad_name: String, guid: String) -> StringName:
	var lowered: String = pad_name.to_lower()
	var vendor: int = vendor_of(guid)
	if vendor == VENDOR_NINTENDO or _has_any(lowered, ["nintendo", "switch", "pro controller", "joy-con"]):
		return SWITCH
	if vendor == VENDOR_SONY or _has_any(lowered, ["playstation", "dualshock", "dualsense", "ps4", "ps5", "ps3"]):
		return PLAYSTATION
	if _has_any(lowered, ["xbox one", "xbox series", "series x", "series s"]):
		return XBOX_ONE
	if _has_any(lowered, ["xbox 360", "x360", "x-box", "xinput"]):
		return XBOX_360
	if vendor == VENDOR_MICROSOFT:
		return XBOX_360 if _XBOX_360_PRODUCTS.has(product_of(guid)) else XBOX_ONE
	if lowered.contains("xbox"):
		return XBOX_ONE
	return GENERIC


## The layout in force for a setting value: the setting itself, or for `AUTO` what was detected (Xbox 360 with no pad).
static func resolve(setting: StringName, detected: StringName) -> StringName:
	if LAYOUTS.has(setting):
		return setting
	return detected if LAYOUTS.has(detected) else XBOX_360


## "Xbox 360", "Nintendo Switch"...
static func display_name(layout: StringName) -> String:
	return _NAMES.get(layout, String(layout))


## "Auto (detected: Nintendo Switch)" for `AUTO`, else the layout's name.
static func setting_text(setting: StringName, detected: StringName) -> String:
	if setting == AUTO:
		return "Auto (detected: %s)" % display_name(resolve(AUTO, detected))
	return display_name(setting)


## The label printed on a pad part (`a`, `lb`, `start`...) for `layout`; the Xbox 360 word `base` stands where the layout
## prints the same.
static func tag(layout: StringName, widget: StringName, base: String) -> String:
	var table: Dictionary = _TAGS.get(layout, {})
	return table.get(widget, base)


## True where Godot reports the face buttons by label, so bindings need `button_index` to stay positional.
static func swaps_face_buttons(layout: StringName) -> bool:
	return layout == SWITCH


## The button index to read or record for `index` under `layout`: A/B and X/Y trade places for a pad that reports by label.
## It is its own inverse, so it turns a bound index into the raw one and a raw press into the bound one.
static func button_index(layout: StringName, index: int) -> int:
	return _FACE_SWAP.get(index, index) if swaps_face_buttons(layout) else index


## The vendor id an SDL GUID carries (bytes 4-5 hold it when bytes 6-7 are zero), or 0 when it has none.
static func vendor_of(guid: String) -> int:
	return _le16(guid, 8) if _has_ids(guid) else 0


static func product_of(guid: String) -> int:
	return _le16(guid, 16) if _has_ids(guid) else 0


# SDL3 and SDL2 GUIDs with ids: bus(4) crc(4) vendor(4 hex) 0000 product(4 hex) 0000 ... Older ones put a name there instead.
static func _has_ids(guid: String) -> bool:
	return guid.length() == 32 and guid.is_valid_hex_number() and guid.substr(12, 4) == "0000" and guid.substr(20, 4) == "0000"


static func _le16(guid: String, at: int) -> int:
	return ("0x" + guid.substr(at + 2, 2) + guid.substr(at, 2)).hex_to_int()


static func _has_any(text: String, needles: Array[String]) -> bool:
	for needle: String in needles:
		if text.contains(needle):
			return true
	return false
