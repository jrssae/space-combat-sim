extends GutTest
## The `AiPilot` facade's gate to the native brains (M4-T17 fix round 1): a pilot goes native only when every behaviour is
## one the native slot rebuilds the same way (the default construction: the pilot's seed and labels, the profile's numbers).
## A behaviour built with its own seed or numbers keeps the GDScript path, since the native slot could not roll the same.
## Pure GDScript; no library needed.

var profile: AiProfile


func before_each() -> void:
	profile = AiProfile.new()
	profile.tactics = load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	profile.idle_hold = true


func test_the_default_pilot_is_native_capable() -> void:
	var pilot := AiPilot.new(profile, 7)
	assert_true(pilot.native_capable(), "the standard set, built by the pilot")
	pilot.add_behaviour(BehaviourFormation.new(pilot.profile))
	pilot.add_behaviour(BehaviourRally.new(pilot.profile))
	BehaviourGuard.attach(pilot, UniversePos.new(1.0, 2.0, 3.0))
	BehaviourFollowPath.attach(pilot, Route.new())
	assert_true(pilot.native_capable(), "the wing's, the guard's and the route's behaviours as the game adds them")


func test_a_behaviour_built_with_its_own_seed_or_numbers_keeps_the_gdscript_path() -> void:
	var custom_seed := AiPilot.new(profile, 7, [BehaviourRam.new(hash([7, "ram"])), BehaviourRetreat.new(profile),
			BehaviourEvade.new(hash([7, "evade"])), BehaviourAttack.new(profile, 42), BehaviourIdle.new(true)] as Array[AiBehaviour])
	assert_false(custom_seed.native_capable(), "an attack seeded by hand")
	var other_hold := AiPilot.new(profile, 7, [BehaviourRam.new(hash([7, "ram"])), BehaviourRetreat.new(profile),
			BehaviourEvade.new(hash([7, "evade"])), BehaviourAttack.new(profile, hash([7, "attack"])), BehaviourIdle.new(false)] as Array[AiBehaviour])
	assert_false(other_hold.native_capable(), "an idle that coasts where the profile holds")
	var as_built := AiPilot.new(profile, 7, [BehaviourRam.new(hash([7, "ram"])), BehaviourRetreat.new(profile),
			BehaviourEvade.new(hash([7, "evade"])), BehaviourAttack.new(profile, hash([7, "attack"])), BehaviourIdle.new(true)] as Array[AiBehaviour])
	assert_true(as_built.native_capable(), "the same construction by hand is the default one")
	var other_cruise := AiPilot.new(profile, 7)
	var guard := BehaviourGuard.new()
	guard.cruise_mps = profile.cruise_mps + 1.0
	other_cruise.add_behaviour(guard)
	assert_false(other_cruise.native_capable(), "a guard with its own cruise speed")


func test_a_scripted_behaviour_keeps_the_gdscript_path() -> void:
	var pilot := AiPilot.new(profile, 7)
	var scripted := AiBehaviour.new()
	scripted.id = &"attack"
	pilot.add_behaviour(scripted)
	assert_false(pilot.native_capable(), "a plain AiBehaviour under a known id")
