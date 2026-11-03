class_name AiThinkRate
extends RefCounted
## When an AI ship thinks (architecture §17.4, M4-T04): every tick near the player, at the far rate on staggered ticks
## farther out or with no player alive. Pure; `AiPilotDriver` holds the state and asks.


## Physics ticks between a far ship's thinks at `far_hz` (at least 1: a rate at or above the tick rate thinks every tick).
static func period_ticks(far_hz: float, physics_hz: int) -> int:
	return maxi(1, roundi(float(physics_hz) / maxf(far_hz, 0.001)))


## Whether a far ship thinks on its `tick`-th step. Each ship's `ordinal` shifts its beat, so consecutive ordinals share
## the period's ticks evenly.
static func on_beat(tick: int, ordinal: int, period: int) -> bool:
	return period <= 1 or posmod(tick + ordinal, period) == 0


## Whether a ship thinks this tick: always with the rule off, when woken (a new pilot, a hit) or near the player, else on
## its beat.
static func thinks(enabled: bool, woken: bool, near: bool, tick: int, ordinal: int, period: int) -> bool:
	return not enabled or woken or near or on_beat(tick, ordinal, period)
