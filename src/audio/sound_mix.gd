class_name SoundMix
extends RefCounted
## The game's mix (M8-T12, roadmap M7-5): how loud each sound plays against the others. Every generated sound is written at
## one loudness reference (`REFERENCE_LUFS`, `tools/procgen/core/loudness.py`), so these levels are the only place one effect
## is set louder than another. A caller's own `volume_db` is a variation on top (a heavier gun, a buoy's smaller blast).
##
## Levels are in dB against the reference, heard at the effect's unit size (`UNIT_SIZE_M`); the comment on each row gives the
## loudness that makes (reference + level). The engines' rows are a whole ship at full thrust (`EngineVoices.gain`).

const REFERENCE_LUFS: float = -20.0

const LEVEL_DB: Dictionary[StringName, float] = {
	&"explosion": 8.0,  # -12: the loudest thing in a fight
	&"jump_in": 6.0,  # -14: a jump point opening, heard from far off
	&"main_burst": 4.0,  # -16: a ship's pods at full thrust, the bed the rest sits on
	&"pulse_fire": 2.0,  # -18: the Starfury's guns, the player's own most of the time
	&"raider_fire": 1.0,  # -19
	&"turret_fire": 1.0,  # -19: capital and station turrets (the grid varies it per kind)
	&"hit_hull": 1.0,  # -19
	&"rcs_burst": -1.0,  # -21: a ship's jets, under the pods
	&"warning_beep": 6.0,  # -14: hull low, must cut through a fight
	&"target_blip": 1.0,  # -19
	&"ui_move": 0.0,  # -20: a patter while the focus moves
	&"ui_accept": 3.0,  # -17
	&"ui_back": 3.0,  # -17
	&"radio_open": -1.0,  # -21: the squelches frame a line, never cover it
	&"radio_close": -1.0,  # -21
}

## Distance at which a 3D sound plays at its level (inverse distance beyond it, `max_db` 3 dB nearer).
const UNIT_SIZE_M: Dictionary[StringName, float] = {
	&"shot": 60.0,  # the pooled voices: guns, hits, explosions
	&"pod": 25.0,
	&"rcs": 15.0,
	&"jump_in": 120.0,
}

## The Master bus's limiter ceiling: the mix never clips however many sounds pile up.
const LIMITER_CEILING_DB: float = -0.5


## A sound's level against the reference; 0 for a sound the table does not list.
static func level_db(sound: StringName) -> float:
	return LEVEL_DB.get(sound, 0.0)
