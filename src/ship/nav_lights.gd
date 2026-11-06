class_name NavLights
extends RefCounted
## What a ship's running lights are (architecture §7.3, M3-T27, Q27): the three markers, worked out from its `nav_lights` hardpoints.
## Port is red on -X and starboard green on +X, the standard; all steady. The cabin's red glow is the canopy glass's own (its emissive
## map, M4-T30b), and the cockpit's red lamp is the ship's cabin emitter. Pure.

## HDR marker colours: each is read at several km as a coloured point.
const PORT_COLOR: Color = Color(3.2, 0.12, 0.08)
const STARBOARD_COLOR: Color = Color(0.1, 2.8, 0.5)
const TOP_COLOR: Color = Color(2.8, 2.8, 2.6)
## The dim red of the lamp that lights the cockpit frame in the first-person view (`settings.cockpit_light_energy` scales it).
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
