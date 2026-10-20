class_name Combatant
extends RefCounted
## One fighting ship and the components `ShipAssembly` built for it (architecture §15.2): the handle the player's
## `Main`, the AI drivers, the pool and the destruction code pass around. Plain references, no logic beyond
## `apply_commands`.
##
## The components are created together, but the ones that need the ship's hardpoints (thruster layout, muzzles) are wired
## when the ship enters the tree and is ready, so spawn `ship` through `World.spawn` before relying on them.

var ship: Ship = null
var cannon: PulseCannon = null
var thrusters: ThrusterVisuals = null
var targetable: Targetable = null
## `Damageable` (M2-T03) and the AI's `AiPilotDriver` (M2-T07); null until those exist.
var damageable: Node = null
var driver: Node = null

var faction: StringName = Factions.NEUTRAL
var display_name: String = ""
var is_player: bool = false


## One tick of pilot input, for the player (from `InputAdapter`) and for an AI ship (from its brain) alike: the flight
## command and the combat command go to the ship, the combat command also to the cannon.
func apply_commands(flight: FlightCommand, combat: CombatCommand) -> void:
	ship.set_flight_command(flight)
	ship.set_combat_command(combat)
	cannon.set_combat_command(combat)
