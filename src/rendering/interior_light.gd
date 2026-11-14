class_name InteriorLight
extends RefCounted
## Puts a ship in or out of the interior light (M7): inside a station's hall or bay its meshes go on `LightRig.INTERIOR_LAYER`,
## which the key star's light leaves out, so only the lamps, glow and ambient light it, as they do the walls round it; outside
## they go back on the first layer. Pure: `LaunchDirector` calls it for a fighter on its rack, `InteriorZones` for a ship flying
## into a bay.

const OUTSIDE_LAYER: int = 1


## `layers` moved in or out: the first layer swapped for the interior one, every other layer kept.
static func moved(layers: int, inside: bool) -> int:
	if inside and (layers & OUTSIDE_LAYER) != 0:
		return (layers & ~OUTSIDE_LAYER) | LightRig.INTERIOR_LAYER
	if not inside and (layers & LightRig.INTERIOR_LAYER) != 0:
		return (layers & ~LightRig.INTERIOR_LAYER) | OUTSIDE_LAYER
	return layers


## Moves every mesh under `root` (and `root` itself) in or out.
static func set_inside(root: Node, inside: bool) -> void:
	if root is GeometryInstance3D:
		var mesh := root as GeometryInstance3D
		mesh.layers = moved(mesh.layers, inside)
	for child: Node in root.get_children():
		set_inside(child, inside)


## Whether any mesh under `root` is in the interior light.
static func is_inside(root: Node) -> bool:
	if root is GeometryInstance3D and ((root as GeometryInstance3D).layers & LightRig.INTERIOR_LAYER) != 0:
		return true
	for child: Node in root.get_children():
		if is_inside(child):
			return true
	return false
