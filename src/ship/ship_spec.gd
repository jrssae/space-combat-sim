class_name ShipSpec
extends Resource
## Tunable parameters of one ship type (architecture §5.1). Pure data: the flight model, the ship node and the
## tests all read the same resource, so expected values in tests are derived from it, never hard-coded.
##
## Mass and inertia are design values, not the generator's `mass_kg` / `inertia_estimate_kg_m2` from
## `hardpoints.json`: the estimate is point masses at part centroids (a lower bound, documented as informational
## in docs/assets-starfury.md), while the rates, RCS torque (= inertia × angular acceleration) and the trim numbers
## in §5.1 are all pinned to the inertia here. Geometry (nozzle positions, centre of mass) does come from the
## hardpoints, through `ThrusterLayout`.

## Folder name under assets/generated/ that holds this ship's splats, meshes and hardpoints.json.
@export var asset_id: String = ""
## kg.
@export var mass: float = 48000.0
## Body-frame diagonal inertia, kg·m²: x pitch, y yaw, z roll.
@export var inertia: Vector3 = Vector3(6.0e5, 6.0e5, 5.0e5)
## N per pod main nozzle (exhaust +Z, thrust forward).
@export var pod_main_thrust: float = 3.6e5
## N per pod retro nozzle (exhaust -Z, thrust aft).
@export var pod_retro_thrust: float = 1.8e5
## N, body frame: x sway, y heave, z 0 (fore/aft is the pods' job).
@export var rcs_force_max: Vector3 = Vector3(4.8e5, 4.8e5, 0.0)
## N·m, body frame: x pitch, y yaw, z roll.
@export var rcs_torque_max: Vector3 = Vector3(9.4e5, 9.4e5, 1.57e6)
## deg/s, pilot axes (pitch, yaw, roll): the assist's rate target at full deflection.
@export var rate_max: Vector3 = Vector3(60.0, 60.0, 90.0)
## s⁻¹, rate controller P gain.
@export var assist_gain_k: float = 6.0
## Assist on: one full one-sided trigger commands `pod_yaw_gain × rate_max.y` of yaw.
@export var pod_yaw_gain: float = 0.5
## Assist on: trigger (and bumper) side differences below this fly straight.
@export var pod_yaw_deadzone: float = 0.10
## s, first-order smoothing time constant of the pod-yaw command.
@export var pod_yaw_smoothing_s: float = 0.15
## s⁻¹, translational brake P gain.
@export var brake_gain_k: float = 2.0
## m/s, the reaction-mass flow: `mass_flow = Σ thrust / exhaust_velocity` (`FlightOutput.mass_flow_kg_s`).
@export var exhaust_velocity: float = 30000.0
## kg of reaction mass the tank holds (`FuelTank`). The default is 10 minutes of both pods' mains at full
## (4 × 0.36 MN / 30 km/s = 48 kg/s × 600 s). Only drawn down when `settings.fuel_unlimited` is off.
@export var fuel_capacity_kg: float = 28800.0
## m/s: the hard ceiling. Inertia grows with speed (`SpeedGovernor`), so thrust fades to zero as the ship nears it.
@export var speed_limit_mps: float = 9999.0
## m/s: flight assist's "maximum safe speed". With assist on, thrust that would push the ship faster than this is
## cancelled; with assist off the ship can go on up to `speed_limit_mps`.
@export var assist_speed_max_mps: float = 5000.0
## Hull points (`HullHealth`, M2-T03). 300 is about 30 hits from a Starfury pulse bolt.
@export var hull_max: float = 300.0
## m/s: ram damage (§16 D32, `RamMath`). A change of the ship's own velocity up to this in a collision is harmless...
@export var ram_safe_dv_mps: float = 5.0
## m/s: ... and one of this or more takes the whole hull, quadratic in between. A 30 m/s head-on between two Starfuries is
## about 15 m/s each, about 60 % of the hull at the Starfury's 18.
@export var ram_lethal_dv_mps: float = 18.0
## HDR colour of the engine plumes (`ThrusterVisuals`). The default is the Starfury's blue-white.
@export var engine_glow_color: Color = Color(0.7, 0.9, 1.8, 1.0)
## Which main components the HUD's damage silhouette shows (`DamageZones.layout_from_name`): `x_fighter` or `delta`.
@export var damage_layout: StringName = &"x_fighter"
## The ship's guns; null falls back to a default `WeaponSpec` (the Starfury's M1 numbers).
@export var weapon: WeaponSpec = null


## Whether the asset has a first-person `cockpit_interior.obj` (the Starfury does; AI ships such as the raider do not,
## so the ship does not look for it or warn about it).
@export var has_cockpit_interior: bool = true
## Which level of detail of the asset's splats the hull draws: 0 is the full `<asset_id>.ply`, a higher level is the one the
## asset's `manifest.json` lists under `lods` (`SplatLod`). Allied Starfuries draw LOD1, about a quarter of the splats (§16 D35).
## The collision, hardpoints, fallback mesh and break-up chunks are the asset's, whatever the level.
@export_range(0, 8) var splat_lod: int = 0


## Where this ship's generated hardpoints live.
func hardpoints_path() -> String:
	return "res://assets/generated/%s/hardpoints.json" % asset_id


## `rate_max` in rad/s.
func rate_max_rad() -> Vector3:
	return Vector3(deg_to_rad(rate_max.x), deg_to_rad(rate_max.y), deg_to_rad(rate_max.z))
