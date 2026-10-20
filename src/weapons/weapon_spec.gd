class_name WeaponSpec
extends Resource
## Tunable parameters of one weapon type (architecture §15.1, §15.2): the pulse cannon's muzzle speed, rate of fire,
## damage and bolt look, and the energy store that pays for the shots. Pure data, like `ShipSpec`: the cannon, the gate,
## the projectile and the tests read the same resource, so expected values in tests are derived from it. The defaults
## are the Starfury's M1 numbers.

## m/s, relative to the shooter: a bolt inherits the shooter's velocity and adds this along the nose.
@export var muzzle_speed_mps: float = 400.0
## s per bolt. ALTERNATING fires one bolt every interval; LINKED fires every muzzle together every interval × muzzles,
## so both modes put out the same number of bolts per second.
@export var shot_interval_s: float = 0.25
## Hull points taken from a hostile ship by one bolt.
@export var damage: float = 10.0
## s of sim time from launch to the bolt expiring.
@export var lifetime_s: float = 4.0
## m, the bolt's radius for hit detection (generous next to the visual `bolt_radius_m`).
@export var hit_radius_m: float = 0.25
## Material of the bolt capsule; null keeps the pulse bolt material.
@export var bolt_material: Material = null
## m, the visual capsule's length and radius.
@export var bolt_length_m: float = 1.5
@export var bolt_radius_m: float = 0.05
## Tint of the bolt's impact flash and sparks (and, later, of its sound). HDR, like the bolt material.
@export var bolt_color: Color = Color(3.0, 1.0, 0.5, 1.0)
## Energy units the capacitor holds when full (`WeaponCapacitor`).
@export var capacitor_capacity: float = 100.0
## Energy units one bolt costs.
@export var capacitor_cost_per_shot: float = 14.0
## Energy units regained per second.
@export var capacitor_recharge_per_s: float = 25.0


## A capacitor sized for this weapon, full.
func make_capacitor() -> WeaponCapacitor:
	return WeaponCapacitor.new(capacitor_capacity, capacitor_cost_per_shot, capacitor_recharge_per_s)
