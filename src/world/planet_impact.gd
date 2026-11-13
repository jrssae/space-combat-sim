class_name PlanetImpact
extends Node
## A planet's surface is the end of a ship (M6-T08, D67): a ship that hits a planet or moon, or drops below its atmosphere's
## top, is destroyed. Not a simulation of entry, a rule from the star system's data (each body's radius plus its
## `atmosphere_top_m`), checked every tick by the native core over every ship and capital row, the player's and the tier's
## included. An internal child of the `WorldFrame`; nothing to do while nothing pulls near the local space (every body is
## then far beyond it).

## After the hits (200) and before the rams (210): a ship that met the planet this tick is gone before anything else reads it.
const PRIORITY: int = 205

var world: WorldFrame = null
## Ships this rule destroyed so far (a readout).
var destroyed: int = 0
## The last ship it destroyed and the body it hit, for the console ("" before the first).
var last: String = ""


func _init(p_world: WorldFrame) -> void:
	world = p_world
	name = "PlanetImpact"
	process_physics_priority = PRIORITY


func _physics_process(_delta: float) -> void:
	if world == null or world.star_system == null or not world.gravity_active():
		return
	var hits: PackedInt64Array = world.impacts()
	for k: int in range(0, hits.size() - 1, 2):
		destroy(hits[k], int(hits[k + 1]))


## Destroys the ship or capital of instance `body_id` on body `index` (an ephemeris index). False when it has no live hull.
func destroy(body_id: int, index: int) -> bool:
	if not is_instance_id_valid(body_id):
		return false
	var body := instance_from_id(body_id) as Node
	var hull: Damageable = Damageable.of(body)
	if hull == null or not hull.kill(HitInfo.CAUSE_PLANET):
		return false
	destroyed += 1
	last = "%s on %s" % [body.name, world.star_system.display_name(world.star_system.id_at(index))]
	return true
