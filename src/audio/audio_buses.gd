class_name AudioBuses
extends RefCounted
## The four audio buses and what feeds them (architecture §18, D57): `Master` over `SFX`, `UI` and `Comms`. Menu sounds play on
## UI, radio sounds on Comms, everything else on SFX; each bus has a 0..1 volume setting. Pure, so the routing is tested
## without a sound device.

const MASTER: StringName = &"Master"
const SFX: StringName = &"SFX"
const UI: StringName = &"UI"
const COMMS: StringName = &"Comms"
const NAMES: Array[StringName] = [MASTER, SFX, UI, COMMS]
const SETTINGS: Dictionary[StringName, StringName] = {
	MASTER: &"master_volume", SFX: &"sfx_volume", UI: &"ui_volume", COMMS: &"comms_volume"}
## The radio's open and close clicks (`sfx_ui`, M5-T06); they sound on the Comms bus with the voice.
const COMMS_SOUNDS: Array[StringName] = [&"radio_open", &"radio_close"]
const SILENT_DB: float = -80.0


## The setting that sets `bus`'s volume.
static func setting_of(bus: StringName) -> StringName:
	return SETTINGS.get(bus, &"")


## The bus a volume setting belongs to, or "" for any other setting.
static func bus_of_setting(setting: StringName) -> StringName:
	for bus: StringName in SETTINGS:
		if SETTINGS[bus] == setting:
			return bus
	return &""


## The bus a sound plays on: menu sounds `UI`, the radio `Comms`, all else `SFX`.
static func bus_of_sound(sound: StringName) -> StringName:
	if COMMS_SOUNDS.has(sound):
		return COMMS
	if String(sound).begins_with("ui_"):
		return UI
	return SFX


## A bus's gain in dB for a 0..1 volume, silent at 0.
static func volume_db(linear: float) -> float:
	if linear <= 0.0:
		return SILENT_DB
	return linear_to_db(minf(linear, 1.0))
