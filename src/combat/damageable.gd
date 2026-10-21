class_name Damageable
extends Node
## The hull of one ship (architecture §15.4): a component under the ship, like `Targetable`. It holds the pure
## `HullHealth` and the ship's hit volumes (`HitShape`s built from the hardpoints' `collision` list, the same primitives
## Jolt collides with). `HitResolver` finds it through group `damageable`, sweeps bolts against `shapes` and hands the
## result to `apply_hit`.
##
## `apply_hit` always emits `hit_taken` (effects, HUD flash), then removes hull points unless god mode protects this ship
## (`respects_god_mode`, the player's, reading `DebugConsole.flags.invulnerable` at hit time), emits `damaged` when points
## were removed and `destroyed` once, on the hit that took the hull to zero. What destruction does is M2-T06; here it
## is only a signal.
##
## Console (§15.13, D27): the player's Damageable registers provider `hull` (`hp`, `max_hp`, `fraction`, `invulnerable`,
## `destroyed`); the others stay out of the console.

## A bolt reached the hull, whether or not it did damage (god mode).
signal hit_taken(info: HitInfo)
## Hull points were removed: the hit and how many.
signal damaged(info: HitInfo, applied: float)
## The hit that took the hull to zero; emitted once per life.
signal destroyed(info: HitInfo)

const GROUP: StringName = &"damageable"

var faction: StringName = Factions.NEUTRAL
var hull: HullHealth = HullHealth.new()
## Where the damage landed, by main component (the HUD's silhouettes).
var zones: DamageZones = DamageZones.new()
var shapes: Array[HitShape] = []
## Radius of a sphere around the body origin that holds every shape (broad phase).
var bounding_radius: float = 0.0
## True for something that any bolt hurts whatever its faction (a nav buoy: neutral to everyone, yet shootable). Bolts of its
## own faction still pass through.
var hit_by_anyone: bool = false
## True for the player's hull: `debug.invulnerable` stops its damage.
var respects_god_mode: bool = false


func _init() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## The Damageable among `owner`'s children, or null.
static func of(owner: Node) -> Damageable:
	if owner == null:
		return null
	for child: Node in owner.get_children():
		if child is Damageable:
			return child as Damageable
	return null


## Builds the hull and the hit volumes. `collision` is `Hardpoints.collision`; entries that are not a box or a
## capsule are skipped. Calling it again replaces everything and restores the hull.
func setup(collision: Array[Dictionary], hull_max: float, p_faction: StringName, p_respects_god_mode: bool = false,
		register_console: bool = false, damage_layout: StringName = &"") -> void:
	faction = p_faction
	respects_god_mode = p_respects_god_mode
	hull = HullHealth.new(hull_max)
	zones = DamageZones.new(DamageZones.layout_from_name(damage_layout))
	shapes.clear()
	bounding_radius = 0.0
	for entry: Dictionary in collision:
		var shape: HitShape = HitShape.from_collision(entry)
		if shape == null:
			continue
		shapes.append(shape)
		bounding_radius = maxf(bounding_radius, shape.extent_radius())
	DebugConsole.registry.unregister_owner(self)
	if register_console:
		_register_console()


## Whether a bolt of `bolt_faction` can hurt this hull.
func can_be_hit_by(bolt_faction: StringName) -> bool:
	if Factions.is_hostile(bolt_faction, faction):
		return true
	return hit_by_anyone and bolt_faction != faction


## The ship this hull belongs to (the parent), or null.
func body() -> Node3D:
	return get_parent() as Node3D


## Can a bolt hit it now? In the tree, visible, its ship processing (a parked or hidden pool ship is not) and not yet
## destroyed.
func is_active() -> bool:
	if not is_inside_tree() or hull.destroyed:
		return false
	var parent: Node3D = body()
	return parent != null and parent.is_visible_in_tree() and parent.can_process()


func apply_hit(info: HitInfo) -> void:
	hit_taken.emit(info)
	var applied: float = 0.0
	if not (respects_god_mode and DebugConsole.flags.invulnerable):
		applied = hull.apply(info.damage)
	info.applied = applied
	if applied > 0.0:
		var b: Node3D = body()
		if b != null and b.is_inside_tree():
			zones.record(b.global_transform.affine_inverse() * info.point, applied)
		damaged.emit(info, applied)
	if hull.destroyed_now:
		destroyed.emit(info)


## A full, intact hull again (respawn, pool re-use, console `heal`): the hull points and the damage zones.
func restore() -> void:
	hull.restore()
	zones.reset()


## 0..1 damage per zone of the silhouette (empty when the ship has no layout): see `DamageZones`.
func zone_severities() -> PackedFloat32Array:
	return zones.severities(hull.max_hp)


## Destroys the hull outright, bypassing god mode (console `kill`): the remaining hull points are applied as one hit with
## no shooter, so `hit_taken`, `damaged` and `destroyed` fire as for any other hit. Returns false if it was already dead.
func kill() -> bool:
	if hull.destroyed:
		return false
	var b: Node3D = body()
	var info := HitInfo.new(b.get_instance_id() if b != null else 0, 0, &"", hull.hp, b.global_position if b != null else Vector3.ZERO)
	hit_taken.emit(info)
	info.applied = hull.apply(hull.hp)
	damaged.emit(info, info.applied)
	if hull.destroyed_now:
		destroyed.emit(info)
	return true


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"hull", ConsoleVars.new({
		&"hp": {"get": func() -> float: return hull.hp, "type": TYPE_FLOAT, "doc": "Hull points left"},
		&"max_hp": {"get": func() -> float: return hull.max_hp, "type": TYPE_FLOAT, "doc": "Hull points when intact"},
		&"fraction": {"get": hull.fraction, "type": TYPE_FLOAT, "doc": "Hull 0..1"},
		&"invulnerable": {"get": func() -> bool: return DebugConsole.flags.invulnerable,
				"set": func(value: Variant) -> void: DebugConsole.flags.invulnerable = bool(value), "type": TYPE_BOOL,
				"doc": "Mirror of debug.invulnerable (god mode): this hull takes no damage"},
		&"destroyed": {"get": func() -> bool: return hull.destroyed, "type": TYPE_BOOL, "doc": "The hull is gone"},
	}), self)
