class_name CapitalSection
extends RefCounted
## One damage section of a capital ship (M10-T08, D12.5): its share of the hull's points, its state and the subsystems it holds
## (weapon mounts, bays, engines), which are lost with it. `CapitalDamage` moves it from state to state. Pure.

enum State {
	INTACT,  ## never hit
	DAMAGED,  ## hit, points left
	DISABLED,  ## at 0: what it holds is lost; a reactor has shut down and can still blow
	DESTROYED,  ## blown up (a magazine, fuel or reactor section)
}

const REACTOR: String = "reactor"
const MAGAZINE: String = "magazine"
const FUEL: String = "fuel"
const BRIDGE: String = "bridge"
const ENGINE: String = "engine"
const HANGAR: String = "hangar"
## The kinds that blow up when lost (a reactor only after its overload).
const EXPLOSIVE_KINDS: Array[String] = [REACTOR, MAGAZINE, FUEL]

var name: String = ""
var kind: String = ""
## The body it sits on (`hull`, or a rotating piece).
var piece: String = CapitalSections.HULL
var max_hp: float = 1.0
var hp: float = 1.0
## A reactor's points taken since it shut down: it blows at `CapitalData.section_rule("reactor_overload")` of `max_hp`.
var overload: float = 0.0
var state: State = State.INTACT
## The hardpoints it holds, by list (names).
var mounts := PackedStringArray()
var bays := PackedStringArray()
var engines := PackedStringArray()
## Its box in the body frame with the rotating pieces at rest (the manifest's `aabb_min`, `aabb_max`).
var box := AABB()


## Whether what it holds is gone (disabled or destroyed).
func lost() -> bool:
	return state == State.DISABLED or state == State.DESTROYED


func explosive() -> bool:
	return EXPLOSIVE_KINDS.has(kind)


## Points left, 0 to 1.
func fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0


## How far `p` (body frame at rest) is from its box, 0 inside.
func distance_to(p: Vector3) -> float:
	var nearest: Vector3 = p.clamp(box.position, box.end)
	return p.distance_to(nearest)


## Whole again (a heal, a pool re-use).
func restore() -> void:
	hp = max_hp
	overload = 0.0
	state = State.INTACT


static func state_name(s: State) -> String:
	return String(State.find_key(s)).to_lower()
