class_name BlastHits
extends RefCounted
## Test fixture (M10-T76): the blast hits a hull takes, as `HitInfo`s, in the order it heard of them. Blasts land in the native
## batch (`BlastResolver`), which tells a ship of a batch's blast hits once, as a `HitSummary`; a batch that hurt it once gives
## one entry with that hit's damage, point, shooter and points removed (two blasts in one batch give one entry with their sum and
## the last one's point). A hit the batch left to GDScript still comes as a `hit_taken` and is taken too.


## The blast hits `damageable` takes from now on; with `every_cause`, its other hits (`hit_taken`) as well, in order.
static func of(damageable: Damageable, every_cause: bool = false) -> Array[HitInfo]:
	var out: Array[HitInfo] = []
	damageable.hits_landed.connect(func(summary: HitSummary) -> void:
		if summary.cause == HitInfo.CAUSE_BLAST:
			var info := HitInfo.new(summary.target_id, summary.last_shooter, &"", summary.damage, summary.point, Vector3.ZERO,
					0.0, HitInfo.CAUSE_BLAST)
			info.applied = summary.applied
			out.append(info))
	damageable.hit_taken.connect(func(info: HitInfo) -> void:
		if every_cause or info.cause == HitInfo.CAUSE_BLAST:
			out.append(info))
	return out
