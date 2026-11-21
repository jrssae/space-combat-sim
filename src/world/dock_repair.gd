class_name DockRepair
extends RefCounted
## How long the station keeps a docked fighter before it launches again (M8-T06, D82; maintainer, 2026-11-18). An AI wingman
## waits a fixed time inside; the player does not wait at all: it is repaired on the way through, the docking's cinematic
## running straight into the launch's. Pure; the numbers are `data/station/docking.json`'s `repair`.

## Seconds an AI wingman spends inside before a Cobra bay takes it.
var wingman_s: float = 30.0
## Seconds the player spends inside: none.
var player_s: float = 0.0


static func from_dict(raw: Variant) -> DockRepair:
	var out := DockRepair.new()
	if not (raw is Dictionary):
		return out
	var d: Dictionary = raw
	out.wingman_s = maxf(float(d.get("wingman_s", out.wingman_s)), 0.0)
	out.player_s = maxf(float(d.get("player_s", out.player_s)), 0.0)
	return out


## Seconds in the bay for the player's ship or an AI wingman's, whatever its damage.
func time_s(is_player: bool) -> float:
	return player_s if is_player else wingman_s
