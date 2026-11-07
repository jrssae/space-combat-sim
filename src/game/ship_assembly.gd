class_name ShipAssembly
extends RefCounted
## Builds a fighting ship from a `ShipSpec` (architecture §15.2): the one path for the player and for AI ships. It
## creates the `Ship`, its `ThrusterVisuals` (tinted by `engine_glow_color`), `PulseCannon` (from the spec's
## `WeaponSpec`), a `Damageable` (hull from `ShipSpec.hull_max`, ram limits from `ram_safe_dv_mps` / `ram_lethal_dv_mps`,
## god mode honoured for the player only) and a
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
## - `is_player` (bool, default `console_owner`). Only the player's targeting rebuilds its whole candidate list every tick, for
##   the HUD and the radar (`TargetingController.keeps_candidates`, M4-T02).
## - `force_assist` (bool, default false): AI ships fly with flight assist always on.
## - `ai` (bool, default false): adds an `AiPilotDriver` (priority -10) that flies the ship with whatever `PilotBrain` it
##   is given (`combatant.driver.brain`); with no brain it does nothing.
## - `lean` (bool, default `ai`): builds the AI ship's lean set of nodes (M4-T11, architecture §17.10, `Ship.lean`): its plumes
##   as one multimesh on the body, its markers as another, its collision shapes without nodes, no cockpit.
## - `civilian` (bool, default false): a civilian ship (M5-T21); other civilians' turrets defend it too.
##
## A hull whose hardpoints list `turrets[]` (M5-T21, D61) gets a `TurretMount` per entry when it is ready, firing the
## spec's `turret_weapon` (the light turret when it has none) for its faction, in `combatant.turrets`, each showing the
## asset's turret model (its manifest's `turret` entry).

const OPT_FACTION: StringName = &"faction"
const OPT_DISPLAY_NAME: StringName = &"display_name"
const OPT_CONSOLE_OWNER: StringName = &"console_owner"
const OPT_IS_PLAYER: StringName = &"is_player"
const OPT_FORCE_ASSIST: StringName = &"force_assist"
const OPT_AI: StringName = &"ai"
const OPT_LEAN: StringName = &"lean"
const OPT_CIVILIAN: StringName = &"civilian"
## The turrets' gun when the spec names none.
const DEFAULT_TURRET_WEAPON: String = "res://assets/weapons/turret_light.tres"


static func build(spec: ShipSpec, world: WorldFrame, projectiles_parent: Node3D, opts: Dictionary = {}) -> Combatant:
	assert(spec != null and projectiles_parent != null, "ShipAssembly.build: spec and projectiles_parent are required")
	var console_owner: bool = bool(opts.get(OPT_CONSOLE_OWNER, false))
	var combatant := Combatant.new()
	combatant.faction = StringName(opts.get(OPT_FACTION, Factions.NEUTRAL))
	combatant.display_name = String(opts.get(OPT_DISPLAY_NAME, ""))
	combatant.is_player = bool(opts.get(OPT_IS_PLAYER, console_owner))
	combatant.civilian = bool(opts.get(OPT_CIVILIAN, false))

	var ship: Ship = Ship.create(spec, world)
	ship.console_owner = console_owner
	ship.lean = bool(opts.get(OPT_LEAN, opts.get(OPT_AI, false))) and not console_owner
	ship.force_assist = bool(opts.get(OPT_FORCE_ASSIST, false))
	combatant.ship = ship
	var targeting := ship.get_node("Targeting") as TargetingController
	targeting.system.own_faction = combatant.faction
	targeting.keeps_candidates = combatant.is_player  # only the player's list is read every frame (M4-T02)
	if combatant.is_player:
		AiPilotDriver.register_player(combatant)  # AI ships near it think every tick (M4-T04)

	var thrusters := ThrusterVisuals.new()
	thrusters.name = "ThrusterVisuals"
	thrusters.glow_color = spec.engine_glow_color
	thrusters.own_ship = combatant.is_player
	thrusters.instanced = ship.lean
	if ship.lean:
		ship.add_child(thrusters)  # on the body: the lean ship drops the empty holder
	else:
		ship.get_node("Thrusters").add_child(thrusters)
	combatant.thrusters = thrusters

	var cannon := PulseCannon.new()
	cannon.name = "PulseCannon"
	ship.get_node("Guns").add_child(cannon)
	combatant.cannon = cannon

	if bool(opts.get(OPT_AI, false)):
		var driver := AiPilotDriver.new()
		driver.name = "AiPilotDriver"
		driver.combatant = combatant
		driver.world = world
		ship.add_child(driver)
		combatant.driver = driver

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
			combatant.is_player, console_owner, ship.spec.damage_layout)
	combatant.damageable.ram_safe_dv_mps = ship.spec.ram_safe_dv_mps
	combatant.damageable.ram_lethal_dv_mps = ship.spec.ram_lethal_dv_mps
	if combatant.civilian:
		SimCore.set_civilian(ship.get_instance_id(), true)
	_mount_turrets(combatant)
	if ship.lean:
		# No marker per muzzle (M4-T35): the cannon fires from the hardpoints' transforms, the World's pool flashes them.
		var transforms: Array[Transform3D] = ship.get_muzzle_transforms()
		if transforms.is_empty():
			push_warning("ShipAssembly: %s has no muzzles; its cannon cannot fire" % ship.spec.asset_id)
			return
		combatant.cannon.setup_transforms(ship, transforms, projectiles_parent, ship.spec.weapon, combatant.faction,
				MuzzleFlashPool.attach(ship.world))
		return
	var muzzles: Array[Node3D] = ship.get_muzzles()
	if muzzles.is_empty():
		if combatant.turrets.is_empty():  # a turreted hull without guns (a civilian) fights with its turrets only
			push_warning("ShipAssembly: %s has no muzzles; its cannon cannot fire" % ship.spec.asset_id)
		return
	combatant.cannon.setup(ship, muzzles, projectiles_parent, ship.spec.weapon, console_owner, combatant.faction)


# A mount per `turrets[]` entry of the hull's hardpoints (M5-T21); the mounts bind themselves to the core as they enter.
static func _mount_turrets(combatant: Combatant) -> void:
	var ship: Ship = combatant.ship
	var entries: Array[Dictionary] = ship.get_hardpoints().turrets if ship.get_hardpoints() != null else []
	if entries.is_empty():
		return
	var weapon: WeaponSpec = ship.spec.turret_weapon
	if weapon == null:
		weapon = load(DEFAULT_TURRET_WEAPON) as WeaponSpec
	var model: Dictionary = TurretMount.model_for(ship.spec.asset_id)
	for entry: Dictionary in entries:
		var mount := TurretMount.create(entry, weapon, combatant.faction)
		mount.use_model(model)
		ship.add_child(mount)
		combatant.turrets.append(mount)
