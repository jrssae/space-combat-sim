class_name JumpCapability
extends RefCounted
## Who may open a jump point and how long it holds (M6-T23, the maintainer's rule of 2026-11-13). Only a jump-capable ship opens
## one: today the capital stand-ins; every designed hull (the Starfury, the raiders, the civilian ships) cannot, and arrives or
## leaves through a jumpgate or through a point a capable ship holds open (any side's). Pure apart from reading the ship.
##
## A point holds only while its opener is near it: within its hold range (by default twice its length) from the ship to the
## funnel's mouth. Out of range, destroyed or disabled, the point collapses at once and kills every ship in its funnel. An opener
## leaving through its own point holds it a few seconds more for the ships behind it. Gates are exempt.

## A ship's hold range, in lengths, when its type gives none.
const HOLD_LENGTHS: float = 2.0
## How long a point stays open after its opener touched its own black ring, for the ships behind it, s.
const OWN_DEPARTURE_HOLD_S: float = 3.0

## Why a point collapses (`verdict`); empty while it holds.
const HOLDS: StringName = &""
const GONE: StringName = &"opener_gone"
const DESTROYED: StringName = &"opener_destroyed"
const DISABLED: StringName = &"opener_disabled"
const OUT_OF_RANGE: StringName = &"out_of_range"
const OPENER_THROUGH: StringName = &"opener_through"


## The hold range for a ship of `length_m`, or `override_m` when its type sets one.
static func hold_range_m(length_m: float, override_m: float = 0.0) -> float:
	return override_m if override_m > 0.0 else HOLD_LENGTHS * maxf(length_m, 0.0)


## Whether a point still holds, and if not, why. `through_s` is how long ago the opener touched its own ring (negative: it has
## not), which ends the point once the short hold is over whatever else is true.
static func verdict(opener_valid: bool, destroyed: bool, disabled: bool, distance_m: float, range_m: float,
		through_s: float = -1.0) -> StringName:
	if through_s >= 0.0:
		return OPENER_THROUGH if through_s >= OWN_DEPARTURE_HOLD_S else HOLDS
	if not opener_valid:
		return GONE
	if destroyed:
		return DESTROYED
	if disabled:
		return DISABLED
	if distance_m > range_m:
		return OUT_OF_RANGE
	return HOLDS


## Whether `ship` can open a jump point of its own.
static func can_open(ship: Node) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if ship is Ship:
		var spec: ShipSpec = (ship as Ship).spec
		return spec != null and spec.can_open_jump_point
	if ship.has_method(&"can_open_jump_point"):
		return bool(ship.call(&"can_open_jump_point"))
	return false


## `ship`'s hold range, m: its type's value, else twice its length (0 for a ship that cannot open a point).
static func hold_range_of(ship: Node) -> float:
	if not can_open(ship):
		return 0.0
	if ship is Ship:
		return hold_range_m(length_of(ship), (ship as Ship).spec.jump_hold_range_m)
	if ship.has_method(&"jump_hold_range_m"):
		return float(ship.call(&"jump_hold_range_m"))
	return hold_range_m(length_of(ship))


## `ship`'s length along its nose at its whole size, m (a ship shrunk in a funnel keeps its length).
static func length_of(ship: Node) -> float:
	if ship != null and ship.has_method(&"length_m"):
		return float(ship.call(&"length_m"))
	var damageable: Damageable = Damageable.of(ship)
	if damageable == null or damageable.ram_bounds.size == Vector3.ZERO:
		return 0.0
	return damageable.ram_bounds.size.z / maxf(damageable.hull_scale, 1e-3)


## Whether `ship` cannot hold anything open: destroyed, or a disabled hulk.
static func is_destroyed(ship: Node) -> bool:
	var damageable: Damageable = Damageable.of(ship)
	return damageable != null and damageable.hull != null and damageable.hull.destroyed


static func is_disabled(ship: Node) -> bool:
	return ship is Ship and (ship as Ship).hulk
