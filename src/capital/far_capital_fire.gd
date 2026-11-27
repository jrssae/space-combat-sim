class_name FarCapitalFire
extends RefCounted
## Far capitals fire (M10-T85): a capital beyond the low-attention tier's radius fires its guns and launchers as seeded rolls
## on its tier row (`capital_far_fire.rs`, stepped by `ScsCapitalGuns` with the near mounts). This lands each tick's far hits
## in native batches on the damage store as the beams' are landed (M10-T75): each batch's writes onto the copies, its events,
## one summary a damaged ship (cause `bolt`), a kill's `destroyed`, the disguises it gave away, and a hit it left to land
## here. A disguised far shooter that fires on its transponder's side gives itself away, as near.

## Readouts since `reset_stats` (wall clock only in `land_us`): hits and hull points landed, batches, hits left to GDScript.
var hits: int = 0
var damage_landed: float = 0.0
var batches_last: int = 0
var deferred: int = 0
var land_us: int = 0


func reset_stats() -> void:
	hits = 0
	damage_landed = 0.0
	deferred = 0


## The step's far fire (`ScsCapitalGuns.step`'s last three entries): reveals for the mounts that fired, then the hits landed.
func take(rows: Object, out: Array, owners: Array[CapitalShip]) -> void:
	var started: int = Time.get_ticks_usec()  # readout only
	batches_last = 0
	var mounts: PackedInt32Array = out[14]
	var targets: PackedInt64Array = out[15]
	for k: int in mounts.size():
		var shooter: CapitalShip = owners[mounts[k]] if mounts[k] >= 0 and mounts[k] < owners.size() else null
		if shooter != null and is_instance_valid(shooter) and SimCore.is_disguised(shooter.get_instance_id()):
			Transponder.note_shot_at(shooter.get_instance_id(), targets[k])
	var count: int = int(out[16])
	if count > 0:
		_land(rows, count)
	land_us = Time.get_ticks_usec() - started


func _land(rows: Object, count: int) -> void:
	var friendly_fire: bool = bool(Settings.get_value(&"friendly_fire"))
	var god_mode: bool = DebugConsole.flags.invulnerable
	var now: float = SimClock.now()
	var sim: SimCore = SimCore.current()
	var names: Array = []  # the core's factions, read once a tick when a summary needs them
	var at: int = 0
	while at < count:
		var got: Array = rows.land_far(at, now, friendly_fire, god_mode)
		if got.is_empty():
			return
		batches_last += 1
		for shooter_id: int in got[5] as PackedInt64Array:
			var marker: Targetable = Targetable.of(instance_from_id(shooter_id) as Node) if is_instance_id_valid(shooter_id) else null
			if marker != null:
				marker.reveal()  # a disguised shooter that hit its own side's friend is found out
		DamageStore.take_writes(got[1])
		DamageStore.apply(got[2])
		var cols: Array = got[3]
		var targets: PackedInt64Array = cols[0]
		if not targets.is_empty() and names.is_empty() and sim != null:
			names = sim.core.factions()
		for k: int in targets.size():
			var hull: Damageable = instance_from_id(targets[k]) as Damageable if is_instance_id_valid(targets[k]) else null
			if hull != null:
				var summary: HitSummary = HitSummary.from_columns(cols, k, names)
				summary.cause = HitInfo.CAUSE_BOLT
				hull.land_summary(summary)
		var kill: Dictionary = got[4]
		if not kill.is_empty():
			_announce_kill(kill)
		hits += int(got[7])
		damage_landed += float(got[8])
		var left: int = int(got[6])
		if left >= 0:
			deferred += 1
			_land_one(rows.far_hit(left))
		at = int(got[0])


# The hit that destroyed its hull: its `destroyed`, with the hit as a bolt's would carry it.
func _announce_kill(kill: Dictionary) -> void:
	var hull: Damageable = instance_from_id(int(kill["target"])) as Damageable if is_instance_id_valid(int(kill["target"])) else null
	if hull == null:
		return
	var info: HitInfo = _info(int(kill["shooter"]), int(kill["body"]), float(kill["damage"]), kill["point"] as Vector3)
	info.volume = int(kill["volume"])
	info.applied = float(kill["applied"])
	hull.destroyed.emit(info)


# A hit the batch left to GDScript (a hull it holds no landing for yet, a capital volume it cannot name): through its
# `Damageable`, which takes the batch's landing from now on.
func _land_one(hit: Array) -> void:
	if hit.is_empty():
		return
	var damageable: Damageable = BlastResolver.hurtable(int(hit[1]))
	var shooter: CapitalShip = _ship(int(hit[6]))
	if damageable == null or shooter == null:
		return
	damageable.push_landing()
	if not damageable.can_be_hit_by(shooter.faction, bool(Settings.get_value(&"friendly_fire"))):
		return
	var info: HitInfo = _info(int(hit[6]), int(hit[2]), float(hit[5]), hit[3] as Vector3)
	info.volume = int(hit[4])
	var sim: SimCore = SimCore.current()
	if sim != null:
		sim.note_hit(info.target_id, info.shooter_id)  # the turrets' attacker memory (M5-T21)
	Transponder.note_hit(info.shooter_id, damageable)
	damageable.apply_hit(info)
	hits += 1
	damage_landed += info.damage


# A far hit by ship `shooter_id` on body `body_id` at `point` as a `HitInfo` (cause `bolt`).
func _info(shooter_id: int, body_id: int, damage: float, point: Vector3) -> HitInfo:
	var shooter: CapitalShip = _ship(shooter_id)
	return HitInfo.new(body_id, shooter_id if shooter != null else 0, shooter.faction if shooter != null else &"", damage, point,
			Vector3.ZERO, 0.0, HitInfo.CAUSE_BOLT)


func _ship(body_id: int) -> CapitalShip:
	return instance_from_id(body_id) as CapitalShip if is_instance_id_valid(body_id) else null
