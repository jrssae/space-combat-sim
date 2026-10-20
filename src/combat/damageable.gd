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
var shapes: Array[HitShape] = []
## Radius of a sphere around the body origin that holds every shape (broad phase).
var bounding_radius: float = 0.0
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
		register_console: bool = false) -> void:
	faction = p_faction
	respects_god_mode = p_respects_god_mode
	hull = HullHealth.new(hull_max)
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
		damaged.emit(info, applied)
	if hull.destroyed_now:
		destroyed.emit(info)


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
