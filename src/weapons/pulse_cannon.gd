class_name PulseCannon
extends Node3D
## The ship's pulse cannons (architecture §6.3): a thin node around the pure `PulseCannonGate`. Each physics tick it
## reads the latest `CombatCommand` (`weapon_next` cycles the fire mode, `fire` is the held trigger), asks the gate
## which muzzles fire, and spawns a `Projectile` at each of them.
##
## Wiring (`ShipAssembly`, M2-T02, does this; the cannon does not know the Ship class):
##
##     cannon.setup(ship_body, muzzles, world_projectiles_node, weapon_spec, register_console)
##     cannon.set_combat_command(cmd)     # once per physics tick, with that tick's command
##
## Any number of muzzles (at least one) works: the gate cycles or fires them all. Bolt speed, rate of fire, lifetime,
## look and the capacitor come from the `WeaponSpec` (the Starfury's M1 numbers when none is given).
##
## A projectile leaves the muzzle's global position with `body.linear_velocity + forward * muzzle_speed_mps`, where
## forward is the body's -Z, so the shooter's own velocity is inherited. With a `convergence_range_m` in the weapon spec
## each muzzle instead aims at the point that far ahead of the body along its nose. Projectiles go under `projectiles_parent`
## (`World/Projectiles`), never under the ship, so they stop following the ship the moment they leave it.
##
## `weapon_next` is a one-tick edge: it is remembered when `set_combat_command` receives it and used once, so a tick
## that runs without a fresh command never cycles the mode twice.
##
## The gate is paid from a `WeaponCapacitor` (M2-T14), sized by the `WeaponSpec`: an empty capacitor stops the fire
## until it has recharged enough for the next shot.
##
## On the kernel (M4-T35, architecture §17.13): with the core on, every cannon but the player's
## registers with `ScsCannons` (its muzzles as data in the ship's frame, its gate and capacitor, what its bolts carry) and
## stops ticking itself; the core steps every cannon's gate in one call a tick, spawns each shot as an owned bolt row and
## names the shots, so this node only flashes the muzzle and emits `shot_fired`. The trigger comes from the ship's row
## command when it flies one, else from `set_combat_command`. The GDScript gate stays the reference (`step`, which the
## tests drive by hand) and carries its state over when the cannon joins or leaves the kernel.
##
## Console (architecture §6.4, §15.1 D27): only the player's cannon registers, when `setup` is given
## `register_console`. Provider `weapons` with `mode` (writable: `alternating` / `linked`), `cooldown_s` and
## `charge` (writable, 0..1: the capacitor), so `set weapons.mode linked` switches modes and `set weapons.charge 0`
## empties the capacitor. Unregistering is in `_exit_tree`.

## A shot left a muzzle as a bolt node: the muzzle index and the new projectile (the node path only).
signal projectile_fired(muzzle_index: int, projectile: Projectile)
## A shot left a muzzle, on either path: the muzzle index and the World position it left from (the sound, the kill credit).
signal shot_fired(muzzle_index: int, at: Vector3)

const PROJECTILE_SCENE: PackedScene = preload("res://src/weapons/projectile.tscn")
const MODE_CHOICES: Array[StringName] = [&"alternating", &"linked"]

## Muzzle speed relative to the shooter, m/s.
@export var muzzle_speed_mps: float = 1000.0

var gate: PulseCannonGate = PulseCannonGate.new()

var weapon: WeaponSpec = WeaponSpec.new()
## Faction of the bolts (the ship's); a bolt hits only ships hostile to it.
var faction: StringName = Factions.NEUTRAL:
	set(value):
		faction = value
		if _slot >= 0:
			_kernel.set_faction(_slot, value)

# Every cannon in a tree, so the core can rebind them all when the kernel comes or goes (M4-T35).
static var _live: Array[PulseCannon] = []

var _body: RigidBody3D = null
var _muzzles: Array[Node3D] = []
var _muzzle_locals := PackedVector3Array()
# The muzzles' transforms in the body's frame (M4-T35, a lean ship: no marker nodes), and the pool its flashes go to.
var _muzzle_transforms: Array[Transform3D] = []
var _pool: MuzzleFlashPool = null
var _flashes: Array[MuzzleFlash] = []
var _projectiles_parent: Node3D = null
var _command: CombatCommand = null
var _weapon_next_pending: bool = false
var _console_owner: bool = false
# The kernel this cannon fires through and its slot there (-1: this node's own gate).
var _kernel: Object = null
var _sim: SimCore = null
var _slot: int = -1


func _init() -> void:
	gate.capacitor = weapon.make_capacitor()


func _enter_tree() -> void:
	_live.append(self)
	if _body != null:
		_bind()


func _exit_tree() -> void:
	_live.erase(self)
	_unbind()
	DebugConsole.registry.unregister_owner(self)


func _notification(what: int) -> void:
	# A parked ship's cannon neither fires nor recharges, on the kernel as on this node; its pooled flashes end at once, as a
	# flash node's light did.
	if _slot >= 0 and (what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED):
		_kernel.set_live(_slot, what == NOTIFICATION_ENABLED)
	if what == NOTIFICATION_DISABLED and _pool != null and is_instance_valid(_pool) and _body != null:
		_pool.clear_for(_body)


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"weapons", ConsoleVars.new({
		&"mode": {"get": func() -> StringName: return PulseCannonGate.mode_name(mode()),
				"set": func(value: Variant) -> void: set_mode(PulseCannonGate.mode_from_name(StringName(str(value)))),
				"type": TYPE_STRING_NAME, "choices": MODE_CHOICES,
				"doc": "Pulse cannon fire mode: alternating (one muzzle at a time) or linked (every muzzle together, slower)"},
		&"cooldown_s": {"get": func() -> float: return cooldown_remaining(SimClock.now()), "unit": "s",
				"doc": "Time until the cannon can fire again"},
		&"charge": {"get": charge_fraction, "set": set_charge_fraction, "type": TYPE_FLOAT, "min": 0.0, "max": 1.0,
				"doc": "Capacitor charge, 0..1: each projectile costs some, it recharges with time, empty = no fire"},
	}), self)


func _physics_process(_delta: float) -> void:
	step(SimClock.now())


## Called by `ShipAssembly` with the ship body (position, velocity and nose come from it), the muzzle markers in
## muzzle-index order (the hardpoints' `muzzles`; at least one), the node projectiles are added to, the weapon type
## (null = the Starfury's M1 numbers), whether this cannon is the player's, so it registers the `weapons` console
## provider, and the faction its bolts carry (M2-T03: bolts know their shooter and faction for hit detection). Adds a `MuzzleFlash` under each muzzle. Calling it again replaces the previous wiring, and refills the
## capacitor to the new spec.
func setup(body: RigidBody3D, muzzles: Array[Node3D], projectiles_parent: Node3D, weapon_spec: WeaponSpec = null,
		register_console: bool = false, p_faction: StringName = Factions.NEUTRAL) -> void:
	assert(body != null and projectiles_parent != null, "PulseCannon.setup: body and projectiles_parent are required")
	assert(not muzzles.is_empty(), "PulseCannon.setup: at least one muzzle is required")
	_unbind()
	faction = p_faction
	weapon = weapon_spec if weapon_spec != null else WeaponSpec.new()
	muzzle_speed_mps = weapon.muzzle_speed_mps
	gate.configure(muzzles.size(), weapon.shot_interval_s)
	gate.capacitor = weapon.make_capacitor()
	for flash: MuzzleFlash in _flashes:
		if is_instance_valid(flash):
			if flash.get_parent() != null:
				flash.get_parent().remove_child(flash)
			flash.free()  # out of the tree already, so freeing at once is safe and leaves no orphan
	_flashes.clear()
	_body = body
	_muzzles = muzzles.duplicate()
	_muzzle_locals = muzzle_locals_of(body, _muzzles)
	_muzzle_transforms.clear()
	_pool = null
	_projectiles_parent = projectiles_parent
	_console_owner = register_console
	for muzzle: Node3D in _muzzles:
		var flash: MuzzleFlash = MuzzleFlash.create()
		muzzle.add_child(flash)
		_flashes.append(flash)
	DebugConsole.registry.unregister_owner(self)
	if register_console:
		_register_console()
	_bind()


## `setup` for a lean ship (M4-T35, finding 12): the muzzles as transforms in the body's frame (the hardpoints' data, no
## marker node each) and the World's `MuzzleFlashPool` for the flashes (null: no flashes). Shots leave from
## `body.global_transform * muzzle.origin`, as the markers' positions were.
func setup_transforms(body: RigidBody3D, muzzle_transforms: Array[Transform3D], projectiles_parent: Node3D,
		weapon_spec: WeaponSpec = null, p_faction: StringName = Factions.NEUTRAL, pool: MuzzleFlashPool = null) -> void:
	assert(body != null and projectiles_parent != null, "PulseCannon.setup_transforms: body and projectiles_parent are required")
	assert(not muzzle_transforms.is_empty(), "PulseCannon.setup_transforms: at least one muzzle is required")
	_unbind()
	faction = p_faction
	weapon = weapon_spec if weapon_spec != null else WeaponSpec.new()
	muzzle_speed_mps = weapon.muzzle_speed_mps
	gate.configure(muzzle_transforms.size(), weapon.shot_interval_s)
	gate.capacitor = weapon.make_capacitor()
	for flash: MuzzleFlash in _flashes:
		if is_instance_valid(flash):
			if flash.get_parent() != null:
				flash.get_parent().remove_child(flash)
			flash.free()
	_flashes.clear()
	_body = body
	_muzzles.clear()
	_muzzle_transforms = muzzle_transforms.duplicate()
	_muzzle_locals.clear()
	for xf: Transform3D in _muzzle_transforms:
		_muzzle_locals.append(xf.origin)
	_pool = pool
	_projectiles_parent = projectiles_parent
	_console_owner = false
	DebugConsole.registry.unregister_owner(self)
	_bind()


## The muzzles' origins in `body`'s frame, composed from the markers' own transforms up to the body (the data the kernel
## fires from, M4-T35; the markers never move on the hull).
static func muzzle_locals_of(body: Node3D, muzzles: Array[Node3D]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for muzzle: Node3D in muzzles:
		var xf: Transform3D = muzzle.transform
		var parent: Node = muzzle.get_parent()
		while parent != null and parent != body:
			var above := parent as Node3D
			if above != null:
				xf = above.transform * xf
			parent = parent.get_parent()
		out.append(xf.origin)
	return out


## The muzzles' origins in the ship's frame, as data (the kernel's and, for the frame's flashes, T36's).
func muzzle_locals() -> PackedVector3Array:
	return _muzzle_locals


## Ends every muzzle flash at once (a ship back in play).
func reset_flashes() -> void:
	for flash: MuzzleFlash in _flashes:
		if is_instance_valid(flash):
			flash.reset()
	if _pool != null and is_instance_valid(_pool) and _body != null:
		_pool.clear_for(_body)


## Whether this cannon's flashes come from the World's pool (a lean ship) rather than a node per muzzle.
func flashes_pooled() -> bool:
	return _pool != null


# Flashes muzzle `index`: the pool's flash on a lean ship, else the node under the marker.
func _flash(index: int) -> void:
	if _pool != null:
		if is_instance_valid(_pool) and index < _muzzle_transforms.size():
			_pool.trigger(_body, _muzzle_transforms[index])
	elif index < _flashes.size():
		_flashes[index].trigger()


# Muzzle `index`'s World position now: the marker's, or the transform's origin composed with the body's transform.
func _muzzle_position(index: int) -> Vector3:
	if index < _muzzles.size():
		return _muzzles[index].global_position
	return _body.global_transform * _muzzle_transforms[index].origin


## Forgets the cooldown and the muzzle turn and refills the capacitor (a respawn), on this node's gate and the kernel's.
func reset_gate() -> void:
	gate.reset()
	if _slot >= 0:
		_kernel.reset(_slot)


## Capacitor charge now, 0..1 (1 when the gate has no capacitor). The HUD's weapon gauge reads this.
func charge_fraction() -> float:
	if _slot >= 0:
		return float(_kernel.charge_fraction(_slot, SimClock.now()))
	if gate.capacitor == null:
		return 1.0
	return gate.capacitor.fraction_at(SimClock.now())


## Sets the capacitor charge, 0..1 (console and tests); ignored without a capacitor.
func set_charge_fraction(fraction: float) -> void:
	if _slot >= 0:
		_kernel.set_charge_fraction(_slot, fraction, SimClock.now())
	if gate.capacitor != null:
		gate.capacitor.set_fraction(fraction, SimClock.now())


## Seconds until the next shot is allowed, 0 when ready, on whichever gate fires.
func cooldown_remaining(now_s: float) -> float:
	if _slot >= 0:
		return float(_kernel.cooldown_remaining(_slot, now_s))
	return gate.cooldown_remaining(now_s)


## The fire mode of whichever gate fires, and setting it.
func mode() -> PulseCannonGate.Mode:
	if _slot >= 0:
		return PulseCannonGate.Mode.LINKED if bool(_kernel.linked(_slot)) else PulseCannonGate.Mode.ALTERNATING
	return gate.mode


func set_mode(value: PulseCannonGate.Mode) -> void:
	gate.mode = value
	if _slot >= 0:
		_kernel.set_linked(_slot, value == PulseCannonGate.Mode.LINKED)


## This tick's combat command; call it once per physics tick, before the cannon's own physics step. The cannon keeps
## the command for its `fire` flag and takes `weapon_next` once.
func set_combat_command(cmd: CombatCommand) -> void:
	_command = cmd
	_weapon_next_pending = cmd != null and cmd.weapon_next
	if _slot >= 0:
		_kernel.set_trigger(_slot, cmd != null and cmd.fire, _weapon_next_pending)
		_weapon_next_pending = false  # the kernel takes the cycle at its step


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
	var converge_at: Vector3 = _body.global_position + forward * weapon.convergence_range_m
	for index: int in muzzle_indices:
		var direction: Vector3 = forward
		if weapon.convergence_range_m > 0.0:
			direction = (converge_at - _muzzle_position(index)).normalized()
		_spawn(index, _body.linear_velocity + direction * muzzle_speed_mps, now_s)


# --- the kernel (M4-T35) --------------------------------------------------------------------------------------------


## Whether this cannon fires through the core's cannon kernel now.
func on_kernel() -> bool:
	return _slot >= 0


## The kernel stepped a cannon whose ship had no row this tick: fire from the node's pose, as `step` would. Returns the
## kernel's shots, `[triples, positions]`, or empty arrays when the body cannot shoot.
func step_without_row(now_s: float) -> Array:
	if _slot < 0 or not _is_wired() or not _body.can_process():
		return [PackedInt64Array(), PackedVector3Array()]
	return _kernel.step_one(_sim.core, _slot, _body.global_basis, _body.global_position, _body.linear_velocity, now_s)


## The kernel fired muzzle `muzzle_index` of this cannon: the flash and the signal.
func on_kernel_fired(muzzle_index: int, at: Vector3) -> void:
	_flash(muzzle_index)
	shot_fired.emit(muzzle_index, at)


## Binds every cannon to the kernel or back to its own gate, as the core and the setting stand now.
static func rebind_all() -> void:
	for cannon: PulseCannon in _live:
		if is_instance_valid(cannon) and cannon._body != null:
			cannon._bind()


# Joins the kernel when the core owns the bolts and this is not the player's cannon; else fires from this node's gate.
func _bind() -> void:
	var sim: SimCore = SimCore.for_tree(get_tree()) if is_inside_tree() else null
	var wanted: bool = sim != null and SimCore.bolt_rows_enabled() and not _console_owner and _body != null \
			and not _muzzle_locals.is_empty()
	if not wanted:
		_unbind()
		return
	if _slot >= 0 and _sim == sim:
		return
	_unbind()
	var slot: int = sim.register_cannon(self, _body.get_instance_id(), _muzzle_locals, weapon, faction)
	if slot >= 0 and _body is Ship and (_body as Ship).spec != null:
		sim.cannons.set_tier_scale(slot, (_body as Ship).spec.tier_hit_scale)  # the hull's term in the tier (M4-T22)
	if slot < 0:
		return
	_sim = sim
	_kernel = sim.cannons
	_slot = slot
	var now_s: float = SimClock.now()
	_kernel.set_gate_state(_slot, gate._ready_at_s, gate._next_alternating, gate.mode == PulseCannonGate.Mode.LINKED)
	if gate.capacitor != null:
		_kernel.set_charge_fraction(_slot, gate.capacitor.fraction_at(now_s), now_s)
	if _command != null:
		_kernel.set_trigger(_slot, _command.fire, _weapon_next_pending)
		_weapon_next_pending = false
	if not can_process():
		_kernel.set_live(_slot, false)
	set_physics_process(false)


# Leaves the kernel, taking its gate's state back into this node's gate.
func _unbind() -> void:
	if _slot >= 0:
		if is_instance_valid(_kernel):
			var state: PackedFloat64Array = _kernel.gate_state(_slot)
			if state.size() == 3:
				gate._ready_at_s = state[0]
				gate._next_alternating = int(state[1]) % gate.muzzle_count
				gate.mode = PulseCannonGate.Mode.LINKED if state[2] != 0.0 else PulseCannonGate.Mode.ALTERNATING
			if gate.capacitor != null:
				var now_s: float = SimClock.now()
				gate.capacitor.set_fraction(float(_kernel.charge_fraction(_slot, now_s)), now_s)
		if is_instance_valid(_sim):
			_sim.unregister_cannon(_slot)
	_slot = -1
	_kernel = null
	_sim = null
	set_physics_process(true)


func _is_wired() -> bool:
	return _body != null and is_instance_valid(_body) and _body.is_inside_tree() \
			and _projectiles_parent != null and is_instance_valid(_projectiles_parent) \
			and _projectiles_parent.is_inside_tree()


func _spawn(muzzle_index: int, launch_velocity: Vector3, now_s: float) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	_projectiles_parent.add_child(projectile)
	projectile.configure(weapon)
	projectile.shooter_id = _body.get_instance_id()
	projectile.faction = faction
	var at: Vector3 = _muzzle_position(muzzle_index)
	projectile.launch(at, launch_velocity, now_s)
	_flash(muzzle_index)
	projectile_fired.emit(muzzle_index, projectile)
	shot_fired.emit(muzzle_index, at)
