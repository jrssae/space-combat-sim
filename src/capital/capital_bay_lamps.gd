class_name CapitalBayLamps
extends Node
## The red lamps of a capital's open bays (M10-T72, Q68): a bay with no door (the Omega's, the Nova's) is lit by its own `bay`
## light alone, as Babylon 5's docking bay is, since the sun's light leaves its hall out. Each is a `LightEmitter` on the ship that
## lights only the interior layer, so it never shows through the hull's walls; it competes for the rig's slots like any emitter.
## A bay with a door lights its hall as the door opens (`BayDoorNode`). The lamps dim with the ship's glow when it is disabled.

var emitters: Array[LightEmitter] = []
var _rig: LightRig = null


## The lamps of the doorless bays in `hardpoints` (body frame), on `ship`; null when there are none.
static func make(ship: Node3D, hardpoints: Dictionary) -> CapitalBayLamps:
	var doored: Dictionary = {}
	for door: Dictionary in BayDoors.doors_of(hardpoints):
		doored[BayDoors.bay_of(str(door.get("name", "")))] = true
	var made := CapitalBayLamps.new()
	made.name = "BayLamps"
	for raw: Variant in hardpoints.get("bays", []) if hardpoints.get("bays") is Array else []:
		var bay: String = str((raw as Dictionary).get("name", "")) if raw is Dictionary else ""
		var light: Dictionary = BayDoors.light_of(hardpoints, bay)
		if bay.is_empty() or doored.has(bay) or light.is_empty():
			continue
		var c: Array = light.get("colour", [1.0, 0.0, 0.0]) as Array
		var at: Array = light.get("position", [0.0, 0.0, 0.0]) as Array
		var emitter := LightEmitter.new(str(light.get("name", "")), LightEmitter.PRIORITY_CABIN, Color(float(c[0]), float(c[1]), float(c[2])),
				BayDoors.LIGHT_ENERGY, float(light.get("range_m", 50.0)), BayDoors.LIGHT_ATTENUATION)
		emitter.anchor = ship
		emitter.offset = Vector3(float(at[0]), float(at[1]), float(at[2]))
		emitter.interior_only = true
		made.emitters.append(emitter)
	if made.emitters.is_empty():
		made.free()
		return null
	return made


## The lamps at `level` of their strength (1 lit, 0 dark).
func set_level(level: float) -> void:
	for emitter: LightEmitter in emitters:
		emitter.energy = BayDoors.LIGHT_ENERGY * clampf(level, 0.0, 1.0)


func _enter_tree() -> void:
	_rig = LightRig.of(self)
	if _rig != null:
		for emitter: LightEmitter in emitters:
			_rig.add_emitter(emitter)


func _exit_tree() -> void:
	if _rig != null and is_instance_valid(_rig):
		for emitter: LightEmitter in emitters:
			_rig.remove_emitter(emitter)
	_rig = null
