class_name CapitalBreakup
extends RefCounted
## One capital's death as a plan (M10-T11, D12.8): its sections, its `BreakupPlan` (which section goes when, and what it blows
## with) and the `StagedWreck` that holds what has not gone yet on the ship's last motion. Built from the ship as it died;
## `CapitalWrecks` plays it (the blasts, the chunks, the fires). Everything is drawn from a seed of the ship's name, so the
## same death plays the same way with any thread count. Pure apart from reading the ship once.

var plan: BreakupPlan = null
var wreck: StagedWreck = null
## Per section (chunk index): its name, kind, its box in the chunk's frame, and its chunk's pose in the body frame.
var names := PackedStringArray()
var kinds := PackedStringArray()
var boxes: Array[AABB] = []
var poses: Array[Transform3D] = []
## Per section: its chunk entry (`hardpoints.json` `chunks[]`, empty when it has none), its collision shapes in its piece's
## frame and the move from that frame into the chunk's, its share of the ship's mass.
var chunk_entries: Array[Dictionary] = []
var shapes: Array = []
var to_chunk: Array[Transform3D] = []
var mass_kg := PackedFloat64Array()
## Per section: its chunk's mesh on its piece's maps (null: none), and the ship's skin variant they are drawn with.
var meshes: Array[Mesh] = []
var skin_variant: float = 0.0
## Who it was: catalogue type, class and side (the blasts' rows), name (readouts).
var type_id: StringName = &""
var capital_class: StringName = &""
var faction: StringName = &""
var label: String = ""
## Its class's `breakup` row.
var numbers: Dictionary = {}
## The first blast (the death's own): set off at once, it goes on the killing hit's event.
var first_spec: BlastSpec = null
var first_at: Vector3 = Vector3.ZERO
## Per section: the seconds of the wreck's age its next fire is due and its last one may start (INF: none).
var fire_next := PackedFloat64Array()
var fire_end := PackedFloat64Array()
## Blasts set off so far.
var blasts: int = 0

var _rng := RandomNumberGenerator.new()


## The plan for `ship` dying at `xform` (World-local) moving at `velocity` and turning at `spin` (world frame), its killing hit
## `info` (null for none); null when the ship has no sections.
static func from_ship(ship: CapitalShip, xform: Transform3D, velocity: Vector3, spin: Vector3, info: HitInfo) -> CapitalBreakup:
	if ship == null or ship.sections == null or not ship.sections.valid or ship.damage == null:
		return null
	var b := CapitalBreakup.new()
	b.type_id = ship.type_id
	b.capital_class = ship.capital_class
	b.faction = ship.faction
	b.label = ship.targetable.display_name if ship.targetable != null else String(ship.name)
	b.skin_variant = ship.skin_variant
	var cls: StringName = BlastTable.capital_class(ship.type_id, ship.capital_class, ship.faction)
	var classes: Dictionary = CapitalData.table("breakup").get("classes", {})
	b.numbers = classes.get(String(cls), classes.get(String(BlastTable.DEFAULT_CLASS), {}))
	var chunk_by_name: Dictionary = {}
	for raw: Variant in ship.hardpoints().get("chunks", []):
		if raw is Dictionary:
			chunk_by_name[str((raw as Dictionary).get("name", ""))] = raw
	var rotors: Dictionary = {}
	for rotor: CapitalRotor in ship.rotors:
		rotors[rotor.piece_name] = rotor
	var centres := PackedVector3Array()
	var spent := PackedByteArray()
	for entry: Dictionary in ship.sections.pieces:
		var section_name: String = str(entry["name"])
		var section: CapitalSection = ship.damage.sections.get(section_name)
		var chunk: Dictionary = chunk_by_name.get(section_name, {})
		var piece: String = str(entry.get("piece", CapitalSections.HULL))
		var box: AABB = section.box if section != null else AABB()
		var offset: Vector3 = _vec3(chunk.get("offset")) if not chunk.is_empty() else box.get_center()
		var turn := Transform3D.IDENTITY  # the piece's frame in the body's: a rotor at its pivot, turned as it stopped
		var rotor: CapitalRotor = rotors.get(piece)
		if rotor != null:
			turn = rotor.pose_for(Transform3D.IDENTITY, rotor.angle)
			offset -= rotor.pivot  # the chunk's place in the piece's frame
		var pose: Transform3D = turn * Transform3D(Basis.IDENTITY, offset)
		b.names.append(section_name)
		b.kinds.append(section.kind if section != null else "")
		var rest_offset: Vector3 = offset + (rotor.pivot if rotor != null else Vector3.ZERO)
		b.boxes.append(AABB(box.position - rest_offset, box.size))
		b.poses.append(pose)
		b.chunk_entries.append(chunk)
		b.meshes.append(ship.chunk_mesh(section_name) if not chunk.is_empty() else null)
		b.shapes.append(entry.get("shapes", []))
		b.to_chunk.append(Transform3D(Basis.IDENTITY, -offset))
		var share: float = float((ship.sections.by_name.get(section_name, {}) as Dictionary).get("hull_share", 0.0))
		b.mass_kg.append(ship.mass * share)
		centres.append(box.get_center())
		spent.append(1 if section != null and section.state == CapitalSection.State.DESTROYED else 0)
	if b.names.is_empty():
		return null
	var seed_value: int = hash([b.label, String(b.type_id)])
	b._rng.seed = seed_value
	var first: int = b._first(ship, info, xform)
	b.plan = BreakupPlan.for_sections(centres, b.kinds, first, spent, b.numbers, seed_value)
	var offsets: Array[Vector3] = []
	for pose: Transform3D in b.poses:
		offsets.append(pose.origin)
	b.wreck = StagedWreck.new(b.plan, offsets, offsets, xform, velocity, spin)
	b.wreck.set_local_poses(b.poses)
	b.fire_next.resize(b.names.size())
	b.fire_end.resize(b.names.size())
	b.fire_next.fill(INF)
	b.fire_end.fill(INF)
	return b


## The blast section `index` sets off as it leaves, or null for none.
func blast_of(index: int) -> BlastSpec:
	var kind: String = plan.blast_kind[index]
	return BlastTable.capital_section(type_id, capital_class, faction, kind) if kind != "" else null


## Where section `index`'s blast goes off now: its box's centre on its chunk's place in the wreck (World-local).
func blast_point(index: int) -> Vector3:
	return wreck.chunk_transform(index) * boxes[index].get_center()


## Section `index`'s fireball radius for a blast of `spec`: its part's size, at least a share of the blast's reach.
func fireball_radius(index: int, spec: BlastSpec) -> float:
	var by_box: float = 0.5 * boxes[index].size.length() * float(CapitalData.table("breakup").get("fireball_per_box", 0.6))
	var by_blast: float = (spec.radius_m if spec != null else 0.0) * float(CapitalData.table("breakup").get("fireball_share", 0.12))
	return maxf(by_box, by_blast)


## Section `index` is loose: its fires start now and burn for its plan's `fire_s`.
func light_fires(index: int) -> void:
	var burn: float = plan.fire_s[index]
	if burn <= 0.0 or float(numbers.get("fire_radius_m", 0.0)) <= 0.0:
		return
	fire_next[index] = wreck.age_s + _fire_gap()
	fire_end[index] = wreck.age_s + burn


## The fires due by now: the section indices, each with a point in its chunk's frame; the next ones are drawn from the seed.
func fires_due() -> Array:
	var out: Array = []
	for i: int in names.size():
		while fire_next[i] <= wreck.age_s and fire_next[i] <= fire_end[i]:
			var box: AABB = boxes[i]
			var local: Vector3 = box.position + box.size * Vector3(_rng.randf(), _rng.randf(), _rng.randf())
			out.append([i, local])
			fire_next[i] += _fire_gap()
		if fire_next[i] > fire_end[i]:
			fire_next[i] = INF
	return out


## Whether nothing is left to play: every section gone and every fire out.
func finished() -> bool:
	if not wreck.finished():
		return false
	for t: float in fire_next:
		if t < INF:
			return false
	return true


func _fire_gap() -> float:
	var every: Variant = numbers.get("fire_every_s", [0.5, 1.0])
	return _rng.randf_range(float(every[0]), float(every[1])) if every is Array and (every as Array).size() >= 2 else 0.75


# The section that goes first: the one that blew, else the one the killing hit landed on (or nearest its point), else (a death
# with no point: the console's, a Vorlon's refusal to hulk) its reactor, as M10-T09's death blast is; one drawn from the seed
# for a hull with no reactor.
func _first(ship: CapitalShip, info: HitInfo, xform: Transform3D) -> int:
	var blown: int = names.find(ship.damage.blown)
	if blown >= 0:
		return blown
	if info != null and info.cause != HitInfo.CAUSE_CONSOLE and info.cause != HitInfo.CAUSE_NO_HULK:
		if info.has_meta(CapitalShip.SECTION_META):
			var named: int = names.find(str(info.get_meta(CapitalShip.SECTION_META)))
			if named >= 0:
				return named
		if info.point.is_finite():
			var local: Vector3 = xform.affine_inverse() * info.point
			var best: int = -1
			var best_d: float = INF
			for i: int in names.size():
				var box := AABB(boxes[i].position + poses[i].origin, boxes[i].size)
				var d: float = _box_distance(box, local)
				if d < best_d:
					best_d = d
					best = i
			if best >= 0:
				return best
	var reactor: int = kinds.find(CapitalSection.REACTOR)
	return reactor if reactor >= 0 else _rng.randi_range(0, names.size() - 1)


static func _box_distance(box: AABB, p: Vector3) -> float:
	var q: Vector3 = p.clamp(box.position, box.end)
	return q.distance_to(p)


static func _vec3(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return value if value is Vector3 else Vector3.ZERO
