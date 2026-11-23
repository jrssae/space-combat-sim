class_name BayDoors
extends RefCounted
## A launch bay's roll-up door (M10-T22, Q58): the pure rules. The generator leaves each door in `hardpoints.json` (`doors`): the
## shut shutter's centre, the way it faces out (`forward`) and rolls (`up`), its size and how many slats it has; its roll housing
## over the mouth is part of the hull. A door is shut whenever its bay is idle; the launch and docking code (T17) opens it first
## and shuts it after. Opening winds the shutter up, slat by slat, into the housing.

## Seconds a door takes to roll from shut to open or back.
const ROLL_SECONDS: float = 2.4
## The dark groove between two slats, as a share of a slat's pitch.
const GAP_SHARE: float = 0.1


## The doors in a hardpoints dictionary (empty when the hull has none).
static func doors_of(hardpoints: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hardpoints.get("doors") is Array:
		for d: Variant in hardpoints["doors"]:
			if d is Dictionary:
				out.append(d)
	return out


## The bay a door belongs to: "bay_fury_1_r_door" gives "bay_fury_1_r".
static func bay_of(door_name: String) -> String:
	return door_name.trim_suffix("_door")


## The shutter's frame in the hull: X across the mouth, Y the way it rolls up, Z out of the bay.
static func frame(door: Dictionary) -> Transform3D:
	return Transform3D(HullMarks.quad_basis(_vec(door.get("forward")), _vec(door.get("up"))), _vec(door.get("position")))


## The slats still out of the housing with the door `amount` open (0 shut, 1 open), bottom first: each its centre's height in
## the shutter's frame and its own height (the top one cut where it enters the housing).
static func slats(door: Dictionary, amount: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var size: Vector3 = _vec(door.get("size_m"))
	var count: int = maxi(int(door.get("slats", 1)), 1)
	var pitch: float = size.y / float(count)
	var top: float = 0.5 * size.y
	var lift: float = clampf(amount, 0.0, 1.0) * size.y
	for i: int in count:
		var lo: float = -top + float(i) * pitch + lift
		var hi: float = minf(lo + pitch * (1.0 - GAP_SHARE), top)
		if hi - lo <= 1e-3:
			break
		out.append(Vector2(0.5 * (lo + hi), hi - lo))
	return out


## The dark plate behind the slats still out of the housing, so no bay light shows through their grooves: its centre's height
## in the shutter's frame and its own height (none when open).
static func backing(door: Dictionary, amount: float) -> Vector2:
	var tall: float = _vec(door.get("size_m")).y
	var lift: float = clampf(amount, 0.0, 1.0) * tall
	return Vector2(0.5 * lift, tall - lift)


## `amount` moved toward `target` by `delta` seconds of rolling.
static func advance(amount: float, target: float, delta: float) -> float:
	return move_toward(amount, target, delta / ROLL_SECONDS)


static func _vec(v: Variant) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() == 3 else Vector3.ZERO
