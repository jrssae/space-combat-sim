extends GutTest
## DebugFlags (architecture §6.4): session-only cheats, all off at start, never persisted.

var flags: DebugFlags


func before_each() -> void:
	flags = DebugFlags.new()


func test_everything_starts_off() -> void:
	for flag: StringName in flags.names():
		assert_false(flags.get_flag(flag), String(flag))
	assert_false(flags.invulnerable)
	assert_eq(Array(flags.names()), [&"invulnerable"])


func test_setting_a_flag_emits_once() -> void:
	watch_signals(flags)
	flags.invulnerable = true
	flags.invulnerable = true
	assert_true(flags.invulnerable)
	assert_signal_emit_count(flags, "changed", 1, "no signal when the value does not change")
	assert_signal_emitted_with_parameters(flags, "changed", [&"invulnerable", true])


func test_set_flag_by_name() -> void:
	assert_true(flags.set_flag(&"invulnerable", true))
	assert_true(flags.get_flag(&"invulnerable"))
	assert_false(flags.set_flag(&"noclip", true), "unknown flags are refused")
	assert_false(flags.has_flag(&"noclip"))
	assert_false(flags.get_flag(&"noclip"))


func test_reset_turns_everything_off() -> void:
	flags.invulnerable = true
	flags.reset()
	assert_false(flags.invulnerable)


func test_flags_have_no_persistence() -> void:
	# The point of DebugFlags: it is plain session state. No save/load API exists, and it is not a settings key.
	assert_false(flags.has_method("save"))
	assert_false(flags.has_method("load_file"))
	assert_false(SettingsSchema.new().has_key(&"invulnerable"))
