class_name FxSpecs
extends RefCounted
## The particle effects of combat (M3-T23, architecture D8): how many emitters each pool holds, how much each throws and how
## fast, plus the pure maths that aims a burst and scales it by `settings.particle_density`. The process materials and meshes
## that realise these numbers are in `assets/fx/`; a test keeps the two in step.

const HIT: int = 0
const RAM: int = 1
const EXPLOSION_SPARKS: int = 2
const EXPLOSION_FRAGMENTS: int = 3
const EXPLOSION_GAS: int = 4
const DEBRIS: int = 5
const COUNT: int = 6

## A chunk vents for this long (2-4 s), always well inside its own 8 s life.
const DEBRIS_MIN_S: float = 2.0
const DEBRIS_MAX_S: float = 4.0

const _STREAK_MESH: String = "res://assets/fx/fx_streak_mesh.tres"
const _FRAGMENT_MESH: String = "res://assets/fx/fx_fragment_mesh.tres"
const _GAS_MESH: String = "res://assets/fx/fx_gas_mesh.tres"

# Per effect: pool size, particles per full burst, particle lifetime (the longest), launch speed range relative to the source,
# cone half-angle around the burst direction, whether it keeps emitting until stopped (a vent), and its resources.
const _SPECS: Array[Dictionary] = [
	{"name": "hit", "emitters": 12, "amount": 24, "lifetime_s": 0.45, "speed_mps": Vector2(20.0, 70.0), "spread_deg": 28.0,
			"continuous": false, "material": "res://assets/fx/fx_hit.tres", "mesh": _STREAK_MESH},
	{"name": "ram", "emitters": 6, "amount": 48, "lifetime_s": 0.9, "speed_mps": Vector2(10.0, 60.0), "spread_deg": 70.0,
			"continuous": false, "material": "res://assets/fx/fx_ram.tres", "mesh": _STREAK_MESH},
	{"name": "explosion_sparks", "emitters": 4, "amount": 80, "lifetime_s": 1.2, "speed_mps": Vector2(40.0, 150.0), "spread_deg": 180.0,
			"continuous": false, "material": "res://assets/fx/fx_explosion_sparks.tres", "mesh": _STREAK_MESH},
	{"name": "explosion_fragments", "emitters": 4, "amount": 20, "lifetime_s": 3.0, "speed_mps": Vector2(5.0, 20.0), "spread_deg": 180.0,
			"continuous": false, "material": "res://assets/fx/fx_explosion_fragments.tres", "mesh": _FRAGMENT_MESH},
	{"name": "explosion_gas", "emitters": 4, "amount": 10, "lifetime_s": 0.7, "speed_mps": Vector2(8.0, 18.0), "spread_deg": 180.0,
			"continuous": false, "material": "res://assets/fx/fx_explosion_gas.tres", "mesh": _GAS_MESH},
	{"name": "debris", "emitters": 10, "amount": 36, "lifetime_s": 0.8, "speed_mps": Vector2(1.0, 6.0), "spread_deg": 180.0,
			"continuous": true, "material": "res://assets/fx/fx_debris.tres", "mesh": _STREAK_MESH},
]


## The numbers of `effect` (`HIT` ... `DEBRIS`).
static func spec(effect: int) -> Dictionary:
	return _SPECS[effect]


## Particles a burst throws at `density` (0-1, `settings.particle_density`): 0 at 0, the full amount at 1.
static func amount_for(effect: int, density: float) -> int:
	return roundi(int(_SPECS[effect]["amount"]) * clampf(density, 0.0, 1.0))


## The share of the emitter's particles that `amount_for` keeps, for `GPUParticles3D.amount_ratio`.
static func ratio_for(effect: int, density: float) -> float:
	return float(amount_for(effect, density)) / float(int(_SPECS[effect]["amount"]))


## Where hull-hit sparks fly: the bolt's direction mirrored about the hull's surface normal, always on the outer side.
static func hit_direction(bolt_direction: Vector3, surface_normal: Vector3) -> Vector3:
	if surface_normal.length_squared() < 1e-12:
		return -bolt_direction.normalized() if bolt_direction.length_squared() > 1e-12 else Vector3.UP
	var normal: Vector3 = surface_normal.normalized()
	if bolt_direction.length_squared() < 1e-12:
		return normal
	var incoming: Vector3 = bolt_direction.normalized()
	if incoming.dot(normal) > 0.0:
		normal = -normal  # a normal that faces away from the bolt is the far side of the same surface
	return (incoming - 2.0 * incoming.dot(normal) * normal).normalized()


## A rotation whose +Y is `direction`, which is the way a burst's cone points. Identity for no direction.
static func basis_facing(direction: Vector3) -> Basis:
	if direction.length_squared() < 1e-12:
		return Basis.IDENTITY
	var y: Vector3 = direction.normalized()
	var helper: Vector3 = Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var z: Vector3 = helper.cross(y).normalized()
	return Basis(y.cross(z), y, z)


## How long a chunk vents, from `unit` in 0-1 (a seeded random number, so a break-up looks the same each time).
static func debris_duration_s(unit: float) -> float:
	return lerpf(DEBRIS_MIN_S, DEBRIS_MAX_S, clampf(unit, 0.0, 1.0))


## How long an emitter stays taken by a burst: a one-shot until its last particle dies, a vent for `duration_s` plus that tail.
static func busy_s(effect: int, duration_s: float) -> float:
	var life: float = _SPECS[effect]["lifetime_s"]
	return life + (maxf(duration_s, 0.0) if _SPECS[effect]["continuous"] else 0.0)
