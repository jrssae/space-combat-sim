class_name HitResolver
extends Node
## Swept hit detection for bolts (architecture §15.3, §15.5, D21). Once per physics tick, after every bolt has moved
## (`process_physics_priority` 200), it sweeps the segment each bolt just flew against every active `Damageable` that is
## hostile to the bolt and is not its shooter. Pure script maths (`SweepMath` through `HitShape`), no Jolt queries, so it
## is exact at any closing speed and does not depend on when Jolt moves the target.
##
## Per bolt and target, in the target's body frame (the target's body has not been stepped yet this tick, so it is still at
## its start-of-tick pose `(t0, B)` with velocity `v_t`):
##
##     a = B^T ((p1 - step) - t0)             # the bolt at the start of the tick, relative to the target
##     b = B^T (p1 - (t0 + v_t * dt))         # ... and at its end
##
## A bounding-sphere test comes first, then each hit volume inflated by the bolt's hit radius; the earliest hit over all
## targets wins. The bolt is spent, the target's `Damageable.apply_hit` runs, an `ImpactFlash` is added to the hit ship
## and `hit_resolved` is emitted for the HUD and sound. Nothing is cached between ticks (a `World.rebase()` between ticks
## changes nothing: the bolt stores a displacement, and positions shift together). The target's rotation during one tick
## is ignored.
##
## Console: provider `combat` (`projectiles`, `hits`, `last_hit`, `pairs_tested`, `resolve_us`) and commands
## `damage <amount> [player|target]` and `heal [player|target|all]`. `resolve_us` is a profiling readout from the wall
## clock, not gameplay time.

## A bolt hit a ship; `info.applied` is set by then.
signal hit_resolved(info: HitInfo)

const LATE_PRIORITY: int = 200
const TARGET_CHOICES: Array[StringName] = [&"player", &"target"]
const HEAL_CHOICES: Array[StringName] = [&"player", &"target", &"all"]

## Bolts considered and ship pairs swept on the last tick, total hits, and the last tick's cost in microseconds.
var projectiles_last_tick: int = 0
var pairs_tested: int = 0
var hits_total: int = 0
var last_hit: String = "none"
var resolve_us: int = 0


func _init() -> void:
	process_physics_priority = LATE_PRIORITY


func _ready() -> void:
	DebugConsole.registry.register_provider(&"combat", ConsoleVars.new({
		&"projectiles": {"get": func() -> int: return projectiles_last_tick, "doc": "Bolts swept on the last tick"},
		&"hits": {"get": func() -> int: return hits_total, "doc": "Hits resolved this session"},
		&"last_hit": {"get": func() -> String: return last_hit, "doc": "The last hit: shooter -> target, damage"},
		&"pairs_tested": {"get": func() -> int: return pairs_tested, "doc": "Bolt and ship pairs swept on the last tick"},
		&"resolve_us": {"get": func() -> int: return resolve_us, "unit": "us",
				"doc": "Cost of the last tick's resolve (profiling only, wall clock)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"damage",
			"Hit the player or the selected target with no shooter (god mode applies to the player)",
			[ConsoleArg.float_required(&"amount", 0.0), ConsoleArg.enum_optional(&"who", TARGET_CHOICES, &"player")]),
			_cmd_damage, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"heal", "Restore the player's, the target's or every hull",
			[ConsoleArg.enum_optional(&"who", HEAL_CHOICES, &"player")]), _cmd_heal, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	resolve(delta)


## One tick of hit detection with time step `delta`. `_physics_process` calls it; public so tests can step it.
func resolve(delta: float) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	projectiles_last_tick = 0
	pairs_tested = 0
	var targets: Array[Dictionary] = _gather_targets(delta)
	for node: Node in get_tree().get_nodes_in_group(Projectile.GROUP):
		var bolt := node as Projectile
		if bolt == null or bolt.is_spent() or bolt.is_queued_for_deletion() or not bolt.is_inside_tree():
			continue
		projectiles_last_tick += 1
		var best: Dictionary = _earliest_hit(bolt, targets, delta)
		if not best.is_empty():
			_land(bolt, best, delta)
	resolve_us = Time.get_ticks_usec() - started_us


# Everything about the active ships that does not depend on the bolt, as of this tick's start.
func _gather_targets(delta: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
		var damageable := node as Damageable
		if damageable == null or not damageable.is_active():
			continue
		var body: Node3D = damageable.body()
		var velocity: Vector3 = Vector3.ZERO
		if body is RigidBody3D:
			velocity = (body as RigidBody3D).linear_velocity
		var basis: Basis = body.global_basis
		out.append({
			"damageable": damageable,
			"body": body,
			"body_id": body.get_instance_id(),
			"t0": body.global_position,
			"basis": basis,
			"to_body": basis.transposed(),
			"move": velocity * delta,
		})
	return out


func _earliest_hit(bolt: Projectile, targets: Array[Dictionary], _delta: float) -> Dictionary:
	var best: Dictionary = {}
	var best_t: float = INF
	var p1: Vector3 = bolt.global_position
	var start: Vector3 = p1 - bolt.last_step
	for target: Dictionary in targets:
		var damageable: Damageable = target["damageable"]
		if int(target["body_id"]) == bolt.shooter_id or not Factions.is_hostile(bolt.faction, damageable.faction):
			continue
		pairs_tested += 1
		var to_body: Basis = target["to_body"]
		var t0: Vector3 = target["t0"]
		var move: Vector3 = target["move"]
		var a: Vector3 = to_body * (start - t0)
		var b: Vector3 = to_body * (p1 - (t0 + move))
		if SweepMath.segment_sphere(a, b, Vector3.ZERO, damageable.bounding_radius + bolt.hit_radius_m) < 0.0:
			continue
		var t: float = INF
		for shape: HitShape in damageable.shapes:
			var shape_t: float = shape.sweep(a, b, bolt.hit_radius_m)
			if shape_t >= 0.0 and shape_t < t:
				t = shape_t
		if t < best_t:
			best_t = t
			best = {"target": target, "t": t, "a": a, "b": b}
	return best


func _land(bolt: Projectile, best: Dictionary, delta: float) -> void:
	var target: Dictionary = best["target"]
	var damageable: Damageable = target["damageable"]
	var basis: Basis = target["basis"]
	var t: float = best["t"]
	var a: Vector3 = best["a"]
	var b: Vector3 = best["b"]
	var move: Vector3 = target["move"]
	var local_point: Vector3 = a + t * (b - a)
	var relative: Vector3 = basis * (b - a)
	var info := HitInfo.new(int(target["body_id"]), bolt.shooter_id, bolt.faction, bolt.damage,
			(target["t0"] as Vector3) + move * t + basis * local_point,
			-relative.normalized() if relative.length_squared() > 1e-12 else Vector3.ZERO,
			relative.length() / maxf(delta, 1e-6))
	bolt.spend()
	_apply(damageable, info)
	var flash := ImpactFlash.create(bolt.color, hash([bolt.shooter_id, info.target_id, Engine.get_physics_frames()]))
	flash.position = local_point
	(target["body"] as Node3D).add_child(flash)
	flash.reset_physics_interpolation()
	hit_resolved.emit(info)


func _apply(damageable: Damageable, info: HitInfo) -> void:
	hits_total += 1
	damageable.apply_hit(info)
	last_hit = "%s -> %s, %.1f of %.1f applied" % [_name_of(info.shooter_id), _name_of(info.target_id), info.applied,
			info.damage]
	if damageable.hull.destroyed_now:
		print("HitResolver: %s destroyed" % _name_of(info.target_id))  # T06 (DestructionDirector) acts on `destroyed`


func _name_of(body_id: int) -> String:
	if body_id == 0 or not is_instance_id_valid(body_id):
		return "nobody"
	var body := instance_from_id(body_id) as Node
	if body == null:
		return "nobody"
	for child: Node in body.get_children():
		if child is Targetable and not (child as Targetable).display_name.is_empty():
			return (child as Targetable).display_name
	return String(body.name)


# --- console -----------------------------------------------------------------------------------------------------


# The player's hull (the one that respects god mode).
func _player_damageable() -> Damageable:
	for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
		var damageable := node as Damageable
		if damageable != null and damageable.respects_god_mode:
			return damageable
	return null


# The hull of the ship the player has selected, or null.
func _target_damageable() -> Damageable:
	var player: Damageable = _player_damageable()
	var ship := player.body() as Ship if player != null else null
	if ship == null or not ship.targeting.system.has_selection():
		return null
	var selected_id: int = ship.targeting.selected_id()
	if not is_instance_id_valid(selected_id):
		return null
	var targetable := instance_from_id(selected_id) as Targetable
	return Damageable.of(targetable.get_parent()) if targetable != null else null


func _cmd_damage(args: Dictionary) -> ConsoleResult:
	var who: StringName = StringName(args[&"who"])
	var damageable: Damageable = _player_damageable() if who == &"player" else _target_damageable()
	if damageable == null:
		return ConsoleResult.failure("no %s hull to damage" % who)
	var body: Node3D = damageable.body()
	var info := HitInfo.new(body.get_instance_id(), 0, &"", float(args[&"amount"]), body.global_position)
	_apply(damageable, info)
	hit_resolved.emit(info)
	return ConsoleResult.line("%s: %.1f applied of %.1f, hull %.1f / %.1f%s" % [who, info.applied, info.damage,
			damageable.hull.hp, damageable.hull.max_hp, " (destroyed)" if damageable.hull.destroyed else ""])


func _cmd_heal(args: Dictionary) -> ConsoleResult:
	var who: StringName = StringName(args[&"who"])
	var healed: Array[Damageable] = []
	match who:
		&"all":
			for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
				if node is Damageable:
					healed.append(node as Damageable)
		&"target":
			var target: Damageable = _target_damageable()
			if target != null:
				healed.append(target)
		_:
			var player: Damageable = _player_damageable()
			if player != null:
				healed.append(player)
	if healed.is_empty():
		return ConsoleResult.failure("no %s hull to heal" % who)
	for damageable: Damageable in healed:
		damageable.hull.restore()
	return ConsoleResult.line("restored %d hull(s)" % healed.size())
