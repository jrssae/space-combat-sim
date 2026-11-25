class_name StationGrid
extends Node
## The station's defense grid (M7-T07, D75, AC6): D75's 23 mounts from the station's hardpoints (M7-T05) bound to the native
## turret rows as the grid's kinds: 12 light pulse turrets (anti-fighter), 2 heavy cannons (capitals first) and 9 interceptor
## batteries. Everything a mount decides runs in the core (`grid_kernels`): the guns' pick in the AI job one tick behind, the
## aim, gate and shot, and the interceptors' choice, on the main thread. This node builds the mounts, says what they did and
## holds the console.
##
## - **The station never fires first** (maintainer): the guns hold fire until a hostile fires on the station or on a friendly
##   near it; from then on the grid is weapons free against that side for the rest of the fight (the core's latch).
## - **Interceptors are always on**: each battery fires blue-white pulses from its four barrels in turn at hostile missiles and
##   pulse bolts whose path meets the hull (never beams); a pulse flies, can miss, and takes the first such projectile it meets
##   (M7-T41).
## - **The drum's mounts turn with the drum**: they bind to the drum's body and hang from its visual pivot; the frame's stay
##   fixed. The station's own frame and drum block every gun's line of fire.
## - **Mounts can be knocked out** (maintainer, after T07): each has its own health (`GridMountHealth`); a hit on the station near
##   it wears it down (the hull half as much, `StationDamage`), and at zero it stops (dark, silent) until `repair` (a mission, or
##   `grid repair`). A station with no power (a hulk or a wreck, M10-T65) keeps its grid off (`set_powered`).
## - **Sub-points**: `sub_points` (and the core's `grid_points`) give each mount's place and whether it works, for attackers (T10).
## - The models are per kind (`MODEL_ASSETS`): the light guns wear the Saturns' turret (T27) scaled, the heavy cannons their oval
##   gun in its recess (M7-T43), the interceptor batteries their own (M7-T42); sounds are the turret shot pitched per kind.
## - **Heavy cannons** (M7-T43) fire three-shot bursts from their trunnion (the line of fire starts there, clear of the recess), a
##   large green pulse with a large green flash at the oval muzzle.
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
## The model each kind wears, by asset id, and its scale: the light guns the Saturns' turret (M5-T27), the heavy cannons their
## oval gun (M7-T43) and the interceptor batteries their four-barrel battery (M7-T42), each at its own size.
const MODEL_ASSETS: Dictionary[Kind, String] = {Kind.LIGHT: "saturn_4_transport", Kind.HEAVY: "grid_heavy_cannon",
		Kind.INTERCEPTOR: "grid_interceptor_battery"}
const MODEL_SCALE: Dictionary[Kind, float] = {Kind.LIGHT: 2.0, Kind.HEAVY: 1.0, Kind.INTERCEPTOR: 1.0}
## A model's barrel reach when its manifest gives none (the Saturns' turret at scale 1), m.
const MODEL_BARREL_M: float = 4.5
## The heavy cannon's own trunnion height and barrel reach (`grid_heavy_cannon`'s manifest), m, so it fires from over its recess
## even in a build without its model (M7-T43: without them it fired from inside the recess and the balance broke).
const HEAVY_TRUNNION_M: float = 9.5
const HEAVY_BARREL_M: float = 22.5
## An interceptor battery's barrels (M7-T41): each recharges this long after it fires, s; the battery's interval spaces them.
const BARREL_RECHARGE_S: float = 1.0
## A battery's muzzle glow: the flash's warm colour scaled to the pulses' blue-white (M7-T41).
const PULSE_GLOW: Color = Color(0.53, 1.0, 2.0)
## A heavy cannon's muzzle flash (M7-T43): the warm flash turned green, and as big as its 9 m muzzle.
const HEAVY_GLOW: Color = Color(0.35, 1.6, 0.55)
const HEAVY_FLASH_SCALE: float = 9.0
## A pulse meeting a projectile shows a smaller flash than a hit on a hull (M7-T41).
const MEET_FLASH_SCALE: float = 0.6
## Each mount's cone round its base's up, degrees (a hemisphere and a little below it).
const ARC_DEG: float = 200.0
## How the turret shot sounds per kind: pitch, and level (dB) on top of `turret_fire`'s `SoundMix` level.
const SOUND_PITCH: Dictionary[Kind, float] = {Kind.LIGHT: 1.0, Kind.HEAVY: 0.55, Kind.INTERCEPTOR: 1.6}
const SOUND_DB: Dictionary[Kind, float] = {Kind.LIGHT: 1.0, Kind.HEAVY: 6.0, Kind.INTERCEPTOR: -2.0}
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
## False while the station has no power (`set_powered`).
var powered: bool = true
var _wanted_on: bool = true

var _pool: MuzzleFlashPool = null
var _fx: FxPool = null


## The grid's mounts for `p_station` (built, its hardpoints read), each under the station's visuals and bound to its frame or
## drum body as the core comes. Call before the station enters the tree.
func build(p_station: Station) -> void:
	station = p_station
	name = "Grid"
	for entry: Dictionary in station.hardpoints.grid_mounts:
		var kind: Kind = KIND_OF.get(String(entry.get("kind", "")), Kind.LIGHT)
		var on_drum: bool = entry["body"] == StationHardpoints.DRUM
		var scale_k: float = MODEL_SCALE[kind]
		var model_id: String = MODEL_ASSETS[kind]
		var mount: TurretMount = TurretMount.create({"name": entry["name"], "position": entry["position"], "up": entry["up"],
				"arc_deg": ARC_DEG, "barrel_m": TurretMount.barrel_reach(model_id,
				HEAVY_BARREL_M if kind == Kind.HEAVY else MODEL_BARREL_M) * scale_k},
				load(WEAPONS[kind]) as WeaponSpec, faction)
		mount.grid_kind = kind
		mount.host = station.drum_body if on_drum else station
		mount.transform.basis = TurretMount.base_basis(mount.up).scaled(Vector3.ONE * scale_k)
		mount.use_model(TurretMount.model_for(model_id))
		if kind == Kind.INTERCEPTOR:
			mount.muzzles_m = muzzles_for(kind)
			mount.trunnion_m = mount.pitch.position * scale_k
			mount.barrel_recharge_s = BARREL_RECHARGE_S
		elif kind == Kind.HEAVY:
			if mount.pitch.position.is_zero_approx():
				mount.pitch.position = Vector3(0.0, HEAVY_TRUNNION_M, 0.0)  # no model: the gun's own trunnion all the same
			mount.trunnion_m = mount.pitch.position * scale_k  # it fires from its trunnion, over its recess
		mount.shot_fired.connect(_on_fired.bind(mount))
		mount.intercepted.connect(_on_intercepted.bind(mount))
		(station.drum_pivot if on_drum else station.frame_piece).add_child(mount)
		mounts.append(mount)
	health = GridMountHealth.from_mounts(station.hardpoints.grid_mounts,
			func(kind_name: String) -> int: return KIND_OF.get(kind_name, Kind.LIGHT))


## The barrels a mount of `kind` fires from in turn, in its pitch frame (origin at the trunnion), m, in firing order (M7-T41):
## the interceptor battery model's four muzzles (M7-T42); none for the guns, which fire down their axis.
static func muzzles_for(kind: Kind) -> Array[Vector3]:
	if kind != Kind.INTERCEPTOR:
		return [] as Array[Vector3]
	var out: Array[Vector3] = []
	for m: Vector3 in TurretMount.pitch_muzzles(MODEL_ASSETS[kind]):
		out.append(m * MODEL_SCALE[kind])
	return out


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


## Adds `amount` to mount `i`'s health (a maintenance bot's work, M7-T35); a knocked-out mount comes back once above zero.
func repair_some(i: int, amount: float) -> void:
	if health != null and health.heal(i, amount):
		mounts[i].knocked_out = false
		mount_repaired.emit(mounts[i].mount_name)


## Takes `amount` off mount `i` alone (the console's staged damage, M7-T35).
func damage_mount(i: int, amount: float) -> void:
	if health != null and health.wear(i, amount):
		mounts[i].knocked_out = true
		mount_knocked_out.emit(mounts[i].mount_name)


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


## Whether the grid fires at all (M8-T34, Control's "defense grid on/off"): off, no gun or interceptor fires; the weapons-free
## latch is kept for when it comes back on.
func is_on() -> bool:
	var sim: SimCore = _sim()
	return sim == null or not sim.core.grid_is_off(faction)


func set_on(on: bool) -> void:
	_wanted_on = on
	_apply_on()


## Whether the station has power for the grid (M10-T65, Q72): a hulk's or a wreck's grid stays off whatever it is told, and
## comes back as it was told once the station is whole again.
func set_powered(on: bool) -> void:
	powered = on
	_apply_on()


func _apply_on() -> void:
	var sim: SimCore = _sim()
	if sim != null:
		sim.core.set_grid_off(faction, not (_wanted_on and powered))


## How far from the station's centre its guns reach, m: the furthest any mount's fire goes (M8-T08: what a raider carrier
## stays outside of). 0 with no mount.
func reach_m() -> float:
	var reach: float = 0.0
	for mount: TurretMount in mounts:
		if mount.weapon != null:
			reach = maxf(reach, mount.position.length() + mount.weapon.turret_range_m)
	return reach


## Covering fire (M8-T34): every gun that reaches takes hostiles within `radius_m` of `ship` first, nearest it first; null ends it.
func set_cover(ship: Node3D, radius_m: float) -> void:
	var sim: SimCore = _sim()
	if sim != null:
		sim.core.set_grid_cover(faction, ship.get_instance_id() if ship != null else 0, radius_m)


## The body the grid covers now (its instance id), or 0.
func cover_body() -> int:
	var sim: SimCore = _sim()
	return int(sim.core.grid_cover_body(faction)) if sim != null else 0


## `[light pulse shots, heavy cannon shots, projectiles shot down, of them missiles, shots the hull blocked, interceptor pulses
## fired]`.
func readouts() -> PackedInt64Array:
	var sim: SimCore = _sim()
	return sim.core.grid_readouts() if sim != null else PackedInt64Array([0, 0, 0, 0, 0, 0])


## How many mounts the core holds for the grid now.
func bound_count() -> int:
	var n: int = 0
	for m: TurretMount in mounts:
		n += 1 if m.slot() >= 0 else 0
	return n


func _sim() -> SimCore:
	return SimCore.for_tree(get_tree()) if is_inside_tree() else null


# A shot: the flash at its muzzle (the pitch holder turns with the barrel); a battery's glows blue-white at the barrel that
# fired (M7-T41).
func _on_fired(_at: Vector3, m: TurretMount) -> void:
	if m.grid_kind == Kind.INTERCEPTOR and m.last_barrel >= 0 and m.last_barrel < m.muzzles_m.size():
		_flash(m, m.muzzles_m[m.last_barrel] / MODEL_SCALE[Kind.INTERCEPTOR], PULSE_GLOW)
	elif m.grid_kind == Kind.HEAVY:
		_flash(m, Vector3(0.0, 0.0, -m.barrel_m / MODEL_SCALE[Kind.HEAVY]), HEAVY_GLOW, HEAVY_FLASH_SCALE)
	else:
		_flash(m, Vector3(0.0, 0.0, -MODEL_BARREL_M))


# A battery's pulse met a projectile (M7-T41): a small flash and a scatter of sparks, both in the projectile's own colour.
func _on_intercepted(point: Vector3, color: Color, _m: TurretMount) -> void:
	var world: Node3D = WorldFrame.of(self)
	if world == null:
		return
	var flash := ImpactFlash.create(color, 0, MEET_FLASH_SCALE)
	world.add_child(flash)
	flash.global_position = point
	flash.reset_physics_interpolation()
	if _fx == null or not is_instance_valid(_fx):
		_fx = world.get_node_or_null(^"Fx") as FxPool
	if _fx != null:
		_fx.tint(_fx.burst(FxSpecs.INTERCEPT, point, Vector3.UP, Vector3.ZERO), color)


# A muzzle flash at `local` in the mount's pitch frame, its warm colour scaled by `tint` and its size by `size_scale`.
func _flash(m: TurretMount, local: Vector3, tint: Color = Color.WHITE, size_scale: float = 1.0) -> void:
	if _pool == null or not is_instance_valid(_pool):
		_pool = MuzzleFlashPool.attach(WorldFrame.of(self))
	if _pool != null:
		_pool.trigger(m.pitch, Transform3D(Basis.IDENTITY, local), tint, size_scale)


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"mounts": {"get": func() -> String: return _mounts_text(),
				"doc": "The grid's mounts by kind (D75: 12 light pulse, 2 heavy cannons, 9 interceptors) and how many the core holds"},
		&"on": {"get": func() -> bool: return is_on(), "doc": "The grid fires at all (M8-T34: Control's defense grid on/off)"},
		&"cover": {"get": func() -> int: return cover_body(), "doc": "The body covering fire protects (M8-T34), 0 for none"},
		&"free": {"get": func() -> String: return ", ".join(free_sides()) if not free_sides().is_empty() else "holding",
				"doc": "The sides the grid is weapons free against (it never fires first; a hostile shot at the station frees it)"},
		&"knocked_out": {"get": func() -> String: return _knocked_out_text(),
				"doc": "The mounts knocked out (dark and silent until grid repair), and each damaged one's health"},
		&"shots": {"get": func() -> String: return _shots_text(),
				"doc": "Shots by the light and heavy guns, interceptor pulses fired, projectiles shot down (missiles), shots the station's hull blocked"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"The station's defense grid (M7-T07): info, free <side>, hold [side], repair <mount|all>",
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
	return "light %d, heavy %d, interceptor pulses %d, shot down %d (missiles %d), blocked by the hull %d" % [r[0], r[1], r[5],
			r[2], r[3], r[4]]


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
