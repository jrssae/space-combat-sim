class_name OverlayText
extends RefCounted
## Pure formatter for the debug overlay (architecture §3, M1-T15). Main gathers a snapshot Dictionary each
## frame; this turns it into monospace lines, so every readout rule is unit-tested without a scene.
## Missing keys are simply skipped, so the overlay degrades gracefully while parts of the game are absent.


static func format(s: Dictionary) -> String:
	var lines: PackedStringArray = []
	if s.has("speed_mps"):
		lines.append("SPD   %8.1f m/s" % float(s["speed_mps"]))
	if s.has("body_velocity"):
		var v: Vector3 = s["body_velocity"]
		lines.append("VEL   %+8.1f %+8.1f %+8.1f  (body x/y/z)" % [v.x, v.y, v.z])
	if s.has("angular_rate_dps"):
		var w: Vector3 = s["angular_rate_dps"]
		lines.append("ROT   %+7.1f %+7.1f %+7.1f °/s (pitch/yaw/roll)" % [w.x, w.y, w.z])
	if s.has("assist_on"):
		var assist_on: bool = s["assist_on"]
		var parts: PackedStringArray = ["ASSIST ON" if assist_on else "ASSIST OFF"]
		if assist_on and s.has("pod_yaw_dps"):
			parts.append("POD YAW %+5.1f °/s" % float(s["pod_yaw_dps"]))
		if s.has("pod_trim"):
			parts.append("POD TRIM %3d %%" % roundi(float(s["pod_trim"]) * 100.0))
		lines.append("   ".join(parts))
	var modes: PackedStringArray = []
	if s.has("camera_mode"):
		modes.append("CAM " + String(s["camera_mode"]).to_upper())
	if s.has("weapon_mode"):
		modes.append("GUNS " + String(s["weapon_mode"]).to_upper())
	if s.has("timescale") and not is_equal_approx(float(s["timescale"]), 1.0):
		modes.append("TIMESCALE %.2f" % float(s["timescale"]))
	if not modes.is_empty():
		lines.append("   ".join(modes))
	if s.has("target_name"):
		lines.append(target_line(String(s["target_name"]), float(s.get("target_range_m", 0.0)),
				float(s.get("target_closing_mps", 0.0)), bool(s.get("target_behind", false))))
	if s.has("universe_position"):
		var u: PackedFloat64Array = s["universe_position"]
		lines.append("POS   %.3f %.3f %.3f m  [%s]" % [u[0], u[1], u[2], String(s.get("system_id", "local"))])
	var render: PackedStringArray = []
	if s.has("splat_backend"):
		render.append("SPLATS " + String(s["splat_backend"]).to_upper())
	if s.has("fps"):
		render.append("FPS %d" % int(s["fps"]))
	if not render.is_empty():
		lines.append("   ".join(render))
	if s.has("gpu"):
		lines.append("GPU   " + String(s["gpu"]))
	for pad: Dictionary in s.get("pads", []):
		lines.append(pad_line(pad))
	return "\n".join(lines)


## `TGT NAV BRAVO  1243 m  +12.4 m/s` (positive closing = getting nearer).
static func target_line(name: String, range_m: float, closing_mps: float, behind: bool) -> String:
	if name.is_empty():
		return "TGT   none"
	var text := "TGT   %s  %d m  %+.1f m/s" % [name, roundi(range_m), closing_mps]
	if behind:
		text += "  BEHIND"
	return text


static func pad_line(pad: Dictionary) -> String:
	var axes: PackedStringArray = []
	for a: float in pad.get("axes", []):
		axes.append("%+.2f" % a)
	return "PAD   %s  %s  rest %d  axes %s" % [String(pad.get("name", "?")), String(pad.get("guid", "")),
			int(pad.get("trigger_rest", 0.0)), " ".join(axes)]
