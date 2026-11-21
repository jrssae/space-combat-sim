class_name CinematicKeyLight
extends RefCounted
## A soft key light from the sun's side and an optional rim from behind on a cinematic shot's subject ship (M8-T29, maintainer
## 2026-11-19: the show always key-lit its ships, even in deep space), so a fighter reads in open space. Shared by every shot
## sequencer (the gate jump, the launches): `attach(ship, to_sun)` when its shots start, `update(to_sun)` each frame while they
## play, `detach()` when they end. The strength is data (`data/camera/key_light.json`). Scene glue: two lights parented to the ship.

const PATH: String = "res://data/camera/key_light.json"

var _key: OmniLight3D = null
var _rim: OmniLight3D = null
var _ship: Node3D = null
var _settings: Dictionary = {}


func _init(settings: Dictionary = {}) -> void:
	_settings = settings if not settings.is_empty() else load_settings()


## The data file's settings (empty sections fall back to the built-in light).
static func load_settings(path: String = PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Lights `ship`, the key from `to_sun` (World, toward the star; zero: from above and in front of the ship).
func attach(ship: Node3D, to_sun: Vector3 = Vector3.ZERO) -> void:
	if ship == _ship and is_attached():
		update(to_sun)
		return
	detach()
	if ship == null or not is_instance_valid(ship):
		return
	_ship = ship
	_key = _make("CinematicKey", _section("key"))
	var rim: Dictionary = _section("rim")
	if bool(rim.get("enabled", true)):
		_rim = _make("CinematicRim", rim)
	update(to_sun)


## Keeps the lights on the sun's side as the ship turns and moves; call it each frame while the shots play.
func update(to_sun: Vector3 = Vector3.ZERO) -> void:
	if not is_attached():
		return
	var sun: Vector3 = to_sun.normalized() if not to_sun.is_zero_approx() else (_ship.global_basis * Vector3(0.4, 0.7, -0.6)).normalized()
	var at: Vector3 = _ship.global_position
	_key.global_position = at + sun * float(_section("key").get("distance_m", 45.0))
	if _rim != null:
		var rim: Dictionary = _section("rim")
		_rim.global_position = at - sun * float(rim.get("distance_m", 40.0)) + _ship.global_basis.y * float(rim.get("lift_m", 12.0))


## Takes the lights away (the shots ended, or the ship is gone).
func detach() -> void:
	for light: OmniLight3D in [_key, _rim]:
		if light != null and is_instance_valid(light):
			light.queue_free()
	_key = null
	_rim = null
	_ship = null


## Whether a ship is lit now.
func is_attached() -> bool:
	return _ship != null and is_instance_valid(_ship) and _key != null and is_instance_valid(_key)


## The ship lit now, or null.
func subject() -> Node3D:
	return _ship if is_attached() else null


func _section(name: String) -> Dictionary:
	var raw: Variant = _settings.get(name)
	return raw if raw is Dictionary else {}


func _make(node_name: String, data: Dictionary) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.light_energy = float(data.get("energy", 1.5))
	light.omni_range = float(data.get("range_m", 120.0))
	var colour: Variant = data.get("colour")
	if colour is Array and (colour as Array).size() >= 3:
		light.light_color = Color(float(colour[0]), float(colour[1]), float(colour[2]))
	light.shadow_enabled = false
	_ship.add_child(light)
	return light
