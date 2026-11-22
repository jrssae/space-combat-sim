class_name HulkStages
extends RefCounted
## How a disabled capital winds down (M10-T10, D12.7): power goes first, at once (its weapons and bays stop; its lights die
## over `lights_fade_s`, stuttering as they go), then control at `control_loss_s` (the helm stops steering, the thrusters and
## the assist go, the mains hold the setting they last had), then thrust: the drive's share falls evenly from the loss to cold
## at `cold_s`, and from then on the hull drifts on its last motion with no force. Pure; `CapitalShip` advances it each tick.

enum Stage {
	LIVE,  ## not disabled
	POWER_LOST,  ## weapons, bays and lights gone; the helm still steers on its last orders with what the drive has left
	CONTROL_LOST,  ## no steering: the mains wind down on their last setting
	COLD,  ## no force at all: a drifting hulk
}

## Lights stutter this many times a second while they die, and a stutter drops them to this share.
const FLICKER_HZ: float = 9.0
const FLICKER_DIP: float = 0.25

var control_loss_s: float = 2.0
var cold_s: float = 6.0
var lights_fade_s: float = 3.0
var stage: Stage = Stage.LIVE
## Time since it was disabled, s (gameplay time: the ticks' deltas).
var elapsed_s: float = 0.0

var _seed: int = 0
var _last: FlightCommand = null  # the helm's last command while it still had control


## The stages with the file's numbers (`CapitalData.hulk_rule`); `seed_value` sets where its lights stutter (its name's hash).
static func from_rules(seed_value: int) -> HulkStages:
	var out := HulkStages.new()
	out.control_loss_s = maxf(CapitalData.hulk_rule("control_loss_s"), 0.0)
	out.cold_s = maxf(CapitalData.hulk_rule("cold_s"), out.control_loss_s)
	out.lights_fade_s = maxf(CapitalData.hulk_rule("lights_fade_s"), 0.0)
	out._seed = seed_value
	return out


## The ship was disabled: power is gone from now.
func start() -> void:
	if stage == Stage.LIVE:
		stage = Stage.POWER_LOST
		elapsed_s = 0.0
		_last = null


## Straight to cold (a hulk handed to the low-attention tier drifts with no force from the first tick).
func finish() -> void:
	stage = Stage.COLD
	elapsed_s = maxf(elapsed_s, maxf(cold_s, lights_fade_s))


## Whole again (the console's heal, a rebuild).
func reset() -> void:
	stage = Stage.LIVE
	elapsed_s = 0.0
	_last = null


func is_live() -> bool:
	return stage == Stage.LIVE


func is_cold() -> bool:
	return stage == Stage.COLD


## Whether the helm still steers.
func has_control() -> bool:
	return stage == Stage.LIVE or stage == Stage.POWER_LOST


## Moves the wind-down on by `delta` s. True when that changed the stage.
func advance(delta: float) -> bool:
	if stage == Stage.LIVE or stage == Stage.COLD:
		return false
	elapsed_s += delta
	var next: Stage = Stage.POWER_LOST
	if elapsed_s >= cold_s:
		next = Stage.COLD
	elif elapsed_s >= control_loss_s:
		next = Stage.CONTROL_LOST
	if next == stage:
		return false
	stage = next
	return true


## The drive's share left: 1 until it is disabled, then falling evenly to 0 at cold.
func thrust_level() -> float:
	match stage:
		Stage.LIVE:
			return 1.0
		Stage.COLD:
			return 0.0
	return clampf(1.0 - elapsed_s / cold_s, 0.0, 1.0) if cold_s > 0.0 else 0.0


## The lights' share: 1 until it is disabled, then dying over `lights_fade_s`, stuttering as a failing supply does.
func lights_level() -> float:
	if stage == Stage.LIVE:
		return 1.0
	if elapsed_s >= lights_fade_s:
		return 0.0
	var level: float = 1.0 - elapsed_s / lights_fade_s
	var slot: int = int(floor(elapsed_s * FLICKER_HZ)) + _seed
	return level * FLICKER_DIP if posmod(hash(slot), 4) == 0 else level


## Whether the lights are still changing (the visuals stop asking once they are out).
func lights_fading() -> bool:
	return stage != Stage.LIVE and elapsed_s < lights_fade_s + 0.5


## The command flown now, from what the helm asks (`helm`, null once it has no control): as asked while live; steering kept
## and the push scaled by the drive's share while power is lost; the mains' last setting winding down with no steering once
## control is gone; nothing when cold.
func shape(helm: FlightCommand) -> FlightCommand:
	if stage == Stage.LIVE:
		return helm if helm != null else FlightCommand.new()
	var out := FlightCommand.new()
	var level: float = thrust_level()
	if stage == Stage.POWER_LOST and helm != null:
		_last = helm
		out.rot = helm.rot
		out.strafe = helm.strafe * level
		_set_mains(out, helm, level)
	elif stage == Stage.CONTROL_LOST and _last != null:
		_set_mains(out, _last, level)
	return out


## Whether the flight assist still flies (it is the helm's: gone with control).
func assist_on() -> bool:
	return has_control()


## The stage's name for the console.
func stage_name() -> String:
	return ["live", "power lost", "control lost", "cold"][stage]


static func _set_mains(out: FlightCommand, from: FlightCommand, level: float) -> void:
	out.main_left = from.main_left * level
	out.main_right = from.main_right * level
	out.retro_left = from.retro_left * level
	out.retro_right = from.retro_right * level
