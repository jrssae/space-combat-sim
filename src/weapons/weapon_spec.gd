class_name WeaponSpec
extends Resource
## Tunable parameters of one weapon type (architecture §15.1, §15.2): the pulse cannon's muzzle speed, rate of fire,
## damage and bolt look, and the energy store that pays for the shots. Pure data, like `ShipSpec`: the cannon, the gate,
## the projectile and the tests read the same resource, so expected values in tests are derived from it. The defaults
## are the Starfury's M1 numbers.

## m/s, relative to the shooter: a bolt inherits the shooter's velocity and adds this along the nose.
@export var muzzle_speed_mps: float = 1000.0
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
@export var bolt_color: Color = Color(0.9, 1.5, 3.0, 1.0)
## m: where the muzzles' lines cross, measured ahead of the ship along its nose. 0 = the guns fire parallel (the Starfury).
## A raider's guns are spread over a 6 m width, so parallel bolts would miss a small target aimed at its centre: with a
## convergence range each muzzle aims at the point that far ahead, and the bolts hit the aim point at that range.
@export var convergence_range_m: float = 0.0
## Energy units the capacitor holds when full (`WeaponCapacitor`).
@export var capacitor_capacity: float = 100.0
## Energy units one bolt costs.
@export var capacitor_cost_per_shot: float = 14.0
## Energy units regained per second.
@export var capacitor_recharge_per_s: float = 25.0

@export_group("Turret")
## Read only by a defensive turret (M5-T21, D61): m, the farthest it fires at; degrees, its bolts' spread round the barrel;
## degrees per second, how fast it traverses round its base and lifts its barrel.
@export var turret_range_m: float = 1500.0
@export var turret_spread_deg: float = 0.8
@export var turret_traverse_deg_s: float = 50.0
@export var turret_elevation_deg_s: float = 40.0
## Bursts (M7-T43, the heavy cannon): shots a burst, `burst_spacing_s` apart; `shot_interval_s` is then the whole cycle, from one
## burst's first shot to the next's. One shot a burst is a plain gun.
@export var burst_shots: int = 1
@export var burst_spacing_s: float = 0.0

@export_group("Capital")
## M10-T12 to T16 (D12.9): the weapon's `loadouts.json` id and role (`ac` anti-capital: the hull's `damage_scale` multiplies
## it, Q54; `af` anti-fighter; `dual`; `fighter`) and its one trait (`kinetic`, `push`, or none).
@export var weapon_id: StringName = &""
@export var role: StringName = &""
@export var weapon_trait: StringName = &""
## M10-T14: bolts (or missiles) a capital gun (or launcher) fires together each shot, side by side; the loadouts' `barrels`.
@export var barrels: int = 1

@export_group("Beam")
## M10-T12 (D12.9): 0 not a beam, 1 pulsed (one tick, `damage` on the first hull on the line), 2 sustained (on for `beam_on_s`,
## `beam_dps` each tick to the first hull under the line). A beam fires every `shot_interval_s` (its cycle), after
## `beam_charge_s` of charge, as far as `beam_range_m`, its emitter turning at `turret_traverse_deg_s`; it is drawn in
## `bolt_color`, `beam_width_m` across. A pulsed emitter with `burst_shots` barrels lands them as one pulse.
@export_enum("none", "pulsed", "sustained") var beam_kind: int = 0
@export var beam_dps: float = 0.0
@export var beam_on_s: float = 0.0
@export var beam_charge_s: float = 0.0
@export var beam_range_m: float = 0.0
@export var beam_width_m: float = 3.0

@export_group("Missile")
## M10-T14 (D12.9): 0 a gun's bolt, 1 a guided missile, 2 a torpedo; a missile's or torpedo's warhead blasts where it strikes
## (`BlastTable`'s `missile` or `torpedo` row). Guided by proportional navigation at `missile_nav_gain`, turning at most
## `missile_turn_rad_s`, at `muzzle_speed_mps` for `lifetime_s`; launched at targets within `turret_range_m` inside the
## launcher's arc. `toughness`: interceptor pulses it takes to stop one of these shots (T13).
@export_enum("none", "missile", "torpedo") var warhead: int = 0
@export var missile_nav_gain: float = 4.0
@export var missile_turn_rad_s: float = 0.6
@export var toughness: int = 1


## A capacitor sized for this weapon, full.
func make_capacitor() -> WeaponCapacitor:
	return WeaponCapacitor.new(capacitor_capacity, capacitor_cost_per_shot, capacitor_recharge_per_s)


const WEAPON_DIR: String = "res://assets/weapons"
const BEAM_NONE: int = 0
const BEAM_PULSED: int = 1
const BEAM_SUSTAINED: int = 2
const WARHEAD_NONE: int = 0
const WARHEAD_MISSILE: int = 1
const WARHEAD_TORPEDO: int = 2


## The spec of capital weapon `id` (`assets/weapons/<id>.tres`), or null.
static func of_weapon(id: StringName) -> WeaponSpec:
	var path: String = "%s/%s.tres" % [WEAPON_DIR, id]
	return load(path) as WeaponSpec if ResourceLoader.exists(path) else null


## The bolt colour of every bolt weapon's spec under `assets/weapons` (not the beams'), each once: what the impact flashes
## are warmed for at load.
static func known_bolt_colors() -> Array[Color]:
	var out: Array[Color] = []
	for file: String in DirAccess.get_files_at(WEAPON_DIR):
		var path: String = "%s/%s" % [WEAPON_DIR, file.trim_suffix(".remap")]
		if not path.ends_with(".tres"):
			continue
		var spec := load(path) as WeaponSpec
		if spec != null and spec.beam_kind == BEAM_NONE and not out.has(spec.bolt_color):
			out.append(spec.bolt_color)
	return out
