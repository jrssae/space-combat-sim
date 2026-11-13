class_name Damageable
extends Node
## The hull of one ship (architecture §15.4): a component under the ship, like `Targetable`. It holds the pure
## `HullHealth` and the ship's hit volumes (`HitShape`s built from the hardpoints' `collision` list, the same primitives
## Jolt collides with). `HitResolver` finds it through group `damageable`, sweeps bolts against `shapes` and hands the
## result to `apply_hit`; `RamResolver` does the same for rams (§16 D32), with `core_radius` and the `ram_*` values.
##
## `apply_hit` always emits `hit_taken` (effects, HUD flash), then removes hull points unless god mode protects this ship
## (`respects_god_mode`, the player's, reading `DebugConsole.flags.invulnerable` at hit time) or the hull is `invulnerable`
## (any ship, set by its scenario spawn: the instructor), emits `damaged` when points
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
## The hull is whole again (`restore`, a rebuild): what watches the hull points (the core's columns, M4-T35) reads them anew.
signal restored
## The hit volumes changed in play (`set_volumes`: cargo pods mounted or taken off, M5-T16).
signal volumes_changed

const GROUP: StringName = &"damageable"

var faction: StringName = Factions.NEUTRAL
var hull: HullHealth = HullHealth.new()
## Where the damage landed, by main component (the HUD's silhouettes).
var zones: DamageZones = DamageZones.new()
var shapes: Array[HitShape] = []
## The shapes as `ConvexSweep` volumes in the body frame, whole and shrunk to their points at least `RamMath.RAM_DEPTH_M` deep
## (the ram resolver's swept test; built with the shapes).
var ram_volumes: Array[ConvexSweep.Convex] = []
var ram_cores: Array[ConvexSweep.Convex] = []
## The axis-aligned box in the body frame that holds every shape.
var ram_bounds: AABB = AABB()
## Radius of a sphere around the body origin that holds every shape (broad phase).
var bounding_radius: float = 0.0
## Radius of the largest sphere inside one of the shapes, wherever it sits (`RamMath.core_radius`, about 1 m for a fighter):
## how thick the solid core is, for the tunnelling threshold (§16 D32).
var core_radius: float = 0.0
## Ram damage (§16 D32): a velocity change of the owner's own body up to this is harmless...
var ram_safe_dv_mps: float = 5.0
## ... and one of this or more takes the whole hull (quadratic in between, `RamMath.severity`). Ships take both from their
## `ShipSpec`; these defaults are the Starfury's.
var ram_lethal_dv_mps: float = 18.0
## Mass for the ram maths when the owner is not a rigid body (a nav buoy); a rigid body's own `mass` is used otherwise.
var ram_mass_kg: float = 0.0
## True for something that any bolt hurts whatever its faction (a nav buoy: neutral to everyone, yet shootable). Bolts of its
## own faction still pass through.
var hit_by_anyone: bool = false
## True for a big hull that a bolt it does not take damage from still stops on (M7-T07, maintainer: the station, whose grid fires
## many bolts close to its hull); the bolt is spent with no damage.
var stops_friendly_bolts: bool = false
## True for the player's hull: `debug.invulnerable` stops its damage.
var respects_god_mode: bool = false
## True for a hull nothing damages, god-mode style but for any ship (M3-T09: the instructor, from its scenario spawn's
## `invulnerable`). Hits still arrive (`hit_taken`); only the console's `kill` gets through, as it does through god mode.
## The pool clears it on every acquire.
var invulnerable: bool = false
## The hit volumes' scale about the body origin (M6-T22: a ship shrunk in a jump vortex's funnel); 1 normally.
var hull_scale: float = 1.0
## How many times the hull was made whole again (`restore`: a respawn, a pool re-use, a heal): a far missile launched at one
## life does not land on the next (M4-T22 fix round 1).
var life: int = 0

var _base_shapes: Array[HitShape] = []  # as built, before `hull_scale`
var _whole_volumes: Array[ConvexSweep.Convex] = []  # the ram volumes, bounds and radii of the whole hull
var _whole_cores: Array[ConvexSweep.Convex] = []
var _whole_bounds: AABB = AABB()
var _whole_radius: float = 0.0
var _whole_core: float = 0.0
var _whole_dirty: bool = true


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
	set_volumes(collision)
	DebugConsole.registry.unregister_owner(self)
	if register_console:
		_register_console()


## Replaces the hit volumes (and the bounds and ram volumes built from them) and keeps the hull: a hull whose shape changes
## in play (cargo pods mounted or taken off, M5-T16). `collision` is `Hardpoints.collision`'s form.
func set_volumes(collision: Array[Dictionary]) -> void:
	_base_shapes.clear()
	_whole_dirty = true
	for entry: Dictionary in collision:
		var shape: HitShape = HitShape.from_collision(entry)
		if shape != null:
			_base_shapes.append(shape)
	_build_volumes()


## Scales the hit volumes (and the bounds and ram volumes) by `factor` about the body origin, the hull kept: a ship shrinking
## or growing in a jump vortex's funnel (M6-T22). 1 puts them back as built.
func set_hull_scale(factor: float) -> void:
	if is_equal_approx(factor, hull_scale):
		return
	hull_scale = factor
	_build_volumes()


# The volumes from the unscaled shapes at `hull_scale`: built in full at 1, scaled copies of those otherwise (a ship shrinking
# in a funnel rebuilds its hull many times; scaling about the origin keeps every bound in proportion).
func _build_volumes() -> void:
	if _whole_dirty:
		_build_whole()
	if hull_scale == 1.0:
		shapes = _base_shapes.duplicate()
		ram_volumes = _whole_volumes.duplicate()
		ram_cores = _whole_cores.duplicate()
		ram_bounds = _whole_bounds
		bounding_radius = _whole_radius
		core_radius = _whole_core
	else:
		shapes.clear()
		ram_volumes.clear()
		ram_cores.clear()
		for i: int in _base_shapes.size():
			shapes.append(_base_shapes[i].scaled(hull_scale))
			ram_volumes.append(_whole_volumes[i].scaled(hull_scale))
			ram_cores.append(_whole_cores[i].scaled(hull_scale))
		ram_bounds = AABB(_whole_bounds.position * hull_scale, _whole_bounds.size * hull_scale)
		bounding_radius = _whole_radius * hull_scale
		core_radius = _whole_core * hull_scale
	volumes_changed.emit()


# The whole hull's ram volumes, bounds and radii, from the unscaled shapes.
func _build_whole() -> void:
	_whole_volumes.clear()
	_whole_cores.clear()
	_whole_bounds = AABB()
	_whole_radius = 0.0
	for shape: HitShape in _base_shapes:
		_whole_volumes.append(ConvexSweep.Convex.of(shape, Transform3D.IDENTITY))
		_whole_cores.append(ConvexSweep.Convex.of(shape, Transform3D.IDENTITY, RamMath.RAM_DEPTH_M))
		_whole_bounds = _whole_volumes[-1].bounds if _whole_volumes.size() == 1 else _whole_bounds.merge(_whole_volumes[-1].bounds)
		_whole_radius = maxf(_whole_radius, shape.extent_radius())
	_whole_core = RamMath.core_radius(_base_shapes)
	_whole_dirty = false


## Whether a bolt of `bolt_faction` can hurt this hull. With `friendly_fire` (`settings.friendly_fire`, D31) any bolt can:
## allies, neutrals and buoys included. Not the shooter's own hull: the resolver skips that by instance id before asking.
func can_be_hit_by(bolt_faction: StringName, friendly_fire: bool = false) -> bool:
	if friendly_fire:
		return true
	if Factions.is_hostile(bolt_faction, faction):
		return true
	return hit_by_anyone and bolt_faction != faction


## The ship this hull belongs to (the parent), or null.
func body() -> Node3D:
	return get_parent() as Node3D


## Mass for the ram maths: the owner's rigid body mass, or `ram_mass_kg` for a prop without a body.
func ram_mass() -> float:
	var rigid := get_parent() as RigidBody3D
	return rigid.mass if rigid != null else ram_mass_kg


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
	var killed: bool = false  # this hit's own kill, never one left over from an earlier hit (code review 2026-11-12)
	if not invulnerable and not (respects_god_mode and DebugConsole.flags.invulnerable):
		applied = hull.apply(info.damage)
		killed = hull.destroyed_now
	info.applied = applied
	if applied > 0.0:
		var b: Node3D = body()
		if b != null and b.is_inside_tree():
			zones.record(b.global_transform.affine_inverse() * info.point, applied)
		damaged.emit(info, applied)
	if killed:
		destroyed.emit(info)


## A full, intact hull again (respawn, pool re-use, console `heal`): the hull points and the damage zones.
func restore() -> void:
	life += 1
	hull.restore()
	zones.reset()
	restored.emit()


## 0..1 damage per zone of the silhouette (empty when the ship has no layout): see `DamageZones`.
func zone_severities() -> PackedFloat32Array:
	return zones.severities(hull.max_hp)


## Destroys the hull outright, bypassing god mode (console `kill`, a planet's surface): the remaining hull points are applied
## as one hit with no shooter and `cause`, so `hit_taken`, `damaged` and `destroyed` fire as for any other hit. Returns false
## if it was already dead.
func kill(cause: StringName = HitInfo.CAUSE_CONSOLE) -> bool:
	if hull.destroyed:
		return false
	var b: Node3D = body()
	var info := HitInfo.new(b.get_instance_id() if b != null else 0, 0, &"", hull.hp, b.global_position if b != null else Vector3.ZERO,
			Vector3.ZERO, 0.0, cause)
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
