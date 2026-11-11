class_name StarSystemHost
extends Node
## Holds the flight scene's `StarSystem` and shows it on the console (M6-T03): the `system` provider. A thin adapter; the
## rules and the maths live in `StarSystem` and the native ephemeris.

## The planet the station orbits, whose centre the provider measures from.
const CENTRE: StringName = &"epsilon_iii"

var system: StarSystem


func setup(system_id: StringName) -> void:
	system = StarSystem.load_system(system_id)
	if not system.is_valid():
		push_warning("StarSystemHost: %s: %s" % [system_id, "; ".join(system.errors)])


func _ready() -> void:
	DebugConsole.registry.register_provider(&"system", ConsoleVars.new({
		&"id": {"get": func() -> String: return String(system.id), "doc": "The star system loaded"},
		&"valid": {"get": func() -> bool: return system.is_valid(), "doc": "Whether the system loaded; if not, `errors` says why"},
		&"errors": {"get": func() -> String: return "; ".join(system.errors), "doc": "Why the system was rejected, or empty"},
		&"a_min": {"get": func() -> float: return system.a_min, "unit": "m/s^2", "doc": "The weakest pull that still counts"},
		&"bodies": {"get": _bodies_text, "doc": "Each body: kind, GM, radius, atmosphere top and the zone its pull reaches"},
		&"places": {"get": _places_text, "doc": "Each place: its position from Epsilon III's centre now, in km"},
		&"gate_distance_km": {"get": func() -> float: return system.distance_m(&"jumpgate", &"babylon5", SimClock.now()) / 1000.0,
				"unit": "km", "doc": "How far the jumpgate is from the station now"},
		&"station_period_h": {"get": func() -> float: return system.period_s(&"babylon5") / 3600.0, "unit": "h",
				"doc": "The station's orbit period around Epsilon III"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _bodies_text() -> String:
	var lines := PackedStringArray()
	for key: StringName in system.body_ids:
		var row: Dictionary = system.info(key)
		lines.append("%s (%s) gm %.3e radius %.0f km atmosphere %.0f km zone %.0f km" % [key, row["kind"], row["gm"],
				float(row["radius_m"]) / 1000.0, float(row["atmosphere_top_m"]) / 1000.0, system.zone_radius_m(key) / 1000.0])
	return "; ".join(lines)


func _places_text() -> String:
	var lines := PackedStringArray()
	for key: StringName in system.place_ids:
		var rel: PackedFloat64Array = system.relative_state(key, CENTRE, SimClock.now())
		if rel.size() >= 3:
			lines.append("%s %.1f %.1f %.1f" % [key, rel[0] / 1000.0, rel[1] / 1000.0, rel[2] / 1000.0])
	return "; ".join(lines)
