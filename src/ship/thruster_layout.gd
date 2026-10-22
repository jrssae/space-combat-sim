class_name ThrusterLayout
extends RefCounted
## The pod nozzles of a ship as the flight model sees them (architecture §5.2), built from `hardpoints.json`.
## Pure: parses a Dictionary, text or a file and never touches the scene tree. Body frame, metres, relative to
## the body origin; `r_i = p_i - center_of_mass` is the lever arm for `r × F`.
##
## Each pod has one main nozzle (exhaust +Z, thrust forward) and one retro nozzle (exhaust -Z). The pilot drives
## the nozzles in four groups: RT = both right mains, LT = both left mains, RB = right retros, LB = left retros.
## Nozzle data lives in parallel packed arrays indexed by nozzle (mains first, then retros, in pod order).
##
## A malformed input is not fatal: `valid` is false and `error` says why; the caller decides whether to warn
## (no `push_error` here, so tests can exercise bad input quietly).

## Nozzle groups, one per trigger/bumper (§5.2).
enum Group { R_MAIN, L_MAIN, R_RETRO, L_RETRO }

const GROUP_COUNT: int = 4
const GROUP_NAMES: PackedStringArray = ["R_MAIN", "L_MAIN", "R_RETRO", "L_RETRO"]

## False when the input could not be read; `error` explains. An invalid layout has no nozzles.
var valid: bool = false
var error: String = ""
## Body-frame centre of mass the lever arms are taken about.
var center_of_mass: Vector3 = Vector3.ZERO
## Pod names in file order (`ur`, `lr`, `ul`, `ll` for the Starfury).
var pod_names: PackedStringArray = []
## True for pods on the right side (x > 0), per pod.
var pod_is_right: PackedByteArray = []
## Per nozzle: `<pod>_main` or `<pod>_retro`.
var nozzle_names: PackedStringArray = []
## Per nozzle: index into `pod_names`.
var nozzle_pods: PackedInt32Array = []
## Per nozzle: its `Group`.
var nozzle_groups: PackedInt32Array = []
## Per nozzle: position relative to the body origin (where the Ship applies the force).
var nozzle_positions: PackedVector3Array = []
## Per nozzle: unit exhaust direction; thrust acts along `-exhaust`.
var nozzle_exhausts: PackedVector3Array = []
## Per nozzle: lever arm `r_i = p_i - center_of_mass`.
var nozzle_arms: PackedVector3Array = []
## Cosmetic RCS nozzles for effects (decision D14): `name`, `pod`, `position`, `exhaust`, `tags` (PackedStringArray).
var rcs_nozzles: Array[Dictionary] = []

# Per group, sums over its nozzles of the unit thrust direction and of `r × (-exhaust)`: the force and torque
# per newton of nozzle thrust, so the model can scale them by level × thrust instead of looping every tick.
var _group_thrust_axes: PackedVector3Array = []
var _group_torque_axes: PackedVector3Array = []


## Reads `hardpoints.json` from disk; the centre of mass comes from the file.
static func load_file(path: String) -> ThrusterLayout:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var missing := ThrusterLayout.new()
		missing.error = "cannot open %s (error %d); run scripts/gen_assets.sh" % [path, FileAccess.get_open_error()]
		return missing
	return from_json_text(file.get_as_text())


## Parses hardpoints JSON text; the centre of mass comes from the document's `center_of_mass`.
static func from_json_text(text: String) -> ThrusterLayout:
	var json := JSON.new()
	if json.parse(text) != OK:
		var broken := ThrusterLayout.new()
		broken.error = "hardpoints are not valid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()]
		return broken
	var data: Variant = json.data
	if not (data is Dictionary):
		var not_object := ThrusterLayout.new()
		not_object.error = "hardpoints root is not an object"
		return not_object
	var hardpoints: Dictionary = data
	var com: Variant = hardpoints.get("center_of_mass")
	if not _is_vec3(com):
		var no_com := ThrusterLayout.new()
		no_com.error = "hardpoints have no center_of_mass [x, y, z]"
		return no_com
	return from_dict(hardpoints, _to_vec3(com))


## Builds the layout from a parsed hardpoints Dictionary (T04 schema: `pods[]` with `name`, `side`, `main` and
## `retro` nozzles; optional cosmetic `rcs[]`) about the given centre of mass.
static func from_dict(hardpoints: Dictionary, p_center_of_mass: Vector3) -> ThrusterLayout:
	var layout := ThrusterLayout.new()
	layout.center_of_mass = p_center_of_mass
	var pods: Variant = hardpoints.get("pods")
	if not (pods is Array) or (pods as Array).is_empty():
		layout.error = "hardpoints have no pods[]"
		return layout
	var mains: Array[Dictionary] = []
	var retros: Array[Dictionary] = []
	for pod_value: Variant in pods as Array:
		if not (pod_value is Dictionary):
			layout.error = "pods[] holds a non-object"
			return layout
		var pod: Dictionary = pod_value
		var name: Variant = pod.get("name")
		var side: Variant = pod.get("side")
		if not (name is String) or (name as String).is_empty():
			layout.error = "pod %d has no name" % layout.pod_names.size()
			return layout
		if side != "left" and side != "right":
			layout.error = "pod %s has side %s, expected left or right" % [name, str(side)]
			return layout
		var pod_index: int = layout.pod_names.size()
		var is_right: bool = side == "right"
		var pod_name: String = name
		layout.pod_names.append(pod_name)
		layout.pod_is_right.append(1 if is_right else 0)
		var main: Dictionary = _nozzle_record(pod, "main", pod_index, Group.R_MAIN if is_right else Group.L_MAIN, layout)
		if main.is_empty():
			return layout
		var retro: Dictionary = _nozzle_record(pod, "retro", pod_index, Group.R_RETRO if is_right else Group.L_RETRO, layout)
		if retro.is_empty():
			return layout
		mains.append(main)
		retros.append(retro)
	var right_count: int = 0
	for flag: int in layout.pod_is_right:
		right_count += flag
	if right_count == 0 or right_count == layout.pod_names.size():
		layout.error = "pods must cover both sides (%d of %d are right)" % [right_count, layout.pod_names.size()]
		return layout
	# Mains first, then retros, so nozzle index order is stable regardless of pod count.
	for record: Dictionary in mains:
		layout._append_nozzle(record)
	for record: Dictionary in retros:
		layout._append_nozzle(record)
	layout._build_group_axes()
	layout._read_rcs(hardpoints.get("rcs"))
	layout.valid = true
	return layout


## Number of pod nozzles (2 per pod).
func nozzle_count() -> int:
	return nozzle_positions.size()


## Number of pods.
func pod_count() -> int:
	return pod_names.size()


## Sum over the group's nozzles of the unit thrust direction (`-exhaust`): body-frame force per newton of
## per-nozzle thrust, i.e. `F_g = level × thrust × thrust_axis(g)`.
func thrust_axis(group: int) -> Vector3:
	return _group_thrust_axes[group]


## Sum over the group's nozzles of `r_i × (-exhaust_i)`: body-frame torque about the centre of mass per newton of
## per-nozzle thrust, i.e. `tau_g = level × thrust × torque_axis(g)`.
func torque_axis(group: int) -> Vector3:
	return _group_torque_axes[group]


## Indices of the nozzles in a group.
func nozzles_in_group(group: int) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for i: int in nozzle_groups.size():
		if nozzle_groups[i] == group:
			found.append(i)
	return found


static func is_main_group(group: int) -> bool:
	return group == Group.R_MAIN or group == Group.L_MAIN


static func is_right_group(group: int) -> bool:
	return group == Group.R_MAIN or group == Group.R_RETRO


static func group_name(group: int) -> String:
	return GROUP_NAMES[group]


func _append_nozzle(record: Dictionary) -> void:
	nozzle_names.append(record["name"])
	nozzle_pods.append(record["pod"])
	nozzle_groups.append(record["group"])
	var position: Vector3 = record["position"]
	nozzle_positions.append(position)
	nozzle_exhausts.append(record["exhaust"])
	nozzle_arms.append(position - center_of_mass)


func _build_group_axes() -> void:
	_group_thrust_axes.resize(GROUP_COUNT)
	_group_torque_axes.resize(GROUP_COUNT)
	_group_thrust_axes.fill(Vector3.ZERO)
	_group_torque_axes.fill(Vector3.ZERO)
	for i: int in nozzle_count():
		var group: int = nozzle_groups[i]
		var direction: Vector3 = -nozzle_exhausts[i]
		_group_thrust_axes[group] += direction
		_group_torque_axes[group] += nozzle_arms[i].cross(direction)


func _read_rcs(rcs: Variant) -> void:
	if not (rcs is Array):
		return
	for value: Variant in rcs as Array:
		if not (value is Dictionary):
			continue
		var entry: Dictionary = value
		if not _is_vec3(entry.get("position")) or not _is_vec3(entry.get("exhaust")):
			continue
		var tags: PackedStringArray = []
		var raw_tags: Variant = entry.get("tags")
		if raw_tags is Array:
			for tag: Variant in raw_tags as Array:
				if tag is String:
					tags.append(tag)
		rcs_nozzles.append({
			"name": str(entry.get("name", "")),
			"pod": str(entry.get("pod", "")),
			"position": _to_vec3(entry.get("position")),
			"exhaust": _to_vec3(entry.get("exhaust")).normalized(),
			"tags": tags,
		})


# Validates one nozzle of a pod and returns its record; empty (with `layout.error` set) when malformed.
static func _nozzle_record(pod: Dictionary, key: String, pod_index: int, group: int, layout: ThrusterLayout) -> Dictionary:
	var pod_name: String = pod["name"]
	var nozzle: Variant = pod.get(key)
	if not (nozzle is Dictionary):
		layout.error = "pod %s has no %s nozzle" % [pod_name, key]
		return {}
	var position: Variant = (nozzle as Dictionary).get("position")
	var exhaust: Variant = (nozzle as Dictionary).get("exhaust")
	if not _is_vec3(position) or not _is_vec3(exhaust):
		layout.error = "pod %s %s nozzle needs position [x, y, z] and exhaust [x, y, z]" % [pod_name, key]
		return {}
	var exhaust_vec: Vector3 = _to_vec3(exhaust)
	if exhaust_vec.is_zero_approx():
		layout.error = "pod %s %s nozzle has a zero exhaust direction" % [pod_name, key]
		return {}
	return {
		"name": "%s_%s" % [pod_name, key],
		"pod": pod_index,
		"group": group,
		"position": _to_vec3(position),
		"exhaust": exhaust_vec.normalized(),
	}


static func _is_vec3(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 3:
		return false
	for part: Variant in value as Array:
		if not (part is float or part is int):
			return false
	return true


static func _to_vec3(value: Variant) -> Vector3:
	var parts: Array = value
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
