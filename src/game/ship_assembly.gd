class_name ShipAssembly
extends RefCounted
## Builds a fighting ship from a `ShipSpec` (architecture §15.2): the one path for the player and for AI ships. It
## creates the `Ship`, its `ThrusterVisuals` (tinted by `engine_glow_color`), `PulseCannon` (from the spec's
## `WeaponSpec`), a `Damageable` (hull from `ShipSpec.hull_max`, god mode honoured for the player only) and a
## `Targetable`, and returns them as a `Combatant`. The caller then spawns `combatant.ship`
## through `World.spawn`; the components that need the ship's hardpoints are wired on the ship's `ready` signal.
##
##     var c: Combatant = ShipAssembly.build(spec, world, world.projectiles, {&"faction": Factions.RAIDERS,
##             &"display_name": "RAIDER 1", &"force_assist": true})
##     world.spawn(c.ship, position, basis)
##
## Options (all optional):
## - `faction` (StringName, default `neutral`): the Targetable's faction and the targeting system's own faction.
## - `display_name` (String, default ""): what the pilot reads on the target bracket.
## - `console_owner` (bool, default false): the player's ship; it registers the console providers (D27).
## - `is_player` (bool, default `console_owner`).
## - `force_assist` (bool, default false): AI ships fly with flight assist always on.

const OPT_FACTION: StringName = &"faction"
const OPT_DISPLAY_NAME: StringName = &"display_name"
const OPT_CONSOLE_OWNER: StringName = &"console_owner"
const OPT_IS_PLAYER: StringName = &"is_player"
const OPT_FORCE_ASSIST: StringName = &"force_assist"


static func build(spec: ShipSpec, world: WorldFrame, projectiles_parent: Node3D, opts: Dictionary = {}) -> Combatant:
	assert(spec != null and projectiles_parent != null, "ShipAssembly.build: spec and projectiles_parent are required")
	var console_owner: bool = bool(opts.get(OPT_CONSOLE_OWNER, false))
	var combatant := Combatant.new()
	combatant.faction = StringName(opts.get(OPT_FACTION, Factions.NEUTRAL))
	combatant.display_name = String(opts.get(OPT_DISPLAY_NAME, ""))
	combatant.is_player = bool(opts.get(OPT_IS_PLAYER, console_owner))

	var ship: Ship = Ship.create(spec, world)
	ship.console_owner = console_owner
	ship.force_assist = bool(opts.get(OPT_FORCE_ASSIST, false))
	combatant.ship = ship
	(ship.get_node("Targeting") as TargetingController).system.own_faction = combatant.faction

	var thrusters := ThrusterVisuals.new()
	thrusters.name = "ThrusterVisuals"
	thrusters.glow_color = spec.engine_glow_color
	ship.get_node("Thrusters").add_child(thrusters)
	combatant.thrusters = thrusters

	var cannon := PulseCannon.new()
	cannon.name = "PulseCannon"
	ship.get_node("Guns").add_child(cannon)
	combatant.cannon = cannon

	var damageable := Damageable.new()
	damageable.name = "Damageable"
	ship.add_child(damageable)
	combatant.damageable = damageable

	var targetable := Targetable.new()
	targetable.name = "Targetable"
	targetable.display_name = combatant.display_name
	targetable.faction = combatant.faction
	ship.add_child(targetable)
	combatant.targetable = targetable

	ship.ready.connect(_wire.bind(combatant, projectiles_parent, console_owner), CONNECT_ONE_SHOT)
	return combatant


# The ship is ready: its layout and muzzles exist now.
static func _wire(combatant: Combatant, projectiles_parent: Node3D, console_owner: bool) -> void:
	var ship: Ship = combatant.ship
	combatant.thrusters.setup(ship.get_layout(), ship.get_flight_output)
	combatant.damageable.setup(ship.get_hardpoints().collision, ship.spec.hull_max, combatant.faction,
			combatant.is_player, console_owner)
	var muzzles: Array[Node3D] = ship.get_muzzles()
	if muzzles.is_empty():
		push_warning("ShipAssembly: %s has no muzzles; its cannon cannot fire" % ship.spec.asset_id)
		return
	combatant.cannon.setup(ship, muzzles, projectiles_parent, ship.spec.weapon, console_owner, combatant.faction)
