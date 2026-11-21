class_name CapitalMarksLayout
extends RefCounted
## Far capital ships' HUD markers (M8-T08), pure: a capital kilometres out is a few dark pixels, so the HUD shows a capital glyph
## with its class and range where it is, or an edge arrow when it is off screen, until its hull is big enough to read. One
## marker per capital, the nearest few only; none for the selected target or the waypoint, whose own marks already name them
## (M8-T33's one label per spot).


## Fills `f.capital_marks` from `input.capitals` by `input.capital_rules`: each `{on_screen, pos, angle, label, range_m, color}`.
static func compute(input: HudInput, f: HudFrame) -> void:
	var rules: CapitalMarkerRules = input.capital_rules
	if rules == null or input.capitals.is_empty() or rules.max_markers <= 0:
		return
	var marks: Array[Dictionary] = []
	for c: Dictionary in input.capitals:
		var id: int = int(c["id"])
		if id == input.selected_id and input.target != null:
			continue
		if input.has_waypoint and id == input.waypoint_id:
			continue
		var relation: Factions.Relation = Factions.relation(input.faction, c["faction"])
		if not rules.relations.has(relation):
			continue
		var at: Vector3 = c["position"]
		var range_m: float = input.own_position.distance_to(at)
		if range_m > rules.max_range_m:
			continue
		if radius_px(input, float(c["radius_m"]), input.camera_transform.origin.distance_to(at)) >= rules.hide_above_px:
			continue  # big enough to read: its hull speaks for itself, on screen or once the pilot turns to it
		var mark := {"label": String(c["label"]), "range_m": range_m, "color": Factions.contact_color(relation, false),
				"on_screen": false, "pos": Vector2.ZERO, "angle": 0.0}
		var shown: Dictionary = HudLayout.project(input, at)
		if bool(shown["in_front"]) and HudLayout.on_screen(input, shown["pos"]):
			mark["on_screen"] = true
			mark["pos"] = shown["pos"]
		elif rules.edge_arrows:
			var edge: Dictionary = HudLayout.edge_arrow(input, f, at)
			mark["pos"] = edge["pos"]
			mark["angle"] = edge["angle"]
		else:
			continue
		marks.append(mark)
	marks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["range_m"]) < float(b["range_m"]))
	f.capital_marks = marks.slice(0, rules.max_markers)


## How big a hull of `radius_m` is `distance_m` from the camera, px of a 1080 px window, wherever it is in the view.
static func radius_px(input: HudInput, radius_m: float, distance_m: float) -> float:
	return 540.0 * input.projection.y.y * radius_m / maxf(distance_m, 1.0)  # y.y: 1 / tan(half the field of view)
