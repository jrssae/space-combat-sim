class_name TurretRows
extends RefCounted
## The defensive turrets' facade on the native core (M5-T21, D61, architecture §18): binds each `TurretMount` to a mount
## row in `ScsSimCore`, keeps the relation table the turrets' pick reads in step with `Factions`, steps the mounts once a
## tick from `SimCore.step_now` (aim, fire gate and shot, all in the core; the shots become owned bolt rows the hit sweep
## lands like any other) and hands each shot back to its mount for the sound. The target pick runs in the AI job
## (`ScsBrains`, one tick behind) and the attacker memory is fed by `HitResolver` in the sweep's order. No turret runs any
## GDScript per tick: this is one call a tick and a loop over the tick's shots.

## How a turret's `WeaponSpec` packs for the core (`turret_rows.rs`, `GUN_LEN`).
const GUN_LEN: int = 9

var sim: SimCore = null
var shots_last_tick: int = 0
var step_us: int = 0

var _mounts: Dictionary[int, TurretMount] = {}
var _relations_count: int = -1
var _relations_table: FactionTable = null
var _relations_revision: int = -1


func _init(p_sim: SimCore) -> void:
	sim = p_sim


## Mounts `mount` on body `body_id` and returns its slot (-1 when the core refused it).
func register(mount: TurretMount, body_id: int, weapon: WeaponSpec, faction: StringName) -> int:
	if sim == null or sim.core == null or weapon == null:
		return -1
	var slot: int = int(sim.core.add_turret(body_id, mount.position, mount.up, mount.arc_deg, mount.barrel_m, faction,
			gun_of(weapon), weapon.bolt_color, BoltMesh.look_for(weapon)))
	if slot < 0:
		return -1
	_mounts[slot] = mount
	return slot


func unregister(slot: int) -> void:
	_mounts.erase(slot)
	if sim != null and sim.core != null:
		sim.core.remove_turret(slot)


## Turrets mounted now.
func count() -> int:
	return _mounts.size()


## The mount in `slot`, or null.
func mount_at(slot: int) -> TurretMount:
	return _mounts.get(slot)


## One tick of every turret (from `SimCore.step_now`, after the cannons and before the bolts move): the relations brought
## up to date, the core's step, and each shot handed to its mount.
func step(now_s: float, delta: float) -> void:
	shots_last_tick = 0
	if _mounts.is_empty():
		return
	var started: int = Time.get_ticks_usec()  # readout only
	refresh_relations()
	var out: Array = sim.core.step_turrets(now_s, delta)
	var slots: PackedInt32Array = out[0]
	var starts: PackedVector3Array = out[1]
	shots_last_tick = slots.size()
	for k: int in slots.size():
		var mount: TurretMount = _mounts.get(slots[k])
		if mount != null and is_instance_valid(mount):
			mount.on_fired(starts[k])
	step_us = Time.get_ticks_usec() - started


## Builds the relation table again when the core knows a new faction, another faction table is active or the active one
## changed a relation (the console's `relation`).
func refresh_relations() -> void:
	var count_now: int = int(sim.core.faction_count())
	var table: FactionTable = Factions.table()
	if count_now == _relations_count and table == _relations_table and table.revision == _relations_revision:
		return
	_relations_count = count_now
	_relations_table = table
	_relations_revision = table.revision
	var names: Array = sim.core.factions()
	var matrix := PackedByteArray()
	matrix.resize(count_now * count_now)
	for a: int in count_now:
		for b: int in count_now:
			matrix[a * count_now + b] = Factions.relation(names[a], names[b])
	sim.core.set_turret_relations(count_now, matrix)


## A turret weapon's numbers as the core takes them.
static func gun_of(weapon: WeaponSpec) -> PackedFloat64Array:
	return PackedFloat64Array([weapon.muzzle_speed_mps, weapon.shot_interval_s, weapon.lifetime_s, weapon.damage,
			weapon.hit_radius_m, weapon.turret_range_m, weapon.turret_spread_deg, weapon.turret_traverse_deg_s,
			weapon.turret_elevation_deg_s])
