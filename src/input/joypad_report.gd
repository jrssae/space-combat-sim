class_name JoypadReport
extends RefCounted
## What the game knows about the gamepads (M8-T22, D88): the pads connected now and the last connect and disconnect
## events, worded for the log, the toast, the front end's notice and the `joypads` command. Pure: `Joypads` feeds it what
## Godot reports. It is diagnostics only; flight still reads pads through `InputSource`.

const START: StringName = &"start"
const CONNECTED: StringName = &"connected"
const DISCONNECTED: StringName = &"disconnected"

## Events kept for `joypads`.
const MAX_EVENTS: int = 16
## A pad Godot reports this soon after launch was there all along: it is logged, not announced.
const STARTUP_WINDOW_S: float = 1.0
## What a wireless pad's receiver needs before it shows up as a pad (the maintainer's took 6 to 40 s, D88).
const NONE_NOTICE: String = "No gamepad detected: keyboard and mouse work. A wireless pad must be switched on, and can take up to 40 s to appear."
const DOC_HINT: String = "docs/playtest.md, \"Gamepad not detected\""

var _pads: Dictionary = {}  # device id -> {"id", "name", "guid", "known"}
var _events: Array[Dictionary] = []
var _seen: int = 0


## A pad appeared. Returns the event, or {} when this pad was already listed (Godot repeats its start-up pads).
func note_connected(id: int, pad_name: String, guid: String, known: bool, time_s: float) -> Dictionary:
	if _pads.has(id) and String((_pads[id] as Dictionary)["guid"]) == guid:
		return {}
	var pad: Dictionary = {"id": id, "name": pad_name if not pad_name.is_empty() else "unnamed pad", "guid": guid, "known": known}
	_pads[id] = pad
	return _record(START if time_s < STARTUP_WINDOW_S else CONNECTED, pad, time_s)


## A pad went away. Godot has forgotten its name by then, so the event carries what was noted when it connected.
func note_disconnected(id: int, time_s: float) -> Dictionary:
	if not _pads.has(id):
		return {}
	var pad: Dictionary = _pads[id]
	_pads.erase(id)
	return _record(DISCONNECTED, pad, time_s)


func count() -> int:
	return _pads.size()


## The connected pads, by device id.
func pads() -> Array[Dictionary]:
	var ids: Array = _pads.keys()
	ids.sort()
	var out: Array[Dictionary] = []
	for id: int in ids:
		out.append((_pads[id] as Dictionary).duplicate())
	return out


## The layout the first connected pad looks like (`PadLayout.XBOX_360` with none).
func layout() -> StringName:
	var listed: Array[Dictionary] = pads()
	if listed.is_empty():
		return PadLayout.XBOX_360
	return PadLayout.detect(String(listed[0]["name"]), String(listed[0]["guid"]))


## Connected pads Godot has no button mapping for: their buttons may be laid out wrong.
func unmapped_count() -> int:
	var n: int = 0
	for pad: Dictionary in _pads.values():
		if not bool(pad["known"]):
			n += 1
	return n


## The last events, oldest first.
func events() -> Array[Dictionary]:
	return _events.duplicate()


## Every event since launch, including those `events` no longer holds.
func events_seen() -> int:
	return _seen


func last_event() -> Dictionary:
	return _events.back() if not _events.is_empty() else {}


## What the front end shows while no pad is connected; "" when one is.
func none_notice() -> String:
	return NONE_NOTICE if _pads.is_empty() else ""


## The toast for an event; "" for a pad that was there at launch.
static func toast_text(event: Dictionary) -> String:
	if event.is_empty() or event["kind"] == START:
		return ""
	if event["kind"] == DISCONNECTED:
		return "Gamepad disconnected: %s" % event["name"]
	var text: String = "Gamepad connected: %s" % event["name"]
	return text if bool(event["known"]) else text + " (no known button mapping)"


## "0: Generic X-Box pad  guid 0300...  mapping known".
static func pad_line(pad: Dictionary) -> String:
	return "%d: %s  guid %s  mapping %s" % [pad["id"], pad["name"], pad["guid"], "known" if bool(pad["known"]) else "unknown"]


## "12.3 s  connected  0: Generic X-Box pad  guid 0300...  mapping known".
static func event_line(event: Dictionary) -> String:
	if event.is_empty():
		return "none"
	return "%.1f s  %s  %s" % [event["time_s"], event["kind"], pad_line(event)]


## The log's lines once launch has settled: every pad, or that there is none.
func start_lines() -> PackedStringArray:
	if _pads.is_empty():
		return PackedStringArray(["none at start: keyboard and mouse work (%s)" % DOC_HINT])
	var lines := PackedStringArray(["%d at start" % _pads.size()])
	for pad: Dictionary in pads():
		lines.append("  " + pad_line(pad))
	return lines


## What `joypads` prints: the pads with their mapping, then the last events.
func summary_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if _pads.is_empty():
		lines.append("joypads: none connected")
		lines.append("  " + NONE_NOTICE)
		lines.append("  See %s." % DOC_HINT)
	else:
		lines.append("joypads: %d connected" % _pads.size())
		for pad: Dictionary in pads():
			lines.append("  " + pad_line(pad))
	lines.append("last events: %s" % ("none" if _events.is_empty() else "%d of %d" % [_events.size(), _seen]))
	for event: Dictionary in _events:
		lines.append("  " + event_line(event))
	return lines


func _record(kind: StringName, pad: Dictionary, time_s: float) -> Dictionary:
	var event: Dictionary = pad.duplicate()
	event["kind"] = kind
	event["time_s"] = time_s
	_events.append(event)
	if _events.size() > MAX_EVENTS:
		_events.pop_front()
	_seen += 1
	return event.duplicate()
