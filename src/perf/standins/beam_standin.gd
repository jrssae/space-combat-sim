class_name BeamStandin
extends Node3D
## A capital's beam laser stand-in (M4-T12, Q19): bench-only, replaced by M12's lasers. A hitscan shot: a `Projectile` of
## kind beam whose whole 3 km segment is its one tick of flight, so the hit resolver sweeps it through the hit broad phase in
## the tick it fires, lands it on the first hull along it and retires it. `StandinDirector` fires each emitter every
## `INTERVAL_S` at its capital's hostile fighter when that is within reach; an emitter has no process of its own.

const RANGE_M: float = 3000.0
const INTERVAL_S: float = 2.0
const DAMAGE: float = 25.0
## A beam the resolver never saw (no resolver in the tree) frees itself after this, s.
const LIFETIME_S: float = 0.1
const COLOR: Color = Color(3.0, 0.6, 0.6, 1.0)
const PROJECTILE_SCENE: PackedScene = preload("res://src/weapons/projectile.tscn")

static var _weapon: WeaponSpec = null

var capital: CapitalStandin = null
## Beams fired.
var shots: int = 0


static func weapon() -> WeaponSpec:
	if _weapon == null:
		_weapon = WeaponSpec.new()
		_weapon.lifetime_s = LIFETIME_S
		_weapon.damage = DAMAGE
		_weapon.hit_radius_m = Projectile.hit_radius_for(Projectile.KIND_BEAM)
		_weapon.bolt_color = COLOR
	return _weapon


## Fires one beam toward `at` (World frame), its full length, under `projectiles`; returns it.
func fire(at: Vector3, now_s: float, projectiles: Node3D) -> Projectile:
	var from: Vector3 = global_position
	var line: Vector3 = at - from
	var direction: Vector3 = line.normalized() if line.length_squared() > 1e-6 else -global_basis.z
	var beam := PROJECTILE_SCENE.instantiate() as Projectile
	projectiles.add_child(beam)
	beam.configure(weapon())
	if capital != null:
		beam.shooter_id = capital.get_instance_id()
		beam.faction = capital.faction
	beam.fire_beam(from, from + direction * RANGE_M, now_s)
	shots += 1
	return beam
