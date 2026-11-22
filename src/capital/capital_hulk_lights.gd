class_name CapitalHulkLights
extends RefCounted
## A disabled capital's lights going out (M10-T10, D12.7): its glowing surfaces (windows, running lights, engine glow, an
## organic hull's veins) get copies of their materials of its own, so this one ship's glow fades while its sisters, which
## share the materials, stay lit. Made when the ship is disabled, given back when it is whole again. Per event, never per tick.

## The glow's strength on the hull shaders (`emission_energy`) and on the sheen layer's veins (`glow_energy`).
const SHADER_ENERGIES: Array[StringName] = [&"emission_energy", &"glow_energy"]

## The level last applied, 0 to 1.
var level: float = 1.0

# One glowing surface: the node, its surface (-1: its material override), what was there before, the copy and its energies.
var _entries: Array[Dictionary] = []


## The glowing surfaces of every mesh under `roots`, each given its own copy of its material.
static func collect(roots: Array[Node]) -> CapitalHulkLights:
	var out := CapitalHulkLights.new()
	for root: Node in roots:
		if root != null:
			out._walk(root)
	return out


## How many surfaces it dims.
func count() -> int:
	return _entries.size()


## Sets the glow to `p_level` of its strength as built.
func apply(p_level: float) -> void:
	if is_equal_approx(p_level, level):
		return
	level = p_level
	for entry: Dictionary in _entries:
		var material: Material = entry["copy"]
		var base: Dictionary = entry["base"]
		for key: StringName in base:
			if material is StandardMaterial3D:
				(material as StandardMaterial3D).emission_energy_multiplier = float(base[key]) * level
			else:
				(material as ShaderMaterial).set_shader_parameter(key, float(base[key]) * level)


## Gives every surface its own material back (the ship is whole again).
func release() -> void:
	for entry: Dictionary in _entries:
		var node: MeshInstance3D = entry["node"]
		if not is_instance_valid(node):
			continue
		if int(entry["surface"]) < 0:
			node.material_override = entry["before"]
		else:
			node.set_surface_override_material(int(entry["surface"]), entry["before"])
	_entries.clear()
	level = 1.0


func _walk(node: Node) -> void:
	if node is MeshInstance3D:
		_take(node as MeshInstance3D)
	for child: Node in node.get_children():
		_walk(child)


func _take(node: MeshInstance3D) -> void:
	if node.material_override != null:
		_add(node, -1, node.material_override, node.material_override)
		return
	if node.mesh == null:
		return
	for i: int in node.mesh.get_surface_count():
		var active: Material = node.get_active_material(i)
		_add(node, i, active, node.get_surface_override_material(i))


func _add(node: MeshInstance3D, surface: int, material: Material, before: Material) -> void:
	var base: Dictionary = _energies(material)
	if base.is_empty():
		return
	var copy: Material = material.duplicate() as Material
	if surface < 0:
		node.material_override = copy
	else:
		node.set_surface_override_material(surface, copy)
	_entries.append({"node": node, "surface": surface, "before": before, "copy": copy, "base": base})


# The glow strengths a material has, by name; empty when it does not glow.
static func _energies(material: Material) -> Dictionary:
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		return {&"emission_energy_multiplier": standard.emission_energy_multiplier} if standard.emission_enabled and standard.emission_energy_multiplier > 0.0 else {}
	var out: Dictionary = {}
	if material is ShaderMaterial:
		for key: StringName in SHADER_ENERGIES:
			var value: Variant = (material as ShaderMaterial).get_shader_parameter(key)
			if (value is float or value is int) and float(value) > 0.0:
				out[key] = float(value)
	return out
