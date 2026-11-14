class_name StationGrid
extends Node
## The station's defence grid (M7-T07, D75, AC6): D75's 23 mounts from the station's hardpoints (M7-T05) bound to the native
## turret rows as the grid's kinds: 12 light pulse turrets (anti-fighter), 2 heavy cannons (capitals first) and 9 interceptor
## batteries. Everything a mount decides runs in the core (`grid_kernels`): the guns' pick in the AI job one tick behind, the
## aim, gate and shot, and the interceptors' choice, on the main thread. This node builds the mounts, says what they did and
## holds the console.
##
## - **The station never fires first** (maintainer): the guns hold fire until a hostile fires on the station or on a friendly
##   near it; from then on the grid is weapons free against that side for the rest of the fight (the core's latch).
## - **Interceptors are always on**: they stop hostile missiles and pulse bolts whose path meets the hull, never beams, one per
##   battery per interval.
## - **The drum's mounts turn with the drum**: they bind to the drum's body and hang from its visual pivot; the frame's stay
##   fixed. The station's own frame and drum block every gun's line of fire.
## - **Mounts can be knocked out** (maintainer, after T07): each has its own health (`GridMountHealth`); a hit on the station near
##   it wears it down as well as its section, and at zero it stops (dark, silent) until `repair` (a mission, or `grid repair`).
## - **Sub-points**: `sub_points` (and the core's `grid_points`) give each mount's place and whether it works, for attackers (T10).
## - The models are the Saturns' turret (T27) scaled per kind; sounds are the turret shot pitched per kind.
##
## Console: provider and command `grid`.

enum Kind { LIGHT = 1, HEAVY = 2, INTERCEPTOR = 3 }

## The hardpoints' kind names (`StationHardpoints.grid_mounts[].kind`).
const KIND_OF: Dictionary[String, Kind] = {"light_pulse": Kind.LIGHT, "heavy_cannon": Kind.HEAVY, "interceptor": Kind.INTERCEPTOR}
const KIND_NAMES: Dictionary[Kind, String] = {Kind.LIGHT: "light pulse", Kind.HEAVY: "heavy cannon",
		Kind.INTERCEPTOR: "interceptor"}
const WEAPONS: Dictionary[Kind, String] = {
	Kind.LIGHT: "res://assets/weapons/grid_light_pulse.tres",
	Kind.HEAVY: "res://assets/weapons/grid_heavy_cannon.tres",
	Kind.INTERCEPTOR: "res://assets/weapons/grid_interceptor.tres",
}
## The model every mount wears (the Saturns' turret, M5-T27), scaled per kind; its barrel is 4.5 m long at scale 1.
const MODEL_ASSET: String = "saturn_4_transport"
const MODEL_BARREL_M: float = 4.5
const MODEL_SCALE: Dictionary[Kind, float] = {Kind.LIGHT: 2.0, Kind.HEAVY: 4.0, Kind.INTERCEPTOR: 1.2}
## Each mount's cone round its base's up, degrees (a hemisphere and a little below it).
const ARC_DEG: float = 200.0
## How the turret shot sounds per kind: pitch and level (dB).
const SOUND_PITCH: Dictionary[Kind, float] = {Kind.LIGHT: 1.0, Kind.HEAVY: 0.55, Kind.INTERCEPTOR: 1.6}
const SOUND_DB: Dictionary[Kind, float] = {Kind.LIGHT: -13.0, Kind.HEAVY: -8.0, Kind.INTERCEPTOR: -16.0}
const PROVIDER: StringName = &"grid"
const ACTIONS: Array[StringName] = [&"info", &"free", &"hold", &"repair"]

## A mount was knocked out (its health gone) or repaired: its name.
signal mount_knocked_out(mount_name: String)
signal mount_repaired(mount_name: String)

var station: Station = null
var mounts: Array[TurretMount] = []
## The station's people: who the grid fires for.
var faction: StringName = Factions.EARTH_ALLIANCE
## Each mount's own health, in `mounts`' order.
var health: GridMountHealth = null

var _pool: MuzzleFlashPool = null


## The grid's mounts for `p_station` (built, its hardpoints read), each under the station's visuals and bound to its frame or
## drum body as the core comes. Call before the station enters the tree.
func build(p_station: Station) -> void:
	station = p_station
	name = "Grid"
	for entry: Dictionary in station.hardpoints.grid_mounts:
		var kind: Kind = KIND_OF.get(String(entry.get("kind", "")), Kind.LIGHT)
		var on_drum: bool = entry["body"] == StationHardpoints.DRUM
		var scale_k: float = MODEL_SCALE[kind]
		var mount: TurretMount = TurretMount.create({"name": entry["name"], "position": entry["position"], "up": entry["up"],
				"arc_deg": ARC_DEG, "barrel_m": MODEL_BARREL_M * scale_k}, load(WEAPONS[kind]) as WeaponSpec, faction)
		mount.grid_kind = kind
		mount.host = station.drum_body if on_drum else station
		mount.transform.basis = TurretMount.base_basis(mount.up).scaled(Vector3.ONE * scale_k)
		mount.use_model(TurretMount.model_for(MODEL_ASSET))
		mount.shot_fired.connect(_on_fired.bind(mount))
		mount.intercepted.connect(_on_intercepted.bind(mount))
		(station.drum_pivot if on_drum else station.frame_piece).add_child(mount)
		mounts.append(mount)
	health = GridMountHealth.from_mounts(station.hardpoints.grid_mounts,
			func(kind_name: String) -> int: return KIND_OF.get(kind_name, Kind.LIGHT))


## A hit of `amount` on the station at `point` in `body`'s frame (`Station`, beside its section's share): the mounts near it wear
## down, and one that reaches zero is knocked out.
func take_hit(body: String, point: Vector3, amount: float) -> void:
	if health == null:
		return
	for i: int in health.hit(body, point, amount):
		mounts[i].knocked_out = true
		mount_knocked_out.emit(mounts[i].mount_name)


## Repairs mount `mount_name` (or every mount for `all`); false for no such mount.
func repair(mount_name: String) -> bool:
	if mount_name == "all":
		for i: int in mounts.size():
			_repair_at(i)
		return true
	var i: int = health.index_of(mount_name)
	if i < 0:
		return false
	_repair_at(i)
	return true


func _repair_at(i: int) -> void:
	if health.repair(i):
		mounts[i].knocked_out = false
		mount_repaired.emit(mounts[i].mount_name)


## The knocked-out mounts' names.
func knocked_out() -> PackedStringArray:
	var out := PackedStringArray()
	for m: TurretMount in mounts:
		if m.knocked_out:
			out.append(m.mount_name)
	return out


## Each mount as a point an attacker can aim at (M7-T10): `name`, `kind`, `position` (World, now) and `alive`.
func sub_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: TurretMount in mounts:
		out.append({"name": m.mount_name, "kind": m.grid_kind, "position": m.global_position, "alive": not m.knocked_out})
	return out


func _ready() -> void:
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## The mounts of one kind.
func of_kind(kind: Kind) -> Array[TurretMount]:
	var out: Array[TurretMount] = []
	for m: TurretMount in mounts:
		if m.grid_kind == kind:
			out.append(m)
	return out


## The mount named `mount_name` (D75's `L1` to `I9`), or null.
func mount(mount_name: String) -> TurretMount:
	for m: TurretMount in mounts:
		if m.mount_name == mount_name:
			return m
	return null


## The sides the grid is weapons free against now.
func free_sides() -> PackedStringArray:
	var out := PackedStringArray()
	var sim: SimCore = _sim()
	if sim == null:
		return out
	var pairs: PackedStringArray = sim.core.grid_free_sides()
	for i: int in range(0, pairs.size() - 1, 2):
		if StringName(pairs[i]) == faction:
			out.append(pairs[i + 1])
	return out


## Sets the grid weapons free against `side` (as a hostile shot would), or holds fire against it (every side when empty).
func set_free(side: StringName, on: bool) -> void:
	var sim: SimCore = _sim()
	if sim != null:
		sim.core.set_grid_free(faction, side, on)


## `[light pulse shots, heavy cannon shots, projectiles shot down, of them missiles, shots the hull blocked]`.
func readouts() -> PackedInt64Array:
	var sim: SimCore = _sim()
	return sim.core.grid_readouts() if sim != null else PackedInt64Array([0, 0, 0, 0, 0])


## How many mounts the core holds for the grid now.
func bound_count() -> int:
	var n: int = 0
	for m: TurretMount in mounts:
		n += 1 if m.slot() >= 0 else 0
	return n


func _sim() -> SimCore:
	return SimCore.for_tree(get_tree()) if is_inside_tree() else null


# A gun's shot: the flash at its muzzle (the pitch holder turns with the barrel).
func _on_fired(_at: Vector3, m: TurretMount) -> void:
	_flash(m)


# A battery's kill: its muzzle flashes and the projectile goes up in a spark of the battery's colour.
func _on_intercepted(point: Vector3, m: TurretMount) -> void:
	_flash(m)
	var world: Node3D = WorldFrame.of(self)
	if world != null:
		var spark := ImpactFlash.create(m.weapon.bolt_color)
		world.add_child(spark)
		spark.global_position = point
		spark.reset_physics_interpolation()


func _flash(m: TurretMount) -> void:
	if _pool == null or not is_instance_valid(_pool):
		_pool = MuzzleFlashPool.attach(WorldFrame.of(self))
	if _pool != null:
		_pool.trigger(m.pitch, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -MODEL_BARREL_M)))


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"mounts": {"get": func() -> String: return _mounts_text(),
				"doc": "The grid's mounts by kind (D75: 12 light pulse, 2 heavy cannons, 9 interceptors) and how many the core holds"},
		&"free": {"get": func() -> String: return ", ".join(free_sides()) if not free_sides().is_empty() else "holding",
				"doc": "The sides the grid is weapons free against (it never fires first; a hostile shot at the station frees it)"},
		&"knocked_out": {"get": func() -> String: return _knocked_out_text(),
				"doc": "The mounts knocked out (dark and silent until grid repair), and each damaged one's health"},
		&"shots": {"get": func() -> String: return _shots_text(),
				"doc": "Shots by the light and heavy guns, projectiles shot down (missiles), shots the station's hull blocked"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"The station's defence grid (M7-T07): info, free <side>, hold [side], repair <mount|all>",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"side")]), _cmd_grid, self)


func _mounts_text() -> String:
	return "%d light pulse, %d heavy cannons, %d interceptors; %d bound" % [of_kind(Kind.LIGHT).size(),
			of_kind(Kind.HEAVY).size(), of_kind(Kind.INTERCEPTOR).size(), bound_count()]


func _knocked_out_text() -> String:
	var parts := PackedStringArray()
	for i: int in health.count():
		if health.health[i] < health.max_health[i]:
			parts.append("%s %s" % [health.names[i], "KNOCKED OUT" if health.is_out(i) else "%.0f/%.0f" % [health.health[i],
					health.max_health[i]]])
	return "%d knocked out%s" % [health.out_count(), (": " + ", ".join(parts)) if not parts.is_empty() else ""]


func _shots_text() -> String:
	var r: PackedInt64Array = readouts()
	return "light %d, heavy %d, shot down %d (missiles %d), blocked by the hull %d" % [r[0], r[1], r[2], r[3], r[4]]


func _cmd_grid(args: Dictionary) -> ConsoleResult:
	var side: String = str(args[&"side"]) if args[&"side"] != null else ""
	if _sim() == null:
		return ConsoleResult.failure("grid: no native core in this world")
	match StringName(args[&"action"]):
		&"free":
			if side.is_empty() or not Factions.is_hostile(faction, StringName(side)):
				return ConsoleResult.failure("grid free <side>: a side hostile to %s" % faction)
			set_free(StringName(side), true)
			return ConsoleResult.line("grid weapons free against %s" % side)
		&"hold":
			set_free(StringName(side), false)
			return ConsoleResult.line("grid holding fire%s" % (" against %s" % side if not side.is_empty() else ""))
		&"repair":
			if side.is_empty() or not repair(side):
				return ConsoleResult.failure("grid repair <mount|all>; mounts: %s" % ", ".join(health.names))
			return ConsoleResult.line("grid repaired %s; %s" % [side, _knocked_out_text()])
	return ConsoleResult.line("grid: %s; free against %s; %s; %s" % [_mounts_text(),
			", ".join(free_sides()) if not free_sides().is_empty() else "nobody (holding)", _knocked_out_text(), _shots_text()])
