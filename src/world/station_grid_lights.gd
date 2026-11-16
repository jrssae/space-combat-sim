class_name StationGridLights
extends Node
## The floodlights that wash the bow frame's heavy cannons and the tower's interceptor battery (M7-T57): the bow faces away from the
## sun, so without them the guns the tour's Defense Grid stop shows stand in shadow. One `LightEmitter` just ahead of and above each
## mount enters the `LightRig`'s competition like the bays' lamps, so only the guns the camera is near hold slots. Console: provider
## `grid_lights`.

const PROVIDER: StringName = &"grid_lights"
## The mounts lit, by name: the two heavy cannons and the bow tower's battery.
const MOUNTS: Array[String] = ["H1", "H2", "I5"]
const COLOUR: Color = Color(1.0, 0.89, 0.76)
const ENERGY: float = 16.0
const RANGE_M: float = 140.0
const ATTENUATION: float = 1.0
## Where a flood stands from its mount: toward the bow (the side the guns face) and above.
const AHEAD_M: float = 24.0
const ABOVE_M: float = 16.0

var emitters: Array[LightEmitter] = []
var _rig: LightRig = null


## The floods of `station`'s grid mounts, or null when its hardpoints list none of them.
static func make(station: Station) -> StationGridLights:
	var made := StationGridLights.new()
	made.name = "StationGridLights"
	if station.hardpoints == null:
		made.free()
		return null
	for name: String in MOUNTS:
		var mount: Dictionary = station.hardpoints.mount(name)
		if mount.is_empty():
			continue
		var emitter := LightEmitter.new("grid_flood_" + name, LightEmitter.PRIORITY_CABIN, COLOUR, ENERGY, RANGE_M, ATTENUATION)
		emitter.anchor = station
		var at: Vector3 = mount["position"]
		emitter.offset = at + (station.drum_origin if str(mount.get("body", "")) == StationHardpoints.DRUM else Vector3.ZERO) \
				+ Vector3(0.0, ABOVE_M, -AHEAD_M)
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
		&"floods": {"get": func() -> int: return emitters.size(), "doc": "The floodlights on the heavy cannons and the bow tower"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _rig != null and is_instance_valid(_rig):
		for emitter: LightEmitter in emitters:
			_rig.remove_emitter(emitter)
	_rig = null
