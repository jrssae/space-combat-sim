class_name BayLights
extends Node
## The main docking bay's red lamps down its mouth (M7-T25): the show's metallic grey walls read red-lit. Two `LightEmitter`s at
## the manifest's `main_docking_bay_red_*` lights (on the bay's axis, so the drum's turn does not move them) enter the `LightRig`'s
## competition for its slots like any emitter: near the mouth they win slots, at range they lose them and the walls keep only their
## faint baked red. T18 lights the station's other lights from the same list. Console: provider `bay_lights`.

const PROVIDER: StringName = &"bay_lights"
const ENERGY: float = 3.5
const RANGE_M: float = 55.0
const ATTENUATION: float = 1.2

var emitters: Array[LightEmitter] = []
var _rig: LightRig = null


## The lamps of `station`'s main docking bay, or null when its hardpoints list none.
static func make(station: Station) -> BayLights:
	var made := BayLights.new()
	made.name = "BayLights"
	for light: Dictionary in station.hardpoints.lights if station.hardpoints != null else []:
		var name: String = str(light.get("name", ""))
		if not name.begins_with("main_docking_bay_red_"):
			continue
		var emitter := LightEmitter.new(name, LightEmitter.PRIORITY_CABIN, light.get("colour", Color.RED) as Color, ENERGY, RANGE_M,
				ATTENUATION)
		emitter.anchor = station
		var at: Vector3 = light["position"]
		emitter.offset = at + (station.drum_origin if str(light.get("body", "")) == StationHardpoints.DRUM else Vector3.ZERO)
		made.emitters.append(emitter)
	if made.emitters.is_empty():
		made.free()
		return null
	return made


func _ready() -> void:
	_rig = LightRig.of(self)
	if _rig != null:
		for emitter: LightEmitter in emitters:
			_rig.add_emitter(emitter)
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"lamps": {"get": func() -> int: return emitters.size(), "doc": "The main docking bay's red lamps down its mouth"},
		&"lit": {"get": _lit, "doc": "Of them, holding one of the light rig's slots now"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _rig != null and is_instance_valid(_rig):
		for emitter: LightEmitter in emitters:
			_rig.remove_emitter(emitter)
	_rig = null


func _lit() -> int:
	if _rig == null or not is_instance_valid(_rig):
		return 0
	var n: int = 0
	for emitter: LightEmitter in _rig.picked():
		n += 1 if emitter != null and emitters.has(emitter) else 0
	return n
