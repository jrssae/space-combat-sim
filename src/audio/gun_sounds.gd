class_name GunSounds
extends RefCounted
## Which shot a gun plays (M10-T87, Q82): every bolt gun shares the Starfury's shot, pitched down and lengthened for the bigger
## ones (`sfx_gun.WEAPONS`, approved by the maintainer). Particle cannons and the other beams, missiles and interceptors keep
## their own sounds, so they get none here. Pure: read by `AudioDirector`.

## A capital's bolt guns by their weapon kind in the loadouts (`CapitalData.weapon_kind`).
const BY_KIND: Dictionary[String, StringName] = {
	"bolt_light": &"gun_light",
	"bolt_medium": &"gun_medium",
	"bolt_fixed": &"gun_medium",
	"bolt_heavy": &"gun_heavy",
	"fighter_gun": &"pulse_fire",
}
## Weapons that sound unlike their kind.
const BY_WEAPON: Dictionary[String, StringName] = {"ea_railgun": &"gun_railgun"}
## How much louder a bigger gun plays, dB on top of its `SoundMix` level (the station grid's heavy cannon's +6 the top).
const VOLUME_DB: Dictionary[StringName, float] = {&"gun_light": 1.0, &"gun_medium": 3.0, &"gun_railgun": 3.0, &"gun_heavy": 6.0}
## Every shot plays a little off its pitch, so a burst does not drone.
const PITCH_JITTER: float = 0.04


## The shot weapon `id` plays; &"" for one that keeps a sound of its own or has none.
static func of_weapon(id: String) -> StringName:
	if BY_WEAPON.has(id):
		return BY_WEAPON[id]
	return BY_KIND.get(CapitalData.weapon_kind(id), &"")


static func volume_db(sound: StringName) -> float:
	return VOLUME_DB.get(sound, 0.0)


## A shot's pitch: 1 give or take `PITCH_JITTER`.
static func jitter() -> float:
	return randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
