class_name EngineVoices
extends RefCounted
## Which thrusters are heard, where on their ship and how loud (M5-T19, D60). The nodes are `AudioDirector`'s; this class
## only decides, so it is unit-tested without a scene.
##
## Every ship has a voice per pod (its main and retro nozzle share it, heard at whichever fires harder) playing `main_burst`.
## The player's ship also has one per RCS cluster playing `rcs_burst`: its jets grouped by where they sit about the centre of
## mass (`rcs_clusters`), so any hull gets a handful. `allocate` grants at most `cap` voices: the player's first, then whole
## ships, nearest first, within `AUDIBLE_RANGE_M`. The ranking is the core's (`ScsSimCore.ships_near`, M5-T28): a re-rank is
## `begin_allocation`, an `offer` per ship the core listed (nearest first, until the budget is spent) and `finish_allocation`,
## so its work follows the ships in earshot, never the ships in play (`allocate_work`). `step` moves only the granted voices,
## so a frame costs one unit per voice however many ships and nozzles exist (`step_work`); levels come from the same mapping
## as the glows (`ThrusterGlowLevels`).
##
## Envelopes follow docs/design-references.md "Roars and pass-bys" and run on the frame's delta (sim time).

enum Kind { POD, RCS }

const DEFAULT_CAP: int = 24
const AUDIBLE_RANGE_M: float = 1500.0
## Demand below this is the flight computer's settling, not a burst: silent.
const GATE: float = 0.05
## A voice released below this level is silent and its player can stop.
const SILENT: float = 0.001
## Envelope time constants, s. A 10-90 % rise takes 2.2 of them, a 30 dB fall 3.45.
const POD_ATTACK_TAU_S: float = 0.009  # a 20 ms rise (reference: 5-35 ms)
const POD_RELEASE_TAU_S: float = 0.0116  # 30 dB down in 40 ms (reference: stops in 30-50 ms)
const RCS_ATTACK_TAU_S: float = 0.027  # a 60 ms rise (reference: 25-100 ms)
const RCS_RELEASE_SHORT_TAU_S: float = 0.15  # after a pulse (reference: 120-250 ms)
const RCS_RELEASE_LONG_TAU_S: float = 0.65  # after a long burn (reference: up to 0.65 s)
const RCS_LONG_BURN_S: float = 1.5  # a burn this long earns the longest release
## A jet plays an octave low at silence and at its own pitch at full level: its brightness follows its level.
const RCS_DULL_PITCH: float = 0.5
## Along each axis, jets within this fraction of the farthest jet's offset from the centre of mass are on the centre line.
const CLUSTER_CENTRE_BAND: float = 0.2
const _GOLDEN: float = 0.6180339887498949

## Most voices granted at once (`settings.engine_voice_cap`).
var cap: int = DEFAULT_CAP

## Per voice, every ship's: owner, kind, place on the ship (body frame; a pod's main nozzle or a cluster's centre) and,
## for pods, the retro nozzle.
var voice_ship := PackedInt32Array()
var voice_kind := PackedInt32Array()
var voice_position := PackedVector3Array()
var voice_retro_position := PackedVector3Array()
## Per voice: the envelope (0..1, amplitude), the demand it moves toward, and whether a pod is heard at its retro.
var level := PackedFloat64Array()
var target := PackedFloat64Array()
var at_retro := PackedByteArray()
## The voices the last `allocate` granted, the ships they belong to, and those that lost their grant (their players stop).
var active := PackedInt32Array()
var voiced_ships := PackedInt32Array()
var revoked := PackedInt32Array()
## Units of work done by the last `step` (one per granted voice) and the last re-rank (the player and one per ship offered).
var step_work: int = 0
var allocate_work: int = 0

var _layouts: Array[ThrusterLayout] = []
var _outputs: Array[FlightOutput] = []
var _first_voice := PackedInt32Array()
var _voice_count := PackedInt32Array()
var _player: int = -1
var _main_nozzle := PackedInt32Array()
var _retro_nozzle := PackedInt32Array()
var _tags: Array[PackedStringArray] = []
var _burn_s := PackedFloat64Array()
var _release_tau := PackedFloat64Array()
var _granted := PackedByteArray()
var _before := PackedInt32Array()
var _budget: int = 0
var _removed: int = 0


## Registers a ship and makes its voices; returns its id. The player's ship also gets its RCS cluster voices.
func add_ship(layout: ThrusterLayout, is_player: bool) -> int:
	var ship: int = _layouts.size()
	_layouts.append(layout)
	_outputs.append(null)
	_first_voice.append(voice_ship.size())
	var mains := PackedInt32Array()
	var retros := PackedInt32Array()
	mains.resize(layout.pod_count())
	retros.resize(layout.pod_count())
	for i: int in layout.nozzle_count():
		if ThrusterLayout.is_main_group(layout.nozzle_groups[i]):
			mains[layout.nozzle_pods[i]] = i
		else:
			retros[layout.nozzle_pods[i]] = i
	for pod: int in layout.pod_count():
		_add_voice(ship, Kind.POD, layout.nozzle_positions[mains[pod]], layout.nozzle_positions[retros[pod]], mains[pod],
				retros[pod], PackedStringArray())
	if is_player:
		_player = ship
		for cluster: Dictionary in rcs_clusters(layout):
			var at: Vector3 = cluster["position"]
			_add_voice(ship, Kind.RCS, at, at, -1, -1, cluster["tags"])
	_voice_count.append(voice_ship.size() - _first_voice[ship])
	return ship


## Ships with voices now (a removed ship no longer counts).
func ship_count() -> int:
	return _layouts.size() - _removed


## Voice ids of a ship: its pods in pod order, then its RCS clusters.
func voices_of(ship: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v: int in range(_first_voice[ship], _first_voice[ship] + _voice_count[ship]):
		out.append(v)
	return out


## The output a voiced ship flew on its last tick (null: silent).
func set_output(ship: int, output: FlightOutput) -> void:
	_outputs[ship] = output


## Starts a re-rank: the last grants are let go and the player's voices (when it is in play) are granted first. Follow with
## `offer` for the ships in earshot, nearest first, and then `finish_allocation`.
func begin_allocation(player_in_play: bool) -> void:
	allocate_work = 0
	_before = active
	for v: int in _before:
		_granted[v] = 0
	active = PackedInt32Array()
	voiced_ships.resize(0)
	_budget = cap
	if _player >= 0:
		allocate_work += 1
		if player_in_play:
			_budget -= _grant(_player, _budget)


## Grants a whole ship's voices if they fit in what is left of the cap; a ship with none, or the player's, is passed over.
func offer(ship: int) -> void:
	allocate_work += 1
	if ship != _player and _voice_count[ship] > 0 and _voice_count[ship] <= _budget:
		_budget -= _grant(ship, _budget)


## What is left of the cap in this re-rank: the caller stops offering at 0.
func budget_left() -> int:
	return _budget


## Ends the re-rank: a voice that lost its grant restarts cold and is listed in `revoked`.
func finish_allocation() -> void:
	revoked.resize(0)
	for v: int in _before:
		if _granted[v] == 0:
			revoked.append(v)
			_go_cold(v)
	_before = PackedInt32Array()


## Takes a ship out for good (it despawned): its voices are revoked, returned so their players can stop, and never granted
## again. Its ids stay taken, so the other ships' keep their meaning.
func remove_ship(ship: int) -> PackedInt32Array:
	var gone := PackedInt32Array()
	if ship < 0 or ship >= _layouts.size() or _layouts[ship] == null:
		return gone
	var kept := PackedInt32Array()
	for v: int in active:
		if voice_ship[v] == ship:
			_granted[v] = 0
			gone.append(v)
			_go_cold(v)
		else:
			kept.append(v)
	active = kept
	var at: int = voiced_ships.find(ship)
	if at >= 0:
		voiced_ships.remove_at(at)
	_voice_count[ship] = 0
	_layouts[ship] = null
	_outputs[ship] = null
	if _player == ship:
		_player = -1
	_removed += 1
	return gone


## Moves every granted voice's envelope on by `delta` seconds of sim time toward its thrusters' demand.
func step(delta: float) -> void:
	step_work = 0
	var dt: float = maxf(delta, 0.0)
	for v: int in active:
		step_work += 1
		var ship: int = voice_ship[v]
		var output: FlightOutput = _outputs[ship]
		var demand: float = 0.0
		if voice_kind[v] == Kind.POD:
			if output != null:
				var main: float = ThrusterGlowLevels.pod_nozzle_level(_layouts[ship], output, _main_nozzle[v])
				var retro: float = ThrusterGlowLevels.pod_nozzle_level(_layouts[ship], output, _retro_nozzle[v])
				demand = maxf(main, retro)
				if demand >= GATE:
					at_retro[v] = 1 if retro > main else 0
			demand = demand if demand >= GATE else 0.0
			level[v] = step_level(level[v], demand, dt, POD_ATTACK_TAU_S, POD_RELEASE_TAU_S)
		else:
			if output != null:
				demand = ThrusterGlowLevels.rcs_level(_tags[v], output.rcs_force_level, output.rcs_torque_level)
			demand = demand if demand >= GATE else 0.0
			if demand > 0.0:
				_burn_s[v] += dt
				_release_tau[v] = rcs_release_tau(_burn_s[v])
			else:
				_burn_s[v] = 0.0
			level[v] = step_level(level[v], demand, dt, RCS_ATTACK_TAU_S, _release_tau[v])
		target[v] = demand
		if demand == 0.0 and level[v] < SILENT:
			level[v] = 0.0


## Groups a layout's RCS jets by where they sit: each jet falls on one side of the centre of mass, or on its centre line,
## along each axis, and jets in the same place share a voice. Returns `{position, members, tags}` per cluster (the
## members' centre, their indices in `layout.rcs_nozzles`, and every tag they answer to) in order of first jet.
static func rcs_clusters(layout: ThrusterLayout) -> Array[Dictionary]:
	var reach := Vector3.ZERO
	for jet: Dictionary in layout.rcs_nozzles:
		reach = reach.max(((jet["position"] as Vector3) - layout.center_of_mass).abs())
	var band: Vector3 = reach * CLUSTER_CENTRE_BAND
	var by_place: Dictionary = {}  # Vector3i -> cluster index
	var sums := PackedVector3Array()
	var members: Array[PackedInt32Array] = []
	var tags: Array[PackedStringArray] = []
	for j: int in layout.rcs_nozzles.size():
		var jet: Dictionary = layout.rcs_nozzles[j]
		var offset: Vector3 = (jet["position"] as Vector3) - layout.center_of_mass
		var place := Vector3i(_side(offset.x, band.x), _side(offset.y, band.y), _side(offset.z, band.z))
		if not by_place.has(place):
			by_place[place] = sums.size()
			sums.append(Vector3.ZERO)
			members.append(PackedInt32Array())
			tags.append(PackedStringArray())
		var c: int = by_place[place]
		sums[c] += jet["position"] as Vector3
		var in_cluster: PackedInt32Array = members[c]
		in_cluster.append(j)
		members[c] = in_cluster
		var answers: PackedStringArray = tags[c]
		for tag: String in jet["tags"] as PackedStringArray:
			if not answers.has(tag):
				answers.append(tag)
		tags[c] = answers
	var clusters: Array[Dictionary] = []
	for c: int in sums.size():
		clusters.append({"position": sums[c] / float(members[c].size()), "members": members[c], "tags": tags[c]})
	return clusters


## One envelope step toward `target_level`: first order, at the attack rate going up and the release rate going down,
## exact for any `dt` so it sounds the same at any frame rate.
static func step_level(current: float, target_level: float, dt: float, attack_tau_s: float, release_tau_s: float) -> float:
	var tau: float = attack_tau_s if target_level > current else release_tau_s
	return target_level + (current - target_level) * exp(-maxf(dt, 0.0) / tau)


## A jet's release time constant after burning `burn_s` seconds: short after a pulse, long after a sustained burn.
static func rcs_release_tau(burn_s: float) -> float:
	return lerpf(RCS_RELEASE_SHORT_TAU_S, RCS_RELEASE_LONG_TAU_S, clampf(burn_s / RCS_LONG_BURN_S, 0.0, 1.0))


## A jet's playback pitch at an envelope level: duller when softer.
static func rcs_pitch(voice_level: float) -> float:
	return lerpf(RCS_DULL_PITCH, 1.0, clampf(voice_level, 0.0, 1.0))


## Where in its loop a voice starts, spread so no two voices of a ship play in step.
static func start_offset(voice: int, length_s: float) -> float:
	return fposmod(float(voice) * _GOLDEN, 1.0) * length_s


func _add_voice(ship: int, kind: Kind, at: Vector3, retro_at: Vector3, main_nozzle: int, retro_nozzle: int,
		tags: PackedStringArray) -> void:
	voice_ship.append(ship)
	voice_kind.append(kind)
	voice_position.append(at)
	voice_retro_position.append(retro_at)
	level.append(0.0)
	target.append(0.0)
	at_retro.append(0)
	_main_nozzle.append(main_nozzle)
	_retro_nozzle.append(retro_nozzle)
	_tags.append(tags)
	_burn_s.append(0.0)
	_release_tau.append(RCS_RELEASE_SHORT_TAU_S)
	_granted.append(0)


# Grants up to `budget` of a ship's voices in order; returns how many.
func _grant(ship: int, budget: int) -> int:
	var n: int = mini(_voice_count[ship], budget)
	for v: int in range(_first_voice[ship], _first_voice[ship] + n):
		_granted[v] = 1
		active.append(v)
	if n > 0:
		voiced_ships.append(ship)
	return n


func _go_cold(v: int) -> void:
	level[v] = 0.0
	target[v] = 0.0
	_burn_s[v] = 0.0
	_release_tau[v] = RCS_RELEASE_SHORT_TAU_S


static func _side(offset: float, band: float) -> int:
	if absf(offset) <= band:
		return 0
	return 1 if offset > 0.0 else -1
