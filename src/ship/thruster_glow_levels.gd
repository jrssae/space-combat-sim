class_name ThrusterGlowLevels
extends RefCounted
## What each thruster glow should show for a `FlightOutput` (architecture §7.1), kept apart from the scene nodes so
## the mapping is unit-tested: the node (`ThrusterVisuals`) only smooths these targets and applies them.
##
## Glow order is the layout's: first every pod nozzle in `ThrusterLayout` order (mains, then retros), then every
## cosmetic RCS nozzle. All levels are 0..1.
##
## - A pod nozzle shows its pod's `main_levels` / `retro_levels` entry. Those are post-trim, so trim and differential
##   thrust are visible.
## - An RCS nozzle shows the strongest of its pilot-term tags (decision D14: RCS is cosmetic, glow only). Each tag
##   reads one signed axis of the output, in the same body-frame signs the flight model uses:
##   `rcs_force_level` x = sway right, y = heave up; `rcs_torque_level` x = pitch up, y = yaw LEFT, z = roll LEFT
##   (a positive body rotation about +Y yaws the nose left, about +Z rolls left; see `FlightModel`).


## Targets for every glow of `layout`, in glow order. `output` may be null (nothing flying yet): all zeros.
static func targets(layout: ThrusterLayout, output: FlightOutput) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(layout.nozzle_count() + layout.rcs_nozzles.size())
	if output == null:
		return result
	for i: int in layout.nozzle_count():
		result[i] = pod_nozzle_level(layout, output, i)
	for j: int in layout.rcs_nozzles.size():
		var tags: PackedStringArray = layout.rcs_nozzles[j]["tags"]
		result[layout.nozzle_count() + j] = rcs_level(tags, output.rcs_force_level, output.rcs_torque_level)
	return result


## Level of pod nozzle `nozzle_index`: its pod's main or retro level after trim.
static func pod_nozzle_level(layout: ThrusterLayout, output: FlightOutput, nozzle_index: int) -> float:
	var levels: PackedFloat64Array = output.main_levels
	if not ThrusterLayout.is_main_group(layout.nozzle_groups[nozzle_index]):
		levels = output.retro_levels
	var pod: int = layout.nozzle_pods[nozzle_index]
	return clampf(levels[pod], 0.0, 1.0) if pod < levels.size() else 0.0


## Strongest level over the tags of one RCS nozzle (0 for no tags).
static func rcs_level(tags: PackedStringArray, force_level: Vector3, torque_level: Vector3) -> float:
	var level: float = 0.0
	for tag: String in tags:
		level = maxf(level, tag_level(tag, force_level, torque_level))
	return level


## Level 0..1 asked of one effect tag by the output's RCS levels; unknown tags read 0.
static func tag_level(tag: String, force_level: Vector3, torque_level: Vector3) -> float:
	var signed: float
	match tag:
		"sway_right":
			signed = force_level.x
		"sway_left":
			signed = -force_level.x
		"heave_up":
			signed = force_level.y
		"heave_down":
			signed = -force_level.y
		"pitch_up":
			signed = torque_level.x
		"pitch_down":
			signed = -torque_level.x
		"yaw_left":
			signed = torque_level.y
		"yaw_right":
			signed = -torque_level.y
		"roll_left":
			signed = torque_level.z
		"roll_right":
			signed = -torque_level.z
		_:
			return 0.0
	return clampf(signed, 0.0, 1.0)


## One step of first-order smoothing toward `target` with time constant `time_constant_s`; exact for any `dt`, so
## the glow looks the same at 60 and 144 frames per second. A time constant of 0 or less jumps straight to the target.
static func smooth(current: float, target: float, dt: float, time_constant_s: float) -> float:
	if time_constant_s <= 0.0:
		return target
	return current + (target - current) * (1.0 - exp(-maxf(dt, 0.0) / time_constant_s))
