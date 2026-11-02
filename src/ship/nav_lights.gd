class_name NavLights
extends RefCounted
## What a ship's running lights are (architecture §7.3, M3-T27, Q27): the three markers and the lights it carries for itself, worked
## out from its `nav_lights` hardpoints. Port is red on -X and starboard green on +X, the standard; all steady. Red and green are
## markers only; the top one also has a lamp over the hull, and the cabin glow stays on when the ship goes dark. Pure.

## HDR marker colours: each is read at several km as a coloured point.
const PORT_COLOR: Color = Color(3.2, 0.12, 0.08)
const STARBOARD_COLOR: Color = Color(0.1, 2.8, 0.5)
const TOP_COLOR: Color = Color(2.8, 2.8, 2.6)
## The light the top lamp throws on the hull, the red of the glow in the canopy, and the dimmer red of the lamp that lights the
## cockpit frame in the first-person view (`settings.cockpit_light_energy` scales it).
const TOP_LAMP_COLOR: Color = Color(1.0, 0.97, 0.9)
const CABIN_COLOR: Color = Color(1.0, 0.16, 0.1)
const CABIN_LAMP_COLOR: Color = Color(0.42, 0.07, 0.045)


## One entry per marker, port first: `name`, `position` (ship frame), `color`. Empty when the hull names no lights.
static func markers(nav: Dictionary) -> Array[Dictionary]:
	if nav.is_empty():
		return [] as Array[Dictionary]
	return [
		{"name": "Port", "position": nav["port"], "color": PORT_COLOR},
		{"name": "Starboard", "position": nav["starboard"], "color": STARBOARD_COLOR},
		{"name": "Top", "position": nav["top"], "color": TOP_COLOR},
	] as Array[Dictionary]


## The own lights of a ship's splat node, in the node's frame (`node_pose`: its pose relative to the ship): the white top lamp while
## `lit`, and the red cabin glow always. Empty when the hull names no lights.
static func own_lights(nav: Dictionary, lit: bool, top_energy: float, glow_level: float, glow_view_m: float,
		node_pose: Transform3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if nav.is_empty():
		return out
	if lit:
		out.append_array(GaussianOwnLights.surface(GaussianOwnLights.to_instance_frame(nav["top_lamp"] as Vector3, node_pose),
				TOP_LAMP_COLOR, top_energy, float(nav["top_lamp_range_m"])))
	out.append_array(GaussianOwnLights.glow(GaussianOwnLights.to_instance_frame(nav["cabin"] as Vector3, node_pose), CABIN_COLOR,
			glow_level, float(nav["cabin_range_m"]), glow_view_m))
	return out
