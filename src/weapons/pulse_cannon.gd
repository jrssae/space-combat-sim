class_name PulseCannon
extends Node3D
## The ship's pulse cannons (architecture §6.3): a thin node around the pure `PulseCannonGate`. Each physics tick it
## reads the latest `CombatCommand` (`weapon_next` cycles the fire mode, `fire` is the held trigger), asks the gate
## which muzzles fire, and spawns a `Projectile` at each of them.
##
## Wiring (Main, M1-T15, does this; the cannon does not know the Ship class):
##
##     cannon.setup(ship_body, [left_muzzle, right_muzzle], world_projectiles_node)
##     cannon.set_combat_command(cmd)     # once per physics tick, with that tick's command
##
## A projectile leaves the muzzle's global position with `body.linear_velocity + forward * muzzle_speed_mps`, where
## forward is the body's -Z, so the shooter's own velocity is inherited. Projectiles go under `projectiles_parent`
## (`World/Projectiles`), never under the ship, so they stop following the ship the moment they leave it.
##
## `weapon_next` is a one-tick edge: it is remembered when `set_combat_command` receives it and used once, so a tick
## that runs without a fresh command never cycles the mode twice.
##
## The gate is paid from a `WeaponCapacitor` (M2-T14, defaults in that class): an empty capacitor stops the fire
## until it has recharged enough for the next shot. Its numbers move into the `WeaponSpec` with M2-T02.
##
## Console (architecture §6.4): provider `weapons` with `mode` (writable: `alternating` / `linked`), `cooldown_s` and
## `charge` (writable, 0..1: the capacitor), so `set weapons.mode linked` switches modes and `set weapons.charge 0`
## empties the capacitor.

## A shot left a muzzle: the muzzle index and the new projectile.
signal projectile_fired(muzzle_index: int, projectile: Projectile)

const PROJECTILE_SCENE: PackedScene = preload("res://src/weapons/projectile.tscn")
const MODE_CHOICES: Array[StringName] = [&"alternating", &"linked"]

## Muzzle speed relative to the shooter, m/s.
@export var muzzle_speed_mps: float = 400.0

var gate: PulseCannonGate = PulseCannonGate.new()

var _body: RigidBody3D = null
var _muzzles: Array[Node3D] = []
var _flashes: Array[MuzzleFlash] = []
var _projectiles_parent: Node3D = null
var _command: CombatCommand = null
var _weapon_next_pending: bool = false


func _init() -> void:
	gate.capacitor = WeaponCapacitor.new()


func _ready() -> void:
	DebugConsole.registry.register_provider(&"weapons", ConsoleVars.new({
		&"mode": {"get": func() -> StringName: return PulseCannonGate.mode_name(gate.mode),
				"set": func(value: Variant) -> void: gate.mode = PulseCannonGate.mode_from_name(StringName(str(value))),
				"type": TYPE_STRING_NAME, "choices": MODE_CHOICES,
				"doc": "Pulse cannon fire mode: alternating (4 Hz, one muzzle at a time) or linked (2 Hz, both)"},
		&"cooldown_s": {"get": func() -> float: return gate.cooldown_remaining(SimClock.now()), "unit": "s",
				"doc": "Time until the cannon can fire again"},
		&"charge": {"get": charge_fraction, "set": set_charge_fraction, "type": TYPE_FLOAT, "min": 0.0, "max": 1.0,
				"doc": "Capacitor charge, 0..1: each projectile costs some, it recharges with time, empty = no fire"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(_delta: float) -> void:
	step(SimClock.now())


## Called by Main with the ship body (position, velocity and nose come from it), the muzzle markers in muzzle-index
## order (the hardpoints' `muzzles`: left, right) and the node projectiles are added to. Adds a `MuzzleFlash` under
## each muzzle. Calling it again replaces the previous wiring.
func setup(body: RigidBody3D, muzzles: Array[Node3D], projectiles_parent: Node3D) -> void:
	assert(body != null and projectiles_parent != null, "PulseCannon.setup: body and projectiles_parent are required")
	assert(muzzles.size() == PulseCannonGate.MUZZLE_COUNT, "PulseCannon.setup: expected %d muzzles" % PulseCannonGate.MUZZLE_COUNT)
	for flash: MuzzleFlash in _flashes:
		if is_instance_valid(flash):
			if flash.get_parent() != null:
				flash.get_parent().remove_child(flash)
			flash.free()  # out of the tree already, so freeing at once is safe and leaves no orphan
	_flashes.clear()
	_body = body
	_muzzles = muzzles.duplicate()
	_projectiles_parent = projectiles_parent
	for muzzle: Node3D in _muzzles:
		var flash: MuzzleFlash = MuzzleFlash.create()
		muzzle.add_child(flash)
		_flashes.append(flash)


## Capacitor charge now, 0..1 (1 when the gate has no capacitor). The HUD's weapon gauge reads this.
func charge_fraction() -> float:
	if gate.capacitor == null:
		return 1.0
	return gate.capacitor.fraction_at(SimClock.now())


## Sets the capacitor charge, 0..1 (console and tests); ignored without a capacitor.
func set_charge_fraction(fraction: float) -> void:
	if gate.capacitor != null:
		gate.capacitor.set_fraction(fraction, SimClock.now())


## This tick's combat command; call it once per physics tick, before the cannon's own physics step. The cannon keeps
## the command for its `fire` flag and takes `weapon_next` once.
func set_combat_command(cmd: CombatCommand) -> void:
	_command = cmd
	_weapon_next_pending = cmd != null and cmd.weapon_next


## One tick of the cannon at sim time `now_s`. `_physics_process` calls it with `SimClock.now()`; public so tests
## can step it with a chosen clock.
func step(now_s: float) -> void:
	if _weapon_next_pending:
		_weapon_next_pending = false
		gate.cycle_mode()
	if not _is_wired():
		return  # nothing to shoot from: leave the gate alone so the first shot is not wasted
	var trigger_held: bool = _command != null and _command.fire
	var muzzle_indices: Array[int] = gate.update(now_s, trigger_held)
	if muzzle_indices.is_empty():
		return
	var forward: Vector3 = -_body.global_basis.z
	var launch_velocity: Vector3 = _body.linear_velocity + forward * muzzle_speed_mps
	for index: int in muzzle_indices:
		_spawn(index, launch_velocity, now_s)


func _is_wired() -> bool:
	return _body != null and is_instance_valid(_body) and _body.is_inside_tree() \
			and _projectiles_parent != null and is_instance_valid(_projectiles_parent) \
			and _projectiles_parent.is_inside_tree()


func _spawn(muzzle_index: int, launch_velocity: Vector3, now_s: float) -> void:
	var muzzle: Node3D = _muzzles[muzzle_index]
	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	_projectiles_parent.add_child(projectile)
	projectile.launch(muzzle.global_position, launch_velocity, now_s)
	_flashes[muzzle_index].trigger()
	projectile_fired.emit(muzzle_index, projectile)
