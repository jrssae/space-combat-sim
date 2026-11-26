class_name CapitalBrainSpec
extends RefCounted
## A capital ship as its native helm and brain take it (M10-T16, D12.10): the numbers `ScsSimCore.capital_add` reads, built
## from the ship's flight spec, its mounts (guns, launchers, interceptors, beams) and its subsystems (engines, bays, reactor,
## bridge), with the class's worth and the faction's doctrine from `capitals.json` (`capital_brain`). Pure.

## Mount shapes and roles as the brain numbers them (`capital_brain.rs`).
const MOUNT_TURRET: int = 0
const MOUNT_FIXED: int = 1
const MOUNT_LAUNCHER: int = 2
const MOUNT_BEAM: int = 3
const MOUNT_PD: int = 4
const ROLE_AC: int = 2
const ROLE_PD: int = 3
const POINT_ENGINE: int = 0
const POINT_BAY: int = 1
const POINT_REACTOR: int = 2
const POINT_BRIDGE: int = 3
const POINT_MAGAZINE: int = 4
const POINT_SECTION: int = 5
## A nozzle or a bay's mouth as a part to aim at: this far round its place when its hardpoint names no size, m.
const PART_HALF_M: float = 10.0
## `capital_set_tuning`'s keys, in order, with their defaults.
const TUNING_KEYS: Array[String] = ["think_hz", "engage_share", "approach_mps", "arrive_s", "sensor_m", "screen_min_m",
		"screen_max_m", "withdraw_hull", "withdraw_reactor", "outgunned_ratio", "keep_bonus", "attitude_margin"]
const TUNING_DEFAULTS: Array[float] = [5.0, 0.7, 40.0, 30.0, 30000.0, 800.0, 1200.0, 0.3, 0.5, 1.5, 1.25, 1.1]


## The helm's numbers for a hull flying `flight_spec` with `layout`'s nozzles: gravitic, retros, a_main, a_retro, a_rcs x and
## y, rate max (3), alpha max (3).
static func helm_numbers(flight_spec: ShipSpec, layout: ThrusterLayout) -> PackedFloat64Array:
	var cap: ShipCapability = ShipCapability.from_spec(flight_spec, layout)
	return PackedFloat64Array([1.0 if CapitalPropulsion.is_gravitic(flight_spec) else 0.0,
			1.0 if CapitalPropulsion.has_retros(flight_spec) else 0.0, cap.a_main, cap.a_retro, cap.a_rcs.x, cap.a_rcs.y,
			cap.rate_max_rad.x, cap.rate_max_rad.y, cap.rate_max_rad.z, cap.alpha_max_rad.x, cap.alpha_max_rad.y,
			cap.alpha_max_rad.z])


## The brain's numbers for `ship`: hull points, its class's worth, its faction's doctrine (threat and value weights, cripple)
## and whether it carries fighters.
static func brain_numbers(ship: CapitalShip) -> PackedFloat64Array:
	var data: Dictionary = CapitalData.table("capital_brain")
	var values: Dictionary = data.get("class_value", {}) if data.get("class_value") is Dictionary else {}
	var value: float = float(values.get(String(ship.capital_class), values.get("capital", 2.0)))
	var d: Dictionary = doctrine(ship.faction)
	var carrier: bool = not (ship.hardpoints().get("bays", []) as Array).is_empty()
	return PackedFloat64Array([ship.spec.hull_max, value, float(d["threat_w"]), float(d["value_w"]),
			1.0 if bool(d["cripple"]) else 0.0, 1.0 if carrier else 0.0])


## `faction`'s doctrine: `{threat_w, value_w, cripple}`, the file's `default` for a faction it does not list.
static func doctrine(faction: StringName) -> Dictionary:
	var table: Variant = CapitalData.table("capital_brain").get("doctrine")
	var all: Dictionary = table if table is Dictionary else {}
	var found: Variant = all.get(String(faction), all.get("default"))
	var d: Dictionary = found if found is Dictionary else {}
	return {"threat_w": float(d.get("threat_w", 1.0)), "value_w": float(d.get("value_w", 1.0)), "cripple": bool(d.get("cripple", false))}


## The fighters' runs' keys (`fighter_runs`), in the order `capital_set_tuning` takes them after `TUNING_KEYS`.
const RUN_KEYS: Array[String] = ["fire_from_m", "fire_to_m", "open_m", "replan_s", "regroup_m"]
const RUN_DEFAULTS: Array[float] = [1500.0, 400.0, 3000.0, 2.0, 5000.0]


## The shared numbers (`capital_set_tuning`), the file's where it has them: the brain's, then the fighters' runs'.
static func tuning() -> PackedFloat64Array:
	var data: Dictionary = CapitalData.table("capital_brain")
	var out := PackedFloat64Array()
	for i: int in TUNING_KEYS.size():
		out.append(float(data.get(TUNING_KEYS[i], TUNING_DEFAULTS[i])))
	var runs: Dictionary = data.get("fighter_runs", {}) if data.get("fighter_runs") is Dictionary else {}
	for i: int in RUN_KEYS.size():
		out.append(float(runs.get(RUN_KEYS[i], RUN_DEFAULTS[i])))
	return out


## `ship`'s mounts as the brain weighs them, in a fixed order: `{names, packed}` with `ScsSimCore.MOUNT_LEN` numbers each
## (place, axis, cone half angle in degrees, dps, range, shape, role, works).
static func mounts(ship: CapitalShip) -> Dictionary:
	var names := PackedStringArray()
	var packed := PackedFloat64Array()
	var hardpoints: Dictionary = ship.hardpoints()
	for m: Dictionary in CapitalGunMounts.of_hardpoints(hardpoints, ship.type_id):
		var p: PackedFloat64Array = m["packed"]
		var kind: int = MOUNT_LAUNCHER if p[0] > 0.5 else (MOUNT_FIXED if bool(m["on_axis"]) else MOUNT_TURRET)
		var dps: float = p[2] * p[3] * p[4] / maxf(p[6], 0.01)
		_add(names, packed, m["name"], m["position"], m["axis"], m["half_deg"], dps, p[8], kind, int(p[1]), ship)
	for m: Dictionary in CapitalGunMounts.interceptors_of(hardpoints, ship.type_id):
		_add(names, packed, m["name"], m["position"], m["axis"], m["half_deg"], 0.0, 0.0, MOUNT_PD, ROLE_PD, ship)
	for m: Dictionary in BeamMounts.of_hardpoints(hardpoints, ship.type_id):
		var b: PackedFloat64Array = m["packed"]
		var cycle: float = maxf(b[4], 0.01)
		var dps: float = b[1] / cycle if int(b[0]) == WeaponSpec.BEAM_PULSED else b[2] * b[3] / cycle
		_add(names, packed, m["name"], m["position"], m["forward"], m["arc_half_deg"], dps, b[6], MOUNT_BEAM, ROLE_AC, ship)
	return {"names": names, "packed": packed}


## `ship`'s parts as attackers and its brain aim at them: `{keys, packed}` with `ScsSimCore.POINT_LEN` numbers each (place,
## kind, works, half extents): the engines, the bays and every section of the hull (the reactor, bridge and magazine as vital
## ones); a key is `engine:<name>`, `bay:<name>`, `section:<name>`.
static func points(ship: CapitalShip) -> Dictionary:
	var keys := PackedStringArray()
	var packed := PackedFloat64Array()
	var hardpoints: Dictionary = ship.hardpoints()
	for raw: Variant in hardpoints.get("engines", []):
		var e: Dictionary = raw
		var r: float = float(e.get("radius_m", PART_HALF_M))
		_point(keys, packed, "engine:%s" % e.get("name", ""), _vec3(e.get("position")), POINT_ENGINE,
				ship.damage.engine_works(str(e.get("name", ""))), Vector3(r, r, r))
	for raw: Variant in hardpoints.get("bays", []):
		var b: Dictionary = raw
		var mouth: Array = b.get("mouth_m", [2.0 * PART_HALF_M, 2.0 * PART_HALF_M])
		_point(keys, packed, "bay:%s" % b.get("name", ""), _vec3(b.get("exit", b.get("position"))), POINT_BAY,
				ship.damage.bay_works(str(b.get("name", ""))), Vector3(0.5 * float(mouth[0]), 0.5 * float(mouth[1]), PART_HALF_M))
	for name: String in ship.damage.sections:
		var s: CapitalSection = ship.damage.sections[name]
		var kind: int = {CapitalSection.REACTOR: POINT_REACTOR, CapitalSection.BRIDGE: POINT_BRIDGE,
				CapitalSection.MAGAZINE: POINT_MAGAZINE}.get(s.kind, POINT_SECTION)
		_point(keys, packed, "section:%s" % name, s.box.get_center(), kind, not s.lost(), 0.5 * s.box.size)
	return {"keys": keys, "packed": packed}


## Which of `mount_names` and `point_keys` still work on `ship`, a byte each (`capital_set_works`).
static func works(ship: CapitalShip, mount_names: PackedStringArray, point_keys: PackedStringArray) -> Array[PackedByteArray]:
	var m := PackedByteArray()
	for name: String in mount_names:
		m.append(1 if ship.mount_works(name) else 0)
	var p := PackedByteArray()
	for key: String in point_keys:
		var parts: PackedStringArray = key.split(":", true, 1)
		var ok: bool = false
		match parts[0]:
			"engine":
				ok = ship.damage.engine_works(parts[1])
			"bay":
				ok = ship.damage.bay_works(parts[1])
			_:
				var s: CapitalSection = ship.damage.sections.get(parts[1])
				ok = s != null and not s.lost()
		p.append(1 if ok else 0)
	return [m, p]


## The reactor's share (the weakest reactor section's points left; 1 with none) and the main engines live and in all.
static func status(ship: CapitalShip) -> Array:
	var reactor: float = 1.0
	for name: String in ship.damage.sections:
		var s: CapitalSection = ship.damage.sections[name]
		if s.kind == CapitalSection.REACTOR:
			reactor = minf(reactor, 0.0 if s.lost() else s.fraction())
	var total: int = (ship.hardpoints().get("engines", []) as Array).size()
	return [reactor, ship.damage.live_engines().size(), total]


static func _add(names: PackedStringArray, packed: PackedFloat64Array, name: String, at: Vector3, axis: Vector3, half_deg: float,
		dps: float, range_m: float, kind: int, role: int, ship: CapitalShip) -> void:
	names.append(name)
	packed.append_array([at.x, at.y, at.z, axis.x, axis.y, axis.z, half_deg, dps, range_m, kind, role,
			1.0 if ship.mount_works(name) else 0.0])


static func _point(keys: PackedStringArray, packed: PackedFloat64Array, key: String, at: Vector3, kind: int, ok: bool,
		half: Vector3) -> void:
	keys.append(key)
	packed.append_array([at.x, at.y, at.z, kind, 1.0 if ok else 0.0, half.x, half.y, half.z])


static func _vec3(raw: Variant) -> Vector3:
	if raw is Array and (raw as Array).size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO
