class_name HitInfo
extends RefCounted
## One resolved hit (architecture §15.4, §15.5, §16 D32): plain data from `HitResolver` (a bolt), `RamResolver` (a ram) or
## the console to `Damageable.apply_hit`, and on to the HUD, the impact flash, the sound and the kill counter via
## `hit_resolved` / `ram_resolved` / `hit_taken` / `damaged`.

const CAUSE_BOLT: StringName = &"bolt"
const CAUSE_RAM: StringName = &"ram"
const CAUSE_CONSOLE: StringName = &"console"
## The ship hit a planet or dropped below its atmosphere's top (M6-T08, D67).
const CAUSE_PLANET: StringName = &"planet"
## The ship was in a jump point's funnel when the point collapsed (M6-T23, `JumpPointPool`): no shooter, no kill credit.
const CAUSE_VORTEX_COLLAPSE: StringName = &"vortex_collapse"
## The ship sat where a jump point's vortex formed, or was still in it when it closed (M8-T17, maintainer 2026-11-19: jump points
## kill): no shooter, no kill credit.
const CAUSE_VORTEX: StringName = &"vortex"
## The ship sat docked on a carrier that was destroyed (M12-T19, Q28, `CarrierDock`): no shooter, no kill credit.
const CAUSE_CARRIER_LOST: StringName = &"carrier_lost"
## A blast's damage (M10-T09, `BlastResolver`): a death, a section blowing, a missile's warhead.
const CAUSE_BLAST: StringName = &"blast"
## A disabled hulk scuttled past the cap on hulks kept (M10-T10, Q19, `CapitalFlight`): no shooter, no kill credit.
const CAUSE_SCUTTLE: StringName = &"scuttle"

## Instance id of the `Damageable` (or its ship) that was hit.
var target_id: int = 0
## Instance id of the ship that fired the bolt, or of the other body in a ram; never equal to `target_id` for a resolved
## hit. 0 for the console.
var shooter_id: int = 0
## Faction of the bolt (its shooter's faction), or of the other body in a ram.
var faction: StringName = &""
## Hull points the hit carries (`WeaponSpec.damage`, or the ram's share of the hull).
var damage: float = 0.0
## Where the bolt entered the hit volume, or where the ram touched, `World`-local.
var point: Vector3 = Vector3.ZERO
## Surface normal at `point`, best effort: the reversed relative direction of the bolt is acceptable.
var normal: Vector3 = Vector3.ZERO
## Speed of the bolt (or the other body) relative to the target at impact.
var relative_speed_mps: float = 0.0
## What did it: `bolt` (`HitResolver`), `ram` (`RamResolver`), `console` (`damage`, `kill`), `planet` (`PlanetImpact`),
## `vortex_collapse` (a collapsing jump point) or `blast` (`BlastResolver`).
var cause: StringName = CAUSE_BOLT
## Hull points actually removed; 0 until the `Damageable` has applied the hit (and for god mode or a dead hull).
var applied: float = 0.0
## On the hit that destroyed a ship (M4-T22, set by `DestructionDirector` before its signals): the death's blast (M10-T09,
## `BlastTable`), its energy (J), its radius (m) and its centre (`World`-local), for the far explosions (M4-T23). 0 otherwise.
var blast_energy_j: float = 0.0
var blast_radius_m: float = 0.0
var blast_point: Vector3 = Vector3.ZERO
## The big hull's surface volume the bolt entered first, as the core's sweep found it (a capital's hit lands on that volume's
## section, M10-T08), or the one nearest a blast (M10-T09); -1 for any other hit.
var volume: int = -1


func _init(p_target_id: int = 0, p_shooter_id: int = 0, p_faction: StringName = &"", p_damage: float = 0.0,
		p_point: Vector3 = Vector3.ZERO, p_normal: Vector3 = Vector3.ZERO, p_relative_speed_mps: float = 0.0,
		p_cause: StringName = CAUSE_BOLT) -> void:
	target_id = p_target_id
	shooter_id = p_shooter_id
	faction = p_faction
	damage = p_damage
	point = p_point
	normal = p_normal
	relative_speed_mps = p_relative_speed_mps
	cause = p_cause


func _to_string() -> String:
	return "HitInfo(%s %d -> %d %s damage %.1f applied %.1f at %s)" % [cause, shooter_id, target_id, faction, damage,
			applied, point]
