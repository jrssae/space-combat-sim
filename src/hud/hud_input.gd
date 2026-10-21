class_name HudInput
extends RefCounted
## Everything `HudLayout.compute` needs for one frame (architecture §15.9): the camera, the player's state, the selected
## target and the contacts. Plain data, filled by `Main` each rendered frame from the live nodes (never cached), so the layout
## stays pure and testable.

## The active camera: global transform, `Camera3D.get_camera_projection()` and the viewport size in pixels.
var camera_transform: Transform3D = Transform3D.IDENTITY
var projection: Projection = Projection.IDENTITY
var viewport_size: Vector2 = Vector2(1920.0, 1080.0)
var cockpit: bool = false
## The targeting grid is shown in the chase view too (`settings.hud_targeting_grid`).
var show_grid: bool = false

## The player ship, World frame: pose, velocity, the mean muzzle position and the weapon's bolt speed and lifetime.
var own_position: Vector3 = Vector3.ZERO
var own_basis: Basis = Basis.IDENTITY
var own_velocity: Vector3 = Vector3.ZERO
var muzzle_position: Vector3 = Vector3.ZERO
var weapon_speed_mps: float = 1000.0
var weapon_lifetime_s: float = 4.0
var faction: StringName = Factions.EARTH_ALLIANCE

## Gauges, 0..1 (fuel is 1 and `fuel_unlimited` true while the tank is never drawn down).
var hull_fraction: float = 1.0
var god: bool = false
var fuel_fraction: float = 1.0
var fuel_unlimited: bool = true
var charge_fraction: float = 1.0
var fire_mode: String = "alternating"

## The selected target (position, velocity, faction, name, range, closing speed, hull or -1, bounding radius), or null.
var target: TargetReadout = null
## Every targetable in sensor range as of this tick, and which one is selected (0 = none).
var contacts: Array[TargetInfo] = []
var selected_id: int = 0
## One line at the top centre (wave, raiders left, kills); empty until the wave director feeds it.
var status_line: String = ""
